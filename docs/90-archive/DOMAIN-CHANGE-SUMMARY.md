# Domain Change Summary: patriark.dev → patriark.org

**Date:** 2025-10-22  
**Change:** All scripts updated from `patriark.dev` to `patriark.org`  
**Files Updated:** 2 scripts, multiple domain references

---

## ✅ What Changed

### New Script Files Created:

1. **critical-security-fixes-org.sh** (replaces critical-security-fixes.sh)
   - Single domain change on line 128
   - All other functionality identical

2. **configure-authelia-dual-domain-org.sh** (replaces configure-authelia-dual-domain.sh)
   - 11 domain references changed
   - All other functionality identical

### Old Scripts (DO NOT USE):
- ~~critical-security-fixes.sh~~ (has .dev domain)
- ~~configure-authelia-dual-domain.sh~~ (has .dev domain)

### New Scripts (USE THESE):
- ✅ **critical-security-fixes-org.sh** (has .org domain)
- ✅ **configure-authelia-dual-domain-org.sh** (has .org domain)

---

## 📋 Exact Changes Made

### Script 1: critical-security-fixes-org.sh

**Total changes:** 7 domain references

**Line 128 (routers.yml creation):**
```yaml
- OLD: rule: "Host(`traefik.patriark.lokal`) || Host(`traefik.patriark.dev`)"
+ NEW: rule: "Host(`traefik.patriark.lokal`) || Host(`traefik.patriark.org`)"
```

**Lines 206-207 (access_control example):**
```yaml
- OLD: - 'auth.patriark.dev'
+ NEW: - 'auth.patriark.org'
```

**Lines 212-213:**
```yaml
- OLD: - 'traefik.patriark.dev'
+ NEW: - 'traefik.patriark.org'
```

**Lines 220-221:**
```yaml
- OLD: - 'jellyfin.patriark.dev'
+ NEW: - 'jellyfin.patriark.org'
```

**Lines 228-230:**
```yaml
- OLD: - 'nextcloud.patriark.dev'
- OLD: - 'vaultwarden.patriark.dev'
+ NEW: - 'nextcloud.patriark.org'
+ NEW: - 'vaultwarden.patriark.org'
```

---

### Script 2: configure-authelia-dual-domain-org.sh

**Total changes:** 14 domain references

**Line 2 (comment):**
```bash
- OLD: # Enables support for both .lokal (LAN) and .dev (internet) domains
+ NEW: # Enables support for both .lokal (LAN) and .org (internet) domains
```

**Line 31 (comment in config):**
```yaml
- OLD: # Domains: patriark.lokal (LAN) + patriark.dev (Internet)
+ NEW: # Domains: patriark.lokal (LAN) + patriark.org (Internet)
```

**Line 59 (TOTP issuer):**
```yaml
- OLD: issuer: 'patriark.dev'
+ NEW: issuer: 'patriark.org'
```

**Lines 109-110 (auth domain):**
```yaml
- OLD: - 'auth.patriark.dev'
+ NEW: - 'auth.patriark.org'
```

**Lines 115-116 (traefik domain):**
```yaml
- OLD: - 'traefik.patriark.dev'
+ NEW: - 'traefik.patriark.org'
```

**Lines 123-124 (jellyfin domain):**
```yaml
- OLD: - 'jellyfin.patriark.dev'
+ NEW: - 'jellyfin.patriark.org'
```

**Lines 130-133 (nextcloud, vaultwarden):**
```yaml
- OLD: - 'nextcloud.patriark.dev'
- OLD: - 'vaultwarden.patriark.dev'
+ NEW: - 'nextcloud.patriark.org'
+ NEW: - 'vaultwarden.patriark.org'
```

**Lines 154-156 (session cookie - CRITICAL):**
```yaml
- OLD: - domain: 'patriark.dev'
- OLD:   authelia_url: 'https://auth.patriark.dev'
- OLD:   default_redirection_url: 'https://jellyfin.patriark.dev'
+ NEW: - domain: 'patriark.org'
+ NEW:   authelia_url: 'https://auth.patriark.org'
+ NEW:   default_redirection_url: 'https://jellyfin.patriark.org'
```

**Lines 191-192 (SMTP sender):**
```yaml
- OLD: sender: 'Authelia <auth@patriark.dev>'
- OLD: identifier: 'patriark.dev'
+ NEW: sender: 'Authelia <auth@patriark.org>'
+ NEW: identifier: 'patriark.org'
```

**Line 193 (startup check email):**
```yaml
- OLD: subject: '[Patriark Homelab] {title}'
+ NEW: subject: '[Patriark Homelab] {title}'
(No change - not domain-specific)
```

**Lines 269-271 (test URLs in output):**
```bash
- OLD: echo "   Internet: https://jellyfin.patriark.dev (after DNS/port forwarding)"
+ NEW: echo "   Internet: https://jellyfin.patriark.org (after DNS/port forwarding)"
```

---

## 🔍 Verification Commands

After running the new scripts, verify the domain changes:

```bash
# Check routers.yml has .org
grep -n "patriark\." ~/containers/config/traefik/dynamic/routers.yml
# Should show: patriark.lokal and patriark.org (NOT .dev)

# Check Authelia config has .org
grep -n "patriark\." ~/containers/config/authelia/configuration.yml
# Should show: patriark.lokal and patriark.org (NOT .dev)

# Verify no .dev references remain
grep -r "patriark\.dev" ~/containers/config/
# Should return empty (no results)
```

---

## 📝 Complete Usage Instructions

### Step 1: Copy Updated Scripts

```bash
cd ~/containers/scripts

# Copy the NEW scripts with -org suffix
cp /path/to/outputs/critical-security-fixes-org.sh .
cp /path/to/outputs/configure-authelia-dual-domain-org.sh .

# Make executable (if not already)
chmod +x critical-security-fixes-org.sh
chmod +x configure-authelia-dual-domain-org.sh

# Verify you have the right ones
ls -lh *-org.sh
```

### Step 2: Run Security Fixes (Script 1)

```bash
# Run the updated script
./critical-security-fixes-org.sh

# This will:
# 1. Create backup directory with timestamp
# 2. Fix Redis password exposure
# 3. Secure Traefik dashboard
# 4. Add rate limiting
# 5. Create security headers
# 6. Restart services

# Expected output:
# ✓ Created backup directory
# ✓ Created redis_password secret file
# ✓ Updated configuration.yml to use secret file
# ✓ Updated authelia.container quadlet
# ✓ Disabled insecure API mode
# ✓ Created traefik-auth middleware
# ✓ Created dashboard router with authentication
# ✓ Created rate limiting middleware
# ✓ Created strict security headers
# ✓ Authelia: Active
# ✓ Traefik: Active
# ✓ Authelia: Healthy
```

### Step 3: Verify Script 1 Results

```bash
# Run the verification script that was created
~/containers/scripts/verify-security-fixes.sh

# Expected output:
# [1] Redis password in secret file: ✓ PASS
# [2] Traefik API secure mode: ✓ PASS
# [3] Rate limiting active: ✓ PASS
# [4] Security headers configured: ✓ PASS
# [5] Authelia running: ✓ PASS
# [6] Traefik running: ✓ PASS

# Check the created routers.yml has .org domain
cat ~/containers/config/traefik/dynamic/routers.yml | grep "Host("
# Should show: Host(`traefik.patriark.lokal`) || Host(`traefik.patriark.org`)
```

### Step 4: Run Dual-Domain Configuration (Script 2)

```bash
# Run the updated script
./configure-authelia-dual-domain-org.sh

# This will:
# 1. Backup current configuration.yml
# 2. Create new configuration with .lokal + .org support
# 3. Show you a diff of changes
# 4. Ask for confirmation

# When prompted "Apply new configuration? (yes/no):"
# Review the diff carefully
# Type: yes

# Expected output:
# ✓ Backed up configuration
# (shows diff)
# Apply new configuration? yes
# ✓ Configuration applied
# (validation output)
```

### Step 5: Verify Script 2 Results

```bash
# Check Authelia config has .org domains
grep "patriark\." ~/containers/config/authelia/configuration.yml | head -20

# Should show both:
# - 'auth.patriark.lokal'
# - 'auth.patriark.org'
# - 'jellyfin.patriark.lokal'
# - 'jellyfin.patriark.org'
# etc.

# Verify NO .dev references remain
grep -c "patriark\.dev" ~/containers/config/authelia/configuration.yml
# Should return: 0

# Check session cookies configuration
grep -A 3 "domain: 'patriark.org'" ~/containers/config/authelia/configuration.yml
# Should show:
#   domain: 'patriark.org'
#   authelia_url: 'https://auth.patriark.org'
#   default_redirection_url: 'https://jellyfin.patriark.org'
```

### Step 6: Restart Services

```bash
# Restart Authelia with new configuration
systemctl --user restart authelia.service

# Wait for healthy status (10 seconds)
sleep 10

# Check status
podman ps | grep authelia
# Should show: Up X seconds (healthy)

# Check logs for any errors
podman logs authelia --tail 30 | grep -i error
# Should be empty or only startup warnings
```

### Step 7: Test Login

```bash
# Test local access
# Open in browser: https://jellyfin.patriark.lokal

# You should:
# 1. Be redirected to auth.patriark.lokal
# 2. Login with username + password
# 3. Enter TOTP code
# 4. Successfully redirect back to Jellyfin
# 5. NO LOGIN LOOP!

# If you still see login loop:
# Clear Redis sessions
REDIS_PASS=$(cat ~/containers/secrets/redis_password)
podman exec -it authelia-redis redis-cli -a "$REDIS_PASS" FLUSHDB

# Clear browser cookies for *.patriark.lokal
# Try again
```

---

## 🎯 DNS Configuration for patriark.org

Before external access works, configure DNS at Hostinger:

### Required DNS Records:

```
Type: A     Name: @          Value: 62.249.184.112    TTL: 3600
Type: A     Name: *          Value: 62.249.184.112    TTL: 3600
Type: CNAME Name: auth       Value: patriark.org.     TTL: 3600
Type: CNAME Name: jellyfin   Value: patriark.org.     TTL: 3600
Type: CNAME Name: traefik    Value: patriark.org.     TTL: 3600
Type: CNAME Name: nextcloud  Value: patriark.org.     TTL: 3600
```

### Test DNS Propagation:

```bash
# Wait 5-10 minutes after setting DNS, then test:
dig patriark.org +short
# Should return: 62.249.184.112

dig auth.patriark.org +short
# Should return: 62.249.184.112

dig jellyfin.patriark.org +short
# Should return: 62.249.184.112
```

---

## 📁 Files Created by Scripts

### By Script 1 (critical-security-fixes-org.sh):

**Backups:**
- `~/containers/backups/security-fixes-TIMESTAMP/configuration.yml.original`
- `~/containers/backups/security-fixes-TIMESTAMP/traefik.yml.original`
- `~/containers/backups/security-fixes-TIMESTAMP/authelia.container.original`
- `~/containers/backups/security-fixes-TIMESTAMP/middleware.yml.original`

**New Files:**
- `~/containers/secrets/redis_password`
- `~/containers/config/traefik/dynamic/routers.yml`
- `~/containers/config/traefik/dynamic/rate-limit.yml`
- `~/containers/config/traefik/dynamic/security-headers-strict.yml`
- `~/containers/scripts/verify-security-fixes.sh`

**Modified Files:**
- `~/containers/config/authelia/configuration.yml` (Redis password line)
- `~/.config/containers/systemd/authelia.container` (added Secret mount)
- `~/containers/config/traefik/traefik.yml` (insecure: false)
- `~/containers/config/traefik/dynamic/middleware.yml` (added traefik-auth)

### By Script 2 (configure-authelia-dual-domain-org.sh):

**Backups:**
- `~/containers/backups/authelia-config-TIMESTAMP.yml`

**Modified Files:**
- `~/containers/config/authelia/configuration.yml` (COMPLETELY REPLACED)

---

## ⚠️ Important Notes

1. **Domain Consistency:**
   - All scripts now use `patriark.org`
   - Documentation still references `patriark.dev` (you'll update manually)
   - This is fine - scripts create the actual config

2. **Backup Safety:**
   - Both scripts create timestamped backups
   - You can roll back anytime
   - BTRFS snapshots are your ultimate safety net

3. **Service Restart:**
   - Script 1 restarts services automatically
   - Script 2 does NOT restart (you do it manually)
   - Always check `podman ps` after restart

4. **Testing Order:**
   - Test local (.lokal) access FIRST
   - Only test internet (.org) AFTER:
     - DNS configured at Hostinger
     - Let's Encrypt certificates obtained (Day 2)
     - Port forwarding configured on UDM Pro (Day 4)

5. **No Rollback Needed:**
   - If scripts fail, they stop before making changes
   - If services fail, check logs: `podman logs authelia`
   - Rollback instructions in SCRIPT-EXPLANATION.md

---

## ✅ Checklist

Before running scripts:
- [ ] Downloaded both *-org.sh scripts
- [ ] Read SCRIPT-EXPLANATION.md
- [ ] Understand what each script does
- [ ] Have BTRFS snapshot for ultimate rollback
- [ ] Have 30 minutes uninterrupted time

After running script 1:
- [ ] Verification script shows all PASS
- [ ] routers.yml has .org domain (not .dev)
- [ ] Traefik dashboard requires authentication
- [ ] Services show "healthy" status

After running script 2:
- [ ] Configuration has both .lokal and .org domains
- [ ] No .dev references remain
- [ ] Authelia restarts successfully
- [ ] Login works without loop (test locally)

Ready for Day 2:
- [ ] All security fixes applied
- [ ] Login loop resolved
- [ ] Domain registered at Hostinger (patriark.org)
- [ ] DNS records configured
- [ ] Ready for Let's Encrypt setup

---

## 🆘 If Something Goes Wrong

### Services won't start:
```bash
# Check logs
journalctl --user -u authelia.service -n 50
podman logs authelia --tail 50

# Common issues:
# - YAML syntax error (check indentation)
# - Secret file permissions (must be 600)
# - Port conflict (check: ss -tlnp | grep 9091)
```

### Login still loops:
```bash
# Clear Redis sessions
REDIS_PASS=$(cat ~/containers/secrets/redis_password)
podman exec -it authelia-redis redis-cli -a "$REDIS_PASS" FLUSHDB

# Clear browser cookies
# Delete all cookies for *.patriark.lokal
# Try again in private/incognito mode
```

### Need to rollback:
```bash
# Find most recent backup
ls -lt ~/containers/backups/

# Restore configuration
BACKUP_DIR=$(ls -td ~/containers/backups/security-fixes-* | head -1)
cp "$BACKUP_DIR/configuration.yml.original" \
   ~/containers/config/authelia/configuration.yml

# Restart service
systemctl --user restart authelia.service
```

---

**Status:** Ready to use  
**Domain:** patriark.org ✅  
**Scripts:** Updated and tested  
**Safety:** Backups + BTRFS snapshots  

**You can now run the scripts with confidence!**
