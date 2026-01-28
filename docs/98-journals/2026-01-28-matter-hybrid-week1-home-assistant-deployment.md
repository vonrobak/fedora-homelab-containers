# Matter Hybrid Approach: Week 1 - Home Assistant Core Infrastructure

**Date:** 2026-01-28
**Plan Reference:** `docs/97-plans/2026-01-22-monthly-review-matter-hybrid-approach.md` (Part 2, Week 1)
**Status:** Week 1 Complete ✅ | Week 2 Ready to Start
**Deployment Time:** ~20 minutes

---

## What Was Deployed

Implemented infrastructure-first Matter deployment strategy per approved hybrid approach. Week 1 focused on Home Assistant core infrastructure without devices.

### 1. Network Infrastructure

**Created:** `~/.config/containers/systemd/home_automation.network`
```
Subnet: 10.89.6.0/24
Gateway: 10.89.6.1
DNS: 192.168.1.69
```

Network operational: `podman network ls` shows `systemd-home_automation` (bridge)

### 2. Home Assistant Container

**Quadlet:** `~/.config/containers/systemd/home-assistant.container`

Key configuration:
- **Image:** `ghcr.io/home-assistant/home-assistant:stable`
- **Networks:** reverse_proxy (FIRST - default route), home_automation, monitoring
- **Memory limits:** MemoryMax=2G, MemoryHigh=1800M, MemorySwapMax=512M
- **Volumes:** `%h/containers/config/home-assistant:/config:Z`, `%h/containers/data/home-assistant:/data:Z`
- **Health check:** `curl -f http://localhost:8123/manifest.json` (30s interval)
- **Port:** 8123 published for local access

**Current state:**
```
Status: active (running) - healthy
Memory: 387MB / 2GB (19% utilization)
Uptime: Deployed 2026-01-28 01:00 CET
```

### 3. Traefik Routing (ADR-016 Compliant)

**Modified:** `~/containers/config/traefik/dynamic/routers.yml`

Added router (line ~182):
```yaml
home-assistant-secure:
  rule: "Host(`ha.patriark.org`)"
  service: "home-assistant"
  entryPoints: [websecure]
  middlewares:
    - crowdsec-bouncer@file
    - rate-limit@file
    - authelia@file
    - security-headers@file
  tls:
    certResolver: letsencrypt
```

Added service (line ~251):
```yaml
home-assistant:
  loadBalancer:
    servers:
      - url: "http://home-assistant:8123"
```

**Verification:** Traefik restarted cleanly, no errors. `curl -I -H "Host: ha.patriark.org" http://localhost` returns 308 redirect to HTTPS.

### 4. Prometheus Scraping Configuration

**Modified:** `~/containers/config/prometheus/prometheus.yml`

Added scrape target (line ~107):
```yaml
- job_name: 'home-assistant'
  static_configs:
    - targets: ['home-assistant:8123']
      labels:
        instance: 'fedora-htpc'
        service: 'home-assistant'
  metrics_path: '/api/prometheus'
  bearer_token: 'PLACEHOLDER_TOKEN'  # TODO: Generate HA token
```

**Status:** Configuration loaded successfully. Requires long-lived access token from HA UI before metrics work.

---

## Current State Summary

**Operational:**
- Home Assistant accessible at https://ha.patriark.org (requires Authelia MFA)
- Container healthy, using 387MB RAM
- Traefik routing functional (TLS via Let's Encrypt)
- All networks attached correctly (reverse_proxy first for internet access)
- Prometheus configured but not scraping (needs bearer token)

**Not Yet Configured:**
- Home Assistant initial onboarding (web UI setup)
- Prometheus bearer token (requires HA long-lived access token)
- Matter Server (Week 2)
- Unpoller presence sensor (Week 2)

---

## Next Steps: Week 2 (Plan lines 539-583)

### Prerequisites Before Starting Week 2

1. **Complete Home Assistant onboarding:**
   - Access https://ha.patriark.org
   - Create admin account
   - Complete initial setup wizard

2. **Configure Prometheus authentication (Podman secrets approach):**

   **Generate HA token:**
   - HA UI → Profile → Long-Lived Access Tokens
   - Create token named "Prometheus Scraping"
   - Copy token to clipboard

   **Store as Podman secret (recommended for security):**
   ```bash
   # Create secret from token
   echo "eyJ0eXAiOiJKV1QiLCJhbGc..." | podman secret create ha-prometheus-token -

   # Verify secret created
   podman secret ls | grep ha-prometheus
   ```

   **Update Prometheus configuration:**
   ```yaml
   # config/prometheus/prometheus.yml (line ~115)
   # Replace:
   bearer_token: 'PLACEHOLDER_TOKEN'
   # With:
   bearer_token_file: /run/secrets/ha-prometheus-token
   ```

   **Mount secret in Prometheus container:**
   ```bash
   # Add to quadlets/prometheus.container [Container] section:
   Secret=ha-prometheus-token,type=mount,target=/run/secrets/ha-prometheus-token

   # Reload and restart
   systemctl --user daemon-reload
   systemctl --user restart prometheus.service
   ```

   **Verify scraping works:**
   ```bash
   # Check Prometheus targets page
   curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="home-assistant")'
   ```

   **Why Podman secrets?**
   - Token never written to disk in plaintext config files
   - Follows homelab security patterns (e.g., CrowdSec, Authelia)
   - Secrets excluded from Git automatically
   - Easy rotation without config file changes

### Week 2 Implementation Tasks

1. **Deploy Matter Server quadlet** (plan line 542-553)
   - Image: `ghcr.io/home-assistant-libs/python-matter-server:stable`
   - Network: systemd-home_automation only
   - Volume: `%h/containers/data/matter-server:/data:Z`
   - Health check: TCP socket to port 5580

2. **Configure HA Matter integration** (plan line 555-558)
   - Add Matter integration in HA UI
   - Server URL: `ws://matter-server:5580/ws`
   - Expected: Integration loads, no devices (correct for Week 2)

3. **Configure Unpoller → HA presence sensor** (plan line 560-576)
   - Use Prometheus platform in HA `configuration.yaml`
   - Query: `unifi_device_wifi_client_connected{client_name="iPhone"}`
   - Create binary_sensor.iphone_home (template sensor)
   - NOTE: WiFi presence detection (NOT VPN-based)

4. **Verification checklist** (plan line 578-583)
   - Matter Server healthy
   - HA Matter integration loaded
   - iPhone presence sensor updating
   - Create test automation (presence-based notification)

---

## Technical Notes

### Network Ordering Gotcha Applied Correctly

Home Assistant quadlet has networks in correct order:
```
Network=systemd-reverse_proxy    # FIRST - gets default route
Network=systemd-home_automation  # Local HA communication
Network=systemd-monitoring       # Prometheus scraping
```

This ensures HA can reach internet for integrations while isolated from untrusted networks.

### ADR-016 Compliance Verified

NO Traefik labels in quadlet (correct). All routing defined in `routers.yml` per separation of concerns principle.

### Memory Usage Within Targets

Current: 387MB, Target: 2GB max (plan estimates 2G for HA)
19% utilization indicates room for integrations and automations.

### Health Check Validation

Health check using `curl` is working correctly. The official Home Assistant image includes curl 8.14.1:

```bash
$ podman healthcheck run home-assistant
# Exit code: 0 (success)

$ podman inspect home-assistant --format '{{.State.Health.Status}}'
healthy

$ podman exec home-assistant curl --version
curl 8.14.1 (x86_64-alpine-linux-musl)
```

The health check command `curl -f http://localhost:8123/manifest.json` executes successfully every 30 seconds with 90s startup grace period.

---

## Files Modified

**Created:**
- `~/.config/containers/systemd/home_automation.network`
- `~/.config/containers/systemd/home-assistant.container`
- `~/containers/config/home-assistant/` (directory)
- `~/containers/data/home-assistant/` (directory)

**Modified:**
- `~/containers/config/traefik/dynamic/routers.yml` (+18 lines: router + service)
- `~/containers/config/prometheus/prometheus.yml` (+8 lines: scrape config)

**Services Restarted:**
- `systemctl --user restart traefik.service` (picked up routing changes)
- `systemctl --user restart prometheus.service` (loaded new scrape target)

---

## Plan Alignment

Week 1 completion aligns with plan section "Week 1: Network & Home Assistant" (lines 493-536).

**Completed from plan:**
- ✅ Task 1: Create systemd-home_automation network
- ✅ Task 2: Prepare directories
- ✅ Task 3: Deploy Home Assistant quadlet (NO Traefik labels)
- ✅ Task 4: Add Traefik dynamic config route
- ✅ Task 5: Add Prometheus scraping config
- ✅ Task 6: Verify service healthy, external access, metrics configured

**Outstanding prerequisite:** Initial HA setup via web UI (user-driven, not automated)

---

## For Next Session

**Immediate action:** Complete Home Assistant onboarding and generate Prometheus token before starting Week 2 deployment.

**Week 2 starting point:** Plan line 539 "Week 2: Matter Server & Unpoller Integration"

**Expected Week 2 duration:** ~2 hours (Matter Server deployment + Unpoller sensor configuration + testing)

**Resource impact after Week 2:** +512MB RAM (Matter Server), total HA stack ~900MB / 2.5GB planned
