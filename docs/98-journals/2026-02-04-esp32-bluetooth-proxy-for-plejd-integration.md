# ESP32 Bluetooth Proxy for Plejd Integration

**Date:** 2026-02-04
**Author:** System (with Claude Code)
**Status:** Planned - Awaiting ESP32 Hardware
**Related:** Home Assistant, Plejd Smart Lighting, Bluetooth Integration

## Context

Home Assistant runs in a rootless Podman container with network segmentation (ADR-017 static IPs). User has 4 Plejd devices (2× DIM-01-2P dimmers, 2× WRT-01 controllers) that need integration with Home Assistant for automation and monitoring.

### Devices

- **Living Room:** 1× DIM-01-2P dimmer + 1× WRT-01 controller
- **Master Bedroom:** 1× DIM-01-2P dimmer + 1× WRT-01 controller

All devices paired in Plejd app and functioning locally.

### The Bluetooth Challenge

**Problem:** Home Assistant container cannot access Bluetooth due to architectural constraints:

1. **Rootless Podman** - UID namespace mapping breaks D-Bus EXTERNAL authentication
2. **Network Segmentation** - HA on isolated networks (reverse_proxy, home_automation, monitoring)
3. **SELinux Enforcing** - Additional permission barriers for D-Bus socket access

**Attempted Solutions:**
- ❌ D-Bus socket mount with security contexts - Permission denied
- ❌ USB Bluetooth dongle passthrough - Requires rootful container or complex udev rules
- ❌ Host network mode - Breaks network segmentation architecture (unacceptable)
- ❌ Custom Plejd2MQTT bridge - Complex protocol implementation (8-16 hours work)

**Chosen Solution:** ESPHome Bluetooth Proxy via ESP32 D1 Mini

### Why ESP32 Bluetooth Proxy?

**Advantages:**
- ✅ No container modifications needed (preserves architecture)
- ✅ Network segmentation intact
- ✅ Better Bluetooth range (can place ESP32 centrally)
- ✅ Maintained by Home Assistant community
- ✅ Works with ALL Bluetooth integrations (not just Plejd)
- ✅ Simple setup (~15 minutes)
- ✅ Low cost (~€5-8)

**Trade-offs:**
- Requires external hardware (ESP32)
- WiFi dependency (acceptable - already required for HA)
- Additional device to maintain (minimal - OTA updates via ESPHome)

## Hardware

### ESP32 D1 Mini Specifications

**Model:** m-d1-esp32
**Product Name:** ESP32 D1 mini Bluetooth+WiFi modul
**Manufacturer:** Espressif Systems

**Key Specifications:**
- **Chip:** ESP32 (hybrid Bluetooth + WiFi)
- **CPU:** Dual-core 240MHz
- **Bluetooth:** Classic + BLE (Bluetooth Low Energy)
- **WiFi:** 802.11 b/g/n (2.4GHz)
- **ADC:** 12-bit
- **Form Factor:** D1 Mini (compact, compatible with D1 Mini shields)
- **GPIO:** Multiple pins (UART, SPI, I2C)
- **Arduino IDE:** Fully compatible

**Why This Model Works:**
- Genuine ESP32 chip (not ESP8266 - verified via product description)
- Both Bluetooth + WiFi (required for ESPHome proxy)
- Compact form factor (easy placement)
- Well-supported by ESPHome

### Host System Bluetooth Status

**Existing Adapters:**
```bash
$ bluetoothctl list
Controller 00:1A:7D:DA:71:11 fedora-HTPC #2 [default]  # hci1 - Second dongle (standby)
Controller 8A:88:4B:C1:35:F6 fedora-HTPC             # hci0 - Primary (Gnome)
```

**Note:** Second USB Bluetooth dongle (hci1) was acquired for potential Plejd2MQTT bridge but is no longer needed with ESP32 solution. Can be removed or kept as spare.

## Implementation Plan

### Phase 1: Flash ESP32 with ESPHome Bluetooth Proxy

**Prerequisites:**
- Chrome or Edge browser (required for Web Serial API)
- USB cable (micro-USB or USB-C, depending on ESP32 model)
- ESP32 D1 Mini connected to fedora-htpc

**Steps:**

1. **Connect ESP32 to fedora-htpc via USB**
   ```bash
   # Verify device detected
   lsusb | grep -i "CP210\|CH340\|FTDI"
   # Common USB-to-serial chips on ESP32 boards

   # Check serial device
   ls -la /dev/ttyUSB* /dev/ttyACM*
   ```

2. **Flash ESPHome Bluetooth Proxy firmware**

   Navigate to: https://esphome.github.io/bluetooth-proxies/

   - Click **"Connect"** button
   - Select serial port (e.g., `/dev/ttyUSB0`)
   - Choose **"Generic ESP32"** from device list
   - Click **"Install Bluetooth Proxy"**
   - Enter WiFi credentials:
     - **SSID:** `[IoT WiFi SSID]` (ASUS RT-N66U on VLAN2)
     - **Password:** `[IoT WiFi password]`
   - Click **"Install"**
   - Wait 2-3 minutes for flashing to complete

   **Important:** Use IoT network credentials (VLAN2) for security isolation.

   **Expected output:**
   ```
   Connecting to ESP32...
   Erasing flash...
   Writing firmware...
   Verifying...
   Configuring WiFi...
   Rebooting ESP32...
   Done! Your Bluetooth Proxy is ready.
   ```

3. **Verify ESP32 connects to WiFi**
   ```bash
   # Check ASUS RT-N66U (IoT router) DHCP leases
   # ESP32 should receive 192.168.2.x address
   # Hostname: "esp32-bluetooth-proxy"

   # From fedora-htpc, test connectivity across VLANs
   ping 192.168.2.x
   # Should succeed (firewall allows ICMP)

   # Test ESPHome API port
   nc -zv 192.168.2.x 6053
   # Should show: Connection succeeded
   # If fails: Firewall rule needs update
   ```

4. **Physical placement**
   - Position ESP32 centrally between living room and master bedroom
   - Ensure power supply (USB power adapter or computer USB port)
   - Verify WiFi signal strength (should be strong for reliable proxy operation)

### Phase 2: Add ESP32 to Home Assistant

**⚠️ Note:** Auto-discovery will **NOT work** (ESP32 on different VLAN). Manual integration required.

**Manual addition:**

1. **Settings → Devices & Services → Add Integration**
2. Search for **"ESPHome"**
3. Enter ESP32 IP address (from router DHCP)
4. Enter encryption key (displayed during flash, or retrieve from ESP32 logs)
5. Click **Submit**

**Verification:**
```bash
# In HA Developer Tools → States, search for:
sensor.esp32_bluetooth_proxy_*
# Should see entities for WiFi signal, uptime, etc.
```

### Phase 3: Install Plejd Integration via HACS

**Prerequisites:**
- HACS installed in Home Assistant ✅ (completed 2026-02-04)
- ESP32 Bluetooth Proxy online and connected ✅

**Steps:**

1. **Navigate to HACS**
   - **Settings → Devices & Services → HACS**
   - Or sidebar: **HACS**

2. **Search for Plejd integration**
   - Click **Integrations**
   - Search: `plejd`
   - Select **"Plejd"** by thomasloven
   - Click **Download**
   - Restart Home Assistant (required for custom components)

3. **Add Plejd integration**
   - **Settings → Devices & Services → Add Integration**
   - Search: `Plejd`
   - Enter Plejd credentials:
     - **Username:** [Plejd app email]
     - **Password:** [Plejd app password]
     - **Site:** Select your site (if multiple)
   - Click **Submit**

4. **Device discovery**
   - Integration scans via ESP32 Bluetooth proxy
   - Discovers all 4 devices:
     - Living room dimmer (DIM-01-2P)
     - Living room controller (WRT-01)
     - Master bedroom dimmer (DIM-01-2P)
     - Master bedroom controller (WRT-01)

**Expected entities:**
```yaml
light.living_room_dimmer        # DIM-01-2P in living room
light.master_bedroom_dimmer     # DIM-01-2P in bedroom
```

**Note:** WRT-01 controllers function locally (paired to dimmers) and trigger events in HA, but don't appear as separate entities.

### Phase 4: Testing & Verification

**Functional tests:**

1. **Control via Home Assistant**
   ```bash
   # Turn on living room dimmer
   # Set brightness to 50%
   # Verify physical light responds
   ```

2. **Physical button control (WRT-01)**
   ```bash
   # Press WRT-01 button
   # Verify HA receives state update
   # Check HA logs for Plejd events
   ```

3. **Automation test**
   Create simple automation:
   ```yaml
   automation:
     - alias: "Test Plejd Dimmer"
       trigger:
         platform: time
         at: "20:00:00"
       action:
         service: light.turn_on
         target:
           entity_id: light.living_room_dimmer
         data:
           brightness_pct: 75
   ```

4. **Range test**
   - Test control from different rooms
   - Verify Bluetooth proxy maintains connection
   - Check for latency (should be <1 second)

5. **Reliability test**
   - Leave running for 24 hours
   - Monitor ESP32 uptime and WiFi stability
   - Check HA logs for connection drops

**Monitoring:**
```bash
# Check ESP32 proxy status
# In HA: Settings → Devices → esp32-bluetooth-proxy
# View diagnostics: uptime, memory, WiFi signal strength

# Check Plejd integration status
# Settings → Devices & Services → Plejd
# Verify all 4 devices online

# Check logs for errors
# Settings → System → Logs
# Filter: "plejd" or "esphome"
```

## Network Topology Impact

### WiFi Network Placement

**Decision: ESP32 on VLAN2 (IoT Network - 192.168.2.0/24)**

**Rationale:**
- ESP32 is an IoT device (untrusted hardware)
- Security isolation principle (defense in depth)
- Aligns with existing IoT segregation architecture
- Compromised ESP32 cannot access main network

**Network Architecture:**

```
Internet
  ↓
Traefik (reverse_proxy network)
  ↓
Home Assistant (reverse_proxy + home_automation + monitoring networks)
  │ IP: 192.168.1.70 (fedora-htpc host)
  │
  ├─(VLAN1)─→ Main Network (192.168.1.0/24)
  │            Unifi U7 Pro
  │
  └─(VLAN2)─→ IoT Network (192.168.2.0/24)
               ASUS RT-N66U
                 ↓
               ESP32 Bluetooth Proxy (192.168.2.x)
                 ↓ (BLE)
               Plejd Devices
```

**Firewall Requirements:**

Existing rule: `192.168.1.70 → VLAN2` already allows HA to reach IoT network.

**Verify rule includes ESPHome API port:**
```
Source: 192.168.1.70 (fedora-htpc)
Destination: 192.168.2.0/24 (IoT network)
Protocol: TCP
Port: 6053 (ESPHome API)
Action: ALLOW
State: ESTABLISHED,RELATED (return traffic)
```

**Testing firewall rule:**
```bash
# From fedora-htpc, test connectivity to ESP32 on VLAN2
nc -zv 192.168.2.x 6053
# Should show: Connection succeeded
```

**Network segmentation preserved:**
- HA remains on isolated Podman networks (ADR-017)
- ESP32 on segregated IoT network (VLAN2)
- Firewall controls HA ↔ ESP32 communication
- No container modifications needed

**Trade-off:**
- ✅ Better security isolation
- ⚠️ mDNS auto-discovery won't work (manual ESPHome integration required)
- ✅ Stateful firewall handles bidirectional traffic

## Configuration Files

### ESPHome Configuration (auto-generated)

**Location:** Managed by ESPHome integration in HA

**YAML config (for reference):**
```yaml
esphome:
  name: esp32-bluetooth-proxy
  friendly_name: ESP32 Bluetooth Proxy

esp32:
  board: esp32dev
  framework:
    type: arduino

wifi:
  ssid: !secret wifi_ssid
  password: !secret wifi_password

  ap:
    ssid: "ESP32-BT-Proxy Fallback"
    password: !secret ap_password

api:
  encryption:
    key: !secret api_encryption_key

ota:
  password: !secret ota_password

bluetooth_proxy:
  active: true

logger:
  level: DEBUG
```

**Access ESPHome dashboard:**
- Via HA: **Settings → Devices → esp32-bluetooth-proxy → Visit**
- Or: `http://[ESP32_IP]:80`

### Home Assistant - Plejd Integration

**Configuration:** UI-based (no YAML required)

**Config storage:** `.storage/core.config_entries` (managed by HA)

**Entities:** Auto-discovered and registered in entity registry

## Troubleshooting

### ESP32 not discovered by Home Assistant

**Symptoms:** No auto-discovery notification after flashing

**Diagnostics:**
1. Check ESP32 connected to WiFi:
   ```bash
   # Ping ESP32 IP
   ping [ESP32_IP]

   # Check router DHCP leases
   # ESP32 should appear with hostname "esp32-bluetooth-proxy"
   ```

2. Check ESPHome API port open:
   ```bash
   nc -zv [ESP32_IP] 6053
   # Should show: Connection succeeded
   ```

3. Verify encryption key:
   - Re-flash ESP32 and note encryption key
   - Add manually via ESPHome integration

**Solution:** Manual integration addition (see Phase 2)

### Plejd devices not discovered

**Symptoms:** Plejd integration added but no devices found

**Diagnostics:**
1. Verify ESP32 Bluetooth proxy active:
   ```bash
   # In HA Developer Tools → States:
   # Search for: binary_sensor.esp32_bluetooth_proxy_*
   # Should show state: "on"
   ```

2. Check Plejd credentials:
   - Re-authenticate in Plejd integration
   - Verify username/password in Plejd app

3. Check Bluetooth range:
   - Move ESP32 closer to Plejd devices
   - Verify devices are powered on

4. Check integration logs:
   ```bash
   # Settings → System → Logs
   # Filter: "plejd"
   # Look for authentication or discovery errors
   ```

**Solution:**
- Re-add Plejd integration
- Power cycle Plejd devices (turn off wall switch for 10 seconds)
- Restart ESP32 proxy

### High latency or connection drops

**Symptoms:** Slow response times, frequent disconnections

**Diagnostics:**
1. Check ESP32 WiFi signal strength:
   ```bash
   # In HA: ESP32 device page
   # Check: sensor.esp32_bluetooth_proxy_wifi_signal
   # Should be > -70 dBm for reliable operation
   ```

2. Check Bluetooth interference:
   - Other Bluetooth devices nearby?
   - 2.4GHz WiFi congestion?
   - Microwave oven, baby monitors?

3. Check ESP32 uptime and restarts:
   ```bash
   # Frequent restarts indicate power or stability issues
   ```

**Solution:**
- Relocate ESP32 for better WiFi signal
- Use external antenna if available
- Switch to less congested WiFi channel
- Ensure stable USB power supply (2A recommended)

### WRT-01 controllers not responding

**Symptoms:** Physical buttons don't trigger HA updates

**Note:** WRT-01 controllers are **locally paired** to DIM-01-2P dimmers. They communicate directly via Bluetooth mesh, not through HA.

**Expected behavior:**
1. Press WRT-01 button → Dimmer responds immediately (local Bluetooth)
2. Dimmer state change → Propagates to HA (via ESP32 proxy)

**If dimmer responds but HA doesn't update:**
- Check Plejd integration logs
- Verify ESP32 proxy receiving updates
- Increase polling interval in Plejd integration settings

## Maintenance

### Regular tasks

**Monthly:**
- Check ESP32 uptime (should be continuous)
- Verify WiFi signal strength (>-70 dBm)
- Update ESPHome firmware if available (OTA via HA)

**Quarterly:**
- Review HA logs for Plejd errors
- Test all dimmer controls (manual + automation)
- Verify WRT-01 button responses

**Annually:**
- Consider ESP32 replacement (if hardware degradation observed)
- Review Plejd integration updates in HACS

### Updates

**ESPHome firmware updates:**
1. **Settings → Devices → esp32-bluetooth-proxy**
2. Click **"Update"** if available
3. Confirm OTA update (takes ~2 minutes)
4. Verify connectivity after update

**Plejd integration updates:**
1. **HACS → Integrations → Plejd**
2. Click **"Update"** if available
3. Restart Home Assistant
4. Test device control

### Backup

**ESPHome configuration:**
- Automatically backed up via HA `.storage/` (included in HA snapshots)
- Optional: Export YAML from ESPHome dashboard

**Plejd credentials:**
- Stored in HA config entries (encrypted)
- Included in HA backups

## Future Considerations

### Additional Bluetooth devices

ESP32 proxy supports **multiple Bluetooth integrations simultaneously:**
- SwitchBot devices
- Xiaomi sensors (LYWSD03MMC, etc.)
- Bluetooth beacons (presence detection)
- Other BLE devices

**No additional hardware needed** - single ESP32 handles all.

### Multiple ESP32 proxies

For larger homes, deploy multiple ESP32 proxies for extended range:
- HA automatically uses closest proxy
- No configuration changes needed
- Proxies coordinate via HA

### Alternative: USB Bluetooth on dedicated service

If ESP32 becomes unreliable, alternative approach:
- Run lightweight VM with direct USB Bluetooth access
- Install HA Core or just Bluetooth proxy service
- Bridge to main HA via API/MQTT

**Not recommended** - ESP32 is simpler and more reliable.

## References

- **ESPHome Bluetooth Proxy:** https://esphome.io/components/bluetooth_proxy.html
- **Plejd HACS Integration:** https://github.com/thomasloven/hass-plejd
- **ESP32 Datasheet:** https://www.espressif.com/sites/default/files/documentation/esp32_datasheet_en.pdf
- **ADR-017:** Static IP Multi-Network Services (network segmentation rationale)

## Related Issues

- **Untrusted Proxy Errors:** Resolved via ADR-017 static IPs
- **Rootless Podman Bluetooth Access:** Architectural constraint, solved by ESP32 proxy
- **D-Bus Authentication Failures:** No longer relevant with ESP32 approach

## Conclusion

ESP32 Bluetooth Proxy provides clean Bluetooth integration for Home Assistant running in rootless Podman with network segmentation. Solution preserves architectural principles while enabling full Plejd device control and automation.

**Total cost:** ~€5-8 (ESP32 D1 Mini)
**Setup time:** ~15 minutes
**Maintenance:** Minimal (OTA updates)
**Reliability:** High (mature ESPHome platform)

**Status:** Awaiting ESP32 hardware delivery. Configuration steps documented and ready for implementation.
