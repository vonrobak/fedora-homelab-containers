# Matter-First Home Automation Platform: Implementation Plan

**Date:** 2025-12-30
**Status:** Awaiting Approval
**Trajectory:** B (Deep Integration) with expansion potential to C
**Timeline:** 3-6 months (1-2 hours/day)
**Budget:** ~5,300 NOK initial, ~8,000 NOK total with future expansion

---

## Executive Summary

This plan designs a **production-grade Matter-first home automation platform** deeply integrated with your existing homelab infrastructure. The architecture leverages:

- **Home Assistant** (container, not HAOS) as the central automation hub
- **OpenThread Border Router** (OTBR, FOSS) with nRF52840 USB dongle (~$12)
- **Python Matter Server** for Matter device control
- **Function Gemma** (Ollama, hybrid approach) for intelligent context-aware automations
- **Unpoller** for UDM Pro network observability and presence detection
- **Wyoming protocol** for privacy-preserving guest voice control

**Key Design Principles:**
1. Matter-first for all new devices (accept 10-20% premium for future-proofing)
2. Deep integration with existing monitoring (Prometheus/Grafana/Loki)
3. Guest voice control with extreme security isolation (lighting only)
4. Privacy-preserving local processing (no cloud dependencies)
5. Observable system (metrics, logs, alerts, SLOs)
6. Gradual deployment following existing ADR patterns

---

## Architecture Overview

### Network Topology

```
Internet
  ↓
UDM Pro (192.168.1.1)
  ├─ Main Network (192.168.1.0/24)
  │   └─ Homelab (192.168.1.70) - Fedora Workstation
  │       ├─ Existing Podman Networks:
  │       │   ├─ systemd-reverse_proxy (10.89.2.0/24) - Gateway, internet-facing services
  │       │   ├─ systemd-auth_services (10.89.3.0/24) - Authelia, Redis
  │       │   ├─ systemd-media_services (10.89.1.0/24) - Jellyfin
  │       │   ├─ systemd-monitoring (10.89.4.0/24) - Prometheus, Grafana, Loki
  │       │   ├─ systemd-photos (10.89.5.0/24) - Immich stack
  │       │   └─ systemd-nextcloud (10.89.10.0/24) - Nextcloud stack
  │       │
  │       └─ NEW Networks for Home Automation:
  │           ├─ systemd-home_automation (10.89.6.0/24) - HA, Matter, OTBR, Ollama
  │           └─ systemd-voice_assistant (10.89.7.0/24) - Wyoming services, voice gateway
  │
  ├─ IoT VLAN (192.168.2.0/24)
  │   ├─ Matter/Thread devices (via OTBR bridge)
  │   ├─ Hue Bridge (192.168.2.10 - Matter enabled)
  │   ├─ Mill WiFi heaters
  │   └─ Roborock vacuum
  │
  └─ Guest WiFi (192.168.99.0/24)
      └─ Voice control ONLY (port 10300 to homelab)
```

### Service Architecture (10 New Containers)

| Service | Networks | Memory | Purpose |
|---------|----------|--------|---------|
| **home-assistant** | reverse_proxy, home_automation, monitoring | 2G | Core automation controller |
| **matter-server** | home_automation | 512M | Python Matter Controller |
| **otbr** | reverse_proxy, home_automation, monitoring | 256M | OpenThread Border Router |
| **unpoller** | monitoring | 128M | UDM Pro metrics exporter |
| **ollama** | home_automation | 4G | Function Gemma LLM (2B model) |
| **automation-bridge** | reverse_proxy, home_automation, monitoring | 512M | Cross-system orchestration |
| **wyoming-whisper** | voice_assistant | 1G | STT (speech-to-text) |
| **wyoming-piper** | voice_assistant | 512M | TTS (text-to-speech) |
| **wyoming-openwakeword** | voice_assistant | 256M | Wake word detection |
| **voice-gateway** | reverse_proxy, voice_assistant, home_automation | 512M | Guest voice proxy (security) |

**Total Resource Impact:** +9.5GB memory (current usage: 2-3GB → new total: 11.5-12.5GB)

---

## Guest Voice Control Security Model

**Critical Requirement:** Guests on WiFi 192.168.99.0/24 can control lighting only, strictly isolated.

### UDM Pro Firewall Rules

```
Rule 1: Guest → Voice Gateway (ACCEPT)
  - Source: 192.168.99.0/24
  - Destination: 192.168.1.70:10300
  - Logging: ENABLED

Rule 2: Guest → Main Network (DROP)
  - Source: 192.168.99.0/24
  - Destination: 192.168.1.0/24 (except :10300)
  - Logging: ENABLED (security audit)

Rule 3: Guest → IoT VLAN (DROP)
  - Source: 192.168.99.0/24
  - Destination: 192.168.2.0/24
  - Logging: ENABLED
```

### Voice Gateway Security Layers

1. **Rate Limiting:** 10 req/min per IP (application + Traefik)
2. **Action Whitelist:** ONLY `light.turn_on`, `light.turn_off`, `light.toggle`, `scene.turn_on`, status queries
3. **Audit Logging:** ALL commands → Loki (90-day retention)
4. **CrowdSec Integration:** Auto-ban on 3 failed attempts or abuse pattern
5. **Session Timeout:** 5 minutes

---

## Deployment Strategy: 5 Phases (24 Weeks)

### Phase 1: Infrastructure Foundation (Weeks 1-3)

**Objective:** Deploy core home automation infrastructure

**Week 1: Networks & Directories**
```bash
# Create new networks (using available subnet ranges)
podman network create systemd-home_automation --subnet 10.89.6.0/24 --dns 192.168.1.69
podman network create systemd-voice_assistant --subnet 10.89.7.0/24 --dns 192.168.1.69

# Verify
podman network ls --format "{{.Name}}: {{range .Subnets}}{{.Subnet}} {{end}}"

# Prepare directories
mkdir -p ~/containers/config/home-assistant
mkdir -p ~/containers/data/home-assistant
mkdir -p ~/containers/config/matter-server
mkdir -p ~/containers/data/matter-server
mkdir -p ~/containers/config/unpoller
mkdir -p ~/containers/data/otbr
```

**Week 2: Core Services**
- Deploy Home Assistant container (networks: reverse_proxy, home_automation, monitoring)
- Deploy Python Matter Server (network: home_automation)
- Deploy Unpoller (network: monitoring)
- Configure Traefik routing + Authelia protection
- Integrate Prometheus scrape configs

**Week 3: OpenThread Border Router**
- Flash nRF52840 USB dongle with RCP firmware ([Guide](https://openthread.io/guides/border-router/prepare))
- Deploy OTBR container (networks: reverse_proxy, home_automation, monitoring)
- Verify Thread network formation (web UI: http://otbr:8080)

**Success Criteria:**
- All services healthy (green in Grafana)
- Thread network formed (visible in OTBR)
- Unpoller scraping UDM Pro metrics
- HA accessible at https://ha.patriark.org

**Network Assignment Pattern (following existing pattern):**
- Services needing internet: `reverse_proxy` as FIRST network (gets default route)
- Services needing monitoring: Add `monitoring` network
- Services in home automation ecosystem: Add `home_automation` network
- Voice services: Use `voice_assistant` network (isolated)

---

### Phase 2: Network Observability (Weeks 4-5)

**Objective:** Deep monitoring integration

**Week 4: Unpoller & Metrics**
- Import Grafana dashboards (UniFi Client Insights, Network Sites)
- Create presence detection panels (WireGuard VPN clients)
- Enable HA Prometheus integration
- Create SLO recording rules

**Week 5: Loki Log Aggregation**
- Configure Promtail for HA logs
- Create LogQL queries for debugging
- Document in `docs/40-monitoring-and-documentation/guides/loki-home-automation-queries.md`

**Success Criteria:**
- SLO metrics recording (>99% availability)
- Network presence detection working (VPN client count)
- Loki ingesting HA logs
- Alerts configured (none firing in healthy state)

---

### Phase 3: Function Gemma & Automation Bridge (Weeks 6-8)

**Objective:** Intelligent context-aware automations

**Week 6: Ollama + Function Gemma**
```bash
# BTRFS NOCOW setup
sudo mkdir -p /mnt/btrfs-pool/subvol7-containers/ollama
sudo chattr +C /mnt/btrfs-pool/subvol7-containers/ollama

# Deploy and pull model
systemctl --user enable --now ollama.service
podman exec ollama ollama pull functiongemma:2b
```

**Week 7: Automation Bridge**
- Implement FastAPI application (`automation-bridge/main.py`)
- Create function definitions for cross-system actions:
  - `/actions/homelab/update-containers` (smart update scheduling)
  - `/actions/homelab/snapshot` (BTRFS snapshot before risky ops)
  - `/query/presence` (WireGuard VPN status)
- Add Prometheus metrics endpoint
- Deploy container

**Week 8: HA Integration**
- Configure Ollama integration in HA
- Create test automations using Function Gemma context
- Example: Context-aware climate (occupancy + outdoor temp + energy price)
- Document patterns in `docs/10-services/guides/function-gemma-patterns.md`

**Success Criteria:**
- Ollama responding to function calls (<1s latency)
- Automation bridge executing homelab actions
- HA automations using Prometheus metrics as context
- Resource usage within limits (4GB for 2B model)

---

### Phase 4: Guest Voice Control (Weeks 9-11)

**Objective:** Privacy-preserving guest voice assistant

**Week 9: Wyoming Services**
- Deploy wyoming-whisper (STT)
- Deploy wyoming-piper (TTS)
- Deploy wyoming-openwakeword (wake word: "hey jarvis")
- Test pipeline locally, benchmark latency (target: <2s)

**Week 10: Voice Gateway**
- Implement FastAPI gateway (`voice-gateway/gateway.py`)
- Add rate limiting, whitelist enforcement, audit logging
- Deploy container (exposed on port 10300)

**Week 11: Security Hardening**
- Configure UDM Pro firewall rules (guest → voice gateway only)
- Add Traefik security middleware
- Create CrowdSec scenario for abuse detection
- Test from guest device (phone on 192.168.99.x)

**Success Criteria:**
- Voice pipeline <2s end-to-end latency
- Whitelist enforced (lighting ✓, climate ✗)
- Firewall blocking guest access to main network
- Rate limiting working (11th req/min → 429)
- Audit logs in Loki

---

### Phase 5: Matter Device Rollout (Weeks 12-24, gradual)

**Objective:** Deploy Matter devices and advanced automations

**Week 12: Hue Bridge Matter**
- Update Hue Bridge firmware (1974142030+)
- Commission to HA via Matter
- Test 2-3 bulbs, benchmark performance

**Weeks 13-14: Mill Heaters**
- Integrate WiFi heaters (HA Mill integration or API reverse-engineering)
- Deploy smart plugs for Gen 1 panel heaters (4x Eve Energy)

**Weeks 15-18: Smart Plugs**
- Commission Eve Energy plugs to Thread network
- Verify Thread mesh expansion (plugs as router nodes)
- Configure power monitoring, create energy dashboards

**Weeks 19-22: Sensors**
- Deploy Matter sensors:
  - 3x Temperature/Humidity (Aqara, ~250 NOK each)
  - 4x Door/Window (Aqara, ~200 NOK each)
  - 2x Motion (Eve, ~550 NOK each)
  - 1x Presence mmWave (Aqara FP2, ~800 NOK)
- Create occupancy-based automations

**Weeks 23-24: Advanced Automations**
- **Presence Detection:** WireGuard VPN connect → "Home" scene (lights, heating)
- **Energy Optimization:** Nordpool spot pricing integration (if enabled)
- **Context-Aware Climate:** Function Gemma optimizes heating based on:
  - Prometheus metrics (room temp, occupancy, outdoor temp)
  - Energy price (if Nordpool)
  - Time of day, presence detection
- **Morning Routine:** Motion sensor → gradual lighting → voice greeting

**Success Criteria:**
- All Hue lights accessible via Matter
- Mill heaters controlled via HA
- 4+ smart plugs deployed, Thread mesh stable
- 10+ sensors integrated
- Presence detection working (VPN → Home scene)
- Energy dashboards live
- Function Gemma automations running

---

## Matter Device Budget

### Phase 5 Costs (Weeks 12-24)

| Phase | Devices | Qty | Unit (NOK) | Total |
|-------|---------|-----|------------|-------|
| **5B: Smart Plugs** | Eve Energy (EU) | 4 | 450 | 1,800 |
| **5C: Sensors** | | | | |
| | Temp/Humidity (Aqara) | 3 | 250 | 750 |
| | Door/Window (Aqara) | 4 | 200 | 800 |
| | Motion (Eve) | 2 | 550 | 1,100 |
| | Presence mmWave (Aqara FP2) | 1 | 800 | 800 |
| **Total Phase 5** | | | | **5,250** |

### Future Expansion (Post-Week 24)

| Item | Qty | Unit (NOK) | Total |
|------|-----|------------|-------|
| Additional smart plugs | 2 | 450 | 900 |
| Outdoor plug (Eve) | 1 | 600 | 600 |
| Smart buttons (Aqara) | 3 | 180 | 540 |
| Additional sensors | 3 | 250 | 750 |
| **Total Future** | | | **2,790** |

**Grand Total:** 8,040 NOK (~$760 USD)

**Recommendation:** Start with Phase 5 only (5,250 NOK), evaluate ROI after Week 22, expand if positive.

---

## Integration Patterns

### 1. WireGuard VPN → Presence Detection

```
iPhone connects to WireGuard
  ↓ Unpoller metrics
unifi_device_wlan_num_sta{ssid="WireGuard"} > 0
  ↓ HA automation trigger
Automation: "VPN Connected - Home Scene"
  ↓ Function Gemma context check
- Is it evening? (sun below horizon)
- Temperature < 20°C?
  ↓ Execute scene
- Turn on entryway lights (100%)
- Set living room scene ("Welcome")
- Adjust heating (+2°C if needed)
- Discord notification: "Welcome home!"
```

### 2. Context-Aware Climate Optimization

```
Prometheus metrics (every 15 min):
  - room_temperature
  - occupancy (mmWave sensor)
  - outdoor_temp
  - energy_price (Nordpool, if enabled)
  ↓ Function Gemma query
"What's optimal temperature for living room?"
  ↓ Gemma response
{
  "target_temperature": 20.5,
  "reason": "Occupancy detected, outdoor 5°C, energy price low",
  "confidence": 0.92
}
  ↓ Execute via Automation Bridge
climate.set_temperature → Mill heaters
Log to Loki (audit trail)
```

### 3. Guest Voice Control Flow

```
Guest (192.168.99.x): "Turn on living room lights"
  ↓ Wyoming satellite → Voice Gateway
Voice Gateway validates:
  - Rate limit: OK (<10 req/min)
  - Whitelist: OK (lighting allowed)
  - Audit: "192.168.99.45 → light.turn_on"
  ↓ Forward to HA API
HA executes: light.turn_on
  ↓ Optional cross-system action
If Jellyfin streaming → dim to 30%
If not streaming → 100% brightness
```

---

## Critical Files to Create/Modify

### 1. Container Quadlets (10 files)
- `/home/patriark/.config/containers/systemd/home-assistant.container`
- `/home/patriark/.config/containers/systemd/otbr.container` ⚠️ Critical (Thread network)
- `/home/patriark/.config/containers/systemd/matter-server.container`
- `/home/patriark/.config/containers/systemd/unpoller.container`
- `/home/patriark/.config/containers/systemd/ollama.container`
- `/home/patriark/.config/containers/systemd/automation-bridge.container`
- `/home/patriark/.config/containers/systemd/wyoming-whisper.container`
- `/home/patriark/.config/containers/systemd/wyoming-piper.container`
- `/home/patriark/.config/containers/systemd/wyoming-openwakeword.container`
- `/home/patriark/.config/containers/systemd/voice-gateway.container`

### 2. Application Code (3 services)
- `/home/patriark/containers/config/automation-bridge/main.py` (FastAPI)
- `/home/patriark/containers/config/voice-gateway/gateway.py` (FastAPI)
- `/home/patriark/containers/config/home-assistant/configuration.yaml`

### 3. Monitoring & Observability
- `/home/patriark/containers/config/prometheus/prometheus.yml` (add 10 scrape configs)
- `/home/patriark/containers/config/prometheus/rules/home-automation-slos.yml` (NEW)
- `/home/patriark/containers/config/prometheus/alerts/home-automation-alerts.yml` (NEW)
- `/home/patriark/containers/config/promtail/promtail.yml` (HA log scraping)

### 4. Traefik Configuration
- `/home/patriark/containers/config/traefik/dynamic/routers.yml` (add HA, OTBR, voice gateway)
- `/home/patriark/containers/config/traefik/dynamic/middleware.yml` (voice-gateway-rate-limit)

### 5. Documentation
- `/home/patriark/containers/docs/00-foundation/decisions/2025-12-30-ADR-016-matter-first-device-strategy.md`
- `/home/patriark/containers/docs/00-foundation/decisions/2025-12-30-ADR-017-guest-voice-control-security.md`
- `/home/patriark/containers/docs/00-foundation/decisions/2025-12-30-ADR-018-function-gemma-hybrid-architecture.md`
- `/home/patriark/containers/docs/00-foundation/decisions/2025-12-30-ADR-019-openthread-border-router.md`
- `/home/patriark/containers/docs/10-services/guides/function-gemma-patterns.md`
- `/home/patriark/containers/docs/10-services/guides/guest-voice-control.md`
- `/home/patriark/containers/docs/40-monitoring-and-documentation/guides/loki-home-automation-queries.md`

### 6. Secrets (create before deployment)
```bash
podman secret create ha_token <(echo "LONG_LIVED_HA_TOKEN")
podman secret create automation_bridge_token <(echo "SECURE_TOKEN")
podman secret create unifi_user <(echo "unifi-readonly")
podman secret create unifi_pass <(echo "SECURE_PASSWORD")
```

---

## Monitoring: SLO Targets

| Service | SLO Target | Error Budget (30d) | Rationale |
|---------|------------|-------------------|-----------|
| **Home Assistant** | 99.5% availability | 216 min/month | Core automation hub, high criticality |
| **Matter Server** | 99.9% availability | 43 min/month | All Matter devices depend on it |
| **OTBR** | 99.9% availability | 43 min/month | Critical: Thread mesh gateway |
| **Voice Gateway** | 95% success rate | 5% failures OK | Guests expect some failures |
| **Automation Bridge** | 95% of actions <2s | Latency target | Context-aware decisions need speed |

**Monthly SLO Report:** Automated at 08:00 on 1st of month (existing script updated)

---

## Hardware Requirements

### nRF52840 USB Dongle (~$12)
- **Product:** Nordic Semiconductor nRF52840 Dongle
- **Purpose:** Thread Radio Co-Processor for OTBR
- **Flashing:** Nordic nRF Connect Programmer ([Guide](https://openthread.io/guides/border-router/prepare))
- **Sources:** Mouser, DigiKey, Amazon

### System Requirements (Homelab)
- **Current Usage:** 2-3GB RAM
- **After Deployment:** 11.5-12.5GB RAM
- **Recommendation:** 16GB RAM minimum for comfortable headroom
- **CPU:** 4+ cores (sufficient for Function Gemma 2B)
- **Storage:** +10GB for containers/models

---

## Migration Path

### Hue Bridge
- **Week 12:** Update firmware (1974142030+), enable Matter
- **Decision:** Keep as Matter bridge (no bulb replacement needed)
- **Future (2026):** Re-evaluate if Matter bulbs reach price parity

### Mill Heaters
- **WiFi Models:** Integrate via HA (cloud API or local reverse-engineering)
- **Gen 1 Panel Heaters:** Control via Eve Energy smart plugs

### Bluetooth Smart Plugs
- **Weeks 17-22:** Gradual replacement with Eve Energy (Matter/Thread)
- **Priority:** High-traffic areas first (living room, bedroom)
- **Decommission:** Week 24 (all Bluetooth retired)

### Zigbee Sunset (2026+)
- **Current:** Hue Bridge in Matter mode (valid long-term solution)
- **Future:** Migrate to Matter-native bulbs ONLY when:
  - Price parity (<400 NOK/bulb)
  - Feature parity (entertainment mode, gradient)
  - Proven reliability (6+ months production use)
- **No urgency:** Hue Bridge Matter mode works excellently

---

## Success Metrics

### Phase 1-3 (Weeks 1-8)
- All services healthy (Grafana green)
- Thread network formed (2+ devices)
- Function Gemma responding (<1s)
- Automation bridge working

### Phase 4 (Weeks 9-11)
- Guest voice control operational
- Whitelist enforced (0 unauthorized actions)
- Latency <2s end-to-end
- Audit logs in Loki

### Phase 5 (Weeks 12-24)
- 25-50 Matter devices deployed
- Thread mesh stable (5+ router nodes)
- Presence detection working
- Energy optimization active
- No alerts firing (SLO >99%)

---

## Risk Mitigation

| Risk | Mitigation |
|------|-----------|
| **Matter ecosystem immaturity** | Gradual rollout, keep existing devices as fallback |
| **Thread mesh instability** | Monitor OTBR metrics, add router nodes (Eve Energy) |
| **Function Gemma resource usage** | Start with 2B model, monitor RAM, upgrade to 7B only if needed |
| **Guest voice abuse** | Extreme security (rate limit, whitelist, CrowdSec, audit logs) |
| **Integration complexity** | Phased deployment (1-2 hours/day sustainable), comprehensive monitoring |

---

## Next Steps After Approval

**Week 1 Day 1: Networks & Directories**
```bash
# Create new Podman networks
podman network create systemd-home_automation --subnet 10.89.6.0/24 --dns 192.168.1.69
podman network create systemd-voice_assistant --subnet 10.89.7.0/24 --dns 192.168.1.69

# Prepare directories
mkdir -p ~/containers/config/{home-assistant,matter-server,unpoller,automation-bridge,voice-gateway}
mkdir -p ~/containers/data/{home-assistant,matter-server,otbr,ollama}
```

**Week 1 Day 2-3: Deploy Home Assistant + Matter Server**
- Create quadlet files following existing patterns
- Deploy Home Assistant (reverse_proxy first, then home_automation, monitoring)
- Deploy Matter Server (home_automation only)
- Systemd daemon-reload and enable services

**Week 1 Day 4-5: Flash nRF52840 & Deploy OTBR**
- Flash USB dongle with Nordic nRF Connect Programmer
- Deploy OTBR container (reverse_proxy first for internet, then home_automation, monitoring)
- Verify Thread network formation

**Week 2 Day 1: Unpoller & Prometheus Integration**
- Deploy Unpoller (monitoring network)
- Create UniFi read-only user
- Configure Prometheus scrape targets

**Week 2 Day 2-3: Traefik Routing**
- Add HA, OTBR routers to `config/traefik/dynamic/routers.yml`
- Configure Authelia middleware
- Test external access

**Week 2 Day 4-5: Monitoring Validation**
- Create Grafana dashboards
- Verify all services scraped by Prometheus
- Create initial SLO recording rules

**Continue phased rollout...**

---

## Sources & References

- [Home Assistant - ArchWiki](https://wiki.archlinux.org/title/Home_Assistant)
- [Moving to Podman Quadlets](https://jfx.ac/blog/moving-to-podman-quadlets/)
- [All Open-Source THREAD Network](https://www.apalrd.net/posts/2025/ha_thread/)
- [OpenThread Border Router Setup](https://openthread.io/guides/border-router/prepare)
- [Matter 1.5 Camera Support](https://www.matteralpha.com/industry-news/matter-1-5-introduces-camera-support-finally)
- [Philips Hue Matter Support](https://www.philips-hue.com/en-us/support/article/philips-hue-and-matter-complete-setup-and-support-guide/000012)
- [Eve Energy Matter Specs](https://matterdevices.net/devices/eve-energy-smart-plug-eu)
- [Aqara Matter Devices](https://www.aqara.com/eu/explore/everything-matter/)
- [Unpoller GitHub](https://github.com/unpoller/unpoller)
- [Wyoming Protocol - Home Assistant](https://www.home-assistant.io/integrations/wyoming/)

---

**End of Implementation Plan**
