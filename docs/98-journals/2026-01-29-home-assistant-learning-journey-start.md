# Home Assistant Learning Journey

**Started:** 2026-01-29
**Guide Reference:** `docs/10-services/guides/home-assistant-learning-path.md`
**Status:** 🟢 In Progress - Phase 1 Exercise 1.1 Complete

**Philosophy:** This journal tracks actual progress through the HA learning path, documenting deviations from the guide, obstacles encountered, and solutions implemented. The guide remains immutable as a reference; this journal reflects reality.

---

## Progress Overview

| Phase | Status | Started | Completed | Notes |
|-------|--------|---------|-----------|-------|
| **Phase 1: Philips Hue** | 🟡 In Progress | 2026-01-29 | - | Exercise 1.1 complete |
| Phase 2: Dashboards | ⏳ Not Started | - | - | - |
| Phase 3: Air Quality | ⏳ Not Started | - | - | - |
| Phase 4: Roborock + Focus | ⏳ Not Started | - | - | - |
| Phase 5: Homelab Integration | ⏳ Not Started | - | - | - |
| Phase 6: iPad Command Center | ⏳ Not Started | - | - | - |
| Phase 7: Calendar + Matter | ⏳ Not Started | - | - | - |

---

## Phase 1: Philips Hue Mastery

**Guide Reference:** Phase 1, Exercises 1.1-1.7 (~3 hours total)

**Current Status:** Exercise 1.1 complete ✅

---

### Exercise 1.1: Connect Hue Bridge to Home Assistant

**Started:** 2026-01-29
**Status:** ✅ Complete
**Time Spent:** ~1 hour (including network troubleshooting)

#### Network Topology Challenge (Deviation from Guide)

**Guide Assumption:** Home Assistant and IoT devices on same network

**Reality:** Network segmentation for security:
- **VLAN1 (patriark-lan):** 192.168.1.0/24 - fedora-htpc (192.168.1.70), Home Assistant
- **VLAN2 (IoT):** 192.168.2.0/24 - Hue Bridge (192.168.2.60), Roborock, Mill devices
- **Firewall:** UDM Pro blocks inter-VLAN traffic by default

**Discovery Process:**

1. **Initial test failed:**
   ```bash
   curl http://192.168.2.60/api/0/config
   # Result: Connection timeout
   ```

2. **Diagnosis:**
   - ✅ ICMP (ping) works: VLAN1 → VLAN2 gateway
   - ✅ Unpoller sees devices (via UniFi controller, not direct)
   - ❌ HTTP blocked: VLAN1 → VLAN2 port 80

3. **Root cause:** Firewall blocking inter-VLAN HTTP/HTTPS traffic

#### Firewall Rule Solution

**Created:** UDM Pro Firewall Rule - "HA to Hue Bridge"

**Initial Configuration (Failed):**
```
Action: Allow
Protocol: TCP
Source: 192.168.1.70, Source Port: 80,443  ← WRONG!
Destination: 192.168.2.60, Destination Port: 80,433  ← Typo + wrong concept
```

**Problem Identified:**
- When clients (curl, HA) connect to server, they use **random high source ports** (e.g., 54321)
- Source port restriction (80,443) blocked all traffic
- Destination port typo: 433 should be 443

**Correct Configuration (Working):**
```
Action: Allow
Protocol: TCP
Source: 192.168.1.70, Source Port: Any  ← Fixed
Destination: 192.168.2.60, Destination Port: 80,443  ← Fixed typo
```

**Additional Rule (mDNS Discovery):**
```
Action: Allow
Protocol: UDP
Source: 192.168.1.70, Source Port: 5353
Destination: 192.168.2.60, Destination Port: 5353
```

**Security Posture:**
- 🔒 Specific source IP (only fedora-htpc, not all VLAN1)
- 🔒 Specific destination IP (only Hue Bridge, not all VLAN2)
- 🔒 Limited ports (HTTP/HTTPS only, not all ports)
- 🔒 Hue API still requires authentication (network access ≠ control)

#### Firewall Rule Ordering Challenge

**Issue:** UniFi Network 10.0.162 GUI doesn't allow drag-and-drop rule reordering

**Context:**
- Rules evaluated top-to-bottom (first match wins)
- "Block All Traffic" rule at bottom
- Need "Allow HA to Hue" rule to execute before blocking rules

**UniFi Version:**
- Network Application: 10.0.162
- UDM Pro Firmware: 4.4.6

**Known Issue:** Multiple community reports of rule reordering problems in UniFi Network 10 ([source](https://community.ui.com/questions/Rule-reordering-simply-doesnt-work-in-Unifi-GUI/f2e7ef25-7a73-4f62-873a-ed3cbfd8a40a))

**Workaround:** Rules created in correct order evaluate properly despite inability to reorder in GUI

#### Hue Bridge Integration Success

**After firewall fix:**

1. **Connectivity confirmed:**
   ```bash
   curl http://192.168.2.60/api/0/config
   # Success! Returns Hue Bridge config JSON

   podman exec home-assistant curl http://192.168.2.60/api/0/config
   # Success! HA container can reach Hue Bridge
   ```

2. **Home Assistant integration:**
   - Settings → Devices & Services → Add Integration
   - Searched "Philips Hue"
   - Auto-discovered Hue Bridge at 192.168.2.60
   - Pressed physical button on Hue Bridge (authentication)
   - Integration successful!

3. **Imported successfully:**
   - ✅ **Hue Bridge Device:** ECB5FAFFFEAC1942 (BSB002 - Gen 2)
   - ✅ **8 Hue Bulbs:** All "White and Color Ambiance" bulbs
   - ✅ **Rooms:** All room configurations from Hue app
   - ✅ **Scenes:** All existing scenes from Hue app imported
   - ✅ **Hue Remote:** (integration to be explored in Exercise 1.7)

**Hue Bridge Details:**
```
Name: Hue Bridge
Bridge ID: ECB5FAFFFEAC1942
Model: BSB002 (Hue Bridge Gen 2)
API Version: 1.75.0
Software Version: 1975104000
IP: 192.168.2.60
Ports: 80 (HTTP), 443 (HTTPS)
```

#### Deviations from Guide

**Guide Path (assumes same network):**
- Step 1: Add integration → auto-discovery → authenticate
- Expected time: 10 minutes

**Actual Path (with VLAN segregation):**
- Step 0: Diagnose network connectivity issue
- Step 1: Create firewall rules (troubleshoot source port restriction)
- Step 2: Test connectivity (curl, nc, traceroute)
- Step 3: Add integration → auto-discovery → authenticate
- Actual time: ~1 hour

**Guide Improvement Needed:**
- Add "Network Topology Check" section before Exercise 1.1
- Document firewall rule requirements for VLAN-segregated setups
- Include connectivity test commands
- Common pitfall: Source port restrictions in firewall rules

#### Key Learnings

1. **Firewall Rule Fundamentals:**
   - **Source port = client's random port** (usually ephemeral range 32768-65535)
   - **Destination port = server's listening port** (e.g., 80, 443)
   - Client → Server connections: Source port must be "Any", destination port specific

2. **UniFi Network 10 Behavior:**
   - Rule reordering GUI limitations known issue
   - Creation order matters (can't easily fix later)
   - Rule index numbers (10000 series) indicate creation order

3. **Hue Bridge Protocol:**
   - HTTP (port 80): Primary API protocol
   - HTTPS (port 443): Available but less commonly used by HA
   - Both ports should be allowed for future compatibility

4. **Integration Success Factors:**
   - Network reachability tested before HA integration attempt
   - Podman container networking verified (HA can reach bridge)
   - Physical button press required (30-second authentication window)

#### Next Steps

**Remaining Phase 1 Exercises:**
- [ ] Exercise 1.2: Understanding Light Control Concepts (~15 min)
- [ ] Exercise 1.3: Hue Scenes - Best of Both Worlds (~20 min)
- [ ] Exercise 1.4: Time-Based Lighting Automation (~30 min)
- [ ] Exercise 1.5: Presence-Based Lighting (~30 min)
- [ ] Exercise 1.6: Norwegian Winter Lighting (~45 min)
- [ ] Exercise 1.7: Hue Remote Integration (~20 min)
- [ ] Phase 1 Checkpoint: Build First Dashboard (~30 min)

**Estimated Time Remaining:** ~2.5 hours

**Ready to Continue:** Yes - Hue integration working, all prerequisites met

---

## Equipment Inventory

### Existing Devices (Ready for Integration)

**Lighting:**
- ✅ **Philips Hue Bridge** (Gen 2, BSB002) - 192.168.2.60 - Integrated
- ✅ **8x Hue White and Color Ambiance Bulbs** - Integrated
- ✅ **Hue Remote** - Connected to bridge, HA integration pending

**Vacuum:**
- ⏳ **Roborock Saros 10** - 192.168.2.21 - Not yet integrated
  - Official HA integration available
  - Known issues with Saros 10 local API (workarounds documented)

**Air Quality:**
- ⏳ **Mill Sense Air** - VLAN2 - Integration status unknown
  - Sensors: Temperature, Humidity, eCO2, TVOC
  - No official HA integration for air purifiers
  - Test needed to determine if Mill integration supports Sense Air

- ⏳ **Mill Compact Pro** (air purifier) - 192.168.2.11 - No HA integration
- ⏳ **Mill Silent Pro** (air purifier) - 192.168.2.22 - No HA integration

**Heating:**
- ⏳ **Old Gen 1 Mill Panel Heaters** - Not smart-enabled
  - Gen 1 IoT system deprecated by Mill
  - Smart plug control planned (future: Eve Energy Matter plugs)

**Mobile Devices:**
- ✅ **iPhone** - WiFi presence detection working (Unpoller)
  - Entity: `binary_sensor.iphone_home`
  - iOS Focus Mode integration ready to implement
- ✅ **iPad** - Dashboard interface ready
- ✅ **Apple Watch** - Focus Mode control (triggers HA via webhooks)

### Future Hardware Purchases

**Phase 7: Matter Smart Plugs (Deferred)**
- 🛒 **4x Eve Energy (Matter)** - Not purchased
  - Cost: ~1,200-1,600 NOK
  - Use case: Control panel heaters
  - Deploy: Heating season (Sep-Oct 2026)

---

## Network Topology

**Infrastructure:**
- **Router/Firewall:** UniFi Dream Machine Pro (UDM Pro)
  - Network: 10.0.162
  - Firmware: 4.4.6
- **Primary AP:** UniFi Access Point (VLAN2)
- **Metrics Collection:** Unpoller → Prometheus (544 metrics/poll)

**VLANs:**

| VLAN | Name | Network | Purpose | Key Devices |
|------|------|---------|---------|-------------|
| 1 | patriark-lan | 192.168.1.0/24 | Primary network | fedora-htpc (192.168.1.70), PiHole (192.168.1.69) |
| 2 | IoT | 192.168.2.0/24 | IoT device segregation | Hue Bridge, Roborock, Mill devices |

**Firewall Rules (Relevant to HA):**

| Rule Name | Action | Source | Destination | Ports | Purpose |
|-----------|--------|--------|-------------|-------|---------|
| HA to Hue Bridge | Allow | 192.168.1.70 (any port) | 192.168.2.60 | TCP 80,443 | Hue API access |
| mDNS discovery HA to Hue Bridge | Allow | 192.168.1.70 | 192.168.2.60 | UDP 5353 | Service discovery |
| Allow DNS from VLAN2 to VLAN1 | Allow | 192.168.2.0/24 (any) | 192.168.1.69 | TCP/UDP 53 | PiHole DNS |

**Inter-VLAN Communication:**
- ✅ DNS: All VLANs → PiHole (192.168.1.69:53)
- ✅ HTTP/HTTPS: fedora-htpc → Hue Bridge (specific rule)
- ❌ General inter-VLAN: Blocked by default (security)

**Future Firewall Rules Needed:**
- HA → Roborock (192.168.2.21) - Ports TBD (integration testing)
- HA → Mill devices (if integration works) - Ports TBD

---

## Technical Environment

**Home Assistant Deployment:**
- **Version:** stable (ghcr.io/home-assistant/home-assistant:stable)
- **Platform:** Podman rootless container (systemd quadlet)
- **Host:** fedora-htpc (192.168.1.70, Fedora 42)
- **Memory:** 527MB actual / 2GB limit (26% utilization)
- **Networks:**
  - systemd-reverse_proxy (10.89.2.34) - Traefik routing, internet access
  - systemd-home_automation (10.89.6.2) - Matter Server communication (future)
  - systemd-monitoring (10.89.4.53) - Prometheus metrics export
- **External Access:** https://ha.patriark.org (Traefik → Authelia → HA)
- **Local Access:** http://192.168.1.70:8123

**Supporting Services:**
- **Matter Server:** 99MB / 512MB (deployed Week 2, ready for devices)
- **Traefik:** Reverse proxy with CrowdSec, rate limiting, Authelia
- **Prometheus:** Metrics collection (HA + Unpoller + homelab)
- **Loki:** Log aggregation
- **Grafana:** Dashboards

**Monitoring Integration:**
- ✅ Prometheus scraping HA `/api/prometheus` endpoint (configured)
- ✅ Loki ingesting HA logs via Promtail
- ⏳ Grafana "Home Automation" dashboard (to be created Phase 2)

---

## Obstacles Encountered & Solutions

### 1. VLAN Segregation Firewall Blocking

**Obstacle:** HA (VLAN1) couldn't reach Hue Bridge (VLAN2) due to firewall

**Impact:** Integration impossible without network connectivity

**Solution:**
- Created specific firewall rule: 192.168.1.70 → 192.168.2.60 (ports 80,443)
- Minimal security impact (specific IPs, limited ports)
- Maintained VLAN segregation security posture

**Time Lost:** ~30 minutes

**Prevention:** Network connectivity pre-check before integration attempts

---

### 2. Source Port Misconception in Firewall Rule

**Obstacle:** Firewall rule blocked traffic despite appearing correct

**Root Cause:** Source port set to 80,443 (should be "Any")
- Client connections use random ephemeral ports (32768-65535)
- Restricting source port to 80,443 blocks all legitimate traffic

**Diagnosis:**
- `curl -v` showed "Connection timed out"
- `nc -zv` confirmed TCP port unreachable
- Firewall logs would have shown dropped packets (not checked)

**Solution:** Changed source port from "80,443" to "Any"

**Time Lost:** ~20 minutes

**Learning:** Source port = client's random port; Destination port = server's port

**Prevention:** Firewall rule template in guide with correct port settings

---

### 3. UniFi Network 10 Rule Reordering Limitations

**Obstacle:** GUI doesn't allow reordering firewall rules

**Context:** Rules evaluated top-to-bottom; "Block All" at bottom needs exceptions above it

**Workaround:** Rules created in correct order worked without manual reordering

**Impact:** Minimal (rule worked once source port fixed)

**Known Issue:** Widespread UniFi Network 10 community reports

**Future Consideration:** If blocking rules added later, may need to delete/recreate allow rules

---

## Insights & Patterns

### Architecture Decisions Validated

1. **Keep Hue Bridge + HA (not HA-only):**
   - ✅ Hue remote still works (instant response via bridge)
   - ✅ Scenes created in Hue app imported seamlessly
   - ✅ Firmware updates managed by Signify
   - ✅ Proven reliability (millions of installations)
   - ✅ HA adds intelligence without replacing foundation

2. **VLAN Segregation Worth the Complexity:**
   - ✅ IoT devices isolated from primary network
   - ✅ Firewall provides defense in depth
   - ✅ Specific rules minimize attack surface
   - ⏰ Setup time: +1 hour for firewall configuration
   - 🎯 Security benefit: High

### Integration Quality Observations

**Hue Integration Maturity:**
- Official HA integration (not community HACS)
- Auto-discovery worked perfectly (via mDNS/UPnP)
- Scene import preserved Hue app configurations
- Room assignments maintained
- No manual entity configuration needed

**Expected Behavior:**
- Scenes appear as `scene.*` entities
- Lights appear as `light.*` entities
- Bridge appears as device with diagnostics
- Updates propagate bidirectionally (HA ↔ Hue app)

### Norwegian Context Applicability

**Winter Lighting Considerations (Phase 1, Exercise 1.6):**
- Exercise 1.6 addresses Norwegian dark winters (Oct-Mar)
- Focus on bright, cool lighting during day (combat SAD)
- Extra relevant given 8 color-capable bulbs
- Circadian rhythm automation particularly valuable

**Current Season:** January 2026 (peak dark season)
- Sunrise: ~09:30
- Sunset: ~15:30
- Daylight: ~6 hours
- **Perfect timing** to implement winter lighting automation

---

## Guide Refinements Needed (Post-Journey)

**After completing learning journey, update main guide with:**

1. **Pre-Integration Network Check:**
   - Add connectivity test commands
   - VLAN segregation detection
   - Firewall rule requirements for cross-VLAN

2. **Firewall Rule Template:**
   ```
   Source: <HA_IP>, Source Port: Any  ← Critical!
   Destination: <Device_IP>, Destination Port: <Service_Ports>
   ```

3. **UniFi-Specific Guidance:**
   - Document rule reordering limitations
   - Creation order importance
   - Workarounds for locked-down GUI

4. **Troubleshooting Decision Tree:**
   - Connection timeout → Check firewall
   - Firewall exists → Check source port = Any
   - Rule order → Check blocking rules above allow rules

5. **Success Validation Commands:**
   ```bash
   # Test 1: TCP connectivity
   nc -zv <DEVICE_IP> <PORT>

   # Test 2: HTTP API
   curl http://<DEVICE_IP>/api/endpoint

   # Test 3: From HA container
   podman exec home-assistant curl http://<DEVICE_IP>/api/endpoint
   ```

---

## Session Context for Future Claude

**If starting fresh session, key facts:**

1. **Current Progress:** Phase 1, Exercise 1.1 complete (Hue Bridge integrated)

2. **Network Topology:** VLAN segregation with firewall rules required
   - HA: 192.168.1.70 (VLAN1)
   - IoT devices: 192.168.2.0/24 (VLAN2)
   - Firewall rule exists: HA → Hue Bridge (working)

3. **Hue Integration Status:** ✅ Working perfectly
   - 8 bulbs integrated
   - Scenes imported
   - Rooms configured
   - Ready for automation exercises

4. **Next Steps:** Phase 1, Exercise 1.2 onwards (light control concepts)

5. **Key Learning:** Source port must be "Any" in firewall rules for client connections

6. **Device Inventory:** See "Equipment Inventory" section above

7. **Guide Philosophy:** Guide immutable, journal tracks reality and deviations

---

## Next Session TODO

**Immediate Next Steps:**
- [ ] Exercise 1.2: Test light control services (15 min)
- [ ] Exercise 1.3: Create/import additional Hue scenes (20 min)
- [ ] Exercise 1.4: First automation - time-based lighting (30 min)

**Before Phase 2:**
- [ ] Complete all Phase 1 exercises (1.2-1.7)
- [ ] Build Phase 1 checkpoint dashboard
- [ ] Verify all 8 bulbs controllable from HA

**Before Phase 3 (Air Quality):**
- [ ] Test Mill Sense Air integration attempt
- [ ] Document Mill integration status (works/doesn't work)
- [ ] If Mill fails: Document workaround approach

**Before Phase 4 (Roborock):**
- [ ] Add firewall rule: HA → Roborock (192.168.2.21)
- [ ] Ports: 58867 (local API) or cloud API
- [ ] Expect potential Saros 10 local API issues (documented in guide)

---

## Acknowledgments

**Guide Creation:** 2026-01-28
- Phase 1-2 detailed exercises
- Phase 3: Air quality monitoring (Mill devices)
- Phase 4: Roborock + iOS Focus Mode integration
- Phase 7: Calendar automation + Matter smart plugs reference

**Total Guide Length:** 3,952 lines across 4 documents

**Key Innovation:** iOS Focus Mode + Apple Watch integration (1-2 second smart home context changes via webhooks)

---

**Journal Status:** Active - append progress as exercises completed
**Last Updated:** 2026-01-29
**Next Update:** After Exercise 1.2 or next major milestone
