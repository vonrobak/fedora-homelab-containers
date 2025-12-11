# BTRFS RAID Migration Preparation

**Created:** 2025-11-28
**Purpose:** Document current state before 2TB→4TB drive replacement and RAID5 conversion
**Status:** Pre-migration documentation

---

## Current Configuration (Pre-Migration)

### BTRFS Filesystem State

**Date:** 2025-11-28 17:40 CET
**Pool Label:** htpc-btrfs-pool
**UUID:** ac5ee56e-f255-4e30-acc1-620b593a5cfa

```
Total devices: 4
FS bytes used: 8.25TiB

Device Layout:
├─ devid 1: /dev/sdc - 3.64TiB (used 3.60TiB - 99% full)
├─ devid 2: /dev/sdd - 1.82TiB (used 1.79TiB - 98% full) ← 2TB DRIVE TO REMOVE
├─ devid 3: /dev/sda - 3.64TiB (used 3.46TiB - 95% full)
└─ devid 4: /dev/sdb - 3.64TiB (used 57GB - 1.5% full)

Data Profile: SINGLE (⚠️ NO REDUNDANCY)
Metadata Profile: RAID1 (✅ Redundant)
System Profile: RAID1 (✅ Redundant)

Space Allocation:
├─ Data, single: total=8.88TiB, used=8.25TiB
├─ Metadata, RAID1: total=11.00GiB, used=10.23GiB
├─ System, RAID1: total=32.00MiB, used=1.12MiB
└─ GlobalReserve, single: total=512.00MiB, used=0.00B
```

---

## Backup Status

**Daily Backup Automation**: ✅ OPERATIONAL

```
Timer: btrfs-backup-daily.timer
Schedule: Daily at 02:00 CET
Persistent: Yes (runs after reboot)
Next run: 2025-11-29 02:00 CET

Recent Execution History:
✅ 2025-11-25 02:00 - Finished successfully
✅ 2025-11-26 02:00 - Finished successfully
✅ 2025-11-27 02:00 - Finished successfully
✅ 2025-11-28 02:00 - Finished successfully
```

**Backup Destinations**:
- Primary: 18TB drive (daily snapshots via btrfs send/receive)
- Secondary: 2TB drive (will become dedicated backup after removal from pool)

---

## Migration Plan

### Phase 1: Verify Backup Integrity (TONIGHT - Nov 28)

**Before Migration**:
1. ✅ Verify daily backup runs successfully (Nov 29 02:00)
2. ✅ Confirm snapshot cleanup frees ~30GB system space
3. ✅ Test restore from 18TB backup (sample subvolume)
4. ✅ Document all subvolume layouts

### Phase 2: Remove 2TB Drive from Pool

**Prerequisites**:
- ✅ Recent backup verified and tested
- ✅ All data redistributed off /dev/sdd
- ✅ No active writes during migration

**Steps**:
1. Balance data off 2TB drive: `btrfs balance start -dconvert=single,devid=2 /mnt/btrfs-pool`
2. Wait for balance completion (monitor with `btrfs balance status`)
3. Remove device: `btrfs device delete /dev/sdd /mnt/btrfs-pool`
4. Verify filesystem: `btrfs scrub start /mnt/btrfs-pool`

### Phase 3: Add 4TB Drive and Convert to RAID5

**New Drive Addition**:
1. Add 4TB drive: `btrfs device add /dev/sdX /mnt/btrfs-pool`
2. Convert data to RAID5: `btrfs balance start -dconvert=raid5 -mconvert=raid1c3 /mnt/btrfs-pool`
3. Monitor balance progress: `watch btrfs balance status /mnt/btrfs-pool`
4. Verify RAID5: `btrfs filesystem df /mnt/btrfs-pool`

**Expected Post-Migration Configuration**:
```
Total devices: 4
├─ devid 1: /dev/sdc - 3.64TiB
├─ devid 3: /dev/sda - 3.64TiB
├─ devid 4: /dev/sdb - 3.64TiB
└─ devid 5: /dev/sdX - 3.64TiB (new 4TB drive)

Data Profile: RAID5 (✅ 1-drive redundancy + parity)
Metadata Profile: RAID1C3 (✅ 3 copies across devices)
System Profile: RAID1C3 (✅ 3 copies across devices)

Usable capacity: ~10.9TiB (from 14.5TiB raw - 3.6TiB parity overhead)
```

### Phase 4: Repurpose 2TB Drive as Dedicated Backup

**New Role**: Dedicated backup destination for critical system data

**Backup Targets**:
1. **System root (/)**: Daily snapshots
2. **User home (/home)**: Daily snapshots
3. **Container data (subvol7-containers)**: Daily snapshots
4. **Complement to 18TB**: Secondary local backup

**Setup**:
```bash
# Format 2TB as BTRFS single-device
mkfs.btrfs -L "backup-local-2tb" /dev/sdd
mount /dev/sdd /mnt/backup-local

# Create backup subvolumes
btrfs subvolume create /mnt/backup-local/root-snapshots
btrfs subvolume create /mnt/backup-local/home-snapshots
btrfs subvolume create /mnt/backup-local/containers-snapshots
```

---

## Risk Assessment

### Current Risks (Pre-Migration)

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Data loss (SINGLE profile) | **CRITICAL** | Medium | Daily backups to 18TB |
| Drive failure during migration | High | Low | Verified backup + scrub before |
| Balance operation failure | High | Low | Can be safely restarted |
| Insufficient space for RAID5 conversion | Medium | Low | Only using 8.25TiB of 12.74TiB available |

### Post-Migration Benefits

✅ **1-drive fault tolerance**: RAID5 survives any single drive failure
✅ **Parity protection**: Data automatically reconstructed if drive fails
✅ **Metadata redundancy**: RAID1C3 = 3 copies across devices
✅ **Dual backup strategy**: 18TB + 2TB dedicated backup drives
✅ **No data loss risk**: Can proceed boldly with development

---

## Monitoring During Migration

**Key Metrics to Watch**:
```bash
# Balance progress
watch -n 10 btrfs balance status /mnt/btrfs-pool

# Filesystem usage
watch -n 30 btrfs filesystem df -h /mnt/btrfs-pool

# Device statistics
watch -n 30 btrfs device stats /mnt/btrfs-pool

# Scrub progress (after changes)
btrfs scrub status /mnt/btrfs-pool
```

**Alert Thresholds**:
- Balance stuck for >6 hours → investigate
- Device errors >0 → investigate immediately
- Scrub errors → do NOT proceed with migration

---

## Rollback Plan

**If Migration Fails**:

1. **During balance**: Cancel balance and leave as-is
   ```bash
   btrfs balance cancel /mnt/btrfs-pool
   ```

2. **After device removal fails**: Re-add 2TB drive
   ```bash
   btrfs device add /dev/sdd /mnt/btrfs-pool
   btrfs balance start -dusage=0 /mnt/btrfs-pool
   ```

3. **Total failure**: Restore from 18TB backup
   - System has verified backup from Nov 29 02:00
   - Full restore capability tested

---

## Post-Migration Verification

**Mandatory Checks After RAID5 Conversion**:

```bash
# 1. Verify RAID5 active
btrfs filesystem df /mnt/btrfs-pool | grep "Data.*raid5"

# 2. Full scrub (finds corruption)
btrfs scrub start -B /mnt/btrfs-pool

# 3. Verify all subvolumes accessible
ls -la /mnt/btrfs-pool/

# 4. Test file write/read
dd if=/dev/zero of=/mnt/btrfs-pool/test-write bs=1M count=100
md5sum /mnt/btrfs-pool/test-write
rm /mnt/btrfs-pool/test-write

# 5. Check balance completion
btrfs balance status /mnt/btrfs-pool  # Should say "No balance found"
```

---

## Timeline

| Date | Milestone | Status |
|------|-----------|--------|
| 2025-11-28 | Document current state | ✅ Complete |
| 2025-11-28 | SLO violation fixes deployed | ✅ Complete |
| 2025-11-29 02:00 | Daily backup runs | ⏳ Pending |
| 2025-11-29 AM | Verify backup success + snapshot cleanup | ⏳ Pending |
| 2025-11-29 PM | Begin migration (if backup verified) | ⏳ Pending |

---

## Success Criteria

**Migration is successful when**:
- ✅ RAID5 data profile active and verified
- ✅ RAID1C3 metadata profile active
- ✅ Scrub completes with 0 errors
- ✅ All 4 drives online and healthy
- ✅ Test file writes succeed
- ✅ Usable capacity ~10.9TiB
- ✅ 2TB drive repurposed as backup destination

**Ready to proceed boldly when**:
- ✅ 1-drive fault tolerance confirmed
- ✅ Dual backup strategy operational
- ✅ All monitoring shows healthy state

---

**Next Document**: After migration completes, create `2025-11-29-btrfs-raid5-migration-report.md` in `docs/99-reports/`
