---
type: Runbook
title: "DR-003: Accidental Deletion Recovery"
description: "Disaster-recovery runbook for recovering accidentally deleted files or directories from daily snapshots and external backups."
sensitivity: public
created: 2025-11-30
updated: 2026-07-21
---

# DR-003: Accidental Deletion Recovery

**Severity:** Medium
**RTO Target:** 5-30 minutes
**RPO Target:** Up to 1 day (daily snapshots, managed by [Urd](https://github.com/vonrobak/urd))
**Last Tested:** 2026-01-03 (pre-Urd; mechanism unchanged post-migration)
**Success Rate:** 100% (verified external backup restore)

---

## Scenario Description

User accidentally deletes important files or directories from:
- Home directory (`/home/patriark`)
- Document storage (`/mnt/btrfs-pool/subvol1-docs`)
- Container configuration (`/mnt/btrfs-pool/subvol7-containers`)
- Photo library (`/mnt/btrfs-pool/subvol2-pics`)
- Media library (`/mnt/btrfs-pool/subvol3-opptak`)

This could result from:
- Accidental `rm -rf` command
- Script error deleting wrong files
- Application bug removing data
- User mistake in file manager

**Snapshots and external sends are managed by [Urd](https://github.com/vonrobak/urd) (ADR-021)** — a
nightly `urd-backup.timer` (04:00) snapshots all 9 tracked subvolumes and sends deltas to two
external drives. `urd status` shows current protection state per subvolume.

## Prerequisites

- [ ] BTRFS snapshots exist for affected subvolume (`urd status` shows `PROTECTED`)
- [ ] Sufficient disk space for restore (if restoring large directories)
- [ ] Know approximate time when files were last known to exist
- [ ] Can identify file/directory names or paths

## Detection

**How to know this scenario occurred:**

- Files or directories missing from expected location
- Application reports missing configuration/data
- User reports deleted files

**Command to verify deletion:**
```bash
# Check if file exists
ls -l /path/to/missing/file

# Search for file in current location
find /home/patriark -name "missing-file.txt"

# Check if directory is empty
ls -la /path/to/directory/
```

## Impact Assessment

**What's affected:**
- Specific files/directories are unavailable
- Applications may fail if configuration files deleted
- Work/data may be lost if not recovered

**What still works:**
- All other files and systems
- Snapshot backups contain deleted data
- Read-only access to snapshots

## Recovery Procedure

### Step 1: Identify Affected Subvolume

Determine which subvolume contained the deleted files:

| Path | Subvolume |
|------|-----------|
| `/home/patriark/*` | htpc-home |
| `/mnt/btrfs-pool/subvol1-docs/*` | subvol1-docs |
| `/mnt/btrfs-pool/subvol2-pics/*` | subvol2-pics |
| `/mnt/btrfs-pool/subvol3-opptak/*` | subvol3-opptak |
| `/mnt/btrfs-pool/subvol7-containers/*` | subvol7-containers |
| `/` (system files) | htpc-root |

### Step 2: Restore a Single File with `urd get`

For a single file, skip manual snapshot browsing entirely:

```bash
# Print to stdout
urd get /home/patriark/path/to/file.txt --at 2026-01-15

# Write straight to a recovery location (doesn't touch the original path yet)
urd get /home/patriark/path/to/file.txt --at 2026-01-15 -o /tmp/recovered-file.txt

# "yesterday" and "today" work as --at values too
urd get /mnt/btrfs-pool/subvol7-containers/config/jellyfin/config.xml --at yesterday
```

`urd get` auto-detects the owning subvolume from the path; override with `--subvolume <name>`
if the path is ambiguous (e.g. a bind-mounted location). It reads from the **local** snapshot
store first — for local-pool-loss scenarios see Step 3.

### Step 3: Directory Restores / Local Pool Loss — Browse Snapshots Directly

`urd get` only retrieves single files. For whole directories, or when the local pool itself is
gone and you're restoring from an external drive, browse the snapshot tree directly. Urd names
local snapshots `YYYYMMDD-HHMM-<short_name>` under each subvolume's `snapshot_root`
(`~/containers/.config/urd/urd.toml` has the authoritative list — `urd status` shows the same
short names):

```bash
# Home directory
ls -lt $HOME/.snapshots/htpc-home/

# BTRFS pool subvolumes (docs, pics, opptak/media, containers, music, multimedia, tmp)
ls -lt /mnt/btrfs-pool/.snapshots/subvol1-docs/
ls -lt /mnt/btrfs-pool/.snapshots/subvol7-containers/

# External drive, if the local snapshot is gone (see DR-002/DR-004)
ls -lt /run/media/patriark/WD-18TB/.snapshots/subvol7-containers/
```

Find and restore a directory:

```bash
# Find a directory inside a specific snapshot
find /mnt/btrfs-pool/.snapshots/subvol1-docs/20260115-0403-docs/ \
    -type d -name "project-folder"

# Restore the whole directory (preserves permissions, COW-reflinked on BTRFS)
cp -a /mnt/btrfs-pool/.snapshots/subvol1-docs/20260115-0403-docs/Projects/MyProject/ \
      /mnt/btrfs-pool/subvol1-docs/Projects/MyProject/

# Restore only certain file types
cp -a /mnt/btrfs-pool/.snapshots/subvol1-docs/20260115-0403-docs/Documents/*.pdf \
      /mnt/btrfs-pool/subvol1-docs/Documents/
```

### Step 4: Verify File Integrity Before Restoring

```bash
# Check file size and modification time in the snapshot
ls -lh /mnt/btrfs-pool/.snapshots/subvol1-docs/20260115-0403-docs/path/to/file.txt

# Preview contents (text files)
head -20 /mnt/btrfs-pool/.snapshots/subvol1-docs/20260115-0403-docs/path/to/file.txt

# Checksum for verification
sha256sum /mnt/btrfs-pool/.snapshots/subvol1-docs/20260115-0403-docs/path/to/file.txt
```

### Step 5: Verify Restored Data

```bash
# Check file exists
ls -lh /path/to/restored/file.txt

# Verify permissions match
stat /path/to/restored/file.txt

# For text files, verify contents
cat /path/to/restored/file.txt

# For application config, test application starts
systemctl --user restart service-name.service
systemctl --user status service-name.service
```

## Verification Checklist

- [ ] File(s) restored to correct location
- [ ] File permissions preserved (match snapshot)
- [ ] File contents correct (spot check)
- [ ] Application can access restored files
- [ ] User confirms this is the correct version

## Post-Recovery Actions

- [ ] Document what was deleted and why
- [ ] Update scripts/procedures to prevent recurrence
- [ ] Consider more frequent snapshots for critical data
- [ ] Test restored files in application
- [ ] Inform affected users (if multi-user system)

## Rollback Plan

If restored file is wrong version or causes issues:

```bash
# Delete incorrectly restored file
rm /path/to/restored/file.txt

# Try a different date with urd get
urd get /home/patriark/path/to/file.txt --at 2026-01-14
```

## Estimated Timeline

- **Detection:** 1-5 minutes (depends on when deletion noticed)
- **Snapshot identification:** 2-5 minutes
- **File location in snapshot:** 2-10 minutes (depends on file organization)
- **Restore execution:** 1-5 minutes (single file), 5-30 minutes (large directory)
- **Verification:** 2-5 minutes
- **Total RTO:** 5-30 minutes

## Common Scenarios

### Scenario A: Deleted file from home directory today

```bash
urd get /home/patriark/path/to/file.txt --at today
```

### Scenario B: Deleted entire project directory yesterday

```bash
# Directories need the raw snapshot path, not urd get (single-file only)
YESTERDAY=$(date -d "yesterday" +%Y%m%d)
LATEST=$(ls -t /mnt/btrfs-pool/.snapshots/subvol1-docs/ | grep "^${YESTERDAY}" | head -1)
cp -a "/mnt/btrfs-pool/.snapshots/subvol1-docs/${LATEST}/Projects/MyProject/" \
      /mnt/btrfs-pool/subvol1-docs/Projects/MyProject/
```

### Scenario C: Need file from last week

```bash
urd get /home/patriark/Documents/report.docx --at 2026-01-08 \
  -o /home/patriark/Documents/report-recovered.docx
```

### Scenario D: Accidentally deleted container config

```bash
# Single file
urd get /mnt/btrfs-pool/subvol7-containers/config/jellyfin/config.xml --at yesterday

# Whole config directory — needs the raw snapshot path
LATEST=$(ls -t /mnt/btrfs-pool/.snapshots/subvol7-containers/ | head -1)
cp -a "/mnt/btrfs-pool/.snapshots/subvol7-containers/${LATEST}/config/jellyfin/" \
      /mnt/btrfs-pool/subvol7-containers/config/jellyfin/

# Restart service
systemctl --user restart jellyfin.service
```

---

## Prevention Measures

### Implement Safety Aliases

Add to `~/.bashrc`:
```bash
# Safer rm command - prompt before deleting
alias rm='rm -i'

# Trash command instead of permanent delete
alias trash='mv --target-directory=$HOME/.local/share/Trash/files/'
```

### Pre-Delete Verification Script

```bash
#!/bin/bash
# safe-rm.sh - Verify before deleting

if [[ $# -eq 0 ]]; then
    echo "Usage: safe-rm.sh <files/dirs>"
    exit 1
fi

echo "You are about to delete:"
for item in "$@"; do
    echo "  - $item"
    if [[ -d "$item" ]]; then
        echo "    (directory with $(find "$item" -type f | wc -l) files)"
    fi
done

read -p "Continue? (yes/no): " confirm
if [[ "$confirm" == "yes" ]]; then
    rm -rf "$@"
    echo "Deleted."
else
    echo "Cancelled."
fi
```

### Automated Snapshot Verification

Implemented via `scripts/test-backup-restore.sh`, run by `backup-restore-test.timer`:
- Weekly automated testing (Sundays)
- Samples files per subvolume, restores to `subvol6-tmp` scratch space, and checksum-verifies
- Alerts on restoration failures

Separately, `urd verify` checks incremental send-chain integrity and drive pin health directly:
```bash
urd verify --detail
```

### External Backup Restore Verified

**Test Date:** 2026-01-03 (pre-Urd; the mechanism this validated — `btrfs send`/`receive` off an
external drive's read-only snapshot — is unchanged post-migration, only the naming convention
around each snapshot directory changed: `YYYYMMDD-shortname` then, `YYYYMMDD-HHMM-shortname` now)
**Test Scope:** Restored subvol7-containers (81,716 files) from external drive
**Result:** ✅ Success - All files restored correctly with proper permissions
**Procedure Verified:** BTRFS send/receive from WD-18TB external drive works correctly

**Test evidence:**
```bash
# Restored from external drive
sudo btrfs send /run/media/patriark/WD-18TB/.snapshots/subvol7-containers/20260103-containers | \
  sudo btrfs receive /mnt/btrfs-pool/subvol6-tmp/99-outbound/snapshot-restore-test/

# Verification: 81,716 files restored, readonly snapshot, correct UUIDs
# Cleanup: Successfully deleted after verification
```

**Conclusion:** External backups are proven restorable. Hardware failure scenarios (DR-001, DR-002) have verified recovery paths.

---

## Related Runbooks

- **DR-001:** System SSD Failure (for system-wide recovery)
- **DR-002:** BTRFS Pool Corruption (for storage-level failures)
- **DR-004:** Total Catastrophe (for complete data loss scenarios)

---

## Appendix: Quick Reference Commands

```bash
# Restore a single file to stdout or a chosen path
urd get /path/to/file.txt --at 2026-01-15
urd get /path/to/file.txt --at yesterday -o /tmp/recovered.txt

# Check subvolume protection state and snapshot counts
urd status

# Check incremental chain integrity
urd verify --detail

# Browse recent backup runs (or just failures)
urd history --last 20
urd history --failures

# List all local snapshots for home (directory restores)
ls -lt ~/.snapshots/htpc-home/

# Restore directory recursively from a snapshot path
cp -a /source/directory/ /dest/directory/

# Verify checksum after restore
sha256sum original_backup.txt restored.txt

# Test application after config restore
systemctl --user restart service.service && \
systemctl --user status service.service
```

---

**Last Updated:** 2026-07-21 (Rewritten around Urd — ADR-021 superseded `btrfs-snapshot-backup.sh` on 2026-03-25)
**Maintainer:** Homelab Operations
**Review Schedule:** Quarterly
