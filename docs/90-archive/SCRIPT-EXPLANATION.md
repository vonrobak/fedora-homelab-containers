# Script Detailed Explanation & Domain Changes

## Domain Change: patriark.dev → patriark.org

**Good news:** The domain change is straightforward. Here's what needs to be updated:

---

## Script 1: critical-security-fixes.sh

### What This Script Does:

This script makes **5 critical security fixes** to your homelab configuration. It does NOT directly modify domain names - it only fixes security vulnerabilities.

### Files Modified:

1. **`~/containers/config/authelia/configuration.yml`**
   - Changes Redis password from plain text to file reference
   - Line modified: `password: '81f6a133...'` → `password: 'file:///run/secrets/redis_password'`

2. **`~/.config/containers/systemd/authelia.container`** (quadlet)
   - Adds secret mount for redis_password
   - Adds line: `Secret=redis_password,type=mount,target=/run/secrets/redis_password,mode=0400`

3. **`~/containers/secrets/redis_password`** (NEW FILE)
   - Creates secret file containing your Redis password
   - Permissions: 600 (read/write for owner only)

4. **`~/containers/config/traefik/traefik.yml`**
   - Changes `insecure: true` → `insecure: false`
   - Secures Traefik API dashboard

5. **`~/containers/config/traefik/dynamic/middleware.yml`**
   - Adds `traefik-auth` middleware (Authelia forward auth)
   - APPENDS to existing file (doesn't overwrite)

6. **`~/containers/config/traefik/dynamic/routers.yml`** (NEW FILE)
   - Creates router for Traefik dashboard
   - **⚠️ CONTAINS DOMAIN:** Line 128 has `patriark.dev`

7. **`~/containers/config/traefik/dynamic/rate-limit.yml`** (NEW FILE)
   - Creates rate limiting middleware
   - No domain references

8. **`~/containers/config/traefik/dynamic/security-headers-strict.yml`** (NEW FILE)
   - Creates strict security headers
   - No domain references

9. **Backup files created in:**
   - `~/containers/backups/security-fixes-TIMESTAMP/`
   - All original files backed up before modification

### Domain References in Script 1:

**LINE 128 of routers.yml (created by script):**
```yaml
rule: "Host(`traefik.patriark.lokal`) || Host(`traefik.patriark.dev`)"
```

**CHANGE TO:**
```yaml
rule: "Host(`traefik.patriark.lokal`) || Host(`traefik.patriark.org`)"
```

### Step-by-Step What Happens:

1. **Creates backup directory** with timestamp
2. **Extracts Redis password** from your current config (line 79)
3. **Creates secret file** at `~/containers/secrets/redis_password` with password inside
4. **Updates configuration.yml** to reference secret file instead of plain text
5. **Updates authelia.container** to mount the secret file
6. **Changes Traefik** from insecure to secure mode
7. **Creates middleware** for Traefik authentication via Authelia
8. **Creates router** for Traefik dashboard (THIS HAS .dev)
9. **Creates rate limiting** rules
10. **Creates security headers**
11. **Reloads systemd** units
12. **Restarts services** (Authelia, then Traefik)
13. **Verifies** services are healthy

### Critical Notes for Script 1:

- ✅ **Safe to run** - creates backups first
- ✅ **Idempotent** - can run multiple times safely
- ✅ **Validation** - checks files exist before modifying
- ⚠️ **One domain reference** - Line 128 in routers.yml needs manual edit

---

## Script 2: configure-authelia-dual-domain.sh

### What This Script Does:

This script **COMPLETELY REPLACES** your Authelia configuration with a new one that supports both `.lokal` (LAN) and `.org` (internet) domains. This is what fixes the login loop.

### Files Modified:

1. **`~/containers/config/authelia/configuration.yml`**
   - **COMPLETELY REPLACED** with new configuration
   - Backup created first at `~/containers/backups/authelia-config-TIMESTAMP.yml`

### Domain References in Script 2:

This script has **MANY domain references** that need changing:

**Line 31-32 (comments):**
```yaml
# Domains: patriark.lokal (LAN) + patriark.dev (Internet)
```
Change to: `+ patriark.org (Internet)`

**Line 59 (TOTP issuer):**
```yaml
issuer: 'patriark.dev'
```
Change to: `issuer: 'patriark.org'`

**Lines 107-132 (access_control rules):**
```yaml
- domain:
    - 'auth.patriark.lokal'
    - 'auth.patriark.dev'      # Change to .org
  policy: 'bypass'

- domain:
    - 'traefik.patriark.lokal'
    - 'traefik.patriark.dev'   # Change to .org
  policy: 'two_factor'
  networks:
    - 'internal'
    - 'vpn'

- domain:
    - 'jellyfin.patriark.lokal'
    - 'jellyfin.patriark.dev'  # Change to .org
  policy: 'two_factor'

- domain:
    - 'nextcloud.patriark.lokal'
    - 'nextcloud.patriark.dev'     # Change to .org
    - 'vaultwarden.patriark.lokal'
    - 'vaultwarden.patriark.dev'   # Change to .org
  policy: 'two_factor'
```

**Lines 149-165 (session cookies - CRITICAL):**
```yaml
cookies:
  # LAN access via .lokal domain
  - domain: 'patriark.lokal'
    authelia_url: 'https://auth.patriark.lokal'
    default_redirection_url: 'https://jellyfin.patriark.lokal'
    # ... (no changes needed here)
  
  # Internet access via .dev domain
  - domain: 'patriark.dev'                              # Change to .org
    authelia_url: 'https://auth.patriark.dev'           # Change to .org
    default_redirection_url: 'https://jellyfin.patriark.dev'  # Change to .org
```

**Lines 191-193 (SMTP sender - cosmetic):**
```yaml
smtp:
  # ...
  sender: 'Authelia <auth@patriark.dev>'     # Change to .org
  identifier: 'patriark.dev'                 # Change to .org
```

### Step-by-Step What Happens:

1. **Backs up** current configuration.yml
2. **Creates NEW configuration** as `.new` file
3. **Shows diff** between old and new (you review changes)
4. **Asks for confirmation** (type 'yes' or 'no')
5. If yes: **Replaces** configuration.yml with new version
6. **Sets permissions** to 600
7. **Validates YAML** syntax (if yamllint installed)
8. **Tests** with Authelia validator container
9. **Provides instructions** for next steps (restart service)

### Critical Notes for Script 2:

- ⚠️ **REPLACES entire config** - backup created first
- ⚠️ **Many domain references** - all `.dev` → `.org`
- ✅ **Shows diff** before applying
- ✅ **Requires confirmation** - you must type 'yes'
- ⚠️ **Does NOT restart services** - you do this manually

---

## Summary: What Needs Changing?

### Script 1: critical-security-fixes.sh
**1 domain reference** to change:

```bash
# Line 128 in the routers.yml section
OLD: rule: "Host(`traefik.patriark.lokal`) || Host(`traefik.patriark.dev`)"
NEW: rule: "Host(`traefik.patriark.lokal`) || Host(`traefik.patriark.org`)"
```

### Script 2: configure-authelia-dual-domain.sh  
**11+ domain references** to change:

All instances of `patriark.dev` → `patriark.org`

**Quick find/replace locations:**
- Line 31-32 (comment)
- Line 59 (TOTP issuer)
- Lines 107-132 (access_control domains - 5 instances)
- Lines 149-165 (session cookies - 3 instances)
- Lines 191-193 (SMTP config - 2 instances)

---

## Updated Scripts

I'll create corrected versions for you with `patriark.org` domain.

### How to Use Updated Scripts:

1. **Download the NEW versions** I'm creating now
2. **Review the changes** (I'll show you exactly what changed)
3. **Run critical-security-fixes.sh** first
4. **Check the output** - it will create all the files
5. **Manually verify** the routers.yml file has `.org` not `.dev`
6. **Run configure-authelia-dual-domain.sh** second
7. **Review the diff** it shows you
8. **Type 'yes'** to apply changes
9. **Restart services** manually

---

## Safety Features:

Both scripts:
- ✅ Create backups before modifying anything
- ✅ Check if files exist before proceeding
- ✅ Use atomic operations (create .new, then replace)
- ✅ Show you what they're doing (verbose output)
- ✅ Validate configurations where possible
- ✅ Can be run multiple times safely

### Rollback Process:

If anything goes wrong:

```bash
# From script 1 backup:
BACKUP_DIR=$(ls -td ~/containers/backups/security-fixes-* | head -1)
cp "$BACKUP_DIR/configuration.yml.original" ~/containers/config/authelia/configuration.yml
cp "$BACKUP_DIR/traefik.yml.original" ~/containers/config/traefik/traefik.yml
cp "$BACKUP_DIR/authelia.container.original" ~/.config/containers/systemd/authelia.container

# From script 2 backup:
BACKUP_FILE=$(ls -t ~/containers/backups/authelia-config-*.yml | head -1)
cp "$BACKUP_FILE" ~/containers/config/authelia/configuration.yml

# Restart services
systemctl --user daemon-reload
systemctl --user restart authelia.service
systemctl --user restart traefik.service
```

---

## Files That Need Manual Domain Updates (NOT in scripts):

After running the scripts, you'll also need to update:

1. **Pi-hole DNS records** (if they exist):
   - auth.patriark.org → 192.168.1.70
   - jellyfin.patriark.org → 192.168.1.70
   - traefik.patriark.org → 192.168.1.70
   - nextcloud.patriark.org → 192.168.1.70

2. **Any existing Traefik labels** in your quadlet files:
   - Check jellyfin.container for domain labels
   - Check any other service .container files

3. **Documentation** (as you mentioned, you'll handle manually)

---

## Next: Updated Scripts

I'm now creating the corrected versions with `patriark.org` domain...
