# Session Handoff: Backup Flow Fix & Vaultwarden Deployment

**Date:** 2025-11-12
**From:** Claude Code Web (sandboxed environment)
**To:** Claude Code CLI (fedora-htpc direct access)
**Branch:** New feature branch (auto-created by CLI session)
**Previous Branch:** `claude/cli-work-continuation-011CV2uAKpZuRynDLGUvXfvy` (PRed)

---

## Executive Summary

**Completed in Web Session:**
- ✅ Vaultwarden configuration files created (ready for deployment)
- ✅ Traefik routing configured (vault.patriark.org)
- ✅ Comprehensive documentation (deployment guide + ADR-006)
- ❌ Backup automation investigation incomplete (sandboxed environment limitations)

**Critical Discovery:**
Backup timers **already exist** on fedora-htpc:
- `btrfs-backup-daily.timer` - Runs at 02:00 CET
- `btrfs-backup-weekly.timer` - Runs Sunday 03:00 CET

**User reported:** Backup script "does not seem to run properly automatically"

**Immediate Task:** Investigate and fix backup automation flow on actual system

**Blocked:** Vaultwarden deployment (requires working backups first)

---

## System State (As Reported by User)

### Backup Timers (Confirmed Running)

```bash
$ systemctl --user list-timers | grep -i backup
Thu 2025-11-13 02:00:00 CET     16h Wed 2025-11-12 02:00:00 CET  7h ago  btrfs-backup-daily.timer   btrfs-backup-daily.service
Sun 2025-11-16 03:00:00 CET  3 days Sun 2025-11-09 03:00:04 CET  3 days ago  btrfs-backup-weekly.timer  btrfs-backup-weekly.service
```

**Analysis:**
- ✅ Timers are loaded and scheduled
- ✅ Last run: Daily backup ran Wed 02:00 (7h ago from user's message)
- ✅ Weekly backup ran Sun 03:00 (3 days ago)
- ❓ **Unknown:** Did backups succeed or fail?
- ❓ **Unknown:** Are snapshots actually being created?

### Files Created in Web Session (May Conflict)

**Created but may duplicate existing:**
- `~/.config/systemd/user/btrfs-snapshot-backup.service` (Web session created)
- `~/.config/systemd/user/btrfs-snapshot-backup.timer` (Web session created)

**Actual system likely has:**
- `~/.config/systemd/user/btrfs-backup-daily.service`
- `~/.config/systemd/user/btrfs-backup-daily.timer`
- `~/.config/systemd/user/btrfs-backup-weekly.service`
- `~/.config/systemd/user/btrfs-backup-weekly.timer`

**Action Required:** Check for duplicates, remove if needed

---

## Investigation Checklist for CLI Session

### Step 1: Verify Backup Script Execution

```bash
# Check service status (both daily and weekly)
systemctl --user status btrfs-backup-daily.service
systemctl --user status btrfs-backup-weekly.service

# Check recent logs
journalctl --user -u btrfs-backup-daily.service -n 100
journalctl --user -u btrfs-backup-weekly.service -n 100

# Check for errors in last run
journalctl --user -u btrfs-backup-daily.service --since "02:00" --until "03:00"

# Check backup script logs (if separate)
ls -lah ~/containers/data/backup-logs/
tail -100 ~/containers/data/backup-logs/backup-$(date +%Y%m).log
```

**Look for:**
- ❌ Service failed status
- ❌ Permission denied errors
- ❌ Missing directories
- ❌ Sudo password prompts (shouldn't happen for user services)
- ❌ Disk full errors
- ❌ BTRFS command failures

---

### Step 2: Verify Snapshot Creation

```bash
# Check if snapshots exist (home subvolume)
ls -lah ~/.snapshots/htpc-home/
# Should see: YYYYMMDD-htpc-home directories

# Check if snapshots exist (BTRFS pool)
ls -lah /mnt/btrfs-pool/.snapshots/subvol7-containers/
# Should see: YYYYMMDD-containers directories

# List all BTRFS subvolumes
sudo btrfs subvolume list /
sudo btrfs subvolume list /mnt/btrfs-pool

# Check snapshot ages
ls -lth ~/.snapshots/htpc-home/ | head -10
ls -lth /mnt/btrfs-pool/.snapshots/subvol7-containers/ | head -10
```

**Expected:**
- ✅ Snapshots from last 7 days (daily retention)
- ✅ Most recent snapshot from today (Wed 02:00) or yesterday
- ❌ **If no recent snapshots:** Script is running but failing silently

---

### Step 3: Check Systemd Unit Files

```bash
# List all backup-related units
systemctl --user list-unit-files | grep backup

# Compare with Web session files
ls -la ~/.config/systemd/user/btrfs*

# View actual service configuration
systemctl --user cat btrfs-backup-daily.service
systemctl --user cat btrfs-backup-weekly.service

# Check timer configuration
systemctl --user cat btrfs-backup-daily.timer
systemctl --user cat btrfs-backup-weekly.timer
```

**Look for:**
- Correct ExecStart path (must point to actual script location)
- Correct flags (--local-only for daily, different for weekly?)
- User/permission issues
- Conflicting units (Web session files vs existing files)

---

### Step 4: Check Script and Permissions

```bash
# Verify script exists and is executable
ls -la ~/fedora-homelab-containers/scripts/btrfs-snapshot-backup.sh
stat ~/fedora-homelab-containers/scripts/btrfs-snapshot-backup.sh

# Test script manually (dry run)
~/fedora-homelab-containers/scripts/btrfs-snapshot-backup.sh --dry-run --local-only --verbose

# Test script manually (real run)
~/fedora-homelab-containers/scripts/btrfs-snapshot-backup.sh --local-only --verbose

# Check for sudo requirements
grep -n "sudo" ~/fedora-homelab-containers/scripts/btrfs-snapshot-backup.sh
```

**Common issues:**
- Script not executable (chmod +x needed)
- Script runs manually but fails when triggered by systemd
- Sudo prompts blocking automated execution
- Wrong paths in systemd unit (~/containers vs ~/fedora-homelab-containers)

---

### Step 5: Check Directory Structure

```bash
# Verify critical directories exist
ls -ld /mnt/btrfs-pool/subvol7-containers/
ls -ld /mnt/btrfs-pool/.snapshots/
ls -ld ~/.snapshots/

# Check permissions
ls -la /mnt/btrfs-pool/.snapshots/ | head -20
ls -la ~/.snapshots/ | head -20

# Check disk space (backups fail if disk full)
df -h /
df -h /mnt/btrfs-pool
btrfs fi usage /mnt/btrfs-pool
```

**Critical checks:**
- ❌ Snapshot directories don't exist (script should create but may fail)
- ❌ Permission denied on snapshot directories
- ❌ Disk >95% full (BTRFS won't snapshot)

---

### Step 6: Check External Backup Mount

```bash
# Check if external drive path exists (weekly backups)
ls -la /run/media/patriark/WD-18TB/

# Check if mounted
mount | grep WD-18TB

# Check last external backup
ls -lah /run/media/patriark/WD-18TB/.snapshots/
```

**Expected:**
- Weekly backups require external drive
- Daily backups should work without external (--local-only)
- External drive may not be permanently mounted

---

## Likely Root Causes (Ranked by Probability)

### 1. **Silent Failures (Most Likely)**
**Symptoms:** Service runs, exits 0, but no snapshots created
**Causes:**
- Sudo password prompt (blocks automated execution)
- Directory permissions preventing snapshot creation
- BTRFS command failures not caught by script
- Wrong paths in script configuration

**Fix:**
- Check logs: `journalctl --user -u btrfs-backup-daily.service -n 100`
- Test manually: `./scripts/btrfs-snapshot-backup.sh --dry-run --verbose`
- Fix sudo/permissions/paths as needed

---

### 2. **Wrong Service Configuration**
**Symptoms:** Timer triggers, service shows "inactive (dead)" immediately
**Causes:**
- Wrong ExecStart path
- Missing flags (--local-only)
- Script not executable
- Wrong WorkingDirectory

**Fix:**
- Compare service file with script location
- Ensure ExecStart points to correct path
- Add `chmod +x scripts/btrfs-snapshot-backup.sh`

---

### 3. **Disk Space Issues**
**Symptoms:** Snapshots fail with "No space left on device"
**Causes:**
- System SSD >95% full
- BTRFS pool exhausted

**Fix:**
- Check: `df -h / && btrfs fi usage /mnt/btrfs-pool`
- Clean up: `podman system prune -f && journalctl --user --vacuum-time=7d`
- Increase retention: Edit script to keep fewer snapshots

---

### 4. **Conflicting Systemd Units**
**Symptoms:** Multiple timers, unclear which one runs
**Causes:**
- Web session created duplicate units
- Old units not cleaned up

**Fix:**
- List: `systemctl --user list-unit-files | grep backup`
- Remove duplicates: `rm ~/.config/systemd/user/btrfs-snapshot-backup.*`
- Reload: `systemctl --user daemon-reload`

---

## Vaultwarden Deployment Status

**Status:** 🟡 Ready but blocked (requires working backups first)

**Files created (in Git):**
- ✅ `config/vaultwarden/vaultwarden.env.template`
- ✅ `config/traefik/dynamic/middleware.yml` (updated)
- ✅ `config/traefik/dynamic/routers.yml` (updated)
- ✅ `~/.config/containers/systemd/vaultwarden.container` (may need to recreate in CLI session)
- ✅ `docs/10-services/guides/vaultwarden-deployment.md`
- ✅ `docs/10-services/decisions/2025-11-12-decision-006-vaultwarden-architecture.md`

**Missing:**
- ❌ `/mnt/btrfs-pool/subvol7-containers/vaultwarden/` directory (verify exists or create)
- ❌ `config/vaultwarden/vaultwarden.env` (copy from template, add admin token)

**Blocked by:** Backup automation must work before deploying Vaultwarden (password vault requires reliable backups)

---

## Recommended Workflow for CLI Session

### Phase 1: Backup Investigation (Priority 1)

1. **Investigate current backup state** (Steps 1-6 above)
2. **Identify root cause** (Silent failures? Wrong config? Disk space?)
3. **Fix backup automation**
4. **Verify snapshots are created**
5. **Test restoration** (critical - backups are useless if restore doesn't work)
6. **Update documentation** if gaps found

**Success Criteria:**
- ✅ Manual script run succeeds
- ✅ Snapshots visible in `~/.snapshots/` and `/mnt/btrfs-pool/.snapshots/`
- ✅ Systemd service shows success (exit code 0)
- ✅ Logs show no errors
- ✅ Can restore file from snapshot

---

### Phase 2: Vaultwarden Deployment (Priority 2)

**Only proceed after Phase 1 complete!**

1. **Verify backup automation working** (from Phase 1)
2. **Create Vaultwarden data directory** on BTRFS pool
3. **Copy environment template** and generate admin token
4. **Deploy Vaultwarden** (follow deployment guide)
5. **Test access** (web vault, admin panel)
6. **Configure 2FA** (YubiKey + TOTP)
7. **Verify backups include Vaultwarden** (trigger manual backup, check snapshot)
8. **Disable admin panel** (security critical)
9. **Test client sync** (desktop, browser, mobile)

**Success Criteria:**
- ✅ All checklist items in deployment guide completed
- ✅ Vaultwarden database in latest snapshot
- ✅ Can restore Vaultwarden from snapshot

---

## Key Context for CLI Session

### User Preferences (From Previous Sessions)

1. **Configuration Philosophy:**
   - Traefik dynamic config files (NOT labels)
   - Centralized configuration in `/config/traefik/dynamic/`
   - Documented in `docs/00-foundation/guides/configuration-design-quick-reference.md`

2. **Security Posture:**
   - UDM-Pro handles GeoIP blocking and IDS (don't duplicate)
   - WireGuard VPN on UDM-Pro (192.168.100.0/24) - not yet tested
   - Defense-in-depth preferred (CrowdSec + rate limiting + headers)

3. **Work Style:**
   - Values detailed planning but wants action
   - Appreciates comprehensive documentation (ADRs, guides)
   - Prefers fixes over workarounds
   - Portfolio website: https://vonrobak.github.io/homelab-infrastructure-public/

### Git Workflow

**Branch naming:** Auto-generated by Claude Code CLI (starts with `claude/`)

**Commit style:**
- Clear, descriptive messages
- GPG signing enabled on fedora-htpc
- Group related changes logically

**PR workflow:**
- Previous branch PRed: `claude/cli-work-continuation-011CV2uAKpZuRynDLGUvXfvy`
- CLI session will create new branch automatically

---

## Files to Check in CLI Session

**Potentially conflicting files (Web session created):**
```
~/.config/systemd/user/btrfs-snapshot-backup.service
~/.config/systemd/user/btrfs-snapshot-backup.timer
~/.config/containers/systemd/vaultwarden.container
```

**Actual system files (likely existing):**
```
~/.config/systemd/user/btrfs-backup-daily.service
~/.config/systemd/user/btrfs-backup-daily.timer
~/.config/systemd/user/btrfs-backup-weekly.service
~/.config/systemd/user/btrfs-backup-weekly.timer
```

**Action:** Compare and consolidate if needed

---

## Quick Reference Commands

```bash
# Backup investigation
systemctl --user status btrfs-backup-daily.service
journalctl --user -u btrfs-backup-daily.service -n 100
ls -lah /mnt/btrfs-pool/.snapshots/subvol7-containers/
~/fedora-homelab-containers/scripts/btrfs-snapshot-backup.sh --dry-run --verbose

# Check system health
df -h / && df -h /mnt/btrfs-pool
btrfs fi usage /mnt/btrfs-pool
podman ps --format "{{.Names}}\t{{.Status}}"
systemctl --user list-timers

# Vaultwarden deployment (after backups fixed)
sudo mkdir -p /mnt/btrfs-pool/subvol7-containers/vaultwarden
cp config/vaultwarden/vaultwarden.env.template config/vaultwarden/vaultwarden.env
openssl rand -base64 48  # Generate admin token
systemctl --user daemon-reload
systemctl --user start vaultwarden.service
```

---

## Expected Issues and Solutions

### Issue 1: Sudo Password Prompt in Automated Script
**Symptom:** Script runs manually but hangs when run by systemd
**Solution:** Configure passwordless sudo for BTRFS commands OR run as root with systemd

### Issue 2: SELinux Denials
**Symptom:** Permission denied despite correct ownership
**Solution:** Check `ausearch -m avc -ts recent` and add SELinux policies

### Issue 3: Snapshot Directories Don't Exist
**Symptom:** Script fails to create snapshots
**Solution:** Manually create directories with correct permissions

### Issue 4: Wrong Script Path in Systemd Unit
**Symptom:** Service fails immediately with "not found"
**Solution:** Update ExecStart in service file to correct path

---

## Success Metrics

**Phase 1 (Backups) Success:**
- [ ] Backup script runs successfully (exit 0)
- [ ] Snapshots visible and recent (<24h old)
- [ ] Can restore file from snapshot
- [ ] Systemd logs show no errors
- [ ] Both daily and weekly timers working

**Phase 2 (Vaultwarden) Success:**
- [ ] Service running and healthy
- [ ] Web vault accessible at https://vault.patriark.org
- [ ] 2FA configured (YubiKey + TOTP)
- [ ] Client sync working (desktop/browser/mobile)
- [ ] Vaultwarden data in snapshots
- [ ] Can restore Vaultwarden from snapshot

---

## Critical Reminders for CLI Session

1. **You have root access** - Don't guess, check actual system state
2. **Timers already exist** - Don't create duplicates, investigate existing
3. **Test manually first** - Always test scripts manually before relying on timers
4. **Backups before Vaultwarden** - Non-negotiable, password vault requires backups
5. **Document findings** - If investigation reveals gaps, update documentation

---

## Next Session Starting Point

```bash
# 1. Navigate to repo
cd ~/fedora-homelab-containers

# 2. Check backup status
systemctl --user status btrfs-backup-daily.service

# 3. Read logs
journalctl --user -u btrfs-backup-daily.service -n 100

# 4. Start investigation using checklist above
```

**First message to CLI session:**
"I need to investigate and fix the backup automation. The timers exist (btrfs-backup-daily and btrfs-backup-weekly) but the user reports backups aren't working properly. Start with Step 1 of the investigation checklist in the handoff document."

---

## Documentation Links

- **Backup script:** `scripts/btrfs-snapshot-backup.sh`
- **Backup guide (Web session):** `docs/20-operations/guides/backup-automation-setup.md`
- **Vaultwarden deployment:** `docs/10-services/guides/vaultwarden-deployment.md`
- **ADR-006:** `docs/10-services/decisions/2025-11-12-decision-006-vaultwarden-architecture.md`
- **Config philosophy:** `docs/00-foundation/guides/configuration-design-quick-reference.md`

---

**End of Handoff Document**

Good luck in CLI session! You have direct system access now - use it wisely.
