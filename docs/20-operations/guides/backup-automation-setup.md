# Backup Automation Setup Guide

**Date:** 2025-11-12
**Purpose:** Enable automated daily BTRFS snapshots via systemd timer
**Status:** ✅ Timer files created, awaiting activation

---

## Overview

The backup system uses a comprehensive BTRFS snapshot script with systemd timer automation:

- **Script:** `scripts/btrfs-snapshot-backup.sh`
- **Service:** `~/.config/systemd/user/btrfs-snapshot-backup.service`
- **Timer:** `~/.config/systemd/user/btrfs-snapshot-backup.timer`

**Schedule:**
- Daily local snapshots at **02:00 AM**
- Tier 1 (critical): home, opptak, containers
- Tier 2 (important): docs, root (monthly only)
- Tier 3 (standard): pics (weekly only)

---

## Activation Steps

### Step 1: Make Script Executable

```bash
chmod +x ~/fedora-homelab-containers/scripts/btrfs-snapshot-backup.sh
```

### Step 2: Test Script Manually (Dry Run)

```bash
cd ~/fedora-homelab-containers
./scripts/btrfs-snapshot-backup.sh --dry-run --local-only
```

**Expected output:**
- Shows what snapshots would be created
- Lists cleanup actions
- No actual changes made

### Step 3: Test Script for Real (Local Only)

```bash
./scripts/btrfs-snapshot-backup.sh --local-only --verbose
```

**This will:**
- Create local snapshots in `~/.snapshots` and `/mnt/btrfs-pool/.snapshots`
- Apply retention policies (cleanup old snapshots)
- Log to `~/containers/data/backup-logs/backup-YYYYMM.log`

**Check results:**
```bash
# Verify snapshots created
ls -la ~/.snapshots/htpc-home/
ls -la /mnt/btrfs-pool/.snapshots/subvol7-containers/

# Check logs
tail -50 ~/containers/data/backup-logs/backup-$(date +%Y%m).log
```

### Step 4: Reload Systemd User Daemon

```bash
systemctl --user daemon-reload
```

### Step 5: Enable and Start Timer

```bash
# Enable timer (start automatically on boot)
systemctl --user enable btrfs-snapshot-backup.timer

# Start timer immediately
systemctl --user start btrfs-snapshot-backup.timer
```

### Step 6: Verify Timer is Active

```bash
# Check timer status
systemctl --user status btrfs-snapshot-backup.timer

# List all timers
systemctl --user list-timers
```

**Expected output:**
```
NEXT                          LEFT          LAST  PASSED  UNIT
Wed 2025-11-13 02:00:00 CET   Xh Xmin left  n/a   n/a     btrfs-snapshot-backup.timer
```

### Step 7: Test Manual Trigger (Optional)

```bash
# Trigger service immediately (without waiting for 02:00 AM)
systemctl --user start btrfs-snapshot-backup.service

# Watch logs in real-time
journalctl --user -u btrfs-snapshot-backup.service -f
```

---

## Verification Checklist

After activation, verify the system is working:

- [ ] Script is executable (`chmod +x`)
- [ ] Dry run completes without errors
- [ ] Real run creates snapshots successfully
- [ ] Timer is enabled (`systemctl --user is-enabled btrfs-snapshot-backup.timer` returns `enabled`)
- [ ] Timer is active (`systemctl --user is-active btrfs-snapshot-backup.timer` returns `active`)
- [ ] Next run is scheduled (`systemctl --user list-timers` shows future run)
- [ ] Logs are being written to `~/containers/data/backup-logs/`
- [ ] Snapshots exist in `~/.snapshots/` and `/mnt/btrfs-pool/.snapshots/`

---

## Monitoring

### Check Last Run Status

```bash
# View service status
systemctl --user status btrfs-snapshot-backup.service

# View recent logs
journalctl --user -u btrfs-snapshot-backup.service -n 100

# View logs from last run
journalctl --user -u btrfs-snapshot-backup.service --since "02:00" --until "03:00"
```

### View Backup Logs

```bash
# Current month's log
tail -100 ~/containers/data/backup-logs/backup-$(date +%Y%m).log

# Follow logs in real-time (during manual run)
tail -f ~/containers/data/backup-logs/backup-$(date +%Y%m).log
```

### List Snapshots

```bash
# Tier 1: Containers (most important for Vaultwarden)
ls -lah /mnt/btrfs-pool/.snapshots/subvol7-containers/

# Tier 1: Home
ls -lah ~/.snapshots/htpc-home/

# Tier 1: Opptak
ls -lah /mnt/btrfs-pool/.snapshots/subvol3-opptak/

# All snapshots with sizes
sudo btrfs subvolume list /
sudo btrfs subvolume list /mnt/btrfs-pool
```

---

## Troubleshooting

### Timer Not Running

**Check if timer is loaded:**
```bash
systemctl --user list-unit-files | grep btrfs
```

**Reload if needed:**
```bash
systemctl --user daemon-reload
systemctl --user restart btrfs-snapshot-backup.timer
```

### Snapshots Not Created

**Check for sudo permission issues:**
```bash
# Test sudo access for btrfs commands
sudo btrfs subvolume list /
```

If password prompt appears, you may need to configure passwordless sudo for btrfs commands.

**Check disk space:**
```bash
df -h /
df -h /mnt/btrfs-pool
```

If system SSD is >80% full, snapshots may fail.

### External Backup Not Running

The service is configured with `--local-only` flag (external drive not required).

To enable external backups (weekly on Sundays):
1. Edit `~/.config/systemd/user/btrfs-snapshot-backup.service`
2. Remove `--local-only` flag from `ExecStart` line
3. Ensure external drive is mounted at `/run/media/patriark/WD-18TB/`
4. Reload: `systemctl --user daemon-reload`
5. Restart timer: `systemctl --user restart btrfs-snapshot-backup.timer`

---

## Configuration

### Change Backup Schedule

Edit the timer file:
```bash
nano ~/.config/systemd/user/btrfs-snapshot-backup.timer
```

**Common schedules:**
- `OnCalendar=daily` - Every day at midnight
- `OnCalendar=*-*-* 02:00:00` - Every day at 02:00 AM
- `OnCalendar=*-*-* 04:00:00` - Every day at 04:00 AM
- `OnCalendar=Sun *-*-* 03:00:00` - Every Sunday at 03:00 AM

After changes:
```bash
systemctl --user daemon-reload
systemctl --user restart btrfs-snapshot-backup.timer
```

### Change Retention Policies

Edit the script directly:
```bash
nano ~/fedora-homelab-containers/scripts/btrfs-snapshot-backup.sh
```

Look for retention variables (lines 69-91):
- `TIER1_CONTAINERS_LOCAL_RETENTION_DAILY=7` (keep 7 daily local snapshots)
- `TIER1_CONTAINERS_EXTERNAL_RETENTION_WEEKLY=4` (keep 4 weekly external snapshots)

---

## Restoration Process

### Restore a Single File

```bash
# Find the snapshot
ls /mnt/btrfs-pool/.snapshots/subvol7-containers/

# Navigate to snapshot
cd /mnt/btrfs-pool/.snapshots/subvol7-containers/20251112-containers/

# Find your file
find . -name "vaultwarden_db.sqlite3"

# Copy file back to original location
sudo cp path/to/file /mnt/btrfs-pool/subvol7-containers/vaultwarden/
```

### Restore Entire Subvolume

```bash
# 1. Stop affected services
systemctl --user stop vaultwarden.service

# 2. Rename current subvolume (as backup)
sudo mv /mnt/btrfs-pool/subvol7-containers /mnt/btrfs-pool/subvol7-containers.old

# 3. Create read-write snapshot from backup
sudo btrfs subvolume snapshot \
  /mnt/btrfs-pool/.snapshots/subvol7-containers/20251112-containers \
  /mnt/btrfs-pool/subvol7-containers

# 4. Restart services
systemctl --user start vaultwarden.service

# 5. Verify restoration successful, then delete old subvolume
sudo btrfs subvolume delete /mnt/btrfs-pool/subvol7-containers.old
```

---

## Integration with Monitoring

### Add Prometheus Alert for Backup Failures

Add to `~/containers/config/prometheus/alerts/backup.yml`:

```yaml
groups:
  - name: backup_alerts
    interval: 5m
    rules:
      - alert: BackupServiceFailed
        expr: systemd_unit_state{name="btrfs-snapshot-backup.service",state="failed"} == 1
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "BTRFS backup service failed"
          description: "The daily BTRFS snapshot backup has failed. Check logs with: journalctl --user -u btrfs-snapshot-backup.service"

      - alert: BackupNotRunRecently
        expr: time() - systemd_unit_start_time_seconds{name="btrfs-snapshot-backup.service"} > 86400*2
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "Backup hasn't run in 2 days"
          description: "BTRFS snapshots haven't been created in over 48 hours. Check timer status."
```

### Add Grafana Dashboard Panel

Create panel showing:
- Last successful backup timestamp
- Backup duration
- Number of snapshots created
- Snapshot disk usage

---

## Security Considerations

**Snapshots are NOT encryption:**
- Snapshots preserve the exact state (including permissions and SELinux contexts)
- If source data is encrypted, snapshots are too
- If source is unencrypted, snapshots are unencrypted

**For Vaultwarden:**
- Vaultwarden database is encrypted at rest (master password + encryption keys)
- BTRFS snapshots preserve this encryption
- Snapshots are stored locally (same physical security as live data)

**External backup security:**
- External drive should be encrypted (LUKS)
- Keep external drive disconnected when not backing up
- Store off-site for disaster recovery

---

## Next Steps

1. **Immediate:** Enable timer and verify first run
2. **Week 1:** Monitor daily backups for consistency
3. **Week 2:** Test restoration process (practice makes perfect!)
4. **Month 1:** Review retention policies based on disk usage
5. **Ongoing:** Monitor backup metrics in Grafana

---

## Related Documentation

- **Backup Strategy:** `docs/20-operations/guides/backup-strategy.md`
- **Storage Layout:** `docs/20-operations/guides/storage-layout.md`
- **BTRFS Script:** `scripts/btrfs-snapshot-backup.sh`
