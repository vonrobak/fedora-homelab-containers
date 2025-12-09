# Storage Layout and Strategy

**Last Updated:** 2025-12-09
**Status:** Authoritative Guide
**Review Cycle:** Monthly or when system drive >75%

---

## Executive Summary

This homelab operates under a **critical constraint: 128GB system drive** (118GB usable). All storage strategy decisions flow from this limitation. This guide documents current state, migration priorities, and decision-making criteria for where data should live.

**Current Status:** System drive at **81% capacity** (93GB / 118GB used) - **⚠️ URGENT ACTION REQUIRED**

**Storage Architecture:**
- **System SSD (NVMe):** 128GB BTRFS - OS, containers, critical configs
- **BTRFS Pool (HDD Array):** 14.56 TiB BTRFS Single profile - Media, bulk data, container volumes

---

## Table of Contents

1. [Current State Analysis](#current-state-analysis)
2. [System Drive Breakdown](#system-drive-breakdown)
3. [BTRFS Pool Architecture](#btrfs-pool-architecture)
4. [Storage Decision Matrix](#storage-decision-matrix)
5. [Migration Priorities](#migration-priorities-urgent)
6. [NOCOW Database Optimization](#nocow-database-optimization)
7. [Cleanup Strategies](#cleanup-strategies)
8. [Monitoring and Thresholds](#monitoring-and-thresholds)
9. [Backup Strategy](#backup-strategy)

---

## Current State Analysis

**Measurement Date:** 2025-11-14

### System Drive (NVMe SSD - BTRFS)

```
Filesystem      Size  Used Avail Use% Mounted on
/dev/nvme0n1p3  118G   93G   23G  81% /
```

**⚠️ CRITICAL: System drive at 81% (threshold: 80%)**
- Only 23GB free space remaining
- Immediate cleanup/migration required
- Risk of filling during OS updates

**BTRFS Subvolumes:**
- `/` - Root filesystem (subvolume)
- `/home` - User data (subvolume)

### BTRFS Pool (HDD Array)

```
Filesystem      Size  Used Avail Use% Mounted on
/dev/sdc        14.6T  8.2T  6.4T  56% /mnt/btrfs-pool
```

**✅ Healthy: BTRFS pool at 56%**
- 6.37 TiB free space available (increased from RAID5 → Single conversion)
- Physical Devices: 4x 3.64 TiB (14.56 TiB total)
- **Profile:** Single (data), RAID1 (metadata/system)
- **Conversion:** Migrated from RAID5 to Single on 2025-12-06 due to operational issues
- Future: Consider 2x 4TB Samsung SSDs for system drive expansion

---

## System Drive Breakdown

### Top Space Consumers

| Component | Size | Path | Status |
|-----------|------|------|--------|
| **Podman Storage** | 8.4GB | `~/.local/share/containers/storage` | 🔴 Cannot relocate |
| **Jellyfin Config** | 4.6GB | `~/containers/config/jellyfin` | 🟡 **MIGRATE (Priority 1)** |
| **Journal Logs** | 1.8GB | User journal | 🟢 Can prune |
| **Other Configs** | ~800MB | `~/containers/config/*` | ✅ Optimal |
| **Container Data** | 410MB | `~/containers/data/*` | ✅ Acceptable |
| **Docs/Scripts** | 3.3MB | `~/containers/docs`, `scripts` | ✅ Optimal |

**Total Container-Related:** ~15GB
**System/OS/Other:** ~78GB

### Podman Storage Detail

```bash
TYPE           TOTAL  ACTIVE  SIZE     RECLAIMABLE
Images         22     20      8.692GB  599.3MB (7%)
Containers     20     20      1.423MB  0B (0%)
Local Volumes  2      1       20.48kB  20.48kB (100%)
```

**Analysis:**
- **overlay storage:** 8.4GB (`~/.local/share/containers/storage/overlay`)
- **Cannot relocate:** Podman expects default location, complex to change
- **Reclaimable:** 599MB from unused images (7% cleanup potential)
- **Growth rate:** ~400MB per new service (container image)

### Container Configuration Directories

```bash
# Sorted by size (largest first)
jellyfin:     4.6GB  ← PROBLEM: Transcoding cache, should be on BTRFS
grafana:      576KB  ← Acceptable
traefik:      64KB
homepage:     60KB
prometheus:   20KB
authelia:     8KB
alertmanager: 4KB
loki:         4KB
alloy:        4KB
promtail:     4KB
ocis:         4KB
monitoring/   0KB (empty)
nextcloud/    0KB (empty)
```

**Issue:** Jellyfin config contains transcoding cache and metadata databases that grow over time.

### Container Data Directories

```bash
journal-export:   261MB  ← Prometheus-exported journal logs
crowdsec:         80MB   ← CrowdSec databases
grafana:          17MB   ← SQLite database (should move to BTRFS with NOCOW)
authelia:         252KB
backup-logs:      136KB
redis-authelia:   28KB
promtail:         4KB
alloy:            8KB
(others):         <4KB each
```

**Assessment:** Current sizes acceptable on system drive, but grafana will grow.

---

## BTRFS Pool Architecture

### Profile Configuration

**Data Profile:** Single
- 1.0x storage ratio (no redundancy)
- All disks independently allocatable
- Provides maximum capacity
- **Risk:** Single disk failure = data loss
- **Mitigation:** Daily local snapshots + weekly external backups

**Metadata Profile:** RAID1
- 2.0x storage ratio (2 copies on different disks)
- Filesystem metadata survives single disk failure
- Provides filesystem-level redundancy
- Critical for maintaining filesystem integrity

**System Profile:** RAID1 (32 MiB total)
- Stores BTRFS superblock and critical structures
- Survives single disk failure

**Why Single Profile?**
- Previous RAID5 had operational issues (chunk allocation deadlocks)
- RAID1 didn't fit (would need 16.36 TiB for 8.18 TiB data, have 14.56 TiB total)
- Hardware limited to 4 SATA ports (no expansion possible)
- Strong backup strategy makes Single profile viable

**Physical Layout:**
```
Device       DevID   Total    Data     Metadata  Unallocated
/dev/sdc     1       3.64T    1.69T    4.00G     1.94T
/dev/sda     3       3.64T    1.69T    4.00G     1.94T
/dev/sdb     4       3.64T    2.40T    7.00G     1.23T
/dev/sdd     5       3.64T    2.40T    7.00G     1.23T
─────────────────────────────────────────────────────────
Total:               14.56T   8.19T    22.00G    6.37T
```

### Subvolume Structure

Location: `/mnt/btrfs-pool/`

| Subvolume | Size | Purpose | SMB Share | Notes |
|-----------|------|---------|-----------|-------|
| **subvol1-docs** | 12GB | Documents | ✅ Yes | Intended for Nextcloud |
| **subvol2-pics** | 42GB | Photos | ✅ Yes | Immich + Nextcloud target |
| **subvol3-opptak** | 2.0TB | Phone recordings | ✅ Yes | Immich + Nextcloud target |
| **subvol4-multimedia** | 5.2TB | Jellyfin media files | ✅ Yes | **Consider READ-ONLY mounts** |
| **subvol5-music** | 1.1TB | Music library | ✅ Yes | **Consider READ-ONLY mounts** |
| **subvol6-tmp** | 6.5GB | Temporary files, cache | ❌ No | Jellyfin transcoding cache |
| **subvol7-containers** | 3.0GB | Container persistent data | ❌ No | Database volumes with NOCOW |

**Total Used:** 8.19 TiB / 14.56 TiB (56%)

**Network Access:** Subvolumes 1-5 are SMB shared on local network.

**Read-Only Consideration:** subvol4-multimedia and subvol5-music could be mounted read-only in containers for additional data protection (Jellyfin only reads media).

### Container Subvolume Detail

**Path:** `/mnt/btrfs-pool/subvol7-containers/`

```bash
# Actual usage breakdown
prometheus:          1.1GB  (NOCOW: YES ✅) - TSDB
immich-ml-cache:     786MB  (NOCOW: NO ✅)  - ML model cache
jellyfin:            603MB  (NOCOW: NO ✅)  - Transcoding cache
loki:                561MB  (NOCOW: NO ❌)  - Log database (NEEDS NOCOW!)
homelab-public:      44MB   (NOCOW: NO ✅)  - Static website
redis-immich:        1.2MB  (NOCOW: NO ✅)  - Redis RDB
vaultwarden:         764KB  (NOCOW: NO ⚠️)  - SQLite (check NOCOW need)

# Empty (prepared for future)
databases/           0KB
monitoring/          0KB
nextcloud/           0KB
postgresql-immich/   0KB
ocis/                0KB
```

**Issues Identified:**
1. **Loki MUST have NOCOW** - Database write pattern suffers from BTRFS COW (Priority 2)
2. **Jellyfin config not migrated** - 4.6GB wasted on system drive (Priority 1)
3. **Grafana database on system drive** - Will grow, should migrate to BTRFS+NOCOW (Priority 3)
4. **Vaultwarden** - Verify if SQLite database present, may need NOCOW

---

## Storage Decision Matrix

**Where should data live?** Use this decision tree:

```
START: New service needs storage
│
├─ Is it OS-critical? (systemd, networking, base auth)
│  └─ YES → System Drive (SSD)
│
├─ Is it >500MB and growing?
│  └─ YES → BTRFS Pool (HDD)
│
├─ Does it need high IOPS? (databases, frequent random writes)
│  ├─ YES & <1GB → System Drive (SSD)
│  └─ YES & >1GB → BTRFS Pool (HDD) + NOCOW required
│
├─ Is it media/bulk data?
│  └─ YES → BTRFS Pool (HDD) - use appropriate subvolume
│
├─ Is it configuration files? (<100MB)
│  └─ YES → System Drive (SSD) for fast access
│
└─ Default: BTRFS Pool (HDD) - always safer given 128GB constraint
```

### Size Thresholds Reference

| Data Type | System Drive | BTRFS Pool | Special Handling |
|-----------|-------------|------------|------------------|
| **Config files** | < 100MB | > 100MB | Small configs on SSD for speed |
| **Databases** | < 500MB | > 500MB | **NOCOW required** on BTRFS |
| **Logs** | Rotate aggressively | Archive here | Journal: 7 days max on SSD |
| **Media** | Never | Always | No exceptions, use subvol4/5 |
| **Caches** | < 50MB | > 50MB | Prefer BTRFS, use subvol6-tmp |
| **Container images** | Always | N/A | Podman default, cannot change |
| **Build artifacts** | Never | Always | Temporary, use subvol6-tmp |

### Performance Characteristics

**System Drive (NVMe SSD - BTRFS):**
- **Pros:** 3000+ MB/s sequential, <1ms latency, excellent random I/O
- **Cons:** Limited 128GB capacity, wear leveling concerns, expensive
- **Best For:** OS, quadlets, hot configs, small databases, Podman images
- **Avoid:** Large media, bulk storage, anything >500MB

**BTRFS Pool (HDD Array - BTRFS Single):**
- **Pros:** 14.56 TiB capacity, cheap, good sequential reads (media streaming), snapshots, maximum usable space
- **Cons:** ~150 MB/s sequential, ~10ms seek latency, poor random I/O, **no data redundancy**
- **Best For:** Media, bulk storage, large databases (with NOCOW), archives
- **Avoid:** OS files, small frequently-accessed configs
- **Critical:** Relies entirely on backup strategy for data protection

---

## Migration Priorities (URGENT)

### Priority 1: Move Jellyfin Config to BTRFS ⚠️ ### This is now resolved!

**Impact:** Frees 4.6GB (5% of system drive)
**Risk:** Low - just transcoding cache and metadata
**Effort:** 30 minutes
**Status:** Resolved


---

### Priority 2: Set NOCOW on Loki Database ⚠️

**Impact:** Improved Loki performance, reduced fragmentation
**Risk:** Low - just attribute change
**Effort:** 15 minutes
**Status:** Tried, but encountered complex errors

**Current:** `/mnt/btrfs-pool/subvol7-containers/loki` (NOCOW: NO)
**Issue:** Database write patterns suffer from BTRFS Copy-on-Write overhead

**Migration Steps:**
```bash
# 1. Stop Loki
systemctl --user stop loki.service

# 2. Create new directory with NOCOW
mkdir -p /mnt/btrfs-pool/subvol7-containers/loki-new
chattr +C /mnt/btrfs-pool/subvol7-containers/loki-new

# 3. Verify NOCOW set
lsattr -d /mnt/btrfs-pool/subvol7-containers/loki-new
# Should show: ---------------C------

# 4. Move data
rsync -av /mnt/btrfs-pool/subvol7-containers/loki/ \
  /mnt/btrfs-pool/subvol7-containers/loki-new/

# 5. Swap directories
mv /mnt/btrfs-pool/subvol7-containers/loki \
   /mnt/btrfs-pool/subvol7-containers/loki-old
mv /mnt/btrfs-pool/subvol7-containers/loki-new \
   /mnt/btrfs-pool/subvol7-containers/loki

# 6. Restart service
systemctl --user start loki.service

# 7. Verify working (check logs)
journalctl --user -u loki.service -n 50

# 8. After 24-48h, cleanup
rm -rf /mnt/btrfs-pool/subvol7-containers/loki-old
```

---

### Priority 3: Move Grafana Database to BTRFS

**Impact:** Frees 17MB, prevents future growth on system drive
**Risk:** Low
**Effort:** 20 minutes

**Current:** `~/containers/data/grafana` (17MB, growing)
**Target:** `/mnt/btrfs-pool/subvol7-containers/grafana` (with NOCOW)

**Migration Steps:** (Same pattern as Loki)

---

### Priority 4: Prune Journal Logs (QUICK WIN)

**Impact:** Frees ~1.3GB
**Risk:** None (retains 7 days minimum)
**Effort:** 5 minutes

```bash
# Check current usage
journalctl --user --disk-usage

# Vacuum to 7 days retention
journalctl --user --vacuum-time=7d

# Or vacuum to size limit
journalctl --user --vacuum-size=500M

# Make permanent (create drop-in)
mkdir -p ~/.config/systemd/user/systemd-journald.service.d/
cat > ~/.config/systemd/user/systemd-journald.service.d/override.conf << 'EOF'
[Journal]
SystemMaxUse=500M
MaxRetentionSec=7day
EOF

systemctl --user daemon-reload
```

---

### Priority 5: Prune Unused Container Images

**Impact:** Frees ~600MB
**Risk:** Low - only removes unused images
**Effort:** 2 minutes

```bash
# Preview what will be removed
podman image prune --all --dry-run

# Remove unused images
podman image prune --all --force

# Verify space reclaimed
podman system df
```

**Expected Combined Impact (Priorities 1-5):**
- Jellyfin config: -4.6GB
- Journal prune: -1.3GB
- Image prune: -0.6GB
- Grafana move: -0.02GB
- **Total freed:** ~6.5GB
- **New system drive usage:** ~86.5GB (75%) ✅ **Sustainable**

---

## NOCOW Database Optimization

### Understanding NOCOW

BTRFS Copy-on-Write (COW) is excellent for snapshots and data integrity, but **terrible for databases**:
- Every database write triggers a copy operation (metadata + data)
- Causes severe fragmentation over time
- Degrades performance significantly (50%+ slower writes)
- Increases disk usage

**Solution:** Disable COW for database directories with `chattr +C`

### When to Use NOCOW

**ALWAYS use NOCOW for:**
- ✅ PostgreSQL data directories
- ✅ MySQL/MariaDB data directories
- ✅ Prometheus TSDB (time-series database)
- ✅ Loki indexes and chunks
- ✅ Grafana SQLite database (grafana.db)
- ✅ Vaultwarden SQLite vault
- ✅ Any SQLite database
- ✅ InfluxDB, TimescaleDB, ClickHouse

**NEVER use NOCOW for:**
- ❌ Media files (MP4, MKV, JPG, PNG, etc.)
- ❌ Configuration files (YAML, JSON, INI)
- ❌ Log archives (want compression & snapshots)
- ❌ Backup files
- ❌ Container images
- ❌ Static website content

### Current NOCOW Status

| Directory | NOCOW | Correct? | Action Needed |
|-----------|-------|----------|---------------|
| **prometheus** | YES ✅ | ✅ Correct | None |
| **loki** | NO ❌ | ❌ Wrong | **Set NOCOW** (Priority 2) |
| **jellyfin** | NO ✅ | ✅ Correct | None (cache/media, not DB) |
| **immich-ml-cache** | NO ✅ | ✅ Correct | None (ML models, not DB) |
| **vaultwarden** | NO ⚠️ | ⚠️ Unknown | Check for SQLite DB |
| **homelab-public** | NO ✅ | ✅ Correct | None (static files) |
| **redis-immich** | NO ✅ | ✅ Correct | None (Redis manages I/O) |

### How to Set NOCOW (Critical Process)

**⚠️ CRITICAL: NOCOW only works on EMPTY directories or NEW files**

**For NEW database (before first use):**
```bash
# Create directory
mkdir -p /mnt/btrfs-pool/subvol7-containers/postgres-db

# Set NOCOW attribute
chattr +C /mnt/btrfs-pool/subvol7-containers/postgres-db

# Verify (should show 'C' flag)
lsattr -d /mnt/btrfs-pool/subvol7-containers/postgres-db
# Output: ---------------C------ /mnt/.../postgres-db

# Now start service - all files will be created with NOCOW
```

**For EXISTING database (requires migration):**
```bash
# 1. Stop service FIRST
systemctl --user stop service.service

# 2. Create new directory with NOCOW
mkdir -p /mnt/btrfs-pool/subvol7-containers/db-new
chattr +C /mnt/btrfs-pool/subvol7-containers/db-new

# 3. Verify NOCOW set
lsattr -d /mnt/btrfs-pool/subvol7-containers/db-new

# 4. Copy data (rsync preserves everything except BTRFS attributes)
rsync -av /old/db/path/ /new/db/path/

# 5. Swap directories (keep backup!)
mv /old/db/path /old/db/path-backup
mv /new/db/path /old/db/path

# 6. Restart service
systemctl --user start service.service

# 7. Verify service works
systemctl --user status service.service

# 8. After 24-48h verification, remove backup
rm -rf /old/db/path-backup
```

---

## Cleanup Strategies

### Regular Maintenance (Monthly)

**1. Prune Podman Resources**
```bash
# Check reclaimable space
podman system df

# Remove unused images only
podman image prune --all --force

# Full prune (images + unused volumes)
podman system prune --all --force --volumes
```

**2. Rotate Journal Logs**
```bash
# Check current usage
journalctl --user --disk-usage

# Vacuum by time
journalctl --user --vacuum-time=7d

# Vacuum by size
journalctl --user --vacuum-size=500M
```

**3. Clean Temporary Files**
```bash
# Check temp subvolume
du -sh /mnt/btrfs-pool/subvol6-tmp

# Remove old files (>30 days)
find /mnt/btrfs-pool/subvol6-tmp -type f -mtime +30 -delete

# Clean Jellyfin transcoding cache if needed
rm -rf /mnt/btrfs-pool/subvol6-tmp/jellyfin/transcodes/*
```

**4. Review Container Log Files**
```bash
# Find largest logs
find ~/containers/data -name "*.log" -exec du -h {} \; | sort -h | tail -10

# Truncate specific logs if needed
: > ~/containers/data/some-service/app.log

# Or rotate with logrotate
```

### Emergency Cleanup (System Drive >90%)

**⚠️ When system drive reaches 90%+, execute immediately:**

```bash
# 1. Aggressive Podman prune
podman system prune --all --force --volumes

# 2. Brutal journal vacuum
journalctl --user --vacuum-size=200M

# 3. Clear package cache (system-wide)
sudo dnf clean all

# 4. Remove old kernels (keep latest 2)
sudo dnf remove $(dnf repoquery --installonly --latest-limit=-2 -q)

# 5. Check for core dumps
du -sh /var/lib/systemd/coredump 2>/dev/null
sudo rm -rf /var/lib/systemd/coredump/* 2>/dev/null

# 6. Clear Podman build cache
podman builder prune --all --force
```

---

## Monitoring and Thresholds

### Disk Usage Alert Levels

| Level | System Drive | BTRFS Pool | Action Required |
|-------|-------------|------------|-----------------|
| **Normal** | < 70% | < 75% | Continue normal operation |
| **Warning** | 70-79% | 75-84% | Review cleanup opportunities |
| **Critical** | 80-89% | 85-94% | **Immediate cleanup required** |
| **Emergency** | ≥ 90% | ≥ 95% | **STOP new deployments, urgent action** |

**Current Status (2025-11-14):**
- System Drive: **81%** 🔴 **CRITICAL**
- BTRFS Pool: **65%** ✅ **NORMAL**

### Daily Monitoring Commands

**Quick Status Check:**
```bash
# One-liner system health
echo "System: $(df -h / | awk 'NR==2 {print $5}')" && \
echo "BTRFS: $(df -h /mnt/btrfs-pool | awk 'NR==2 {print $5}')"

# Detailed breakdown
df -h / /mnt/btrfs-pool
podman system df
journalctl --user --disk-usage
```

**Top Consumer Analysis:**
```bash
# Top 20 on system drive
du -h ~/ 2>/dev/null | sort -h | tail -20

# Top 20 on BTRFS
du -h /mnt/btrfs-pool 2>/dev/null | sort -h | tail -20

# Container-specific
du -sh ~/containers/* | sort -h
du -sh /mnt/btrfs-pool/subvol7-containers/* | sort -h
```

### Prometheus Alerting

Add to Alertmanager configuration:

```yaml
# Alert when system drive >80%
- alert: SystemDriveCritical
  expr: |
    (1 - (node_filesystem_avail_bytes{mountpoint="/"} /
          node_filesystem_size_bytes{mountpoint="/"})) > 0.80
  for: 5m
  annotations:
    summary: "System drive >80% full (CRITICAL)"
    description: "Free space: {{ $value | humanizePercentage }}"

# Alert when BTRFS pool >85%
- alert: BtrfsPoolWarning
  expr: |
    (1 - (node_filesystem_avail_bytes{mountpoint="/mnt/btrfs-pool"} /
          node_filesystem_size_bytes{mountpoint="/mnt/btrfs-pool"})) > 0.85
  for: 15m
  annotations:
    summary: "BTRFS pool >85% full"
    description: "Free space: {{ $value | humanizePercentage }}"
```

### Growth Tracking

**Expected Monthly Growth Rates (no cleanup):**
- Prometheus TSDB: ~200-300MB (15-day retention)
- Loki logs: ~100-200MB (7-day retention)
- Grafana database: ~5-10MB (dashboard changes)
- Journal logs: ~500MB (if not pruned)
- New service images: ~400MB (varies)
- **Total:** ~1.2-1.5GB per month

**Projected System Drive Usage (no intervention):**
- Current: 93GB (81%)
- +1 month: ~95GB (83%)
- +3 months: ~99GB (87%)
- +6 months: ~106GB (93%) ⚠️ **EMERGENCY ZONE**

**After Priorities 1-5 (sustainable trajectory):**
- Post-cleanup: ~86GB (75%) ✅
- +1 month: ~87GB (76%)
- +3 months: ~90GB (79%)
- +6 months: ~93GB (81%) - Returns to current level, cycle repeats

**Recommendation:** Execute Priorities 1-5, then repeat cleanup cycle every 6 months.

---

## Backup Strategy

**⚠️ CRITICAL FOR SINGLE PROFILE:** With no data redundancy in the BTRFS pool, the backup strategy is the **ONLY** protection against data loss.

**Method:** BTRFS Read-Only Snapshots → `btrfs send` to external drives

### Backup Hardware

- **Primary:** 18TB WD External Drive (`/run/media/patriark/WD-18TB/.snapshots`)
- **Secondary:** 18TB Clone Drive (annual off-site backup)

### Single Profile Risk Mitigation

**Data Protection Layers:**
1. **RAID1 Metadata** - Filesystem survives single disk failure (can still mount read-only)
2. **Daily Local Snapshots** - Quick recovery from accidental deletion (RPO: 24 hours)
3. **Weekly External Backups** - Protection from disk failure (RPO: 7 days)
4. **Annual Off-Site Clone** - Disaster recovery (fire, theft, catastrophic failure)

**Recovery Time Objectives (RTO):**
- Accidental deletion: ~5 minutes (snapshot rollback)
- Single disk failure: 6-24 hours (restore from external backup)
- Total pool failure: 24-48 hours (full restore from external backup)

**Recovery Point Objectives (RPO):**
- Tier 1 (Home, Opptak, Containers): 12-24 hours (daily backups)
- Tier 2 (Docs, Pics): 7 days (weekly backups)
- Tier 3 (Multimedia, Music): 30 days (monthly backups)

**SMART Monitoring (Mandatory):**
- Weekly disk health checks required
- Early warning of disk failure critical
- See `~/containers/scripts/weekly-intelligence-report.sh`

### Snapshot Schedule

**System Drive Subvolumes:**
- `/` (root)
- `/home`
- **Schedule:** Weekly on Saturdays at 04:00
- **Last exported:** 2025-10-23

**BTRFS Pool Subvolumes:**
- **Tier 1** (subvol1-home, subvol3-opptak, subvol7-containers): Daily at 02:00
- **Tier 2** (subvol1-docs, subvol2-pics): Weekly on Saturdays
- **Tier 3** (subvol4-multimedia, subvol5-music): Monthly
- **Last external backup:** 2025-12-06 (completed successfully)

### Backup Commands

**Create snapshot:**
```bash
# Example for containers subvolume
sudo btrfs subvolume snapshot -r \
  /mnt/btrfs-pool/subvol7-containers \
  /mnt/btrfs-pool/.snapshots/subvol7-containers-$(date +%Y%m%d)
```

**Send to external drive:**
```bash
# Initial full send
sudo btrfs send /mnt/btrfs-pool/.snapshots/subvol7-containers-20251114 | \
sudo btrfs receive /run/media/patriark/WD-18TB/.snapshots/

# Incremental send (after next snapshot)
sudo btrfs send -p /mnt/btrfs-pool/.snapshots/subvol7-containers-20251114 \
  /mnt/btrfs-pool/.snapshots/subvol7-containers-20251214 | \
sudo btrfs receive /run/media/patriark/WD-18TB/.snapshots/
```

**Restore from snapshot:**
```bash
# Make read-write
sudo btrfs property set -ts /mnt/btrfs-pool/.snapshots/subvol7-containers-20251114 ro false

# Or create writable snapshot
sudo btrfs subvolume snapshot \
  /mnt/btrfs-pool/.snapshots/subvol7-containers-20251114 \
  /mnt/btrfs-pool/subvol7-containers-restored
```

---

## Quick Reference Card

### Critical Paths

**System Drive (SSD):**
```bash
~/.local/share/containers/storage/    # Podman images (8.4GB - immovable)
~/containers/config/                   # Service configs (<100MB each)
~/containers/data/                     # Application state (<500MB total)
~/containers/docs/                     # Documentation (3.3MB)
~/containers/scripts/                  # Automation scripts (300KB)
~/containers/quadlets -> ~/.config/containers/systemd/  # Symlink
~/containers/secrets/                  # Secrets (proper permissions)
~/containers/cache -> /mnt/btrfs-pool/subvol6-tmp/container-cache  # Symlink
```

**BTRFS Pool (HDD):**
```bash
/mnt/btrfs-pool/subvol4-multimedia/    # Jellyfin media (5.2TB, ro recommended)
/mnt/btrfs-pool/subvol5-music/         # Music (1.1TB, ro recommended)
/mnt/btrfs-pool/subvol3-opptak/        # Recordings (2.0TB)
/mnt/btrfs-pool/subvol2-pics/          # Photos (42GB)
/mnt/btrfs-pool/subvol1-docs/          # Documents (12GB)
/mnt/btrfs-pool/subvol6-tmp/           # Temp/cache (6.5GB)
/mnt/btrfs-pool/subvol7-containers/    # Container data (3GB → should be 7-8GB after migrations)
```

### Essential Commands

```bash
# Quick capacity check
df -h / /mnt/btrfs-pool

# What's eating system drive?
du -h ~/ 2>/dev/null | sort -h | tail -15

# Container storage status
podman system df

# Journal log usage
journalctl --user --disk-usage

# NOCOW verification
lsattr -d /mnt/btrfs-pool/subvol7-containers/*

# Set NOCOW on new directory
mkdir -p /path/to/db && chattr +C /path/to/db

# Emergency cleanup combo
podman system prune --all --force && journalctl --user --vacuum-size=500M
```

---

## Decision Workflow Example

**Scenario:** Deploying Nextcloud with PostgreSQL database (expected 5GB data, 2GB DB)

1. **Nextcloud data:** 5GB expected
   - > 500MB → BTRFS pool
   - Path: `/mnt/btrfs-pool/subvol7-containers/nextcloud-data`
   - NOCOW: NO (files, not database)

2. **PostgreSQL database:** 2GB expected
   - > 500MB → BTRFS pool
   - **Database → NOCOW required**
   - Path: `/mnt/btrfs-pool/subvol7-containers/postgresql-nextcloud`
   - **Create with `chattr +C` BEFORE first use**

3. **Nextcloud config:** ~50MB expected
   - < 100MB → System drive OK
   - Path: `~/containers/config/nextcloud`

4. **Quadlet definitions:** Always system drive
   - Path: `~/.config/containers/systemd/nextcloud.container`
   - Path: `~/.config/containers/systemd/postgresql-nextcloud.container`

---

## Revision History

| Date | Change | Reason |
|------|--------|--------|
| 2025-11-09 | Initial version created | Basic structure documented |
| 2025-11-14 | **Major update - comprehensive guide** | System drive at 81% critical |
| | Measured actual current state | Real data from production system |
| | Identified 4.6GB Jellyfin config issue | Priority 1 migration needed |
| | Documented NOCOW requirements | Loki missing NOCOW optimization |
| | Added decision matrices | Provide clear guidance for future |
| | Created migration priorities | Urgent cleanup plan established |
| 2025-12-09 | **BTRFS RAID5 → Single profile conversion** | Major storage architecture change |
| | Updated capacity: 14.56 TiB total, 6.37 TiB free | RAID5 → Single freed 1.8 TiB |
| | Documented Single profile with RAID1 metadata | Metadata redundancy critical |
| | Enhanced backup strategy section | Backups now primary data protection |
| | Added RTO/RPO targets | Single profile requires clear recovery expectations |
| | Updated physical layout table | Shows current chunk distribution |
| | Explained RAID5 → Single migration rationale | Operational issues + capacity constraints |

---

**Status:** Authoritative guide for all storage decisions
**Owner:** Homelab infrastructure (patriark)
**Next Review:** 2026-01-09 (monthly) or when system drive >75%

**Storage Profile:** Single (data) + RAID1 (metadata) - Backups are primary data protection
