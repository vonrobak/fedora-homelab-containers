# Phase 3: Air Quality & Climate Monitoring (Mill Devices)

**Parent Guide:** [Home Assistant Learning Path](./home-assistant-learning-path.md)
**Duration:** Week 3
**Difficulty:** Intermediate
**Devices:** Mill Sense Air, Mill Compact Pro (air purifier), Mill Silent Pro (air purifier)
**Goal:** Integrate Norwegian air quality monitoring, understand climate sensor patterns

**Status:** ⚠️ **Integration Challenges** - No official HA integration for Mill air purifiers as of 2026

---

## Understanding Your Mill Ecosystem

### Device Inventory

**Mill Sense Air** - Climate Sensor
- **Type:** Portable climate monitoring sensor
- **Sensors:** Temperature, Humidity, eCO2, TVOC (Total Volatile Organic Compounds)
- **Connectivity:** WiFi (Mill app)
- **HA Integration:** Partial - community requests since 2021 ([source](https://community.home-assistant.io/t/add-suport-for-mill-sense-air-indoor-climate-sensor/345022))

**Mill Compact Pro** - Air Purifier
- **Type:** Compact air purifier with sensors
- **Coverage:** Up to 55 m²
- **Sensors:** PM1, PM2.5, PM10, Temperature, Humidity, eCO2, TVOC
- **Filtration:** HEPA 13 (99.97% particles ≥0.3 microns)
- **HA Integration:** ❌ None ([source](https://millnorway.com/product/mill-silent-pro-compact-air-purifier/))

**Mill Silent Pro** - Air Purifier
- **Type:** Full-size air purifier with sensors
- **Coverage:** Larger rooms
- **Sensors:** PM1, PM2.5, PM10, Temperature, Humidity, eCO2, TVOC
- **Filtration:** HEPA 13
- **HA Integration:** ❌ None

**Old Gen 1 Mill Panel Heaters**
- **Type:** Panel heaters (WiFi smart features)
- **Status:** ⚠️ Abandoned by Mill (Gen 1 IoT system deprecated)
- **HA Integration:** Official Mill integration exists but Gen 1 support problematic ([source](https://www.home-assistant.io/integrations/mill/))

---

## Integration Reality Check

### Current Status (2026)

**✅ What Works:**
- Official Mill integration exists for heaters ([Home Assistant Mill Integration](https://www.home-assistant.io/integrations/mill/))
- Some community discussion about Mill Sense Air support

**❌ What Doesn't Work:**
- No official integration for Mill air purifiers (Silent Pro, Compact Pro)
- Mill Sense Air support unclear (PR submitted 2021, status unknown)
- Gen 1 heaters: Mill migrated to new IoT system (2023), breaking Gen 1 devices

**🔍 Investigation Needed:**
- Check if Mill Sense Air works with official Mill integration
- Verify if community HACS integrations exist
- Test if Mill API can be accessed directly

---

## Phase 3 Strategy: Pragmatic Approach

Given integration limitations, we'll take a **hybrid monitoring approach**:

1. **Use Mill app for air purifier control** (no HA integration available)
2. **Investigate Mill Sense Air integration** (may work with official Mill integration)
3. **Create air quality awareness** through alternative methods
4. **Prepare for future integration** when available

---

## Exercise 3.1: Check Mill Sense Air Integration

**Time:** 15 minutes
**Goal:** Determine if Mill Sense Air can be integrated into Home Assistant

### Steps

1. **Verify Mill integration installed**
   ```bash
   # Check if Mill integration available
   # Settings → Devices & Services → Search "Mill"
   ```

2. **Attempt Mill Sense Air addition**
   - Settings → Devices & Services → Add Integration
   - Search "Mill"
   - Enter Mill account credentials (same as Mill app)
   - Check if Mill Sense Air detected

3. **Expected outcomes:**

   **If Mill Sense Air is discovered:**
   ```yaml
   # Entities created (example):
   sensor.mill_sense_air_temperature
   sensor.mill_sense_air_humidity
   sensor.mill_sense_air_eco2
   sensor.mill_sense_air_tvoc
   ```

   **If NOT discovered:**
   - Mill Sense Air requires community integration or workaround
   - Proceed to Exercise 3.2 (alternative approach)

### Verification

1. **Developer Tools → States**
   - Filter by "mill"
   - Look for temperature, humidity, eCO2, TVOC sensors

2. **Test sensor values**
   - Check sensor readings match Mill app
   - Verify updates (check timestamp)

**💡 Decision Point:**
- **If working:** Proceed to Exercise 3.3 (air quality dashboard)
- **If NOT working:** Proceed to Exercise 3.2 (alternative monitoring)

---

## Exercise 3.2: Alternative Air Quality Monitoring (If Mill Integration Fails)

**Time:** 30 minutes
**Goal:** Create air quality awareness using available sensors

### Option A: Manual Entry Sensors

If Mill devices can't integrate, create **manual input sensors** to track air quality manually:

```yaml
# ~/containers/config/home-assistant/configuration.yaml

# Manual input for air quality tracking
input_number:
  living_room_temperature:
    name: "Living Room Temperature"
    min: 10
    max: 35
    step: 0.5
    unit_of_measurement: "°C"
    icon: mdi:thermometer

  living_room_humidity:
    name: "Living Room Humidity"
    min: 0
    max: 100
    step: 1
    unit_of_measurement: "%"
    icon: mdi:water-percent

  living_room_co2:
    name: "Living Room CO2"
    min: 400
    max: 5000
    step: 50
    unit_of_measurement: "ppm"
    icon: mdi:molecule-co2

  living_room_tvoc:
    name: "Living Room TVOC"
    min: 0
    max: 10000
    step: 50
    unit_of_measurement: "ppb"
    icon: mdi:chemical-weapon

# Binary sensors for air quality thresholds
binary_sensor:
  - platform: template
    sensors:
      air_quality_poor:
        friendly_name: "Air Quality Poor"
        device_class: problem
        value_template: >
          {{ states('input_number.living_room_co2') | float(0) > 1000 or
             states('input_number.living_room_tvoc') | float(0) > 500 }}
```

**Manual Update Process:**
1. Open Mill app on phone
2. Check sensor readings
3. Update HA input numbers manually
4. Use for dashboards and awareness (not real-time automation)

**Pros:**
- ✅ Simple, no integration needed
- ✅ Keeps data in HA for historical tracking
- ✅ Can create dashboards and notifications

**Cons:**
- ❌ Manual entry required (not automated)
- ❌ No real-time automation possible

---

### Option B: MQTT Bridge (Advanced)

If you're comfortable with DIY solutions, create an MQTT bridge:

**Concept:**
1. Capture Mill API data (if accessible)
2. Publish to MQTT broker (Mosquitto)
3. HA subscribes to MQTT topics

**Prerequisites:**
- Mill API documentation/access
- MQTT broker (can deploy in homelab)
- Python script to bridge Mill → MQTT

**Skip this option unless you want a deep-dive project** - focus on working integrations first.

---

### Option C: Keep Mill Separate, Focus on Actionable Data

**Pragmatic approach:**
- Use Mill app for air purifier control and monitoring
- Integrate OTHER air quality sensors if needed (Aqara, Xiaomi)
- Focus HA integration on devices that WORK (Hue, Roborock, heaters via smart plugs)

**When to revisit:**
- Official Mill air purifier integration announced
- Community HACS integration becomes available
- Mill releases open API documentation

---

## Exercise 3.3: Air Quality Dashboard (If Integration Works)

**Time:** 30 minutes
**Goal:** Create visual air quality monitoring dashboard

### Dashboard Design

```yaml
# Dashboard: Air Quality Monitor
views:
  - title: Air Quality
    path: air-quality
    icon: mdi:air-filter
    cards:
      # Header card
      - type: markdown
        content: |
          # 🌫️ Indoor Air Quality
          Real-time monitoring from Mill sensors

      # Temperature & Humidity (horizontal gauges)
      - type: horizontal-stack
        cards:
          - type: gauge
            entity: sensor.mill_sense_air_temperature
            name: Temperature
            min: 15
            max: 30
            severity:
              green: 20
              yellow: 25
              red: 28
            needle: true

          - type: gauge
            entity: sensor.mill_sense_air_humidity
            name: Humidity
            min: 20
            max: 80
            severity:
              green: 40
              yellow: 30
              red: 65
            needle: true

      # Air Quality Metrics (PM, CO2, TVOC)
      - type: horizontal-stack
        cards:
          # PM2.5 (if available from purifier)
          - type: gauge
            entity: sensor.mill_compact_pro_pm25
            name: PM2.5
            min: 0
            max: 100
            severity:
              green: 0
              yellow: 25
              red: 50
            unit: "µg/m³"

          # CO2
          - type: gauge
            entity: sensor.mill_sense_air_eco2
            name: CO2
            min: 400
            max: 2000
            severity:
              green: 400
              yellow: 800
              red: 1000
            unit: "ppm"

          # TVOC
          - type: gauge
            entity: sensor.mill_sense_air_tvoc
            name: TVOC
            min: 0
            max: 1000
            severity:
              green: 0
              yellow: 300
              red: 500
            unit: "ppb"

      # Air Quality Status Summary
      - type: entities
        title: Air Quality Status
        entities:
          - entity: binary_sensor.air_quality_poor
            name: "Air Quality Alert"
          - entity: sensor.mill_sense_air_temperature
            name: "Temperature"
          - entity: sensor.mill_sense_air_humidity
            name: "Humidity"
          - entity: sensor.mill_sense_air_eco2
            name: "CO2 Level"

      # Historical graphs (past 24 hours)
      - type: history-graph
        title: Temperature & Humidity (24h)
        hours_to_show: 24
        entities:
          - entity: sensor.mill_sense_air_temperature
          - entity: sensor.mill_sense_air_humidity

      - type: history-graph
        title: Air Quality (24h)
        hours_to_show: 24
        entities:
          - entity: sensor.mill_sense_air_eco2
          - entity: sensor.mill_sense_air_tvoc
```

### Air Quality Thresholds (Norwegian Standards)

**Temperature:**
- ✅ Optimal: 19-22°C (living spaces)
- ⚠️ Acceptable: 18-24°C
- 🚨 Poor: <18°C or >24°C

**Humidity:**
- ✅ Optimal: 40-60%
- ⚠️ Acceptable: 30-70%
- 🚨 Poor: <30% (dry, winter) or >70% (mold risk)

**CO2 (eCO2):**
- ✅ Excellent: 400-600 ppm (outdoor level)
- ✅ Good: 600-800 ppm
- ⚠️ Acceptable: 800-1000 ppm
- 🚨 Poor: >1000 ppm (ventilation needed)

**TVOC:**
- ✅ Excellent: 0-220 ppb
- ✅ Good: 220-660 ppb
- ⚠️ Acceptable: 660-2200 ppb
- 🚨 Poor: >2200 ppb (source identification needed)

**PM2.5 (if available):**
- ✅ Good: 0-12 µg/m³
- ⚠️ Moderate: 12-35 µg/m³
- 🚨 Unhealthy: >35 µg/m³

---

## Exercise 3.4: Air Quality Awareness Automations

**Time:** 30 minutes
**Goal:** Create notifications when air quality deteriorates

### Automation 1: High CO2 Alert

```yaml
- id: air_quality_high_co2
  alias: "Air Quality: High CO2 Alert"
  description: "Notify when CO2 exceeds 1000 ppm - ventilation needed"

  trigger:
    - platform: numeric_state
      entity_id: sensor.mill_sense_air_eco2
      above: 1000
      for:
        minutes: 5  # Sustained high CO2

  action:
    - service: notify.mobile_app_iphone
      data:
        title: "🌫️ High CO2 Detected"
        message: "CO2 level: {{ states('sensor.mill_sense_air_eco2') }} ppm. Open windows for ventilation."
        data:
          actions:
            - action: "VENTILATION_REMINDER"
              title: "Remind me in 30 min"

    # Optional: Visual alert (flash lights amber)
    - service: light.turn_on
      target:
        entity_id: light.living_room_ceiling
      data:
        rgb_color: [255, 191, 0]  # Amber
        brightness_pct: 50
        flash: short
```

### Automation 2: Poor Air Quality Notification

```yaml
- id: air_quality_poor_tvoc
  alias: "Air Quality: High TVOC Alert"
  description: "Notify when TVOC exceeds healthy threshold"

  trigger:
    - platform: numeric_state
      entity_id: sensor.mill_sense_air_tvoc
      above: 500
      for:
        minutes: 10

  condition:
    # Only alert during waking hours
    - condition: time
      after: "07:00:00"
      before: "22:00:00"

  action:
    - service: notify.persistent_notification
      data:
        title: "Poor Air Quality Detected"
        message: |
          TVOC level: {{ states('sensor.mill_sense_air_tvoc') }} ppb

          Possible sources:
          - Cleaning products
          - Cooking fumes
          - New furniture/materials

          Action: Increase ventilation or turn on air purifier
```

### Automation 3: Low Humidity (Winter Dryness)

```yaml
- id: air_quality_low_humidity_winter
  alias: "Air Quality: Low Humidity Alert (Winter)"
  description: "Notify when humidity drops below 30% during heating season"

  trigger:
    - platform: numeric_state
      entity_id: sensor.mill_sense_air_humidity
      below: 30
      for:
        hours: 2

  condition:
    # Winter months (Oct-Mar)
    - condition: template
      value_template: >
        {% set month = now().month %}
        {{ month >= 10 or month <= 3 }}

  action:
    - service: notify.mobile_app_iphone
      data:
        title: "💧 Low Humidity Detected"
        message: "Humidity: {{ states('sensor.mill_sense_air_humidity') }}%. Consider using humidifier or placing water containers on radiators."
```

---

## Exercise 3.5: Climate Comfort Zones (Norwegian Context)

**Time:** 30 minutes
**Goal:** Create comfort zone monitoring for Norwegian climate

### Concept: Climate Comfort Score

Create a **template sensor** that scores overall climate comfort (0-100):

```yaml
# ~/containers/config/home-assistant/configuration.yaml

template:
  - sensor:
      - name: "Climate Comfort Score"
        unique_id: climate_comfort_score
        unit_of_measurement: "%"
        icon: mdi:home-thermometer-outline
        state: >
          {% set temp = states('sensor.mill_sense_air_temperature') | float(20) %}
          {% set humidity = states('sensor.mill_sense_air_humidity') | float(50) %}
          {% set co2 = states('sensor.mill_sense_air_eco2') | float(600) %}

          {# Temperature score (optimal: 19-22°C) #}
          {% set temp_score = 100 if (temp >= 19 and temp <= 22) else
                              80 if (temp >= 18 and temp <= 24) else
                              50 if (temp >= 16 and temp <= 26) else 0 %}

          {# Humidity score (optimal: 40-60%) #}
          {% set hum_score = 100 if (humidity >= 40 and humidity <= 60) else
                             80 if (humidity >= 30 and humidity <= 70) else
                             50 if (humidity >= 25 and humidity <= 75) else 0 %}

          {# CO2 score (optimal: <800 ppm) #}
          {% set co2_score = 100 if co2 < 600 else
                             80 if co2 < 800 else
                             60 if co2 < 1000 else
                             40 if co2 < 1200 else 0 %}

          {# Average score #}
          {{ ((temp_score + hum_score + co2_score) / 3) | round(0) }}

        attributes:
          temperature_score: >
            {% set temp = states('sensor.mill_sense_air_temperature') | float(20) %}
            {{ 100 if (temp >= 19 and temp <= 22) else
               80 if (temp >= 18 and temp <= 24) else
               50 if (temp >= 16 and temp <= 26) else 0 }}

          humidity_score: >
            {% set humidity = states('sensor.mill_sense_air_humidity') | float(50) %}
            {{ 100 if (humidity >= 40 and humidity <= 60) else
               80 if (humidity >= 30 and humidity <= 70) else
               50 if (humidity >= 25 and humidity <= 75) else 0 }}

          co2_score: >
            {% set co2 = states('sensor.mill_sense_air_eco2') | float(600) %}
            {{ 100 if co2 < 600 else
               80 if co2 < 800 else
               60 if co2 < 1000 else
               40 if co2 < 1200 else 0 }}

          rating: >
            {% set score = states('sensor.climate_comfort_score') | float(0) %}
            {{ 'Excellent' if score >= 90 else
               'Good' if score >= 70 else
               'Fair' if score >= 50 else
               'Poor' }}
```

### Dashboard: Comfort Score Display

```yaml
# Add to Air Quality dashboard
- type: gauge
  entity: sensor.climate_comfort_score
  name: Climate Comfort
  min: 0
  max: 100
  severity:
    green: 70
    yellow: 50
    red: 0
  needle: true
  segments:
    - from: 0
      color: '#db4437'  # Red (Poor)
    - from: 50
      color: '#ff9800'  # Orange (Fair)
    - from: 70
      color: '#fdd835'  # Yellow (Good)
    - from: 90
      color: '#0f9d58'  # Green (Excellent)

# Detailed breakdown
- type: entities
  title: Comfort Breakdown
  entities:
    - entity: sensor.climate_comfort_score
      name: "Overall Score"
    - type: attribute
      entity: sensor.climate_comfort_score
      attribute: rating
      name: "Rating"
    - type: attribute
      entity: sensor.climate_comfort_score
      attribute: temperature_score
      name: "Temperature"
    - type: attribute
      entity: sensor.climate_comfort_score
      attribute: humidity_score
      name: "Humidity"
    - type: attribute
      entity: sensor.climate_comfort_score
      attribute: co2_score
      name: "Air Quality"
```

---

## Phase 3 Completion: What You've Built

### If Mill Integration Worked ✅

**Achievements:**
- ✅ Mill Sense Air integrated (temperature, humidity, CO2, TVOC)
- ✅ Air quality dashboard with real-time monitoring
- ✅ Air quality awareness automations (high CO2, TVOC alerts)
- ✅ Climate comfort score (Norwegian standards)
- ✅ Winter-specific humidity monitoring

**Skills Learned:**
- Numeric state triggers (threshold-based automation)
- Template sensors (calculated values from multiple inputs)
- Gauge cards with severity zones
- Historical graphs (24-hour trends)
- Notification actions (iOS actionable notifications)

---

### If Mill Integration Failed ❌

**Achievements:**
- ✅ Understanding of air quality metrics and thresholds
- ✅ Manual monitoring approach (input_number helpers)
- ✅ Dashboard design patterns (gauges, history graphs)
- ✅ Awareness of integration limitations

**Workarounds:**
- Use Mill app for air purifier control (separate from HA)
- Manual entry for tracking trends (not real-time)
- Focus on devices that DO integrate (Hue, Roborock, future smart plugs)

**When to Revisit:**
- Check HA community forum for updates on Mill integrations
- Search HACS for community Mill integrations
- Monitor official Mill API announcements

---

## Next Steps

**Proceed to Phase 4:** Roborock Intelligence + iOS Focus Mode Integration

**Why this progression makes sense:**
- Roborock has official HA integration (higher success rate)
- iOS Focus Mode integration teaches webhook/API concepts
- Focus Mode + Presence = powerful automation patterns
- Builds on presence detection from Phase 1

**If you want to pursue Mill integration further:**
- Post to HA community forum with your specific devices
- Check if Mill API is documented (reverse engineering opportunity)
- Consider alternative air quality sensors (Aqara, Xiaomi) with better HA support

---

## Appendix A: Norwegian Air Quality Standards

**FHI (Folkehelseinstituttet) Recommendations:**

| Metric | Optimal | Acceptable | Poor | Source |
|--------|---------|------------|------|--------|
| Temperature | 19-22°C | 18-24°C | <18 or >24°C | Building regulations TEK17 |
| Humidity | 40-60% | 30-70% | <30 or >70% | FHI indoor climate guide |
| CO2 | <600 ppm | 600-1000 ppm | >1000 ppm | FHI ventilation standards |
| PM2.5 | <12 µg/m³ | 12-35 µg/m³ | >35 µg/m³ | WHO guidelines |

**Norwegian Context:**
- **Winter (Oct-Mar):** Focus on humidity (heating causes dryness)
- **Ventilation:** Norwegian homes require mechanical ventilation (TEK17)
- **Energy efficiency:** Balance ventilation with heat retention

---

## Appendix B: Troubleshooting Mill Integration

**Issue: Mill Sense Air not discovered**
- Verify device connected to WiFi (check Mill app)
- Ensure HA and Mill Sense on same network or HA can reach device VLAN
- Check Mill integration version (Settings → System → Repairs)
- Try removing and re-adding Mill integration

**Issue: Sensors show "Unavailable"**
- Mill migrated IoT systems in 2023 - Gen 1 devices affected
- Check Mill app - if device works there but not HA, API migration issue
- Community thread: [Mill IoT migration issue](https://github.com/home-assistant/core/issues/95424)

**Issue: Air purifiers not detected**
- Expected - no official integration exists as of 2026
- Keep air purifiers controlled via Mill app
- Monitor HA community for future integration announcements

---

**Document Status:** Complete (with integration caveats)
**Last Updated:** 2026-01-28
**Next Phase:** [Phase 4: Roborock + iOS Focus Modes](./home-assistant-phase4-roborock-focus.md)
