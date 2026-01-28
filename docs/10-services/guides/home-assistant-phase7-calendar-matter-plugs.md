# Phase 7: Calendar-Driven Automation + Matter Smart Plugs

**Parent Guide:** [Home Assistant Learning Path](./home-assistant-learning-path.md)
**Duration:** Future (when ready to expand)
**Difficulty:** Intermediate
**Status:** 📝 Reference guide - deploy when needed

**Two independent features:**
1. **Nextcloud Calendar Integration** - Schedule tasks via CalDAV calendar
2. **Matter Smart Plugs** - Control panel heaters (future hardware purchase)

---

# Part A: Nextcloud Calendar Integration (CalDAV)

**Goal:** Use your self-hosted Nextcloud Calendar to schedule Home Assistant automations

**Use Cases:**
- Calendar event "Deep Clean" → trigger vacuum thorough cleaning
- Calendar event "Guest Arriving 18:00" → activate welcome scene
- Calendar event "Work Focus Block" → activate productivity mode
- Calendar event "Movie Night" → entertainment lighting preset

---

## Exercise 7A.1: Connect Nextcloud Calendar to Home Assistant

**Time:** 20 minutes
**Prerequisites:** Nextcloud Calendar already configured (you have this)

### Step 1: Add CalDAV Integration

1. **Settings → Devices & Services → Add Integration**
2. **Search "CalDAV"** ([source](https://www.home-assistant.io/integrations/caldav/))
3. **Enter Nextcloud credentials:**
   - **URL:** `https://nextcloud.patriark.org/remote.php/dav`
   - **Username:** Your Nextcloud username
   - **Password:** Nextcloud password or app password (recommended)
   - **Calendars:** Select calendars to import

4. **Submit** - Integration will discover your calendars

### Step 2: Verify Calendar Entities

**Developer Tools → States:**
```yaml
# Example entities created:
calendar.personal              # Your personal calendar
calendar.home_automation       # Create this calendar in Nextcloud for HA events
calendar.shared_family         # If you have shared calendars
```

**Check calendar event:**
- Current/upcoming events appear in entity attributes
- State: `on` (event active now) or `off` (no current event)

---

## Exercise 7A.2: Create Calendar-Triggered Automation

**Time:** 30 minutes
**Goal:** Trigger actions based on calendar events

### Automation 1: "Deep Clean" Calendar Event

**In Nextcloud Calendar:**
1. Create calendar event titled "Deep Clean"
2. Set date/time (e.g., Saturday 09:00)
3. Description: "Thorough house cleaning"

**In Home Assistant:**
```yaml
- id: calendar_deep_clean
  alias: "Calendar: Deep Clean Triggered"
  description: "Start max power vacuum cleaning when calendar event starts"

  trigger:
    - platform: calendar
      entity_id: calendar.home_automation
      event: start
      offset: "-00:00:00"  # Trigger at event start

  condition:
    # Check event title contains "Deep Clean"
    - condition: template
      value_template: >
        {{ 'deep clean' in trigger.calendar_event.summary | lower }}

  action:
    # Send notification
    - service: notify.mobile_app_iphone
      data:
        title: "🧹 Deep Clean Starting"
        message: "{{ trigger.calendar_event.summary }} scheduled for {{ trigger.calendar_event.start }}"

    # Start vacuum in max power mode
    - service: vacuum.start
      target:
        entity_id: vacuum.roborock_saros_10
      data:
        fan_speed: "max"
```

### Automation 2: "Guest Arriving" Event

```yaml
- id: calendar_guest_arriving
  alias: "Calendar: Guest Arrival Preparation"
  description: "Activate welcome scene 30 minutes before guests arrive"

  trigger:
    - platform: calendar
      entity_id: calendar.personal
      event: start
      offset: "-00:30:00"  # 30 minutes before event

  condition:
    - condition: template
      value_template: >
        {{ 'guest' in trigger.calendar_event.summary | lower or
           'visitor' in trigger.calendar_event.summary | lower }}

  action:
    # Ensure vacuum is docked (not cleaning when guests arrive)
    - service: vacuum.return_to_base
      target:
        entity_id: vacuum.roborock_saros_10
      continue_on_error: true

    # Activate welcome lighting
    - service: scene.turn_on
      target:
        entity_id: scene.relax

    # Notification
    - service: notify.mobile_app_iphone
      data:
        title: "👋 Guests Arriving Soon"
        message: "{{ trigger.calendar_event.summary }} at {{ trigger.calendar_event.start.strftime('%H:%M') }}"
```

### Automation 3: "Work Focus Block" Event

```yaml
- id: calendar_work_focus_block
  alias: "Calendar: Work Focus Block"
  description: "Activate productivity mode for scheduled focus time"

  trigger:
    - platform: calendar
      entity_id: calendar.personal
      event: start

  condition:
    - condition: template
      value_template: >
        {{ 'focus' in trigger.calendar_event.summary | lower or
           'work block' in trigger.calendar_event.summary | lower }}

    # Only at home
    - condition: state
      entity_id: binary_sensor.iphone_home
      state: "on"

  action:
    # Activate focus lighting
    - service: scene.turn_on
      target:
        entity_id: scene.focus

    # Set iOS focus mode (if HA → iOS integration exists)
    # This would require additional iOS Shortcuts setup

    # Notification with actionable reminder
    - service: notify.mobile_app_iphone
      data:
        title: "🧠 Focus Time"
        message: "{{ trigger.calendar_event.summary }} starting now"
        data:
          actions:
            - action: "FOCUS_REMIND_30MIN"
              title: "Remind me in 30 min"
```

---

## Exercise 7A.3: Calendar Dashboard

**Time:** 15 minutes
**Goal:** Display upcoming calendar events

```yaml
# Dashboard: Calendar & Schedule
views:
  - title: Schedule
    path: schedule
    icon: mdi:calendar
    cards:
      # Upcoming events
      - type: calendar
        entities:
          - calendar.home_automation
          - calendar.personal
        initial_view: listWeek

      # Today's automations
      - type: markdown
        title: Today's Scheduled Automations
        content: |
          {% set events = state_attr('calendar.home_automation', 'message') %}
          {% if events %}
          **Upcoming:**
          {{ events }}
          {% else %}
          No scheduled automations today
          {% endif %}
```

---

## CalDAV vs iOS Focus Mode: When to Use Which?

| Feature | Nextcloud Calendar | iOS Focus Mode |
|---------|-------------------|----------------|
| **Trigger Type** | Time-based, scheduled | User-initiated, context |
| **Planning** | Plan ahead (days/weeks) | Instant (Apple Watch) |
| **Best For** | Recurring events, appointments | Dynamic context changes |
| **Control** | Nextcloud app, HA dashboard | iPhone/iPad/Apple Watch |
| **Automation** | Event start/end triggers | Focus on/off triggers |

**Recommendation: Use Both**
- **Calendar:** Scheduled events (guests, cleaning, focus blocks)
- **Focus Mode:** Instant context changes (leaving home, movie time, work)

**Example Combination:**
1. Calendar event "Work Block 10:00-12:00"
2. Event starts → HA activates Work focus mode (via iOS Shortcut webhook)
3. Work focus triggers lighting + vacuum pause
4. Event ends → HA deactivates Work focus

---

# Part B: Matter Smart Plugs for Panel Heaters

**Goal:** Control old Gen 1 Mill panel heaters via Matter smart plugs

**Status:** 🛒 **Hardware not yet purchased** - this is a reference for future deployment

---

## Recommended Hardware: Eve Energy (Matter)

**Specs:**
- Power rating: 2500W / 11A
- EU plug: Type E & F (Schuko)
- Protocol: Matter over Thread
- Energy monitoring: Yes (W, kWh, voltage, current)
- Price: ~300-400 NOK for 2-pack

**Where to buy:**
- [avXperten.no](https://www.avxperten.no/enheder-til-matter-smart-home/) (Norwegian retailer)
- [Amazon.com](https://www.amazon.com/Eve-Energy-Matter-Control-SmartThings/dp/B0BZBGD87V) (international shipping)

**Why Eve Energy:**
- ✅ Sufficient power rating for 2000W heaters (2500W capacity)
- ✅ EU manufactured (German company)
- ✅ Excellent reputation (Apple HomeKit heritage)
- ✅ Thread mesh networking (extends range)
- ✅ Energy monitoring built-in

---

## ⚠️ CRITICAL SAFETY INFORMATION

**Before using smart plugs with panel heaters:**

### Power Rating Verification

**Your Mill panel heaters (Gen 1):**
- Typical rating: 600W, 1000W, 1500W, 2000W (check label on heater)
- **CRITICAL:** Smart plug must support continuous load
- **Formula:** Watts ÷ 230V = Amps
  - 2000W ÷ 230V = 8.7A
  - Eve Energy rating: 11A (✅ sufficient)

### Safety Requirements

1. **Direct wall outlet only** - NO extension cords or power strips
2. **Ventilation** - Ensure good airflow around smart plug
3. **Supervised load test** - Monitor plug temperature during first 2 hours of use
4. **Fire hazard** - If plug feels warm (>40°C), STOP use immediately
5. **Norwegian electrical code** - Verify plug meets NEK 400 standards

### NOT Suitable For

- ❌ Space heaters >2000W
- ❌ High-draw appliances without continuous rating verification
- ❌ Appliances that cycle on/off rapidly (wear on relay)

---

## Quick Deployment Reference (When Hardware Arrives)

### Step 1: Commission Matter Smart Plug (5 minutes)

1. **Plug Eve Energy into wall outlet** (don't connect heater yet)
2. **Home Assistant:** Settings → Devices & Services → Matter integration
3. **Add Device** → Scan QR code on Eve Energy box
4. **Commissioning** - Matter Server connects via Thread network
5. **Verify entity created:**
   ```yaml
   switch.eve_energy_living_room  # Main switch entity
   sensor.eve_energy_power        # Current power (W)
   sensor.eve_energy_total        # Total energy (kWh)
   ```

### Step 2: Connect Panel Heater (Safety Check)

1. **Plug panel heater into Eve Energy**
2. **Turn on heater** (set to desired temperature)
3. **Monitor for 2 hours:**
   - Check Eve Energy temperature (should be <40°C)
   - Check power consumption (should match heater rating)
   - Listen for unusual sounds (clicking, buzzing = stop use)

### Step 3: Create Heater Control Automation (10 minutes)

```yaml
# Temperature-based heater control
- id: heater_temperature_control
  alias: "Heater: Temperature-Based Control"
  description: "Turn on heater when temp drops below 19°C, off above 21°C"

  trigger:
    # Too cold
    - platform: numeric_state
      entity_id: sensor.mill_sense_air_temperature
      below: 19
      id: "too_cold"

    # Too warm
    - platform: numeric_state
      entity_id: sensor.mill_sense_air_temperature
      above: 21
      id: "too_warm"

  condition:
    # Only when home (save energy when away)
    - condition: state
      entity_id: binary_sensor.iphone_home
      state: "on"

  action:
    - choose:
        # Turn heater ON (too cold)
        - conditions:
            - condition: trigger
              id: "too_cold"
          sequence:
            - service: switch.turn_on
              target:
                entity_id: switch.eve_energy_living_room

        # Turn heater OFF (too warm)
        - conditions:
            - condition: trigger
              id: "too_warm"
          sequence:
            - service: switch.turn_off
              target:
                entity_id: switch.eve_energy_living_room
```

### Step 4: Energy Monitoring Dashboard

```yaml
# Energy dashboard card
- type: entity
  entity: switch.eve_energy_living_room
  name: "Living Room Heater"
  icon: mdi:radiator

- type: gauge
  entity: sensor.eve_energy_power
  name: "Current Power"
  min: 0
  max: 2000
  unit: "W"

- type: sensor
  entity: sensor.eve_energy_total
  name: "Total Energy (Today)"
  graph: line
```

---

## Norwegian Heating Optimization (Future)

### Nordpool Spot Price Integration

**When Matter plugs deployed + Nordpool integration added:**

**Concept:** Pre-heat during cheap electricity hours (typically night)

```yaml
# Placeholder automation (requires Nordpool integration)
- id: heater_spot_price_optimization
  alias: "Heater: Spot Price Optimization"
  description: "Pre-heat during low-price hours"

  trigger:
    - platform: numeric_state
      entity_id: sensor.nordpool_spot_price
      below: 0.50  # NOK/kWh (adjust threshold)

  condition:
    # Only during heating season (Oct-Mar)
    - condition: template
      value_template: >
        {% set month = now().month %}
        {{ month >= 10 or month <= 3 }}

    # Temperature not already high
    - condition: numeric_state
      entity_id: sensor.mill_sense_air_temperature
      below: 21

  action:
    # Pre-heat to 22°C during cheap hours
    - service: switch.turn_on
      target:
        entity_id: switch.eve_energy_living_room

    # Notification
    - service: notify.mobile_app_iphone
      data:
        title: "💰 Cheap Electricity - Pre-Heating"
        message: "Spot price: {{ states('sensor.nordpool_spot_price') }} NOK/kWh"
```

---

## When to Deploy This Phase

**Deploy Matter Smart Plugs When:**
- ✅ Phase 1-4 mastered (comfortable with HA)
- ✅ Budget available (~1200-1600 NOK for 4x Eve Energy plugs)
- ✅ Heating season approaching (September-October)
- ✅ Temperature sensors working (Mill Sense or alternatives)

**Don't Deploy Yet If:**
- ❌ Still learning HA basics (focus on Phases 1-4 first)
- ❌ Uncertain about heater power ratings (safety risk)
- ❌ Summer months (no heating needed - wait until autumn)

---

## Alternative Approach: Thermostat Integration

**If Mill releases new smart heaters with HA integration:**
- Consider replacing Gen 1 heaters with Gen 3 WiFi heaters (if Mill integration improves)
- Native climate entities better than switch-based control
- Eliminates smart plug cost and safety concerns

**Monitor:**
- HA Community forum for Mill integration updates
- Mill Norway website for new smart heater models
- Matter-native heaters (future product category)

---

## Summary: Phase 7 Deployment Status

### Nextcloud Calendar Integration

**Status:** ✅ **Ready to Deploy Anytime**
- No hardware required (Nextcloud already running)
- Official CalDAV integration exists
- Takes ~1 hour to set up and test

**When to Deploy:**
- After mastering Phases 1-4
- When you want scheduled automation
- Complements iOS Focus Mode (planned vs instant)

---

### Matter Smart Plugs

**Status:** 🛒 **Postponed - Hardware Purchase Required**
- Waiting for budget/seasonal timing
- Eve Energy recommended (2500W, EU, reliable)
- Cost: ~1200-1600 NOK for 4 plugs

**When to Deploy:**
- Heating season (Sep-Oct 2026)
- After temperature sensor integration working
- Budget available for hardware

---

**Document Status:** Reference guide (deploy when ready)
**Last Updated:** 2026-01-28
**Dependencies:** Phases 1-4 completion, hardware procurement (Matter plugs)

**Sources:**
- [Home Assistant CalDAV Integration](https://www.home-assistant.io/integrations/caldav/)
- [Nextcloud CalDAV Setup](https://help.nextcloud.com/t/home-assistant-connect-to-caldav/68155)
- [Eve Energy Matter Smart Plug](https://matterdevices.net/devices/eve-energy-smart-plug-eu/)
- [avXperten.no Matter Devices](https://www.avxperten.no/enheder-til-matter-smart-home/)
