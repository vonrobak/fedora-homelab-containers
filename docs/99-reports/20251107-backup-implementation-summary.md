# BTRFS Backup Implementation Summary

**Date:** 2025-11-07
**Status:** Ready for activation (requires user approval)

---

## ✅ What Was Created

### 1. Automated Backup Script
**Location:** `~/containers/scripts/btrfs-snapshot-backup.sh`

**Features:**
- Automated BTRFS snapshot creation and external backup
- Optimized for 128GB NVMe (minimal local retention)
- Weekly external backups only (reduces system load)
- Tier-based approach (Critical → Important → Standard)
- Extensive logging and error handling
- Dry-run mode for testing
- Configurable retention policies

**Key Design Decisions:**
- **Local retention**: 7 days max (saves NVMe space)
- **External frequency**: Weekly only (per your request - daily is too much load)
- **Root snapshots**: Monthly only, 1 local (per architecture doc)
- **Manual handling**: Tier 4+ (multimedia/music) not automated

### 2. Comprehensive Documentation
**Location:** `~/containers/docs/backup-strategy-guide.md`

**Contents:**
- Complete parameter adjustment guide
- Usage examples for all scenarios
- Recovery procedures (file and full restore)
- Troubleshooting common issues
- Monitoring and health checks
- Best practices

### 3. Systemd Timer Units
**Location:** `~/.config/systemd/user/`

**Created timers:**
- `btrfs-backup-daily.timer` - Daily 02:00 AM (local snapshots only)
- `btrfs-backup-weekly.timer` - Sunday 03:00 AM (external backup)

**Status:** Created but NOT enabled (requires your activation)

---

## 📊 Backup Strategy Summary

### Tier 1: CRITICAL (Automated - Daily local, Weekly external)

| Subvolume | Local | External | Local Retention | External Retention |
|-----------|-------|----------|-----------------|-------------------|
| **htpc-home** | Daily 02:00 | Sun 03:00 | 7 days | 8 weekly + 12 monthly |
| **subvol3-opptak** | Daily 02:00 | Sun 03:00 | 7 days | 8 weekly + 12 monthly |
| **subvol7-containers** | Daily 02:00 | Sun 03:00 | 7 days | 4 weekly + 6 monthly |

**Rationale:**
- **htpc-home**: Infrastructure configs, critical
- **subvol3-opptak**: Irreplaceable videos, **heightened backup demands** (per doc)
- **subvol7-containers**: Operational continuity (Prometheus, Grafana, Loki)

### Tier 2: IMPORTANT (Automated - Daily/Monthly local, Weekly/Monthly external)

| Subvolume | Local | External | Local Retention | External Retention |
|-----------|-------|----------|-----------------|-------------------|
| **subvol1-docs** | Daily 02:00 | Sun 03:00 | 7 days | 8 weekly + 6 monthly |
| **htpc-root** | 1st of month | Monthly | 1 month | 6 monthly |

**Rationale:**
- **subvol1-docs**: Work documents
- **htpc-root**: System recovery (monthly only per architecture doc line 174)

### Tier 3: STANDARD (Automated - Weekly local, Monthly external)

| Subvolume | Local | External | Local Retention | External Retention |
|-----------|-------|----------|-----------------|-------------------|
| **subvol2-pics** | Sun 02:00 | 1st Sun 03:00 | 4 weeks | 12 monthly |

**Rationale:** Mostly replaceable content (art, wallpapers, memes)

### Tier 4: MANUAL ONLY (No Automation)

- subvol4-multimedia (Jellyfin media - re-acquirable)
- subvol5-music (Music library - re-acquirable)
- subvol6-tmp (Cache - not backed up)

**Rationale:** Very large, replaceable content; handle manually when needed

---

## 📂 Storage Impact Estimates

### Local NVMe Storage (128GB)

Estimated local snapshot storage with 7-day retention:

```
htpc-home (Tier 1):
  - Base size: ~5-10 GB
  - 7 daily snapshots: ~1-2 GB (CoW, mostly metadata)
  - TOTAL: ~6-12 GB

subvol3-opptak (Tier 1):
  - Base size: ~50-200 GB (on HDD pool, not NVMe)
  - Snapshots: 0 GB on NVMe (local snapshots on HDD pool)

subvol7-containers (Tier 1):
  - Base size: ~10-50 GB (on HDD pool, not NVMe)
  - Snapshots: 0 GB on NVMe (local snapshots on HDD pool)

subvol1-docs (Tier 2):
  - Base size: ~5-20 GB (on HDD pool)
  - Snapshots: 0 GB on NVMe

htpc-root (Tier 2):
  - Base size: ~10-30 GB (on NVMe)
  - 1 monthly snapshot: ~500 MB - 2 GB (CoW)
  - TOTAL: ~0.5-2 GB

TOTAL NVMe SNAPSHOT OVERHEAD: ~7-15 GB (acceptable on 128GB drive)
```

### External Drive Storage (18TB)

With 8 weekly + 12 monthly retention:

```
Estimated maximum with all tiers:
- htpc-home: ~150 GB (8w + 12m snapshots)
- subvol3-opptak: ~4 TB (if heavily used for videos)
- subvol7-containers: ~800 GB (metrics grow over time)
- subvol1-docs: ~400 GB
- htpc-root: ~360 GB
- subvol2-pics: ~600 GB
TOTAL: ~6-7 TB (leaves ~11 TB free on 18TB drive)
```

---

## 🚀 Next Steps (Manual Activation Required)

### Step 1: Test Dry-Run (RECOMMENDED)

```bash
# Test what would happen
~/containers/scripts/btrfs-snapshot-backup.sh --dry-run --verbose | less

# Test specific tier
~/containers/scripts/btrfs-snapshot-backup.sh --dry-run --tier 1

# Test specific subvolume
~/containers/scripts/btrfs-snapshot-backup.sh --dry-run --subvolume home
```

### Step 2: Create First Real Snapshots (Optional Manual Test)

```bash
# Create local snapshots only (no external backup)
~/containers/scripts/btrfs-snapshot-backup.sh --local-only --verbose

# Verify snapshots were created
ls -lh ~/.snapshots/htpc-home/
ls -lh /mnt/btrfs-pool/.snapshots/subvol3-opptak/
ls -lh /mnt/btrfs-pool/.snapshots/subvol7-containers/
```

### Step 3: Test External Backup (When Drive Connected)

```bash
# Ensure external drive is mounted
df -h /run/media/patriark/WD-18TB

# Test external backup with existing local snapshots
~/containers/scripts/btrfs-snapshot-backup.sh --external-only --verbose

# Verify backups on external drive
ls -lh /run/media/patriark/WD-18TB/.snapshots/htpc-home/
```

### Step 4: Enable Systemd Timers (Automation)

```bash
# Enable daily local snapshots
systemctl --user enable btrfs-backup-daily.timer
systemctl --user start btrfs-backup-daily.timer

# Enable weekly external backups
systemctl --user enable btrfs-backup-weekly.timer
systemctl --user start btrfs-backup-weekly.timer

# Verify timers are active
systemctl --user list-timers btrfs-backup*
```

### Step 5: Monitor First Automated Runs

```bash
# Check timer status
systemctl --user status btrfs-backup-daily.timer

# View logs after first run
journalctl --user -u btrfs-backup-daily.service -n 100

# View backup script logs
tail -100 ~/containers/data/backup-logs/backup-$(date +%Y%m).log
```

---

## 🔍 Verification Checklist

After enabling timers, verify:

- [ ] Daily timer scheduled correctly: `systemctl --user list-timers`
- [ ] Weekly timer scheduled correctly
- [ ] First daily backup completed successfully
- [ ] Local snapshots created in correct locations
- [ ] External drive has space for backups: `df -h /run/media/patriark/WD-18TB`
- [ ] First weekly external backup completed
- [ ] Logs show no errors: `grep ERROR ~/containers/data/backup-logs/*.log`
- [ ] Old snapshots cleaned up according to retention policy

---

## 🛠️ Common Adjustments

### Reduce Local Retention (Free Up NVMe)

If NVMe gets tight, reduce retention in script:

```bash
nano ~/containers/scripts/btrfs-snapshot-backup.sh

# Change these values (around line 50-70):
TIER1_HOME_LOCAL_RETENTION_DAILY=3      # Instead of 7
TIER1_OPPTAK_LOCAL_RETENTION_DAILY=3
TIER1_CONTAINERS_LOCAL_RETENTION_DAILY=3
```

### Disable Specific Backups

```bash
# Edit script
nano ~/containers/scripts/btrfs-snapshot-backup.sh

# Disable subvol1-docs if using Nextcloud sync:
TIER2_DOCS_ENABLED=false

# Disable subvol2-pics if not important:
TIER3_PICS_ENABLED=false
```

### Change Backup Schedule

```bash
# Change daily backup time from 02:00 to 04:00
nano ~/.config/systemd/user/btrfs-backup-daily.timer

# Change: OnCalendar=*-*-* 04:00:00

# Reload and restart
systemctl --user daemon-reload
systemctl --user restart btrfs-backup-daily.timer
```

---

## 📋 Monitoring & Maintenance

### Daily Checks (Optional)

```bash
# Quick health check
~/containers/scripts/btrfs-snapshot-backup.sh --dry-run | grep -E "(SUCCESS|ERROR)"
```

### Weekly Checks (Recommended)

```bash
# Check backup logs for errors
grep ERROR ~/containers/data/backup-logs/backup-$(date +%Y%m).log

# Verify external drive health
sudo smartctl -H /dev/sdX  # Replace X with actual drive

# Check external drive space
df -h /run/media/patriark/WD-18TB
```

### Monthly Checks (Recommended)

```bash
# Test restore procedure
ls ~/.snapshots/htpc-home/
# Pick a snapshot and verify you can access files

# Review retention policies
ls -lh ~/.snapshots/htpc-home/ | wc -l  # Should be ~7 snapshots
ls -lh /run/media/patriark/WD-18TB/.snapshots/htpc-home/ | wc -l  # Should be ~20 (8w + 12m)

# Check NVMe space usage
df -h /
sudo btrfs filesystem usage /
```

---

## 🎯 Design Highlights

### Why This Strategy Works for You

1. **Minimal NVMe impact**: Only 7-15 GB overhead on 128GB drive
2. **Weekly external**: Balances protection vs. system load
3. **Risk tolerance**: Accepts up to 7 days data loss (you approved this)
4. **Tiered approach**: Critical data protected more heavily
5. **Documented parameters**: Easy to adjust as needs change
6. **Manual Tier 4**: Saves automation complexity for large replaceable data

### Key Optimizations

- **subvol3-opptak priority**: Elevated to Tier 1 per architecture doc
- **htpc-root minimal**: 1 local snapshot only (saves NVMe space)
- **CoW efficiency**: BTRFS snapshots are space-efficient
- **Incremental sends**: Only changed data sent to external drive
- **Nice priority**: Backup processes don't impact system performance

---

## 📚 Related Documentation

- **Main guide**: `~/containers/docs/backup-strategy-guide.md`
- **Storage architecture**: `~/containers/docs/99-reports/20251025-storage-architecture-authoritative-rev2.md`
- **Monitoring stack**: `~/containers/docs/monitoring-stack-guide.md`

---

## ⚠️ Important Notes

1. **External drive must be connected** for weekly backups to work
2. **First full backup will be slow** (subsequent incrementals are fast)
3. **Timers are DISABLED by default** - you must enable them manually
4. **Test dry-run first** before enabling automation
5. **Monitor first week** to ensure everything works as expected
6. **Backup the backup script** itself is in htpc-home (already backed up)

---

## 🔐 Security Considerations

- External drive is LUKS-encrypted ✅
- Snapshots are read-only ✅
- Script runs as user (not root) except for btrfs commands ✅
- Logs contain no sensitive data ✅
- External drive should be disconnected when not in use (ransomware protection) ⚠️

---

**Implementation Status:** ✅ COMPLETE - Ready for activation

**Next Action Required:** Run Step 1 (dry-run test) above

---

**Created:** 2025-11-07
**Script Version:** 1.0
**Last Updated:** 2025-11-07
