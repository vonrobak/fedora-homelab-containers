# iOS Shortcuts Quick Reference - Roborock Voice Commands

**Purpose:** Quick copy-paste reference for creating 9 Roborock cleaning shortcuts
**Platform:** iOS Shortcuts app (iPhone/iPad)
**Sync:** Automatically syncs to Apple Watch

## Shortcut Template

**For each shortcut below:**

1. Open Shortcuts app
2. Tap "+" → Add Action
3. Search "Get Contents of URL"
4. Copy URL from table below
5. Set Method: GET
6. Name shortcut (tap title at top)
7. Add to Siri (record phrase)

## Shortcuts to Create (9 total)

| # | Shortcut Name      | Siri Phrase           | Webhook URL                                                           | Cleans                          |
|---|--------------------|-----------------------|-----------------------------------------------------------------------|---------------------------------|
| 1 | Clean Living Room  | "clean living room"   | `https://ha.patriark.org/api/webhook/clean_living_room`    | Stua only                       |
| 2 | Clean Kitchen      | "clean kitchen"       | `https://ha.patriark.org/api/webhook/clean_kitchen`        | Kjokken only                    |
| 3 | Clean Corridor     | "clean corridor"      | `https://ha.patriark.org/api/webhook/clean_corridor`       | Gang only                       |
| 4 | Clean Hall         | "clean hall"          | `https://ha.patriark.org/api/webhook/clean_hall`           | Hall only                       |
| 5 | Clean Study        | "clean study"         | `https://ha.patriark.org/api/webhook/clean_study`          | Study only                      |
| 6 | Clean Bedroom      | "clean bedroom"       | `https://ha.patriark.org/api/webhook/clean_bedroom`        | Master bedroom only             |
| 7 | Quick Clean        | "quick clean"         | `https://ha.patriark.org/api/webhook/clean_quick`          | Group 1: Stua, Gang, Kjokken    |
| 8 | Extended Clean     | "extended clean"      | `https://ha.patriark.org/api/webhook/clean_extended`       | Group 2: Group 1 + Hall + Study |
| 9 | Clean All Rooms    | "clean all rooms"     | `https://ha.patriark.org/api/webhook/clean_all_rooms`      | All except bathroom (6 rooms)   |

## URL Copy-Paste List

```
https://ha.patriark.org/api/webhook/clean_living_room
https://ha.patriark.org/api/webhook/clean_kitchen
https://ha.patriark.org/api/webhook/clean_corridor
https://ha.patriark.org/api/webhook/clean_hall
https://ha.patriark.org/api/webhook/clean_study
https://ha.patriark.org/api/webhook/clean_bedroom
https://ha.patriark.org/api/webhook/clean_quick
https://ha.patriark.org/api/webhook/clean_extended
https://ha.patriark.org/api/webhook/clean_all_rooms
```

## Detailed Example: Clean Living Room

**Step-by-step:**

1. Open Shortcuts app
2. Tap "+" in top right
3. Tap "Add Action"
4. Search bar: type "get contents"
5. Select "Get Contents of URL"
6. Tap "URL" field
7. Paste: `https://ha.patriark.org/api/webhook/clean_living_room`
8. Verify Method is "GET" (default)
9. Tap shortcut name at top (currently "Shortcut Name")
10. Type: "Clean Living Room"
11. Tap "Done"
12. Tap "⋮" (three dots in top right)
13. Tap "Add to Siri"
14. Tap red record button
15. Say: "clean living room"
16. Tap "Done"
17. Tap "Done" again

**Result:** Shortcut created and accessible via Siri

**Test:** Say "Hey Siri, clean living room"

**Expected:**
- Siri confirms: "Running your shortcut"
- Home Assistant notification: "🤖 Cleaning Living Room"
- Vacuum starts cleaning living room

## Verification Checklist

After creating all 9 shortcuts:

- [ ] All shortcuts visible in Shortcuts app
- [ ] Each shortcut has correct webhook URL
- [ ] Each shortcut has Siri phrase assigned
- [ ] Test each Siri command
- [ ] Verify notifications received
- [ ] Confirm vacuum cleans correct rooms

## Testing Commands

**Individual Rooms:**
```
"Hey Siri, clean living room"  → Stua only
"Hey Siri, clean kitchen"      → Kjokken only
"Hey Siri, clean corridor"     → Gang only
"Hey Siri, clean hall"         → Hall only
"Hey Siri, clean study"        → Study only
"Hey Siri, clean bedroom"      → Bedroom only
```

**Group Commands:**
```
"Hey Siri, quick clean"        → 3 rooms (Stua, Gang, Kjokken)
"Hey Siri, extended clean"     → 5 rooms (quick + Hall + Study)
"Hey Siri, clean all rooms"    → 6 rooms (extended + Bedroom)
```

## Troubleshooting

### Shortcut Runs But Nothing Happens

**Check:**
1. Home Assistant accessible: http://home-assistant.patriark.org
2. Webhook ID matches automation (check automations.yaml)
3. Segment IDs updated in automations (not placeholders)
4. Home Assistant restarted after automation changes

**Test webhook manually:**
```bash
curl -X GET "https://ha.patriark.org/api/webhook/clean_living_room"
```

Should return HTTP 200 OK immediately.

### Siri Says "There's a Problem with the App"

**Causes:**
- Home Assistant not accessible from iPhone's network
- Webhook URL typo
- Certificate validation issue (rare)

**Fix:**
1. Verify HA accessible in Safari: https://ha.patriark.org
2. Re-create shortcut with correct URL
3. Test shortcut manually (tap to run) before adding to Siri

### Vacuum Cleans Wrong Room

**Cause:** Segment IDs in automations.yaml don't match rooms

**Fix:**
1. Developer Tools → Actions → `roborock.get_maps`
2. Verify segment ID for each room name
3. Update automations.yaml with correct mappings
4. Restart Home Assistant
5. Test shortcut again

### Shortcut Works on iPhone But Not Apple Watch

**Solution:** Force sync
1. Open Watch app on iPhone
2. General → Reset Sync Data
3. Wait 5-10 minutes for re-sync
4. Test on watch: "Hey Siri, clean living room"

## Apple Watch Usage

**Access shortcuts on watch:**
1. Raise wrist
2. Say "Hey Siri, clean living room"
   OR
3. Open Shortcuts app on watch
4. Tap shortcut

**Benefits:**
- Hands-free control from anywhere in home
- No need to pull out iPhone
- Instant room-specific cleaning

## Advanced Usage

### Custom Room Groups

Want to create your own custom groups? Add new automations:

**Example: "Clean Main Floor" (Living Room + Kitchen only)**

1. Add automation in automations.yaml:
```yaml
- id: siri_clean_main_floor
  alias: "Siri: Clean Main Floor"
  description: "Custom group: Stua + Kjokken only"

  trigger:
    - platform: webhook
      webhook_id: clean_main_floor
      allowed_methods:
        - POST
        - GET

  action:
    - service: vacuum.send_command
      target:
        entity_id: vacuum.saros_10
      data:
        command: app_segment_clean
        params:
          - segments: [16, 18]  # Stua, Kjokken (replace with your IDs)
            repeat: 1
    - service: notify.mobile_app_iphone_16
      data:
        title: "🤖 Cleaning Main Floor"
        message: "Stua + Kjokken cleaning started."
```

2. Restart Home Assistant

3. Create iOS Shortcut:
   - URL: `https://ha.patriark.org/api/webhook/clean_main_floor`
   - Siri Phrase: "clean main floor"

### Repeat Counts

**Current groups:**
- Individual rooms: 1x repeat (default)
- Quick clean: 1x repeat
- Extended clean: 1x repeat
- Weekend deep clean: **2x repeat** (automation-triggered only)
- All rooms: 1x repeat

**To change repeat count:**
Edit automation in automations.yaml, change `repeat: 1` to `repeat: 2` for deeper cleaning.

## Related Documentation

- [Roborock Room Cleaning Setup](./roborock-room-cleaning-setup.md) - Full implementation guide
- [Home Assistant Automation Catalog](./home-assistant-automations.md) - All 40 automations
- [Implementation Next Steps](../../IMPLEMENTATION-NEXT-STEPS.md) - Overall progress tracker

## Maintenance

**When to update shortcuts:**
- Moving to new home (new room names/IDs)
- Adding/removing rooms
- Changing webhook authentication (if enabled)
- Home Assistant URL changes

**No updates needed for:**
- Changing room cleaning order (handled by Roborock app)
- Adjusting automation conditions (time windows, battery levels)
- Adding new non-cleaning automations

---

**Quick Start:** Copy all 9 URLs above → Create shortcuts in 15 minutes → Start voice-controlling your vacuum!
