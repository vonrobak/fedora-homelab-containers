---
type: Runbook
title: "DR-002: BTRFS Pool Corruption"
description: "Disaster-recovery runbook for BTRFS storage-pool corruption or unmountable filesystem across all subvolumes."
sensitivity: public
created: 2025-11-30
updated: 2026-07-21
---

# DR-002: BTRFS Pool Corruption

**Severity:** Critical
**RTO Target:** 6-12 hours (depends on data volume)
**RPO Target:** Up to 1 day for most subvolumes — [Urd](https://github.com/vonrobak/urd) (ADR-021)
sends nightly at 04:00. Check `urd status` for actual `last_send_age_secs` per subvolume; don't
assume a fixed window.
**Last Tested:** Not yet tested
**Success Rate:** Not yet tested in production

---

## Scenario Description

BTRFS filesystem on the storage pool becomes corrupted or unmountable, affecting all 7 pool
subvolumes tracked by Urd:
- Container configuration (`subvol7-containers`)
- Media library (`subvol3-opptak`)
- Photo library (`subvol2-pics`)
- Documents (`subvol1-docs`)
- Music (`subvol5-music`)
- Multimedia (`subvol4-multimedia`)
- Scratch/tmp (`subvol6-tmp`) — **not sent externally** (`send_enabled = false` in
  `urd.toml`); anything here that isn't reproducible elsewhere is unrecoverable by design

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
- Whatever changed since each subvolume's last successful Urd send — run `urd status` on the
  surviving system (home directory is separate from the pool) before proceeding
- `subvol6-tmp` is not sent externally at all — total loss for anything not reproducible

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

**Create all required subvolumes** (all 7 tracked in `~/.config/urd/urd.toml`):
```bash
cd /mnt/btrfs-pool

# Create subvolumes matching original structure
sudo btrfs subvolume create subvol1-docs
sudo btrfs subvolume create subvol2-pics
sudo btrfs subvolume create subvol3-opptak
sudo btrfs subvolume create subvol4-multimedia
sudo btrfs subvolume create subvol5-music
sudo btrfs subvolume create subvol6-tmp
sudo btrfs subvolume create subvol7-containers

# Create snapshot directories (Urd expects this layout — see snapshot_root in urd.toml)
sudo mkdir -p .snapshots/{subvol1-docs,subvol2-pics,subvol3-opptak,subvol4-multimedia,subvol5-music,subvol6-tmp,subvol7-containers}

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

**Restore music and multimedia (same pattern, lower priority — restore after Tier 1 if RTO is
tight):**
```bash
for name in subvol5-music subvol4-multimedia; do
    LATEST=$(ls -t /mnt/external/.snapshots/$name/ | head -1)
    sudo rsync -av --progress "/mnt/external/.snapshots/$name/$LATEST/" "/mnt/btrfs-pool/$name/"
    sudo chown -R patriark:patriark "/mnt/btrfs-pool/$name/"
done
```

`subvol6-tmp` is scratch space and isn't sent externally (`send_enabled = false`) — recreate it
empty; there's nothing to restore.

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

**Re-enable Urd backup automation** (the pool it snapshots was just recreated — it needs to
re-baseline):
```bash
urd doctor
systemctl --user enable --now urd-backup.timer
systemctl --user enable --now urd-sentinel.service
urd status
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

**Expected data loss:** whatever changed since each subvolume's last successful Urd send —
check `urd status`/`urd history` beforehand, don't assume a fixed window. All 6 backed-up pool
subvolumes send nightly; `subvol6-tmp` is never sent (total loss for anything not reproducible).

**Minimizing data loss:**
- Check if any recent local snapshots survived on a still-mountable part of the pool
- Review Git history for `~/containers` config changes
- Check if home directory has recent work files (separate from the pool, on the system SSD)

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

### Backup Frequency

Already daily for every backed-up subvolume via Urd's `send_interval = "1d"`. To tighten further,
edit the relevant subvolume's interval in `~/.config/urd/urd.toml` — `urd doctor` validates the
change before it's applied.

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
# SUBVOLNAME ∈ subvol1-docs, subvol2-pics, subvol3-opptak, subvol4-multimedia,
#              subvol5-music, subvol7-containers (subvol6-tmp is never sent externally)

# Restart services
systemctl --user daemon-reload
systemctl --user start traefik.service

# Re-enable Urd against the recreated pool
urd doctor
systemctl --user enable --now urd-backup.timer

# Verify
sudo btrfs scrub start /mnt/btrfs-pool
df -h /mnt/btrfs-pool
podman ps
urd status
```

---

**Last Updated:** 2026-07-21 (Rewritten around Urd — ADR-021 superseded `btrfs-snapshot-backup.sh` on 2026-03-25)
**Maintainer:** Homelab Operations
**Review Schedule:** Quarterly
**Next Test:** Not yet scheduled
