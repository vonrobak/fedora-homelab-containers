# Backup Automation Setup Guide

**Date:** 2025-11-12 (Updated: 2025-12-09)
**Purpose:** Enable automated daily BTRFS snapshots via systemd timer
**Status:** ✅ Production - Daily and weekly backups running successfully

---

## Overview

The backup system uses a comprehensive BTRFS snapshot script with systemd timer automation:

- **Script:** `scripts/btrfs-snapshot-backup.sh`
- **Daily Service:** `~/.config/systemd/user/btrfs-backup-daily.service`
- **Daily Timer:** `~/.config/systemd/user/btrfs-backup-daily.timer`
- **Weekly Service:** `~/.config/systemd/user/btrfs-backup-weekly.service`
- **Weekly Timer:** `~/.config/systemd/user/btrfs-backup-weekly.timer`

**Schedule:**
- **Daily** local snapshots at **02:00 AM** (Tier 1: home, opptak, containers)
- **Weekly** external backups on **Saturdays at 04:00 AM** (all tiers to WD-18TB drive)

**⚠️ CRITICAL FOR SINGLE PROFILE:**
With the BTRFS pool now running in **Single profile** (no data redundancy), this backup system is the **ONLY** protection against data loss from disk failure. The backup automation must be monitored closely and maintained rigorously.

---

## Single Profile Considerations

**Storage Profile Change (2025-12-06):**
The BTRFS pool was converted from RAID5 to Single profile due to operational issues with RAID5 chunk allocation. This has significant implications for backup strategy:

### Data Protection Layers

**Before (RAID5):**
1. RAID5 parity (survives 1 disk failure)
2. Daily local snapshots
3. Weekly external backups

**After (Single):**
1. ~~RAID5 parity~~ **REMOVED**
2. RAID1 metadata (filesystem survives disk failure, can mount read-only)
3. Daily local snapshots (on same disks - no hardware failure protection)
4. Weekly external backups (**PRIMARY PROTECTION**)

### Recovery Expectations

**Recovery Time Objective (RTO):**
- Accidental deletion: ~5 minutes (local snapshot rollback)
- Single disk failure: **6-24 hours** (restore from WD-18TB external)
- Multiple disk failure: **24-48 hours** (full rebuild + restore)
- External drive failure: **DATA LOSS** (no backup!)

**Recovery Point Objective (RPO):**
- Tier 1 (critical data): 12-24 hours (daily backups to external drive weekly)
- Tier 2 (important data): 7 days (weekly backups)
- Tier 3 (replaceable media): 30 days (monthly backups)

### Critical Requirements

**1. Weekly External Backup MUST Succeed**
- Monitor `btrfs-backup-weekly.service` status closely
- Current timeout: 6 hours (may be insufficient for subvol3-opptak at 2TB+)
- **Recommendation:** Increase timeout to 12 hours

**2. SMART Monitoring is Mandatory**
- Weekly disk health checks via `weekly-intelligence-report.sh`
- Early warning of disk failure is critical
- Any SMART warnings = immediate backup verification

**3. External Drive Must Be Reliable**
- WD-18TB is single point of failure for recovery
- Test drive health monthly
- Consider annual clone to secondary drive

**4. Backup Verification**
- Cannot assume backups are good
- Quarterly test restore recommended
- Verify backup completion in logs weekly

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

## Current Production Status

**As of 2025-12-09:**

**Daily Backups (btrfs-backup-daily.timer):**
- ✅ Running successfully
- Schedule: Daily at 02:00
- Last run: 2025-12-08 02:00 (successful)
- Duration: ~3 minutes
- Creates snapshots for: htpc-home, subvol3-opptak, subvol7-containers

**Weekly External Backups (btrfs-backup-weekly.timer):**
- ✅ Running successfully (with timeout warnings)
- Schedule: Saturdays at 04:00
- Last run: 2025-12-06 04:00 → 13:40 (9h 40m total)
- **Issue:** subvol3-opptak (2.1 TiB) took 9h 40m but timeout set to 6h
- **Status:** Backup completed successfully despite timeout warning
- **Action needed:** Increase timeout to 12 hours

**Retention Status:**
- Local snapshots: 7 days for Tier 1 (working as designed)
- External snapshots: 8 weeks for Tier 1 (working as designed)
- Oldest snapshot: 2025-04-20 (needs cleanup review)

---

## Proposed Improvements

Based on Single profile deployment and operational experience:

### HIGH PRIORITY

**1. Increase Weekly Backup Timeout**
```bash
# Edit weekly service file
nano ~/.config/systemd/user/btrfs-backup-weekly.service

# Change TimeoutStartSec from 6h to 12h
TimeoutStartSec=12h

# Reload and restart
systemctl --user daemon-reload
systemctl --user restart btrfs-backup-weekly.timer
```
**Reason:** subvol3-opptak (2.1 TiB) requires 9h 40m for incremental backup

**2. Add SMART Monitoring Alerts**
- Weekly SMART checks already run via `weekly-intelligence-report.sh`
- Add Prometheus alert for SMART failures
- Alert on: Reallocated sectors, pending sectors, offline uncorrectable

**3. Test External Drive Restore**
- Document: Last restore test date
- Procedure: Restore test file from snapshot to verify integrity
- Frequency: Quarterly

### MEDIUM PRIORITY

**4. Consider Midday Snapshots for Tier 1**
- Current RPO: 24 hours (backup at 02:00)
- With midday snapshot (14:00): RPO: 12 hours
- Minimal cost (snapshots are cheap with BTRFS COW)
- Only for critical data (subvol7-containers with Vaultwarden)

**5. Implement Backup Verification**
- Checksum verification of external backups
- Compare snapshot sizes (source vs destination)
- Alert on size mismatch (potential corruption)

**6. Export Backup Metrics to Prometheus**
- Add node_exporter textfile collector
- Metrics: backup duration, snapshot count, backup size
- Enable Grafana dashboards for backup health

### LOW PRIORITY

**7. Update Documentation**
- ✅ This document updated (2025-12-09)
- ✅ storage-layout.md updated (2025-12-09)
- Consider: Restore procedure runbook

**8. Add Backup Dashboard to Grafana**
- Panel: Last successful backup timestamp
- Panel: Backup duration trend
- Panel: Snapshot disk usage
- Panel: Days since last backup

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

---

## Revision History

| Date | Change | Reason |
|------|--------|--------|
| 2025-11-12 | Initial version created | Document backup automation setup |
| 2025-12-09 | **Major update for Single profile** | BTRFS pool converted from RAID5 to Single |
| | Added Single Profile Considerations section | Backups now primary data protection |
| | Documented RTO/RPO expectations | Clear recovery time/point objectives |
| | Added Current Production Status | Document operational experience |
| | Added Proposed Improvements | 8 improvements across 3 priorities |
| | Updated service/timer names | Corrected to actual production names |
| | Documented timeout issue | subvol3-opptak requires 9h 40m for backup |
| | Recommended timeout increase to 12h | Prevent false failures on large backups |

---

**Status:** Production operational guide
**Owner:** Homelab infrastructure (patriark)
**Next Review:** 2026-01-09 or after backup system changes

**Critical:** Weekly external backups are PRIMARY protection for Single profile storage
