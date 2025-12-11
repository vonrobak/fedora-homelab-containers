# Tier 3 Initial Backup Guide

**Date:** 2025-12-10
**Purpose:** Manual initial backup for large Tier 3 subvolumes
**Status:** Operational Guide

---

## Overview

This guide covers the manual initial backup process for **subvol4-multimedia** (5.8 TB), the largest volume in Tier 3. After the initial backup completes, incremental backups will be much faster and can be handled automatically by the weekly backup script.

**Why Manual Initial Backup?**
- **subvol4-multimedia**: 5.8 TB → Estimated **27 hours** for first backup
- Allows you to monitor the long-running operation
- Prevents automated backup timeout failures
- You can choose optimal timing (e.g., weekend when system load is low)

---

## Prerequisites

### Before You Begin

**1. Verify External Drive Available:**
```bash
df -h /run/media/patriark/WD-18TB
```
Should show WD-18TB drive mounted with sufficient free space (need ~5.8 TB).

**2. Verify BTRFS Pool Health:**
```bash
sudo btrfs filesystem show /mnt/btrfs-pool
sudo btrfs device stats /mnt/btrfs-pool
```
All device stats should show zero errors.

**3. Check Current Disk Space:**
```bash
du -sh /mnt/btrfs-pool/subvol4-multimedia
du -sh /run/media/patriark/WD-18TB/.snapshots
```

**4. Verify No Snapshots Exist Yet:**
```bash
ls -la /mnt/btrfs-pool/.snapshots/subvol4-multimedia/ 2>/dev/null
ls -la /run/media/patriark/WD-18TB/.snapshots/subvol4-multimedia/ 2>/dev/null
```
Both should be empty or not exist.

---

## Step 1: Create Local Snapshot

Create the first read-only snapshot on the local BTRFS pool:

```bash
# Create snapshot directory if it doesn't exist
sudo mkdir -p /mnt/btrfs-pool/.snapshots/subvol4-multimedia

# Create snapshot (read-only)
sudo btrfs subvolume snapshot -r \
  /mnt/btrfs-pool/subvol4-multimedia \
  /mnt/btrfs-pool/.snapshots/subvol4-multimedia/$(date +%Y%m%d)-multimedia

# Verify snapshot created
sudo btrfs subvolume list /mnt/btrfs-pool | grep multimedia
ls -la /mnt/btrfs-pool/.snapshots/subvol4-multimedia/
```

**Expected:** You should see one snapshot with today's date.

---

## Step 2: Initial Send to External Drive

This is the **long-running step** (~27 hours). Run in a persistent session:

### Option A: Using tmux (Recommended)

```bash
# Start tmux session
tmux new -s multimedia-backup

# Inside tmux, run the backup
sudo btrfs send \
  /mnt/btrfs-pool/.snapshots/subvol4-multimedia/$(date +%Y%m%d)-multimedia \
  | pv -ptebar \
  | sudo btrfs receive /run/media/patriark/WD-18TB/.snapshots/

# Detach from tmux: Ctrl+B, then D
# Reattach later: tmux attach -t multimedia-backup
```

**pv flags explained:**
- `-p` = progress bar
- `-t` = timer (elapsed time)
- `-e` = ETA (estimated time remaining)
- `-b` = bytes transferred
- `-a` = average transfer rate
- `-r` = current transfer rate

### Option B: Using nohup (Background)

```bash
# Run in background with log output
nohup sudo sh -c "btrfs send /mnt/btrfs-pool/.snapshots/subvol4-multimedia/$(date +%Y%m%d)-multimedia | \
  pv -ptebar | \
  btrfs receive /run/media/patriark/WD-18TB/.snapshots/" \
  > ~/containers/data/backup-logs/multimedia-initial-backup-$(date +%Y%m%d).log 2>&1 &

# Save the process ID
echo $! > /tmp/multimedia-backup.pid

# Monitor progress
tail -f ~/containers/data/backup-logs/multimedia-initial-backup-$(date +%Y%m%d).log
```

---

## Step 3: Monitor Progress

### While Backup is Running

**Check process status:**
```bash
# If using tmux
tmux attach -t multimedia-backup

# If using nohup
ps aux | grep "btrfs send"
tail -f ~/containers/data/backup-logs/multimedia-initial-backup-$(date +%Y%m%d).log
```

**Monitor disk I/O:**
```bash
# Watch transfer speed
iostat -x 5 sda sdb sdc sdd

# Monitor process I/O
PID=$(pgrep -f "btrfs send")
cat /proc/$PID/io
```

**Estimate time remaining:**
```bash
# Get current size transferred
du -sh /run/media/patriark/WD-18TB/.snapshots/subvol4-multimedia/

# Calculate: (5.8 TB - current_size) / transfer_rate
# Example: If you've transferred 1 TB in 5 hours
# Transfer rate: 1 TB / 5h = 0.2 TB/h = ~56 MB/s
# Remaining: (5.8 - 1) / 0.2 = 24 hours
```

### Expected Transfer Rate

Based on subvol3-opptak experience (2.1 TiB in 9h 40m):
- **Average:** ~60 MB/s
- **Best case:** ~80 MB/s (if no other I/O)
- **Worst case:** ~40 MB/s (if system busy)

---

## Step 4: Verify Backup Completed

**After backup finishes (wait for command to exit):**

```bash
# Verify snapshot exists on external drive
ls -la /run/media/patriark/WD-18TB/.snapshots/subvol4-multimedia/

# Compare sizes (should be identical)
sudo btrfs subvolume show /mnt/btrfs-pool/.snapshots/subvol4-multimedia/$(date +%Y%m%d)-multimedia
sudo btrfs subvolume show /run/media/patriark/WD-18TB/.snapshots/subvol4-multimedia/$(date +%Y%m%d)-multimedia

# Verify snapshot is read-only on both locations
# Should show "Flags: readonly" for both
```

**Check for errors:**
```bash
# Review backup log (if using nohup)
grep -i error ~/containers/data/backup-logs/multimedia-initial-backup-*.log
```

---

## Step 5: Enable Automatic Backups

**After successful initial backup**, enable automatic external backups in the script:

```bash
# Edit backup script
nano ~/containers/scripts/btrfs-snapshot-backup.sh

# Find line ~149 and change:
# FROM: TIER3_MULTIMEDIA_EXTERNAL_ENABLED=false
# TO:   TIER3_MULTIMEDIA_EXTERNAL_ENABLED=true

# Save and exit (Ctrl+O, Enter, Ctrl+X)
```

**Verify change:**
```bash
grep "TIER3_MULTIMEDIA_EXTERNAL_ENABLED" ~/containers/scripts/btrfs-snapshot-backup.sh
```

Should show: `TIER3_MULTIMEDIA_EXTERNAL_ENABLED=true`

---

## Step 6: Test Next Incremental Backup

**Wait until next Saturday** (or trigger manually) to verify incremental backups work:

```bash
# Test manual incremental backup (dry-run first)
~/containers/scripts/btrfs-snapshot-backup.sh --tier 3 --subvolume multimedia --verbose --dry-run

# If dry-run looks good, run for real
~/containers/scripts/btrfs-snapshot-backup.sh --tier 3 --subvolume multimedia --verbose
```

**Expected:** Incremental backup should be much faster (only changes since last snapshot).

---

## Troubleshooting

### Backup Stuck or Very Slow

**Check for competing I/O:**
```bash
iotop -o  # Show processes doing I/O
```

**Pause other services temporarily:**
```bash
systemctl --user stop jellyfin.service immich-server.service
# Resume after backup: systemctl --user start jellyfin.service immich-server.service
```

### Out of Space on External Drive

**Check available space:**
```bash
df -h /run/media/patriark/WD-18TB
```

**If low, delete old snapshots from other subvolumes:**
```bash
# List old snapshots
find /run/media/patriark/WD-18TB/.snapshots -type d -name "2025*" | sort

# Delete specific old snapshot (be careful!)
sudo btrfs subvolume delete /run/media/patriark/WD-18TB/.snapshots/subvol3-opptak/20250420-opptak
```

### Backup Failed Mid-Transfer

**Cleanup incomplete transfer:**
```bash
# Check if partial subvolume exists
ls -la /run/media/patriark/WD-18TB/.snapshots/subvol4-multimedia/

# Delete incomplete snapshot
sudo btrfs subvolume delete /run/media/patriark/WD-18TB/.snapshots/subvol4-multimedia/YYYYMMDD-multimedia

# Restart from Step 2
```

### Process Died / Lost Session

**Find if backup is still running:**
```bash
ps aux | grep "btrfs send"
ps aux | grep "btrfs receive"
```

**If still running, monitor with:**
```bash
# Get PID of btrfs receive
PID=$(pgrep -f "btrfs receive")

# Watch its I/O
watch -n 5 "cat /proc/$PID/io | grep -E 'read_bytes|write_bytes'"

# Check destination size growth
watch -n 60 "du -sh /run/media/patriark/WD-18TB/.snapshots/subvol4-multimedia/"
```

**If not running and backup incomplete, restart from Step 2.**

---

## Estimated Timeline

| Phase | Duration | Notes |
|-------|----------|-------|
| **Step 1: Create snapshot** | ~2 minutes | Fast, local BTRFS operation |
| **Step 2: Send to external** | **~27 hours** | Main time sink (5.8 TB transfer) |
| **Step 3: Monitor** | Periodic checks | Check every few hours |
| **Step 4: Verify** | ~5 minutes | Post-transfer validation |
| **Step 5: Enable auto** | ~2 minutes | Edit configuration |
| **Total** | **~27-28 hours** | Plan for a weekend |

---

## Music and Tmp Volumes

**subvol5-music (1.1 TB) and subvol6-tmp (6.2 GB)** are also new to Tier 3:

**subvol5-music initial backup:**
- Estimated time: ~5 hours
- Can run automatically via weekly backup (within 48h timeout)
- **OR** follow same manual process if you prefer to monitor it

**subvol6-tmp initial backup:**
- Estimated time: ~6 minutes
- Runs automatically, no manual intervention needed

**Recommendation for subvol5-music:**
- Let weekly backup handle it automatically (Saturday 04:00)
- Or run manual backup if you want to ensure it completes before multimedia

---

## Post-Backup Monitoring

**After all Tier 3 initial backups complete:**

```bash
# Check all Tier 3 snapshots exist
ls -la /mnt/btrfs-pool/.snapshots/subvol2-pics/
ls -la /mnt/btrfs-pool/.snapshots/subvol4-multimedia/
ls -la /mnt/btrfs-pool/.snapshots/subvol5-music/
ls -la /mnt/btrfs-pool/.snapshots/subvol6-tmp/

# Check external backups
ls -la /run/media/patriark/WD-18TB/.snapshots/subvol2-pics/
ls -la /run/media/patriark/WD-18TB/.snapshots/subvol4-multimedia/
ls -la /run/media/patriark/WD-18TB/.snapshots/subvol5-music/
ls -la /run/media/patriark/WD-18TB/.snapshots/subvol6-tmp/

# Monitor next Saturday's automatic backup
journalctl --user -u btrfs-backup-weekly.service -f
```

---

## Automation Status After Initial Backup

**Tier 3 Backup Schedule (after manual initial backup):**
- **Local snapshots:** Weekly (Saturdays)
- **External backup:** Monthly (first Saturday of month)
- **Timeout:** 48 hours (enough for incremental backups)

**Expected incremental backup times:**
- subvol2-pics: ~5 minutes (42 GB + changes)
- subvol4-multimedia: ~30-60 minutes (only changed/new media)
- subvol5-music: ~15-30 minutes (only new music)
- subvol6-tmp: ~2 minutes (cache data)

**Total expected time for monthly Tier 3 external backup (after initial):**
- ~1-2 hours (vs 32 hours for initial!)

---

## Revision History

| Date | Change | Reason |
|------|--------|--------|
| 2025-12-10 | Initial version created | Guide for Tier 3 initial backups |
| | Documented subvol4-multimedia process | 5.8 TB volume requires manual handling |
| | Added troubleshooting section | Common issues during long transfers |
| | Included monitoring commands | Help track 27-hour backup progress |

---

**Status:** Operational guide for one-time setup
**Owner:** Homelab infrastructure (patriark)
**Next Review:** After first manual backup completes

**Important:** After initial backup succeeds, set `TIER3_MULTIMEDIA_EXTERNAL_ENABLED=true` in backup script!
