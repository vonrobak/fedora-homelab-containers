# Home Assistant Presence Detection Fix

**Date:** 2026-02-09
**Scope:** Home Assistant automations (presence-based lighting)
**Trigger:** False "Welcome Home" automation triggers while user was away

## Problem

After leaving home at ~16:25, the "Welcome Home" automation fired 4 times between 17:36-18:08 while the user was actually away. Only the final trigger at 18:26 was a real arrival. The "Away Mode" departure automation worked correctly (once).

## Root Cause Analysis

The `person.bjorn_robak` entity tracks two device trackers:
- `device_tracker.iphone_16` (iPhone 16 -- carried everywhere)
- `device_tracker.patriark_ipad_pro` (iPad Pro -- usually stays home)

HA's person entity uses a **"most recently updated tracker wins"** algorithm. When the user left home with the iPhone, the iPad (still at home) periodically sent location updates reporting `home`. Each iPad update overrode the iPhone's `not_home` state for the person entity, causing rapid state flapping:

```
16:25  iPhone -> not_home  => person = not_home  (correct departure)
17:36  iPad   -> home      => person = home      (false arrival #1)
17:39  iPhone -> not_home  => person = not_home  (corrected)
17:46  iPad   -> home      => person = home      (false arrival #2)
...pattern repeats 4 times until actual arrival at 18:26
```

The arrival automation had **no `for:` debounce** -- it fired instantly on every `not_home -> home` transition. The departure automation's `for: 15 minutes` clause happened to work because the iPad went quiet for 71 minutes after departure, but this was luck -- if the iPad had updated within 15 minutes, it would have reset the timer.

**Contrast with UniFi presence sensor:** `binary_sensor.iphone_home` (WiFi-based via UnPoller -> Prometheus) showed only two transitions all day: off at 16:23, on at 18:32. Zero flapping.

## Fixes Applied

### 1. Arrival automation (`arrival_lights_on`)

- Added `for: minutes: 2` debounce to absorb brief state flapping
- Added condition requiring `device_tracker.iphone_16` specifically to be `home`
- The person entity trigger is kept (preserves iPad's role in travel detection) but the iPhone condition filters out iPad-only state changes

**Verification against today's data:** All 4 false triggers would have been blocked (iPhone was `not_home` during each). Real arrival at 18:26 would fire at 18:28 (2-min delay).

### 2. Departure automation (`departure_lights_off`)

- Changed trigger from `person.bjorn_robak` to `device_tracker.iphone_16` directly
- The iPad can no longer reset the 15-minute departure timer
- With today's data: departure would have fired reliably at 16:40 regardless of iPad activity

### 3. `light.gang` -> `light.hallway` (6 references)

The Hue bridge room "Gang" created scenes as `scene.gang_*` but the light group entity as `light.hallway`. All automations referenced the non-existent `light.gang`, causing corridor brightness overrides to silently fail in 5 automations (weekday/weekend afternoon relax, arrival relax, robot vision restore, sunset transition). This bug existed since at least 2026-02-07 per older log entries.

### 4. Mill integration log suppression

Set `mill` logger to `critical` in configuration.yaml to suppress the "Unsupported device" error for the CompactPro air purifier. This was firing every 30 seconds (~2,880 errors/day) due to the upstream Mill integration not supporting air purifier devices. The setting change does not affect the 3 Mill heaters or the air quality sensor which continue to work normally.

## Design Decisions

**Why keep iPad in person entity?** The iPad serves as a reliable indicator for long-term travel (work trips). Removing it would lose that signal. The iPhone-specific condition on arrival is a targeted fix that preserves the iPad's travel detection role.

**Why not switch to UniFi as primary trigger?** The UniFi sensor had a ~6 minute lag behind GPS (18:32 vs 18:26) due to the polling chain (WiFi connect -> UnPoller scrape -> Prometheus scrape -> HA REST sensor poll). Using it as primary trigger would add ~8 minutes total delay. The person entity + iPhone condition gives ~2 minute delay.

**Why not version-control HA config files?** `automations.yaml` contains 16 webhook IDs that function as bearer tokens for triggering automations (vacuum, lights, departure mode). HA webhooks bypass authentication by design, and HA uses native auth (not Authelia) because companion apps require direct access. BTRFS snapshots provide change history as an alternative.

## Other Observations

- **Morning lights issue:** After 03:00 container update, 5-hour gap in person entity history (03:00-08:02). The iOS app had trouble reconnecting after the HA version update. The weekend 09:30 energize automation likely fired but notifications weren't delivered due to app connectivity issues.
- **`light.hallway` (Gang corridor):** Four "ganglys" bulbs controlled as a Hue room group. The entity naming mismatch (scenes use Hue room name "Gang", lights use HA-generated "hallway") is a Hue integration quirk worth noting for future automation work.
