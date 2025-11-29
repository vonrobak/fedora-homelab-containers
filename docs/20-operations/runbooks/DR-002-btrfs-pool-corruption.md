# DR-002: BTRFS Pool Corruption

**Severity:** Critical
**RTO Target:** 6-12 hours (depends on data volume)
**RPO Target:** Up to 7 days (Tier 1), up to 30 days (Tier 3)
**Last Tested:** Not yet tested
**Success Rate:** Not yet tested in production

---

## Scenario Description

BTRFS filesystem on the storage pool becomes corrupted or unmountable, affecting:
- `/mnt/btrfs-pool` (all subvolumes)
- Container configuration (`subvol7-containers`)
- Media library (`subvol3-opptak`)
- Photo library (`subvol2-pics`)
- Documents (`subvol1-docs`)

This could result from:
- Power outage during write operations
- Hardware failure (disk controller, cable)
- Kernel panic during filesystem operations
- Metadata corruption
- Physical drive damage
- Software bugs in BTRFS driver

**Impact:** All data on BTRFS pool inaccessible, services that depend on it offline.

## Prerequisites

- [ ] External backup drive accessible (WD-18TB)
- [ ] System still bootable (home directory intact)
- [ ] Sufficient time for large data restore (hours to days)
- [ ] Network connectivity for any missing packages
- [ ] This runbook accessible

## Detection

**How to know this scenario occurred:**

- Cannot mount BTRFS pool: `mount: wrong fs type, bad option, bad superblock`
- BTRFS errors in dmesg: `BTRFS error`, `parent transid verify failed`
- Services fail to start (missing `/mnt/btrfs-pool`)
- `df` shows BTRFS pool missing
- `btrfs check` reports errors

**Verification steps:**
```bash
# Try to mount
sudo mount /dev/mapper/btrfs-pool /mnt/btrfs-pool
# If fails → corruption detected

# Check dmesg for BTRFS errors
sudo dmesg | grep -i btrfs | tail -50

# Check filesystem (READ-ONLY check first!)
sudo btrfs check --readonly /dev/mapper/btrfs-pool

# Check device status
sudo btrfs device stats /dev/mapper/btrfs-pool
```

## Impact Assessment

**What's affected:**
- **All container services** - config/data on BTRFS pool
- Media library (Jellyfin, Immich)
- Photo library
- Documents
- Any services using BTRFS pool storage

**What still works:**
- System boots (OS on separate NVMe SSD)
- Home directory (`/home/patriark`)
- External backup drive (has all data)
- Network connectivity

**Data loss risk:**
- Last 7 days for Tier 1 data (containers, opptak)
- Last 7-30 days for Tier 2/3 data (docs, pics)

## Recovery Procedure

### Step 1: Assess Damage and Backup Current State

**DO NOT attempt repair yet - assess first:**

```bash
# Check BTRFS status (READ-ONLY)
sudo btrfs check --readonly /dev/mapper/btrfs-pool 2>&1 | tee ~/btrfs-check-readonly.log

# Check device stats
sudo btrfs device stats /dev/mapper/btrfs-pool 2>&1 | tee ~/btrfs-device-stats.log

# Check dmesg
sudo dmesg | grep -i btrfs > ~/btrfs-dmesg.log

# Review logs
less ~/btrfs-check-readonly.log
```

**Evaluate corruption severity:**
- **Minor:** Few checksum errors, metadata mostly intact → Try repair
- **Moderate:** Many errors, some subvolumes accessible → Selective recovery
- **Severe:** Cannot mount, extensive corruption → Reformat and restore from backup

### Step 2: Attempt Recovery (Minor to Moderate Corruption Only)

**⚠️ WARNING:** `btrfs check --repair` can make things worse! Only use if:
- You have complete backups
- Read-only check shows specific fixable issues
- You accept risk of data loss

**Attempt repair (DESTRUCTIVE):**
```bash
# Ensure filesystem is NOT mounted
sudo umount /mnt/btrfs-pool 2>/dev/null || true

# Run repair (this modifies the filesystem!)
sudo btrfs check --repair /dev/mapper/btrfs-pool 2>&1 | tee ~/btrfs-repair.log

# If repair completes without errors
sudo mount /dev/mapper/btrfs-pool /mnt/btrfs-pool

# Verify mount successful
df -h /mnt/btrfs-pool

# Check subvolumes
sudo btrfs subvolume list /mnt/btrfs-pool

# Run scrub to detect remaining issues
sudo btrfs scrub start /mnt/btrfs-pool
sudo btrfs scrub status /mnt/btrfs-pool
```

**If repair succeeds:**
- Immediately backup all data to external drive
- Run full system diagnostics
- Monitor for recurring errors
- Consider replacing hardware if errors persist

**If repair fails or makes things worse:**
- Proceed to Step 3 (reformat and restore)

### Step 3: Prepare for Reformat and Restore

**Mount external backup drive:**
```bash
# Connect external drive
lsblk

# Unlock LUKS
sudo cryptsetup open /dev/sdX WD-18TB

# Mount
sudo mount /dev/mapper/WD-18TB /mnt/external

# Verify backups present
ls -lh /mnt/external/.snapshots/
```

**Document what will be lost:**
```bash
# Check dates of latest backups
ls -lt /mnt/external/.snapshots/subvol7-containers/ | head -5
ls -lt /mnt/external/.snapshots/subvol3-opptak/ | head -5
ls -lt /mnt/external/.snapshots/subvol1-docs/ | head -5
ls -lt /mnt/external/.snapshots/subvol2-pics/ | head -5

# Calculate data loss window
echo "Today: $(date '+%Y-%m-%d')"
echo "Latest containers backup: $(ls -t /mnt/external/.snapshots/subvol7-containers/ | head -1)"
# ... repeat for other subvolumes
```

### Step 4: Reformat BTRFS Pool

**⚠️ DESTRUCTIVE:** This permanently destroys all data on the pool!

```bash
# Ensure nothing mounted
sudo umount /mnt/btrfs-pool 2>/dev/null || true

# Reformat with BTRFS
sudo mkfs.btrfs -f -L btrfs-pool /dev/mapper/btrfs-pool

# Mount new filesystem
sudo mount /dev/mapper/btrfs-pool /mnt/btrfs-pool

# Verify mount
df -h /mnt/btrfs-pool
```

### Step 5: Recreate Subvolume Structure

**Create all required subvolumes:**
```bash
cd /mnt/btrfs-pool

# Create subvolumes matching original structure
sudo btrfs subvolume create subvol1-docs
sudo btrfs subvolume create subvol2-pics
sudo btrfs subvolume create subvol3-opptak
sudo btrfs subvolume create subvol7-containers

# Create snapshot directories
sudo mkdir -p .snapshots/subvol1-docs
sudo mkdir -p .snapshots/subvol2-pics
sudo mkdir -p .snapshots/subvol3-opptak
sudo mkdir -p .snapshots/subvol7-containers

# Set ownership
sudo chown -R patriark:patriark .

# Verify structure
ls -la /mnt/btrfs-pool/
sudo btrfs subvolume list /mnt/btrfs-pool/
```

### Step 6: Restore Tier 1 Data (Priority: Containers)

**Restore container configuration (critical for services):**
```bash
# Find latest containers backup
LATEST_CONTAINERS=$(ls -t /mnt/external/.snapshots/subvol7-containers/ | head -1)
echo "Restoring from: $LATEST_CONTAINERS"

# Restore data
sudo cp -av /mnt/external/.snapshots/subvol7-containers/$LATEST_CONTAINERS/* \
            /mnt/btrfs-pool/subvol7-containers/

# Fix ownership
sudo chown -R patriark:patriark /mnt/btrfs-pool/subvol7-containers/

# Verify critical files present
ls -lh /mnt/btrfs-pool/subvol7-containers/config/
ls -lh /mnt/btrfs-pool/subvol7-containers/data/

# Apply NOCOW attribute to database directories (performance)
sudo chattr +C /mnt/btrfs-pool/subvol7-containers/data/prometheus
sudo chattr +C /mnt/btrfs-pool/subvol7-containers/data/grafana
sudo chattr +C /mnt/btrfs-pool/subvol7-containers/data/loki

# Verify NOCOW set
lsattr -d /mnt/btrfs-pool/subvol7-containers/data/prometheus
```

### Step 7: Restore Tier 1 Data (Media Library)

**Restore opptak/media library:**
```bash
# Find latest opptak backup
LATEST_OPPTAK=$(ls -t /mnt/external/.snapshots/subvol3-opptak/ | head -1)
echo "Restoring from: $LATEST_OPPTAK"

# This will take HOURS for 2TB - run in tmux/screen
tmux new -s restore-opptak

# Restore with progress
sudo rsync -av --progress \
     /mnt/external/.snapshots/subvol3-opptak/$LATEST_OPPTAK/ \
     /mnt/btrfs-pool/subvol3-opptak/

# Fix ownership
sudo chown -R patriark:patriark /mnt/btrfs-pool/subvol3-opptak/

# Verify key directories
ls -lh /mnt/btrfs-pool/subvol3-opptak/
```

**Note:** Can detach from tmux with `Ctrl+B, D` and reattach later with `tmux attach -t restore-opptak`

### Step 8: Restore Tier 2/3 Data (Documents, Photos)

**Restore documents:**
```bash
LATEST_DOCS=$(ls -t /mnt/external/.snapshots/subvol1-docs/ | head -1)

sudo cp -av /mnt/external/.snapshots/subvol1-docs/$LATEST_DOCS/* \
            /mnt/btrfs-pool/subvol1-docs/

sudo chown -R patriark:patriark /mnt/btrfs-pool/subvol1-docs/
```

**Restore photos (large, ~500GB):**
```bash
LATEST_PICS=$(ls -t /mnt/external/.snapshots/subvol2-pics/ | head -1)

# Run in tmux for long operation
tmux new -s restore-pics

sudo rsync -av --progress \
     /mnt/external/.snapshots/subvol2-pics/$LATEST_PICS/ \
     /mnt/btrfs-pool/subvol2-pics/

sudo chown -R patriark:patriark /mnt/btrfs-pool/subvol2-pics/
```

### Step 9: Restart Services

**Update fstab if needed:**
```bash
# Verify BTRFS pool in fstab
grep btrfs-pool /etc/fstab

# If UUID changed after reformat, update fstab
sudo blkid /dev/mapper/btrfs-pool
sudo vim /etc/fstab  # Update UUID if needed
```

**Restart container services:**
```bash
# Reload systemd to pick up restored configs
systemctl --user daemon-reload

# Start critical services
systemctl --user start traefik.service
systemctl --user start prometheus.service
systemctl --user start grafana.service
systemctl --user start jellyfin.service

# Check status
systemctl --user status traefik.service
podman ps

# View logs
journalctl --user -u traefik.service -f
```

### Step 10: Verify Data Integrity

**Check restored data:**
```bash
# Verify containers config
ls -lh ~/containers/config/
ls -lh /mnt/btrfs-pool/subvol7-containers/config/

# Check media library
du -sh /mnt/btrfs-pool/subvol3-opptak/

# Test services
curl -f http://localhost:3000/  # Grafana
curl -f http://localhost:9090/  # Prometheus

# Run diagnostics
~/containers/scripts/homelab-intel.sh
```

**Run BTRFS scrub on new filesystem:**
```bash
sudo btrfs scrub start /mnt/btrfs-pool
sudo btrfs scrub status /mnt/btrfs-pool

# Should show 0 errors on fresh filesystem
```

## Verification Checklist

- [ ] BTRFS pool mounted successfully
- [ ] All 4 subvolumes present and accessible
- [ ] Container configs restored
- [ ] Media library restored (or restore in progress)
- [ ] Documents restored
- [ ] Photos restored (or restore in progress)
- [ ] All container services running
- [ ] Web services accessible (Grafana, Jellyfin, etc.)
- [ ] BTRFS scrub shows 0 errors
- [ ] Backup automation re-enabled

## Post-Recovery Actions

- [ ] **Immediate:**
  - Complete any long-running restores (opptak, pics)
  - Run full backup to external drive
  - Test all critical services end-to-end
  - Document total downtime and recovery time

- [ ] **Within 24 hours:**
  - Review what data was lost (7-30 days)
  - Root cause analysis (why did corruption occur?)
  - Check hardware (SMART, cables, controller)
  - Update this runbook with actual experience

- [ ] **Within 1 week:**
  - Replace failed hardware if identified
  - Implement preventive measures (UPS, monitoring)
  - Consider increasing backup frequency
  - Test restored services under normal load

## Rollback Plan

If restore fails or data integrity issues found:

1. **Preserve restore attempt:**
   ```bash
   sudo btrfs subvolume snapshot /mnt/btrfs-pool/subvol7-containers \
        /mnt/btrfs-pool/subvol7-containers-restore-attempt
   ```

2. **Try different backup date:**
   ```bash
   PREV_BACKUP=$(ls -t /mnt/external/.snapshots/subvol7-containers/ | head -2 | tail -1)
   sudo cp -av /mnt/external/.snapshots/subvol7-containers/$PREV_BACKUP/* \
               /mnt/btrfs-pool/subvol7-containers/
   ```

3. **Selective file restoration:**
   - Restore only critical configs manually
   - Rebuild services from documentation
   - Restore data files as discovered missing

## Estimated Timeline

- **Assessment and backup current state:** 30-60 minutes
- **Repair attempt (if applicable):** 1-2 hours
- **Reformat and recreate structure:** 15-30 minutes
- **Restore containers (Tier 1, ~100GB):** 30-60 minutes
- **Restore opptak (Tier 1, ~2TB):** 4-8 hours
- **Restore docs (Tier 2, ~20GB):** 10-20 minutes
- **Restore photos (Tier 3, ~500GB):** 1-3 hours
- **Service restart and verification:** 30-60 minutes
- **Total RTO:** **6-12 hours** (can operate with partial restore)

**Parallel restoration:**
- Can start services after containers restored (~2 hours)
- Media restores can continue in background
- User services functional while large data restores complete

## Data Loss Window

**Expected data loss:**
- Containers: Last 7 days (weekly backup)
- Media (opptak): Last 7 days (weekly backup)
- Documents: Last 7-30 days (weekly/monthly backup)
- Photos: Last 30 days (monthly backup)

**Minimizing data loss:**
- Check if any recent local snapshots survived
- Review Git history for config changes
- Check if home directory has recent work files

## Prevention Measures

### Regular BTRFS Scrubs

**Enable monthly scrubs:**
```bash
# Add to systemd timer
sudo btrfs scrub start /mnt/btrfs-pool

# Check for errors
sudo btrfs scrub status /mnt/btrfs-pool
```

### Monitor BTRFS Health

**Add to monitoring:**
```bash
# Check BTRFS device stats in Prometheus
# Alert on:
# - write_io_errs > 0
# - read_io_errs > 0
# - flush_io_errs > 0
# - corruption_errs > 0
```

### UPS for Power Protection

**Install UPS:**
- Prevents corruption from power outages
- Allows clean shutdown during power loss
- Protects against write corruption

### Increase Backup Frequency

**For critical data:**
```bash
# Change Tier 1 to daily external backups
# Reduces RPO from 7 days to 1 day
```

### BTRFS Filesystem Options

**Mount with safety options:**
```bash
# In /etc/fstab
/dev/mapper/btrfs-pool  /mnt/btrfs-pool  btrfs  defaults,compress=zstd,autodefrag  0  0
```

## Related Runbooks

- **DR-001:** System SSD Failure (if system drive also affected)
- **DR-003:** Accidental Deletion (for recovering specific files)
- **DR-004:** Total Catastrophe (if backup drive also lost)

## Quick Reference Commands

```bash
# Check BTRFS status (safe, read-only)
sudo btrfs check --readonly /dev/mapper/btrfs-pool
sudo btrfs device stats /dev/mapper/btrfs-pool

# Attempt repair (DESTRUCTIVE!)
sudo umount /mnt/btrfs-pool
sudo btrfs check --repair /dev/mapper/btrfs-pool

# Reformat (DESTROYS ALL DATA!)
sudo mkfs.btrfs -f -L btrfs-pool /dev/mapper/btrfs-pool

# Mount external backup
sudo cryptsetup open /dev/sdX WD-18TB
sudo mount /dev/mapper/WD-18TB /mnt/external

# Restore pattern
LATEST=$(ls -t /mnt/external/.snapshots/SUBVOLNAME/ | head -1)
sudo cp -av /mnt/external/.snapshots/SUBVOLNAME/$LATEST/* /mnt/btrfs-pool/SUBVOLNAME/
sudo chown -R patriark:patriark /mnt/btrfs-pool/SUBVOLNAME/

# Restart services
systemctl --user daemon-reload
systemctl --user start traefik.service

# Verify
sudo btrfs scrub start /mnt/btrfs-pool
df -h /mnt/btrfs-pool
podman ps
```

---

**Last Updated:** 2025-11-30
**Maintainer:** Homelab Operations
**Review Schedule:** Quarterly
**Next Test:** Q2 2026 (simulated corruption on test volume)
