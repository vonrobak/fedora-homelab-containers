# Disaster Recovery Framework

**Status:** Implemented (Phase 1 complete)
**Last Updated:** 2025-11-30
**Test Schedule:** Monthly (last Sunday, 11:00 AM)

---

## Overview

This homelab has a comprehensive backup and disaster recovery system with:

1. **Automated BTRFS Snapshots** - Daily/weekly/monthly snapshots of 6 subvolumes
2. **External Backups** - 18TB encrypted USB drive (weekly sync)
3. **Automated Restore Testing** - Monthly validation that backups are actually restorable
4. **Disaster Recovery Runbooks** - Step-by-step procedures for recovery scenarios

**Critical Achievement:** Backups are **tested monthly** - we know they work!

---

## Backup Coverage

### Tier 1: Critical (Daily Local + Weekly External)
- `htpc-home` - User home directory (~50GB)
- `subvol3-opptak` - Media library (~2TB)
- `subvol7-containers` - Container configs/data (~100GB)

### Tier 2: Important (Weekly/Monthly)
- `subvol1-docs` - Documents (~20GB)
- `htpc-root` - System root (monthly only, ~40GB)

### Tier 3: Standard (Weekly/Monthly)
- `subvol2-pics` - Photo library (~500GB)

**Retention Policies:**
- Local: 7 daily snapshots (space permitting)
- External: 4-8 weekly + 6-12 monthly snapshots

---

## Automated Restore Testing

**Script:** `~/containers/scripts/test-backup-restore.sh`
**Schedule:** Monthly (last Sunday at 11:00 AM)
**Method:** Restore random sample of 50 files per subvolume, validate integrity

### What Gets Tested

Each month, the automated test:
1. Selects latest snapshot (external preferred, local fallback)
2. Chooses 50 random files from each subvolume
3. Restores files to temporary location
4. Validates:
   - Checksums match (byte-for-byte identical)
   - Permissions preserved
   - Ownership correct
   - SELinux contexts match
5. Generates pass/fail report
6. Exports metrics to Prometheus

### Running Manual Tests

```bash
# Test all subvolumes (default: 50 files each)
~/containers/scripts/test-backup-restore.sh

# Test specific subvolume with verbose output
~/containers/scripts/test-backup-restore.sh --subvolume htpc-home --verbose

# Quick test with small sample
~/containers/scripts/test-backup-restore.sh --sample-size 10

# Dry-run to see what would be tested
~/containers/scripts/test-backup-restore.sh --dry-run

# Test specific subvolume only
~/containers/scripts/test-backup-restore.sh --subvolume subvol7-containers
```

### Checking Test Results

```bash
# View last test report
cat ~/containers/data/backup-logs/restore-test-*.log | tail -100

# Check test metrics (for Prometheus)
cat ~/containers/data/backup-metrics/restore-test-metrics.prom

# View test logs in journal
journalctl --user -u backup-restore-test.service

# Check next scheduled test
systemctl --user list-timers backup-restore-test.timer
```

---

## Disaster Recovery Runbooks

### Available Runbooks

| Runbook | Scenario | RTO | RPO | Tested |
|---------|----------|-----|-----|--------|
| [DR-003](../runbooks/DR-003-accidental-deletion.md) | Accidental file/directory deletion | 5-30 min | 1 day | ✓ 2025-11-30 |

### Planned Runbooks

- **DR-001:** System SSD Failure - Complete OS drive failure, restore from external backup
- **DR-002:** BTRFS Pool Corruption - Storage array corruption, reformat and restore
- **DR-004:** Total Catastrophe - Fire/flood/theft, rebuild from off-site backup

---

## Recovery Time Objectives (RTO)

Estimated time to restore and resume operations:

| Subvolume | Size | Restore Time | RTO Target | Notes |
|-----------|------|--------------|------------|-------|
| htpc-home | ~50GB | ~15 min | 30 min | User data, configs |
| subvol7-containers | ~100GB | ~30 min | 1 hour | Service configs |
| subvol3-opptak | ~2TB | ~6 hours | 8 hours | Media library |
| subvol1-docs | ~20GB | ~10 min | 30 min | Documents |
| htpc-root | ~40GB | ~20 min | 1 hour | System files |
| subvol2-pics | ~500GB | ~2 hours | 4 hours | Photo library |

**Notes:**
- Times based on BTRFS send/receive over USB 3.0 (~150 MB/s)
- Add overhead for verification, service restart
- Full system rebuild (DR-001): 4-6 hours total

---

## Recovery Point Objectives (RPO)

Maximum acceptable data loss:

| Tier | Backup Frequency | RPO | Data Loss Risk |
|------|-----------------|-----|----------------|
| 1 (Critical) | Daily local, Weekly external | **7 days** | Config changes, recent data |
| 2 (Important) | Weekly/Monthly | 7-30 days | Documents, system state |
| 3 (Standard) | Weekly local, Monthly external | **30 days** | Media files (replaceable) |

**Improving RPO:**
- For critical data requiring <7 day RPO, increase external backup frequency to daily
- For mission-critical data, implement hourly local snapshots
- For zero data loss, implement continuous replication (BTRFS send/receive streaming)

---

## Backup Locations

### Local Snapshots

**Home directory snapshots:**
```bash
~/.snapshots/htpc-home/
~/.snapshots/htpc-root/
```

**BTRFS pool snapshots:**
```bash
/mnt/btrfs-pool/.snapshots/subvol1-docs/
/mnt/btrfs-pool/.snapshots/subvol2-pics/
/mnt/btrfs-pool/.snapshots/subvol3-opptak/
/mnt/btrfs-pool/.snapshots/subvol7-containers/
```

### External Backup Drive

**Location:** `/run/media/patriark/WD-18TB/` (when mounted)
**Encryption:** LUKS encrypted
**Capacity:** 18TB
**Usage:** ~2.5TB (14% full)

**Mount external drive:**
```bash
# Drive auto-mounts when connected via USB
# Manual mount if needed:
sudo cryptsetup open /dev/sdX WD-18TB
sudo mount /dev/mapper/WD-18TB /mnt/external
```

**External snapshot structure:**
```bash
/run/media/patriark/WD-18TB/.snapshots/htpc-home/
/run/media/patriark/WD-18TB/.snapshots/subvol1-docs/
/run/media/patriark/WD-18TB/.snapshots/subvol2-pics/
/run/media/patriark/WD-18TB/.snapshots/subvol3-opptak/
/run/media/patriark/WD-18TB/.snapshots/subvol7-containers/
```

---

## Quick Recovery Examples

### Example 1: Restore deleted file from today

```bash
# Use today's snapshot
TODAY=$(date +%Y%m%d)
cp -a ~/.snapshots/htpc-home/${TODAY}-home/Documents/report.pdf \
      ~/Documents/report.pdf
```

### Example 2: Restore container config from last week

```bash
# Find last week's snapshot
LAST_WEEK=$(ls -t /mnt/btrfs-pool/.snapshots/subvol7-containers/ | grep "$(date -d '7 days ago' +%Y%m)" | head -1)

# Restore config
cp -a /mnt/btrfs-pool/.snapshots/subvol7-containers/$LAST_WEEK/config/jellyfin/ \
      ~/containers/config/jellyfin/

# Restart service
systemctl --user restart jellyfin.service
```

### Example 3: Restore from external backup

```bash
# Mount external drive (if not auto-mounted)
# Drive should appear at /run/media/patriark/WD-18TB/

# Find latest external snapshot
LATEST=$(ls -t /run/media/patriark/WD-18TB/.snapshots/htpc-home/ | head -1)

# Restore
cp -a /run/media/patriark/WD-18TB/.snapshots/htpc-home/$LATEST/path/to/file.txt \
      ~/path/to/file.txt
```

---

## Monitoring & Alerts

### Prometheus Metrics

**Restore test metrics:**
```prometheus
# Test success (1 = pass, 0 = fail)
backup_restore_test_success{subvolume="htpc-home"}

# Test duration
backup_restore_test_duration_seconds{subvolume="htpc-home"}

# Files validated
backup_restore_test_files_validated{subvolume="htpc-home"}

# Last test timestamp
backup_restore_test_last_run_timestamp
```

**View metrics:**
```bash
cat ~/containers/data/backup-metrics/restore-test-metrics.prom
```

### Future: Grafana Dashboard

Planned dashboard panels:
- Backup status overview (all subvolumes)
- Restore test results (pass/fail history)
- Backup age (time since last backup)
- Backup size trends
- RTO/RPO metrics

---

## Backup Maintenance

### Check Backup Health

```bash
# Run comprehensive diagnostics
~/containers/scripts/homelab-diagnose.sh

# Check backup age
ls -lt ~/.snapshots/htpc-home/ | head -10

# Verify external drive
df -h /run/media/patriark/WD-18TB/
```

### Manual Backup

```bash
# Run backup manually for specific subvolume
~/containers/scripts/btrfs-snapshot-backup.sh \
    --subvolume containers \
    --tier 1

# Run full backup (all tiers)
~/containers/scripts/btrfs-snapshot-backup.sh --verbose
```

### Cleanup Old Snapshots

**Automated cleanup:**
- Backup script automatically removes old snapshots per retention policy
- Local: Keeps 7 daily
- External: Keeps 4-8 weekly + 6-12 monthly

**Manual cleanup (if needed):**
```bash
# List old snapshots
ls -lt ~/.snapshots/htpc-home/

# Delete specific snapshot
sudo btrfs subvolume delete ~/.snapshots/htpc-home/20251101-home
```

---

## Off-Site Backup Strategy

**Status:** Not yet implemented (Future Phase 5)

**Recommended approach:**
1. **Cloud backup** (Backblaze B2, Wasabi)
   - Encrypted with rclone
   - Monthly sync of critical data
   - Cost: ~$6/TB/month

2. **Friend's house exchange**
   - Swap external drives monthly
   - Free, requires trust + coordination

3. **Bank safe deposit box**
   - Quarterly rotation
   - Maximum security, slow recovery

**Priority:** Implement cloud backup for htpc-home and subvol7-containers (most critical, small size)

---

## Testing Schedule

### Monthly Automated Tests
- Restore test (last Sunday 11:00 AM)
- Validates 50 random files per subvolume
- Reports via Prometheus metrics

### Quarterly Manual Drills
- Full subvolume restore to test environment
- Practice DR runbook procedures
- Update RTO measurements
- Review and update runbooks

### Annual Review
- Complete disaster recovery table-top exercise
- Review backup strategy
- Update documentation
- Validate off-site backup procedures (when implemented)

---

## Troubleshooting

### Test Failed - What to Do

1. **Check test logs:**
   ```bash
   cat ~/containers/data/backup-logs/restore-test-*.log | tail -100
   ```

2. **Identify failure:**
   - Checksum mismatch = snapshot corruption (critical!)
   - Permission mismatch = SELinux context (usually OK)
   - File missing = snapshot incomplete

3. **Investigate snapshot integrity:**
   ```bash
   # Check BTRFS filesystem
   sudo btrfs scrub start /mnt/btrfs-pool/
   sudo btrfs scrub status /mnt/btrfs-pool/
   ```

4. **Test manual restore:**
   ```bash
   # Try restoring single file manually
   cp -a ~/.snapshots/htpc-home/20251130-home/test.txt ~/test-restore.txt
   cmp ~/.snapshots/htpc-home/20251130-home/test.txt ~/test-restore.txt
   ```

### Backup Not Running

1. **Check timer status:**
   ```bash
   systemctl --user list-timers | grep btrfs
   ```

2. **Check service logs:**
   ```bash
   journalctl --user -u btrfs-snapshot-backup.service -n 50
   ```

3. **Run backup manually:**
   ```bash
   ~/containers/scripts/btrfs-snapshot-backup.sh --verbose
   ```

---

## Related Documentation

- [Backup Strategy](backup-strategy.md) - Overall backup approach
- [BTRFS Snapshot Backup Script](../../scripts/btrfs-snapshot-backup.sh) - Automated backup implementation
- [Restore Testing Script](../../scripts/test-backup-restore.sh) - Automated validation
- [DR Runbooks](../runbooks/) - Step-by-step recovery procedures

---

**Project Status:** Phase 1 Complete ✓

- [x] Automated restore testing script
- [x] Monthly test schedule (systemd timer)
- [x] First DR runbook (DR-003)
- [ ] All DR runbooks (DR-001, DR-002, DR-004)
- [ ] Prometheus alerting integration
- [ ] Grafana dashboard
- [ ] RTO measurement for all subvolumes
- [ ] Off-site backup implementation

**Next Steps:**
1. Let automated tests run for 3 months to establish baseline
2. Create remaining DR runbooks (DR-001, DR-002, DR-004)
3. Implement Prometheus alerting for backup failures
4. Build Grafana backup health dashboard
5. Plan and implement off-site backup strategy
