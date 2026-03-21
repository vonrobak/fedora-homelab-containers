# BTRFS Backup Strategy Guide

**Created:** 2025-11-07
**Updated:** 2026-03-21 (ADR-020: daily external backups with incremental sends)
**System:** fedora-htpc
**Storage:** 128GB NVMe (system) + BTRFS multi-device pool (Single profile) + 2x 18TB external (LUKS)

---

## Overview

Automated BTRFS snapshot and incremental backup strategy, optimized for:
- **Daily external backups** for critical data (RPO ~1 day, down from 7 days)
- **Time Machine-style local retention** (14 daily + 6 weekly + 3 monthly = ~90 days coverage)
- **Offsite rotation** with dual incremental chains (quarterly drive swaps)
- **Minimal system load** — incremental sends transfer only changed extents (~minutes, not hours)

**Key architecture decision:** See ADR-020 for rationale.

---

## Quick Reference

### Script and Logs
```bash
~/containers/scripts/btrfs-snapshot-backup.sh     # Main backup script
~/containers/data/backup-logs/backup-$(date +%Y%m).log  # Monthly log files
~/containers/data/backup-metrics/backup.prom       # Prometheus metrics
```

### External Backup Drives
```bash
/run/media/patriark/WD-18TB/.snapshots/   # Primary (fstab, always connected)
/run/media/patriark/WD-18TB1/.snapshots/  # Offsite (udisks2, cycled ~quarterly)
```

### Current Schedule

**Single nightly timer at 02:00 AM** — the script determines per-subvolume what to do.

| Tier | Subvolume | Local Schedule | External Schedule | External Retention |
|------|-----------|---------------|-------------------|-------------------|
| 1 | htpc-home | Daily | Daily | 14 snapshots |
| 1 | subvol3-opptak | Daily | Daily | 14 snapshots |
| 1 | subvol7-containers | Daily | Daily | 14 snapshots |
| 2 | subvol1-docs | Daily | Daily | 14 snapshots |
| 2 | htpc-root | Monthly | Monthly | 6 snapshots |
| 3 | subvol2-pics | Weekly (Sat) | Monthly (1st) | 6 snapshots |
| 3 | subvol4-multimedia | Weekly (Sat) | Monthly (1st) | 3 snapshots |
| 3 | subvol5-music | Weekly (Sat) | Monthly (1st) | 6 snapshots |
| 3 | subvol6-tmp | Weekly (Sat) | Monthly (1st) | 3 snapshots |

### Local Retention (Graduated / Time Machine-style)

For daily-schedule subvolumes (Tier 1/2):
- **Last 14 days:** All snapshots kept
- **15-60 days:** 1 per ISO week
- **61-90 days:** 1 per month
- ~21 snapshots total, covering 3 months

For weekly-schedule subvolumes (Tier 3): simple count (4-8 snapshots).

---

## How It Works

### Incremental Sends

BTRFS `send -p` transfers only the delta between a parent snapshot and a new snapshot. The parent must exist on both the local system and the external drive. The script:

1. Calls `find_common_parent()` to find the most recent local snapshot that also exists on external
2. If found: incremental send (fast, minutes)
3. If not found: full send (slow, hours — happens on first sync or broken chain)

### Pinned Parent Mechanism

After a successful send, the script writes a `.last-external-parent-<DRIVE_LABEL>` file with the snapshot name. This "pinned parent" is never deleted by cleanup, even if it's older than the retention window. This prevents the incremental chain from breaking.

**Dual pin files:** Each external drive has its own pin file (e.g., `.last-external-parent-WD-18TB` and `.last-external-parent-WD-18TB1`). This supports offsite rotation — when the offsite drive returns after months, its pinned parent still exists locally (protected by graduated retention).

### Graceful Drive Absence

When no external drive is mounted, the script logs INFO and skips external sends without recording a failure. No Discord alerts fire. This is the expected state when the offsite drive is at the remote location.

---

## Automation (Systemd Timer)

**Single timer:** `btrfs-backup-daily.timer` at 02:00 AM nightly.

```bash
# Check timer status
systemctl --user list-timers | grep backup

# View last run logs
journalctl --user -u btrfs-backup-daily.service -n 50

# Manual run
~/containers/scripts/btrfs-snapshot-backup.sh --verbose
```

### Monitoring

- **Discord:** Failure-only notifications (red embed with failed subvolumes and reasons)
- **Prometheus:** `backup.prom` metrics scraped by node_exporter textfile collector
  - `backup_success{subvolume}` — 1 or 0
  - `backup_last_success_timestamp{subvolume}` — Unix timestamp
  - `backup_duration_seconds{subvolume}` — time taken
  - `backup_snapshot_count{subvolume,location}` — snapshot inventory
  - `backup_send_type{subvolume}` — 1=incremental, 0=full
  - `backup_external_drive_mounted` — 1 or 0
  - `backup_external_free_bytes` — external drive free space

---

## Offsite Rotation Guide

The offsite drive (WD-18TB1) is stored at a friend's location and cycled roughly quarterly.

### Rotation Procedure

1. **Bring offsite drive home** — mount it (udisks2 auto-mounts)
2. **Run full backup:** `~/containers/scripts/btrfs-snapshot-backup.sh --verbose`
   - Script auto-detects the mounted drive
   - Incremental send from the pinned parent (if still within 90-day graduated retention)
   - If no common parent: full send (slow, but correct)
3. **Verify sends completed** — check log output
4. **Take drive back to offsite location**
5. **Primary drive resumes daily** — next 02:00 run picks up WD-18TB automatically

### Constraints

- Offsite cycle must not exceed **~90 days** (graduated retention window)
- If exceeded: full sends required (slow, but data integrity maintained)
- Both drives maintain independent incremental chains

---

## Usage Examples

```bash
# Dry run (see what would happen)
~/containers/scripts/btrfs-snapshot-backup.sh --dry-run --verbose

# Local snapshots only (skip external sends)
~/containers/scripts/btrfs-snapshot-backup.sh --local-only

# External sends only (use existing local snapshots)
~/containers/scripts/btrfs-snapshot-backup.sh --external-only

# Specific tier
~/containers/scripts/btrfs-snapshot-backup.sh --tier 1

# Specific subvolume
~/containers/scripts/btrfs-snapshot-backup.sh --subvolume containers --verbose
```

---

## Recovery Procedures

### Restore File from Local Snapshot
```bash
ls ~/.snapshots/htpc-home/                          # List available snapshots
cp ~/.snapshots/htpc-home/20260321-htpc-home/path/to/file ~/restored-file
```

### Restore from External Drive
```bash
ls /run/media/patriark/WD-18TB/.snapshots/htpc-home/  # List external snapshots
sudo btrfs send /run/media/patriark/WD-18TB/.snapshots/htpc-home/20260321-htpc-home | \
    sudo btrfs receive ~/.snapshots/htpc-home/
sudo btrfs subvolume snapshot ~/.snapshots/htpc-home/20260321-htpc-home /home
```

### Restore Entire Subvolume from Local
```bash
sudo mv /home /home.broken
sudo btrfs subvolume snapshot ~/.snapshots/htpc-home/20260321-htpc-home /home
sudo systemctl reboot
```

---

## Troubleshooting

### Backup service fails with "sudo: a password is required"
Configure passwordless sudo for BTRFS commands — see `backup-automation-setup.md`.

### "No space left on device" when creating snapshot
```bash
df -h /home
sudo btrfs filesystem usage /
sudo btrfs balance start -dusage=10 /
```

### External backup fails with "no common parent"
The incremental chain is broken. Script will fall back to full send automatically. If space is insufficient for full send, it will abort with a clear error.

### Script hangs during external backup
```bash
sudo dmesg | tail -50              # Check for USB/disk errors
mountpoint /run/media/patriark/WD-18TB  # Verify mount
sudo smartctl -H /dev/sdX          # Check drive health
```

---

## Related Documentation

- **ADR-020:** Daily External Backups — `docs/00-foundation/decisions/2026-03-21-ADR-020-daily-external-backups.md`
- **Automation Setup:** `docs/20-operations/guides/backup-automation-setup.md`
- **Disaster Recovery:** `docs/20-operations/guides/disaster-recovery.md`
- **Storage Layout:** `docs/20-operations/guides/storage-layout.md`
- **Operational Excellence Journal:** `docs/98-journals/2026-03-21-backup-script-operational-excellence.md`

---

**Last Updated:** 2026-03-21 (ADR-020: daily external, graduated retention, dual pin files)
