# Apple Ecosystem Integration - Quick Reference

**Created:** 2026-01-30
**Status:** Active Setup Guide
**Devices:** iPhone 16, iPad Pro M1, Apple Watch (MWWE2DH/A), MacBook Air M2

---

## Overview

**What's Integrated:**
- ✅ Siri voice commands (7 commands)
- ✅ Apple Watch complications (one-tap control)
- ✅ Focus Mode auto-detection (Work, Sleep)
- ✅ Remote access (WireGuard VPN + Cellular)
- ✅ Actionable notifications (coming soon)

---

## Siri Voice Commands

| Command | What It Does | Example Phrase |
|---------|--------------|----------------|
| **Movie Mode** | Activate cozy ambient lighting | "Hey Siri, movie mode" |
| **Good Night** | Nightlight all rooms | "Hey Siri, good night" |
| **Good Morning** | Energize all rooms | "Hey Siri, good morning" |
| **Leaving Home** | Lights off + start vacuum | "Hey Siri, I'm leaving" |
| **Arriving Home** | Time-aware lighting | "Hey Siri, I'm home" |
| **Work Focus** | Productivity mode | "Hey Siri, work mode" |
| **Lights Off** | Turn off all lights | "Hey Siri, lights off" |

---

## Webhook URLs

**Base URL:** `https://ha.patriark.org/api/webhook/`

**Webhook IDs:**
- `movie_mode` - Movie Mode
- `good_night` - Good Night
- `good_morning` - Good Morning
- `leaving_home` - Leaving Home
- `arriving_home` - Arriving Home
- `focus_work` - Work Focus
- `lights_off` - All Lights Off

**Full URL Example:**
```
https://ha.patriark.org/api/webhook/movie_mode
```

---

## iOS Shortcuts Setup

### Creating a Shortcut (Template)

1. **Shortcuts app** → **+** (New Shortcut)
2. **Add Action** → Search "Get Contents of URL"
3. **Configure:**
   - **URL:** `https://ha.patriark.org/api/webhook/WEBHOOK_ID`
   - **Method:** GET
4. **Name the shortcut** (e.g., "Movie Mode")
5. **Add to Siri:** Record voice phrase
6. **Done!**

### Quick Import (All Shortcuts)

**Instead of creating manually, use this method:**

1. **MacBook Air** → Create shortcut configuration files:

```bash
# Create shortcuts directory
mkdir -p ~/HA-Shortcuts

# Create Movie Mode shortcut URL scheme
echo "shortcuts://run-shortcut?name=Movie%20Mode&input=text&text=https://ha.patriark.org/api/webhook/movie_mode" > ~/HA-Shortcuts/movie_mode.txt

# Repeat for each command...
```

2. **AirDrop** shortcuts from MacBook to iPhone
3. **Import** in Shortcuts app

---

## Apple Watch Integration

### Method 1: Shortcuts App on Watch

1. **Open Shortcuts app** on Apple Watch
2. **Shortcuts auto-sync** from iPhone
3. **Tap any shortcut** → Instant execution
4. **Or use Siri:** Raise wrist → "Hey Siri, movie mode"

### Method 2: Watch Face Complications

1. **Long press watch face** → **Edit**
2. **Tap complication slot**
3. **Select "Shortcuts"** → Choose shortcut
4. **Done!** → One-tap from watch face

**Recommended Complications:**
- **Top:** Good Morning
- **Center:** Movie Mode
- **Bottom:** Good Night
- **Corners:** Lights Off, Work Focus

---

## Focus Mode Auto-Detection

**How It Works:**
- Enable **Sleep Focus** on iPhone/Watch → HA detects it → Nightlight activates automatically
- Enable **Work Focus** → Productivity lighting + vacuum pauses
- **No manual shortcuts needed** - completely automatic!

**Setup:**

1. **iPhone → Home Assistant App → Settings → Companion App → Sensors**
   - ✅ Enable **"Focus"** sensor
   - ✅ Enable **"Activity"** sensor

2. **Reload automations in HA** (Settings → Automations → Reload)

3. **Test:**
   - iPhone → Settings → Focus → Sleep → Enable
   - Wait 5-10 seconds → Nightlight should activate
   - Check HA notification on iPhone

---

## Remote Access (Outside Home)

### Via WireGuard VPN

**All shortcuts work remotely through WireGuard VPN!**

1. **Enable WireGuard** on iPhone/iPad
2. **Connect to VPN** (192.168.100.0/24)
3. **Use shortcuts normally** - HA accessible at `https://ha.patriark.org`

**Cellular Data Only (iPad/Watch):**
- Shortcuts work **without VPN** if using external URL
- Authelia authentication required (YubiKey/TOTP)
- Slower than VPN (goes through Traefik → Authelia → HA)

---

## Testing Checklist

### Voice Commands (Siri)

- [ ] "Hey Siri, movie mode" → Cozy ambient lighting
- [ ] "Hey Siri, good night" → Nightlight all rooms
- [ ] "Hey Siri, good morning" → Energize all rooms
- [ ] "Hey Siri, I'm leaving" → Lights off + vacuum starts
- [ ] "Hey Siri, I'm home" → Time-aware lighting
- [ ] "Hey Siri, work mode" → Productivity lighting
- [ ] "Hey Siri, lights off" → All lights off

### Apple Watch

- [ ] Shortcuts app shows all 7 shortcuts
- [ ] Tap "Movie Mode" from watch → Works
- [ ] Siri from watch → "Hey Siri, good night" → Works
- [ ] Watch face complication → One-tap activation

### Focus Mode Auto-Detection

- [ ] Enable Sleep Focus → Nightlight activates (10s delay)
- [ ] Enable Work Focus → Productivity mode + vacuum pauses
- [ ] iPhone notification appears confirming action

### Remote Access

- [ ] WireGuard VPN enabled → Shortcuts work from anywhere
- [ ] Cellular only (iPad) → Shortcuts work (slower)
- [ ] From outside home network → Voice commands trigger HA

---

## Troubleshooting

### Shortcut Fails (No Response)

**Check:**
1. **HA reachable?** → Open HA app, verify connection
2. **Webhook URL correct?** → Check for typos
3. **Automation loaded?** → HA → Settings → Automations → Verify webhook automation exists
4. **Logs:** HA → Settings → System → Logs → Search "webhook"

**Common Issues:**
- ❌ Typo in webhook ID (e.g., `movie_mode` vs `moviemode`)
- ❌ Automations not reloaded after adding new ones
- ❌ Network issue (check WireGuard VPN if outside home)

### Focus Mode Not Detected

**Check:**
1. **Companion App sensors enabled?** → HA App → Settings → Sensors → "Focus" enabled
2. **Sensor exists in HA?** → Developer Tools → States → Search "sensor.iphone_focus"
3. **Focus actually enabled?** → iPhone → Settings → Focus → Verify active
4. **Automation loaded?** → HA → Settings → Automations → Search "Focus Mode"

**Sensor Value:**
- `sensor.iphone_focus` = "Sleep" → Sleep Focus active
- `sensor.iphone_focus` = "Work" → Work Focus active
- `sensor.iphone_focus` = "unavailable" → Sensor not reporting

### Apple Watch Shortcuts Not Syncing

**Fix:**
1. **iPhone → Shortcuts app** → Verify shortcuts exist
2. **Apple Watch → Shortcuts app** → Force quit app (hold side button → swipe Shortcuts)
3. **Reopen Shortcuts on watch** → Should sync
4. **If persistent:** Unpair/re-pair watch (last resort)

---

## Advanced: Actionable Notifications

**Coming in Phase 4C** - notifications with action buttons:

**Example:**
- Vacuum stuck → Notification on watch: **[Help Vacuum]** | **[Ignore]**
- Tap **[Help Vacuum]** → HA sends resume command
- **No need to open app!**

---

## Performance Tips

### Optimize Webhook Response Time

**Current:** ~200-500ms (Authelia → HA → Automation)

**Optimization:**
1. **Local network:** ~50-100ms (skip Authelia when on VLAN1)
2. **WireGuard VPN:** ~100-200ms (direct tunnel)
3. **Cellular:** ~500-1000ms (goes through Traefik)

**Recommendation:** Use WireGuard VPN when outside home for faster response.

### Reduce Notification Spam

**Current:** Every webhook sends iPhone notification

**Disable if desired:**
```yaml
# In automation, comment out notify service:
# - service: notify.mobile_app_iphone
#   data:
#     title: "Movie Mode 🎬"
#     message: "Cozy ambient lighting activated."
```

---

## Security Notes

**Authentication:**
- ✅ **Webhooks require HTTPS** (TLS 1.2+)
- ✅ **Traefik reverse proxy** enforces rate limiting
- ✅ **CrowdSec** blocks malicious IPs
- ✅ **Webhook IDs are secrets** (don't share publicly)

**Best Practices:**
- 🔒 Use unique webhook IDs (not "webhook1", "webhook2")
- 🔒 Rotate webhook IDs if leaked
- 🔒 Monitor HA logs for unauthorized webhook attempts
- 🔒 Use WireGuard VPN for remote access (encrypted tunnel)

---

## Next Steps

**Phase 4C: Advanced Features (Optional)**
- Actionable notifications (buttons on notifications)
- NFC tags (tap phone to activate scenes)
- Location-based triggers (arrive at work → disable home automations)
- CarPlay integration (dashboard controls while driving)

**Phase 5: Homelab Integration**
- CrowdSec attack → Flash lights red
- Prometheus metrics → Energy dashboard
- Alertmanager → Notify on system issues

---

## Quick Links

- **HA Web UI:** https://ha.patriark.org
- **Companion App:** Home Assistant (App Store)
- **Shortcuts App:** Pre-installed on iPhone/iPad
- **WireGuard VPN:** (Already configured, 192.168.100.0/24)

---

**Created:** 2026-01-30
**Last Updated:** 2026-01-30
**Author:** Claude + Bjørn
**Status:** Active - 7 voice commands, Focus Mode detection
