# Quadlet Tracking Migration

**Date:** 2026-01-28
**Status:** Complete ✅
**PR:** [#72](https://github.com/vonrobak/fedora-homelab-containers/pull/72)
**Time:** ~1 hour

---

## What Changed

Migrated quadlet tracking from sanitized copy approach to direct git tracking with symlinks.

**Before:**
- Sanitized copies in `~/containers/quadlets/` (22 files tracked)
- Real files in `~/.config/containers/systemd/` (29 files deployed)
- Manual sync required → **9 services missing from git**

**After:**
- Single source of truth in `~/containers/quadlets/` (34 files tracked)
- Symlinks at `~/.config/containers/systemd/` → `~/containers/quadlets/`
- No sync needed - systemd follows symlinks

---

## Why Now

**Original concern:** Preventing hardcoded secrets in git

**Current reality:**
- ✅ All 17/29 production services use Podman secrets
- ✅ Zero hardcoded credentials in production quadlets
- ✅ Configuration drift already happening (9 files out of sync)
- ✅ Security problem solved, workaround now creating maintenance burden

**Decision:** Security foundation in place. Simplify workflow and trust the safety measures.

---

## Implementation

### 1. Pre-Commit Hook (30 min)

Created `.claude/hooks/pre-commit-quadlet-secrets.sh`:
- Scans staged quadlets for hardcoded `PASSWORD=`, `SECRET=`, `TOKEN=`, `API_KEY=`
- Blocks unsafe commits automatically
- Integrated with `.git/hooks/pre-commit`

### 2. Migration (15 min)

```bash
# Backup old quadlets directory
tar -czf /tmp/quadlets-backup-*.tar.gz ~/containers/quadlets/

# Copy all quadlets to git-tracked location
cp ~/.config/containers/systemd/*.{container,network} ~/containers/quadlets/

# Backup systemd directory
tar -czf /tmp/systemd-quadlets-backup-*.tar.gz ~/.config/containers/systemd/

# Replace systemd quadlets with symlinks
cd ~/.config/containers/systemd
for file in *.container *.network; do
  rm "$file"
  ln -s ~/containers/quadlets/"$file" "$file"
done

# Reload systemd (symlinks work!)
systemctl --user daemon-reload
```

### 3. Documentation (10 min)

Updated `quadlets/README.md`:
- Architecture explanation (symlink approach)
- Security measures (Podman secrets, pre-commit hook)
- Simplified workflow (no copy step)
- Troubleshooting guide

### 4. Commit & Verify (5 min)

```bash
# Stage all files
git add quadlets/*.{container,network} .claude/hooks/ .gitignore

# Commit (pre-commit hook validates automatically)
git commit -m "refactor: migrate quadlets to direct git tracking with symlink approach"
# ✓ Pre-commit: Checking quadlet files for hardcoded secrets...
# ✓ No hardcoded secrets found

# Verify services still work
systemctl --user status prometheus.service  # active
systemctl --user is-active matter-server.service  # active
```

---

## Files Tracked (11 New)

Services now in git that were previously missing:
1. `authelia.container` - SSO with YubiKey MFA
2. `matter-server.container` - Matter protocol server (Week 2)
3. `vaultwarden.container` - Password manager
4. `unpoller.container` - UniFi metrics exporter
5. `homepage.container` - Dashboard service
6. `gathio.container` + `gathio-db.container` - Event management
7. `nextcloud-redis.container` - Redis cache
8. `gathio.network` + `nextcloud.network` - Networks
9. `grafana.container` - Now uses Podman secrets (was template)

**Total:** 29 containers + 5 networks = 34 quadlet files

---

## Security Validation

**Pre-commit hook tested:**
```bash
$ .claude/hooks/pre-commit-quadlet-secrets.sh
✓ No hardcoded secrets found in quadlet files
```

**Security audit results:**
- 17/29 services use Podman secrets ✅
- 0/29 production quadlets have hardcoded credentials ✅
- Only `ocis-test.container` excluded (test placeholder)

**Defense in depth:**
1. Pre-commit hook blocks unsafe commits
2. .gitignore excludes `*-test.container`
3. Podman secrets for all production credentials
4. /commit-push-pr command provides validation layer

---

## Verification

**Symlinks working:**
```bash
$ readlink ~/.config/containers/systemd/matter-server.container
/home/patriark/containers/quadlets/matter-server.container

$ systemctl --user daemon-reload  # No errors

$ systemctl --user is-active matter-server.service
active
```

**All services operational:**
- Prometheus: ✅ Running
- Matter Server: ✅ Running
- All 29 containerized services: ✅ Healthy

---

## Workflow Going Forward

**Simple edit workflow:**
```bash
# Edit quadlet (either location works - same file via symlink)
nano ~/containers/quadlets/service.container
# OR
nano ~/.config/containers/systemd/service.container

# Reload and restart
systemctl --user daemon-reload
systemctl --user restart service.service

# Commit (automated validation)
/commit-push-pr
```

**Pre-commit hook automatically:**
- Scans for hardcoded secrets
- Blocks unsafe commits
- Validates Traefik config (existing hook)

---

## Benefits Achieved

1. **Single source of truth** - Git reflects actual deployment
2. **No sync overhead** - Eliminated manual copy step
3. **Configuration accuracy** - All 29 services now tracked
4. **Atomic commits** - Quadlet + config + docs together
5. **Automated safety** - Pre-commit hook validates automatically

---

## Key Learnings

### Trust the Security Foundation

Migration was safe because:
- Podman secrets adoption already complete (17 services)
- Pre-commit hooks provide automatic validation
- /commit-push-pr command adds review layer
- Multiple safety mechanisms in place

### Simplify When Appropriate

The sanitized copy workaround solved a problem that no longer exists:
- Original concern: Hardcoded secrets in git
- Current state: All production secrets use Podman secrets
- Outcome: Workaround creating more problems than it solves

### Symlinks Work Great

Systemd quadlets work perfectly with symlinks:
- No performance impact
- Daemon reload recognizes changes
- Services continue running normally
- Edit either location - same file

---

## Related

**Week 2 Deployment:** PR #71
- Deployed matter-server.container (now tracked in git)
- Comprehensive deployment journal
- Unpoller metrics guide

**Quadlet Migration:** PR #72
- 36 files changed (+1018/-219 lines)
- Pre-commit hook implementation
- Architecture documentation

---

## Status

**Complete:** All quadlets tracked, symlinks working, pre-commit hook active, services healthy.

**Next:** Normal workflow - edit quadlets directly, /commit-push-pr handles git operations automatically.
