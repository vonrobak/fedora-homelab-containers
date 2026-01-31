# Mill Air Purifier Support - Home Assistant Feature Request

**Date:** 2026-01-31
**Purpose:** Feature request template for submitting to Home Assistant Core GitHub
**Target Repository:** https://github.com/home-assistant/core/issues
**Integration:** Mill (`homeassistant/components/mill/`)

---

## Feature Request Template

**Copy the content below and submit as a GitHub issue:**

---

### Title
```
Mill integration: Add support for air purifier devices (GL-Air Purifier M/L)
```

### Description

The Mill integration currently filters out air purifier devices as "unsupported", despite the Mill cloud API providing complete sensor data for these devices. This feature request asks to add air purifier support to the existing Mill integration.

### Problem Statement

Mill manufactures both heaters (currently supported) and air purifiers (currently unsupported) that use the same cloud API. The integration currently only creates entities for `mill.Heater` and `mill.Socket` device types, logging an error for air purifier devices:

```
ERROR (MainThread) [mill] Unsupported device, Air Purifiers {'deviceId': '...', 'customName': 'CompactPro', ...}
```

However, **the Mill API already provides complete sensor data** for air purifiers in the same format as other devices. The integration is filtering them out, not because data is unavailable, but because the device type isn't recognized.

### Evidence: Complete Sensor Data Available

**Real data from Home Assistant logs showing air purifier metrics:**

#### CompactPro (GL-Air Purifier M)
```json
{
  "deviceId": "b47d76d0-a044-4021-89f7-d848ad7b9e01",
  "macAddress": "EC:62:60:07:ED:48",
  "deviceType": {
    "childType": {
      "id": "021fee4b-39f0-4e2a-b3c4-f614c9673a1f",
      "name": "GL-Air Purifier M"
    },
    "parentType": {
      "id": "80c2105f-918c-410b-9046-3c08cba42b35",
      "name": "Air Purifiers"
    }
  },
  "isConnected": true,
  "customName": "CompactPro",
  "lastMetrics": {
    "deviceId": "b47d76d0-a044-4021-89f7-d848ad7b9e01",
    "receivedAt": "2026-01-31T12:33:27.380Z",
    "sentAt": "2026-01-31T12:33:27.000Z",
    "temperature": 19.74,
    "humidity": 35.12,
    "massPm_10": 4,
    "massPm_25": 4,
    "massPm_100": 4,
    "numberPm_05": 348,
    "numberPm_10": 464,
    "numberPm_25": 491,
    "numberPm_50": 502,
    "numberPm_100": 505,
    "eco2": 2147483647,
    "tvoc": 2147483647,
    "controlSignal": 24
  }
}
```

**Note:** `eco2` and `tvoc` values of `2147483647` indicate these sensors are not present on the CompactPro model.

#### Silent Pro (GL-Air Purifier L)
```json
{
  "deviceId": "d3d244dd-8cea-4875-b2ac-3c6925328a38",
  "macAddress": "EC:62:60:09:9F:08",
  "deviceType": {
    "childType": {
      "id": "b6f56a1b-24b5-4239-b800-64e553572204",
      "name": "GL-Air Purifier L"
    },
    "parentType": {
      "id": "80c2105f-918c-410b-9046-3c08cba42b35",
      "name": "Air Purifiers"
    }
  },
  "isConnected": true,
  "customName": "Mill Silent Pro",
  "lastMetrics": {
    "deviceId": "d3d244dd-8cea-4875-b2ac-3c6925328a38",
    "receivedAt": "2026-01-31T12:27:06.243Z",
    "sentAt": "2026-01-31T12:27:04.000Z",
    "temperature": 24.27,
    "humidity": 26.55,
    "massPm_10": 5,
    "massPm_25": 5,
    "massPm_100": 6,
    "numberPm_05": 408,
    "numberPm_10": 520,
    "numberPm_25": 550,
    "numberPm_50": 564,
    "numberPm_100": 566,
    "eco2": 606,
    "tvoc": 136,
    "airQualityIndex": 2,
    "controlSignal": 10
  }
}
```

**Note:** Silent Pro includes eCO2 and TVOC sensors with valid readings.

### Proposed Solution

Add air purifier device support to the Mill integration by:

1. **Create new device class** (or extend existing sensor logic):
   - Check for `parentType.name == "Air Purifiers"` in device type
   - Extract sensor data from `lastMetrics` field (same structure as existing devices)

2. **Add sensor entities** based on device capabilities:

#### CompactPro (GL-Air Purifier M) - 6 sensors
| Metric Key | Entity | Unit | Device Class |
|------------|--------|------|--------------|
| `temperature` | Temperature | °C | `temperature` |
| `humidity` | Humidity | % | `humidity` |
| `massPm_10` | PM 1.0 | µg/m³ | `pm10` |
| `massPm_25` | PM 2.5 | µg/m³ | `pm25` |
| `massPm_100` | PM 10 | µg/m³ | None |
| `numberPm_05` | PM 0.5 Count | count | None |

#### Silent Pro (GL-Air Purifier L) - 8 sensors
All CompactPro sensors PLUS:

| Metric Key | Entity | Unit | Device Class |
|------------|--------|------|--------------|
| `eco2` | Estimated CO₂ | ppm | `co2` |
| `tvoc` | TVOC | ppb | None |
| `airQualityIndex` | Air Quality Index | - | `aqi` |

**Sensor filtering:** Skip `eco2` and `tvoc` sensors if value equals `2147483647` (sentinel value indicating sensor not present).

3. **Device info** already available:
   - MAC address: `macAddress` field
   - Model: `deviceType.childType.name`
   - Name: `customName` field
   - Connection status: `isConnected` field

### Implementation Guidance

**Location:** `homeassistant/components/mill/sensor.py`

**Current code** (lines 157-170):
```python
entities = [
    MillSensor(
        mill_data_coordinator,
        entity_description,
        mill_device,
    )
    for mill_device in mill_data_coordinator.data.values()
    for entity_description in (
        SOCKET_SENSOR_TYPES
        if isinstance(mill_device, mill.Socket)
        else HEATER_SENSOR_TYPES
        if isinstance(mill_device, mill.Heater)
        else SENSOR_TYPES
    )
]
```

**Suggested approach:**

1. **Option A:** Create `AirPurifier` class in `mill` library (requires upstream change)
2. **Option B:** Check device type in raw device data before `mill` library filtering (access `mill_connection.request_controller.all_devices` or equivalent)
3. **Option C:** Add air purifier as new sensor type with attribute-based device type checking

**Air purifier sensor types to add:**
```python
AIR_PURIFIER_SENSOR_TYPES: tuple[SensorEntityDescription, ...] = (
    SensorEntityDescription(
        key="temperature",
        device_class=SensorDeviceClass.TEMPERATURE,
        native_unit_of_measurement=UnitOfTemperature.CELSIUS,
        state_class=SensorStateClass.MEASUREMENT,
    ),
    SensorEntityDescription(
        key="humidity",
        device_class=SensorDeviceClass.HUMIDITY,
        native_unit_of_measurement=PERCENTAGE,
        state_class=SensorStateClass.MEASUREMENT,
    ),
    SensorEntityDescription(
        key="massPm_10",
        device_class=SensorDeviceClass.PM10,
        native_unit_of_measurement=CONCENTRATION_MICROGRAMS_PER_CUBIC_METER,
        state_class=SensorStateClass.MEASUREMENT,
    ),
    SensorEntityDescription(
        key="massPm_25",
        device_class=SensorDeviceClass.PM25,
        native_unit_of_measurement=CONCENTRATION_MICROGRAMS_PER_CUBIC_METER,
        state_class=SensorStateClass.MEASUREMENT,
    ),
    SensorEntityDescription(
        key="massPm_100",
        native_unit_of_measurement=CONCENTRATION_MICROGRAMS_PER_CUBIC_METER,
        state_class=SensorStateClass.MEASUREMENT,
        translation_key="pm_100",
    ),
    SensorEntityDescription(
        key="numberPm_05",
        state_class=SensorStateClass.MEASUREMENT,
        translation_key="pm_05_count",
    ),
    SensorEntityDescription(
        key="eco2",
        device_class=SensorDeviceClass.CO2,
        native_unit_of_measurement=CONCENTRATION_PARTS_PER_MILLION,
        state_class=SensorStateClass.MEASUREMENT,
    ),
    SensorEntityDescription(
        key="tvoc",
        native_unit_of_measurement=CONCENTRATION_PARTS_PER_BILLION,
        state_class=SensorStateClass.MEASUREMENT,
        translation_key="tvoc",
    ),
    SensorEntityDescription(
        key="airQualityIndex",
        device_class=SensorDeviceClass.AQI,
        state_class=SensorStateClass.MEASUREMENT,
    ),
)
```

### Use Cases

Air purifier sensor data enables valuable automations:

**Air quality monitoring:**
```yaml
- trigger:
    - platform: numeric_state
      entity_id: sensor.silent_pro_eco2
      above: 1200
  action:
    - service: notify.mobile_app
      data:
        message: "High CO₂ detected ({{ states('sensor.silent_pro_eco2') }} ppm). Consider ventilation."
```

**PM 2.5 alerts:**
```yaml
- trigger:
    - platform: numeric_state
      entity_id: sensor.compactpro_mass_pm_25
      above: 35  # WHO 24-hour guideline
  action:
    - service: notify.mobile_app
      data:
        message: "Poor air quality - PM 2.5: {{ states('sensor.compactpro_mass_pm_25') }} µg/m³"
```

**Dashboard integration:**
- Real-time air quality monitoring across multiple rooms
- Historical data tracking (PM 2.5 trends, CO₂ patterns)
- Air quality index visualization

### Affected Users

Mill sells air purifiers in Nordic markets (Norway, Sweden, Denmark) alongside their heaters. Users who have both Mill heaters and air purifiers expect both to be supported by the same integration.

**Current workaround:** None available without creating custom components or REST sensors with hardcoded credentials.

### Additional Information

**Mill Product Line:**
- Heaters: ✅ Supported (oil-filled, panel, convection heaters)
- Smart Sockets: ✅ Supported
- Air Purifiers: ❌ **Not supported** (this feature request)
  - GL-Air Purifier M (CompactPro)
  - GL-Air Purifier L (Silent Pro)

**Mill API:** Same cloud API (`api.millheat.com`) for all device types

**Update frequency:** 30 seconds (same as heaters, already implemented)

**Dependencies:**
- Mill library: `millheater==0.14.1` (may need update to add air purifier device class)
- Alternative: Access raw device data before library filtering

### Testing Availability

I can test this feature with two Mill air purifiers:
- CompactPro (GL-Air Purifier M) - 6 sensors
- Silent Pro (GL-Air Purifier L) - 8 sensors (includes eCO2/TVOC)

Both devices are connected to Mill cloud account and visible in Mill mobile app. Logs show complete sensor data being received by Home Assistant but filtered out.

### References

**Current Mill integration:**
- Code: https://github.com/home-assistant/core/tree/dev/homeassistant/components/mill
- Documentation: https://www.home-assistant.io/integrations/mill
- Mill library: https://github.com/Danielhiversen/pymill

**Relevant sensor device classes:**
- `SensorDeviceClass.TEMPERATURE`
- `SensorDeviceClass.HUMIDITY`
- `SensorDeviceClass.PM10`
- `SensorDeviceClass.PM25`
- `SensorDeviceClass.CO2`
- `SensorDeviceClass.AQI`

**Similar integrations with air purifier support:**
- Xiaomi Mi Air Purifier (`xiaomi_miio`)
- Philips Air Purifier (`philips_js`)
- Dyson (`dyson`)

### Summary

The Mill API already provides complete air purifier sensor data in the same format as heaters and sockets. This feature request asks to stop filtering out air purifier devices and create sensor entities for the metrics already available in `lastMetrics` field.

**Benefit:** Users with Mill air purifiers gain native Home Assistant integration with no additional API calls or infrastructure changes required.

---

## Submission Instructions

### Step 1: Verify GitHub Account

Ensure you have a GitHub account: https://github.com/signup

### Step 2: Navigate to Issues

Go to: https://github.com/home-assistant/core/issues

### Step 3: Search Existing Issues

Before creating, search for existing issues:
- Search: "mill air purifier"
- Check if someone already requested this feature

**If found:** Add a comment with your supporting evidence (logs, device models)

**If not found:** Continue to create new issue

### Step 4: Create New Issue

1. Click "New issue" button
2. Select "Feature request" template
3. Copy the feature request template above
4. Paste into issue description
5. Add any additional context if needed

### Step 5: Add Labels (if permitted)

Suggested labels:
- `integration: mill`
- `new-feature`

### Step 6: Submit

Click "Submit new issue"

### Step 7: Monitor Issue

- GitHub will notify you of responses via email
- Respond to any developer questions
- Provide additional testing/logs if requested

## Alternative: Submit to Mill Library

If developers prefer to add air purifier support in the Mill library first:

**Repository:** https://github.com/Danielhiversen/pymill

**Process:**
1. Create issue in pymill repository
2. Suggest adding `AirPurifier` device class
3. Reference Home Assistant integration waiting for upstream support

**Then:** Link pymill issue in Home Assistant feature request

## Expected Timeline

**Typical feature request timeline:**
- **Triage:** 1-7 days (developers review and label)
- **Discussion:** 1-4 weeks (clarifying questions, approach agreement)
- **Implementation:** Depends on:
  - Developer availability
  - Complexity (this should be straightforward)
  - Whether upstream library changes needed
- **Release:** Next Home Assistant release after PR merge

**Realistic estimate:** 1-3 months from submission to release

**Note:** You can speed this up by:
1. Offering to test implementation
2. Providing detailed technical evidence (already done above)
3. Responding quickly to developer questions

## Success Criteria

**Feature request considered successful when:**
- ✅ Issue acknowledged by Home Assistant team
- ✅ Labeled with `integration: mill` and `new-feature`
- ✅ Developer assigned or community member volunteers
- ✅ PR created implementing air purifier support
- ✅ PR merged to `dev` branch
- ✅ Included in upcoming Home Assistant release notes

**Then:**
- Update Home Assistant to version with fix
- Mill air purifier entities appear automatically
- No custom components or workarounds needed

## Fallback: Community PR

If no developer picks this up within 4-8 weeks, you could:

1. Learn Python/Home Assistant development
2. Fork `home-assistant/core`
3. Implement feature yourself following contribution guidelines
4. Submit PR with feature implementation

**Resources for contributing:**
- https://developers.home-assistant.io/
- https://developers.home-assistant.io/docs/development_environment

**Note:** This requires significant time investment but guarantees the feature gets implemented.

## Status Tracking

**Update this section when submitting:**

- [ ] GitHub issue created
- [ ] Issue number: `#______`
- [ ] Issue URL: `https://github.com/home-assistant/core/issues/______`
- [ ] Date submitted: `YYYY-MM-DD`
- [ ] Developer response received: `YYYY-MM-DD`
- [ ] PR created: `#______`
- [ ] PR merged: `YYYY-MM-DD`
- [ ] Included in release: `YYYY.MM`
- [ ] Feature available in my HA instance: `YYYY-MM-DD`

---

## Related Documentation

**Internal references:**
- Implementation attempt log: `docs/98-journals/2026-01-31-learning-journey-completion.md`
- Roborock completion: `docs/ROBOROCK-IMPLEMENTATION-COMPLETE.md`
- Evidence in HA logs: `podman logs home-assistant | grep "Unsupported device, Air Purifiers"`

**External references:**
- Mill website: https://www.millheat.com/
- Mill app: iOS/Android "Mill" app by Mill International AS
- Support: https://www.millheat.com/support/

---

**Created:** 2026-01-31
**Status:** Ready for submission
**Confidence:** High - Complete technical evidence provided
**Impact:** Medium - Benefits all Mill air purifier owners using Home Assistant
