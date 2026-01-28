# Phase 4: Roborock Intelligence + iOS Focus Mode Integration

**Parent Guide:** [Home Assistant Learning Path](./home-assistant-learning-path.md)
**Duration:** Week 3-4
**Difficulty:** Intermediate-Advanced
**Devices:** Roborock Saros 10, iPhone/iPad, Apple Watch
**Goal:** Master robot vacuum automation + leverage Apple Focus Modes for context-aware smart home

**Key Innovation:** Combine iOS Focus Modes (controlled from Apple Watch) with presence detection for intelligent home automation

---

## Table of Contents

- [Part A: Roborock Saros 10 Integration](#part-a-roborock-saros-10-integration)
- [Part B: iOS Focus Mode Integration](#part-b-ios-focus-mode-integration)
- [Part C: Focus Mode + Presence Automation Matrix](#part-c-focus-mode--presence-automation-matrix)
- [Part D: Advanced Choreography](#part-d-advanced-choreography)

---

# Part A: Roborock Saros 10 Integration

**Duration:** 1-2 hours (including setup troubleshooting)
**Concepts:** Cloud authentication, local API, vacuum entities, cleaning modes

---

## Exercise 4A.1: Connect Roborock to Home Assistant

**Time:** 30 minutes
**Goal:** Integrate Roborock Saros 10 using official integration

### Prerequisites

- Roborock Saros 10 connected to WiFi (same VLAN as iPhone: 192.168.2.0/24)
- Roborock app installed on iPhone (device configured)
- Email access (verification code sent during setup)

### Integration Setup

1. **Add Roborock Integration**
   - Settings → Devices & Services → Add Integration
   - Search "Roborock"
   - Select official "Roborock" integration ([source](https://www.home-assistant.io/integrations/roborock/))

2. **Enter Roborock Account Credentials**
   - Email address (same as Roborock app)
   - Password
   - Click Submit

3. **Email Verification**
   - Check email for 6-digit verification code
   - Enter code in HA setup dialog
   - Timeout: ~5 minutes (check spam folder if not received)

4. **Device Discovery**
   - Integration will discover Roborock Saros 10 via cloud API
   - Automatically attempts local API connection (preferred)
   - Local communication: Port 58867 ([source](https://pimylifeup.com/home-assistant-roborock/))

### Expected Result

**Entities created (examples):**
```yaml
vacuum.roborock_saros_10            # Main vacuum entity
sensor.roborock_battery             # Battery percentage
sensor.roborock_last_clean_area     # Area cleaned (m²)
sensor.roborock_last_clean_duration # Cleaning duration (min)
sensor.roborock_filter_left         # Filter life remaining (%)
sensor.roborock_main_brush_left     # Main brush life (%)
sensor.roborock_side_brush_left     # Side brush life (%)
sensor.roborock_sensor_dirty_left   # Sensor cleaning needed (%)
binary_sensor.roborock_mop_attached # Mop attachment status
binary_sensor.roborock_water_box    # Water box attached
```

---

### ⚠️ Known Issues with Saros 10/10R

**Issue: Local API Connection Fails**
- **Symptom:** Logs show "Using the cloud API for device" ([source](https://github.com/home-assistant/core/issues/152159))
- **Impact:** Slower response times, potential rate limiting
- **Workaround:**
  1. Set static IP for Roborock in UDM Pro DHCP settings
  2. Verify HA can reach 192.168.2.x (Roborock IP) on port 58867
  3. Check UDM Pro firewall rules (allow VLAN1 → VLAN2 traffic)

**Issue: Setup Failure - "No devices were able to successfully setup"**
- **Symptom:** Integration fails during device discovery ([source](https://github.com/home-assistant/core/issues/151273))
- **Solution:**
  1. Remove integration (Settings → Devices & Services → Roborock → Delete)
  2. Restart Home Assistant
  3. Re-add integration with fresh email verification code
  4. If persistent: Check Roborock app firmware (update if available)

**Issue: Mop Intensity Resets to OFF**
- **Known bug** with Saros 10R ([source](https://github.com/home-assistant/core/issues/148755))
- Workaround: Set mop intensity via Roborock app before starting clean

---

### Verification Steps

1. **Check vacuum entity state**
   ```bash
   # Developer Tools → States
   # Search: vacuum.roborock_saros_10
   # State should be: docked, cleaning, returning, etc.
   ```

2. **Test basic control**
   - Developer Tools → Services
   - Service: `vacuum.start`
   - Target: `vacuum.roborock_saros_10`
   - Call Service → Roborock should start cleaning

3. **Verify local API** (preferred)
   ```bash
   # Check HA logs
   Settings → System → Logs
   # Search: roborock
   # Look for: "Using local API for device" (GOOD)
   # Avoid: "Using cloud API for device" (SLOWER)
   ```

4. **Test return to dock**
   - Service: `vacuum.return_to_base`
   - Roborock should navigate back to dock

**✅ Success Criteria:**
- Vacuum entity exists and shows current state
- Battery sensor updates (matches Roborock app)
- Start/stop/return commands work
- Local API preferred (check logs)

---

## Exercise 4A.2: Understanding Vacuum Services & Modes

**Time:** 20 minutes
**Goal:** Master Roborock control services

### Available Services

**Basic Control:**
```yaml
# Start cleaning (whole home)
service: vacuum.start
target:
  entity_id: vacuum.roborock_saros_10

# Pause cleaning
service: vacuum.pause
target:
  entity_id: vacuum.roborock_saros_10

# Stop cleaning (cancel current job)
service: vacuum.stop
target:
  entity_id: vacuum.roborock_saros_10

# Return to dock
service: vacuum.return_to_base
target:
  entity_id: vacuum.roborock_saros_10
```

**Advanced Control:**
```yaml
# Set fan speed (suction power)
service: vacuum.set_fan_speed
target:
  entity_id: vacuum.roborock_saros_10
data:
  fan_speed: "balanced"  # Options: off, quiet, balanced, turbo, max

# Clean specific room(s)
service: vacuum.send_command
target:
  entity_id: vacuum.roborock_saros_10
data:
  command: "app_segment_clean"
  params:
    - segments: [1, 3]  # Room IDs from Roborock app

# Spot cleaning (small area)
service: vacuum.clean_spot
target:
  entity_id: vacuum.roborock_saros_10

# Locate vacuum (beep)
service: vacuum.locate
target:
  entity_id: vacuum.roborock_saros_10
```

### Cleaning Modes

**Fan Speed (Suction Power):**
- `quiet`: Low suction, quietest operation
- `balanced`: Normal cleaning (default)
- `turbo`: High suction for carpets
- `max`: Maximum power (highest noise)
- `off`: Mop-only mode (no vacuum)

**Cleaning Patterns:**
- **Whole Home:** `vacuum.start` (cleans entire map)
- **Room-Specific:** `app_segment_clean` with room IDs
- **Zone Cleaning:** Define rectangular zones (X/Y coordinates)
- **Spot Cleaning:** 1.5m x 1.5m area around current position

### Hands-On: Test Each Service

1. **Start whole home clean**
   - Use `vacuum.start` service
   - Observe vacuum leave dock and start cleaning

2. **Pause mid-cleaning**
   - While cleaning, call `vacuum.pause`
   - Vacuum stops in place

3. **Resume cleaning**
   - Call `vacuum.start` again
   - Vacuum continues from where it stopped

4. **Change fan speed during cleaning**
   - Call `vacuum.set_fan_speed` with `fan_speed: turbo`
   - Listen to suction power increase

5. **Return to dock**
   - Call `vacuum.return_to_base`
   - Vacuum navigates back (may take several minutes)

**💡 Key Learning:**
- Vacuum state transitions: `docked` → `cleaning` → `returning` → `docked`
- Fan speed can be changed mid-cleaning
- Pause doesn't return to dock (vacuum waits in place)
- Stop cancels job; Start after pause resumes

---

## Exercise 4A.3: Presence-Based Vacuum Automation

**Time:** 30 minutes
**Goal:** Auto-start vacuum when leaving home, pause when returning

### Automation 1: Start Cleaning When Away

```yaml
- id: roborock_auto_clean_away
  alias: "Roborock: Auto Clean When Away"
  description: "Start vacuum 15 minutes after last person leaves home"

  trigger:
    - platform: state
      entity_id: binary_sensor.iphone_home
      from: "on"
      to: "off"
      for:
        minutes: 15  # Ensure actually left (not just WiFi glitch)

  condition:
    # Only during daytime (not at night)
    - condition: time
      after: "08:00:00"
      before: "20:00:00"

    # Only if vacuum is docked (not already cleaning)
    - condition: state
      entity_id: vacuum.roborock_saros_10
      state: "docked"

    # Only if battery >20% (avoid mid-clean return to dock)
    - condition: numeric_state
      entity_id: sensor.roborock_battery
      above: 20

  action:
    # Send notification (optional: disable later when confident)
    - service: notify.mobile_app_iphone
      data:
        title: "🤖 Roborock Starting"
        message: "Auto-cleaning started - you left home 15 minutes ago"

    # Start whole home cleaning
    - service: vacuum.start
      target:
        entity_id: vacuum.roborock_saros_10
      data:
        fan_speed: "balanced"
```

### Automation 2: Pause Cleaning When Arriving Home

```yaml
- id: roborock_pause_on_arrival
  alias: "Roborock: Pause When Arriving Home"
  description: "Pause vacuum when someone arrives home (reduce noise)"

  trigger:
    - platform: state
      entity_id: binary_sensor.iphone_home
      from: "off"
      to: "on"

  condition:
    # Only if vacuum is actively cleaning
    - condition: state
      entity_id: vacuum.roborock_saros_10
      state: "cleaning"

  action:
    # Pause cleaning
    - service: vacuum.pause
      target:
        entity_id: vacuum.roborock_saros_10

    # Notification with action buttons
    - service: notify.mobile_app_iphone
      data:
        title: "🤖 Roborock Paused"
        message: "Cleaning paused - you arrived home. Resume or send to dock?"
        data:
          actions:
            - action: "ROBOROCK_RESUME"
              title: "Resume Cleaning"
            - action: "ROBOROCK_DOCK"
              title: "Return to Dock"
```

### Automation 3: Handle Notification Actions

```yaml
- id: roborock_notification_resume
  alias: "Roborock: Resume via Notification"
  description: "Resume cleaning when tapping notification action"

  trigger:
    - platform: event
      event_type: mobile_app_notification_action
      event_data:
        action: "ROBOROCK_RESUME"

  action:
    - service: vacuum.start
      target:
        entity_id: vacuum.roborock_saros_10

- id: roborock_notification_dock
  alias: "Roborock: Dock via Notification"
  description: "Return to dock when tapping notification action"

  trigger:
    - platform: event
      event_type: mobile_app_notification_action
      event_data:
        action: "ROBOROCK_DOCK"

  action:
    - service: vacuum.return_to_base
      target:
        entity_id: vacuum.roborock_saros_10
```

**💡 Key Learning:**
- **For duration** prevents false triggers (WiFi disconnects)
- **Numeric state condition** checks battery level
- **State condition** ensures vacuum is docked before starting
- **Actionable notifications** allow quick control from lock screen

---

## Exercise 4A.4: Scheduled Cleaning (Traditional Approach)

**Time:** 15 minutes
**Goal:** Set up time-based cleaning schedule

### Daily Cleaning Schedule

```yaml
- id: roborock_daily_clean_weekday
  alias: "Roborock: Daily Clean (Weekdays)"
  description: "Clean at 10:00 on weekdays (when typically away)"

  trigger:
    - platform: time
      at: "10:00:00"

  condition:
    # Weekdays only
    - condition: time
      weekday:
        - mon
        - tue
        - wed
        - thu
        - fri

    # Only if not home (double-check presence)
    - condition: state
      entity_id: binary_sensor.iphone_home
      state: "off"

    # Only if docked
    - condition: state
      entity_id: vacuum.roborock_saros_10
      state: "docked"

  action:
    - service: vacuum.start
      target:
        entity_id: vacuum.roborock_saros_10
      data:
        fan_speed: "balanced"
```

### Weekend Deep Clean (Turbo Mode)

```yaml
- id: roborock_weekend_deep_clean
  alias: "Roborock: Weekend Deep Clean"
  description: "Thorough cleaning on Saturday mornings"

  trigger:
    - platform: time
      at: "09:00:00"

  condition:
    - condition: time
      weekday:
        - sat

  action:
    - service: vacuum.start
      target:
        entity_id: vacuum.roborock_saros_10
      data:
        fan_speed: "max"  # Maximum suction for deep clean
```

**💡 Key Learning:**
- Time-based schedules good for **predictable routines**
- Presence-based automations better for **flexible schedules**
- Combine both: Time trigger + Presence condition

---

# Part B: iOS Focus Mode Integration

**Duration:** 2-3 hours
**Concepts:** iOS Shortcuts, webhooks, REST API, focus mode detection

**Key Idea:** iOS Focus Modes (Personal, Work, Sleep, Do Not Disturb, custom modes) can trigger Home Assistant automations via webhooks. Control Focus Modes from Apple Watch → instant smart home changes.

---

## Understanding iOS Focus Modes

### What are Focus Modes?

Built-in iOS 15+ feature that filters notifications and customizes lock screen based on activity:

- **Personal** - Default mode, all notifications
- **Work** - Work apps only, silence personal notifications
- **Sleep** - Minimal notifications, sleep tracking
- **Do Not Disturb** - All notifications silenced
- **Driving** - Auto-enabled when driving (CarPlay)
- **Custom Modes** - Create your own (Reading, Exercise, Movie, etc.)

### How to Control Focus Modes

1. **iPhone/iPad:** Control Center → Focus icon → Select mode
2. **Apple Watch:** Control Center → Focus icon → Select mode ⭐
3. **Automation:** Time-based, location-based, app-based triggers

**Why Apple Watch is powerful:**
- Quick access from wrist (1-2 seconds)
- No need to pull out phone/iPad
- Perfect for "I'm leaving home" or "Movie time" triggers

---

## Exercise 4B.1: Set Up iOS Focus Mode Detection

**Time:** 45 minutes
**Goal:** Create webhooks that detect when Focus Modes activate/deactivate

### Method: iOS Shortcuts + Home Assistant Webhooks

**How it works:**
1. Create iOS Personal Automation (runs when Focus Mode changes)
2. Automation calls iOS Shortcut
3. Shortcut sends HTTP request to HA webhook
4. HA webhook triggers automation

### Step 1: Create HA Webhook Automations

Create separate automations for each Focus Mode you want to track:

```yaml
# ~/containers/config/home-assistant/automations.yaml

# Focus Mode: Personal (On)
- id: ios_focus_personal_on
  alias: "iOS Focus: Personal Mode Activated"
  description: "Triggered when iPhone enters Personal focus mode"

  trigger:
    - platform: webhook
      webhook_id: ios_focus_personal_on  # Unique ID

  action:
    # Set input_select helper (created later)
    - service: input_select.select_option
      target:
        entity_id: input_select.ios_focus_mode
      data:
        option: "Personal"

    # Optional: Notification for testing
    - service: notify.persistent_notification
      data:
        title: "Focus Mode Changed"
        message: "iPhone now in Personal mode"

# Focus Mode: Work (On)
- id: ios_focus_work_on
  alias: "iOS Focus: Work Mode Activated"

  trigger:
    - platform: webhook
      webhook_id: ios_focus_work_on

  action:
    - service: input_select.select_option
      target:
        entity_id: input_select.ios_focus_mode
      data:
        option: "Work"

# Focus Mode: Sleep (On)
- id: ios_focus_sleep_on
  alias: "iOS Focus: Sleep Mode Activated"

  trigger:
    - platform: webhook
      webhook_id: ios_focus_sleep_on

  action:
    - service: input_select.select_option
      target:
        entity_id: input_select.ios_focus_mode
      data:
        option: "Sleep"

# Focus Mode: Do Not Disturb (On)
- id: ios_focus_dnd_on
  alias: "iOS Focus: DND Activated"

  trigger:
    - platform: webhook
      webhook_id: ios_focus_dnd_on

  action:
    - service: input_select.select_option
      target:
        entity_id: input_select.ios_focus_mode
      data:
        option: "Do Not Disturb"

# Focus Mode: OFF (any focus disabled)
- id: ios_focus_off
  alias: "iOS Focus: All Modes Disabled"

  trigger:
    - platform: webhook
      webhook_id: ios_focus_off

  action:
    - service: input_select.select_option
      target:
        entity_id: input_select.ios_focus_mode
      data:
        option: "None"
```

### Step 2: Create Input Select Helper (Focus Mode Tracker)

```yaml
# ~/containers/config/home-assistant/configuration.yaml

input_select:
  ios_focus_mode:
    name: "iPhone Focus Mode"
    icon: mdi:cellphone-check
    options:
      - "None"
      - "Personal"
      - "Work"
      - "Sleep"
      - "Do Not Disturb"
      - "Driving"
      - "Custom"  # Add more as needed
    initial: "None"
```

**Restart Home Assistant** to load helper.

### Step 3: Get Webhook URLs

1. **Find your HA external URL:**
   - Use: `https://ha.patriark.org`
   - Local alternative: `http://192.168.1.70:8123` (only works on local network)

2. **Webhook URL format:**
   ```
   https://ha.patriark.org/api/webhook/WEBHOOK_ID
   ```

   **Examples:**
   - Personal On: `https://ha.patriark.org/api/webhook/ios_focus_personal_on`
   - Work On: `https://ha.patriark.org/api/webhook/ios_focus_work_on`
   - Sleep On: `https://ha.patriark.org/api/webhook/ios_focus_sleep_on`
   - DND On: `https://ha.patriark.org/api/webhook/ios_focus_dnd_on`
   - Focus Off: `https://ha.patriark.org/api/webhook/ios_focus_off`

### Step 4: Create iOS Shortcuts (One Per Focus Mode)

**On iPhone/iPad:**

1. **Open Shortcuts app**

2. **Create "Focus Personal On" shortcut:**
   - Tap + (New Shortcut)
   - Name: "Focus Personal On"
   - Add Action: "Get Contents of URL"
     - URL: `https://ha.patriark.org/api/webhook/ios_focus_personal_on`
     - Method: POST
   - Done

3. **Repeat for each Focus Mode:**
   - "Focus Work On" → webhook: `ios_focus_work_on`
   - "Focus Sleep On" → webhook: `ios_focus_sleep_on`
   - "Focus DND On" → webhook: `ios_focus_dnd_on`
   - "Focus Off" → webhook: `ios_focus_off`

### Step 5: Create iOS Personal Automations

**On iPhone/iPad:**

1. **Open Shortcuts app → Automation tab**

2. **Create "Personal Focus Turns On" automation:**
   - Tap + (New Automation)
   - Select "Focus"
   - Choose "Personal" focus
   - Choose "Is Turned On"
   - Next
   - Add Action: "Run Shortcut"
   - Select "Focus Personal On" shortcut
   - Turn OFF "Ask Before Running" (important!)
   - Turn ON "Notify When Run" (for testing, disable later)
   - Done

3. **Repeat for other Focus Modes:**
   - Work → "Focus Work On"
   - Sleep → "Focus Sleep On"
   - Do Not Disturb → "Focus DND On"

4. **Create "Any Focus Turns Off" automation:**
   - New Automation → Focus
   - Select any focus mode
   - Choose "Is Turned Off"
   - Run Shortcut: "Focus Off"

### Step 6: Test Focus Mode Detection

1. **Enable Personal focus mode** (Control Center → Focus → Personal)

2. **Check HA:**
   - Developer Tools → States
   - Find `input_select.ios_focus_mode`
   - State should change to "Personal"

3. **Disable focus mode**
   - State should change to "None"

4. **Test other focus modes:**
   - Work, Sleep, DND
   - Verify `input_select.ios_focus_mode` updates correctly

**✅ Success Criteria:**
- Focus mode changes on iPhone/Apple Watch instantly reflect in HA
- `input_select.ios_focus_mode` updates within 1-2 seconds
- Works both locally and remotely (through Traefik → Authelia)

**💡 Key Learning:**
- **Webhooks** allow external services (iOS) to trigger HA automations
- **Input select helper** stores current focus mode (persistent state)
- **iOS Personal Automations** run automatically (no user interaction)
- **Apple Watch** can trigger HA automations via Focus Mode changes

---

## Exercise 4B.2: Create Focus Mode Dashboard

**Time:** 20 minutes
**Goal:** Visualize current focus mode, quickly change modes

```yaml
# Dashboard: Focus & Automation
views:
  - title: Focus Control
    path: focus-control
    icon: mdi:cellphone-check
    cards:
      # Current Focus Mode Display
      - type: entities
        title: Current Status
        entities:
          - entity: input_select.ios_focus_mode
            name: "iPhone Focus Mode"
            icon: mdi:cellphone-check

          - entity: binary_sensor.iphone_home
            name: "Presence"
            icon: mdi:home-account

      # Quick Focus Mode Selector (manual override)
      - type: button
        name: "Work Focus"
        icon: mdi:briefcase
        tap_action:
          action: call-service
          service: input_select.select_option
          target:
            entity_id: input_select.ios_focus_mode
          data:
            option: "Work"

      # Status Summary Card
      - type: markdown
        content: |
          ## Current Context

          **Focus Mode:** {{ states('input_select.ios_focus_mode') }}
          **Presence:** {{ 'Home' if is_state('binary_sensor.iphone_home', 'on') else 'Away' }}

          **Active Automations:**
          {% if is_state('input_select.ios_focus_mode', 'Work') and is_state('binary_sensor.iphone_home', 'on') %}
          - 🔆 Focus lighting active
          - 🤫 Vacuum paused
          {% elif is_state('input_select.ios_focus_mode', 'Sleep') %}
          - 🌙 Sleep lighting active
          - 🔇 All sounds muted
          {% else %}
          - ✅ Normal operation
          {% endif %}
```

---

# Part C: Focus Mode + Presence Automation Matrix

**Duration:** 1-2 hours
**Goal:** Create intelligent automations that respond to **both** Focus Mode AND Presence

**Key Concept:** Different actions based on **context matrix**:

| Focus Mode | Home | Away |
|------------|------|------|
| Personal | Relax lighting | Start vacuum |
| Work | Focus lighting, DND vacuum | Normal away mode |
| Sleep | Minimal lighting, all quiet | (Shouldn't happen) |
| DND | Movie lighting, pause vacuum | Normal away mode |

---

## Exercise 4C.1: Work Focus + Home = Productivity Mode

```yaml
- id: work_focus_home_productivity
  alias: "Work Focus @ Home: Productivity Mode"
  description: "Activate focus lighting and silence distractions"

  trigger:
    # Trigger 1: Work focus activated while home
    - platform: state
      entity_id: input_select.ios_focus_mode
      to: "Work"

    # Trigger 2: Arrive home while in work focus
    - platform: state
      entity_id: binary_sensor.iphone_home
      to: "on"

  condition:
    # Both must be true
    - condition: state
      entity_id: input_select.ios_focus_mode
      state: "Work"

    - condition: state
      entity_id: binary_sensor.iphone_home
      state: "on"

    # Daytime only (not late night work)
    - condition: time
      after: "08:00:00"
      before: "22:00:00"

  action:
    # Activate Focus lighting scene (bright, cool white)
    - service: scene.turn_on
      target:
        entity_id: scene.focus  # From Phase 1

    # Pause vacuum if running (reduce distraction)
    - service: vacuum.pause
      target:
        entity_id: vacuum.roborock_saros_10
      continue_on_error: true  # Don't fail if vacuum already docked

    # Notification (optional, disable when confident)
    - service: notify.persistent_notification
      data:
        title: "🧠 Productivity Mode"
        message: "Work focus active - lighting optimized, distractions minimized"
```

---

## Exercise 4C.2: Sleep Focus = Complete Quiet Mode

```yaml
- id: sleep_focus_bedtime_routine
  alias: "Sleep Focus: Bedtime Routine"
  description: "Dim lights, ensure vacuum docked, minimize noise"

  trigger:
    - platform: state
      entity_id: input_select.ios_focus_mode
      to: "Sleep"

  condition:
    # Only at home (shouldn't trigger sleep mode when away)
    - condition: state
      entity_id: binary_sensor.iphone_home
      state: "on"

  action:
    # Very dim warm lighting (bedtime)
    - service: light.turn_on
      target:
        entity_id: all
      data:
        brightness_pct: 5
        color_temp: 500  # Very warm
        transition: 10  # Slow 10-second fade

    # Ensure vacuum is docked (pause if cleaning)
    - choose:
        - conditions:
            - condition: state
              entity_id: vacuum.roborock_saros_10
              state: "cleaning"
          sequence:
            - service: vacuum.return_to_base
              target:
                entity_id: vacuum.roborock_saros_10

    # Optional: Disable motion sensors, set alarm system, etc.
```

---

## Exercise 4C.3: "Leaving Home" Focus (Custom Mode)

**Time:** 30 minutes
**Goal:** Create custom "Leaving Home" Focus Mode that triggers departure automation

### Step 1: Create Custom Focus Mode on iPhone

1. **Settings → Focus → + (top right)**
2. **Choose "Custom"**
3. **Name:** "Leaving Home"
4. **Icon:** Choose house icon
5. **Configure:**
   - Allow Notifications: None (or minimal)
   - Home Screen: Default
6. **Add to Control Center**

### Step 2: Create HA Webhook + Shortcut

**Webhook automation:**
```yaml
- id: ios_focus_leaving_home_on
  alias: "iOS Focus: Leaving Home Activated"

  trigger:
    - platform: webhook
      webhook_id: ios_focus_leaving_home_on

  action:
    - service: input_select.select_option
      target:
        entity_id: input_select.ios_focus_mode
      data:
        option: "Leaving Home"
```

**iOS Shortcut:** "Focus Leaving Home On"
- URL: `https://ha.patriark.org/api/webhook/ios_focus_leaving_home_on`
- Method: POST

**iOS Personal Automation:**
- When "Leaving Home" focus turns on
- Run Shortcut: "Focus Leaving Home On"

### Step 3: Departure Automation

```yaml
- id: leaving_home_departure_routine
  alias: "Leaving Home: Departure Routine"
  description: "Secure home and start cleaning when leaving"

  trigger:
    - platform: state
      entity_id: input_select.ios_focus_mode
      to: "Leaving Home"

  condition:
    # Double-check presence (WiFi should show away)
    - condition: state
      entity_id: binary_sensor.iphone_home
      state: "off"
      for:
        seconds: 30

  action:
    # Turn off all lights (save energy)
    - service: light.turn_off
      target:
        entity_id: all

    # Start vacuum cleaning (after lights off)
    - delay:
        seconds: 5
    - service: vacuum.start
      target:
        entity_id: vacuum.roborock_saros_10
      data:
        fan_speed: "balanced"

    # Optional: Lock smart locks, arm security, etc.

    # Confirmation notification
    - service: notify.mobile_app_iphone
      data:
        title: "🏠 Departure Routine Complete"
        message: "Lights off, vacuum started. Have a great day!"
```

**💡 Key Insight:**
- **Apple Watch** → Enable "Leaving Home" focus (2 seconds)
- **HA** → Detects focus change → runs departure automation
- **No need to open phone/iPad** → perfect for leaving quickly

---

## Exercise 4C.4: Movie/DND Focus = Entertainment Mode

```yaml
- id: dnd_focus_movie_mode
  alias: "DND/Movie Focus: Entertainment Mode"
  description: "Dim lights for movies, pause vacuum, silence notifications"

  trigger:
    - platform: state
      entity_id: input_select.ios_focus_mode
      to: "Do Not Disturb"

  condition:
    # Only at home
    - condition: state
      entity_id: binary_sensor.iphone_home
      state: "on"

    # Evening/night (movies typically watched after 18:00)
    - condition: time
      after: "18:00:00"

  action:
    # Activate Movie scene (dim red/amber lighting)
    - service: scene.turn_on
      target:
        entity_id: scene.movie  # From Phase 1

    # Pause vacuum if running
    - service: vacuum.pause
      target:
        entity_id: vacuum.roborock_saros_10
      continue_on_error: true

    # Optional: Mute Sonos, pause media on other devices
```

---

# Part D: Advanced Choreography

**Duration:** 1 hour
**Goal:** Multi-device choreography based on context

---

## Exercise 4D.1: Morning Arrival (Work Focus + WiFi Connect)

```yaml
- id: morning_arrival_work_focus
  alias: "Morning Arrival: Work Day Routine"
  description: "Arriving home in morning with work focus = coffee prep mode"

  trigger:
    - platform: state
      entity_id: binary_sensor.iphone_home
      from: "off"
      to: "on"

  condition:
    # Work focus active
    - condition: state
      entity_id: input_select.ios_focus_mode
      state: "Work"

    # Morning hours (06:00-11:00)
    - condition: time
      after: "06:00:00"
      before: "11:00:00"

    # Weekdays only
    - condition: time
      weekday:
        - mon
        - tue
        - wed
        - thu
        - fri

  action:
    # Energize lighting (bright, cool)
    - service: scene.turn_on
      target:
        entity_id: scene.energize

    # Ensure vacuum docked (quiet morning)
    - service: vacuum.return_to_base
      target:
        entity_id: vacuum.roborock_saros_10
      continue_on_error: true

    # Welcome notification
    - service: notify.mobile_app_iphone
      data:
        title: "Good Morning! ☕"
        message: "Work focus detected - energizing lighting activated"

    # Optional: Start coffee maker (if smart plug integrated)
```

---

## Exercise 4D.2: Cleaning Conflict Prevention

```yaml
- id: vacuum_conflict_prevention
  alias: "Vacuum: Prevent Cleaning During Focus Work"
  description: "Cancel scheduled vacuum if work focus active at home"

  trigger:
    # Scheduled vacuum start time
    - platform: time
      at: "10:00:00"

  condition:
    # Work focus active
    - condition: state
      entity_id: input_select.ios_focus_mode
      state: "Work"

    # At home
    - condition: state
      entity_id: binary_sensor.iphone_home
      state: "on"

  action:
    # Send notification instead of starting vacuum
    - service: notify.mobile_app_iphone
      data:
        title: "🤖 Vacuum Cleaning Postponed"
        message: "Scheduled cleaning skipped - Work focus active. Start manually when ready."
        data:
          actions:
            - action: "VACUUM_START_NOW"
              title: "Start Cleaning Now"
            - action: "VACUUM_POSTPONE_1H"
              title: "Postpone 1 Hour"
```

---

## Phase 4 Completion: What You've Built

### Capabilities Unlocked ✅

**Roborock Control:**
- ✅ Basic vacuum control (start, stop, pause, dock)
- ✅ Presence-based automation (clean when away)
- ✅ Scheduled cleaning (time + presence conditions)
- ✅ Actionable notifications (resume/dock from lock screen)

**iOS Focus Mode Integration:**
- ✅ Focus mode detection via webhooks (Personal, Work, Sleep, DND, custom)
- ✅ Apple Watch control (change focus → trigger HA)
- ✅ Focus mode dashboard (visualize current mode)

**Context-Aware Automation:**
- ✅ Focus Mode + Presence matrix (Work@Home, Sleep, Leaving Home, Movie)
- ✅ Multi-device choreography (lights + vacuum coordination)
- ✅ Conflict prevention (skip cleaning during work focus)

### Skills Mastered

- **Webhook triggers** (external service integration)
- **iOS Shortcuts** (no-code iOS automation)
- **Apple ecosystem leverage** (Watch → iPhone → HA)
- **Multi-condition logic** (AND/OR conditions in automations)
- **Actionable notifications** (iOS notification actions)
- **State tracking** (input_select helpers for persistent state)
- **Context matrix design** (2D decision making: focus + presence)

---

## Next Steps

### Option A: Expand to Phase 5 (Homelab Integration Showcase)
- CrowdSec → HA security automations
- Prometheus → HA energy monitoring
- Loki log correlation
- Network-aware features (UDM Pro via Unpoller)

### Option B: Create More Focus Mode Contexts
- **Reading Focus** → Warm dim lighting, pause all media
- **Exercise Focus** → Bright lighting, energetic scenes
- **Cooking Focus** → Kitchen-specific lighting, timers

### Option C: Add Nextcloud Calendar Integration
- Calendar events trigger automations
- "Deep Clean" event → vacuum thorough cleaning
- "Guest Arriving" event → welcome scenes

---

## Appendix A: Focus Mode Best Practices

### When to Use Focus Modes vs Time Automations

**Focus Modes (Dynamic):**
- ✅ Unpredictable schedule (freelancer, shift worker)
- ✅ User-initiated context changes ("I'm starting work now")
- ✅ Apple Watch quick access (leaving home, movie time)
- ✅ Flexible timing (work from 09:00 one day, 11:00 another)

**Time Automations (Static):**
- ✅ Fixed daily routines (wake up 07:00, bedtime 22:30)
- ✅ Background tasks (nightly cleanup, weekly deep clean)
- ✅ No user interaction needed (automatic)

**Best: Combine Both**
- Time trigger + Focus condition: "If 10:00 AND Work focus, skip vacuum"
- Focus trigger + Time condition: "If Sleep focus AND after 20:00, dim lights"

---

## Appendix B: Troubleshooting Roborock

**Issue: Roborock not discovered during setup**
- Verify device on VLAN2 (192.168.2.0/24) - same as iPhone
- Check UDM Pro firewall: Allow VLAN1 (fedora-htpc) → VLAN2 (IoT devices)
- Ensure Roborock app working (firmware updated)
- Try removing and re-adding integration

**Issue: Vacuum shows "Unavailable" in HA**
- Check Roborock still connected to WiFi (Roborock app)
- Verify local API port 58867 reachable: `nc -zv ROBOROCK_IP 58867`
- Restart Roborock (press power button 10 seconds)
- Restart HA integration (Settings → Devices → Roborock → Reload)

**Issue: Focus mode webhook not triggering**
- Verify webhook URL correct: `https://ha.patriark.org/api/webhook/WEBHOOK_ID`
- Check iOS Personal Automation: "Ask Before Running" = OFF
- Test webhook manually: `curl -X POST https://ha.patriark.org/api/webhook/WEBHOOK_ID`
- Check HA logs: Settings → System → Logs → Search "webhook"

---

## Appendix C: iOS Focus Mode Resources

**Official Documentation:**
- [Home Assistant: iOS Focus Mode Automation](https://www.derekseaman.com/2025/06/home-assistant-trigger-on-any-ios-18-ios-26-focus-mode.html)
- [HA Community: Using iOS Focus Modes](https://community.home-assistant.io/t/blog-post-using-any-ios-18-ios-26-focus-mode-to-trigger-ha-automations/901179)
- [Webhook Integration](https://www.home-assistant.io/integrations/webhook/)

**Community Guides:**
- [Michael Sleen: Focus Automations](https://www.michaelsleen.com/focus-automations/)
- [Mitch Talmadge: iPhone Focus Automation](https://mitchtalmadge.com/2025/03/21/iphone-focus-automation-via-homeassistant.html)

---

**Document Status:** Complete
**Last Updated:** 2026-01-28
**Next Phase:** [Phase 5: Homelab Integration Showcase](./home-assistant-phase5-homelab-integration.md)

**Sources:**
- [Roborock Home Assistant Integration](https://www.home-assistant.io/integrations/roborock/)
- [Roborock Setup Guide](https://pimylifeup.com/home-assistant-roborock/)
- [iOS Focus Mode HA Integration Guide](https://www.derekseaman.com/2025/06/home-assistant-trigger-on-any-ios-18-ios-26-focus-mode.html)
- [HA Community: iOS Focus Modes](https://community.home-assistant.io/t/blog-post-using-any-ios-18-ios-26-focus-mode-to-trigger-ha-automations/901179)
- [Roborock Saros 10 HA Issues](https://github.com/home-assistant/core/issues/152159)
