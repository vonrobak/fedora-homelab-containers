# Middleware Improvement Implementation Checklist

**Purpose:** Step-by-step guide to implement middleware improvements
**Companion to:** MIDDLEWARE-CONFIGURATION-GUIDE.md
**Time Estimate:** 2-3 hours total
**Last Updated:** October 26, 2025

---

## Overview

This checklist guides you through implementing the middleware improvements in a safe, tested manner. Each step includes rollback instructions in case something goes wrong.

---

## Pre-Implementation Checklist

```
□ Current configuration backed up
□ Git initialized (or commit current state)
□ All services currently running
□ Test plan prepared
□ Time allocated (2-3 hours)
□ Documentation reviewed
```

**Backup Current Configuration:**
```bash
# Create backup
cd ~/containers
tar -czf ~/middleware-backup-$(date +%Y%m%d-%H%M%S).tar.gz \
  config/traefik/ \
  secrets/ \
  ~/.config/containers/systemd/traefik.container

# Verify backup exists
ls -lh ~/middleware-backup-*.tar.gz
```

---

## Phase 1: Secure API Key (15 minutes)

**Priority:** High (Security improvement)  
**Risk:** Low (just moving location)  
**Rollback:** Easy (keep old key in place until verified)

### Step 1.1: Create Secret File

```bash
# Get current API key from middleware.yml
CURRENT_KEY=$(grep crowdsecLapiKey ~/containers/config/traefik/dynamic/middleware.yml | cut -d':' -f2 | tr -d ' ')

# Create secrets directory if it doesn't exist
mkdir -p ~/containers/secrets
chmod 700 ~/containers/secrets

# Save key to file
echo "$CURRENT_KEY" > ~/containers/secrets/crowdsec_api_key
chmod 600 ~/containers/secrets/crowdsec_api_key

# Verify
ls -la ~/containers/secrets/crowdsec_api_key
cat ~/containers/secrets/crowdsec_api_key  # Should show your API key
```

### Step 1.2: Update Traefik Container

```bash
# Edit traefik.container
nano ~/.config/containers/systemd/traefik.container
```

**Add this line in the [Container] section:**
```ini
Volume=%h/containers/secrets:/run/secrets:ro,Z
```

**Full example:**
```ini
[Container]
Image=docker.io/traefik:v3.2
# ... other settings ...
Volume=%h/containers/config/traefik:/etc/traefik:Z
Volume=%h/containers/secrets:/run/secrets:ro,Z  # ← ADD THIS LINE
```

### Step 1.3: Update Middleware Configuration

```bash
# Edit middleware.yml
nano ~/containers/config/traefik/dynamic/middleware.yml
```

**Change:**
```yaml
# OLD (remove this line)
crowdsecLapiKey: your-key-here

# NEW (add this line)
crowdsecLapiKeyFile: /run/secrets/crowdsec_api_key
```

### Step 1.4: Test Changes

```bash
# Reload systemd
systemctl --user daemon-reload

# Restart Traefik
systemctl --user restart traefik.service

# Wait a few seconds
sleep 5

# Check Traefik is running
systemctl --user status traefik.service

# Check logs for errors
podman logs traefik --tail 50 | grep -i error
podman logs traefik --tail 50 | grep -i crowdsec

# Test access to a service
curl -I https://jellyfin.patriark.org
```

**✅ Success criteria:**
- Traefik starts successfully
- No errors in logs about CrowdSec
- Services still accessible

**❌ Rollback if needed:**
```bash
# Restore backup
cd ~/containers
tar -xzf ~/middleware-backup-*.tar.gz

# Restart Traefik
systemctl --user daemon-reload
systemctl --user restart traefik.service
```

**Checkpoint:** ✅ API key now stored securely in file

---

## Phase 2: Enhanced CrowdSec Configuration (20 minutes)

**Priority:** High (Better IP detection and caching)  
**Risk:** Low (just adding parameters)  
**Rollback:** Easy (remove new parameters)

### Step 2.1: Backup Current Middleware

```bash
cp ~/containers/config/traefik/dynamic/middleware.yml \
   ~/containers/config/traefik/dynamic/middleware.yml.before-phase2
```

### Step 2.2: Add Advanced CrowdSec Parameters

```bash
nano ~/containers/config/traefik/dynamic/middleware.yml
```

**Update crowdsec-bouncer section to:**
```yaml
crowdsec-bouncer:
  plugin:
    crowdsec-bouncer-traefik-plugin:
      enabled: true
      logLevel: INFO
      updateIntervalSeconds: 60
      defaultDecisionSeconds: 60
      
      # LAPI Connection
      crowdsecMode: live
      crowdsecLapiScheme: http
      crowdsecLapiHost: crowdsec:8080
      crowdsecLapiKeyFile: /run/secrets/crowdsec_api_key
      
      # IP Detection (IMPORTANT!)
      forwardedHeadersCustomName: X-Forwarded-For
      clientTrustedIPs:
        - 10.89.2.0/24    # reverse_proxy network
        - 192.168.1.0/24  # local network
      
      # Behavior
      httpTimeoutSeconds: 10
      crowdsecLapiTLSInsecureVerify: false
```

### Step 2.3: Test Changes

```bash
# Restart Traefik (Traefik watches files, but restart ensures clean state)
systemctl --user restart traefik.service

# Wait
sleep 5

# Check logs
podman logs traefik --tail 50 | grep crowdsec

# Test IP detection works
curl -I https://jellyfin.patriark.org
# Should work

# Verify CrowdSec connection
podman exec crowdsec cscli bouncers list
# Should show traefik-bouncer as active
```

**✅ Success criteria:**
- Traefik starts successfully
- CrowdSec bouncer shows as active
- No errors in logs
- Services accessible

**Checkpoint:** ✅ CrowdSec configuration enhanced

---

## Phase 3: Tiered Rate Limiting (15 minutes)

**Priority:** Medium (Better protection for different services)  
**Risk:** Low (just adding new middlewares)  
**Rollback:** Easy (just don't use them in routers)

### Step 3.1: Add Rate Limit Variants

```bash
nano ~/containers/config/traefik/dynamic/middleware.yml
```

**Add after existing rate-limit middleware:**
```yaml
    # Standard rate limit (keep existing one)
    rate-limit:
      rateLimit:
        average: 100
        burst: 50
        period: 1m
        sourceCriterion:
          requestHost: true
          ipStrategy:
            depth: 1
    
    # NEW: Strict rate limit for sensitive endpoints
    rate-limit-strict:
      rateLimit:
        average: 30
        burst: 10
        period: 1m
        sourceCriterion:
          requestHost: true
          ipStrategy:
            depth: 1
    
    # NEW: Very strict for auth endpoints
    rate-limit-auth:
      rateLimit:
        average: 10
        burst: 5
        period: 1m
        sourceCriterion:
          requestHost: true
          ipStrategy:
            depth: 1
    
    # NEW: Generous for public content
    rate-limit-public:
      rateLimit:
        average: 200
        burst: 100
        period: 1m
        sourceCriterion:
          requestHost: true
          ipStrategy:
            depth: 1
```

### Step 3.2: Update Router for Auth Service

```bash
nano ~/containers/config/traefik/dynamic/routers.yml
```

**Find your auth router and update:**
```yaml
auth-router:
  rule: "Host(`auth.patriark.org`)"
  middlewares:
    - crowdsec-bouncer@file
    - rate-limit-auth@file  # ← CHANGE from rate-limit to rate-limit-auth
    - security-headers@file
  service: tinyauth-service
  # ... rest of config
```

### Step 3.3: Test Rate Limiting

```bash
# Restart Traefik
systemctl --user restart traefik.service

# Test auth endpoint rate limit (should be stricter)
for i in {1..20}; do
  curl -s -o /dev/null -w "%{http_code}\n" https://auth.patriark.org
  sleep 0.1
done

# Should see 200/302 for first 10, then 429 (Too Many Requests)
```

**✅ Success criteria:**
- Traefik starts successfully
- Rate limits work as configured
- More restrictive on auth endpoints

**Checkpoint:** ✅ Tiered rate limiting implemented

---

## Phase 4: Enhanced Security Headers (20 minutes)

**Priority:** High (Improves security posture)  
**Risk:** Medium (CSP might break some apps)  
**Rollback:** Easy (revert to old headers)

### Step 4.1: Backup Current Headers

```bash
# Already backed up in Phase 2, but create specific backup
grep -A 20 "security-headers:" ~/containers/config/traefik/dynamic/middleware.yml > \
  ~/containers/security-headers-backup.txt
```

### Step 4.2: Update Security Headers

```bash
nano ~/containers/config/traefik/dynamic/middleware.yml
```

**Replace security-headers middleware with:**
```yaml
    security-headers:
      headers:
        # Frame options
        frameDeny: false
        customFrameOptionsValue: "SAMEORIGIN"
        
        # XSS and content type
        browserXssFilter: true
        contentTypeNosniff: true
        
        # HSTS
        stsSeconds: 31536000
        stsIncludeSubdomains: true
        stsPreload: true
        forceSTSHeader: true
        
        # Content Security Policy (START PERMISSIVE, tighten later)
        contentSecurityPolicy: "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self';"
        
        # Referrer Policy
        referrerPolicy: "strict-origin-when-cross-origin"
        
        # Permissions Policy
        permissionsPolicy: "geolocation=(), microphone=(), camera=(), payment=(), usb=()"
        
        # Custom headers
        customResponseHeaders:
          X-Content-Type-Options: "nosniff"
          X-Frame-Options: "SAMEORIGIN"
          X-XSS-Protection: "1; mode=block"
          X-Robots-Tag: "none"
          Server: ""
```

### Step 4.3: Test Each Service

```bash
# Restart Traefik
systemctl --user restart traefik.service

# Test each service in browser
# Check browser console for CSP errors

# Test Jellyfin
curl -I https://jellyfin.patriark.org | grep -i content-security

# Test with browser and check:
# 1. Does the service load?
# 2. Any console errors?
# 3. Does functionality work (play video, etc.)?
```

**If CSP breaks something:**

1. **Check browser console** for specific CSP violations
2. **Adjust CSP** to allow needed resources:
   ```yaml
   # Example: If media needs to load from CDN
   contentSecurityPolicy: "default-src 'self'; ... ; media-src 'self' https://cdn.example.com;"
   ```

**✅ Success criteria:**
- All services load correctly
- No broken functionality
- Enhanced headers visible in response

**⚠️  If service breaks:**
```bash
# Restore backup
cp ~/containers/config/traefik/dynamic/middleware.yml.before-phase2 \
   ~/containers/config/traefik/dynamic/middleware.yml

# Restart
systemctl --user restart traefik.service
```

**Checkpoint:** ✅ Enhanced security headers active

---

## Phase 5: IP Whitelisting for Admin Access (10 minutes)

**Priority:** High (Protects admin panels)  
**Risk:** Low (only applies where used)  
**Rollback:** Easy (remove from routers)

### Step 5.1: Add IP Whitelist Middleware

```bash
nano ~/containers/config/traefik/dynamic/middleware.yml
```

**Add new middleware:**
```yaml
    # Add after other middlewares
    admin-whitelist:
      ipWhiteList:
        sourceRange:
          - 192.168.1.0/24    # Local network
          - 10.89.2.0/24      # Container network
          # Add your VPN subnet if you have one
          # - 10.8.0.0/24
        ipStrategy:
          depth: 1
```

### Step 5.2: Apply to Traefik Dashboard

```bash
nano ~/containers/config/traefik/dynamic/routers.yml
```

**Update Traefik dashboard router:**
```yaml
traefik-router:
  rule: "Host(`traefik.patriark.org`)"
  middlewares:
    - crowdsec-bouncer@file
    - admin-whitelist@file     # ← ADD THIS
    - rate-limit-strict@file
    - tinyauth@file
    - security-headers@file
  service: api@internal
  # ... rest of config
```

### Step 5.3: Test

```bash
# Restart Traefik
systemctl --user restart traefik.service

# Test from local network (should work)
curl -I https://traefik.patriark.org

# Test from external IP (should get 403)
# Use your phone with mobile data or ask friend to test
# Should receive 403 Forbidden
```

**✅ Success criteria:**
- Local access works
- External access blocked (403)
- Still requires auth after IP check

**Checkpoint:** ✅ Admin access restricted by IP

---

## Phase 6: Compression for Performance (5 minutes)

**Priority:** Low (Performance improvement)  
**Risk:** Very Low (just adds compression)  
**Rollback:** Easy (remove from routers)

### Step 6.1: Add Compression Middleware

```bash
nano ~/containers/config/traefik/dynamic/middleware.yml
```

**Add:**
```yaml
    compression:
      compress:
        excludedContentTypes:
          - text/event-stream
        minResponseBodyBytes: 1024
```

### Step 6.2: Apply to Routers

```bash
nano ~/containers/config/traefik/dynamic/routers.yml
```

**Add compression to middleware chains:**
```yaml
jellyfin-router:
  rule: "Host(`jellyfin.patriark.org`)"
  middlewares:
    - crowdsec-bouncer@file
    - rate-limit@file
    - tinyauth@file
    - compression@file        # ← ADD THIS
    - security-headers@file
  service: jellyfin-service
```

### Step 6.3: Test

```bash
# Restart Traefik
systemctl --user restart traefik.service

# Test compression
curl -H "Accept-Encoding: gzip" -I https://jellyfin.patriark.org | grep -i content-encoding
# Should show: Content-Encoding: gzip
```

**✅ Success criteria:**
- Responses are compressed
- No errors
- Services work normally

**Checkpoint:** ✅ Compression enabled

---

## Phase 7: Enable CrowdSec CAPI (30 minutes)

**Priority:** High (Global threat intelligence)  
**Risk:** Low (just adds data source)  
**Rollback:** Easy (remove CAPI config)

### Step 7.1: Register with CrowdSec Console

```bash
# 1. Go to https://app.crowdsec.net
# 2. Create account / log in
# 3. Create a Security Engine
# 4. Copy enrollment key
```

### Step 7.2: Enroll Your Instance

```bash
# Enroll (replace with your key)
podman exec crowdsec cscli console enroll <your-enrollment-key>

# Verify enrollment
podman exec crowdsec cscli console status
# Should show: "You are enrolled to the Console!"

# Check CAPI status
podman exec crowdsec cscli capi status
# Should show: enabled
```

### Step 7.3: Get Machine Credentials

```bash
# List machines
podman exec crowdsec cscli machines list
# Note the machine ID (looks like: fedora-htpc-xxxxx)

# Get credentials file
podman exec crowdsec cat /etc/crowdsec/local_api_credentials.yaml

# Output will show:
# url: http://127.0.0.1:8080
# login: <machine-id>
# password: <password>

# Note these values
```

### Step 7.4: Update Middleware Configuration

```bash
nano ~/containers/config/traefik/dynamic/middleware.yml
```

**Add to crowdsec-bouncer plugin:**
```yaml
crowdsec-bouncer:
  plugin:
    crowdsec-bouncer-traefik-plugin:
      # ... existing config ...
      
      # Add CAPI configuration
      crowdsecCapiMachineId: "<machine-id-from-step-7.3>"
      crowdsecCapiPassword: "<password-from-step-7.3>"
      crowdsecCapiScenarios:
        - crowdsecurity/http-probing
        - crowdsecurity/http-crawl-non_statics
        - crowdsecurity/http-sensitive-files
        - crowdsecurity/http-bad-user-agent
        - crowdsecurity/http-path-traversal-probing
```

### Step 7.5: Verify CAPI

```bash
# Restart Traefik
systemctl --user restart traefik.service

# Check CrowdSec is pulling scenarios
podman exec crowdsec cscli hub list | grep crowdsecurity

# Check decisions from CAPI
podman exec crowdsec cscli decisions list
# Should show community blocklist entries

# View metrics
podman exec crowdsec cscli metrics
```

**✅ Success criteria:**
- CAPI status shows "enabled"
- Scenarios are installed
- Community decisions visible
- No errors in logs

**Checkpoint:** ✅ CAPI enabled (global threat intelligence active)

---

## Phase 8: Final Validation (15 minutes)

### Step 8.1: Comprehensive Service Test

```bash
# Test each service
echo "Testing Jellyfin..."
curl -I https://jellyfin.patriark.org

echo "Testing Auth..."
curl -I https://auth.patriark.org

echo "Testing Traefik Dashboard..."
curl -I https://traefik.patriark.org

# All should return 200 or 302/303 (redirect to auth)
```

### Step 8.2: Security Headers Validation

```bash
# Check all security headers
curl -I https://jellyfin.patriark.org

# Should see:
# - Strict-Transport-Security
# - X-Content-Type-Options
# - X-Frame-Options
# - Content-Security-Policy
# - Referrer-Policy
# - Permissions-Policy
```

### Step 8.3: CrowdSec Validation

```bash
# Check bouncer is active
podman exec crowdsec cscli bouncers list

# Check metrics
podman exec crowdsec cscli metrics

# Check for any errors
podman logs crowdsec --tail 50 | grep -i error
podman logs traefik --tail 50 | grep -i error
```

### Step 8.4: Rate Limiting Test

```bash
# Test auth endpoint (should be strict)
echo "Testing rate limit..."
for i in {1..15}; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://auth.patriark.org)
  echo "Request $i: $STATUS"
  sleep 0.1
done

# Should see 429 after 10-15 requests
```

### Step 8.5: Browser Testing

```
□ Open each service in browser
□ Verify functionality works
□ Check browser console for errors
□ Test authentication flow
□ Verify no CSP errors
```

---

## Post-Implementation

### Create Clean Backup

```bash
# Everything working? Create clean backup
cd ~/containers
tar -czf ~/middleware-improved-$(date +%Y%m%d).tar.gz \
  config/traefik/ \
  secrets/ \
  ~/.config/containers/systemd/traefik.container

echo "Clean backup created: ~/middleware-improved-$(date +%Y%m%d).tar.gz"
```

### Update Documentation

```bash
# Add to your Git repo (if using)
cd ~/containers
git add config/traefik/dynamic/middleware.yml
git add secrets/.gitignore  # Don't commit actual secrets!
git commit -m "Enhanced middleware configuration

- Moved CrowdSec API key to secret file
- Added advanced CrowdSec configuration
- Implemented tiered rate limiting
- Enhanced security headers (CSP, Referrer-Policy, etc.)
- Added IP whitelisting for admin access
- Enabled compression
- Configured CAPI for global threat intelligence"
```

### Update your QUICK-REFERENCE.md

```bash
# Add note about new middlewares available
```

---

## Troubleshooting

### Issue: Traefik Won't Start

```bash
# Check config syntax
podman run --rm -v ~/containers/config/traefik:/etc/traefik:Z \
  traefik:v3.2 traefik --configFile=/etc/traefik/traefik.yml --dry-run

# Check logs
journalctl --user -u traefik.service -n 50

# Check file permissions
ls -la ~/containers/config/traefik/dynamic/
ls -la ~/containers/secrets/
```

### Issue: CrowdSec API Key Not Found

```bash
# Verify file exists
ls -la ~/containers/secrets/crowdsec_api_key

# Verify volume mount in container
podman inspect traefik | grep -A 10 Mounts

# Check file is readable
podman exec traefik cat /run/secrets/crowdsec_api_key
```

### Issue: CSP Breaking Application

```bash
# Check browser console for specific violations
# Firefox: F12 → Console → Filter "CSP"
# Chrome: F12 → Console → Filter "csp"

# Common fixes:
# - Add 'unsafe-inline' for inline scripts/styles
# - Add specific domains for external resources
# - Add 'data:' for data URIs (images)
```

### Issue: Rate Limiting Too Aggressive

```bash
# Temporarily increase limits for testing
nano ~/containers/config/traefik/dynamic/middleware.yml

# Increase average/burst values
# Test, then adjust to final values
```

### Issue: Can't Access Admin Panel

```bash
# Check if your IP is in whitelist
curl -I https://traefik.patriark.org

# If 403, add your IP:
nano ~/containers/config/traefik/dynamic/middleware.yml

# Add to admin-whitelist sourceRange
# Restart Traefik
```

---

## Success Metrics

After completing all phases, you should have:

```
✅ CrowdSec API key stored securely
✅ Enhanced CrowdSec configuration (IP detection, caching)
✅ CAPI enabled (global threat intelligence)
✅ Tiered rate limiting (public/standard/strict/auth)
✅ Comprehensive security headers (CSP, HSTS, etc.)
✅ IP whitelisting for admin panels
✅ Compression for better performance
✅ All services working correctly
✅ No errors in logs
✅ Clean backup of working configuration
✅ Documentation updated
```

---

## Estimated Time Breakdown

```
Phase 1: Secure API Key           - 15 minutes
Phase 2: Enhanced CrowdSec         - 20 minutes
Phase 3: Tiered Rate Limiting      - 15 minutes
Phase 4: Enhanced Security Headers - 20 minutes
Phase 5: IP Whitelisting           - 10 minutes
Phase 6: Compression               - 5 minutes
Phase 7: Enable CAPI               - 30 minutes
Phase 8: Final Validation          - 15 minutes
─────────────────────────────────────────────
TOTAL:                             ~2.5 hours
```

---

**Good luck with your implementation!**

Remember: Take it phase by phase, test thoroughly after each change, and keep backups. If anything goes wrong, you can always roll back to the previous working state.

**Document Version:** 1.0  
**Created:** October 26, 2025  
**Purpose:** Step-by-step implementation guide for middleware improvements
