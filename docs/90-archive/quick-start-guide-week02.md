# Week 2 Quick Start Guide
**Secure Internet Exposure Implementation**

## 📋 Files You've Received

1. **week02-implementation-plan.md** (29KB)
   - Complete 5-day roadmap
   - Detailed task breakdown
   - Troubleshooting guide
   - Security best practices

2. **critical-security-fixes.sh** (14KB)
   - Automated security hardening
   - Fixes ALL critical vulnerabilities
   - **RUN THIS FIRST!**

3. # (Abandoned due to complexity - replaced Authelia with tinyauth) **configure-authelia-dual-domain.sh** (7.6KB)
   - Updates Authelia for .lokal + .dev domains
   - Fixes login loop bug
   - Enables WebAuthn

4. **pre-letsencrypt-diagnostic.sh** (17KB)
   - Already run - diagnostic report received

---

## 🚨 CRITICAL: Before You Start

### Your Current Security Status
Based on diagnostic analysis:

**VULNERABILITIES FOUND:**
- ⚠️ **HIGH:** Redis password in plain text (line 79 of configuration.yml)
- ⚠️ **HIGH:** Traefik API dashboard exposed without auth (port 8080)
- ⚠️ **MEDIUM:** No SMTP = no account recovery/notifications
- ⚠️ **MEDIUM:** Self-signed certs breaking session cookies (login loop)
- ⚠️ **MEDIUM:** No rate limiting on public entrypoints

**DO NOT expose to internet until these are fixed!**

---

## ⚡ Getting Started (30 Minutes)

### Step 1: Run Security Fixes - Status: finalized!

```bash
# Copy scripts to your homelab
cd ~/containers/scripts
cp /path/to/outputs/*.sh .
chmod +x *.sh

# IMPORTANT: Run security fixes FIRST
./critical-security-fixes.sh

# This will:
# - Move Redis password to secret file
# - Secure Traefik dashboard
# - Add rate limiting
# - Create backups
# - Restart services safely
```

**What it does:**
- Backs up all configs to `~/containers/backups/security-fixes-TIMESTAMP/`
- Fixes 5 critical vulnerabilities
- Restarts services with new configuration
- Creates verification script
- backups sent to encrypted external drive to not expose possible secrets

**Verify fixes worked:**
```bash
./verify-security-fixes.sh
# Should show: ✓ PASS for all checks
```

### Step 2: Register Domain is finalised

1. Go to [Hostinger.com](https://hostinger.com) - finalized!
2. Register `patriark.org` (€8-12/year) - Finalized
3. Cloudflare for DNS and local DynDNS script to update (runs every 30 minutes) - Finalized!
4. 
   - A record: @ (only dns, not orange cloud proxy) pointing to public ip
   - A record: * (only dns, not orange cloud proxy) pointing to public ip
5. Get API token:
   - # Hostinger Dashboard → API → Create Token (unavailable for some reason)
   - Got Cloudflare API token instead
   - Copied token, saved securely in ~/containers/secrets

**Test DNS propagation:**
```bash
# Wait 5-10 minutes, then test:
dig patriark.org +short
# Should return: 62.249.184.112

dig auth.patriark.org +short  
# Should return: 62.249.184.112
```
 - both works and Jellyfin, tinyauth and Traefik are reachable through patriark.org both locally and remotely. Certificate warnings happens and there are some login loop issues with tinyauth (likely due to both auth.patriark.lokal and auth.patriark.org is referenced in configs)
---

## 🔄 Day 1: Complete Security Hardening # - abandoned due to Authelia complexity. Authelia removed and replaced with tinyauth.

Now that prerequisites are done, run the dual-domain configuration:

```bash
cd ~/containers/scripts

# Update Authelia for both .lokal and .dev domains - Abandoned Authelia for tinyauth
./configure-authelia-dual-domain.sh

# Review the diff carefully
# Type 'yes' when prompted to apply changes

# Restart Authelia
systemctl --user restart authelia.service

# Wait 10 seconds
sleep 10

# Check status
podman ps | grep authelia
# Should show: Up X seconds (healthy)
```

**Test LAN access:**
1. Open: https://jellyfin.patriark.lokal
2. Login with username + password
3. Enter TOTP code
4. Should NOT loop anymore!
5. You should be logged into Jellyfin

**If login loop persists:**
```bash
# Clear Redis sessions
REDIS_PASS=$(cat ~/containers/secrets/redis_password)
podman exec -it authelia-redis redis-cli -a "$REDIS_PASS" FLUSHDB

# Clear browser cookies for *.patriark.lokal
# Try again
```

---

## 📅 Day 2-5: Follow Implementation Plan # This is where the user is currently - but with patriark.org hosted at hostinger.com, DNS provided by Cloudflare (with local update scripts for DynDNS) and no possibility for WebAuthn as it is not supported in tinyauth

Open `week02-implementation-plan.md` and follow it sequentially:

**Day 2:** Let's Encrypt setup (DNS-01 challenge)
**Day 3:** Production certificates + WebAuthn
**Day 4:** UDM Pro port forwarding + external access
**Day 5:** Monitoring + documentation

**Each day is designed for 1-2 hours of work.**

---

## 🆘 Emergency Procedures

### If Something Breaks

**Rollback to previous configuration:**
```bash
# Restore from BTRFS snapshot (your existing method)
# OR restore from tar backup:

cd ~/containers
LATEST_BACKUP=$(ls -t backups/security-fixes-*/configuration.yml.original | head -1)
cp "$LATEST_BACKUP" config/authelia/configuration.yml

# Restart services
systemctl --user restart authelia.service
systemctl --user restart traefik.service
```

### If Services Won't Start

```bash
# Check logs
journalctl --user -u authelia.service -n 50
journalctl --user -u traefik.service -n 50

# Or with podman
podman logs authelia --tail 50
podman logs traefik --tail 50

# Common issues:
# - Typo in YAML (check indentation)
# - Secret file permissions (must be 600)
# - Port already in use (check with: ss -tlnp)
```

### Get Help

If stuck, create a diagnostic report:
```bash
cd ~/containers/scripts
./authelia_diag.sh  # If you have it
# OR
podman logs authelia > ~/authelia-error.log
podman logs traefik > ~/traefik-error.log

# Check configuration syntax
yamllint ~/containers/config/authelia/configuration.yml
```

---

## ✅ Success Criteria

You'll know Day 1 is complete when:

- [ ] `verify-security-fixes.sh` shows all PASS
- [ ] Traefik dashboard at https://traefik.patriark.lokal requires login
- [ ] Jellyfin login works without loop
- [ ] Email test notification received
- [ ] Domain registered and DNS propagating
- [ ] No plain-text secrets in configs

**Once these are done, you're ready for Let's Encrypt (Day 2)!**

---

## 📞 Quick Reference

**Important paths:**
```bash
Config:   ~/containers/config/
Secrets:  ~/containers/secrets/
Quadlets: ~/.config/containers/systemd/
Scripts:  ~/containers/scripts/
Backups:  ~/containers/backups/
```

**Essential commands:**
```bash
# Restart services
systemctl --user restart authelia.service
systemctl --user restart traefik.service

# Check status
systemctl --user status authelia.service
podman ps

# View logs
podman logs -f authelia
podman logs -f traefik

# Validate Authelia config
podman run --rm -v ~/containers/config/authelia:/config:ro \
  docker.io/authelia/authelia:latest \
  authelia validate-config /config/configuration.yml
```

**Useful URLs (LAN):**
```
Authelia:  https://auth.patriark.lokal
Jellyfin:  https://jellyfin.patriark.lokal
Traefik:   https://traefik.patriark.lokal
```

---

## 🎯 Week 2 Goal

**Transform your homelab from local-only to securely internet-accessible.**

By end of Week 2 you will have:
- Valid Let's Encrypt certificates
- Working external access from anywhere
- Email notifications
- Basic monitoring
- Documentation for family members

**Timeline:** 5 days @ 1-2 hours/day = 5-10 total hours

**Confidence:** Following this plan step-by-step gives you 70-80% chance of success without major issues.

---

## 🚀 Start Now!

1. Read this entire guide (you just did! ✓)
2. Run `critical-security-fixes.sh` # finalized
3. Register domain at Hostinger # finalized - patriark.org registered
5. Run `configure-authelia-dual-domain.sh` # abandoned and replaced with tinyauth
6. Test that login works
7. Open `week02-implementation-plan.md` for Day 2

**Remember:** Security first, then functionality. Don't skip steps!

Good luck! 🎉

---

**Created:** 2025-10-22  
**For:** fedora-htpc homelab  
**Owner:** patriark  
**Status:** Ready to execute
