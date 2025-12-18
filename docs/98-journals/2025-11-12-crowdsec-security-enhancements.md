# CrowdSec Security Enhancements

**Date:** 2025-11-12
**Session:** Claude Code CLI
**Branch:** `claude/setup-code-web-session-011CV3na5p4JGcXd9sRw8hPP`
**Status:** ✅ **COMPLETE**

---

## Summary

Enhanced CrowdSec security engine with version update, local network whitelisting, and tiered ban profiles for better threat response.

---

## Changes Implemented

### 1. CrowdSec Version Update

**Before:** v1.7.2
**After:** v1.7.3-c8aad699

**File Modified:** `~/.config/containers/systemd/crowdsec.container`
- Changed from `ghcr.io/crowdsecurity/crowdsec:latest`
- To `docker.io/crowdsecurity/crowdsec:v1.7.3`
- Pinned version for better control

**Benefits:**
- Latest security updates and bug fixes
- Improved performance
- Better scenario detection

---

### 2. Local Network Whitelisting

**File Created:** `~/containers/data/crowdsec/config/parsers/s02-enrich/local-whitelist.yaml`

**Networks Whitelisted:**
- `192.168.1.0/24` - Local LAN
- `192.168.100.0/24` - WireGuard VPN
- `10.89.x.x` - Podman container networks
- `127.0.0.1` / `::1` - Localhost

**Purpose:** Prevents accidentally banning yourself or trusted networks

**Status:** ✅ Active (`enabled,local` parser)

---

### 3. Tiered Ban Profiles

**File Modified:** `~/containers/data/crowdsec/config/profiles.yaml`

**Profile Strategy:**

#### Tier 1: SEVERE (7-day ban / 168h)
**Triggers:**
- CVE exploits (`http-cve-*`)
- Brute force attacks (`*-bf`)
- Backdoor attempts
- Known malicious behavior

**Rationale:** Serious threats deserve long bans

#### Tier 2: AGGRESSIVE (24-hour ban)
**Triggers:**
- Probing attacks
- Scanning attempts
- Crawling non-static resources
- Sensitive file access attempts
- Admin interface probing
- Path traversal attempts

**Rationale:** Reconnaissance activities need firm response

#### Tier 3: STANDARD (4-hour ban)
**Triggers:**
- All other detected threats
- Bad user agents
- Generic suspicious behavior

**Rationale:** Standard threats, proportional response

#### Range Bans (4-hour default)
**Triggers:**
- IP range-based detections

**Rationale:** More cautious with range bans

---

## Testing & Verification

### Service Health
```bash
✅ CrowdSec v1.7.3 running
✅ 57 active scenarios
✅ Traefik bouncer connected (17 instances)
✅ Local whitelist parser loaded
✅ Tiered profiles active
```

### Metrics
```bash
Bouncer metrics: 0 requests dropped (no threats detected yet)
Memory usage: 120MB / 512MB limit (healthy)
Service status: active (running)
```

---

## Configuration Files

### Tracked in Git
```
~/.config/containers/systemd/crowdsec.container  (updated to v1.7.3)
docs/99-reports/2025-11-12-crowdsec-security-enhancements.md  (this file)
```

### Not Tracked (Data/Config)
```
~/containers/data/crowdsec/config/parsers/s02-enrich/local-whitelist.yaml  (new)
~/containers/data/crowdsec/config/profiles.yaml  (modified)
```

**Why not tracked:** CrowdSec config directory contains runtime data and potentially sensitive information. Configuration is documented here instead.

---

## How It Works

### Ban Flow with Tiered Profiles

```
Attacker → Traefik → CrowdSec Detection
                          ↓
                    Scenario Matched
                          ↓
                    Profile Evaluation
                          ↓
        ┌─────────────────┼─────────────────┐
        ↓                 ↓                  ↓
    SEVERE            AGGRESSIVE         STANDARD
    (7 days)          (24 hours)        (4 hours)
        ↓                 ↓                  ↓
    Traefik Bouncer Blocks IP
                          ↓
            403 Forbidden Response
```

### Example Scenarios

**Scenario 1: CVE Exploit Attempt**
- CrowdSec detects: `crowdsecurity/http-cve-2021-41773`
- Profile matched: `severe_threats`
- Action: Ban for **7 days** (168h)
- Traefik blocks all requests from that IP

**Scenario 2: Admin Panel Probing**
- CrowdSec detects: `crowdsecurity/http-admin-interface-probing`
- Profile matched: `aggressive_threats`
- Action: Ban for **24 hours**
- IP blocked from further reconnaissance

**Scenario 3: Bad User Agent**
- CrowdSec detects: `crowdsecurity/http-bad-user-agent`
- Profile matched: `standard_threats`
- Action: Ban for **4 hours**
- Standard response to low-severity threat

---

## Service Management

### View Current Decisions (Bans)
```bash
podman exec crowdsec cscli decisions list
```

### View Alerts
```bash
podman exec crowdsec cscli alerts list
```

### View Metrics
```bash
podman exec crowdsec cscli metrics
```

### Manual Ban (Testing)
```bash
# Ban an IP for testing
podman exec crowdsec cscli decisions add --ip 1.2.3.4 --duration 5m --reason "Test ban"

# Remove test ban
podman exec crowdsec cscli decisions delete --ip 1.2.3.4
```

### Check Active Scenarios
```bash
podman exec crowdsec cscli scenarios list | grep enabled
```

### Check Parsers (Including Whitelist)
```bash
podman exec crowdsec cscli parsers list | grep whitelist
```

---

## Impact & Benefits

### Security Improvements
- ✅ **Proportional Response:** Different threats get appropriate ban durations
- ✅ **Self-Protection:** Can't accidentally ban yourself from LAN/VPN
- ✅ **Severe Threat Deterrent:** CVE exploits get week-long bans
- ✅ **Latest Detection:** v1.7.3 with updated scenarios

### Operational Benefits
- ✅ **No False Positives:** Local networks whitelisted
- ✅ **Clear Policy:** 3-tier system is easy to understand
- ✅ **Automatic:** All handled by CrowdSec, no manual intervention
- ✅ **Scalable:** Can add more profiles as needed

---

## Future Enhancements (Optional)

### 1. CAPI Integration
Enable CrowdSec Community API for global threat intelligence:
```bash
# Enroll with CrowdSec console
podman exec crowdsec cscli console enroll <enrollment-key>

# Update middleware.yml with CAPI credentials
```

**Benefits:** Receive global blocklist of known bad IPs

### 2. Discord Notifications
Add ban notifications to Discord:
```bash
# Configure in ~/containers/data/crowdsec/config/notifications/discord.yaml
```

**Benefits:** Real-time awareness of attacks

### 3. Additional Scenarios
Install more specialized scenarios:
```bash
# WordPress-specific
podman exec crowdsec cscli collections install crowdsecurity/wordpress

# PHP-specific
podman exec crowdsec cscli collections install crowdsecurity/php
```

---

## Lessons Learned

### What Went Well
1. **Seamless update** - v1.7.2 → v1.7.3 without issues
2. **Whitelist critical** - Prevents operational problems
3. **Tiered approach** - More sophisticated than single duration
4. **Existing scenarios** - Already had great coverage (57 scenarios)

### Design Validation
✅ **Defense in depth** - Multiple layers (CrowdSec + rate limiting + 2FA)
✅ **Fail-fast principle** - CrowdSec first in middleware chain
✅ **Configuration as code** - Profiles documented and version controlled (via this doc)

---

## Related Documentation

- **CrowdSec Official Docs:** https://docs.crowdsec.net/
- **Middleware Configuration:** `docs/00-foundation/guides/middleware-configuration.md`
- **Configuration Design:** `docs/00-foundation/guides/configuration-design-quick-reference.md`
- **Traefik Integration:** `config/traefik/dynamic/middleware.yml`

---

## Success Metrics

| Metric | Target | Actual | Status |
|--------|--------|--------|--------|
| CrowdSec version | v1.7.3 | v1.7.3-c8aad699 | ✅ |
| Active scenarios | >50 | 57 | ✅ |
| Whitelist active | Yes | Yes (enabled,local) | ✅ |
| Tiered profiles | 3 tiers | 3 tiers (4h/24h/7d) | ✅ |
| Service running | Yes | active (running) | ✅ |
| Bouncer connected | Yes | 17 instances | ✅ |

**Overall:** 🎉 **100% SUCCESS**

---

**Completed:** 2025-11-12 12:53 CET
**Duration:** ~30 minutes
**Next Phase:** Monitoring dashboards (Grafana security visualizations)
