# Quadlet Configuration Changes Summary
## Date: 2026-02-03

## Overview
This document tracks changes made to quadlet files in `~/.config/containers/systemd/`
which are managed outside the main git repository.

## Modified Quadlet Files (9 total)

### Critical Fixes (Service Failures)
1. **~/.config/containers/systemd/immich-server.container**
   - Line 20: `Network=systemd-photos:ip=10.89.7.3` → `10.89.5.5`
   - Line 8: `Image=ghcr.io/immich-app/immich-server:v2.4.1` → `v2.5.2`
   - Status: ✅ Applied, service running and verified

2. **~/.config/containers/systemd/jellyfin.container**
   - Line 16: `Network=systemd-media_services:ip=10.89.5.3` → `10.89.1.3`
   - Status: ✅ Applied, service running and verified

3. **~/.config/containers/systemd/nextcloud.container**
   - Line 55: `Network=systemd-nextcloud:ip=10.89.1.3` → `10.89.10.4`
   - Status: ✅ Applied, service running and verified

### Configuration Standardization (.69+ IP scheme)
4. **~/.config/containers/systemd/traefik.container**
   - Line 12-14: Added static IPs
     - `Network=systemd-reverse_proxy` → `:ip=10.89.2.69`
     - `Network=systemd-auth_services` → `:ip=10.89.3.69`
     - `Network=systemd-monitoring` → `:ip=10.89.4.69`
   - Status: ⏳ Applied, requires restart to take effect

5. **~/.config/containers/systemd/crowdsec.container**
   - Line 10: `Network=systemd-reverse_proxy` → `:ip=10.89.2.70`
   - Status: ⏳ Applied, requires restart to take effect

6. **~/.config/containers/systemd/vaultwarden.container**
   - Line 25: `Network=reverse_proxy.network` → `systemd-reverse_proxy:ip=10.89.2.71`
   - Status: ⏳ Applied, requires restart to take effect

7. **~/.config/containers/systemd/alertmanager.container**
   - Line 11-12: Added static IPs
     - `Network=systemd-reverse_proxy` → `:ip=10.89.2.72`
     - `Network=systemd-monitoring` → `:ip=10.89.4.72`
   - Status: ⏳ Applied, requires restart to take effect

8. **~/.config/containers/systemd/homepage.container**
   - Line 13: `Network=systemd-reverse_proxy` → `:ip=10.89.2.73`
   - Status: ⏳ Applied, requires restart to take effect

9. **~/.config/containers/systemd/collabora.container**
   - Line 29-30: Added static IPs
     - `Network=systemd-reverse_proxy` → `:ip=10.89.2.74`
     - `Network=systemd-nextcloud` → `:ip=10.89.10.74`
   - Status: ⏳ Applied, requires restart to take effect

## How to Apply Remaining Changes

Services with ✅ status are already running with new IPs and verified working.
Services with ⏳ status need restart to pick up new static IPs:

```bash
# Apply all changes at once (reload systemd, restart services)
export XDG_RUNTIME_DIR=/run/user/$(id -u)
systemctl --user daemon-reload
systemctl --user restart traefik.service crowdsec.service vaultwarden.service \
  alertmanager.service homepage.service collabora.service

# Wait for services to stabilize
sleep 10

# Verify all services are healthy
podman ps --format "table {{.Names}}\t{{.Status}}" | \
  grep -E "(traefik|crowdsec|vaultwarden|alertmanager|homepage|collabora)"
```

## Validation

All changes have been validated:
- ✅ All static IPs within correct network subnets
- ✅ No duplicate IP addresses
- ✅ No conflicts with existing container allocations
- ✅ Critical services tested and working externally
- ✅ Traefik configuration validated

## Version Control for Quadlets

**Note:** The quadlet files in `~/.config/containers/systemd/` are not currently
tracked in git. Consider adding version control:

```bash
cd ~/.config/containers/systemd
git init
git add *.container *.network
git commit -m "Initial commit: Quadlet configurations with fixed IPs"
```

This would enable:
- Change tracking for service configurations
- Rollback capability
- Integration with homelab documentation

## Related
- Pull Request: https://github.com/vonrobak/fedora-homelab-containers/pull/78
- Root Cause: PR #77 DNS resolution fix with incorrect IP assignments
- Audit Results: 10 misconfigurations found across 28 services

---

## UPDATE: Symlink Approach Restored (2026-02-03 15:53)

The symlink-based quadlet tracking has been **restored** after confirming that
yesterday's routing issues were caused by IP misconfigurations, not the symlink
approach.

### Current Architecture (Restored)
```
~/containers/quadlets/*.{container,network}      (real files, tracked in git)
            ↓ (symlinks created)
~/.config/containers/systemd/*.{container,network}   (systemd loads from here)
```

### Validation Results
- ✅ 36 symlinks created successfully
- ✅ Systemd daemon reload successful
- ✅ All services remain operational
- ✅ Pre-commit hooks passing (Traefik config + secret detection)

### What This Means
All quadlet changes are now **automatically tracked in git**. When you:
- Edit a quadlet: Both locations stay in sync (they're the same file via symlink)
- Commit changes: Quadlets are included in PR automatically
- Deploy new services: Just create the file in either location

No manual syncing required! 🎉

### Files in Git
All quadlet changes from this audit are now committed in PR #78:
- Commit 26d0dca: "fix: Restore quadlet symlink approach with corrected IP configurations"
- 9 quadlets updated with corrected static IPs
- Original symlink approach from commit 6721219 (2026-01-28) restored

