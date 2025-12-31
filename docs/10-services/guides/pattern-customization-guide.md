# Pattern Customization Guide

**Created:** 2025-11-14
**Purpose:** Guide for customizing pattern-based deployments
**Audience:** Users and Claude Code
**Status:** Production ✅

---

## Overview

**Deployment patterns** provide 80% of what most services need. The remaining 20% requires **post-deployment customization**.

This guide explains:
- When to customize vs when to use patterns as-is
- How to customize generated quadlets safely
- Common customization scenarios
- How to preserve customizations through updates

---

## Quick Reference

### Pattern Deployment → Customization Workflow

```bash
# 1. Deploy from pattern
cd .claude/skills/homelab-deployment
./scripts/deploy-from-pattern.sh \
  --pattern media-server-stack \
  --service-name jellyfin \
  --memory 4G

# 2. Customize quadlet
nano ~/.config/containers/systemd/jellyfin.container

# 3. Apply customizations
systemctl --user daemon-reload
systemctl --user restart jellyfin.service

# 4. Verify customizations applied
./scripts/check-drift.sh jellyfin
systemctl --user status jellyfin.service
```

---

## When to Customize

### Use Pattern As-Is ✅

**Deploy without customization when:**
- Service fits pattern's standard use case
- Default resource limits appropriate
- Standard network configuration sufficient
- No special hardware requirements
- No unique volume mounts needed

**Examples:**
- Redis cache with default settings
- PostgreSQL database with standard config
- Internal admin panel with authentication

---

### Customize After Deployment 🔧

**Customize when:**
- Hardware passthrough needed (GPU, USB devices)
- Additional volume mounts required (media libraries, data directories)
- Different middleware chain (remove/add authentication)
- Custom environment variables
- Specific port mappings
- Resource limit adjustments

**Examples:**
- Jellyfin needs GPU transcoding (`AddDevice=/dev/dri/renderD128`)
- Service needs access to specific data directory
- Public service shouldn't require authentication

---

### Manual Deployment (Skip Pattern) 🛠️

**Skip pattern-based deployment when:**
- Service doesn't fit any existing pattern
- Requires 5+ customizations
- Multi-container stack with complex dependencies
- Experimental/one-off deployment

**Solution:** Use patterns as **reference**, deploy manually

---

## Common Customizations

### Customization 1: GPU Passthrough

**Pattern:** `media-server-stack` (Jellyfin, Plex)
**Requirement:** Hardware-accelerated transcoding

**Steps:**
```bash
# 1. Deploy from pattern
./scripts/deploy-from-pattern.sh \
  --pattern media-server-stack \
  --service-name jellyfin \
  --memory 4G

# 2. Edit quadlet
nano ~/.config/containers/systemd/jellyfin.container

# 3. Add GPU device under [Container] section
# ADD THIS LINE:
AddDevice=/dev/dri/renderD128

# Before:
# [Container]
# Image=jellyfin/jellyfin:latest
# ...

# After:
# [Container]
# Image=jellyfin/jellyfin:latest
# AddDevice=/dev/dri/renderD128
# ...

# 4. Apply
systemctl --user daemon-reload
systemctl --user restart jellyfin.service

# 5. Verify GPU accessible
podman exec jellyfin ls -l /dev/dri/renderD128
```

**Result:** Jellyfin can use GPU for transcoding

**Drift status:** DRIFT (AddDevice not in pattern) - **Expected and intentional**

---

### Customization 2: Additional Volume Mounts

**Pattern:** Any pattern
**Requirement:** Mount additional directories (media libraries, data folders)

**Steps:**
```bash
# 1. Deploy from pattern
./scripts/deploy-from-pattern.sh \
  --pattern media-server-stack \
  --service-name jellyfin \
  --memory 4G

# 2. Edit quadlet
nano ~/.config/containers/systemd/jellyfin.container

# 3. Add volume mounts under [Container] section
# ADD THESE LINES:
Volume=/mnt/btrfs-pool/subvol4-multimedia:/media/multimedia:Z,ro
Volume=/mnt/btrfs-pool/subvol5-music:/media/music:Z,ro

# Before:
# [Container]
# Volume=%h/containers/config/jellyfin:/config:Z
# ...

# After:
# [Container]
# Volume=%h/containers/config/jellyfin:/config:Z
# Volume=/mnt/btrfs-pool/subvol4-multimedia:/media/multimedia:Z,ro
# Volume=/mnt/btrfs-pool/subvol5-music:/media/music:Z,ro
# ...

# 4. Apply
systemctl --user daemon-reload
systemctl --user restart jellyfin.service

# 5. Verify mounts
podman exec jellyfin ls /media/multimedia
podman exec jellyfin ls /media/music
```

**Important:** Always use `:Z` SELinux label on volume mounts for rootless containers

**Flags:**
- `:Z` - SELinux private label (required for rootless)
- `:ro` - Read-only mount (recommended for media libraries)
- `:rw` - Read-write mount (default)

---

### Customization 3: Remove Authentication Middleware

**Pattern:** Most public-facing patterns
**Requirement:** Make service publicly accessible (no Authelia login)

**Steps:**
```bash
# 1. Deploy from pattern
./scripts/deploy-from-pattern.sh \
  --pattern media-server-stack \
  --service-name jellyfin \
  --memory 4G

# 2. Edit Traefik routing (NOT quadlet - ADR-016 separation of concerns)
nano ~/containers/config/traefik/dynamic/routers.yml

# 3. Find jellyfin-secure router and remove authelia middleware
# BEFORE:
middlewares:
  - crowdsec-bouncer@file
  - rate-limit-public@file
  - authelia@file
  - security-headers@file

# AFTER (remove authelia):
middlewares:
  - crowdsec-bouncer@file
  - rate-limit-public@file
  - security-headers@file

# 4. Reload Traefik (auto-reloads in ~60s, or force reload)
podman exec traefik kill -SIGHUP 1

# 5. Verify public access
curl https://jellyfin.patriark.org
# Should NOT redirect to SSO portal
```

**Security consideration:** Removing authentication makes service publicly accessible. Ensure service has internal authentication (Jellyfin login, etc.)

---

### Customization 4: Custom Environment Variables

**Pattern:** `password-manager`, `web-app-with-database`
**Requirement:** Service-specific configuration via environment variables

**Steps:**
```bash
# 1. Deploy from pattern
./scripts/deploy-from-pattern.sh \
  --pattern password-manager \
  --service-name vaultwarden \
  --memory 512M

# 2. Edit quadlet
nano ~/.config/containers/systemd/vaultwarden.container

# 3. Add environment variables under [Container] section
# ADD THESE LINES:
Environment=DOMAIN=https://vault.patriark.org
Environment=SIGNUPS_ALLOWED=false
Environment=ADMIN_TOKEN=<your-secret-token>
Environment=SMTP_HOST=smtp.gmail.com
Environment=SMTP_PORT=587

# Or use environment file:
EnvironmentFile=%h/containers/config/vaultwarden/vaultwarden.env

# 4. Apply
systemctl --user daemon-reload
systemctl --user restart vaultwarden.service

# 5. Verify environment
podman exec vaultwarden env | grep -E 'DOMAIN|SIGNUPS|ADMIN'
```

**Best practice:** Use `EnvironmentFile=` for secrets, `Environment=` for non-sensitive config

---

### Customization 5: Adjust Resource Limits

**Pattern:** Any pattern
**Requirement:** Increase/decrease memory or CPU allocation

**Steps:**
```bash
# 1. Deploy from pattern
./scripts/deploy-from-pattern.sh \
  --pattern media-server-stack \
  --service-name jellyfin \
  --memory 4G  # Initial allocation

# 2. Edit quadlet
nano ~/.config/containers/systemd/jellyfin.container

# 3. Modify [Service] section
# BEFORE:
# [Service]
# Memory=4G
# MemoryHigh=3G
# CPUWeight=400

# AFTER (increased for heavy transcoding):
# [Service]
# Memory=8G
# MemoryHigh=6G
# CPUWeight=600

# 4. Apply
systemctl --user daemon-reload
systemctl --user restart jellyfin.service

# 5. Verify new limits
podman inspect jellyfin | grep -i memory
systemctl --user show jellyfin.service | grep Memory
```

**Guidelines:**
- `Memory=` - Hard limit (service killed if exceeded)
- `MemoryHigh=` - Soft limit (75% of Memory recommended)
- `CPUWeight=` - Relative priority (100-1000, default 400)

---

### Customization 6: Add Service to Additional Network

**Pattern:** Any pattern
**Requirement:** Service needs access to multiple networks

**Steps:**
```bash
# 1. Deploy from pattern
./scripts/deploy-from-pattern.sh \
  --pattern web-app-with-database \
  --service-name wiki \
  --memory 2G

# 2. Create additional network (if doesn't exist)
podman network create systemd-wiki_services

# 3. Edit quadlet
nano ~/.config/containers/systemd/wiki.container

# 4. Add network line under [Container] section
# BEFORE:
# [Container]
# Network=systemd-reverse_proxy.network
# Network=systemd-monitoring.network

# AFTER (add app-specific network):
# [Container]
# Network=systemd-reverse_proxy.network  # Must be first for internet access
# Network=systemd-monitoring.network
# Network=systemd-wiki_services.network  # App-specific database network

# 5. Apply
systemctl --user daemon-reload
systemctl --user restart wiki.service

# 6. Verify networks
podman inspect wiki | grep -A 5 Networks
```

**Critical:** First `Network=` line gets default route (internet access). Always put `systemd-reverse_proxy.network` first for public services.

---

## Preserving Customizations

### Through Service Restarts ✅

**Customizations persist automatically** when stored in quadlet file.

**How it works:**
1. Edit `~/.config/containers/systemd/service.container`
2. Run `systemctl --user daemon-reload`
3. Restart service
4. Systemd recreates container from quadlet (including customizations)

**Example:**
```bash
# Edit quadlet (add GPU)
nano ~/.config/containers/systemd/jellyfin.container

# Restart applies customization
systemctl --user daemon-reload
systemctl --user restart jellyfin.service

# GPU remains after reboot
sudo reboot
# After reboot: GPU still available in container
```

---

### Through Pattern Updates ⚠️

**Problem:** Re-running `deploy-from-pattern.sh` overwrites customizations

**Solutions:**

**Option 1: Don't re-deploy** (recommended)
```bash
# After initial pattern deployment + customization:
# DO NOT re-run deploy-from-pattern.sh on same service
# Pattern deployment is ONE-TIME, customizations live in quadlet
```

**Option 2: Backup before re-deployment**
```bash
# Backup customized quadlet
cp ~/.config/containers/systemd/jellyfin.container \
   ~/containers/backups/jellyfin.container.custom-$(date +%Y%m%d)

# Re-deploy from pattern (overwrites customizations)
./scripts/deploy-from-pattern.sh --pattern media-server-stack --service-name jellyfin

# Re-apply customizations from backup
diff ~/containers/backups/jellyfin.container.custom-* \
     ~/.config/containers/systemd/jellyfin.container

# Manually merge customizations back
```

**Option 3: Create custom pattern** (advanced)
```bash
# Copy existing pattern
cp patterns/media-server-stack.yml patterns/jellyfin-custom.yml

# Edit custom pattern to include your customizations
nano patterns/jellyfin-custom.yml

# Deploy from custom pattern
./scripts/deploy-from-pattern.sh --pattern jellyfin-custom --service-name jellyfin
```

---

## Validation After Customization

### Check 1: Systemd Unit Loads

```bash
# Verify quadlet syntax valid
systemctl --user daemon-reload

# Check for errors
systemctl --user status jellyfin.service

# No errors = quadlet valid
```

**Common syntax errors:**
- Missing `=` in key-value pairs
- Invalid section headers (must be `[Container]`, `[Service]`, etc.)
- Typos in option names

---

### Check 2: Container Starts

```bash
# Start service
systemctl --user start jellyfin.service

# Check status
systemctl --user status jellyfin.service

# Expected: active (running)
```

**Common failures:**
- Invalid image name
- Network doesn't exist
- Volume path doesn't exist
- Device not available (`/dev/dri/renderD128`)
- Port already in use

---

### Check 3: Customizations Applied

```bash
# GPU passthrough verification
podman exec jellyfin ls -l /dev/dri/renderD128

# Volume mount verification
podman exec jellyfin df -h | grep /media

# Environment variable verification
podman exec jellyfin env | grep DOMAIN

# Network verification
podman inspect jellyfin | grep -A 10 Networks

# Resource limit verification
podman inspect jellyfin | grep -i memory
```

---

### Check 4: Service Functional

```bash
# Health check (if service supports it)
curl -f http://localhost:8096/health

# Web UI access
curl https://jellyfin.patriark.org

# Service-specific checks
podman logs jellyfin --tail 50
journalctl --user -u jellyfin.service -n 50
```

---

## Troubleshooting Customizations

### Service Won't Start After Customization

**Diagnosis:**
```bash
# Check systemd errors
journalctl --user -u jellyfin.service -n 100

# Check quadlet syntax
systemctl --user cat jellyfin.service

# Test container manually
podman run --rm -it \
  --name jellyfin-test \
  jellyfin/jellyfin:latest \
  /bin/bash
```

**Common issues:**
- **SELinux denial:** Missing `:Z` on volume mount
- **Device unavailable:** GPU device doesn't exist or wrong path
- **Permission denied:** User doesn't have access to device/file
- **Network not found:** Network doesn't exist (`podman network ls`)

**Fix:**
1. Revert customization temporarily
2. Restart service to confirm base pattern works
3. Re-apply customization incrementally
4. Test after each change

---

### Customization Doesn't Persist

**Symptom:** Customization works initially but disappears after restart

**Diagnosis:**
```bash
# Check quadlet file
cat ~/.config/containers/systemd/jellyfin.container

# Verify customization still in file
grep "AddDevice" ~/.config/containers/systemd/jellyfin.container
```

**Common causes:**
- Edited wrong file (edited generated file instead of quadlet)
- Forgot `systemctl --user daemon-reload`
- Pattern re-deployment overwrote customizations

**Fix:** Re-apply customization to correct quadlet file

---

### Drift Detected After Customization

**Symptom:** `check-drift.sh` shows DRIFT after customization

**Diagnosis:**
```bash
./scripts/check-drift.sh jellyfin --verbose
```

**Expected vs Unexpected:**
- **Expected drift:** Customizations not in pattern (GPU, volumes, env vars)
- **Unexpected drift:** Base pattern settings changed unintentionally

**Action:**
- **Expected drift:** Document as intentional in quadlet comments
- **Unexpected drift:** Reconcile or fix quadlet

**Documentation example:**
```ini
[Container]
Image=jellyfin/jellyfin:latest
# CUSTOMIZATION: GPU passthrough for hardware transcoding
AddDevice=/dev/dri/renderD128
```

---

## Best Practices

### Document Your Customizations

**Add comments to quadlet:**
```ini
[Container]
Image=jellyfin/jellyfin:latest

# CUSTOMIZATION 2025-11-14: GPU transcoding
AddDevice=/dev/dri/renderD128

# CUSTOMIZATION 2025-11-14: Media library mounts
Volume=/mnt/btrfs-pool/subvol4-multimedia:/media/multimedia:Z,ro
Volume=/mnt/btrfs-pool/subvol5-music:/media/music:Z,ro

# NOTE: Traefik routing is in ~/containers/config/traefik/dynamic/routers.yml
# (Per ADR-016: Separation of concerns - routing NOT in quadlet labels)
...
```

**Why:**
- Future-you knows why customization exists
- Claude Code understands intent
- Easier to review and update

---

### Test Incrementally

**Don't customize everything at once:**

```bash
# BAD: Add 5 customizations simultaneously
nano jellyfin.container  # Add GPU + volumes + env + networks + resources
systemctl --user restart jellyfin.service
# Fails - which customization broke it?

# GOOD: Add one customization at a time
nano jellyfin.container  # Add GPU only
systemctl --user restart jellyfin.service
# Test: GPU works ✓

nano jellyfin.container  # Add volume mount
systemctl --user restart jellyfin.service
# Test: Volume accessible ✓

# Continue incrementally...
```

---

### Keep Backups

**Before significant customizations:**
```bash
# Backup working quadlet
cp ~/.config/containers/systemd/jellyfin.container \
   ~/containers/backups/jellyfin.container.$(date +%Y%m%d-%H%M%S)

# Make customizations
nano ~/.config/containers/systemd/jellyfin.container

# If breaks, restore from backup
cp ~/containers/backups/jellyfin.container.TIMESTAMP \
   ~/.config/containers/systemd/jellyfin.container
```

---

### Use Git for Quadlet Versioning

**Track quadlet changes:**
```bash
# Add quadlets to git (if not already tracked)
git add ~/.config/containers/systemd/*.container

# Commit before customization
git commit -m "jellyfin: base pattern deployment"

# Make customizations
nano ~/.config/containers/systemd/jellyfin.container

# Commit customizations
git commit -m "jellyfin: add GPU passthrough and media volumes"

# View history
git log -- ~/.config/containers/systemd/jellyfin.container

# Revert if needed
git checkout HEAD~1 -- ~/.config/containers/systemd/jellyfin.container
```

---

## Advanced: Creating Custom Patterns

**When to create custom pattern:**
- Deploying same service type 3+ times
- Complex customizations repeated across services
- Want to standardize organization-specific config

**Steps:**
```bash
# 1. Copy existing pattern as template
cp .claude/skills/homelab-deployment/patterns/media-server-stack.yml \
   .claude/skills/homelab-deployment/patterns/media-server-gpu.yml

# 2. Edit custom pattern
nano .claude/skills/homelab-deployment/patterns/media-server-gpu.yml

# 3. Add customizations to pattern
quadlet:
  container:
    add_device:
      - /dev/dri/renderD128  # GPU built-in
    volumes:
      - /mnt/btrfs-pool/subvol4-multimedia:/media/multimedia:Z,ro
      - /mnt/btrfs-pool/subvol5-music:/media/music:Z,ro

# 4. Deploy from custom pattern
./scripts/deploy-from-pattern.sh \
  --pattern media-server-gpu \
  --service-name plex \
  --memory 4G

# 5. No post-deployment customization needed!
```

**Benefit:** Repeatable, validated deployments with customizations included

---

## Related Documentation

- **Pattern Selection:** `docs/10-services/guides/pattern-selection-guide.md`
- **Deployment Cookbook:** `.claude/skills/homelab-deployment/COOKBOOK.md`
- **Drift Detection:** `docs/20-operations/guides/drift-detection-workflow.md`
- **ADR-007:** `docs/20-operations/decisions/2025-11-14-decision-007-pattern-based-deployment.md`
- **Skill Documentation:** `.claude/skills/homelab-deployment/SKILL.md`

---

**Maintained by:** patriark + Claude Code
**Review frequency:** Quarterly
**Next review:** 2026-02-14
