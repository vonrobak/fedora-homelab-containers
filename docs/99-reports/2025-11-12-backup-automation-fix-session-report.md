# Session Report: Backup Automation Fix

**Date:** 2025-11-12
**Session Type:** CLI (direct system access)
**Branch:** `claude/setup-code-web-session-011CV3na5p4JGcXd9sRw8hPP`
**Duration:** ~30 minutes
**Status:** ✅ **RESOLVED**

---

## Executive Summary

**Problem:** Automated BTRFS backups failing since Nov 8 due to sudo password prompts in systemd user services.

**Solution:** Configured passwordless sudo for specific BTRFS commands via `/etc/sudoers.d/btrfs-backup`.

**Result:** Backup automation now fully operational. Next scheduled backup: Thu 2025-11-13 02:00 CET.

---

## Problem Analysis

### Symptoms Discovered
- Daily backup service: `failed (Result: exit-code)` with status=1
- Weekly backup service: Continuously restarting with same error
- Error logs: `sudo: a terminal is required to read the password`
- Last successful automated snapshot: Nov 8 (20251108-containers)
- Manual snapshots still working (created as root with sudo password)

### Root Cause
The backup script (`scripts/btrfs-snapshot-backup.sh`) uses `sudo` for BTRFS operations:
- `sudo btrfs subvolume snapshot -r` (line 213)
- `sudo btrfs send` / `sudo btrfs receive` (lines 239, 242)
- `sudo btrfs subvolume delete` (line 274)

Systemd user services run non-interactively and cannot provide password prompts, causing all automated backups to fail at the first `sudo` call.

### Timeline
- **Nov 8:** Last successful automated backup
- **Nov 9-12:** All automated backups failing silently (service shows failure)
- **Nov 12:** Issue identified and resolved in CLI session

---

## Solution Implemented

### 1. Sudoers Configuration

Created `/etc/sudoers.d/btrfs-backup` with passwordless access to specific BTRFS commands:

```
patriark ALL=(root) NOPASSWD: /usr/sbin/btrfs subvolume snapshot *
patriark ALL=(root) NOPASSWD: /usr/sbin/btrfs subvolume delete *
patriark ALL=(root) NOPASSWD: /usr/sbin/btrfs send *
patriark ALL=(root) NOPASSWD: /usr/sbin/btrfs receive *
```

**Security considerations:**
- ✅ Only specific subcommands (no `btrfs --version` or `btrfs subvolume list`)
- ✅ Absolute command path prevents PATH manipulation
- ✅ File permissions 0440 (read-only for root/wheel)
- ✅ Validated with `visudo -c` before activation
- ⚠️ User can create/delete any snapshot (acceptable for single-user homelab)

### 2. Testing Performed

| Test | Method | Result |
|------|--------|--------|
| Dry run | `--dry-run --local-only --verbose` | ✅ SUCCESS |
| Manual run | `--local-only --verbose` | ✅ SUCCESS (created 4 snapshots) |
| Systemd service | `systemctl --user start btrfs-backup-daily.service` | ✅ status=0/SUCCESS |
| File restoration | `cp` from snapshot to /tmp | ✅ WORKS |
| Next schedule | `systemctl --user list-timers` | ✅ Thu 02:00 CET |

### 3. Snapshots Created During Testing

```
20251112-htpc-home          (Tier 1: home directory)
20251112-opptak             (Tier 1: private recordings)
20251112-containers         (Tier 1: container operational data)
20251112-docs               (Tier 2: documents)
```

All snapshots verified readable and restorable.

---

## Documentation Updates

**File:** `docs/20-operations/guides/backup-strategy.md`

**Changes:**
1. Added "Prerequisites: Passwordless Sudo for BTRFS Commands" section
   - Step-by-step sudoers configuration
   - Security notes and rationale
   - Verification commands

2. Added troubleshooting entry
   - "Problem: Backup service fails with 'sudo: a password is required'"
   - Symptoms, cause, solution, and verification steps
   - Quick fix command reference

3. Updated last modified timestamp to 2025-11-12

---

## System State After Fix

### Backup Services Status

```
○ btrfs-backup-daily.service
  Status: inactive (dead) - Last run SUCCESS
  Next run: Thu 2025-11-13 02:00:00 CET

○ btrfs-backup-weekly.service
  Status: inactive (dead)
  Next run: Sun 2025-11-16 03:00:00 CET
```

### Snapshot Inventory

| Location | Count | Latest |
|----------|-------|--------|
| ~/.snapshots/htpc-home/ | 4 | 20251112-htpc-home |
| /mnt/btrfs-pool/.snapshots/subvol3-opptak/ | 3 | 20251112-opptak |
| /mnt/btrfs-pool/.snapshots/subvol7-containers/ | 3 | 20251112-containers |
| /mnt/btrfs-pool/.snapshots/subvol1-docs/ | 3 | 20251112-docs |

### Disk Space

```
System SSD (/):            89G/118G (78% - healthy)
BTRFS pool (/mnt):         8.2T/13T (65% - plenty of space)
```

---

## Lessons Learned

### What Went Well
1. **Systematic investigation** - Followed handoff checklist methodically
2. **Root cause identified quickly** - Logs clearly showed sudo password issue
3. **Minimal security impact** - Passwordless sudo limited to specific commands
4. **Comprehensive testing** - Verified dry-run, manual, automated, and restoration
5. **Documentation updated** - Future troubleshooting made easier

### What Could Be Improved
1. **Earlier monitoring** - Backup failures went unnoticed for 4 days
   - **Action:** Consider adding Prometheus alerting for backup failures
   - **Action:** Add "last successful backup" metric to Grafana
2. **Initial setup gap** - Sudoers configuration should have been documented from start
   - **Action:** Update initial deployment guide to include sudo setup

### Architecture Validation
- ✅ Rootless containers philosophy maintained (user services, not system)
- ✅ Security-conscious approach (specific commands only, not blanket NOPASSWD)
- ✅ Documentation-first culture (issue fixed AND documented)

---

## Next Steps

### Immediate (Completed)
- [x] Fix backup automation
- [x] Test restoration
- [x] Document solution
- [x] Commit changes

### Phase 2: Vaultwarden Deployment (Blocked - Now Unblocked)
- [ ] Verify backup automation continues to work overnight (Nov 13 02:00)
- [ ] Deploy Vaultwarden (now safe with working backups)
- [ ] Configure admin panel and 2FA
- [ ] Test Vaultwarden backup/restore

### Future Improvements
- [ ] Add Prometheus metrics for backup monitoring
- [ ] Create Grafana dashboard for backup status
- [ ] Set up alerting for backup failures (Discord webhook)
- [ ] Test weekly external backup (requires external drive connection)

---

## Files Modified

```
docs/20-operations/guides/backup-strategy.md  (+107 lines)
```

**System files created (outside repo):**
```
/etc/sudoers.d/btrfs-backup  (new file, 0440 permissions)
```

---

## Verification Commands for Future Reference

```bash
# Check backup service status
systemctl --user status btrfs-backup-daily.service

# View recent logs
journalctl --user -u btrfs-backup-daily.service -n 50

# List recent snapshots
ls -lth ~/.snapshots/htpc-home/ | head -5
ls -lth /mnt/btrfs-pool/.snapshots/subvol7-containers/ | head -5

# Test restoration
cp ~/.snapshots/htpc-home/20251112-htpc-home/patriark/.bashrc /tmp/test-restore

# Check next scheduled backups
systemctl --user list-timers | grep backup
```

---

## Success Metrics

| Metric | Target | Actual | Status |
|--------|--------|--------|--------|
| Backup script execution | exit 0 | exit 0 | ✅ |
| Snapshots created | 4 | 4 | ✅ |
| File restoration | Works | Works | ✅ |
| Systemd service | SUCCESS | SUCCESS | ✅ |
| Documentation updated | Yes | Yes | ✅ |
| Next backup scheduled | <24h | 15h | ✅ |

**Overall:** 🎉 **100% SUCCESS**

---

## Related Documentation

- **Backup strategy guide:** `docs/20-operations/guides/backup-strategy.md`
- **Session handoff:** `docs/99-reports/2025-11-12-session-handoff-backup-fix.md`
- **Backup script:** `scripts/btrfs-snapshot-backup.sh`

---

**Session End:** 2025-11-12 11:15 CET
**Report Author:** Claude Code CLI
**Status:** Backup automation fixed and fully operational
