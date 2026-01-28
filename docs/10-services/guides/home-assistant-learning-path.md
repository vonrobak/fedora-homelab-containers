# Home Assistant Learning Path: From Basics to Elite Smart Home

**Date:** 2026-01-28
**Status:** Active Learning Guide
**Goal:** Master Home Assistant through hands-on exercises using existing devices

**Philosophy:** Progressive learning from easiest (Philips Hue) to advanced (homelab integration), with beautiful dashboards built incrementally.

---

## Learning Principles

1. **Hands-on exercises** - Each phase builds on the previous, using your actual devices
2. **Incremental dashboards** - Build beautiful UI as capabilities expand
3. **Homelab showcase** - Leverage your elite monitoring infrastructure (unique capabilities)
4. **Reliability first** - Keep existing control methods (Hue remote, apps) working
5. **Open source & privacy** - All local processing, no cloud dependencies where possible

---

## Table of Contents

- [Phase 1: Philips Hue Mastery](#phase-1-philips-hue-mastery) (Week 1-2) ⭐ **START HERE**
- [Phase 2: Dashboard Design Fundamentals](#phase-2-dashboard-design-fundamentals) (Week 2)
- [Phase 3: Mill Climate Control](#phase-3-mill-climate-control) (Week 3)
- [Phase 4: Roborock Intelligence](#phase-4-roborock-intelligence) (Week 3-4)
- [Phase 5: Homelab Integration Showcase](#phase-5-homelab-integration-showcase) (Week 4-5)
- [Phase 6: iPad Command Center](#phase-6-ipad-command-center) (Week 5-6)
- [Phase 7: Matter Smart Plugs for Heaters](#phase-7-matter-smart-plugs-for-heaters) (Future)

---

# Phase 1: Philips Hue Mastery

**Duration:** Week 1-2
**Difficulty:** Beginner
**Devices:** 8x Philips Hue White and Color Ambiance bulbs, Hue Bridge, Hue Remote
**Goal:** Master lighting control, understand HA concepts through hands-on Hue integration

---

## Architecture Decision: Hue Bridge + Home Assistant

### Recommended Approach: **Keep Both, Use Strategically**

```
┌─────────────────────────────────────────────────────────┐
│                    Control Layers                        │
├─────────────────────────────────────────────────────────┤
│  Physical Control  │  Hue Remote → Hue Bridge (instant) │
│  Basic Scenes      │  Hue App → Hue Bridge (reliable)   │
│  Orchestration     │  Home Assistant → Hue Bridge        │
│  Automation        │  Home Assistant automations         │
│  Dashboards        │  iPad HA app (beautiful UI)         │
└─────────────────────────────────────────────────────────┘
```

### Why Keep the Hue Bridge?

**Reliability:**
- ✅ Lights work during HA maintenance/updates
- ✅ Hue remote continues to function (instant, no latency)
- ✅ Firmware updates managed by Signify (automatic security patches)
- ✅ Proven stability (millions of installations)

**Performance:**
- ✅ Scene optimization: Commands sent to all lights simultaneously ([source](https://www.home-assistant.io/integrations/hue/))
- ✅ Hue Bridge handles local processing (reduces HA load)
- ✅ Sub-100ms response time for remote/switch inputs

**Future-proof:**
- ✅ Can migrate to Matter later without losing functionality
- ✅ Compatible with new Hue features (SpatialAware scenes coming Spring 2026) ([source](https://www.signify.com/global/our-company/news/press-releases/2026/20260107-philips-hue-revolutionizes-lighting-design-with-hue-spatialaware-feature-that-understands-your-space))
- ✅ Partner acceptance: Physical remote remains instant

**What Home Assistant Adds:**
- 🎯 **Cross-device orchestration** (lights + heaters + vacuum)
- 🎯 **Advanced automations** (presence-based, time-based, conditional logic)
- 🎯 **Beautiful dashboards** (unified control interface)
- 🎯 **Homelab integration** (Prometheus metrics, security awareness)

### Scene Management Strategy

**Create scenes in:** Hue app
**Activate scenes from:** Home Assistant (imported as scene entities)
**Why:** Hue app provides optimized scene creation; HA provides intelligent activation ([source](https://www.home-assistant.io/integrations/hue/))

---

## Exercise 1.1: Connect Hue Bridge to Home Assistant

**Time:** 10 minutes
**Concepts:** Integration setup, automatic discovery, API authentication

### Steps

1. **Navigate to integrations**
   - Settings → Devices & Services → Add Integration
   - Search for "Philips Hue"

2. **Automatic discovery**
   - Home Assistant should auto-detect your Hue Bridge on the network
   - If not found: Enter bridge IP manually (check your router/UDM Pro)

3. **Authenticate**
   - Press the physical button on top of Hue Bridge
   - Click "Submit" in Home Assistant within 30 seconds

4. **Verify import**
   - Check Developer Tools → States
   - Filter by "light." - should see 8 bulbs
   - Filter by "scene." - should see Hue app scenes imported

### Expected Result

```yaml
# Example entities created:
light.living_room_ceiling
light.bedroom_1
scene.energize  # Imported from Hue app
scene.relax     # Imported from Hue app
sensor.hue_bridge  # Bridge status
```

**✅ Success criteria:**
- All 8 bulbs visible in HA
- Hue Bridge shows as "Connected"
- Can control bulbs from HA UI (on/off, brightness, color)
- Hue remote still works (instant response)

---

## Exercise 1.2: Understanding Light Control Concepts

**Time:** 15 minutes
**Concepts:** State, attributes, services, entity IDs

### Hands-On: Control a Single Bulb

1. **Open Developer Tools → States**
   - Find `light.living_room_ceiling` (or your bulb name)
   - Note the **state**: `on` or `off`
   - Click the entity → see **attributes**:
     - `brightness`: 0-255
     - `color_temp`: Warm (500) to Cool (153) in mired
     - `rgb_color`: [255, 0, 0] for red, etc.
     - `supported_features`: What this bulb can do

2. **Open Developer Tools → Services**
   - Service: `light.turn_on`
   - Target: Select your bulb
   - Try these variations:

   ```yaml
   # Variation 1: Simple on
   service: light.turn_on
   target:
     entity_id: light.living_room_ceiling

   # Variation 2: Set brightness
   service: light.turn_on
   target:
     entity_id: light.living_room_ceiling
   data:
     brightness_pct: 50

   # Variation 3: Set color
   service: light.turn_on
   target:
     entity_id: light.living_room_ceiling
   data:
     rgb_color: [255, 100, 0]  # Orange
     brightness_pct: 75

   # Variation 4: Warm white
   service: light.turn_on
   target:
     entity_id: light.living_room_ceiling
   data:
     color_temp: 400  # Warm (higher = warmer)
     brightness_pct: 30
   ```

3. **Observe Hue remote still works**
   - While HA is controlling bulb, use Hue remote
   - Notice instant response (direct bridge control)
   - Check HA UI updates to reflect remote changes

**💡 Key Learning:**
- Entities have **state** (on/off) and **attributes** (brightness, color)
- Services are **actions** you call with **data** parameters
- Hue Bridge synchronizes state between HA, remote, and app

---

## Exercise 1.3: Hue Scenes - Best of Both Worlds

**Time:** 20 minutes
**Concepts:** Scene entities, scene activation, Hue app integration

### Part A: Create Scenes in Hue App

1. **Open Philips Hue app on your phone**
2. **Create these test scenes:**
   - **"Focus"**: All lights cool white (4000K), 100% brightness
   - **"Relax"**: All lights warm white (2700K), 40% brightness
   - **"Movie"**: All lights dim red, 5% brightness
   - **"Energize"**: If not already created (Hue preset)

3. **Test scenes in Hue app** to verify they look good

### Part B: Use Scenes from Home Assistant

1. **Restart Home Assistant** (Settings → System → Restart)
   - This imports the new scenes you created

2. **Find scene entities**
   - Developer Tools → States
   - Filter by "scene."
   - Should see: `scene.focus`, `scene.relax`, `scene.movie`, etc.

3. **Activate scene from HA**
   - Developer Tools → Services
   - Service: `scene.turn_on`
   - Target: `scene.relax`
   - Call Service

4. **Compare activation methods:**

   **Method 1: Simple scene activation**
   ```yaml
   service: scene.turn_on
   target:
     entity_id: scene.relax
   ```

   **Method 2: Hue-specific activation with overrides**
   ```yaml
   service: hue.activate_scene
   data:
     group_name: "Living Room"  # Hue Bridge group name
     scene_name: "Relax"
     transition: 5  # Fade over 5 seconds
     brightness: 80  # Override brightness to 80%
   ```

**💡 Key Learning:**
- Scenes are created/edited in Hue app (optimized performance)
- Scenes imported to HA as `scene.*` entities
- `hue.activate_scene` service allows runtime overrides (brightness, transition time)
- Scenes activate **all lights simultaneously** (faster than individual commands) ([source](https://www.home-assistant.io/integrations/hue/))

---

## Exercise 1.4: Your First Automation - Time-Based Lighting

**Time:** 30 minutes
**Concepts:** Automations, triggers, conditions, actions, time-based control

### Goal: Implement Circadian Rhythm Lighting

Create automations that adjust lighting based on time of day (Norwegian context: extra important during dark winters).

### Automation 1: Morning Energize (Weekdays)

```yaml
# File: ~/containers/config/home-assistant/automations.yaml
# (Or create via UI: Settings → Automations)

- id: morning_energize_weekday
  alias: "Morning: Energize Scene (Weekdays)"
  description: "Activate energizing cool light on weekday mornings"

  trigger:
    - platform: time
      at: "07:00:00"

  condition:
    - condition: time
      weekday:
        - mon
        - tue
        - wed
        - thu
        - fri

  action:
    - service: scene.turn_on
      target:
        entity_id: scene.energize
    - service: notify.persistent_notification
      data:
        title: "Good Morning! ☀️"
        message: "Energize lighting activated. Have a great day!"
```

### Automation 2: Evening Relax

```yaml
- id: evening_relax
  alias: "Evening: Relax Scene"
  description: "Warm lighting for evening relaxation"

  trigger:
    - platform: sun
      event: sunset
      offset: "-00:30:00"  # 30 min before sunset

  action:
    - service: hue.activate_scene
      data:
        group_name: "Living Room"
        scene_name: "Relax"
        transition: 60  # Slow 60-second fade
```

### Automation 3: Bedtime Dim

```yaml
- id: bedtime_dim
  alias: "Bedtime: Dim All Lights"
  description: "Very dim warm lights for bedtime routine"

  trigger:
    - platform: time
      at: "22:30:00"

  action:
    - service: light.turn_on
      target:
        entity_id: all  # Special: all lights
      data:
        brightness_pct: 10
        color_temp: 500  # Very warm
        transition: 10
```

### Test Your Automations

1. **Manual trigger test:**
   - Settings → Automations
   - Find "Morning: Energize Scene"
   - Click three dots → Run
   - Verify scene activates

2. **Edit trigger time:**
   - Temporarily change morning automation to trigger in 2 minutes
   - Wait and observe automatic execution
   - Change back to 07:00

3. **Check automation history:**
   - Settings → Automations → Click automation
   - View "Last Triggered" timestamp
   - See execution history (success/failure)

**💡 Key Learning:**
- **Triggers** start the automation (time, sun, state change)
- **Conditions** gate execution (only run if condition true)
- **Actions** are what happens (scenes, notifications, service calls)
- Automations run automatically based on triggers

---

## Exercise 1.5: Presence-Based Lighting

**Time:** 30 minutes
**Concepts:** Binary sensors, state triggers, presence detection

### Goal: Welcome Home Lighting

Use your existing `binary_sensor.iphone_home` (WiFi presence) to trigger arrival lighting.

### Automation: Arrival Scene

```yaml
- id: arrival_welcome_home
  alias: "Arrival: Welcome Home"
  description: "Turn on lights when iPhone connects to WiFi"

  trigger:
    - platform: state
      entity_id: binary_sensor.iphone_home
      from: "off"
      to: "on"

  condition:
    # Only trigger if it's evening/night (after sunset)
    - condition: sun
      after: sunset

  action:
    - service: scene.turn_on
      target:
        entity_id: scene.relax
    - service: notify.mobile_app_iphone  # If HA app installed on iPhone
      data:
        title: "Welcome Home! 🏠"
        message: "Relax lighting activated."
```

### Enhancement: Extended Away Detection

```yaml
- id: away_mode_lights_off
  alias: "Away: Turn Off Lights After 15 Minutes"
  description: "Energy saving when away from home"

  trigger:
    - platform: state
      entity_id: binary_sensor.iphone_home
      from: "on"
      to: "off"
      for:
        minutes: 15  # Wait 15 min to avoid false triggers

  action:
    - service: light.turn_off
      target:
        entity_id: all
      data:
        transition: 5  # Slow fade out
```

### Test Procedure

1. **Simulate arrival:**
   - Disconnect iPhone from WiFi
   - Wait 30 seconds (sensor update interval)
   - Verify `binary_sensor.iphone_home` shows "not_home" in HA
   - Reconnect iPhone to WiFi
   - Wait after sunset
   - Observe arrival automation triggers

2. **Check automation in daylight:**
   - Trigger should fire
   - Condition should prevent action (sun not set)
   - Check automation history: "Condition not met"

**💡 Key Learning:**
- **State triggers** fire when entity changes state (off → on)
- **For:** parameter prevents false triggers (must stay in state for duration)
- **Conditions** prevent unwanted automation execution
- Presence detection enables context-aware automation

---

## Exercise 1.6: Advanced - Norwegian Winter Lighting

**Time:** 45 minutes
**Concepts:** Sun integration, seasonal adaptation, color temperature automation

### Goal: Combat Seasonal Affective Disorder (SAD) with Smart Lighting

During Norwegian dark months (October-March), maximize bright, cool lighting during the day.

### Helper: Input Boolean for Winter Mode

1. **Create helper:**
   - Settings → Devices & Services → Helpers
   - Add Helper → Toggle
   - Name: "Winter Lighting Mode"
   - Entity ID: `input_boolean.winter_mode`

2. **Manual toggle or automation:**

```yaml
# Automation: Enable Winter Mode (October-March)
- id: enable_winter_mode
  alias: "Season: Enable Winter Lighting"
  description: "Activate winter lighting mode during dark months"

  trigger:
    - platform: time
      at: "00:00:01"  # Check daily

  condition:
    - condition: template
      value_template: >
        {% set month = now().month %}
        {{ month >= 10 or month <= 3 }}

  action:
    - service: input_boolean.turn_on
      target:
        entity_id: input_boolean.winter_mode
```

### Winter Daytime Brightness

```yaml
- id: winter_daytime_bright
  alias: "Winter: Bright Daytime Lighting"
  description: "Extra bright cool lighting during winter days"

  trigger:
    - platform: sun
      event: sunrise
      offset: "00:30:00"  # 30 min after sunrise

  condition:
    - condition: state
      entity_id: input_boolean.winter_mode
      state: "on"

  action:
    - service: light.turn_on
      target:
        entity_id: all
      data:
        brightness_pct: 100
        color_temp: 250  # Cool blue-white (low mired = cool)
        transition: 30  # Gradual 30-sec fade
```

### Sunset Compensation (Early Winter Sunset)

```yaml
- id: winter_sunset_compensation
  alias: "Winter: Compensate Early Sunset"
  description: "Maintain brightness after early winter sunset"

  trigger:
    - platform: sun
      event: sunset

  condition:
    - condition: state
      entity_id: input_boolean.winter_mode
      state: "on"
    # Only if someone is home
    - condition: state
      entity_id: binary_sensor.iphone_home
      state: "on"

  action:
    # Instead of dimming, maintain moderate brightness
    - service: light.turn_on
      target:
        entity_id: all
      data:
        brightness_pct: 70
        color_temp: 350  # Neutral warm
        transition: 60
```

**💡 Key Learning:**
- **Template conditions** allow complex logic (date ranges, calculations)
- **Input helpers** create toggles/sliders/dropdowns for control
- **Sun integration** provides sunrise/sunset times (automatically adjusted for location)
- Seasonal automations adapt to Norwegian climate needs

---

## Exercise 1.7: Hue Remote Integration

**Time:** 20 minutes
**Concepts:** Zigbee events, device triggers, button mapping

### Goal: Enhance Hue Remote with Custom Actions

Your Hue remote already controls lights via Hue Bridge. We can add **additional actions** in Home Assistant while keeping native control working.

### Discover Remote Events

1. **Open Developer Tools → Events**
2. **Listen to:** `hue_event`
3. **Press buttons on Hue remote**
4. **Note event data** (example):

```yaml
event_type: hue_event
data:
  id: hue_remote_living_room
  device_id: abc123def456
  type: short_release
  subtype: button_1  # On button
```

### Automation: On Button = Welcome Scene

```yaml
- id: hue_remote_on_button
  alias: "Hue Remote: On Button Custom Action"
  description: "On button triggers welcome scene instead of default"

  trigger:
    - platform: event
      event_type: hue_event
      event_data:
        id: hue_remote_living_room  # Your remote's ID
        type: short_release
        subtype: button_1  # On button

  action:
    - service: scene.turn_on
      target:
        entity_id: scene.energize
```

### Automation: Dim Down Button = All Lights Off

```yaml
- id: hue_remote_off_button_all
  alias: "Hue Remote: Off Button = All Lights Off"
  description: "Extend off button to turn off all lights in home"

  trigger:
    - platform: event
      event_type: hue_event
      event_data:
        id: hue_remote_living_room
        type: short_release
        subtype: button_4  # Off button

  action:
    - service: light.turn_off
      target:
        entity_id: all
```

**💡 Key Learning:**
- **Device events** capture button presses, motion sensors, etc.
- Hue remote retains native bridge control (instant, reliable)
- HA automations **extend** remote capabilities without replacing them
- Same physical button can trigger both bridge (lights) and HA (scenes/automations)

---

## Phase 1 Completion: Checkpoint & Dashboard

**Time:** 30 minutes
**Goal:** Consolidate learning, build first dashboard

### What You've Learned

- ✅ Hue Bridge + HA architecture (keep both)
- ✅ Entity states and attributes
- ✅ Services and service calls
- ✅ Scene management (create in Hue app, use in HA)
- ✅ Automations: triggers, conditions, actions
- ✅ Time-based automation (circadian rhythm)
- ✅ Presence-based automation (WiFi detection)
- ✅ Seasonal adaptation (Norwegian winter mode)
- ✅ Device events (Hue remote custom actions)

### Build Your First Dashboard

Create a "Lighting Control" dashboard:

1. **Settings → Dashboards → Add Dashboard**
   - Name: "Lighting"
   - Icon: `mdi:lightbulb-group`

2. **Add cards:**

   **Card 1: Scene Buttons**
   ```yaml
   type: horizontal-stack
   cards:
     - type: button
       name: Energize
       icon: mdi:weather-sunny
       tap_action:
         action: call-service
         service: scene.turn_on
         target:
           entity_id: scene.energize

     - type: button
       name: Relax
       icon: mdi:weather-night
       tap_action:
         action: call-service
         service: scene.turn_on
         target:
           entity_id: scene.relax

     - type: button
       name: Focus
       icon: mdi:desk-lamp
       tap_action:
         action: call-service
         service: scene.turn_on
         target:
           entity_id: scene.focus
   ```

   **Card 2: Light Group Control**
   ```yaml
   type: light
   entity: light.all_hue_lights  # If you created a group
   name: All Lights
   ```

   **Card 3: Individual Light Cards** (repeat for each bulb)
   ```yaml
   type: light
   entity: light.living_room_ceiling
   name: Living Room
   ```

   **Card 4: Winter Mode Toggle**
   ```yaml
   type: entities
   entities:
     - entity: input_boolean.winter_mode
       name: "Winter Lighting Mode"
       icon: mdi:snowflake
   ```

3. **Test on iPad:**
   - Open Home Assistant app on iPad (https://ha.patriark.org)
   - Navigate to Lighting dashboard
   - Test scene buttons, light controls, winter mode toggle

**✅ Phase 1 Complete!**

You now have:
- Fully functional Hue integration
- Time-based and presence-based automations
- Seasonal lighting adaptation
- Beautiful lighting dashboard on iPad
- Hue remote enhanced with custom actions

**Next:** Phase 2 - Dashboard Design Fundamentals

---

# Phase 2: Dashboard Design Fundamentals

**Duration:** Week 2
**Difficulty:** Beginner-Intermediate
**Goal:** Master dashboard design principles, create beautiful and functional interfaces for iPad

---

## Dashboard Philosophy: Context-Driven Design

**Key principle:** Different contexts need different interfaces

- **Morning Dashboard:** Weather, calendar, quick climate/light controls
- **Evening Dashboard:** Lighting scenes, relaxation controls, media status
- **Away Dashboard:** Security monitoring, energy usage, system health
- **Full Control Dashboard:** Everything (for configuration/troubleshooting)

---

## Exercise 2.1: Understanding Card Types

**Time:** 30 minutes
**Concepts:** Card types, layouts, YAML vs UI editor

### Common Card Types

1. **Button Card** - Single action buttons (scenes, scripts)
2. **Light Card** - Bulb control with brightness/color picker
3. **Entities Card** - List of entities (sensors, switches)
4. **Gauge Card** - Visual indicators (temperature, battery)
5. **Graph Card** - Historical data (sensor history)
6. **Picture Elements Card** - Interactive floorplan
7. **Markdown Card** - Text, headers, instructions
8. **Conditional Card** - Show/hide based on state

### Hands-On: Create a Multi-Card Layout

**Goal:** Build a "Home Status" dashboard with different card types

**Steps:**
1. Settings → Dashboards → Add Dashboard → "Home Status"
2. Edit Dashboard → Add Card → Button
3. Try each card type listed above
4. Experiment with UI editor vs YAML editor (top-right toggle)

**Example Layout:**

```yaml
# Dashboard YAML (Edit Dashboard → Three Dots → Raw Configuration Editor)
views:
  - title: Home Status
    path: home-status
    icon: mdi:home
    cards:
      # Row 1: Scene Buttons
      - type: horizontal-stack
        cards:
          - type: button
            entity: scene.energize
            name: Energize
            icon: mdi:weather-sunny
            tap_action:
              action: call-service
              service: scene.turn_on
              target:
                entity_id: scene.energize

          - type: button
            entity: scene.relax
            name: Relax
            icon: mdi:weather-night

          - type: button
            entity: scene.focus
            name: Focus
            icon: mdi:desk-lamp

      # Row 2: Presence & Climate
      - type: horizontal-stack
        cards:
          - type: entity
            entity: binary_sensor.iphone_home
            name: Presence
            icon: mdi:home-account

          - type: gauge
            entity: sensor.mill_sense_temperature  # Your Mill Sense sensor
            name: Living Room
            min: 15
            max: 30
            severity:
              green: 20
              yellow: 18
              red: 16

      # Row 3: Light Controls
      - type: entities
        title: Lighting
        entities:
          - entity: light.living_room_ceiling
          - entity: light.bedroom_1
          - entity: input_boolean.winter_mode
```

**💡 Key Learning:**
- **horizontal-stack** creates row layouts
- **vertical-stack** creates column layouts
- **Card types** have different use cases (action vs display vs control)
- YAML gives more control than UI editor

---

## Exercise 2.2: Conditional Cards - Context-Aware UI

**Time:** 30 minutes
**Concepts:** Conditional visibility, state-based UI changes

### Goal: Show Different Cards Based on Presence

**Use case:** Show security status when away, show comfort controls when home

```yaml
# Card: Show security panel only when away
- type: conditional
  conditions:
    - entity: binary_sensor.iphone_home
      state: "off"
  card:
    type: entities
    title: "🔒 Security Status (Away Mode)"
    entities:
      - entity: light.all_hue_lights
        name: "All Lights"
      - entity: binary_sensor.iphone_home
        name: "Presence"

# Card: Show comfort controls only when home
- type: conditional
  conditions:
    - entity: binary_sensor.iphone_home
      state: "on"
  card:
    type: entities
    title: "🏠 Comfort Controls (Home Mode)"
    entities:
      - entity: light.living_room_ceiling
      - entity: sensor.mill_sense_temperature
      - entity: climate.mill_compact_pro  # If integrated
```

### Enhancement: Time-Based Conditional

```yaml
# Show morning routine card only 06:00-09:00
- type: conditional
  conditions:
    - condition: template
      value_template: >
        {% set hour = now().hour %}
        {{ hour >= 6 and hour < 9 }}
  card:
    type: markdown
    content: |
      ## ☀️ Good Morning!

      Quick actions:
      - Lights set to Energize mode
      - Check today's weather
      - Review calendar
```

**💡 Key Learning:**
- Conditional cards show/hide based on state
- Template conditions enable complex logic (time, calculations)
- Context-aware UI reduces clutter

---

## Exercise 2.3: Building an iPad-Optimized Layout

**Time:** 45 minutes
**Concepts:** Responsive design, iPad screen dimensions, touch targets

### iPad Design Principles

1. **Larger touch targets** (minimum 44x44 points)
2. **Landscape orientation** (iPad typically used landscape)
3. **Grid layouts** (3-4 columns on iPad)
4. **Visual hierarchy** (most important controls on top)
5. **Whitespace** (don't cram too much)

### Hands-On: Create iPad-Optimized Dashboard

**Goal:** "Morning Routine" dashboard designed for iPad

```yaml
views:
  - title: Morning Routine
    path: morning
    icon: mdi:weather-sunset-up
    cards:
      # Header with time & weather
      - type: vertical-stack
        cards:
          - type: markdown
            content: |
              # Good Morning! ☀️
              {{ now().strftime('%A, %B %d') }}

          # Will add weather card in Phase 5

      # Large scene buttons (easy to tap)
      - type: grid
        columns: 3
        square: false
        cards:
          - type: button
            entity: scene.energize
            name: Energize
            icon: mdi:weather-sunny
            icon_height: 80px
            tap_action:
              action: call-service
              service: scene.turn_on
              target:
                entity_id: scene.energize

          - type: button
            entity: scene.focus
            name: Focus
            icon: mdi:desk-lamp
            icon_height: 80px

          - type: button
            entity: scene.relax
            name: Relax
            icon: mdi:sofa
            icon_height: 80px

      # Climate overview (horizontal cards)
      - type: horizontal-stack
        cards:
          - type: gauge
            entity: sensor.mill_sense_temperature
            name: Living Room
            min: 15
            max: 30

          - type: gauge
            entity: sensor.bedroom_temperature  # If available
            name: Bedroom
            min: 15
            max: 30

      # Quick actions (entities list)
      - type: entities
        title: Quick Controls
        entities:
          - entity: light.all_hue_lights
            name: All Lights
          - entity: input_boolean.winter_mode
            name: Winter Mode
```

### Test on iPad

1. Open HA app on iPad
2. Navigate to Morning Routine dashboard
3. Test touch targets (buttons should be easy to tap)
4. Rotate iPad (landscape vs portrait)
5. Adjust layouts if needed

**💡 Key Learning:**
- **Grid layout** (`type: grid`) creates responsive columns
- **icon_height** makes buttons larger and easier to tap
- **horizontal-stack** groups related controls
- Design for landscape iPad orientation

---

## Exercise 2.4: Custom Button Card (HACS)

**Time:** 30 minutes (if HACS installed)
**Concepts:** Custom integrations, advanced button styling

### Optional: Install HACS + Custom Button Card

**HACS (Home Assistant Community Store)** provides custom cards and integrations.

**Installation:**
1. SSH into fedora-htpc (or use Bash tool)
2. Enter HA container:
   ```bash
   podman exec -it home-assistant /bin/bash
   ```
3. Install HACS:
   ```bash
   wget -O - https://get.hacs.xyz | bash -
   ```
4. Restart HA
5. Settings → Devices & Services → Add Integration → HACS
6. Follow GitHub authentication flow

**Install Custom Button Card:**
1. HACS → Frontend → Explore & Download Repositories
2. Search "button-card"
3. Install "custom:button-card"
4. Restart HA

### Enhanced Button Examples

```yaml
# Beautiful scene button with gradient background
type: custom:button-card
entity: scene.energize
name: Energize
icon: mdi:weather-sunny
styles:
  card:
    - background: linear-gradient(135deg, #667eea 0%, #764ba2 100%)
    - color: white
  icon:
    - width: 60px
    - height: 60px
  name:
    - font-size: 18px
    - font-weight: bold
tap_action:
  action: call-service
  service: scene.turn_on
  target:
    entity_id: scene.energize
```

**💡 Key Learning:**
- HACS extends HA with community integrations
- Custom cards provide advanced styling and features
- Button-card enables gradients, templates, animations

*(Skip this exercise if you prefer to keep HA simple without custom components)*

---

## Phase 2 Completion: Dashboard Portfolio

**Goal:** Have 3 polished dashboards ready

### Dashboard 1: Morning Routine ✅
- Scene buttons (Energize, Focus)
- Climate overview
- Quick controls

### Dashboard 2: Evening Relaxation
- Relax/Movie scenes
- Dimming controls
- Status indicators

### Dashboard 3: Full Control
- All lights (individual control)
- All automations (enable/disable toggles)
- System status (HA server, Hue Bridge)

**Test on iPad:**
- Open each dashboard
- Verify touch targets are comfortable
- Check visual hierarchy (most important on top)
- Test in both orientations

**✅ Phase 2 Complete!**

**Next:** Phase 3 - Mill Climate Control

---

# Phase 3: Air Quality & Climate Monitoring (Mill Devices)

**Duration:** Week 3
**Difficulty:** Intermediate
**Devices:** Mill Sense Air, Mill Compact Pro (air purifier), Mill Silent Pro (air purifier)
**Goal:** Integrate air quality monitoring, understand Norwegian climate patterns

**Status:** ✅ **DETAILED GUIDE AVAILABLE**

**📖 Full Guide:** [Phase 3: Air Quality & Climate Monitoring](./home-assistant-phase3-air-quality.md)

**Highlights:**
- Mill Sense Air integration (temperature, humidity, CO2, TVOC)
- Air quality dashboard with Norwegian standards
- Air quality awareness automations (high CO2/TVOC alerts)
- Climate comfort score (0-100 rating)
- Winter-specific humidity monitoring
- ⚠️ Note: No official integration for Mill air purifiers (Silent Pro, Compact Pro)

**What You'll Learn:**
- Numeric state triggers (threshold-based automation)
- Template sensors (calculated values)
- Gauge cards with severity zones
- Historical trend graphing
- Norwegian air quality standards (FHI recommendations)

---

# Phase 4: Roborock Intelligence + iOS Focus Mode Integration

**Duration:** Week 3-4
**Difficulty:** Intermediate-Advanced
**Devices:** Roborock Saros 10, iPhone/iPad, Apple Watch
**Goal:** Master robot vacuum automation + leverage Apple Focus Modes for context-aware automation

**Status:** ✅ **DETAILED GUIDE AVAILABLE**

**📖 Full Guide:** [Phase 4: Roborock + iOS Focus Modes](./home-assistant-phase4-roborock-focus.md)

**Part A: Roborock Integration**
- Connect Roborock Saros 10 via official integration
- Vacuum control services (start, pause, fan speed, room selection)
- Presence-based cleaning (auto-start when away)
- Actionable notifications (resume/dock from lock screen)
- ⚠️ Known issues with Saros 10 local API (workarounds provided)

**Part B: iOS Focus Mode Integration** 🔥 **GAME CHANGER**
- Detect iOS Focus Modes via webhooks (Personal, Work, Sleep, DND, custom)
- Control from **Apple Watch** (instant context changes)
- iOS Shortcuts + HA webhook setup
- Focus mode dashboard

**Part C: Context-Aware Automation Matrix**
- Work Focus + Home = Productivity mode (focus lighting, pause vacuum)
- Sleep Focus = Complete quiet mode (dim lights, dock vacuum)
- "Leaving Home" custom focus = Departure routine (lights off, start vacuum)
- DND/Movie Focus = Entertainment mode (dim lighting, silence distractions)

**Part D: Multi-Device Choreography**
- Conflict prevention (skip vacuum during work focus)
- Morning arrival routines
- Focus Mode + Presence matrix (2D automation logic)

**What You'll Learn:**
- Webhook triggers (external service integration)
- iOS Shortcuts (no-code iOS automation)
- Apple ecosystem leverage (Watch → iPhone → HA)
- Multi-condition logic (AND/OR automation conditions)
- Actionable notifications
- State tracking (input_select helpers)
- Context matrix design

---

# Phase 5: Homelab Integration Showcase

**Duration:** Week 4-5
**Difficulty:** Advanced
**Goal:** Leverage your elite monitoring infrastructure - capabilities most HA users can't replicate

**Status:** 🚧 Detailed exercises coming soon

**Preview:**
- **Security-Aware Automation:** CrowdSec attack → trigger "Security Alert" scene (all lights red)
- **Energy Intelligence:** Prometheus metrics → HA sensors → unified energy dashboard
- **Network-Aware Features:** UDM Pro via Unpoller → room-level presence (multiple APs)
- **Loki Integration:** HA logs → Loki → correlate automations with system events
- **Alertmanager Bidirectional:** HA webhook → Alertmanager (alert on HA failures)

**Example Integrations:**

1. **CrowdSec → HA:**
   ```yaml
   # Trigger when CrowdSec bans increase suddenly
   - alias: "Security: CrowdSec Attack Detected"
     trigger:
       - platform: webhook
         webhook_id: crowdsec_ban_alert
     action:
       - service: light.turn_on
         target:
           entity_id: all
         data:
           rgb_color: [255, 0, 0]  # Red
           brightness_pct: 100
       - service: notify.mobile_app_iphone
         data:
           title: "🚨 Security Alert"
           message: "CrowdSec detected attack - {{ trigger.json.ban_count }} IPs banned"
   ```

2. **Prometheus → HA Energy Dashboard:**
   ```yaml
   # RESTful sensor: Query Prometheus for Mill heater power usage
   sensor:
     - platform: rest
       name: Mill Heater Power Consumption
       resource: http://prometheus:9090/api/v1/query?query=mill_heater_power_watts
       value_template: "{{ value_json.data.result[0].value[1] }}"
       unit_of_measurement: "W"
   ```

---

# Phase 6: iPad Command Center

**Duration:** Week 5-6
**Difficulty:** Intermediate
**Goal:** Transform iPad into world-class home control interface

**Status:** 🚧 Detailed exercises coming soon

**Preview:**
- iOS Shortcuts integration ("Hey Siri, I'm leaving home")
- Home screen widgets (temperature, presence, energy)
- Rich notifications with actions
- Secure remote access (WireGuard → Authelia → HA)
- Context-driven dashboard switching (auto-show morning dashboard at 7am)

---

# Phase 7: Calendar-Driven Automation + Matter Smart Plugs

**Duration:** Future (when ready to expand)
**Difficulty:** Intermediate
**Status:** ✅ **REFERENCE GUIDE AVAILABLE**

**📖 Full Guide:** [Phase 7: Calendar & Matter Plugs](./home-assistant-phase7-calendar-matter-plugs.md)

**Part A: Nextcloud Calendar Integration (Deploy Anytime)**
- CalDAV integration with your existing Nextcloud
- Calendar event triggers ("Deep Clean" → start vacuum)
- Scheduled automations ("Guest Arriving" → welcome scene)
- Calendar dashboard
- ✅ **No hardware required** - ready when you want scheduled automation

**Part B: Matter Smart Plugs (Future - Hardware Purchase Required)**
- Eve Energy (Matter) recommended: 2500W, EU plug, energy monitoring
- Control old Gen 1 Mill panel heaters via smart plugs
- Temperature-based heater control
- Energy monitoring dashboard
- ⚠️ **Safety warnings** for heater use (2000W+ continuous load)
- 🛒 **Cost:** ~1200-1600 NOK for 4 plugs
- **When to deploy:** Heating season (Sep-Oct 2026), after budget allocation

**CalDAV vs iOS Focus Mode:**
- **Calendar:** Time-based, scheduled events (plan ahead)
- **Focus Mode:** User-initiated, instant context changes (Apple Watch)
- **Best:** Use both together (calendar schedules focus mode activation)

---

## Recommended Matter Smart Plugs for Norwegian Market (2026)

Based on research, here are the top recommendations for controlling your panel heaters:

### Option 1: Eve Energy (Matter) - **RECOMMENDED** ⭐

**Specs:**
- **Power rating:** 2500W / 11A (supports 2000W heaters) ([source](https://matterdevices.net/devices/eve-energy-smart-plug-eu))
- **Protocol:** Matter over Thread (requires Thread border router - your Matter Server)
- **EU plug:** Type E & F (Schuko) compatible
- **Energy monitoring:** Yes (voltage, current, power, total energy)
- **Price:** ~300-400 NOK (2-pack available)

**Pros:**
- ✅ German company (Eve Systems GmbH) - EU manufactured
- ✅ Excellent reputation, Apple HomeKit heritage
- ✅ Sufficient power rating for heaters (2500W)
- ✅ Thread mesh networking (extends network range)
- ✅ Energy monitoring built-in
- ✅ Matter certified (works with HA Matter Server)

**Cons:**
- ❌ Premium price
- ❌ Requires Thread border router (you already have via Matter Server)

**Availability:** Available from [avXperten.no](https://www.avxperten.no/enheder-til-matter-smart-home/), international shipping via Amazon ([source](https://www.amazon.com/Eve-Energy-Matter-Control-SmartThings/dp/B0BZBGD87V))

---

### Option 2: Meross MSS315MA (Matter) - **BUDGET OPTION**

**Specs:**
- **Power rating:** ~2300W (verify before purchase)
- **Protocol:** Matter over WiFi
- **EU plug:** Type E & F
- **Energy monitoring:** Yes
- **Price:** 205 NOK at avXperten.no ([source](https://www.avxperten.no/enheder-til-matter-smart-home/))

**Pros:**
- ✅ Very affordable (205 NOK)
- ✅ Available in Norway (avXperten.no)
- ✅ Matter certified
- ✅ WiFi (no Thread border router needed)
- ✅ Energy monitoring

**Cons:**
- ❌ Chinese company (less EU preference)
- ❌ Lower power rating (verify heater compatibility)
- ❌ WiFi only (no Thread mesh benefits)

---

### Option 3: LEDVANCE SMART+ MATTER Plug

**Specs:**
- **Power rating:** TBD (check specifications)
- **Protocol:** Matter over WiFi
- **EU plug:** Yes
- **Price:** TBD

**Pros:**
- ✅ Available at LEDVANCE.no ([source](https://www.ledvance.no/forbruker/produkter/smart-hjem/smart-komponenter/smart-matter/smart-matter/plug-with-smart-socket-to-control-non-smart-devices-with-matter-over-wifi-technology-c317769))
- ✅ German company (Osram spinoff)
- ✅ EU manufactured

**Cons:**
- ❌ Limited information available
- ❌ Need to verify power rating for heater use

---

### ⚠️ CRITICAL SAFETY WARNINGS

**Before using smart plugs with heaters:**

1. **Power rating verification:**
   - Mill Compact Pro: ~2000W (verify exact model)
   - Mill Silent Pro: ~2000W (verify exact model)
   - Smart plug MUST support ≥2000W continuous load
   - Check plug amperage: 2000W ÷ 230V = 8.7A (need ≥10A rated plug)

2. **Heater compatibility:**
   - ⚠️ **NOT suitable** for space heaters, high-draw appliances unless explicitly rated
   - ⚠️ Supervised load tests recommended ([source](https://strongmocha.com/vetted/best-matter-smart-plugs/))
   - ⚠️ Fire hazard if plug overheats under continuous load

3. **Installation:**
   - Use direct wall outlet (no extension cords)
   - Ensure good ventilation around plug
   - Monitor plug temperature during first few uses
   - Never exceed rated power

4. **Norwegian electrical standards:**
   - Verify plug meets NEK 400 (Norwegian electrical code)
   - Type F (Schuko) plugs common in Norway

---

## When Ready to Deploy (Future Phase)

**Prerequisites:**
- ✅ Matter Server deployed (done in Week 2)
- ✅ Thread border router tested (Matter Server provides)
- ⏳ Matter smart plugs purchased
- ⏳ Heater power consumption verified

**Deployment steps:**
1. Commission plug via HA Matter integration
2. Verify power monitoring works
3. Test manual on/off control
4. Create temperature-based automation (Mill Sense → smart plug)
5. Add to energy monitoring dashboard

**Safety validation:**
- Monitor plug temperature after 1 hour continuous use
- Verify heater cycles on/off correctly
- Check energy consumption matches heater specs

---

## Appendices

### Appendix A: Home Assistant Key Concepts Reference

**Entities:**
- Fundamental building block (lights, sensors, switches)
- Have **state** (on/off, temperature value) and **attributes** (brightness, color)
- Unique `entity_id` (e.g., `light.living_room_ceiling`)

**Domains:**
- Entity type prefix (light, sensor, switch, binary_sensor, climate, etc.)
- Each domain has specific services (light.turn_on, switch.toggle)

**Services:**
- Actions you can call (turn_on, turn_off, set_temperature)
- Take **entity targets** and optional **data** parameters

**Automations:**
- **Triggers:** Start the automation (time, state change, event)
- **Conditions:** Gate execution (only run if true)
- **Actions:** What happens (service calls, notifications)

**Scenes:**
- Snapshot of entity states (lights on/off, brightness, colors)
- Activated with `scene.turn_on` service

**Dashboards:**
- UI layouts composed of **cards**
- Cards display or control entities
- Can be edited via UI or YAML

---

### Appendix B: Recommended Learning Resources

**Official Documentation:**
- [Home Assistant Docs](https://www.home-assistant.io/docs/) - Complete reference
- [Philips Hue Integration](https://www.home-assistant.io/integrations/hue/) - Official Hue docs
- [Automation Basics](https://www.home-assistant.io/docs/automation/basics/) - Automation guide

**Community Resources:**
- [Home Assistant Community Forum](https://community.home-assistant.io/) - Support forum
- [r/homeassistant](https://www.reddit.com/r/homeassistant/) - Reddit community
- [YouTube: Smart Home Junkie](https://www.youtube.com/@SmartHomeJunkie) - Video tutorials
- [YouTube: Everything Smart Home](https://www.youtube.com/@EverythingSmartHome) - Reviews and guides

**Norwegian Resources:**
- Search "Home Assistant Norge" for Norwegian Facebook groups/forums
- Norwegian smart home retailers: avXperten.no, Proshop.no, Elkjøp.no

---

### Appendix C: Troubleshooting Common Issues

**Issue: Hue Bridge not discovered**
- Verify bridge on same network as fedora-htpc (192.168.1.0/24)
- Check UDM Pro firewall allows mDNS discovery
- Manual IP entry: Check UDM Pro DHCP leases for bridge IP

**Issue: Scenes not imported**
- Restart Home Assistant after creating scenes in Hue app
- Check Settings → Integrations → Hue → Reload

**Issue: Automations not triggering**
- Check automation history (Settings → Automations → Click automation)
- Verify conditions are met (sun position, presence, time)
- Enable automation (toggle at top of automation page)

**Issue: Dashboard not loading on iPad**
- Clear HA app cache (iOS Settings → Home Assistant → Clear Cache)
- Verify https://ha.patriark.org accessible (Authelia auth required)
- Check Traefik logs: `podman logs traefik | grep ha.patriark.org`

**Issue: Presence sensor always "off"**
- Verify Unpoller collecting metrics: `podman logs unpoller`
- Check Prometheus query: `unpoller_client_uptime_seconds{name="iPhone"}`
- Adjust client_name in configuration.yaml to match UDM Pro device name

---

### Appendix D: Norwegian Climate Context

**Winter (October-March):**
- **Sunrise:** 9:00-10:00 (late)
- **Sunset:** 15:00-16:00 (early)
- **Daylight:** 6-7 hours
- **Lighting strategy:** Bright, cool lighting during day (combat SAD)

**Summer (April-September):**
- **Sunrise:** 04:00-05:00 (early)
- **Sunset:** 21:00-23:00 (late)
- **Daylight:** 16-19 hours
- **Lighting strategy:** Minimal artificial light, warm tones in evening

**Energy Considerations:**
- Norwegian electricity: Nordpool spot pricing (varies hourly)
- Winter heating: Significant energy consumption (panel heaters)
- Opportunity: Heat during low-price hours (typically night)

---

## Next Steps After Learning Path Completion

Once you complete Phases 1-6, consider these advanced topics:

1. **Node-RED** - Visual automation builder (alternative to YAML automations)
2. **AppDaemon** - Python-based automation engine (for complex logic)
3. **Voice control** - Wyoming stack (Whisper + Piper) for local voice assistant
4. **Zigbee/Z-Wave** - Expand beyond Matter (Zigbee sensors, Z-Wave switches)
5. **ESPHome** - Custom ESP32 sensors (DIY projects)
6. **Frigate** - NVR/object detection (if adding cameras)

---

**Document Status:** Living guide - will be updated as you progress through phases

**Last Updated:** 2026-01-28
**Author:** Claude (with patriark's homelab context)
**License:** Use freely for personal homelab learning
