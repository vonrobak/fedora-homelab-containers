# Home Automation Hub Exploration - Phase Planning

**Date:** 2025-12-30
**Type:** Strategic Planning / Architecture Exploration
**Status:** Awaiting User Feedback

## Executive Summary

This journal entry explores the architectural trajectories for expanding the homelab into a comprehensive home automation hub. The expansion centers on three core additions:

1. **Home Assistant** - Central home automation orchestration
2. **Function Gemma** - Local LLM with function calling for intelligent automation
3. **Unpoller** - Unifi network observability

Combined with existing infrastructure (UDM Pro with IoT VLAN, Traefik reverse proxy, Authelia SSO, Prometheus/Grafana stack), this creates a powerful, privacy-respecting smart home platform.

## Current State Analysis

### Existing Smart Home Infrastructure

**Equipment Inventory:**
- **Lighting:** Philips Hue ecosystem (Bridge + Remote) - Zigbee-based, local control
- **Climate Control:**
  - Mill Sense (WiFi-enabled smart heater)
  - Mill Compact Pro (WiFi-enabled portable heater)
  - Mill Silent Pro (WiFi-enabled oil heater)
  - Mill Gen 1 panel heaters (decommissioned from Mill app control)
- **Cleaning:** Roborock Saros 10 (WiFi robot vacuum with advanced mapping)
- **Power:** Unknown Bluetooth smart plugs (controlled by BT switches)

**Network Architecture:**
- IoT devices on dedicated VLAN (192.168.2.0/24)
- Isolated from other subnets (security best practice ✓)
- Internet access permitted
- DNS provided by Pi-hole (ad blocking + local DNS)
- Managed by UDM Pro

**Homelab Services (Integration Points):**
- Traefik (reverse proxy) - Can expose Home Assistant securely
- Authelia (SSO + YubiKey MFA) - Can protect admin interfaces
- Prometheus/Grafana/Loki - Can consume metrics from Home Assistant, Unpoller
- CrowdSec - Can protect external-facing automation services
- Existing monitoring infrastructure

### Gap Analysis

**What's Missing:**

1. **Unified Orchestration** - No central platform coordinating devices
2. **Advanced Automation Logic** - Limited to vendor apps (Mill, Hue, Roborock)
3. **Network-Aware Automation** - Can't react to network conditions/presence
4. **Intelligent Decision Making** - No AI/ML layer for contextual automation
5. **Cross-Vendor Integration** - Devices operate in silos
6. **Granular Observability** - Can't monitor per-device metrics, automation performance
7. **Voice/Natural Language Control** - No interface beyond vendor apps
8. **Energy Monitoring** - Limited visibility into consumption patterns
9. **Presence Detection** - No sophisticated presence/occupancy tracking
10. **Security Automation** - Can't integrate with security events (CrowdSec ban → disable external access)

## Proposed Architecture: Three Trajectories

### Trajectory A: "Conservative Integration" (Low Risk, Moderate Capability)

**Philosophy:** Minimize architectural changes, add Home Assistant as standalone service.

**Architecture:**
```
┌─────────────────────────────────────────────────────────────────┐
│ Homelab Network (192.168.1.0/24)                                │
│                                                                  │
│  ┌──────────────┐      ┌──────────────┐      ┌──────────────┐  │
│  │   Traefik    │──────│   Authelia   │      │  Prometheus  │  │
│  │ (Gateway)    │      │ (Auth)       │      │  (Metrics)   │  │
│  └──────────────┘      └──────────────┘      └──────────────┘  │
│         │                                            ▲           │
│         │ Reverse Proxy                              │ Scrape   │
│         ▼                                            │           │
│  ┌──────────────────────────────────────────────────┼────────┐  │
│  │            Home Assistant Container              │        │  │
│  │  ┌─────────────┐  ┌──────────────┐  ┌──────────┴─────┐  │  │
│  │  │ Automation  │  │ Integrations │  │ Prometheus     │  │  │
│  │  │ Engine      │  │ (Hue, Mill)  │  │ Exporter       │  │  │
│  │  └─────────────┘  └──────────────┘  └────────────────┘  │  │
│  └──────────────────────────────────────────────────────────┘  │
│         │                                                       │
└─────────┼───────────────────────────────────────────────────────┘
          │ Routing via UDM Pro
          ▼
┌─────────────────────────────────────────────────────────────────┐
│ IoT VLAN (192.168.2.0/24) - ISOLATED                            │
│                                                                  │
│  ┌─────────┐  ┌─────────┐  ┌──────────┐  ┌──────────────────┐  │
│  │  Hue    │  │  Mill   │  │ Roborock │  │ Unknown BT Plugs │  │
│  │ Bridge  │  │ Heaters │  │ Vacuum   │  │                  │  │
│  └─────────┘  └─────────┘  └──────────┘  └──────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

**Implementation:**
- Single Home Assistant container on homelab network
- Firewall rule allows HA to reach IoT VLAN (unidirectional)
- HA discovers devices via mDNS/SSDP/API
- Expose HA UI via Traefik (ha.patriark.org)
- Protect with Authelia (YubiKey required)
- Export metrics to Prometheus

**Function Gemma Integration:**
- Run as sidecar container or HA add-on
- Communicate via HTTP/WebSocket
- Limited to HA automation actions

**Unpoller Integration:**
- Separate container scraping UDM Pro API
- Exports to Prometheus
- Grafana dashboards for network metrics

**Pros:**
- Simple to deploy and understand
- Clear security boundary (firewall controlled)
- Minimal impact on existing homelab
- Easy rollback if issues

**Cons:**
- Function Gemma capabilities limited by HA's API surface
- No deep integration between automation and homelab services
- Network routing dependency (UDM Pro firewall)
- Harder to do advanced "homelab-aware" automations

**Estimated Effort:** 2-3 weeks for core deployment, 1-2 months for integration polish

---

### Trajectory B: "Deep Integration" (Medium Risk, High Capability)

**Philosophy:** Treat home automation as first-class homelab capability, deep service integration.

**Architecture:**
```
┌─────────────────────────────────────────────────────────────────────────┐
│ Homelab Network (192.168.1.0/24)                                        │
│                                                                          │
│  ┌──────────────┐      ┌──────────────┐      ┌──────────────┐          │
│  │   Traefik    │──────│   Authelia   │      │  Prometheus  │          │
│  │              │      │              │      │  /Grafana    │          │
│  └───────┬──────┘      └──────────────┘      └──────┬───────┘          │
│          │                                           │                  │
│          │                                           │                  │
│  ┌───────▼─────────────────────────────────────────┬▼──────────────┐   │
│  │              Home Assistant Pod                  │               │   │
│  │  ┌────────────────┐  ┌───────────────────────┐  │  ┌─────────┐  │   │
│  │  │ Home Assistant │  │   Function Gemma      │  │  │ Node    │  │   │
│  │  │ Core           │◄─┤   (LLM Controller)    │  │  │ Exporter│  │   │
│  │  └────────────────┘  └───────────────────────┘  │  └─────────┘  │   │
│  │         ▲                      │                 │               │   │
│  │         │ MQTT/WebSocket       │ Function Calls  │               │   │
│  │         │                      ▼                 │               │   │
│  │  ┌──────┴──────────┐  ┌────────────────────┐   │               │   │
│  │  │  MQTT Broker    │  │ Automation Bridge  │   │               │   │
│  │  │  (Mosquitto)    │  │ (Custom Service)   │◄──┼───────────────┼───┤
│  │  └─────────────────┘  └────────────────────┘   │               │   │
│  └──────────────────────────────────────────────────────────────────   │
│         │                      │                                        │
│         │                      │ Can trigger homelab operations:       │
│         │                      │ - Restart services                     │
│         │                      │ - Query metrics                        │
│         │                      │ - Manage backups                       │
│         │                      │ - Security actions (CrowdSec ban)     │
└─────────┼──────────────────────┼────────────────────────────────────────┘
          │                      │
          │                      ▼
          │              ┌───────────────────┐
          │              │   Unpoller        │──► Prometheus
          │              │ (UDM Monitoring)  │
          │              └───────────────────┘
          │                      │
          │                      │ UDM Pro API
          ▼                      ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ IoT VLAN (192.168.2.0/24)                                               │
│                                                                          │
│  ┌─────────┐  ┌─────────┐  ┌──────────┐  ┌──────────────────┐          │
│  │  Hue    │  │  Mill   │  │ Roborock │  │ Zigbee Dongle    │          │
│  │ Bridge  │  │ Heaters │  │ Vacuum   │  │ (HA direct)      │          │
│  └─────────┘  └─────────┘  └──────────┘  └──────────────────┘          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Implementation:**
- **Home Assistant Pod:** Core + MQTT + Node Exporter
- **Function Gemma Container:** Standalone service with GPU access (if available)
- **Automation Bridge:** Custom Python service translating Function Gemma decisions into:
  - Home Assistant actions (via REST API)
  - Homelab actions (via Podman API, systemctl)
  - Prometheus queries (for context-aware decisions)

**Advanced Capabilities:**

1. **Homelab-Aware Automations:**
   - "If Jellyfin transcoding CPU >80% for 10min AND living room occupied, pause heater boost mode"
   - "If system disk >85%, pause Immich uploads and send notification"
   - "If CrowdSec bans >10 in 1hr, disable external access to smart home until reviewed"

2. **Network-Driven Automation:**
   - Unpoller detects device presence (DHCP leases, WiFi associations)
   - Trigger "Home" / "Away" scenes based on phone WiFi connection
   - "If no devices on home network for 30min, enable away mode"

3. **Intelligent Climate Control:**
   - Function Gemma analyzes: outdoor temp, energy price, occupancy, schedule
   - Optimizes heating: "Preheat bedroom to 21°C by 22:00, living room to 19°C by 18:00"
   - Learns preferences: "User always sets living room to 22°C on Friday evenings"

4. **Natural Language Control:**
   - "Gemma, I'm going to bed" → bedroom lights dim, hallway path lights on, living room heater down
   - "Gemma, prepare for movie night" → lights dim, disable motion sensors, pause vacuum
   - "Gemma, what's using the most power?" → Query Prometheus, respond with top consumers

5. **Predictive Maintenance Integration:**
   - HA device unavailability triggers homelab diagnostics
   - "Hue Bridge unreachable" → Check network, restart bridge, notify if failed
   - Correlate with Unpoller metrics (network issues vs device failure)

**Zigbee Expansion:**
- Add USB Zigbee dongle to HA container (Conbee II / Sonoff Zigbee 3.0)
- Migrate Hue devices to direct HA control (optional, for local control without bridge)
- Enable non-Hue Zigbee devices (sensors, buttons, plugs)

**Pros:**
- Maximum automation capabilities
- Cross-system intelligence (homelab + home automation)
- True natural language control via Gemma
- Network-aware presence detection
- Single pane of glass for all observability

**Cons:**
- Complex architecture (more failure modes)
- Custom code required (Automation Bridge)
- Gemma integration unproven (cutting edge)
- Higher resource requirements
- Longer development cycle

**Estimated Effort:** 1-2 months for core deployment, 3-6 months for advanced capabilities

---

### Trajectory C: "Research Platform" (High Risk, Experimental Capability)

**Philosophy:** Treat homelab as AI/automation research platform, explore bleeding edge.

**Architecture:**
- Everything from Trajectory B, plus:
  - **Multi-LLM Orchestration:** Gemma for fast local decisions, remote API (GPT-4/Claude) for complex reasoning
  - **Reinforcement Learning:** Train models on automation effectiveness (energy savings, user satisfaction)
  - **Autonomous Goal Optimization:** "Minimize energy cost while maintaining comfort" as learned objective
  - **Simulation Environment:** Digital twin of home for testing automations before deployment
  - **Advanced Sensors:** mmWave presence (FP2), environmental (temp/humidity/CO2), power monitoring
  - **Edge Computing:** Dedicated hardware for ML inference (Coral TPU, NVIDIA Jetson)

**Additional Services:**
- **Node-RED:** Visual automation programming (complements HA automations)
- **Frigate:** Local AI video analysis (person/object detection, presence)
- **ESPHome:** Custom sensor/actuator firmware (DIY devices)
- **AppDaemon:** Advanced Python-based automation scripting
- **InfluxDB:** Time-series database for high-resolution sensor data

**Pros:**
- Cutting-edge capabilities
- Research & learning opportunities
- Maximum flexibility
- Platform for future innovations

**Cons:**
- Very high complexity
- Significant hardware investment
- Long development timeline
- Stability concerns (experimental features)
- Potential for over-engineering

**Estimated Effort:** 3-6 months for initial platform, 6-12 months for advanced capabilities, ongoing research

---

## Component Deep Dives

### Home Assistant Deployment

**Recommended Approach: Podman Container (Not HAOS)**

**Rationale:**
- Aligns with existing homelab pattern (all services as containers)
- Full control over updates, networking, integration
- Avoids HAOS complexity (VM management, supervisor overhead)
- Integrates naturally with systemd quadlets

**Container Architecture:**

```yaml
# ~/.config/containers/systemd/home-assistant.container
[Unit]
Description=Home Assistant - Home Automation Hub
After=network-online.target
Wants=network-online.target

[Container]
Image=ghcr.io/home-assistant/home-assistant:latest
ContainerName=home-assistant

# Volumes
Volume=/home/patriark/containers/config/home-assistant:/config:Z
Volume=/etc/localtime:/etc/localtime:ro

# Networking
Network=systemd-reverse_proxy.network
Network=systemd-monitoring.network
PublishPort=127.0.0.1:8123:8123

# Privileged access for device discovery
AddDevice=/dev/ttyUSB0  # Zigbee dongle (if using)
Environment=TZ=Europe/Oslo

# Health check
HealthCmd=curl -f http://localhost:8123 || exit 1
HealthInterval=30s
HealthRetries=3
HealthStartPeriod=60s

[Service]
Restart=always
TimeoutStartSec=120

[Install]
WantedBy=default.target
```

**Traefik Integration:**

```yaml
# config/traefik/dynamic/routers.yml
http:
  routers:
    home-assistant:
      rule: "Host(`ha.patriark.org`)"
      service: home-assistant
      entryPoints:
        - websecure
      middlewares:
        - crowdsec-bouncer
        - rate-limit-auth
        - authelia
        - security-headers-strict
      tls:
        certResolver: letsencrypt

  services:
    home-assistant:
      loadBalancer:
        servers:
          - url: "http://home-assistant:8123"
        healthCheck:
          path: /
          interval: 30s
          timeout: 5s
```

**Key Integrations:**

1. **Prometheus Metrics:**
   - Built-in Prometheus exporter
   - Metrics: automation executions, entity states, system health
   - Scrape config: `prometheus.yml`

2. **MQTT Broker (Mosquitto):**
   - Separate container on same pod network
   - Enables Zigbee2MQTT, ESP devices
   - Lightweight, battle-tested

3. **Database (PostgreSQL or SQLite):**
   - Default SQLite fine for <100 devices
   - PostgreSQL recommended for >100 devices, advanced analytics
   - Share existing PostgreSQL container (if deployed)

**Network Access to IoT VLAN:**

```bash
# UDM Pro firewall rule (via UI or API)
# Allow: homelab network (192.168.1.0/24) → IoT VLAN (192.168.2.0/24)
# Specific source: Home Assistant container IP
# Destination: All IoT VLAN
# Ports: 80, 443, 1883 (MQTT), 5353 (mDNS)
# Direction: Unidirectional (IoT cannot initiate to homelab)
```

**Resource Estimates:**
- Memory: 200-500 MB (idle), up to 1 GB with many integrations
- CPU: <5% idle, 10-20% during automation execution
- Storage: 2-5 GB for config/database (grows with history retention)

---

### Function Gemma Integration

**What is Function Gemma?**

Function Gemma is Google's 2B/7B parameter LLM fine-tuned for function calling and tool use. Key characteristics:

- **Local Execution:** Runs entirely offline (privacy ✓)
- **Function Calling:** Native support for calling external APIs/functions
- **Small Models:** 2B model runs on CPU, 7B benefits from GPU
- **Open Weights:** Fully FOSS-compatible
- **Low Latency:** <1 second inference on modern hardware

**Architecture Options:**

#### Option 1: Ollama + Home Assistant Integration

```
Home Assistant ─► Ollama API ─► Function Gemma Model
                    │
                    └─► Returns function call → HA executes
```

**Implementation:**
```yaml
# ~/.config/containers/systemd/ollama.container
[Container]
Image=ollama/ollama:latest
ContainerName=ollama
Network=systemd-reverse_proxy.network
PublishPort=127.0.0.1:11434:11434
Volume=/home/patriark/containers/data/ollama:/root/.ollama:Z

# GPU support (if available)
# AddDevice=/dev/dri
# Environment=NVIDIA_VISIBLE_DEVICES=all

[Service]
Restart=always
```

```bash
# Load Function Gemma model
podman exec ollama ollama pull gemma2:2b-instruct-q4_K_M
```

**HA Configuration (Extended OpenAI Conversation):**

```yaml
# config/home-assistant/configuration.yaml
conversation:
  intents:
    SetTemperature:
      - "Set [room] to [temp] degrees"
      - "Make [room] [warmer|cooler]"

llm:
  - name: "Function Gemma"
    platform: ollama
    base_url: http://ollama:11434
    model: gemma2:2b-instruct-q4_K_M
    functions:
      - name: set_climate_temperature
        description: "Set target temperature for a climate device"
        parameters:
          type: object
          properties:
            entity_id:
              type: string
              description: "Entity ID of the climate device"
            temperature:
              type: number
              description: "Target temperature in Celsius"
      - name: turn_on_lights
        description: "Turn on lights in specified room"
        parameters:
          type: object
          properties:
            room:
              type: string
              enum: [living_room, bedroom, kitchen, hallway]
```

**Advantages:**
- Tight HA integration
- Official Ollama support in HA
- Simple deployment
- GPU optional (2B model)

**Limitations:**
- Function calling limited to HA's API
- No cross-system orchestration (can't directly control homelab)
- Gemma support via generic Ollama integration (not Gemma-specific)

#### Option 2: Custom Automation Bridge (Advanced)

```
User Input ─► Function Gemma ─► Automation Bridge ─┬─► Home Assistant API
                                                     ├─► Podman API (homelab)
                                                     ├─► Prometheus API (query)
                                                     └─► UDM Pro API (network)
```

**Custom Service (Python + FastAPI):**

```python
# ~/containers/services/automation-bridge/main.py
from fastapi import FastAPI
from pydantic import BaseModel
import ollama
import requests

app = FastAPI()

class AutomationRequest(BaseModel):
    user_input: str
    context: dict = {}

# Define available functions
FUNCTIONS = [
    {
        "name": "set_temperature",
        "description": "Set room temperature",
        "parameters": {
            "type": "object",
            "properties": {
                "room": {"type": "string"},
                "temperature": {"type": "number"}
            }
        }
    },
    {
        "name": "query_system_metrics",
        "description": "Query Prometheus for system metrics",
        "parameters": {
            "type": "object",
            "properties": {
                "query": {"type": "string"},
                "timeframe": {"type": "string"}
            }
        }
    },
    {
        "name": "restart_service",
        "description": "Restart a homelab service",
        "parameters": {
            "type": "object",
            "properties": {
                "service": {"type": "string"}
            }
        }
    }
]

@app.post("/execute")
async def execute_automation(request: AutomationRequest):
    # Send to Gemma with function definitions
    response = ollama.chat(
        model='gemma2:2b-instruct-q4_K_M',
        messages=[{
            'role': 'user',
            'content': request.user_input
        }],
        functions=FUNCTIONS
    )

    # Execute function calls
    if 'function_call' in response:
        func = response['function_call']

        if func['name'] == 'set_temperature':
            # Call Home Assistant API
            ha_response = requests.post(
                'http://home-assistant:8123/api/services/climate/set_temperature',
                headers={'Authorization': f'Bearer {HA_TOKEN}'},
                json={
                    'entity_id': f"climate.{func['arguments']['room']}",
                    'temperature': func['arguments']['temperature']
                }
            )
            return {'status': 'success', 'action': 'temperature_set'}

        elif func['name'] == 'query_system_metrics':
            # Query Prometheus
            prom_response = requests.get(
                f"http://prometheus:9090/api/v1/query",
                params={'query': func['arguments']['query']}
            )
            return {'status': 'success', 'data': prom_response.json()}

        elif func['name'] == 'restart_service':
            # Execute via Podman API or systemctl
            # (Implementation depends on security model)
            pass

    return {'status': 'no_action'}
```

**Advantages:**
- Maximum flexibility
- Cross-system orchestration
- Custom function definitions
- Can integrate ANY service

**Limitations:**
- Custom code to maintain
- Security considerations (service restart capability)
- More complex deployment

#### Option 3: Hybrid Approach (Recommended)

- **Tier 1 (Fast):** Ollama + HA for simple home automation commands
- **Tier 2 (Smart):** Custom bridge for complex cross-system automations
- **Tier 3 (Fallback):** Remote API (Claude/GPT-4) for truly complex reasoning

**Resource Estimates (Gemma 2B):**
- Memory: 2-4 GB
- CPU: 4-8 cores for <1s inference
- GPU: Optional, speeds up to <200ms
- Storage: 2-3 GB for model weights

**Resource Estimates (Gemma 7B):**
- Memory: 8-12 GB
- CPU: Not recommended (slow)
- GPU: 8GB VRAM minimum
- Storage: 5-7 GB for model weights

---

### Unpoller - Network Observability

**What is Unpoller?**

Unpoller scrapes metrics from Unifi controllers (UDM Pro) and exports to Prometheus/InfluxDB. Provides deep visibility into:

- Device connectivity (WiFi associations, DHCP leases)
- Traffic patterns (bandwidth, protocols, top talkers)
- AP performance (signal strength, interference, channel utilization)
- Client metrics (latency, packet loss, roaming)
- Port statistics (switch ports, PoE status)

**Deployment:**

```yaml
# ~/.config/containers/systemd/unpoller.container
[Unit]
Description=Unpoller - Unifi Metrics Exporter
After=network-online.target

[Container]
Image=ghcr.io/unpoller/unpoller:latest
ContainerName=unpoller
Network=systemd-monitoring.network

# Configuration
Volume=/home/patriark/containers/config/unpoller:/config:Z
Environment=UP_UNIFI_DEFAULT_URL=https://192.168.1.1
Environment=UP_UNIFI_DEFAULT_USER=unpoller
Environment=UP_UNIFI_DEFAULT_PASS=<secure-password>
Environment=UP_PROMETHEUS_DISABLE=false
Environment=UP_PROMETHEUS_NAMESPACE=unifi

PublishPort=127.0.0.1:9130:9130

[Service]
Restart=always

[Install]
WantedBy=default.target
```

**Prometheus Scrape Config:**

```yaml
# config/prometheus/prometheus.yml
scrape_configs:
  - job_name: 'unpoller'
    static_configs:
      - targets: ['unpoller:9130']
    scrape_interval: 30s
```

**Key Metrics for Automation:**

1. **Presence Detection:**
   - `unifi_device_wireless_client_count` - Connected clients per AP
   - `unifi_client_receive_bytes_total` - Active data transfer
   - `unifi_client_last_seen_seconds` - Recency of connection

2. **Network Health:**
   - `unifi_device_uptime_seconds` - Device stability
   - `unifi_device_state` - Online/offline status
   - `unifi_network_wan_latency_ms` - Internet latency

3. **IoT Device Monitoring:**
   - Filter by VLAN (192.168.2.0/24)
   - Track connectivity of smart home devices
   - Alert on prolonged disconnections

**Grafana Dashboards:**
- Official Unpoller dashboards available
- Custom dashboards for IoT VLAN
- Combined with HA metrics for holistic view

**Automation Use Cases:**

1. **Presence-Based Automation:**
   ```
   IF unifi_client{name="iPhone"} connected to home network
   AND last_seen < 5 minutes
   THEN trigger "Home" scene (lights, heating)
   ```

2. **Network-Aware Device Control:**
   ```
   IF unifi_network_wan_latency_ms > 100ms for 5min
   AND Jellyfin transcoding active
   THEN notify user "Slow network detected during streaming"
   ```

3. **IoT Device Health:**
   ```
   IF unifi_client{vlan="192.168.2.0/24", name="Hue Bridge"} last_seen > 10min
   THEN alert "Hue Bridge disconnected"
   AND trigger automation to check Hue API health
   ```

**Resource Estimates:**
- Memory: 50-100 MB
- CPU: <1%
- Storage: Negligible (metrics stored in Prometheus)

---

## Smart Home Equipment Recommendations

### Philosophy: Open Protocols, Local Control, No Cloud Dependencies

**Golden Rules:**
1. **Zigbee/Z-Wave over WiFi** - Lower power, mesh network, no internet required
2. **Local API Required** - Must function without cloud service
3. **Open Integration** - Works with Home Assistant natively or via custom component
4. **Matter/Thread Future-Proof** - New standard gaining traction
5. **FOSS Firmware Preferred** - Flashable to Tasmota/ESPHome is a plus

### Recommended Additions

#### 1. Presence Detection (HIGH PRIORITY)

**Aqara FP2 mmWave Sensor** (~$80)
- **Why:** Most accurate presence detection available
- **Tech:** 60GHz mmWave radar (detects breathing, subtle movement)
- **Advantage:** No false negatives (PIR misses stationary people)
- **Integration:** Home Assistant native (via Aqara Hub or Zigbee dongle)
- **Use Case:** "Living room occupied" → maintain temperature, keep lights on

**ESPresense BLE Tracking** (~$15 per ESP32 node)
- **Why:** Room-level presence via Bluetooth device tracking
- **Tech:** ESP32 with BLE scanning, MQTT reporting
- **Advantage:** Tracks phones/watches/tags, multi-room positioning
- **Integration:** MQTT → Home Assistant
- **Use Case:** "User in bedroom" → warm up bedroom, dim other rooms
- **Setup:** 3-5 ESP32 nodes strategically placed

#### 2. Climate Control Enhancements

**Zigbee Temperature/Humidity Sensors** (~$15-25 each)
- **Recommended:** Aqara, Sonoff, Tuya
- **Why:** Accurate per-room climate data
- **Placement:** Each room with heating (bedroom, living room, office)
- **Use Case:** "Bedroom temp 18°C but set to 21°C" → boost Mill heater

**Smart Radiator Valves (TRVs)** (~$40-60 each)
- **Recommended:** Danfoss Ally, Eurotronic Spirit, Aqara
- **Why:** Per-radiator temperature control (if you have hydronic heating)
- **Caveat:** Not applicable if only using Mill electric heaters
- **Alternative:** Smart plugs for Mill Gen 1 heaters (on/off control)

**Zigbee Smart Plugs** (~$15-20 each)
- **Recommended:** SONOFF S31 Lite, Innr SP120
- **Why:** Power monitoring, control of dumb devices
- **Use Case:**
  - Control Mill Gen 1 heaters (on/off scheduling)
  - Monitor power consumption of heaters
  - Replace unknown Bluetooth plugs with reliable Zigbee

#### 3. Advanced Sensors

**Aqara Door/Window Sensors** (~$15 each)
- **Why:** Automation triggers, security monitoring
- **Use Case:** "Front door opened" → disable away mode, turn on hallway lights

**Aqara Motion Sensors** (~$15 each)
- **Why:** Complement mmWave for instant detection, battery-powered
- **Use Case:** "Hallway motion at night" → dim path lighting to bedroom

**Aqara Vibration Sensor** (~$20)
- **Why:** Detect washing machine/dryer cycles, anomalies
- **Use Case:** "Washing machine vibration stopped" → notify laundry done

**Air Quality Sensor** (~$30-50)
- **Options:** Aqara TVOC, Xiaomi CO2, DIY ESPHome + SCD40
- **Why:** Automated ventilation, health monitoring
- **Use Case:** "CO2 > 1000ppm" → send notification to open windows

#### 4. Lighting Expansion

**Zigbee Bulbs (Non-Hue)** (~$10-15 each)
- **Recommended:** IKEA Tradfri, Innr, Sengled
- **Why:** Much cheaper than Hue, direct HA control
- **Strategy:** Keep Hue Bridge for existing Hue ecosystem, add budget bulbs via HA Zigbee

**Zigbee LED Strips** (~$25-40)
- **Recommended:** Gledopto, IKEA Tradfri
- **Use Case:** Under-cabinet lighting, accent lighting, bias lighting

**Smart Switches (Zigbee/Z-Wave)** (~$30-50)
- **Recommended:** Aqara Opple, IKEA Tradfri, Shelly (WiFi but local)
- **Why:** Control dumb bulbs, trigger scenes
- **Advantage:** Works with existing wiring, no need to replace bulbs

#### 5. Energy Monitoring

**Shelly EM** (~$50)
- **Why:** Whole-home energy monitoring, CT clamp measurement
- **Integration:** Local HTTP API, MQTT
- **Use Case:** Track total consumption, correlate with automation decisions
- **Advantage:** Works with Shelly Cloud disabled (fully local)

**Individual Smart Plugs with Power Monitoring**
- **Already mentioned:** SONOFF S31, innr SP120
- **Strategy:** Monitor high-power devices (heaters, vacuum, kitchen appliances)

#### 6. Voice Control (Optional, Privacy-Respecting)

**Wyoming Protocol + Rhasspy/Piper** (Local Voice)
- **Why:** Fully local voice control, no cloud
- **Components:**
  - Wake word detection (openWakeWord)
  - Speech-to-text (Whisper)
  - Intent recognition (HA Assist)
  - Text-to-speech (Piper)
- **Hardware:** Raspberry Pi 4 + USB mic/speaker OR ESP32-S3-BOX
- **Integration:** Wyoming protocol → HA
- **Function Gemma Integration:** Voice → Whisper → Gemma → HA actions

**Mycroft Mark II** (~$350, if available)
- **Why:** Purpose-built open-source voice assistant
- **Status:** Check availability (company had funding issues)
- **Alternative:** DIY solution cheaper and more flexible

### What to AVOID

#### 1. Cloud-Dependent Devices

**Examples:**
- **Nest Thermostat** - Requires Google account, cloud mandatory
- **Ring Doorbell** - Amazon cloud, subscription creep
- **TP-Link Kasa** - Works offline but gimped (no remote access, limited features)

**Why:** Privacy concerns, service discontinuation risk, cloud outages break your home

#### 2. Proprietary WiFi Devices (Without Local API)

**Examples:**
- **Tuya WiFi (without LocalTukey/CloudCutter)** - Cloud-dependent unless hacked
- **Generic Chinese WiFi plugs** - Often firmware locked, poor security

**Exception:** Shelly devices are WiFi but have excellent local API and FOSS commitment

#### 3. Bluetooth-Only Devices (for automation)

**Examples:**
- Your current unknown Bluetooth plugs
- Xiaomi Mi Band (for presence detection)

**Why:**
- Limited range (can't automate from HA container easily)
- No mesh capability (Zigbee/Z-Wave extend via mesh)
- Requires Bluetooth dongle on HA container (adds complexity)

**Exception:** BLE tracking for presence (ESPresense) is good because it's ESP32-based, not HA-direct

#### 4. Matter Devices (For Now)

**Status:** Matter is promising but immature (as of 2025-12)
- Many "Matter" devices still require vendor hubs
- Thread border routers needed (Apple TV, Google Nest)
- HA support improving but not complete

**Strategy:** Wait 6-12 months, revisit when ecosystem matures

#### 5. Battery-Powered Cameras

**Examples:** Arlo, Blink
- **Why:** Cloud-dependent, subscription model, poor local control

**Better Alternative:** Wired PoE cameras with Frigate (if adding video surveillance)

---

### Existing Equipment Analysis

#### Keep As-Is:
- **Philips Hue (Bridge + Remote)** - Excellent ecosystem, keep for existing bulbs
- **Roborock Saros 10** - Great vacuum, HA integration via Xiaomi Miio

#### Upgrade Path:
- **Mill Heaters (Sense, Compact Pro, Silent Pro):**
  - HA integration via Mill WiFi component
  - Consider adding Zigbee temp sensors for closed-loop control
  - Future: Replace WiFi control with smart plugs + local temp sensors (if Mill cloud fails)

- **Mill Gen 1 Panel Heaters:**
  - Add Zigbee smart plugs (SONOFF S31 with power monitoring)
  - Enables on/off scheduling, energy tracking
  - Budget: ~$20 per heater

- **Unknown Bluetooth Smart Plugs:**
  - **Replace with Zigbee smart plugs**
  - Reason: Better integration, power monitoring, mesh network
  - Migration: ~$15-20 per plug

---

## Additional Capabilities to Consider

### 1. Local Media Intelligence (FOSS AI Stack)

**Whisper.cpp** - Speech-to-text (OpenAI Whisper, local inference)
- Use Case: Transcribe voice memos, automate meeting notes
- Integration: API endpoint consumed by HA

**Stable Diffusion WebUI** - Image generation (local, privacy-preserving)
- Use Case: Generate custom artwork for digital displays
- Hardware: Requires GPU (8GB+ VRAM)

**Frigate** - Local AI video analysis
- Use Case: Person detection (driveway camera), package delivery alerts
- Hardware: Coral TPU recommended (~$60) for real-time inference
- Privacy: All video stays local, no cloud uploads

**Piper** - Neural text-to-speech
- Use Case: Natural voice notifications (better than robotic TTS)
- Integration: Wyoming protocol → HA

### 2. Document Management & Knowledge Base

**Paperless-ngx** - Document OCR and management
- Use Case: Digitize bills, receipts, manuals (including smart home device manuals)
- Integration: Scan → OCR → searchable archive
- Pattern: `document-management` deployment pattern available

**Wiki.js** - Knowledge base
- Use Case: Homelab documentation, automation runbooks, device databases
- Integration: Link from HA UI, cross-reference in automations

**Calibre-Web** - E-book library
- Use Case: Device manuals, smart home books, technical references
- Integration: Browse manuals from any device

### 3. Advanced Networking

**Pi-hole Integration with HA**
- Current: Pi-hole serves DNS to IoT VLAN
- Enhancement: HA sensor showing blocked queries, top domains
- Use Case: "Detect chatty IoT devices" → alert if device makes excessive cloud calls

**AdGuard Home** (Pi-hole Alternative)
- Advantage: Better HA integration, DNS-over-HTTPS, per-client config
- Consider: Migration if Pi-hole integration insufficient

**Wireguard VPN** (If Not Already Deployed)
- Use Case: Secure remote access to HA, homelab services
- Integration: VPN connection triggers "Home" presence
- Security: Better than exposing HA to internet (even with Authelia)

### 4. Backup & Disaster Recovery for HA

**Automated Backups:**
- HA config/database → BTRFS snapshot (daily)
- Offsite backup to cloud (encrypted)
- Integration: Backup automation before HA updates

**Configuration Management:**
- Git repository for HA `configuration.yaml`
- Automated commit on changes (via HA add-on or custom script)
- Enables version control, change tracking

**Testing Environment:**
- Separate HA instance (container) for testing automations
- Clone production config, safe experimentation
- Pattern: `home-assistant-test.container` alongside production

### 5. Energy Management & Solar Integration (Future)

**If Solar Panels Added:**
- **Solar Assistant** - PV monitoring
- **Grid Energy Optimization:**
  - "If solar surplus, boost water heater / run washing machine"
  - "If grid expensive (peak hours), reduce heating, defer charging"
- **Integration:** Prometheus metrics → Gemma decision making

**Current (No Solar):**
- Energy price API (Nordpool, if in Nordics)
- "Heat during cheap hours, coast during expensive"
- Shelly EM provides consumption data for optimization

### 6. Security Enhancements

**Fail2Ban for HA**
- Monitor HA login attempts
- Ban IPs after failed attempts
- Integration: Fail2Ban → CrowdSec (feed banned IPs to CrowdSec for homelab-wide protection)

**Intrusion Detection (Zeek/Suricata)**
- Monitor IoT VLAN traffic
- Alert on anomalies (IoT device calling unknown IP, port scans)
- Integration: Alerts → HA notification, CrowdSec ban

**HTTPS for IoT Devices (Where Possible)**
- Hue Bridge, Mill app API likely HTTP-only (internal network)
- Not critical (isolated VLAN) but good hygiene

---

## Integration Patterns

### Pattern 1: Presence-Based Automation

```
ESPresense (BLE) ──┐
Unpoller (WiFi)   ──┼──► Home Assistant ──► Automation ──► Actions
Aqara FP2 (mmWave)─┘         │
                              │
                              └──► Gemma (Natural Language Summary)
                                   "Patriark arrived home 5min ago, currently in living room"
```

**Automation Example:**
```yaml
alias: "Arrival Home Sequence"
trigger:
  - platform: state
    entity_id: person.patriark
    to: 'home'
condition:
  - condition: numeric_state
    entity_id: sensor.living_room_temperature
    below: 19
action:
  - service: climate.set_temperature
    target:
      entity_id: climate.mill_living_room
    data:
      temperature: 21
  - service: light.turn_on
    target:
      entity_id: light.hallway
    data:
      brightness_pct: 80
  - service: notify.discord
    data:
      message: "Welcome home! Living room heating to 21°C"
```

### Pattern 2: Predictive Climate Control

```
Prometheus (Historical Temp) ──┐
Weather API (Forecast)         ──┼──► Function Gemma ──► Optimization ──► HA Climate Actions
Occupancy Schedule             ──┤
Energy Price API               ──┘
```

**Gemma Prompt:**
```
Given:
- Current bedroom temp: 18°C
- Target temp: 21°C
- Occupancy: User typically sleeps 23:00-07:00
- Heater: Mill Compact Pro (1000W, ~1°C/hour heat rate)
- Energy price: Cheap until 22:00, expensive 22:00-06:00

When should I start heating to reach 21°C by 23:00 while minimizing cost?
```

**Gemma Function Call:**
```json
{
  "function": "set_climate_schedule",
  "arguments": {
    "entity_id": "climate.bedroom_mill",
    "schedule": [
      {"time": "22:00", "temperature": 21},
      {"time": "23:30", "temperature": 19}
    ]
  },
  "reasoning": "Start at 22:00 (3h heating = 21°C by bedtime). Drop to 19°C at 23:30 (asleep, blankets compensate). Saves 5h of expensive-rate heating."
}
```

### Pattern 3: Network-Aware Service Management

```
Unpoller (WAN Latency) ──┐
Jellyfin (Transcoding)   ──┼──► Prometheus Alert ──► Automation ──► Action
                           │
                           └──► "High latency + transcoding = poor UX"
                                 ──► Notify user
```

**Prometheus Alert:**
```yaml
- alert: HighLatencyDuringStreaming
  expr: |
    unifi_network_wan_latency_ms > 100
    AND
    jellyfin_transcoding_active > 0
  for: 5m
  annotations:
    summary: "Network latency high during video streaming"
    description: "WAN latency {{ $value }}ms while Jellyfin transcoding"
```

**HA Automation:**
```yaml
alias: "Network Congestion Notice"
trigger:
  - platform: webhook
    webhook_id: prometheus_alert
    allowed_methods: [POST]
condition:
  - condition: template
    value_template: "{{ trigger.json.alerts[0].labels.alertname == 'HighLatencyDuringStreaming' }}"
action:
  - service: notify.mobile_app
    data:
      title: "Streaming Quality Alert"
      message: "High network latency detected. Consider pausing other downloads."
      data:
        actions:
          - action: "pause_jellyfin"
            title: "Pause Streaming"
```

---

## Security & Privacy Considerations

### IoT VLAN Isolation

**Current State:** ✓ Isolated from other subnets
**Recommendation:** Maintain strict isolation

**Firewall Rules (UDM Pro):**
```
1. IoT → Internet: ALLOW (for device updates, cloud APIs)
2. IoT → Homelab (HA): DENY (devices can't initiate)
3. Homelab (HA) → IoT: ALLOW (HA initiates to devices)
4. IoT → Homelab (Prometheus): DENY (metrics pulled, not pushed)
5. IoT → IoT: ALLOW (internal mesh communication)
```

**Rationale:**
- Compromised IoT device can't attack homelab services
- HA container is hardened (regular updates, minimal attack surface)
- Metrics pulled via HA integration, not exposed endpoints

### Home Assistant Hardening

1. **Authentication:**
   - External access via Authelia (YubiKey MFA)
   - Local network: Still require HA login (multi-user support)
   - API tokens: Long-lived tokens only for trusted integrations

2. **Network Exposure:**
   - **DO NOT expose HA directly to internet**
   - Use Traefik + Authelia for external access
   - Consider: VPN-only access (Wireguard) for ultimate security

3. **Update Policy:**
   - HA updates: Wait 1-2 days after release (let community find bugs)
   - HACS (custom integrations): Review code before install
   - Backups before every update

4. **Secret Management:**
   - Secrets in `secrets.yaml` (gitignored)
   - Consider: Podman secrets for API tokens
   - Never commit secrets to Git

### Function Gemma Privacy

**Advantage of Local LLM:**
- All processing on-premises
- No data sent to Google/OpenAI
- Voice commands never leave home network

**Data Retention:**
- HA records all automation executions (useful for debugging)
- Consider: Retention policy (90 days? 1 year?)
- Sensitive commands: Avoid logging (mark automations as "hidden")

### Monitoring Privacy

**Prometheus/Grafana:**
- Contains sensitive data (presence, energy usage, network activity)
- External access: Require Authelia authentication
- Consider: Separate Grafana instance for public dashboards (limited data)

**Unpoller:**
- Knows all network clients (MAC addresses, hostnames)
- Do not expose metrics externally
- UDM credentials: Dedicated user with read-only access

---

## Resource Planning

### Current Homelab Baseline

**From CLAUDE.md:**
- Total memory usage: 2-3 GB
- CPU idle: >90%
- Disk: System SSD <60%, BTRFS plenty of space

### Estimated Additional Resources (Trajectory B)

| Service | Memory | CPU (Idle) | CPU (Peak) | Storage | GPU |
|---------|--------|------------|------------|---------|-----|
| Home Assistant | 300 MB | 2% | 15% | 3 GB | No |
| Mosquitto (MQTT) | 10 MB | <1% | <1% | Negligible | No |
| Ollama + Gemma 2B | 3 GB | 0% | 80% (during inference) | 3 GB | Optional |
| Unpoller | 80 MB | <1% | <1% | Negligible | No |
| Automation Bridge | 100 MB | <1% | 5% | 500 MB | No |
| **Total** | **+3.5 GB** | **+3%** | **+20%** | **+6.5 GB** | **No** |

**Total Homelab After Expansion:**
- Memory: 5.5-6.5 GB
- CPU: 5-8% idle, 25-30% peak (automation execution)
- Storage: +6.5 GB

**Hardware Requirement Check:**
- Modern system (8GB+ RAM, 4+ cores): ✓ Sufficient
- If Gemma 7B desired: 16GB RAM recommended
- If GPU inference desired: 8GB VRAM (RTX 3060+)

### Optional Enhancements (Trajectory C)

| Service | Memory | CPU | Storage | GPU |
|---------|--------|-----|---------|-----|
| Frigate (1 camera) | 500 MB | 5% | 10 GB/day | Coral TPU |
| Node-RED | 100 MB | <1% | 500 MB | No |
| Whisper.cpp (STT) | 1-2 GB | 20% (inference) | 1.5 GB | Optional |
| InfluxDB | 200 MB | 2% | 5 GB | No |

---

## Migration & Rollout Strategy

### Phase 1: Foundation (Weeks 1-2)

**Objective:** Deploy core Home Assistant + basic integrations

1. **Deploy Home Assistant Container**
   - Systemd quadlet
   - Traefik routing
   - Authelia protection
   - Prometheus metrics

2. **Integrate Existing Devices**
   - Philips Hue Bridge
   - Mill heaters (WiFi integration)
   - Roborock vacuum (Xiaomi Miio)

3. **Basic Automations**
   - Lighting scenes (existing Hue remote)
   - Simple scheduling (heaters on/off)

**Success Criteria:**
- HA accessible at ha.patriark.org
- All existing devices visible in HA
- At least 3 basic automations working

### Phase 2: Observability (Weeks 3-4)

**Objective:** Add monitoring and network intelligence

1. **Deploy Unpoller**
   - UDM Pro integration
   - Prometheus scraping
   - Grafana dashboard

2. **Configure HA Metrics**
   - Prometheus exporter
   - Key automation metrics
   - Dashboard creation

3. **Deploy MQTT Broker**
   - Mosquitto container
   - HA integration
   - Testing with mock devices

**Success Criteria:**
- Unpoller metrics in Grafana
- HA metrics tracked and visualized
- MQTT broker functional

### Phase 3: Intelligence (Weeks 5-8)

**Objective:** Add Function Gemma and advanced automation

1. **Deploy Ollama + Gemma**
   - Model download (2B or 7B)
   - HA integration (Ollama conversation)
   - Test function calling

2. **Advanced Automations**
   - Presence-based (using Unpoller WiFi detection)
   - Climate optimization
   - Natural language control

3. **Optional: Automation Bridge**
   - Custom service deployment
   - Cross-system functions
   - Testing

**Success Criteria:**
- Natural language commands working
- At least 5 intelligent automations deployed
- Cross-system awareness functional

### Phase 4: Expansion (Weeks 9-12)

**Objective:** Add new sensors and devices

1. **Order & Deploy Sensors**
   - Aqara FP2 mmWave (living room, bedroom)
   - Zigbee temp/humidity sensors (4-5 rooms)
   - Zigbee smart plugs (replace Bluetooth, add Mill Gen1 control)
   - Door/window sensors (entry points)
   - Motion sensors (hallways)

2. **Zigbee Network**
   - USB Zigbee dongle (Conbee II / Sonoff)
   - Device pairing
   - Mesh optimization

3. **Energy Monitoring**
   - Shelly EM deployment
   - Smart plug power monitoring
   - Energy dashboard

**Success Criteria:**
- All new sensors integrated
- Zigbee mesh stable (>20 devices)
- Energy tracking functional

### Phase 5: Refinement (Ongoing)

**Objective:** Optimize and expand capabilities

1. **Automation Tuning**
   - Adjust triggers/conditions
   - Eliminate false positives
   - Performance optimization

2. **Additional Capabilities**
   - Voice control (Wyoming + Whisper)
   - Video analysis (Frigate, if cameras added)
   - Advanced integrations

3. **Documentation**
   - Automation runbooks
   - Device database
   - Troubleshooting guides

---

## Questions for User Feedback

### 1. Trajectory Selection

**Which architectural trajectory resonates most?**
- **Trajectory A (Conservative):** Simple, stable, limited cross-system intelligence
- **Trajectory B (Deep Integration):** Recommended balance of capability and complexity
- **Trajectory C (Research Platform):** Maximum capability, highest complexity

**Follow-up:** What's your risk tolerance for experimental features?

### 2. Function Gemma Approach

**How important is natural language control?**
- **High:** Deploy Gemma with custom automation bridge (Trajectory B/C)
- **Medium:** Use Ollama + HA integration (simpler, HA-only control)
- **Low:** Skip Gemma for now, revisit in 6 months

**Follow-up:** Do you have GPU available? (Affects Gemma 2B vs 7B choice)

### 3. Sensor Investment

**What's your budget for sensors/devices?**
- **~$300:** Core sensors (mmWave, temp/humidity, smart plugs)
- **~$600:** Core + advanced (door/window, motion, energy monitoring)
- **~$1000+:** Full deployment (all sensors, voice control hardware, cameras)

**Follow-up:** Which rooms are highest priority for sensors?

### 4. Voice Control Priority

**How important is local voice control?**
- **High:** Deploy Wyoming stack + wake word detection immediately
- **Medium:** Plan for future, start with text-based Gemma control
- **Low:** Skip entirely, prefer app/automation-based control

**Follow-up:** Willing to DIY voice hardware (ESP32-S3) or prefer commercial (Mycroft)?

### 5. Existing Device Migration

**Replace Bluetooth smart plugs with Zigbee?**
- **Yes, immediately:** Order Zigbee plugs as part of Phase 4
- **Gradually:** Replace as Bluetooth plugs fail
- **No:** Keep using, accept limited integration

**Follow-up:** Interest in controlling Mill Gen 1 heaters via smart plugs?

### 6. Privacy vs Convenience

**External access to Home Assistant:**
- **VPN Only:** Maximum security, requires VPN connection for remote access
- **Traefik + Authelia (Current Plan):** Secure but accessible from internet
- **Both:** VPN for admin, Traefik for read-only dashboards

**Follow-up:** Need mobile app access while away? (Affects VPN decision)

### 7. Energy Optimization

**Interest in energy cost optimization?**
- **High:** Integrate energy price API (Nordpool?), optimize heating schedules
- **Medium:** Track consumption, manual optimization
- **Low:** Simple monitoring only

**Follow-up:** In a variable-pricing electricity market? (Nordpool, Tibber, etc.)

### 8. Future Video Surveillance

**Plans to add cameras?**
- **Yes, near-term:** Include Frigate in initial deployment
- **Maybe, future:** Plan architecture but don't deploy yet
- **No:** Skip video analysis components

**Follow-up:** If yes, how many cameras? (Affects Coral TPU need)

### 9. Zigbee Strategy

**Philips Hue migration:**
- **Keep Hue Bridge:** Use for Hue bulbs, HA controls bridge
- **Migrate to HA Zigbee:** Direct control, eliminate bridge dependency
- **Hybrid:** Keep bridge, add non-Hue Zigbee devices via HA dongle

**Follow-up:** Satisfaction with current Hue setup?

### 10. Timeline & Commitment

**Realistic timeline for full deployment:**
- **Fast Track (2-3 months):** Aggressive deployment, focus on core features
- **Steady Pace (3-6 months):** Recommended, allows learning and refinement
- **Long Term (6-12 months):** Gradual rollout, extensive experimentation

**Follow-up:** How much time per week can you dedicate? (Affects pace)

---

## Recommended Next Steps

1. **Provide Feedback** on questions above
2. **Finalize Trajectory** (A, B, or C)
3. **Create Detailed Implementation Plan** (based on trajectory + feedback)
4. **Order Initial Hardware** (Zigbee dongle, priority sensors)
5. **Deploy Phase 1** (Home Assistant foundation)

---

## Appendix: Reference Architecture Diagram

```
┌────────────────────────────────────────────────────────────────────────────────┐
│                         INTERNET (Port 80/443)                                 │
└────────────────────────────────┬───────────────────────────────────────────────┘
                                 │
                                 ▼
┌────────────────────────────────────────────────────────────────────────────────┐
│                     HOMELAB NETWORK (192.168.1.0/24)                           │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                         TRAEFIK (Gateway)                                │   │
│  │  Middleware: CrowdSec → Rate Limit → Authelia → Security Headers        │   │
│  └───────┬─────────────────────────────────────────────────────────────────┘   │
│          │                                                                      │
│          ├──────────────────┬──────────────────┬──────────────────┬────────────┤
│          ▼                  ▼                  ▼                  ▼            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │   Jellyfin   │  │   Immich     │  │   Grafana    │  │  Home Assistant  │  │
│  │   (Media)    │  │   (Photos)   │  │ (Monitoring) │  │   (Automation)   │  │
│  └──────────────┘  └──────────────┘  └──────┬───────┘  └─────────┬────────┘  │
│                                              │                     │           │
│  ┌───────────────────────────────────────────┼─────────────────────┼────────┐  │
│  │           MONITORING STACK                │                     │        │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌───▼──────┐  ┌──────────▼──────┐ │  │
│  │  │  Prometheus  │  │     Loki     │  │ Unpoller │  │   Mosquitto     │ │  │
│  │  │  (Metrics)   │  │    (Logs)    │  │(Network) │  │     (MQTT)      │ │  │
│  │  └──────────────┘  └──────────────┘  └──────────┘  └─────────────────┘ │  │
│  └──────────────────────────────────────────────────────────────────────────  │
│                                                                                 │
│  ┌──────────────────────────────────────────────────────────────────────────┐  │
│  │                    INTELLIGENCE LAYER                                    │  │
│  │  ┌────────────────────┐         ┌─────────────────────────────────────┐ │  │
│  │  │  Ollama + Gemma    │◄────────│    Automation Bridge (Optional)     │ │  │
│  │  │  (LLM Inference)   │         │  - HA API integration               │ │  │
│  │  └────────────────────┘         │  - Homelab orchestration            │ │  │
│  │                                  │  - Prometheus queries               │ │  │
│  │                                  └─────────────────────────────────────┘ │  │
│  └──────────────────────────────────────────────────────────────────────────  │
│                                     │                                          │
└─────────────────────────────────────┼──────────────────────────────────────────┘
                                      │
                        Firewall: Unidirectional
                        HA → IoT (Allow)
                        IoT → HA (Deny)
                                      │
                                      ▼
┌────────────────────────────────────────────────────────────────────────────────┐
│                     IoT VLAN (192.168.2.0/24) - ISOLATED                       │
│                           DNS: Pi-hole, Internet: Allowed                      │
│                                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌──────────────┐  ┌────────────────────┐  │
│  │  Hue Bridge │  │ Mill Heaters│  │  Roborock    │  │  Zigbee Dongle     │  │
│  │  (Zigbee)   │  │  (WiFi)     │  │  Vacuum      │  │  (USB to HA)       │  │
│  └─────────────┘  └─────────────┘  └──────────────┘  └────────────────────┘  │
│         │                │                │                    │               │
│         └────────────────┴────────────────┴────────────────────┘               │
│                              Zigbee Mesh                                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │ Smart Plugs  │  │ Temp Sensors │  │ mmWave (FP2) │  │ Door Sensors     │  │
│  │  (Zigbee)    │  │  (Zigbee)    │  │  (Zigbee)    │  │  (Zigbee)        │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────────┘  │
│                                                                                 │
└────────────────────────────────────────────────────────────────────────────────┘
```

---

**End of Journal Entry**

This exploration provides multiple trajectories for consideration. Awaiting user feedback to proceed with detailed implementation planning.
