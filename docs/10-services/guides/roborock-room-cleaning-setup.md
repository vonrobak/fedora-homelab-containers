# Roborock Room-Specific Cleaning - Implementation Guide

**Created:** 2026-01-31
**Service:** Home Assistant + Roborock Saros 10
**Purpose:** Step-by-step guide to activate room-specific cleaning automations

## Overview

13 new Roborock automations have been added to Home Assistant, providing:
- Context-aware smart cleaning (weekday/weekend differentiation)
- Voice-controlled room-specific cleaning via Siri
- State-based robot vision lighting
- Battery guards and safety controls

**Current Status:** Automations configured but require room segment IDs to function.

## Prerequisites

- ✅ Roborock Saros 10 integrated in Home Assistant
- ✅ All rooms named in Roborock mobile app
- ✅ iPhone with iOS Shortcuts app installed
- ✅ Home Assistant mobile app installed and authenticated

## Step 1: Get Room Segment IDs

Room segment IDs are required for all room-specific cleaning commands. These IDs tell the vacuum which areas to clean.

### Procedure

1. **Open Home Assistant Web UI**
   - Navigate to http://home-assistant.patriark.org or local IP

2. **Open Developer Tools**
   - Left sidebar → Developer Tools (wrench icon)
   - Select "Actions" tab

3. **Call `roborock.get_maps` Action**
   - In the "Action" field, type: `roborock.get_maps`
   - In "Target" section, select: `vacuum.saros_10`
   - Click "Perform Action" button

4. **Copy Response**
   - Response appears at bottom of screen
   - Look for section containing room names and segment IDs
   - Example format:
     ```json
     {
       "rooms": {
         "16": {"name": "Stua"},
         "17": {"name": "Gang"},
         "18": {"name": "Kjokken"},
         "19": {"name": "Hall"},
         "20": {"name": "Study"},
         "21": {"name": "Bedroom"},
         "22": {"name": "Bathroom"}
       }
     }
     ```

5. **Record Segment IDs**
   Create a mapping table:
   | Room Name    | Segment ID | Norwegian Name |
   |--------------|------------|----------------|
   | Living Room  | ?          | Stua           |
   | Corridor     | ?          | Gang           |
   | Kitchen      | ?          | Kjokken        |
   | Hall         | ?          | Hall           |
   | Study        | ?          | Study          |
   | Bedroom      | ?          | Bedroom        |
   | Bathroom     | ?          | Bathroom       |

## Step 2: Update Automation Segment IDs

### File to Edit
`/home/patriark/containers/config/home-assistant/automations.yaml`

### Search & Replace

**Find all instances of placeholders:**
- `ID_STUA` → Replace with actual living room segment ID (e.g., `16`)
- `ID_GANG` → Replace with corridor segment ID (e.g., `17`)
- `ID_KJOKKEN` → Replace with kitchen segment ID (e.g., `18`)
- `ID_HALL` → Replace with hall segment ID (e.g., `19`)
- `ID_STUDY` → Replace with study segment ID (e.g., `20`)
- `ID_BEDROOM` → Replace with bedroom segment ID (e.g., `21`)

### Affected Automations (13 total)

**Context-Aware Cleaning (2):**
- `smart_clean_weekday` - Lines ~380-410
- `smart_clean_weekend` - Lines ~415-445

**Individual Room Commands (6):**
- `siri_clean_living_room` - Lines ~460-480
- `siri_clean_kitchen` - Lines ~485-505
- `siri_clean_corridor` - Lines ~510-530
- `siri_clean_hall` - Lines ~535-555
- `siri_clean_study` - Lines ~560-580
- `siri_clean_bedroom` - Lines ~585-605

**Group Commands (3):**
- `siri_clean_quick` - Lines ~610-630 (Group 1: Stua, Gang, Kjokken)
- `siri_clean_extended` - Lines ~635-655 (Group 2: Group 1 + Hall + Study)
- `siri_clean_all_rooms` - Lines ~660-680 (All except bathroom)

### Example Replacement

**Before:**
```yaml
- service: vacuum.send_command
  target:
    entity_id: vacuum.saros_10
  data:
    command: app_segment_clean
    params:
      - segments: [ID_STUA, ID_GANG, ID_KJOKKEN]
        repeat: 1
```

**After (assuming Stua=16, Gang=17, Kjokken=18):**
```yaml
- service: vacuum.send_command
  target:
    entity_id: vacuum.saros_10
  data:
    command: app_segment_clean
    params:
      - segments: [16, 17, 18]
        repeat: 1
```

### Validation

**Search for remaining placeholders:**
```bash
grep -n "ID_STUA\|ID_GANG\|ID_KJOKKEN\|ID_HALL\|ID_STUDY\|ID_BEDROOM" \
  ~/containers/config/home-assistant/automations.yaml
```

**Expected result:** No matches (all placeholders replaced)

## Step 3: Restart Home Assistant

```bash
# Check configuration validity first
podman exec home-assistant python -m homeassistant --script check_config -c /config

# If valid, restart
podman restart home-assistant

# Monitor logs for errors
podman logs -f home-assistant
```

**Watch for:**
- ✅ "Home Assistant is running" message
- ❌ YAML syntax errors (automation IDs, indentation)
- ✅ "Loaded 37 automations" (24 existing + 13 new)

## Step 4: Create iOS Shortcuts

### Webhook URL Format
```
https://ha.patriark.org/api/webhook/<webhook_id>
```

### Shortcuts to Create (9 total)

| Shortcut Name         | Webhook ID          | Voice Command                    |
|-----------------------|---------------------|----------------------------------|
| Clean Living Room     | clean_living_room   | "Hey Siri, clean living room"    |
| Clean Kitchen         | clean_kitchen       | "Hey Siri, clean kitchen"        |
| Clean Corridor        | clean_corridor      | "Hey Siri, clean corridor"       |
| Clean Hall            | clean_hall          | "Hey Siri, clean hall"           |
| Clean Study           | clean_study         | "Hey Siri, clean study"          |
| Clean Bedroom         | clean_bedroom       | "Hey Siri, clean bedroom"        |
| Quick Clean           | clean_quick         | "Hey Siri, quick clean"          |
| Extended Clean        | clean_extended      | "Hey Siri, extended clean"       |
| Clean All Rooms       | clean_all_rooms     | "Hey Siri, clean all rooms"      |

### Shortcut Creation Procedure

For each shortcut:

1. **Open Shortcuts App** (iPhone/iPad)

2. **Create New Shortcut**
   - Tap "+" button → "Add Action"

3. **Add "Get Contents of URL" Action**
   - Search for "Get Contents of URL"
   - Configure:
     - **URL:** `https://ha.patriark.org/api/webhook/<webhook_id>`
     - **Method:** GET
     - **Headers:** None needed (webhook IDs are public in this context)

4. **Name the Shortcut**
   - Tap shortcut name at top
   - Enter descriptive name (e.g., "Clean Living Room")

5. **Test Shortcut**
   - Tap "Play" button
   - Verify notification appears from Home Assistant
   - Check vacuum starts cleaning correct room

6. **Add to Siri**
   - Tap "⋮" (three dots) → "Add to Siri"
   - Record phrase (e.g., "clean living room")
   - Tap "Done"

7. **Sync to Apple Watch**
   - Shortcuts automatically sync to paired Apple Watch
   - Accessible via Shortcuts app on watch

### Example Shortcut Configuration

**Shortcut Name:** Clean Living Room

**Action 1: Get Contents of URL**
```
URL: https://ha.patriark.org/api/webhook/clean_living_room
Method: GET
```

**Siri Phrase:** "clean living room"

**Expected Behavior:**
1. Say "Hey Siri, clean living room"
2. Siri confirms: "Running your shortcut"
3. Home Assistant sends notification: "🤖 Cleaning Living Room - Stua cleaning started."
4. Vacuum begins cleaning living room segment only

## Step 5: Test Automations

### Manual Testing

#### Test 1: Individual Room Cleaning
```
Say: "Hey Siri, clean kitchen"
Expected:
- iOS notification received
- Vacuum undocks (if docked)
- Vacuum navigates to kitchen
- Vacuum cleans kitchen only
- Vacuum returns to dock when complete
```

#### Test 2: Group Cleaning
```
Say: "Hey Siri, quick clean"
Expected:
- Vacuum cleans Stua, Gang, Kjokken (in order)
- Skips all other rooms
- Single pass cleaning
```

#### Test 3: State-Based Lighting
```
Trigger: Start cleaning manually or via Siri
Expected:
- Lights turn on when binary_sensor.saros_10_cleaning becomes "on"
- Energize scenes activated (bright, cool lighting)
- Lights turn off when robot docks
```

### Automatic Trigger Testing

#### Test 4: Weekday Smart Clean
```
Conditions:
- Current day: Mon-Fri
- Time: Between 07:00-23:00
- Activate Work Focus on iPhone
- Leave home (binary_sensor.iphone_home becomes "off")
- Wait 30 minutes

Expected:
- Automation triggers after 30 min delay
- Vacuum cleans Group 1 (Stua, Gang, Kjokken)
- iOS notification: "🤖 Weekday Quick Clean Started"
- Single pass cleaning
```

#### Test 5: Weekend Smart Clean
```
Conditions:
- Current day: Sat-Sun
- Time: Between 07:00-23:00
- Leave home (binary_sensor.iphone_home becomes "off")
- Wait 3 minutes

Expected:
- Automation triggers after 3 min delay
- Vacuum cleans Group 2 (Stua, Gang, Kjokken, Hall, Study)
- iOS notification: "🤖 Weekend Deep Clean Started"
- 2x repeat cleaning (deep clean)
```

#### Test 6: Battery Guard
```
Trigger: Manually start cleaning, then simulate low battery
(Cannot easily test without modifying battery sensor)

Expected Behavior:
- If battery drops below 20% during cleaning
- Automation sends vacuum to dock
- Notification: "⚠️ Vacuum Low Battery"
```

### Verification Checklist

- [ ] All 9 Siri commands tested and working
- [ ] Notifications received on iPhone for each command
- [ ] Vacuum cleans correct rooms for each command
- [ ] Group 1 (quick clean) cleans 3 rooms only
- [ ] Group 2 (extended clean) cleans 5 rooms only
- [ ] Full house clean works (6 rooms, excludes bathroom)
- [ ] Lights turn on when cleaning starts (non-scheduled)
- [ ] Lights turn off when robot docks
- [ ] Weekday smart clean triggers correctly (Work Focus + 30 min away)
- [ ] Weekend smart clean triggers correctly (3 min away, no Work Focus)
- [ ] Battery guard prevents cleaning continuation below 20%

## Troubleshooting

### Automation Not Triggering

**Check Home Assistant Automation Traces:**
1. Settings → Automations & Scenes
2. Find automation (e.g., "Smart Clean: Weekday Quick")
3. Click automation → "Traces" tab
4. View last run attempts and why conditions failed

**Common Issues:**
- Battery below 30% (check `sensor.saros_10_battery`)
- Robot not docked (check `vacuum.saros_10` state)
- Outside time window (07:00-23:00 restriction)
- Work Focus not detected (weekday automation only)
- Already cleaning (prevents duplicate triggers)

### Webhook Not Working

**Test Webhook Manually:**
```bash
curl -X GET "https://ha.patriark.org/api/webhook/clean_living_room"
```

**Expected Response:** HTTP 200 OK (no body returned)

**Common Issues:**
- Typo in webhook ID (check automations.yaml webhook_id field)
- Shortcut using wrong URL
- Network connectivity (test from same WiFi as iPhone)
- Home Assistant not accessible from external URL

### Vacuum Cleans Wrong Room

**Cause:** Incorrect segment ID mapping

**Fix:**
1. Re-run `roborock.get_maps` to verify IDs
2. Check which segment ID corresponds to which room name
3. Update automations.yaml with correct mappings
4. Restart Home Assistant

### Lights Don't Turn On/Off

**State-Based Lighting Issues:**
- Check if `binary_sensor.saros_10_cleaning` entity exists
- Check if lights were already on (condition prevents re-trigger)
- Verify scenes exist: `scene.stua_energize`, `scene.kjokken_energize`, `scene.gang_energize`

**Scheduled Lighting Issues:**
- Time-based automations (Mon/Wed 3am) still exist and work
- State-based automations supplement scheduled ones, don't replace

## Automation Reference

### Smart Cleaning Groups

**Group 1 - Quick Clean (Weekdays):**
- Stua (Living Room)
- Gang (Corridor)
- Kjokken (Kitchen)
- **Trigger:** Work Focus + Away 30 min (Mon-Fri)
- **Repeat:** 1x pass
- **Purpose:** Fast clean of high-traffic areas

**Group 2 - Extended Clean (Weekends):**
- Stua, Gang, Kjokken (Group 1)
- Hall
- Study
- **Trigger:** Away 3 min (Sat-Sun)
- **Repeat:** 2x passes (deep clean)
- **Purpose:** Thorough weekend cleaning

**Group 3 - Full House (Manual Only):**
- All Group 2 rooms
- Bedroom
- **Excludes:** Bathroom (trap risk)
- **Trigger:** Siri command only (user home to untrap)
- **Repeat:** 1x pass

### Exclusion Logic

**Why exclude bedroom/bathroom when away?**
- Risk of robot getting trapped under furniture
- User not home to physically free robot
- Bedroom cleaning only safe when user can supervise

**When is bedroom cleaning allowed?**
- Manual Siri command: "Hey Siri, clean bedroom" (user present)
- Manual Siri command: "Hey Siri, clean all rooms" (user present)
- Scheduled Roborock app cleans (user set schedule, assumed prepped)

### Conflict Management

**Existing Roborock App Schedules:**
- **Monday 3am:** Quiet wash all rooms (except bathroom)
- **Wednesday 3am:** Quiet wash all rooms (except bathroom)
- **Friday 10am:** Deep clean all rooms (except bathroom)

**Home Assistant Automations:**
- Trigger on presence/focus events ONLY
- No time-based triggers (except Mon/Wed lighting support)
- **No conflicts:** App schedules run on fixed times, HA automations run on state changes

**Priority Order:**
1. Manual Siri commands (immediate execution)
2. Roborock app schedules (fixed times)
3. HA smart automations (presence-based)

## Maintenance

### Weekly Checks
- [ ] Review automation traces for failed triggers
- [ ] Verify battery guard prevented low-battery cleaning continuation
- [ ] Check if smart cleaning triggered as expected (weekday/weekend)

### Monthly Reviews
- [ ] Analyze which Siri commands used most frequently
- [ ] Adjust Group 1/2 room assignments if usage patterns change
- [ ] Review cleaning schedule conflicts (if any)

### Automation Improvements
- Add more rooms to groups as needed
- Create custom groups for specific scenarios (e.g., "party mode" = common areas only)
- Adjust trigger delays if false positives/negatives occur
- Add more conditions (e.g., "only if lights were off before cleaning")

## Related Documentation

- [Home Assistant Automation Catalog](./home-assistant-automations.md) - Complete automation reference
- [Learning Journey Journal](../../98-journals/2026-01-31-learning-journey-completion.md) - Implementation summary
- [Roborock Room Cleaning - HA Community](https://community.home-assistant.io/t/roborock-room-cleaning/589015) - Community discussion
- [Control Roborock with Siri via HA](https://noahtallen.com/2025/05/18/controlling-roborock-vacuums-with-siri-nfc-via-home-assistant/) - External guide

## Support

**Home Assistant Logs:**
```bash
podman logs -f home-assistant | grep -i roborock
```

**Automation Debugging:**
- Developer Tools → States → Search for `automation.smart_clean_weekday`
- View last_triggered timestamp, current state, attributes

**Roborock Integration Logs:**
```bash
podman logs home-assistant 2>&1 | grep "roborock"
```

**Community Resources:**
- [Home Assistant Community Forums](https://community.home-assistant.io/)
- [Roborock Integration GitHub](https://github.com/humbertogontijo/homeassistant-roborock)
