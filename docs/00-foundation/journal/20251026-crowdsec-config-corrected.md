# CrowdSec Configuration Clarification & Correction

**CRITICAL:** Addressing confusion between LAPI and CAPI modes
**Your Current Setup:** Working correctly - don't break it!
**Last Updated:** October 26, 2025

---

## ⚠️  IMPORTANT: You Were Right to Question This!

The previous configuration guide contained a **conceptual error** mixing two different CrowdSec operational modes. Let me clarify what's actually happening and what will work.

---

## Understanding CrowdSec Architecture

### Your Current Setup (Working ✅)

```
┌─────────────────────────────────────────────────────────┐
│  CURRENT ARCHITECTURE (CORRECT)                          │
└─────────────────────────────────────────────────────────┘

Traefik Container (with bouncer plugin)
    │
    │ HTTP queries
    ↓
CrowdSec Container (LAPI - Local API)
    │
    │ (CrowdSec engine makes decisions based on logs)
    │
    └→ Decisions stored in local database
    
Network: systemd-reverse_proxy (10.89.2.0/24)
  - Traefik:   10.89.2.3
  - CrowdSec:  10.89.2.2
```

**How it works:**
1. Traefik plugin queries `http://crowdsec:8080` (LAPI)
2. CrowdSec analyzes logs and makes ban decisions
3. Bouncer gets decision: "ban this IP" or "allow"
4. Traefik enforces the decision

This is `crowdsecMode: live` - **Your current mode ✅**

---

## The Confusion: LAPI vs CAPI

### What I Got Wrong

The previous guide mixed two concepts:

**LAPI (Local API) - What you're using:**
- CrowdSec container exposes API on port 8080
- Bouncer plugin queries this local API
- Mode: `crowdsecMode: live`
- **No machine ID/password needed in bouncer config**

**CAPI (Central API) - Community blocklist:**
- CrowdSec *container* (not bouncer!) connects to CrowdSec cloud
- Downloads global blocklist
- Shares your local detections (opt-in)
- **Machine ID/password configured in CrowdSec container, NOT bouncer**

### The Error in Previous Config

```yaml
# ❌ THIS IS WRONG - Don't use this!
crowdsec-bouncer:
  plugin:
    crowdsec-bouncer-traefik-plugin:
      crowdsecMode: live           # ← Using LAPI
      crowdsecCapiMachineId: "..." # ← CAPI config (wrong place!)
      crowdsecCapiPassword: "..."  # ← CAPI config (wrong place!)
```

**Why this is wrong:**
- `crowdsecMode: live` = bouncer queries local LAPI
- CAPI credentials are for CrowdSec *container*, not bouncer
- These settings don't belong in bouncer config

---

## Correct Configuration

### Current Network State Analysis

```
Your Networks:
┌────────────────────────────────────────────────────┐
│ systemd-reverse_proxy (10.89.2.0/24)              │
│   - traefik     (10.89.2.3)                        │
│   - crowdsec    (10.89.2.2) ← LAPI here           │
│   - tinyauth    (10.89.2.4)                        │
│   - jellyfin    (10.89.2.5) ← Also on media       │
└────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────┐
│ systemd-media_services (10.89.1.0/24)             │
│   - jellyfin    (10.89.1.2) ← Dual network        │
└────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────┐
│ systemd-auth_services (10.89.3.0/24)              │
│   - (empty) ← Reserved for future                  │
└────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────┐
│ web_services (unknown subnet)                      │
│   - (unknown) ← Inspect this?                      │
└────────────────────────────────────────────────────┘
```

**Important observations:**
1. ✅ Traefik and CrowdSec on same network (can communicate)
2. ✅ CrowdSec LAPI accessible at `http://crowdsec:8080`
3. ✅ Jellyfin on dual networks (reverse_proxy + media_services)
4. ⚠️  `web_services` network exists but unknown contents

### Correct Bouncer Configuration (LAPI Only)

**This is what you should actually use:**

```yaml
http:
  middlewares:
    crowdsec-bouncer:
      plugin:
        crowdsec-bouncer-traefik-plugin:
          # ════════════════════════════════════════════════
          # BASIC CONFIGURATION (Keep what's working!)
          # ════════════════════════════════════════════════
          enabled: true
          logLevel: INFO
          
          # ════════════════════════════════════════════════
          # LAPI CONNECTION (Local CrowdSec API)
          # ════════════════════════════════════════════════
          crowdsecMode: live                    # Query local LAPI
          crowdsecLapiScheme: http
          crowdsecLapiHost: crowdsec:8080       # CrowdSec container
          crowdsecLapiKey: <your-api-key>       # Bouncer API key
          # OR (better):
          # crowdsecLapiKeyFile: /run/secrets/crowdsec_api_key
          
          # ════════════════════════════════════════════════
          # CACHING (Improves performance)
          # ════════════════════════════════════════════════
          updateIntervalSeconds: 60             # Refresh cache every 60s
          defaultDecisionSeconds: 60            # Default ban duration
          
          # ════════════════════════════════════════════════
          # IP DETECTION (CRITICAL!)
          # ════════════════════════════════════════════════
          forwardedHeadersCustomName: X-Forwarded-For
          clientTrustedIPs:
            - 10.89.2.0/24                      # Trust reverse_proxy network
            - 10.89.1.0/24                      # Trust media_services network
            - 10.89.3.0/24                      # Trust auth_services network
            - 192.168.1.0/24                    # Trust local network
          
          # ════════════════════════════════════════════════
          # BEHAVIOR
          # ════════════════════════════════════════════════
          httpTimeoutSeconds: 10
          crowdsecLapiTLSInsecureVerify: false
          
          # ════════════════════════════════════════════════
          # CAPI - REMOVE THESE (They don't belong here!)
          # ════════════════════════════════════════════════
          # ❌ DO NOT ADD:
          # crowdsecCapiMachineId: "..."
          # crowdsecCapiPassword: "..."
          # crowdsecCapiScenarios: [...]
```

---

## How to Enable CAPI (The Right Way)

CAPI is configured **in the CrowdSec container**, not in the Traefik bouncer!

### Step 1: Enroll CrowdSec Container

```bash
# 1. Register at https://app.crowdsec.net
# 2. Create a Security Engine
# 3. Get enrollment key
# 4. Enroll your CrowdSec instance:

podman exec crowdsec cscli console enroll <your-enrollment-key>

# Verify enrollment
podman exec crowdsec cscli console status
# Should show: "You are enrolled to the Console!"
```

### Step 2: Verify CAPI is Working

```bash
# Check CAPI status (in CrowdSec container)
podman exec crowdsec cscli capi status

# Output should show:
# ✓ CAPI is enabled
# ✓ Community blocklist enabled
# ✓ Pulling blocklists every X hours
```

### Step 3: Subscribe to Scenarios

```bash
# Install community scenarios
podman exec crowdsec cscli scenarios install crowdsecurity/http-probing
podman exec crowdsec cscli scenarios install crowdsecurity/http-crawl-non_statics
podman exec crowdsec cscli scenarios install crowdsecurity/http-sensitive-files

# List installed scenarios
podman exec crowdsec cscli scenarios list

# Restart CrowdSec to apply
podman restart crowdsec
```

### Step 4: Verify It's Working

```bash
# Check decisions (should include CAPI blocklist)
podman exec crowdsec cscli decisions list

# You'll see:
# - Local decisions (from your logs)
# - CAPI decisions (from community blocklist)

# Check metrics
podman exec crowdsec cscli metrics
```

**That's it!** The bouncer will automatically get CAPI decisions through LAPI queries. No bouncer config changes needed!

---

## How CAPI Actually Works

```
┌─────────────────────────────────────────────────────────┐
│  CAPI ARCHITECTURE (Correct Understanding)               │
└─────────────────────────────────────────────────────────┘

[CrowdSec Cloud / Central API]
         │
         │ HTTPS (enrolls, pulls blocklists)
         ↓
[CrowdSec Container]
    │
    ├─→ Analyzes local logs → Local decisions
    ├─→ Receives CAPI blocklist → CAPI decisions
    │
    │ Both stored in local database
    │
    │ Exposed via LAPI (http://crowdsec:8080)
    ↓
[Traefik Bouncer Plugin]
    │
    │ Queries LAPI for ALL decisions
    │ (doesn't know/care if from local or CAPI)
    ↓
[Blocks requests based on decisions]
```

**Key insight:** 
- Bouncer only talks to LAPI
- LAPI serves decisions from both local detection AND CAPI
- Bouncer doesn't need CAPI credentials!

---

## Minimal Safe Improvements to Current Config

### Option 1: Just Add Caching and IP Detection (Safest)

```yaml
http:
  middlewares:
    crowdsec-bouncer:
      plugin:
        crowdsec-bouncer-traefik-plugin:
          enabled: true
          logLevel: INFO                        # ← Add this
          
          crowdsecMode: live
          crowdsecLapiScheme: http
          crowdsecLapiHost: crowdsec:8080
          crowdsecLapiKey: <your-key>
          
          # NEW: Performance improvements
          updateIntervalSeconds: 60             # ← Add this
          defaultDecisionSeconds: 60            # ← Add this
          
          # NEW: Correct IP detection
          forwardedHeadersCustomName: X-Forwarded-For  # ← Add this
          clientTrustedIPs:                     # ← Add this
            - 10.89.2.0/24
            - 10.89.1.0/24
            - 192.168.1.0/24
          
          httpTimeoutSeconds: 10                # ← Add this
```

**Impact:**
- ✅ Better performance (caching)
- ✅ Correct IP detection (critical!)
- ✅ Same mode (live/LAPI)
- ✅ No breaking changes

### Option 2: Move API Key to File (Security improvement)

```bash
# Create secret file
mkdir -p ~/containers/secrets
echo "your-current-api-key" > ~/containers/secrets/crowdsec_api_key
chmod 600 ~/containers/secrets/crowdsec_api_key

# Update traefik.container
# Add: Volume=%h/containers/secrets:/run/secrets:ro,Z

# Update middleware.yml
# Replace: crowdsecLapiKey: <key>
# With:    crowdsecLapiKeyFile: /run/secrets/crowdsec_api_key
```

---

## Testing Your Current Setup

### Verify Current Configuration is Working

```bash
# 1. Check bouncer is registered
podman exec crowdsec cscli bouncers list

# Output should show:
# NAME                           IP ADDRESS    VALID  LAST API PULL
# traefik-bouncer-<something>    10.89.2.3     ✓      <recent time>

# 2. Test manual ban
MY_IP=$(curl -s ifconfig.me)
podman exec crowdsec cscli decisions add --ip $MY_IP --duration 5m

# 3. Try accessing service
curl -I https://jellyfin.patriark.org
# Should return: 403 Forbidden

# 4. Check it was blocked by bouncer
podman logs traefik --tail 50 | grep $MY_IP

# 5. Remove ban
podman exec crowdsec cscli decisions delete --ip $MY_IP

# 6. Verify access works again
curl -I https://jellyfin.patriark.org
# Should return: 200 or 302 (redirect to auth)
```

### Check Current Bouncer Configuration

```bash
# View current middleware
cat ~/containers/config/traefik/dynamic/middleware.yml | grep -A 10 crowdsec-bouncer

# Check Traefik logs for CrowdSec communication
podman logs traefik | grep -i crowdsec

# Should see lines like:
# "Successfully connected to CrowdSec LAPI"
# "Pulled X decisions from LAPI"
```

---

## Network Configuration Review

### Current Network Topology

```
┌─────────────────────────────────────────────────────────┐
│  ACTUAL NETWORK STATE                                    │
└─────────────────────────────────────────────────────────┘

systemd-reverse_proxy (10.89.2.0/24)
├─ traefik   (10.89.2.3) ← Gateway to internet
├─ crowdsec  (10.89.2.2) ← Security engine
├─ tinyauth  (10.89.2.4) ← Authentication
└─ jellyfin  (10.89.2.5) ← Media (also on media network)

systemd-media_services (10.89.1.0/24)
└─ jellyfin  (10.89.1.2) ← Dual-homed (smart!)

systemd-auth_services (10.89.3.0/24)
└─ (empty) ← Reserved for future use

web_services (unknown)
└─ (unknown) ← Need to investigate
```

**Good design decisions you've made:**
1. ✅ Jellyfin on dual networks (segmentation)
2. ✅ All security services on reverse_proxy network
3. ✅ Reserved auth_services for future
4. ⚠️  Consider using auth_services for tinyauth?

### Potential Network Optimization

**Current:**
```
tinyauth on reverse_proxy network
  ↓
Can talk directly to jellyfin, crowdsec, traefik
```

**Alternative (more secure):**
```
Move tinyauth to auth_services network
  ↓
tinyauth on: reverse_proxy + auth_services
  ↓
Can only talk to traefik (reverse_proxy)
Database on auth_services (future)
```

**Benefit:** Better isolation of auth infrastructure

---

## Unknown Network Investigation

```bash
# What's on web_services network?
podman network inspect web_services

# If it's unused/legacy:
# 1. Check if any containers use it: podman ps -a
# 2. If none, can remove: podman network rm web_services
```

---

## Corrected Immediate Improvements Checklist

### Priority 1: Add IP Detection (CRITICAL)

**Why:** Without this, CrowdSec might ban Traefik's IP instead of attacker's IP!

```yaml
# Add to crowdsec-bouncer middleware:
forwardedHeadersCustomName: X-Forwarded-For
clientTrustedIPs:
  - 10.89.2.0/24    # reverse_proxy network
  - 10.89.1.0/24    # media_services network
  - 192.168.1.0/24  # local network
```

**Test:**
```bash
# After applying, test with your real IP
curl -I https://jellyfin.patriark.org

# Ban yourself temporarily
podman exec crowdsec cscli decisions add --ip $(curl -s ifconfig.me) --duration 1m

# Should get 403
curl -I https://jellyfin.patriark.org

# Wait 1 minute, should work again
```

### Priority 2: Add Caching (Performance)

```yaml
# Add to crowdsec-bouncer middleware:
updateIntervalSeconds: 60
defaultDecisionSeconds: 60
```

### Priority 3: Move API Key to File (Security)

Follow steps in "Option 2" above.

### Priority 4: Enable CAPI (Optional)

Follow "How to Enable CAPI (The Right Way)" section above.
**Important:** This is done in CrowdSec container, not bouncer config!

---

## What NOT to Do

### ❌ Don't Add These to Bouncer Config

```yaml
# ❌ WRONG - These don't work in bouncer config!
crowdsecCapiMachineId: "..."
crowdsecCapiPassword: "..."
crowdsecCapiScenarios: [...]

# These are configured in CrowdSec container via CLI:
# podman exec crowdsec cscli console enroll <key>
```

### ❌ Don't Change Mode Without Understanding

```yaml
# ❌ Don't randomly change this!
crowdsecMode: live    # Keep this!

# Other modes exist (stream, none) but require different setup
# Stick with 'live' - it works!
```

### ❌ Don't Remove Working Settings

Keep these as-is:
- `crowdsecMode: live`
- `crowdsecLapiScheme: http`
- `crowdsecLapiHost: crowdsec:8080`
- `crowdsecLapiKey` (or move to file)

---

## Summary: What to Actually Do

### Safe Changes (Won't Break Anything)

```yaml
# Your current working config:
crowdsec-bouncer:
  plugin:
    crowdsec-bouncer-traefik-plugin:
      enabled: true
      crowdsecMode: live
      crowdsecLapiScheme: http
      crowdsecLapiHost: crowdsec:8080
      crowdsecLapiKey: <your-key>
      
      # SAFE ADDITIONS (just add these):
      logLevel: INFO
      updateIntervalSeconds: 60
      defaultDecisionSeconds: 60
      httpTimeoutSeconds: 10
      
      forwardedHeadersCustomName: X-Forwarded-For
      clientTrustedIPs:
        - 10.89.2.0/24
        - 10.89.1.0/24
        - 192.168.1.0/24
      
      crowdsecLapiTLSInsecureVerify: false
```

### CAPI Enable (Separate from Bouncer)

```bash
# Do this on command line, NOT in bouncer config:
podman exec crowdsec cscli console enroll <enrollment-key>
podman exec crowdsec cscli scenarios install crowdsecurity/http-probing
podman restart crowdsec
```

---

## Apology and Clarification

**I apologize** for the confusion in the previous guide. The mixing of LAPI bouncer config with CAPI container config was a significant error that could have broken your working setup.

**Key lessons:**
1. **Bouncer config** = How bouncer talks to local LAPI
2. **CAPI config** = How CrowdSec container talks to cloud
3. **These are separate** and configured in different places
4. **Your current setup is correct** - just needs safe enhancements

**Thank you** for questioning the configuration - that's exactly the right engineering mindset!

---

**Document Version:** 1.0 (Corrected)
**Created:** October 26, 2025
**Purpose:** Correct CrowdSec bouncer configuration and clarify LAPI vs CAPI
