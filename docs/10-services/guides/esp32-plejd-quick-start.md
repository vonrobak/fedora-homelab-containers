# ESP32 Bluetooth Proxy - Quick Start Guide

**Device:** ESP32 D1 Mini (m-d1-esp32)
**Use Case:** Plejd smart lighting integration with Home Assistant

## Prerequisites Checklist

- [ ] ESP32 D1 Mini with USB cable
- [ ] Chrome or Edge browser (for Web Serial API)
- [ ] **IoT WiFi credentials** (VLAN2 - ASUS RT-N66U)
- [ ] Plejd app credentials (email + password)
- [ ] Home Assistant with HACS installed ✅
- [ ] Firewall rule verified: HA (192.168.1.70) → ESP32 (192.168.2.x) port 6053

## 15-Minute Setup

### Step 1: Flash ESP32 (5 minutes)

1. Connect ESP32 to fedora-htpc via USB
2. Open https://esphome.github.io/bluetooth-proxies/ in Chrome
3. Click **"Connect"** → Select USB port
4. Choose **"Generic ESP32"**
5. Click **"Install Bluetooth Proxy"**
6. Enter **IoT WiFi credentials** (VLAN2 - ASUS RT-N66U):
   - SSID: [IoT network name]
   - Password: [IoT network password]
7. Wait for flash completion

**Expected:** ESP32 reboots and connects to IoT WiFi (192.168.2.x)

### Step 2: Add to Home Assistant (2 minutes)

**⚠️ Auto-discovery won't work (ESP32 on different VLAN)**

**Manual Integration:**

1. Check ESP32 IP address on ASUS RT-N66U (VLAN2)
   - Should be `192.168.2.x`
2. **Settings → Devices & Services → Add Integration**
3. Search: **"ESPHome"**
4. Enter ESP32 IP: `192.168.2.x`
5. Enter encryption key (displayed during flash, or from ESP32 logs)
6. Name: `esp32-bluetooth-proxy`
7. **Submit**

**Verify connectivity:**
```bash
# From fedora-htpc
nc -zv 192.168.2.x 6053
# Should succeed (ESPHome API port)
```

### Step 3: Install Plejd Integration (3 minutes)

1. **HACS → Integrations** → Search `plejd`
2. Download **"Plejd"** by thomasloven
3. **Restart Home Assistant**
4. **Settings → Integrations → Add Integration → Plejd**
5. Enter Plejd app credentials
6. Select your site

**Expected:** 2 light entities discovered
- `light.living_room_dimmer`
- `light.master_bedroom_dimmer`

### Step 4: Test (5 minutes)

- [ ] Turn lights on/off via HA
- [ ] Adjust brightness (0-100%)
- [ ] Press WRT-01 buttons → Verify HA receives updates
- [ ] Check logs for errors: **Settings → System → Logs**

## Troubleshooting

| Problem | Solution |
|---------|----------|
| ESP32 not discovered | **Expected** - Manual add via IP (different VLAN) |
| Connection refused (port 6053) | Update firewall rule to allow TCP 6053 |
| ESP32 offline | Check ASUS RT-N66U for DHCP lease |
| No devices found | Re-enter Plejd credentials |
| Slow response | Move ESP32 closer to lights |
| Connection drops | Check WiFi signal strength on VLAN2 |

## Quick Commands

```bash
# Verify ESP32 on IoT network (VLAN2)
ping 192.168.2.x

# Test ESPHome API connectivity (cross-VLAN)
nc -zv 192.168.2.x 6053

# Check ESP32 IP on ASUS RT-N66U
# (via router web interface: 192.168.2.1)

# Check Bluetooth adapters (host)
bluetoothctl list

# Restart Home Assistant
systemctl --user restart home-assistant.service

# View Plejd logs
journalctl --user -u home-assistant.service | grep -i plejd
```

## Placement Recommendations

**Optimal ESP32 location:**
- Central position between living room and master bedroom
- Clear line of sight to Plejd devices (minimal walls)
- Strong WiFi signal (check router placement)
- Powered via USB (wall adapter or computer USB)

**Range:** ~10-15 meters for Bluetooth LE (through walls: ~5-8 meters)

## Post-Setup

**What to keep:**
- ✅ Mosquitto MQTT broker (useful for other integrations)
- ✅ hci0 Bluetooth (Gnome's adapter)
- ❓ hci1 Bluetooth (spare USB dongle - can remove if not needed)

**No longer needed:**
- ❌ Plejd2MQTT bridge (removed)
- ❌ Custom Python scripts (removed)
- ❌ Dedicated hci1 for Plejd (ESP32 replaces this)

## Next Steps

After successful setup:
1. Create automations (time-based, presence, etc.)
2. Add to dashboards (Lovelace cards)
3. Configure scenes (movie mode, night mode, etc.)
4. Test physical WRT-01 button automations

## Full Documentation

See: `docs/98-journals/2026-02-04-esp32-bluetooth-proxy-for-plejd-integration.md`
