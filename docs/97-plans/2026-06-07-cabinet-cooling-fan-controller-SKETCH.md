# Server-Cabinet Active Cooling — Fan Controller (SKETCH / NOT YET BUILT)

> **STATUS: SKETCH — design only, no hardware built, nothing deployed.**
> This is a follow-up plan, not active config. The ESPHome YAML and HA
> automations below are drafts to be implemented when the hardware is in hand.
> When built: the ESPHome config moves to `config/esphome/` (or the ESPHome
> add-on), and the automations into `config/home-assistant/`.

**Date:** 2026-06-07
**Owner:** —
**Context:** Follow-up from the 2026-06-07 "Pi-hole down" investigation. The Pi
resolver was found chronically thermal-throttling (80–86 °C at idle); root cause
was a hot ISP modem stacked beneath it in a passively-cooled, dusty 6U wall
cabinet with no active cooling. De-stacking dropped it to ~63 °C. See
`docs/99-reports/2026-06-07-pihole-false-down-postmortem-private.md` and PR #255
(which added the `PiHoleResolverHot` / `PiHoleResolverCriticalTemp` alerts).

---

## Goal

Add quiet, thermostatically-controlled active cooling to the cabinet (bedroom →
silence matters), plus the **cabinet-ambient temperature telemetry we currently
lack** (the incident could only be inferred from the Pi's CPU temp). Control and
visibility through Home Assistant; cooling resilient to HA/WiFi outage.

## Design decisions

- **Fans:** 2× Noctua **NF-A12x25 G2 PWM** (120 mm, 4-pin, 12 V DC) as **top
  exhaust** (heat rises). DC PWM, not mains AC — silent at low RPM.
- **Mounting:** magnetic, on the steel top panel (the integrating bookshelf
  blocks screwdriver access to the top — and Noctua's rubber push-pins also need
  far-side access, so they don't help here). Add adhesive magnetic brackets (or
  neodymium + 3M VHB) to the fan frames, with the fans' rubber anti-vib pads
  between frame and panel to stop hum transmitting into the steel. Removable for
  dedusting.
- **Controller:** ESP32 + ESPHome. **On-device thermal curve is primary**
  (cabinet keeps cooling if HA/WiFi is down); HA does visibility, manual
  override, and alerting (incl. fan-failure detection).
- **Sensor:** DS18B20 in the cabinet airspace → real ambient telemetry.

## Bill of materials

| Item | Notes |
|---|---|
| 2× Noctua NF-A12x25 G2 PWM | 120 mm 4-pin |
| ESP32 dev board | e.g. esp32dev / nodemcu-32s |
| DS18B20 + 4.7 kΩ resistor | 1-wire temp sensor + pull-up |
| 12 V DC adapter (≥1 A) | powers both fans (~1.4 W each) |
| 12 V→5 V buck *or* USB supply | powers the ESP32 |
| 3.3→5 V level shifter (optional) | spec-correct PWM drive |
| Magnetic fan brackets / neodymium + VHB | tool-free top mount |

## Wiring (Noctua 4-pin: black=GND, yellow=+12 V, green=tach, blue=PWM)

| Fan wire | Connect to |
|---|---|
| Yellow ×2 | 12 V from adapter |
| Black ×2 | GND — **common with adapter GND and ESP32 GND** (required for PWM/tach reference) |
| Blue ×2 | ESP32 **GPIO16** (parallel — both track one PWM) |
| Green fan1 / fan2 | ESP32 **GPIO17** / **GPIO18** |
| DS18B20 data | ESP32 **GPIO4** + 4.7 kΩ pull-up to 3.3 V |
| ESP32 power | its USB 5 V, or a 12 V→5 V buck off the fan rail |

**Safety:** tach is open-collector → use only the ESP's **internal 3.3 V
pull-up** (never pull tach to 5 V/12 V — over-volts the GPIO). GPIO4/16/17/18
avoid the ESP32 strapping pins (0/2/5/12/15).

---

## ESPHome config (draft → `config/esphome/cabinet-cooling.yaml` when built)

```yaml
esphome:
  name: cabinet-cooling
  friendly_name: Server Cabinet Cooling

esp32:
  board: esp32dev          # adjust to your board
  framework:
    type: esp-idf

wifi:
  ssid: !secret wifi_ssid
  password: !secret wifi_password
  ap:
    ssid: "Cabinet-Cooling Fallback"
    password: !secret ap_password

logger:
api:
  encryption:
    key: !secret api_encryption_key
ota:
  - platform: esphome
    password: !secret ota_password

globals:
  - id: fans_on
    type: bool
    restore_value: no
    initial_value: 'false'

one_wire:
  - platform: gpio
    pin: GPIO4

sensor:
  - platform: dallas_temp
    # address: 0x....        # set if >1 sensor on the bus (see boot logs)
    name: "Cabinet Temperature"
    id: cabinet_temp
    update_interval: 30s
    filters:
      - filter_out: nan

  # tach: pulse_counter reports pulses/min; fan = 2 pulses/rev → ×0.5 = RPM
  - platform: pulse_counter
    pin: { number: GPIO17, mode: { input: true, pullup: true } }
    name: "Cabinet Fan 1 RPM"
    id: fan1_rpm
    unit_of_measurement: "RPM"
    accuracy_decimals: 0
    update_interval: 10s
    filters: [ { multiply: 0.5 } ]

  - platform: pulse_counter
    pin: { number: GPIO18, mode: { input: true, pullup: true } }
    name: "Cabinet Fan 2 RPM"
    id: fan2_rpm
    unit_of_measurement: "RPM"
    accuracy_decimals: 0
    update_interval: 10s
    filters: [ { multiply: 0.5 } ]

output:
  - platform: ledc
    id: fan_pwm
    pin: GPIO16
    frequency: 25000 Hz      # 25 kHz = inaudible PWM switching

fan:
  - platform: speed
    output: fan_pwm
    id: cabinet_fans
    name: "Cabinet Fans"

switch:
  - platform: template
    name: "Cabinet Fans Auto Mode"
    id: fan_auto
    optimistic: true
    restore_mode: RESTORE_DEFAULT_ON   # ON = on-device curve drives the fans

interval:
  - interval: 30s
    then:
      - if:
          condition:
            switch.is_on: fan_auto
          then:
            - lambda: |-
                float t = id(cabinet_temp).state;
                float spd;
                if (isnan(t)) {
                  id(fans_on) = true; spd = 0.40;          // sensor fault → safe medium
                } else {
                  if (!id(fans_on) && t >= 30.0) id(fans_on) = true;   // hysteresis
                  if ( id(fans_on) && t <  28.0) id(fans_on) = false;
                  if (!id(fans_on)) {
                    spd = 0.0;
                  } else {
                    spd = (t - 28.0) / 17.0;               // ramp 28→45°C → 0→100%
                    if (spd < 0.20) spd = 0.20;            // floor: clear PWM stall zone
                    if (spd > 1.00) spd = 1.00;
                  }
                }
                auto call = id(cabinet_fans).make_call();
                if (spd <= 0.0) { call.set_state(false); }
                else { call.set_state(true); call.set_speed((int) (spd * 100)); }
                call.perform();
```

## Home Assistant automations (draft → `config/home-assistant/` when built)

Adjust entity IDs / `notify.mobile_app_xxx` to match your instance.

```yaml
# 1) Over-temperature warning — cabinet hot despite the fans
- alias: "Cabinet over-temperature"
  trigger:
    - platform: numeric_state
      entity_id: sensor.cabinet_temperature
      above: 45
      for: "00:10:00"
  action:
    - service: notify.mobile_app_xxx
      data:
        title: "🌡️ Server cabinet hot"
        message: >
          Cabinet at {{ states('sensor.cabinet_temperature') }}°C for 10 min.
          Fans: {{ states('sensor.cabinet_fan_1_rpm') }} /
          {{ states('sensor.cabinet_fan_2_rpm') }} RPM. Check airflow / dust.

# 2) Fan-failure detection — warm enough that a fan SHOULD spin, but RPM ~0
- alias: "Cabinet fan failure"
  trigger:
    - platform: numeric_state
      entity_id: sensor.cabinet_fan_1_rpm
      below: 200
      for: "00:05:00"
    - platform: numeric_state
      entity_id: sensor.cabinet_fan_2_rpm
      below: 200
      for: "00:05:00"
  condition:
    - condition: numeric_state
      entity_id: sensor.cabinet_temperature
      above: 32
  action:
    - service: notify.mobile_app_xxx
      data:
        title: "🪫 Cabinet fan may have failed"
        message: >
          Cabinet {{ states('sensor.cabinet_temperature') }}°C but
          fan1={{ states('sensor.cabinet_fan_1_rpm') }} /
          fan2={{ states('sensor.cabinet_fan_2_rpm') }} RPM.
```

---

## Follow-up checklist

- [ ] Order BOM (fans, ESP32, DS18B20, magnetic brackets, 12 V supply, level shifter).
- [ ] Confirm cabinet top panel is steel + find clear vent area for 2× 120 mm (mind the bookshelf overhang).
- [ ] Breadboard: flash ESPHome over USB, verify temp reads, fan PWM ramps, both tachs report RPM.
- [ ] Decide PWM drive: bare 3.3 V vs level shifter (test the G2's response at low duty).
- [ ] Tune curve thresholds (28/30/45 °C) to real cabinet behaviour.
- [ ] Mount fans (magnet + anti-vib pads) as top exhaust; verify intake path (low/front).
- [ ] Add `secrets.yaml` entries (wifi, api key, ota, ap password).
- [ ] Move config to `config/esphome/`, automations to `config/home-assistant/`; remove SKETCH status.
- [ ] (Optional) Scrape cabinet temp into Prometheus to corroborate the Pi CPU-temp signal.
- [ ] (Optional) Boost override: tie fan speed to the Pi CPU temp if exposed to HA.

## Open questions / decisions

- **Control model:** on-device curve (Model A, chosen) vs HA-owned curve (Model B,
  more flexible but no cooling if HA down). Keeping the curve on the ESP; HA
  supervises. Revisit if a richer multi-input curve is wanted.
- **Single ESP for the whole cabinet** vs per-device — single ESP + cabinet
  ambient sensor chosen for simplicity.
- **Intake:** are the lower/front passive vents sufficient, or is a low intake
  fan also needed? Determine after measuring with exhaust-only.
