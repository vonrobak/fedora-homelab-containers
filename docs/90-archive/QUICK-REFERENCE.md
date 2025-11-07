> **🗄️ ARCHIVED:** 2025-11-07
>
> **Reason:** Commands and scripts outdated, superseded by service-specific guides
>
> **Superseded by:** Service guides in `docs/10-services/guides/` (traefik.md, jellyfin.md, etc.)
>
> **Historical context:** Early quick reference created during week 2 to consolidate common commands. As services matured, each service got its own comprehensive guide with up-to-date commands, making this generic quick reference obsolete.
>
> **Value:** Shows what operations were most commonly needed during early deployment phase
>
> ---

# Quick Reference: patriark.org Scripts

**Domain:** patriark.org ✅ (not .dev)
**Scripts:** Updated for .org domain
**Status:** Ready to use

---

## 📦 Files to Use

### ✅ USE THESE (patriark.org):
1. **critical-security-fixes-org.sh** - Run FIRST
2. **configure-authelia-dual-domain-org.sh** - Run SECOND

### ❌ DO NOT USE (patriark.dev):
- ~~critical-security-fixes.sh~~ (wrong domain)
- ~~configure-authelia-dual-domain.sh~~ (wrong domain)

---

## 🚀 Quick Start (5 minutes)

```bash
# 1. Copy scripts
cd ~/containers/scripts
cp /path/to/outputs/critical-security-fixes-org.sh .
cp /path/to/outputs/configure-authelia-dual-domain-org.sh .
chmod +x *-org.sh

# 2. Run security fixes
./critical-security-fixes-org.sh
# Takes ~2 minutes, restarts services automatically

# 3. Verify fixes worked
./verify-security-fixes.sh
# Should show all ✓ PASS

# 4. Run dual-domain config
./configure-authelia-dual-domain-org.sh
# Review diff, type 'yes' when prompted

# 5. Restart Authelia
systemctl --user restart authelia.service
sleep 10

# 6. Test login
# Open: https://jellyfin.patriark.lokal
# Login should work WITHOUT loop!
```

---

## 📋 What Each Script Does

### Script 1: critical-security-fixes-org.sh

**Fixes 5 security vulnerabilities:**
1. ✅ Redis password (plain text → secret file)
2. ✅ Traefik dashboard (insecure → authenticated)
3. ✅ Rate limiting (none → configured)
4. ✅ Security headers (basic → strict)
5. ✅ Access control (prepared for review)

**Files it modifies:**
- `~/containers/config/authelia/configuration.yml` (1 line)
- `~/.config/containers/systemd/authelia.container` (adds secret)
- `~/containers/config/traefik/traefik.yml` (1 line)
- Creates 4 new files in `~/containers/config/traefik/dynamic/`
- Creates backup in `~/containers/backups/security-fixes-TIMESTAMP/`

**Domain references:** 1 (line 128 in routers.yml)

### Script 2: configure-authelia-dual-domain-org.sh

**Fixes login loop + adds dual-domain support:**
1. ✅ Supports .lokal (LAN) and .org (internet)
2. ✅ Fixes session cookie configuration
3. ✅ Enables WebAuthn for both domains
4. ✅ Configures SMTP notifications
5. ✅ Updates access control rules

**Files it modifies:**
- `~/containers/config/authelia/configuration.yml` (REPLACES entirely)
- Creates backup: `~/containers/backups/authelia-config-TIMESTAMP.yml`

**Domain references:** 14 (all .dev → .org)

---

## 🔍 Verification Commands

```bash
# Check domain is .org (not .dev)
grep "patriark\." ~/containers/config/traefik/dynamic/routers.yml
# Should show: patriark.lokal and patriark.org

grep "patriark\." ~/containers/config/authelia/configuration.yml | head -10
# Should show: patriark.lokal and patriark.org

# Verify no .dev references
grep -r "patriark\.dev" ~/containers/config/ 2>/dev/null
# Should be empty (no results)

# Check services healthy
podman ps | grep -E "authelia|traefik"
# Should show: (healthy) for both
```

---

## 📝 What Changed from .dev to .org

**Script 1:** 1 change
- Line 128: `traefik.patriark.dev` → `traefik.patriark.org`

**Script 2:** 14 changes
- All instances of `patriark.dev` → `patriark.org`
- TOTP issuer, access control rules, session cookies, SMTP config

**See:** DOMAIN-CHANGE-SUMMARY.md for complete details

---

## 🎯 Next Steps After Scripts

1. **Register domain** at Hostinger (patriark.org)
2. **Configure DNS** records (A, CNAME)
4. **Test local** access (.lokal domain)
5. **Proceed to Day 2** (Let's Encrypt)

---

## 📚 Documentation Files

**Start here:**
- **README.md** - Complete overview
- **QUICK-START-GUIDE.md** - 30-minute getting started

**Detailed info:**
- **SCRIPT-EXPLANATION.md** - What scripts do, line by line
- **DOMAIN-CHANGE-SUMMARY.md** - All changes made for .org

**Implementation:**
- **week02-implementation-plan.md** - 5-day roadmap
- **WEEK-2-CHECKLIST.md** - Progress tracker

---

## ⚠️ Important

**Run order:**
1. FIRST: `critical-security-fixes-org.sh`
2. SECOND: `configure-authelia-dual-domain-org.sh`
3. THEN: Test and verify

**Don't skip:**
- Reading SCRIPT-EXPLANATION.md
- Verifying changes after each script
- Testing local access before external

**Safety:**
- Both scripts create backups first
- BTRFS snapshots are your ultimate rollback
- Scripts are idempotent (safe to run multiple times)

---

## 🆘 Problems?

**Services won't start:**
```bash
podman logs authelia --tail 50
journalctl --user -u authelia.service -n 50
```

**Login still loops:**
```bash
# Clear sessions
podman exec -it authelia-redis redis-cli -a "$(cat ~/containers/secrets/redis_password)" FLUSHDB
# Clear browser cookies
# Try in private/incognito mode
```

**Need rollback:**
```bash
# Restore from most recent backup
ls -lt ~/containers/backups/
# Copy files back from backup directory
```

**More help:**
- See SCRIPT-EXPLANATION.md → "Rollback Process"
- See DOMAIN-CHANGE-SUMMARY.md → "If Something Goes Wrong"

---

## ✅ Success Criteria

After running both scripts:
- [ ] `verify-security-fixes.sh` shows all PASS
- [ ] No .dev references: `grep -r "patriark\.dev" ~/containers/config/` is empty
- [ ] Services healthy: `podman ps` shows (healthy)
- [ ] Login works: https://jellyfin.patriark.lokal (no loop!)
- [ ] Traefik dashboard requires auth: https://traefik.patriark.lokal

**If all checks pass → Ready for Day 2 (Let's Encrypt)**

---

**Quick answer to your question:**  
✅ Scripts are updated for patriark.org  
✅ All domain references changed (.dev → .org)  
✅ Safe to run - creates backups first  
✅ Detailed explanation provided

**You're good to go!** 🚀
