# Home Assistant - Production System Guide

**Status:** Production (40 automations, 20+ devices)
**Platform:** Fedora Workstation 42 (Podman container)
**Access:** https://ha.patriark.org
**Location:** `~/containers/config/home-assistant/`

## Current System State

**40 Automations:**
- 10 time-based (Hue lighting schedules)
- 10 presence-based (arrival/departure, focus modes)
- 16 Roborock (smart cleaning, room commands)
- 4 iOS integration (Siri webhooks, focus detection)

**Integrated Devices:**
- Philips Hue (8 bulbs, 1 bridge, 1 remote)
- Roborock Saros 10 (vacuum + 14 sensors)
- Mill (3 heaters, 1 air sensor)
- iOS (iPhone 16, Apple Watch, iPad Pro)
- UniFi (network presence through Unpoller)

## Architecture Principles

### Integration Strategy

**Keep device hubs when they add value:**
- Hue Bridge: Instant physical control, firmware updates, reliability
- Roborock App: Scheduled cleans, map management
- Mill App: Device configuration, air purifier management

**Use Home Assistant for:**
- Cross-device orchestration
- Context-aware automation
- Unified dashboards
- Advanced logic (multi-condition triggers)

### Configuration Structure

```
config/home-assistant/
├── configuration.yaml          # Core config, integrations
├── automations.yaml           # All automations (40 total)
├── scenes.yaml                # Hue scenes (imported from bridge)
├── scripts.yaml               # Reusable action sequences
├── dashboards/
│   └── full_control_enhanced.yaml
└── custom_components/         # Future custom integrations
```

**Key Pattern:** Scenes in Hue app, automations in HA, dashboards unified.

## Core Automation Patterns

### 1. Time-Based Scheduling

**Use:** Predictable daily routines

```yaml
- id: weekday_morning_energize
  trigger:
    - platform: time
      at: "07:35:00"
  condition:
    - condition: time
      weekday: [mon, tue, wed, thu, fri]
    - condition: state
      entity_id: person.bjorn_robak
      state: "home"
  action:
    - service: scene.turn_on
      target:
        entity_id:
          - scene.stua_energize
          - scene.kjokken_energize
          - scene.gang_energize
```

**Why this works:** Time + presence condition prevents firing when away.

### 2. State-Based Automation

**Use:** React to device state changes

```yaml
- id: robot_vision_lighting_auto
  trigger:
    - platform: state
      entity_id: binary_sensor.saros_10_cleaning
      to: "on"
  condition:
    - condition: state
      entity_id: light.stua
      state: "off"
  action:
    - service: scene.turn_on
      target:
        entity_id: scene.stua_energize
```

**Why this works:** Lights follow robot state, not time. Condition prevents re-triggering.

### 3. Context-Aware Triggers

**Use:** Combine multiple signals for intelligent decisions

```yaml
- id: smart_clean_weekday
  trigger:
    - platform: state
      entity_id: binary_sensor.iphone_home
      to: "off"
      for:
        minutes: 30
  condition:
    - condition: time
      weekday: [mon, tue, wed, thu, fri]
      after: "07:00:00"
      before: "23:00:00"
    - condition: state
      entity_id: vacuum.saros_10
      state: "docked"
    - condition: numeric_state
      entity_id: sensor.saros_10_battery
      above: 30
    - condition: template
      value_template: "{{ state_attr('binary_sensor.iphone_16_focus', 'focus_name') == 'Work' }}"
  action:
    - service: vacuum.send_command
      target:
        entity_id: vacuum.saros_10
      data:
        command: app_segment_clean
        params:
          - segments: [6, 7, 3]  # Living room, Corridor, Dining room
            repeat: 1
```

**Why this works:** Multiple safety checks prevent unwanted execution.

### 4. Webhook-Based Voice Control

**Use:** iOS Shortcuts → HA actions

```yaml
- id: siri_clean_living_room
  trigger:
    - platform: webhook
      webhook_id: clean_living_room
      allowed_methods: [POST, GET]
  action:
    - service: vacuum.send_command
      target:
        entity_id: vacuum.saros_10
      data:
        command: app_segment_clean
        params:
          - segments: [6]
            repeat: 1
```

**iOS Shortcut:** `GET https://ha.patriark.org/api/webhook/clean_living_room`

**Why this works:** Simple HTTP GET, no auth required for webhooks, instant response.

## Key Configuration Patterns

### Room Segment Mapping (Roborock)

```yaml
# Obtained via: Developer Tools → Actions → roborock.get_maps
Living room (Stua):    6
Corridor (Gang):       7
Dining room (Kjokken): 3
Hall:                  4
Study:                 2
Master bedroom:        1
Bathroom:              5  # Excluded from auto-cleaning
```

**Usage:** Room-specific cleaning, group definitions (quick: 6,7,3 | extended: 6,7,3,4,2)

### Focus Mode Detection

```yaml
# iOS Focus Modes exposed via HA iOS app
binary_sensor.iphone_16_focus
  state: "on"/"off"
  attributes:
    focus_name: "Work"  # or "Sleep", "Personal", etc.
```

**Pattern:** Use focus state + name check for context-aware automation.

### Presence Detection

```yaml
# UniFi presence via Prometheus + template sensor
binary_sensor.iphone_home
  state: "on" (home) / "off" (away)

# Based on: sensor.iphone_unifi_connection (Unpoller metric)
```

**Why this works:** Network presence more reliable than GPS/iOS app location.

## Extending the System

### Adding New Automation

**Decision tree:**
1. **Single condition?** → Time-based trigger
2. **Multiple conditions?** → Add condition block
3. **React to state change?** → State-based trigger
4. **Need voice control?** → Add webhook + iOS Shortcut

**Template:**
```yaml
- id: unique_id_here
  alias: "Human-Readable Name"
  description: "What this does and why"
  trigger:
    - platform: state|time|webhook
      # ... trigger config
  condition:  # Optional
    - condition: state|numeric_state|template
      # ... safety checks
  action:
    - service: light.turn_on|scene.turn_on|vacuum.send_command
      # ... action config
```

### Adding New Device

**Integration checklist:**
1. **Official integration available?** → Settings → Add Integration
2. **Check entity IDs:** Developer Tools → States
3. **Test basic control:** Developer Tools → Actions
4. **Create automation:** Use patterns above
5. **Add to dashboard:** Lovelace YAML or UI editor

### Adding iOS Shortcut

**Steps:**
1. Create webhook automation in `automations.yaml`
2. Create iOS Shortcut: Get Contents of URL → `https://ha.patriark.org/api/webhook/<id>`
3. Add to Siri: "Hey Siri, [phrase]"
4. Test: Webhook should respond HTTP 200 immediately

## Maintenance Operations

### Configuration Reload
```bash
# After editing YAML files
podman restart home-assistant

# Check logs for errors
podman logs -f home-assistant | grep -i error
```

### Debugging Automations
1. **Settings → Automations → [Select] → Traces**
2. View execution history, condition failures
3. Check which condition blocked execution

### Backup Strategy
```bash
# Config files in git (containers repo)
cd ~/containers
git add config/home-assistant/
git commit -m "HA: description of changes"

# HA creates internal backups: /config/backups/
# Accessible via: Settings → System → Backups
```

## Common Patterns & Gotchas

### ✅ Do This

**Multi-condition safety:**
```yaml
condition:
  - condition: state
    entity_id: vacuum.saros_10
    state: "docked"
  - condition: numeric_state
    entity_id: sensor.saros_10_battery
    above: 30
  - condition: time
    after: "07:00:00"
    before: "23:00:00"
```

**State change delays:**
```yaml
trigger:
  - platform: state
    entity_id: person.bjorn_robak
    to: "not_home"
    for:
      minutes: 15  # Prevent false triggers
```

**Actionable notifications:**
```yaml
- service: notify.mobile_app_iphone_16
  data:
    title: "Action Required"
    message: "Description"
    data:
      actions:
        - action: "CONFIRM_ACTION"
          title: "Confirm"
```

### ❌ Avoid This

**Time-based without presence check:**
```yaml
# BAD: Fires even when away
trigger:
  - platform: time
    at: "07:00:00"
action:
  - service: light.turn_on
```

**Multiple triggers on same entity:**
```yaml
# CONFUSING: Use template or combine conditions instead
- id: automation_1
  trigger:
    platform: state
    entity_id: binary_sensor.motion
    to: "on"

- id: automation_2  # Avoid this pattern
  trigger:
    platform: state
    entity_id: binary_sensor.motion
    to: "off"
```

**Hardcoded values without explanation:**
```yaml
# BAD: What does 30 mean?
above: 30

# GOOD: Document meaning
above: 30  # Battery percentage threshold
```

## Integration Reference

### Philips Hue
- **Platform:** hue
- **Key entities:** `light.*`, `scene.*`, `sensor.*_battery`
- **Scene management:** Create in Hue app, activate from HA
- **Remote:** Works directly with bridge (no HA dependency)

### Roborock
- **Platform:** roborock
- **Key entities:** `vacuum.saros_10`, `sensor.saros_10_*`, `binary_sensor.saros_10_*`
- **Room cleaning:** `vacuum.send_command` with `app_segment_clean`
- **Maps:** Get room IDs via `roborock.get_maps` action

### Mill
- **Platform:** mill
- **Key entities:** `climate.mill_*`, `sensor.sense_*`
- **Note:** Air purifiers not supported (feature request submitted)

### iOS
- **Platform:** mobile_app
- **Key entities:** `person.*`, `binary_sensor.*_focus`, `device_tracker.*`
- **Focus modes:** Exposed as binary sensor with `focus_name` attribute
- **Webhooks:** Create in HA, trigger via iOS Shortcuts

### UniFi (via Prometheus)
- **Platform:** rest sensor
- **Query:** Prometheus API for Unpoller metrics
- **Presence:** Client uptime > 0 = home

## Useful Queries

### Find All Automations
```bash
grep "^- id:" ~/containers/config/home-assistant/automations.yaml | wc -l
```

### Check Entity States
```yaml
# Developer Tools → States
# Search: sensor.*, light.*, vacuum.*
```

### Test Automation Trigger
```yaml
# Developer Tools → Actions
# Service: automation.trigger
# Target: automation.smart_clean_weekday
```

### View Logs
```bash
# Real-time
podman logs -f home-assistant

# Specific integration
podman logs home-assistant 2>&1 | grep -i roborock

# Errors only
podman logs home-assistant 2>&1 | grep -i error
```

## Future Development: Three Trajectories

### Trajectory 1: Air Quality Expansion

**Goal:** Complete air quality monitoring across all rooms

**Prerequisites:** Mill air purifier integration support (feature request submitted)

**Steps:**
1. **Wait for Mill integration update** (1-3 months)
2. **Add air purifier sensors** to dashboard
3. **Create air quality automations:**
   ```yaml
   - CO₂ > 1200ppm → notification
   - PM 2.5 > 35µg/m³ → boost purifier fan
   - TVOC spike → ventilation reminder
   ```
4. **Air quality score calculation** (composite metric)
5. **Historical trending** via Grafana

**Why this trajectory:** Complete environmental monitoring, health benefits, data-driven decisions.

**Estimated effort:** 2-4 hours after integration available

### Trajectory 2: Advanced Presence & Occupancy

**Goal:** Room-level occupancy detection for intelligent automation

**Approach:** Matter motion sensors (Sep 2026 when Thread support mature)

**Steps:**
1. **Install Matter motion sensors** (3-5 sensors for key rooms)
2. **Room occupancy tracking:**
   ```yaml
   # Per-room presence
   binary_sensor.living_room_occupancy
   binary_sensor.bedroom_occupancy

   # Vacancy timer
   for:
     minutes: 15  # Room vacant
   ```
3. **Occupancy-based automation:**
   - Lights follow room occupancy
   - HVAC per-room optimization
   - Vacuum skip occupied rooms
4. **Nighttime presence detection** (bathroom trips → dim nightlight)
5. **Energy optimization** (unused room climate reduction)

**Why this trajectory:** Truly intelligent home that adapts to actual usage patterns.

**Estimated effort:** 8-12 hours (hardware + configuration)

**Hardware needed:**
- 3-5x Matter motion sensors (~$30-50 each)
- Thread border router (iOS 15.4+ devices already support this)

### Trajectory 3: Energy Management & Optimization

**Goal:** Monitor and optimize energy consumption

**Approach:** Matter smart plugs for panel heaters + energy dashboards

**Steps:**
1. **Install Matter smart plugs** (3x for panel heaters)
2. **Energy monitoring:**
   ```yaml
   # Real-time power draw
   sensor.heater_living_room_power
   sensor.heater_bedroom_power

   # Daily consumption
   sensor.heater_living_room_energy_daily
   ```
3. **Create energy dashboard:**
   - Real-time consumption (all devices)
   - Daily/weekly/monthly trends
   - Cost calculation (electricity price)
   - Heating efficiency analysis
4. **Smart HVAC scheduling:**
   - Away mode: Lower temperatures
   - Sleep mode: Bedroom only
   - Price-based optimization (cheap electricity hours)
5. **Automation opportunities:**
   ```yaml
   # Prevent simultaneous high loads
   - If vacuum running + heater on → reduce heater

   # Scheduled heating optimization
   - Preheat 30min before arrival
   - Night setback (22:00-06:00)
   ```

**Why this trajectory:** Cost savings, environmental impact, granular control.

**Estimated effort:** 6-10 hours

**Hardware needed:**
- 3x Matter smart plugs with energy monitoring (~$40-60 each)
- Existing Prometheus/Grafana (already have)

## Trajectory Selection Guidance

**Choose Trajectory 1 if:**
- Health-focused (air quality monitoring)
- Already have air purifiers
- Want passive monitoring (no new hardware)
- Low effort preference

**Choose Trajectory 2 if:**
- Want truly intelligent automation
- Willing to invest in sensors
- Value convenience over monitoring
- Long-term home automation vision

**Choose Trajectory 3 if:**
- Energy cost concerned
- Want concrete ROI (electricity savings)
- Already have panel heaters
- Data-driven optimization mindset

**Can combine trajectories:** All three are compatible and complementary. Suggested order: 1 → 3 → 2 (easiest to hardest).

## Dashboard Troubleshooting

### Evening Relaxation Dashboard Fixes (2026-02-01)

Two configuration errors were resolved in the Evening Relaxation dashboard:

#### Issue #1: Brightness Sliders (Tile #3)

**Error:** "Custom element not found: slider-entity-row"

**Root Cause:** The `custom:slider-entity-row` component was not installed. This is a HACS custom component that requires separate installation.

**Solution:** Replaced custom slider with built-in Home Assistant light controls.

**Before (broken):**
```yaml
- entity: light.stua
  name: Stue Lysstyrke
  type: custom:slider-entity-row
  full_row: true
```

**After (working):**
```yaml
- entity: light.stua
  name: Stue Lysstyrke
```

**Explanation:** Light entities in an `entities` card automatically render with brightness sliders - no custom component needed. This is native Home Assistant functionality.

**Verification:**
1. Open dashboard: https://home-assistant.patriark.org/evening/evening
2. Tile #3 "Lysstyrke Kontroll" should show sliders for all 3 lights
3. Dragging sliders should adjust brightness in real-time

---

#### Issue #2: Bedtime Conditional Card (Tile #10)

**Error:** "Configuration error. Conditions are invalid"

**Root Cause:** Lovelace conditional cards don't support `template` conditions. The syntax used was for automations, not dashboards.

**Broken configuration:**
```yaml
- type: conditional
  conditions:
    - condition: template
      value_template: |
        {{ now().hour >= 22 }}
```

**Solution:** Created template binary sensor in `configuration.yaml`, then referenced it in conditional card.

**Step 1: Add template sensor to configuration.yaml**
```yaml
template:
  - binary_sensor:
      - name: "Is Bedtime"
        unique_id: is_bedtime_sensor
        state: "{{ now().hour >= 22 }}"
        icon: >
          {% if now().hour >= 22 %}
            mdi:sleep
          {% else %}
            mdi:weather-night
          {% endif %}
```

**Step 2: Update dashboard to use sensor**
```yaml
- type: conditional
  conditions:
    - entity: binary_sensor.is_bedtime
      state: "on"
  card:
    type: markdown
    content: |
      ## 😴 Sengetid snart!
      ...
```

**Explanation:**
- Lovelace conditional cards only support `entity` + `state` conditions (not templates)
- Template logic must be moved to a binary sensor in `configuration.yaml`
- Binary sensor evaluates template every update (default: every minute)
- Dashboard simply checks if sensor is "on" or "off"

**Apply Changes:**
```bash
# 1. Restart Home Assistant to load new binary sensor
podman restart home-assistant

# 2. Wait ~30 seconds for restart

# 3. Verify sensor exists (Developer Tools → States)
# Search for: binary_sensor.is_bedtime

# 4. Dashboard will automatically reload
```

**Verification:**
1. Before 22:00 (10 PM): Tile #10 should NOT appear
2. After 22:00 (10 PM): Tile #10 "Sengetid snart!" should appear
3. Check sensor state: Developer Tools → States → `binary_sensor.is_bedtime`

**Testing bedtime logic:**
```yaml
# Temporarily modify configuration.yaml for testing
state: "{{ now().hour >= 15 }}"  # Change 22 to 15 (3 PM) for testing

# Restart Home Assistant
podman restart home-assistant

# Card should now appear after 3 PM
# Don't forget to change back to 22!
```

---

### Common Dashboard Patterns

**Conditional cards (state-based):**
```yaml
# Show card only when home
- type: conditional
  conditions:
    - entity: person.bjorn_robak
      state: "home"
  card:
    type: markdown
    content: "Welcome home!"
```

**Conditional cards (time-based):**
```yaml
# Create binary sensor in configuration.yaml first:
template:
  - binary_sensor:
      - name: "Is Morning"
        state: "{{ 6 <= now().hour < 12 }}"

# Then use in dashboard:
- type: conditional
  conditions:
    - entity: binary_sensor.is_morning
      state: "on"
  card:
    type: markdown
    content: "Good morning!"
```

**Built-in controls (no custom components):**
```yaml
# Light with brightness slider (automatic)
- entity: light.living_room

# Climate with temperature controls (automatic)
- entity: climate.bedroom_heater

# Cover with up/down buttons (automatic)
- entity: cover.bedroom_blinds

# Input number with slider (automatic)
- entity: input_number.comfort_temperature
```

---

## Resources

**Official Documentation:**
- Home Assistant: https://www.home-assistant.io/
- Philips Hue: https://www.home-assistant.io/integrations/hue/
- Roborock: https://www.home-assistant.io/integrations/roborock/
- Mill: https://www.home-assistant.io/integrations/mill/

**Local Documentation:**
- Journals: `/docs/98-journals/` (chronological history)
- Roborock setup: `/docs/10-services/guides/roborock-room-cleaning-setup.md`
- iOS Shortcuts: `/docs/10-services/guides/ios-shortcuts-quick-reference.md`
- Completion summary: `/docs/ROBOROCK-IMPLEMENTATION-COMPLETE.md`

**Community:**
- Home Assistant Community: https://community.home-assistant.io/
- GitHub Issues: https://github.com/home-assistant/core/issues

**Logs:**
```bash
podman logs home-assistant                    # All logs
podman logs -f home-assistant                 # Follow mode
podman logs home-assistant 2>&1 | grep error  # Errors only
```

**Configuration:**
```bash
# Location
cd ~/containers/config/home-assistant/

# Edit automations
nano automations.yaml

# Validate config
podman exec home-assistant python -m homeassistant --script check_config -c /config

# Restart
podman restart home-assistant
```

---

**Current Status:** Production-ready, 40 automations, 20+ devices integrated
**Skill Level:** Advanced intermediate - can independently extend system
**Next Action:** Choose development trajectory and begin implementation
