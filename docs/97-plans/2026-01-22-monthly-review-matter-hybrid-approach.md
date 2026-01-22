# Homelab January 2026: Monthly Review & Matter Hybrid Approach

**Date:** 2026-01-22
**Health Score:** 100/100 ✅
**Services:** 26 running
**Status:** Analysis Complete, Hybrid Infrastructure-First Approach Approved

---

## Executive Summary

January 2026 was a month of **intensive operational excellence work** rather than feature expansion. The homelab achieved 100/100 health score through systematic gap closure, but critical issues emerged that consumed significant effort. The ambitious Matter v2.0 plan (1,760 lines) remains unimplemented since December 30, 2025.

**This document provides:**
1. **Comprehensive Monthly Review** - What was done, postponed, and forgotten
2. **Matter Hybrid Approach** - Infrastructure-first, evaluation-driven deployment
3. **Q1 2026 Path Forward** - Realistic roadmap for next 2 months

**Approved Strategy:** Deploy Home Assistant as Matter-ready integration hub, evaluate for 1 month before device procurement.

---

# PART 1: JANUARY 2026 MONTHLY REVIEW

## What Was Accomplished (Victories)

### ✅ Operational Excellence (Course 2) - COMPLETE

**Timeline:** January 9, 2026
**Impact:** System transformed from 95/100 to 100/100 health

**Achievements:**
- **Memory standardization**: All 22 containers upgraded to MemoryMax+MemoryHigh pattern
- **Health checks fixed**: Loki/Promtail false positives eliminated
- **SLO calibration framework**: Daily snapshot collection + analysis scripts deployed
- **Disaster recovery validated**: DR-003, DR-004 procedures tested (6-minute RTO proven)

**Files created:**
- `docs/98-journals/2026-01-09-course-2-operational-excellence-completion.md`
- `docs/98-journals/2026-01-09-memory-limit-standardization.md`
- `docs/40-monitoring-and-documentation/guides/slo-calibration-process.md`
- `scripts/daily-slo-snapshot.sh` + `scripts/analyze-slo-trends.sh`

**Value:** Infrastructure hardened, patterns established, data-driven decision making enabled

---

### ✅ Alert System Overhaul (Jan 11-22)

**Timeline:** 12 days of intensive firefighting
**Commits:** 10+ commits across 6 phases

**Critical fixes:**

1. **Phase 1 (Jan 16):** NextcloudCronStale alert false positives
2. **Phase 2 (Jan 17):** Log storage migration to BTRFS
3. **Phase 3 (Jan 17):** Fragile log-based metrics eliminated
4. **Phase 4-5 (Jan 17):** Alert consolidation + meta-monitoring
5. **Phase 6 (Jan 21):** Alert flapping root cause fix
6. **CRITICAL (Jan 22):** Burn rate calculation bug fix

**The burn rate bug** was especially severe:
- **Duration:** Broken since December 19, 2025 (34 days)
- **Impact:** Entire SLO multi-window alerting system non-functional
- **Root cause:** Calculated from 30-day constant SLI instead of short-term failure rates
- **Consequence:** Tier 1/2 alerts would NEVER fire during fast incidents
- **Fix:** Complete rewrite of burn rate formulas (35 recording rules)

**Files affected:**
- `config/prometheus/rules/slo-recording-rules.yml`
- `config/prometheus/rules/slo-burn-rate-extended.yml`
- `config/prometheus/rules/log-based-alerts.yml`

**Journals:**
- `2026-01-16-alert-system-redesign.md`
- `2026-01-17-alert-consolidation-meta-monitoring-phase4-5.md`
- `2026-01-21-alert-flapping-root-cause-fix.md`
- `2026-01-22-burn-rate-calculation-fix.md`
- `2026-01-22-slo-operational-excellence-phase1-2-findings.md`

**Value:** Monitoring infrastructure now functional (was broken for a month)

---

### ✅ Security & Compliance

**Completed:**
- **Security audit** (Jan 9): 40+ checks, comprehensive baseline
- **Disaster recovery validation** (Jan 3): External backup restore verified
- **Vulnerability scanning**: Weekly automated scans operational
- **ADR compliance**: Validated against all 17 ADRs

**Projects from standalone index completed:**
- ✅ **Project A:** Disaster Recovery Testing
- ✅ **Project B:** Security Hardening
- ✅ **Project C:** Auto-Documentation

**Auto-generated documentation deployed:**
- `AUTO-SERVICE-CATALOG.md` (26 services)
- `AUTO-NETWORK-TOPOLOGY.md` (5 networks)
- `AUTO-DEPENDENCY-GRAPH.md` (4-tier structure)
- `AUTO-DOCUMENTATION-INDEX.md` (338 files)

**Value:** Security posture quantified, documentation automated

---

### ✅ Infrastructure Additions

**New services deployed:**
- **Unpoller** (Jan 8): UDM Pro metrics exporter, 544 metrics/poll
- **Gathio** (Jan 14): Event management platform

**UniFi network monitoring:**
- 12 recording rules
- 7 alert rules
- 10 SLO rules
- **WiFi presence detection ready** (iPhone home WiFi detection capability)

---

### ✅ Workflow Enhancements

**ADR-017 deployed** (Jan 5): Slash Commands & Subagents framework
- `/commit-push-pr` command (<30s vs 5-10 min manual)
- 3 specialized subagents: infrastructure-architect, service-validator, code-simplifier
- Verification feedback loops integrated

**Value:** Deployment velocity increased, pattern compliance automated

---

## What Was Postponed (Intentional Delays)

### ⏳ Matter v2.0 Plan - Awaiting Approval Since Dec 30

**Status:** Comprehensive 1,760-line plan, never approved
**Reason:** Operational issues consumed bandwidth (alert fixes, burn rate bug)
**Impact:** Home automation expansion blocked for 23 days

**Analysis:** Plan was **over-engineered for homelab use case**
- 10 services proposed (HA, Matter, OTBR, Ollama, Wyoming stack, bridges)
- +9.5GB RAM usage
- Focus on automation scenarios vs infrastructure quality
- Guest voice control complexity disproportionate to value

**Revised approach:** Hybrid infrastructure-first deployment (see Part 2)

---

### ⏳ Course 3: Observability & SLO Maturation - Not Started

**From Q1 2026 Strategic Plan:**
- SLO burn rate alerting (now CRITICAL after bug discovery)
- Loki log analysis expansion
- Trace collection exploration
- Custom business metrics

**Status:** Burn rate fix completed ad-hoc (Jan 22), but comprehensive Course 3 work deferred

---

### ⏳ SLO Calibration - Deferred to Feb 15

**Original plan:** Feb 1 calibration
**Revised:** Feb 15 (need 23+ days of clean data)
**Reason:** 12-day snapshot collection gap (Jan 10-21)

**Current SLI performance (30-day rolling, Jan 22):**
- Traefik: 100.00% (target: 99.95%) ✅
- Authelia: 99.78% (target: 99.90%) ⚠️
- Nextcloud: 99.94% (target: 99.50%) ✅
- Jellyfin: 98.45% (target: 99.50%) ⚠️
- Immich: 95.66% (target: 99.90%) 🚨 (recovering from Jan 11 corruption)

**Trend:** All improving as December incidents age out of 30-day window

---

## What Was Forgotten (Gaps Identified)

### 🚨 CRITICAL: Burn Rate Alerting Broken for 34 Days

**Oversight:** No one realized Tier 1/2 alerts were non-functional from Dec 19 - Jan 22

**Why this happened:**
- Burn rates returned plausible values (e.g., 43x for Immich)
- Values looked correct mathematically
- No alerts fired because services were healthy
- **BUT:** System would NOT have alerted during actual fast incidents

**Root cause:** Fundamental misunderstanding of `avg_over_time(constant_SLI[window])`
- Returns the constant, doesn't measure short-term failure rate
- Conceptual bug, not syntax error

**Lesson learned:** **Alert effectiveness validation should be in runbooks**
- Test that alerts fire during simulated degradation
- Monthly drill: Intentionally break a service, verify alerting works

**Mitigation:** Add to monthly operational checklist (Feb 1+)

---

### ⏳ Snapshot Collection Gap (Jan 10-21)

**Issue:** 12-day data gap, 130 null snapshots
**Root cause:** Prometheus 30-day queries needed more historical data
**Impact:** Calibration delayed from Feb 1 → Feb 15
**Status:** Fixed Jan 22, now collecting valid data

**Lesson:** When deploying daily collection, verify it works for 3+ days before trusting

---

### 📋 Monthly SLO Reports Not Generated

**Script exists:** `scripts/monthly-slo-report.sh`
**Status:** Not run since deployment (Dec 31)
**Missing reports:** January 2026 report
**Impact:** No monthly compliance tracking

**Resolution:** January report generated Jan 22 ✅

---

### 📋 Validation Pending (7-Day Health Score)

**From Course 2:** Validate 100/100 health sustained for 7 days (Jan 9-16)
**Status:** Reminder set for Jan 16, validation not documented
**Current:** Jan 22, system at 100/100 (13 days sustained)
**Action:** Retroactive validation → Course 2 fully complete ✅

---

## Areas for Improvement (Blind Spots)

### 🔍 Testing Gap: Alert Effectiveness

**Current:** Alerts defined, thresholds set
**Missing:** Regular validation that alerts fire correctly

**Proposed quarterly drill:**
1. Simulate service degradation (e.g., stop container for 5 minutes)
2. Verify Tier 1 alert fires within 2 minutes
3. Verify remediation webhook triggered
4. Measure MTTR (target: <5 min)
5. Document results, adjust thresholds if needed

**Schedule:** Every quarter (Q1 target: March 1)

---

### 🔍 Monitoring Gap: Snapshot Collection Health

**Current:** Daily snapshots via systemd timer
**Missing:** Alert if snapshot collection fails
**Risk:** Calibration breaks silently

**Proposed:** Add Prometheus metric `slo_snapshot_last_success_timestamp`
- Alert if > 2 days old
- 1-line addition to `daily-slo-snapshot.sh`

---

### 🔍 Documentation Gap: ADR Decision Tracking

**Current:** 17 ADRs documented
**Missing:** Index showing which ADRs are design-guiding vs implementation details

**Example blind spot:** Matter plan references "ADR-016 through ADR-019" but:
- ADR-016 = Configuration Design Principles (Dec 31)
- ADR-017 = Slash Commands & Subagents (Jan 5)
- ADR-018+: Don't exist yet (Matter plan needs renumbering)

**Proposed:** Add ADR index with categories (deferred to future)

---

### 🔍 Operational Gap: Change Control During Low Error Budget

**Current:** Deploy whenever ready
**Missing:** Freeze deployments when error budget <20%

**Example:** Immich at 95.66% (43 minutes over budget)
- Risky to deploy Immich ML updates right now
- Should wait until recovered to >99%

**Proposed:** Add to deployment checklist:
```bash
# Check error budget before deployment
./scripts/check-error-budget.sh immich
# If <20%, recommend deferring non-critical changes
```

---

## Errors of Judgment to Correct

### 1. Matter v2.0 Scope Creep

**Original intent:** Home automation infrastructure for homelab
**Actual plan:** Production-grade platform with 10 services, LLM, Wyoming voice stack

**Error:** Over-engineering for use case
- **Do need:** Matter-ready integration hub, homelab capability harvesting
- **Don't need:** Guest voice control, LLM-based automations (premature)

**Correction:** Hybrid infrastructure-first approach (see Part 2)

---

### 2. SLO Snapshot Collection Without Validation

**Error:** Deployed daily snapshot timer, assumed it worked
**Result:** 12-day gap due to Prometheus data age issues
**Correction:** Always verify automated systems for 3-7 days post-deployment

---

### 3. Alert Development Without End-to-End Testing

**Error:** Burn rate alerts deployed Dec 19, never tested with simulated degradation
**Result:** 34 days of broken alerting system
**Correction:** Quarterly alert drill (proposed above)

---

## Git Activity Summary (Dec 22 - Jan 22)

**Commits:** 79 total
**Major themes:**
1. Alert system fixes (10+ commits)
2. Course 2 operational excellence (3 commits)
3. Unpoller integration (4 commits)
4. Documentation enhancements (5+ commits)
5. Workflow automation (ADR-017, slash commands)

**Top commits (by impact):**
- `b61aead` - CRITICAL: Restore functional SLO burn rate alerting (#67)
- `d10af3f` - Course 2 operational excellence - memory standardization
- `041cbf8` - Complete Unpoller integration
- `81c39f7` - ADR-017 and workflow impact guide

---

# PART 2: MATTER HYBRID APPROACH - INFRASTRUCTURE FIRST

## Philosophy: Quality Infrastructure Over Premature Automation

**Core Principle:** Build Matter-ready integration platform that harvests homelab capabilities efficiently. Add devices only when infrastructure demonstrates value.

**Why Hybrid?**
- **Validates integration quality** before hardware investment
- **Proves monitoring/observability patterns** work for home automation
- **Establishes operational baseline** for future expansion
- **Minimizes sunk cost** if automation proves unnecessary
- **Focuses on infrastructure excellence** rather than automation scenarios

---

## Analysis of Matter v2.0 Plan

**Original plan strengths:**
- ✅ Comprehensive and well-researched
- ✅ Follows homelab patterns (ADR-016, quadlets, monitoring)
- ✅ Phased deployment (24 weeks)
- ✅ Unpoller prerequisite satisfied

**Over-engineered elements (deferred):**
1. **Ollama + Function Gemma LLM** - 4GB RAM for context-aware scenes
   - **Reality:** Homelab automations are simple, LLM overkill
   - **Decision:** Defer until proven need

2. **Wyoming Voice Stack** - 1.75GB RAM (Whisper, Piper, OpenWakeWord)
   - **Use case:** Guest voice control (novelty)
   - **Decision:** Defer to Phase 3+ (optional expansion)

3. **Automation Bridge** - 512MB RAM for HA ↔ Homelab integrations
   - **Use case:** HA triggers BTRFS snapshots, container updates
   - **Decision:** Manual scripts sufficient initially

4. **Voice Gateway** - 512MB RAM for guest WiFi security proxy
   - **Dependencies:** Wyoming stack + UDM Pro firewall
   - **Decision:** Skip guest voice entirely (now)

**Resource comparison:**
- **v2.0 (full):** +9.5GB RAM, 10 services
- **Hybrid (initial):** +2.0GB RAM, 2 services (HA + Matter Server)
- **Savings:** 7.5GB RAM, 8 fewer services (79% reduction)

---

## Hybrid Architecture: Matter-Ready Integration Hub

### Phase 1: Core Integration Infrastructure (February 2026)

**Services to deploy:**

| Service | Memory | Networks | Purpose |
|---------|--------|----------|---------|
| **home-assistant** | 2G | reverse_proxy, home_automation, monitoring | Integration hub, automation engine |
| **matter-server** | 512M | home_automation | Python Matter controller (ready for devices) |

**Existing services (already deployed):**
| **unpoller** | 128M | monitoring | UDM Pro metrics, WiFi presence detection |

**Total new RAM:** +2.5GB (vs +9.5GB in v2.0)

---

### Network Design

**New network (only 1):**
- `systemd-home_automation.network` (10.89.6.0/24)
  - Purpose: HA, Matter Server, future IoT integrations
  - Isolation: Separate from reverse_proxy (fail-fast security)
  - Monitoring: Connected to systemd-monitoring for Prometheus scraping

**Network topology:**
```
home-assistant:
  - systemd-reverse_proxy (Traefik routing, internet access)
  - systemd-home_automation (Matter Server communication)
  - systemd-monitoring (Prometheus metrics export)

matter-server:
  - systemd-home_automation (HA integration)
```

**Key principle:** First network gets default route (reverse_proxy for HA internet access)

---

### Integration Points: Harvesting Homelab Capabilities

**What makes this infrastructure-first approach valuable:**

1. **Prometheus Integration** (metrics export)
   - HA exports `/api/prometheus` endpoint
   - Metrics: Automation execution count, entity states, system health
   - Dashboard: Grafana "Home Automation" overview
   - Alerts: HA container health, automation failures

2. **Unpoller Integration** (presence detection)
   - **Corrected architecture:** iPhone home WiFi connection detection
   - Unpoller already collecting UDM Pro WiFi client data (544 metrics)
   - HA sensor: `binary_sensor.iphone_home` (based on WiFi MAC presence)
   - **Not VPN-based** (VPN indicates away, WiFi indicates home)
   - Use case: Presence-based automation triggers

3. **Loki Integration** (log correlation)
   - HA logs ingested via Promtail
   - LogQL queries: Correlate automation executions with service state changes
   - Example: "Did Jellyfin restart trigger automation failure?"

4. **Authelia Integration** (SSO)
   - HA dashboard: `https://ha.patriark.org` (behind Authelia)
   - YubiKey MFA required for external access
   - Local network: Direct access (bypass auth)

5. **Traefik Integration** (routing, security)
   - Dynamic config: `config/traefik/dynamic/routers.yml` (ADR-016 compliant)
   - Middleware chain: CrowdSec → Rate Limit → Authelia → Security Headers
   - TLS: Let's Encrypt automatic certificate

6. **Matter-Ready Platform** (device integration)
   - Matter Server operational (no devices yet)
   - Infrastructure validated before hardware procurement
   - OpenThread Border Router deferred (only needed for Thread devices)

---

### What This Infrastructure Enables (Future)

**When devices are added:**
- Matter device commissioning works immediately (server ready)
- Automations observable via Prometheus metrics
- Presence detection already functional (Unpoller + WiFi)
- Logs correlated in Loki (troubleshooting automation failures)
- External access secure (Authelia + Traefik + CrowdSec)

**When expansion is desired:**
- OpenThread Border Router: +nRF52840 dongle, +256MB RAM
- Wyoming voice (local, not guest): +1.75GB RAM, voice assistant
- Automation Bridge: +512MB RAM, HA ↔ Homelab cross-system triggers
- Ollama LLM: +4GB RAM, context-aware intelligent scenes

**Key benefit:** Infrastructure quality proven before resource commitment

---

## Deployment Plan: Infrastructure-First (3 Weeks)

### Week 1: Network & Home Assistant

**Tasks:**
1. Create `systemd-home_automation.network` (Podman network)
2. Prepare directories:
   ```bash
   mkdir -p ~/containers/config/home-assistant
   mkdir -p ~/containers/data/home-assistant
   ```
3. Deploy Home Assistant quadlet (NO Traefik labels, ADR-016 compliant)
4. Add Traefik dynamic config route:
   ```yaml
   # config/traefik/dynamic/routers.yml
   home-assistant-secure:
     rule: "Host(`ha.patriark.org`)"
     service: "home-assistant"
     middlewares:
       - crowdsec-bouncer@file
       - rate-limit-public@file
       - authelia@file
       - security-headers@file
     tls:
       certResolver: letsencrypt

   # services section
   home-assistant:
     loadBalancer:
       servers:
         - url: "http://home-assistant:8123"
   ```
5. Add Prometheus scraping:
   ```yaml
   # config/prometheus/prometheus.yml
   - job_name: 'home-assistant'
     static_configs:
       - targets: ['home-assistant:8123']
     metrics_path: '/api/prometheus'
   ```
6. Verify:
   - Service healthy: `systemctl --user status home-assistant.service`
   - External access: `https://ha.patriark.org` (Authelia MFA required)
   - Metrics: Prometheus targets page shows HA UP

---

### Week 2: Matter Server & Unpoller Integration

**Tasks:**
1. Deploy Matter Server quadlet:
   ```ini
   # ~/.config/containers/systemd/matter-server.container
   [Container]
   Image=ghcr.io/home-assistant-libs/python-matter-server:stable
   ContainerName=matter-server
   Network=systemd-home_automation.network
   Volume=%h/containers/data/matter-server:/data:Z
   Environment=MATTER_SERVER_STORAGE=/data
   HealthCmd=["CMD", "python3", "-c", "import socket; s=socket.socket(); s.connect(('localhost',5580)); s.close()"]
   ```

2. Configure HA Matter integration:
   - Add Matter integration in HA UI
   - Server URL: `ws://matter-server:5580/ws`
   - Verify integration loaded (no devices yet, expected)

3. Configure Unpoller → HA presence sensor:
   ```yaml
   # ~/containers/config/home-assistant/configuration.yaml
   sensor:
     - platform: prometheus
       resource: http://prometheus:9090
       queries:
         - name: "iPhone Home WiFi"
           query: 'unifi_device_wifi_client_connected{client_name="iPhone",ap_name="Living Room"}'
           value_template: '{{ value | int }}'

   binary_sensor:
     - platform: template
       sensors:
         iphone_home:
           friendly_name: "iPhone Home"
           value_template: "{{ states('sensor.iphone_home_wifi') | int > 0 }}"
           device_class: presence
   ```

4. Verify:
   - Matter Server healthy
   - HA Matter integration loaded
   - `binary_sensor.iphone_home` shows correct state (home/away based on WiFi)

---

### Week 3: Monitoring Integration & Validation

**Tasks:**
1. Create Grafana "Home Automation" dashboard:
   - Panel: HA container resource usage (CPU, memory, disk)
   - Panel: Automation execution count (from Prometheus HA metrics)
   - Panel: iPhone presence timeline (Unpoller WiFi data)
   - Panel: Matter Server health

2. Add Prometheus alert for HA health:
   ```yaml
   # config/prometheus/alerts/rules.yml
   - alert: HomeAssistantDown
     expr: up{job="home-assistant"} == 0
     for: 2m
     labels:
       severity: critical
     annotations:
       summary: "Home Assistant is down"
   ```

3. Configure Loki log ingestion:
   - Promtail already running (existing setup)
   - HA logs: `journalctl --user -u home-assistant.service`
   - Automatic ingestion via systemd journal scraping

4. Create test automation (validation):
   ```yaml
   # HA automation (via UI or YAML)
   automation:
     - alias: "Test: iPhone Arrives Home"
       trigger:
         platform: state
         entity_id: binary_sensor.iphone_home
         from: 'off'
         to: 'on'
       action:
         service: persistent_notification.create
         data:
           title: "Welcome Home"
           message: "iPhone detected on home WiFi"
   ```

5. Validation checklist:
   - ✅ HA accessible via https://ha.patriark.org (Authelia MFA)
   - ✅ Matter Server integration loaded (ready for devices)
   - ✅ iPhone presence sensor updating correctly
   - ✅ Test automation fires when iPhone connects to WiFi
   - ✅ Prometheus scraping HA metrics
   - ✅ Grafana dashboard shows HA health
   - ✅ Loki showing HA logs

---

## Success Criteria for 1-Month Evaluation (Feb 22 - Mar 22)

**Infrastructure Quality Metrics:**
1. **Reliability:** HA uptime >99.9% (measure via Prometheus)
2. **Observability:** All integration points functional (Prometheus, Loki, Grafana)
3. **Security:** External access requires Authelia MFA, no incidents
4. **Performance:** HA response time <500ms (measure via Traefik metrics)
5. **Presence detection:** iPhone WiFi sensor accuracy >95%

**Integration Validation:**
- Unpoller → HA presence sensor working reliably
- Prometheus metrics exported without gaps
- Loki logs correlated with service state changes
- Traefik routing + Authelia SSO seamless

**Evaluation Decision (March 22):**
- **Proceed to devices:** If infrastructure rock-solid and presence detection valuable
- **Expand integrations:** Add OpenThread Border Router (nRF52840), deploy Matter devices
- **Defer expansion:** If limited value, maintain HA for future but no hardware investment
- **Decommission:** If no value, remove HA/Matter Server (sunk cost: 3 weeks effort)

---

## Hardware Procurement Strategy (Deferred)

**What to buy AFTER successful 1-month evaluation:**

**Priority 1 (if expanding):**
- nRF52840 USB dongle (~$12 / ~100 NOK) - OpenThread Border Router
- 2-3x Matter bulbs (Eve, Nanoleaf) - Basic lighting test (~1,500 NOK)

**Priority 2 (if Priority 1 successful):**
- 4x Eve Energy smart plugs (~1,800 NOK) - Heating control
- 2x Aqara temperature sensors (~500 NOK) - Climate monitoring

**Priority 3 (optional):**
- Door/window sensors, motion detectors, additional lighting

**Key principle:** Validate infrastructure quality before hardware spend

---

# PART 3: Q1 2026 PATH FORWARD

## February 2026: Infrastructure Deployment

**Week 1 (Feb 1-7):**
- ✅ January SLO report generated (validates Course 2)
- Start Matter hybrid deployment: Network + Home Assistant
- Quarterly alert drill (test Tier 1/2 alerts fire correctly)

**Week 2 (Feb 8-14):**
- Matter Server deployment
- Unpoller → HA presence integration
- Traefik routing + Authelia SSO

**Week 3 (Feb 15-21):**
- Monitoring integration (Prometheus, Grafana, Loki)
- Test automation (iPhone presence)
- SLO calibration analysis (23+ days clean data)

**Week 4 (Feb 22-28):**
- Infrastructure validation complete
- Adjust SLO targets based on p95 performance
- Begin 1-month evaluation period

---

## March 2026: Evaluation & Course 3

**Week 1-2 (Mar 1-14):**
- Monitor HA infrastructure quality
- Validate presence detection accuracy
- Collect observability data (uptime, performance, integration health)

**Week 3 (Mar 15-21):**
- Evaluation decision point (expand vs maintain vs decommission)
- If expanding: Order nRF52840 dongle + initial Matter devices
- If maintaining: Document infrastructure for future use
- If decommissioning: Clean removal, lessons learned

**Week 4 (Mar 22-31):**
- **If Matter expansion:** Deploy OTBR, commission first devices
- **If Course 3 pivot:** Burn rate alert validation, Loki expansion, custom metrics
- Quarterly health review
- Q1 2026 wrap-up documentation

---

## End of Q1 Deliverables

### Operational Excellence
- ✅ Health score: 100/100 for 90 consecutive days (currently 13/90)
- ✅ SLO targets: Calibrated with Jan-Feb data (p95 analysis)
- ✅ Alert effectiveness: Quarterly drill passed
- ✅ Error budget: All services in positive budget by March 31

### Infrastructure Additions
- ✅ Home Assistant: Deployed, monitored, integrated with homelab
- ✅ Matter Server: Operational, ready for devices
- ✅ Presence detection: Unpoller WiFi-based iPhone detection working
- ⏳ Matter devices: Conditional on evaluation (March 22 decision)

### Process Improvements
- ✅ Monthly SLO reports: Jan, Feb, Mar generated
- ✅ Quarterly alert drill: Validated alert effectiveness
- ✅ Error budget checks: Integrated into deployment workflow

---

## Key Success Metrics

**Infrastructure (measured Feb 22 - Mar 22):**
- Home Assistant uptime: >99.9%
- Presence detection accuracy: >95%
- Prometheus scraping: 0 gaps
- External access: 0 security incidents

**Operational (measured Q1 end):**
- 100/100 health: 90 consecutive days
- SLO compliance: All services positive error budget
- Alert drill: Tier 1/2 fire within 2 minutes of simulated degradation

**Decision Quality (qualitative):**
- Infrastructure quality validated before hardware spend
- Homelab capability harvesting demonstrated (Prometheus, Unpoller, Loki)
- Clear evaluation criteria for expansion decision

---

## Critical Design Principles

### Infrastructure-First Philosophy

1. **Quality over features** - Prove integration excellence before expansion
2. **Homelab capability harvesting** - Leverage existing Prometheus/Loki/Unpoller
3. **Matter-ready platform** - Infrastructure prepared, devices when validated
4. **Observable system** - Metrics, logs, dashboards from day 1
5. **Security by design** - Authelia SSO, Traefik middleware, CrowdSec
6. **Evaluation-driven expansion** - Data-based decisions on hardware investment

### Presence Detection Architecture (Corrected)

**Principle:** Home WiFi connection indicates presence (not VPN)

**Why WiFi, not VPN:**
- VPN connected = away from home (remote access)
- Home WiFi connected = at home (local network)
- Unpoller provides WiFi client MAC detection
- iPhone connects to WiFi automatically when in range

**Implementation:**
```
Unpoller → Prometheus (WiFi client metrics)
  ↓
Home Assistant sensor (query Prometheus API)
  ↓
binary_sensor.iphone_home (template: WiFi connected = home)
  ↓
Automation trigger (presence-based actions)
```

**Use cases enabled:**
- Evening arrival: Turn on lights when iPhone joins home WiFi
- Morning routine: Gradual lighting when presence detected + time range
- Away mode: No presence for 30 min → energy saving mode

---

## Conclusion

January 2026 was a month of **firefighting and operational hardening** rather than feature expansion. The homelab achieved 100/100 health through systematic gap closure, but alert system issues (especially the 34-day burn rate bug) consumed significant effort.

**The Matter v2.0 plan was over-engineered** - 10 services, 9.5GB RAM, guest voice control, LLM-based automations. This scope was inappropriate for a homelab learning project.

**The Hybrid Approach is pragmatic:**
- Deploy Matter-ready infrastructure (Home Assistant + Matter Server)
- Harvest existing homelab capabilities (Prometheus, Unpoller, Loki)
- Validate integration quality for 1 month
- Decide on device expansion based on data (March 22)
- Minimize sunk cost if automation proves unnecessary

**Key insight:** The value is in **high-quality integration infrastructure** that harvests homelab monitoring/observability capabilities efficiently, not in premature device procurement or complex automation scenarios.

**Next steps:**
1. Week 1 Feb: Deploy HA + network infrastructure
2. Week 2 Feb: Matter Server + Unpoller presence integration
3. Week 3 Feb: Monitoring dashboards + test automation
4. March 22: Evaluation decision (expand, maintain, or decommission)

This approach balances **infrastructure excellence** (proven through evaluation) with **operational pragmatism** (minimal resource commitment until value validated).

---

## Files Referenced

**Monthly review basis:**
- `docs/98-journals/2026-01-22-slo-operational-excellence-phase1-2-findings.md`
- `docs/98-journals/2026-01-22-burn-rate-calculation-fix.md`
- `docs/98-journals/2026-01-09-course-2-operational-excellence-completion.md`
- `docs/97-plans/2025-01-09-strategic-development-trajectories-plan.md`

**Matter plans:**
- `docs/97-plans/2025-12-30-matter-home-automation-implementation-plan.md` (v2.0, 1,760 lines - over-engineered)
- **This document:** Hybrid infrastructure-first approach (approved)

**Auto-generated state:**
- `docs/AUTO-SERVICE-CATALOG.md` (26 services)
- `docs/AUTO-DOCUMENTATION-INDEX.md` (338 files)

**Commit history:**
- 79 commits (Dec 22, 2025 - Jan 22, 2026)
- Primary focus: Alert system overhaul, burn rate bug fix

---

**Status:** Hybrid approach approved, ready for Week 1 deployment (February 2026)
