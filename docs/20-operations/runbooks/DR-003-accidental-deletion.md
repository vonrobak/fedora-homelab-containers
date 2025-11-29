# DR-003: Accidental Deletion Recovery

**Severity:** Medium
**RTO Target:** 5-30 minutes
**RPO Target:** Up to 1 day (daily snapshots)
**Last Tested:** 2025-11-30
**Success Rate:** Not yet tested in production

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

## Prerequisites

- [ ] BTRFS snapshots exist for affected subvolume
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

### Step 2: List Available Snapshots

**For home directory:**
```bash
ls -lt $HOME/.snapshots/htpc-home/
```

**For BTRFS pool subvolumes:**
```bash
# Documents
ls -lt /mnt/btrfs-pool/.snapshots/subvol1-docs/

# Photos
ls -lt /mnt/btrfs-pool/.snapshots/subvol2-pics/

# Media (opptak)
ls -lt /mnt/btrfs-pool/.snapshots/subvol3-opptak/

# Containers
ls -lt /mnt/btrfs-pool/.snapshots/subvol7-containers/
```

**For system root (if external drive mounted):**
```bash
ls -lt /run/media/patriark/WD-18TB/.snapshots/htpc-root/
```

**Snapshot naming format:** `YYYYMMDD-subvolume` (e.g., `20251130-docs`)

### Step 3: Find Deleted File in Snapshot

Determine when file was last known to exist, then search snapshots:

```bash
# Find file in specific snapshot
find $HOME/.snapshots/htpc-home/20251130/ -name "important-file.txt"

# Search across multiple recent snapshots
for snapshot in $(ls -t $HOME/.snapshots/htpc-home/ | head -7); do
    echo "=== Checking $snapshot ==="
    find $HOME/.snapshots/htpc-home/$snapshot -name "important-file.txt"
done

# Find directory in snapshot
find /mnt/btrfs-pool/.snapshots/subvol1-docs/20251130/ -type d -name "project-folder"
```

### Step 4: Verify File Integrity

Before restoring, verify the file in the snapshot is the correct version:

```bash
# Check file size and modification time
ls -lh $HOME/.snapshots/htpc-home/20251130/path/to/file.txt

# Preview file contents (for text files)
head -20 $HOME/.snapshots/htpc-home/20251130/path/to/file.txt

# Calculate checksum for verification
sha256sum $HOME/.snapshots/htpc-home/20251130/path/to/file.txt
```

### Step 5: Restore File or Directory

**Restore single file:**
```bash
# Copy file back to original location (preserves permissions)
cp -a $HOME/.snapshots/htpc-home/20251130/path/to/file.txt \
      $HOME/path/to/file.txt

# Verify restoration
ls -lh $HOME/path/to/file.txt
```

**Restore directory:**
```bash
# Restore entire directory with all contents
cp -a $HOME/.snapshots/htpc-home/20251130/path/to/directory/ \
      $HOME/path/to/directory/

# Verify contents
ls -R $HOME/path/to/directory/
```

**Restore specific files from directory:**
```bash
# Restore only certain file types
cp -a $HOME/.snapshots/htpc-home/20251130/Documents/*.pdf \
      $HOME/Documents/

# Restore files modified within date range
find $HOME/.snapshots/htpc-home/20251130/Documents/ \
    -type f -newermt "2025-11-01" ! -newermt "2025-11-30" \
    -exec cp -a {} $HOME/Documents/ \;
```

### Step 6: Verify Restored Data

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

# Try different snapshot
cp -a $HOME/.snapshots/htpc-home/20251129/path/to/file.txt \
      $HOME/path/to/file.txt
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
# Use today's snapshot
TODAY=$(date +%Y%m%d)
cp -a $HOME/.snapshots/htpc-home/${TODAY}-home/path/to/file.txt \
      $HOME/path/to/file.txt
```

### Scenario B: Deleted entire project directory yesterday

```bash
# Use yesterday's snapshot
YESTERDAY=$(date -d "yesterday" +%Y%m%d)
cp -a /mnt/btrfs-pool/.snapshots/subvol1-docs/${YESTERDAY}-docs/Projects/MyProject/ \
      /mnt/btrfs-pool/subvol1-docs/Projects/MyProject/
```

### Scenario C: Need file from last week

```bash
# Find snapshots from last week
ls -lt $HOME/.snapshots/htpc-home/ | grep "$(date -d '7 days ago' +%Y%m)"

# Restore from specific date
cp -a $HOME/.snapshots/htpc-home/20251123-home/Documents/report.docx \
      $HOME/Documents/report-recovered.docx
```

### Scenario D: Accidentally deleted container config

```bash
# Find latest snapshot with config
find /mnt/btrfs-pool/.snapshots/subvol7-containers/20251130-containers/config/jellyfin/ \
    -name "*.xml"

# Restore entire config directory
cp -a /mnt/btrfs-pool/.snapshots/subvol7-containers/20251130-containers/config/jellyfin/ \
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

Already implemented via `scripts/test-backup-restore.sh`:
- Monthly automated testing
- Validates snapshot integrity
- Alerts on restoration failures

---

## Related Runbooks

- **DR-001:** System SSD Failure (for system-wide recovery)
- **DR-002:** BTRFS Pool Corruption (for storage-level failures)
- **DR-004:** Total Catastrophe (for complete data loss scenarios)

---

## Appendix: Quick Reference Commands

```bash
# List all snapshots for home
ls -lt ~/.snapshots/htpc-home/

# Find file across all snapshots
for snap in $(ls -t ~/.snapshots/htpc-home/); do
    find ~/.snapshots/htpc-home/$snap -name "filename.txt" 2>/dev/null
done

# Restore with timestamp preservation
cp -a /source/file.txt /dest/file.txt

# Restore directory recursively
cp -a /source/directory/ /dest/directory/

# Verify checksum after restore
sha256sum original_backup.txt restored.txt

# Test application after config restore
systemctl --user restart service.service && \
systemctl --user status service.service
```

---

**Last Updated:** 2025-11-30
**Maintainer:** Homelab Operations
**Review Schedule:** Quarterly
