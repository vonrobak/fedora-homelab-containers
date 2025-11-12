# BTRFS Backup Strategy Guide

**Created:** 2025-11-07
**System:** fedora-htpc
**Storage:** 128GB NVMe (system) + BTRFS multi-device pool + 18TB external (LUKS)

---

## Overview

This guide documents the automated BTRFS snapshot and backup strategy, optimized for:
- **Minimal local storage** (128GB NVMe constraint)
- **Weekly external backups** (daily backups cause too much system load)
- **Risk tolerance** (can accept data loss between weekly backups)
- **Easy parameter adjustment** as needs change

---

## Quick Reference

### Backup Script Location
```bash
~/containers/scripts/btrfs-snapshot-backup.sh
```

### Log Location
```bash
~/containers/data/backup-logs/backup-$(date +%Y%m).log
```

### External Backup Location
```bash
/run/media/patriark/WD-18TB/.snapshots/
```

### Current Schedule

| Tier | Subvolume | Local Frequency | Local Retention | External Frequency | External Retention |
|------|-----------|-----------------|-----------------|-------------------|-------------------|
| 1 | htpc-home | Daily (02:00) | 7 days | Weekly (Sunday 03:00) | 8 weekly + 12 monthly |
| 1 | subvol3-opptak | Daily (02:00) | 7 days | Weekly (Sunday 03:00) | 8 weekly + 12 monthly |
| 1 | subvol7-containers | Daily (02:00) | 7 days | Weekly (Sunday 03:00) | 4 weekly + 6 monthly |
| 2 | subvol1-docs | Daily (02:00) | 7 days | Weekly (Sunday 03:00) | 8 weekly + 6 monthly |
| 2 | htpc-root | Monthly (1st, 04:00) | 1 month | Monthly | 6 monthly |
| 3 | subvol2-pics | Weekly (Sunday 02:00) | 4 weeks | Monthly (1st Sunday) | 12 monthly |

---

## How to Adjust Backup Parameters

### 1. Changing Local Retention (Free Up NVMe Space)

**Problem:** Running low on NVMe storage, need to keep fewer local snapshots.

**Solution:** Edit the `*_LOCAL_RETENTION_*` variables in the script:

```bash
nano ~/containers/scripts/btrfs-snapshot-backup.sh
```

Find the configuration section (lines 34-150) and adjust:

```bash
# Example: Reduce htpc-home local retention from 7 to 3 days
TIER1_HOME_LOCAL_RETENTION_DAILY=3  # Changed from 7

# Example: Reduce subvol3-opptak local retention
TIER1_OPPTAK_LOCAL_RETENTION_DAILY=3  # Changed from 7

# Example: Keep fewer weekly snapshots for subvol2-pics
TIER3_PICS_LOCAL_RETENTION_WEEKLY=2  # Changed from 4
```

**Impact:** Less disk space used locally, but larger gap between snapshots if external drive fails.

---

### 2. Changing External Retention (Free Up Backup Drive Space)

**Problem:** External drive filling up, need to keep fewer old backups.

**Solution:** Adjust `*_EXTERNAL_RETENTION_*` variables:

```bash
# Example: Keep fewer weekly backups of containers
TIER1_CONTAINERS_EXTERNAL_RETENTION_WEEKLY=2  # Changed from 4
TIER1_CONTAINERS_EXTERNAL_RETENTION_MONTHLY=3  # Changed from 6

# Example: Keep fewer monthly backups of pics
TIER3_PICS_EXTERNAL_RETENTION_MONTHLY=6  # Changed from 12
```

**Impact:** Shorter backup history, less recovery flexibility.

---

### 3. Disabling Backups for Specific Subvolumes

**Problem:** Don't need to back up a subvolume anymore (e.g., subvol2-pics if you decide it's not worth backing up).

**Solution:** Set the `*_ENABLED` variable to `false`:

```bash
# Example: Disable subvol2-pics backups entirely
TIER3_PICS_ENABLED=false  # Changed from true

# Example: Disable subvol1-docs if using Nextcloud sync instead
TIER2_DOCS_ENABLED=false
```

**Impact:** No backups created for that subvolume. Use with caution!

---

### 4. Changing Backup Frequency

**Problem:** Want to back up critical data more often (or less often).

**Current Limitation:** Script runs daily and checks day-of-week/day-of-month internally.

**To increase frequency (e.g., daily external backups):**

```bash
# In backup_tier1_home() function (around line 280)
# Remove the Sunday check:

# BEFORE:
if [[ $(date +%u) -eq 7 ]]; then  # Sunday
    check_external_mounted || return 1
    ...
fi

# AFTER (backs up externally every day):
check_external_mounted || return 1
...
```

**Warning:** Daily external backups increase system load and may wear out external drive faster.

**To decrease frequency (e.g., monthly instead of weekly):**

```bash
# Change the day check:
if [[ $(date +%d) -eq 01 ]]; then  # 1st of month
    check_external_mounted || return 1
    ...
fi
```

---

### 5. Adding a New Subvolume to Backup

**Problem:** Created a new subvolume (e.g., `subvol8-projects`) and want to back it up.

**Solution:** Add a new configuration block:

```bash
# Add to appropriate tier (e.g., Tier 2 for important but not critical)

# subvol8-projects (new projects folder)
TIER2_PROJECTS_ENABLED=true
TIER2_PROJECTS_SOURCE="/mnt/btrfs-pool/subvol8-projects"
TIER2_PROJECTS_LOCAL_DIR="$LOCAL_POOL_SNAPSHOTS/subvol8-projects"
TIER2_PROJECTS_EXTERNAL_DIR="$EXTERNAL_BACKUP_ROOT/subvol8-projects"
TIER2_PROJECTS_LOCAL_RETENTION_DAILY=7
TIER2_PROJECTS_EXTERNAL_RETENTION_WEEKLY=8
TIER2_PROJECTS_EXTERNAL_RETENTION_MONTHLY=6
TIER2_PROJECTS_SCHEDULE="daily"
```

Then create a corresponding backup function (copy and modify an existing one):

```bash
backup_tier2_projects() {
    log INFO "=== Processing Tier 2: subvol8-projects ==="

    if [[ "$TIER2_PROJECTS_ENABLED" != "true" ]]; then
        log INFO "subvol8-projects backup disabled, skipping"
        return 0
    fi

    local snapshot_name="${DATE_DAILY}-projects"
    local local_snapshot="$TIER2_PROJECTS_LOCAL_DIR/$snapshot_name"

    # Create local snapshot
    if [[ "$EXTERNAL_ONLY" != "true" ]]; then
        create_snapshot "$TIER2_PROJECTS_SOURCE" "$local_snapshot"
    fi

    # Send to external (weekly)
    if [[ "$LOCAL_ONLY" != "true" ]] && [[ $(date +%u) -eq 7 ]]; then
        check_external_mounted || return 1

        local parent=$(get_latest_snapshot "$TIER2_PROJECTS_EXTERNAL_DIR" "*-projects")
        send_snapshot_incremental "$parent" "$local_snapshot" "$TIER2_PROJECTS_EXTERNAL_DIR"

        cleanup_old_snapshots "$TIER2_PROJECTS_EXTERNAL_DIR" "$TIER2_PROJECTS_EXTERNAL_RETENTION_WEEKLY" "*-projects"
    fi

    # Cleanup local snapshots
    cleanup_old_snapshots "$TIER2_PROJECTS_LOCAL_DIR" "$TIER2_PROJECTS_LOCAL_RETENTION_DAILY" "*-projects"

    log SUCCESS "Completed Tier 2: subvol8-projects"
}
```

Finally, call it in the `main()` function:

```bash
if [[ -z "$TIER_FILTER" ]] || [[ "$TIER_FILTER" == "2" ]]; then
    ...
    if [[ -z "$SUBVOL_FILTER" ]] || [[ "$SUBVOL_FILTER" == "projects" ]]; then
        backup_tier2_projects
    fi
fi
```

---

### 6. Changing Snapshot Naming Convention

**Problem:** Want different snapshot names (e.g., add hostname or more descriptive names).

**Solution:** Modify the `snapshot_name` variable in each backup function:

```bash
# BEFORE:
local snapshot_name="${DATE_DAILY}-htpc-home"

# AFTER (add more context):
local snapshot_name="${DATE_DAILY}-$(hostname)-home-auto"

# OR (add description):
local snapshot_name="${DATE_DAILY}-htpc-home-automated"
```

**Pattern matching for cleanup:**
Make sure to update the cleanup pattern to match:

```bash
cleanup_old_snapshots "$TIER1_HOME_LOCAL_DIR" "$TIER1_HOME_LOCAL_RETENTION_DAILY" "*-home-auto"
```

---

## Usage Examples

### 1. Test Run (Dry Run)

See what would happen without actually executing:

```bash
~/containers/scripts/btrfs-snapshot-backup.sh --dry-run --verbose
```

### 2. Create Local Snapshots Only

Skip external backup (e.g., external drive not connected):

```bash
~/containers/scripts/btrfs-snapshot-backup.sh --local-only
```

### 3. Send Existing Snapshots to External

Don't create new local snapshots, just send existing ones:

```bash
~/containers/scripts/btrfs-snapshot-backup.sh --external-only
```

### 4. Backup Specific Tier Only

```bash
# Only Tier 1 (critical)
~/containers/scripts/btrfs-snapshot-backup.sh --tier 1

# Only Tier 2 (important)
~/containers/scripts/btrfs-snapshot-backup.sh --tier 2
```

### 5. Backup Specific Subvolume

```bash
# Only backup /home
~/containers/scripts/btrfs-snapshot-backup.sh --subvolume home

# Only backup subvol3-opptak
~/containers/scripts/btrfs-snapshot-backup.sh --subvolume opptak
```

### 6. Manual Backup Before Major Change

```bash
# Before system upgrade or major config change
~/containers/scripts/btrfs-snapshot-backup.sh --verbose

# Or create manual snapshot with descriptive name:
sudo btrfs subvolume snapshot -r /home ~/.snapshots/htpc-home/$(date +%Y%m%d)-pre-upgrade
```

---

## Automation Setup (Systemd Timers)

### Prerequisites: Passwordless Sudo for BTRFS Commands

**Required for automated backups via systemd user services.**

The backup script uses `sudo` for BTRFS operations (snapshot, send, receive, delete). Since systemd user services cannot provide interactive password prompts, you must configure passwordless sudo for specific BTRFS commands.

**Create sudoers file:**

```bash
sudo visudo -f /etc/sudoers.d/btrfs-backup
```

**Add the following rules:**

```
# BTRFS Backup Automation - Passwordless sudo for specific commands
# Created: 2025-11-12
# Purpose: Allow automated BTRFS snapshot backups via systemd user services
#
# Security: Only specific BTRFS commands allowed, no wildcards in command paths

patriark ALL=(root) NOPASSWD: /usr/sbin/btrfs subvolume snapshot *
patriark ALL=(root) NOPASSWD: /usr/sbin/btrfs subvolume delete *
patriark ALL=(root) NOPASSWD: /usr/sbin/btrfs send *
patriark ALL=(root) NOPASSWD: /usr/sbin/btrfs receive *
```

**Set correct permissions:**

```bash
sudo chmod 0440 /etc/sudoers.d/btrfs-backup
```

**Verify syntax:**

```bash
sudo visudo -c
# Should output: /etc/sudoers: parsed OK
```

**Security notes:**
- ✅ Only specific BTRFS subcommands are allowed (snapshot, delete, send, receive)
- ✅ Command path is absolute (`/usr/sbin/btrfs`), preventing PATH manipulation
- ✅ Wildcards only in arguments, not in command path
- ✅ File permissions (0440) prevent unauthorized modification
- ⚠️ User can create/delete any BTRFS snapshot - acceptable for single-user homelab

**Test the configuration:**

```bash
# This should work without password prompt:
sudo -n btrfs subvolume list / | head -5

# Run backup script manually to verify:
~/containers/scripts/btrfs-snapshot-backup.sh --local-only --verbose
```

---

### Daily Backup Timer

Create systemd timer for daily local snapshots:

```bash
nano ~/.config/systemd/user/btrfs-backup-daily.timer
```

```ini
[Unit]
Description=Daily BTRFS Snapshot Timer
Requires=btrfs-backup-daily.service

[Timer]
OnCalendar=daily
Persistent=true
OnBootSec=10min

[Install]
WantedBy=timers.target
```

Create corresponding service:

```bash
nano ~/.config/systemd/user/btrfs-backup-daily.service
```

```ini
[Unit]
Description=Daily BTRFS Snapshot Creation
After=network-online.target

[Service]
Type=oneshot
ExecStart=%h/containers/scripts/btrfs-snapshot-backup.sh --local-only
StandardOutput=journal
StandardError=journal
```

Enable and start:

```bash
systemctl --user daemon-reload
systemctl --user enable --now btrfs-backup-daily.timer
systemctl --user list-timers
```

### Weekly External Backup Timer

```bash
nano ~/.config/systemd/user/btrfs-backup-weekly.timer
```

```ini
[Unit]
Description=Weekly BTRFS External Backup Timer
Requires=btrfs-backup-weekly.service

[Timer]
OnCalendar=Sun 03:00
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
nano ~/.config/systemd/user/btrfs-backup-weekly.service
```

```ini
[Unit]
Description=Weekly BTRFS External Backup
After=network-online.target

[Service]
Type=oneshot
ExecStart=%h/containers/scripts/btrfs-snapshot-backup.sh
StandardOutput=journal
StandardError=journal
TimeoutStartSec=6h
```

Enable:

```bash
systemctl --user enable --now btrfs-backup-weekly.timer
```

---

## Monitoring Backups

### Check Last Backup Status

```bash
# View last backup log
tail -50 ~/containers/data/backup-logs/backup-$(date +%Y%m).log

# Check for errors
grep ERROR ~/containers/data/backup-logs/backup-$(date +%Y%m).log

# Check for successes
grep SUCCESS ~/containers/data/backup-logs/backup-$(date +%Y%m).log
```

### Check Snapshot Inventory

```bash
# Local snapshots
ls -lh ~/.snapshots/htpc-home/
ls -lh /mnt/btrfs-pool/.snapshots/subvol3-opptak/

# External snapshots
ls -lh /run/media/patriark/WD-18TB/.snapshots/htpc-home/
ls -lh /run/media/patriark/WD-18TB/.snapshots/subvol3-opptak/
```

### Check Disk Space Usage

```bash
# Local NVMe space
df -h /home
sudo btrfs filesystem usage /

# External drive space
df -h /run/media/patriark/WD-18TB
sudo btrfs filesystem usage /run/media/patriark/WD-18TB
```

### Add Prometheus Monitoring (Future)

Consider adding metrics for:
- Last successful backup timestamp
- Snapshot count per subvolume
- Backup script duration
- Disk space used by snapshots

---

## Recovery Procedures

### Restore File from Snapshot

```bash
# List available snapshots
ls ~/.snapshots/htpc-home/

# Browse snapshot contents
ls ~/.snapshots/htpc-home/20251107-htpc-home/containers/config/

# Copy file from snapshot
cp ~/.snapshots/htpc-home/20251107-htpc-home/containers/config/traefik/traefik.yml ~/containers/config/traefik/traefik.yml.restored
```

### Restore Entire Subvolume

```bash
# 1. Rename current subvolume
sudo mv /home /home.broken

# 2. Restore from snapshot (creates writable copy)
sudo btrfs subvolume snapshot ~/.snapshots/htpc-home/20251107-htpc-home /home

# 3. Reboot
sudo systemctl reboot
```

### Restore from External Drive

```bash
# 1. Mount external drive
# (usually auto-mounted at /run/media/patriark/WD-18TB)

# 2. List available snapshots
ls /run/media/patriark/WD-18TB/.snapshots/htpc-home/

# 3. Send snapshot back to system
sudo btrfs send /run/media/patriark/WD-18TB/.snapshots/htpc-home/20251101-htpc-home | sudo btrfs receive ~/.snapshots/htpc-home/

# 4. Restore from that snapshot
sudo btrfs subvolume snapshot ~/.snapshots/htpc-home/20251101-htpc-home /home
```

---

## Troubleshooting

### Problem: Backup service fails with "sudo: a password is required"

**Symptom:**
```bash
systemctl --user status btrfs-backup-daily.service
# Shows: Active: failed (Result: exit-code)

journalctl --user -u btrfs-backup-daily.service
# Shows: sudo: a terminal is required to read the password
```

**Cause:** The backup script uses `sudo` for BTRFS operations, but systemd user services cannot provide interactive password prompts.

**Solution:** Configure passwordless sudo for BTRFS commands (see "Automation Setup" section above).

**Quick fix:**
```bash
# 1. Create sudoers file
sudo bash -c 'cat > /etc/sudoers.d/btrfs-backup << EOF
patriark ALL=(root) NOPASSWD: /usr/sbin/btrfs subvolume snapshot *
patriark ALL=(root) NOPASSWD: /usr/sbin/btrfs subvolume delete *
patriark ALL=(root) NOPASSWD: /usr/sbin/btrfs send *
patriark ALL=(root) NOPASSWD: /usr/sbin/btrfs receive *
EOF'

# 2. Set permissions
sudo chmod 0440 /etc/sudoers.d/btrfs-backup

# 3. Verify syntax
sudo visudo -c

# 4. Test manually
~/containers/scripts/btrfs-snapshot-backup.sh --local-only --verbose

# 5. Test via systemd
systemctl --user start btrfs-backup-daily.service
systemctl --user status btrfs-backup-daily.service
```

**Verification:**
- ✅ Service status shows `status=0/SUCCESS`
- ✅ Logs show "BTRFS Snapshot & Backup Script Completed"
- ✅ New snapshots appear in `~/.snapshots/` directories
- ✅ No sudo password prompts in logs

---

### Problem: "No space left on device" when creating snapshot

**Cause:** NVMe full or BTRFS metadata full.

**Solution:**

```bash
# Check actual usage
df -h /
sudo btrfs filesystem usage /

# Free up space
sudo btrfs balance start -dusage=10 /
sudo btrfs balance start -musage=10 /

# Delete old snapshots manually
sudo btrfs subvolume delete ~/.snapshots/htpc-home/20251101-htpc-home

# Adjust retention in script to keep fewer local snapshots
```

### Problem: External backup fails with "parent snapshot not found"

**Cause:** Parent snapshot was deleted from external drive.

**Solution:** Send a full snapshot (not incremental):

```bash
# Send full snapshot (will be slow)
sudo btrfs send ~/.snapshots/htpc-home/20251107-htpc-home | sudo btrfs receive /run/media/patriark/WD-18TB/.snapshots/htpc-home/
```

### Problem: Script hangs during external backup

**Cause:** External drive disconnected or very slow.

**Solution:**

```bash
# Check if drive is mounted
mountpoint /run/media/patriark/WD-18TB

# Check drive health
sudo smartctl -H /dev/sdX

# Check dmesg for USB errors
sudo dmesg | tail -50

# Kill stuck btrfs operation
sudo pkill -9 btrfs

# Remount drive
sudo umount /run/media/patriark/WD-18TB
sudo mount /dev/mapper/WD-18TB /run/media/patriark/WD-18TB
```

### Problem: Snapshot cleanup not working

**Cause:** Pattern mismatch in cleanup function.

**Solution:**

```bash
# Test pattern matching manually
find ~/.snapshots/htpc-home/ -maxdepth 1 -type d -name "*-htpc-home"

# If no results, check actual snapshot names
ls ~/.snapshots/htpc-home/

# Adjust pattern in script to match actual names
```

---

## Best Practices

1. **Test restores periodically** - Backups are useless if you can't restore
2. **Monitor external drive health** - Run `smartctl -H` monthly
3. **Keep external drive disconnected** when not backing up (protection against ransomware)
4. **Document manual snapshots** - Use descriptive names like `20251107-pre-upgrade`
5. **Review logs monthly** - Check for backup failures
6. **Verify snapshot sizes** - Large unexpected growth may indicate issues
7. **Test dry-run before changes** - Always use `--dry-run` when testing script modifications

---

## Parameter Quick Reference

### Common Adjustments

```bash
# Make NVMe last longer (reduce local snapshots)
TIER1_HOME_LOCAL_RETENTION_DAILY=3      # Instead of 7
TIER1_OPPTAK_LOCAL_RETENTION_DAILY=3    # Instead of 7

# Free up external drive space (reduce retention)
TIER1_HOME_EXTERNAL_RETENTION_WEEKLY=4  # Instead of 8
TIER1_HOME_EXTERNAL_RETENTION_MONTHLY=6 # Instead of 12

# Disable non-critical backups
TIER3_PICS_ENABLED=false
TIER2_DOCS_ENABLED=false  # If using Nextcloud sync

# Speed up backups (skip external)
~/containers/scripts/btrfs-snapshot-backup.sh --local-only
```

---

## Future Enhancements

Consider implementing:
1. **Compression during send** - Add `--compressed-data` flag to `btrfs send`
2. **Email notifications** - Send email on backup failure
3. **Prometheus metrics** - Track backup success/failure, snapshot counts
4. **Automatic external drive mounting** - Detect drive and mount automatically
5. **Off-site replication** - Add third backup destination (cloud or remote server)
6. **Deduplication tracking** - Monitor shared extents between snapshots

---

## Related Documentation

- Storage Architecture: `~/containers/docs/99-reports/20251025-storage-architecture-authoritative-rev2.md`
- Monitoring Stack: `~/containers/docs/monitoring-stack-guide.md`
- BTRFS Commands: Section 1.2-1.3 in storage architecture addendum

---

**Last Updated:** 2025-11-12 (Added passwordless sudo documentation and troubleshooting)
**Script Version:** 1.0
