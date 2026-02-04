# ESP32 Bluetooth Proxy - VLAN2 Firewall Configuration

**Context:** ESP32 on IoT network (VLAN2) needs to communicate with Home Assistant on main network (VLAN1).

## Network Topology

```
VLAN1 (192.168.1.0/24) - Main Network
  └─ 192.168.1.70 (fedora-htpc / Home Assistant)
       ↓
   [Firewall]
       ↓
VLAN2 (192.168.2.0/24) - IoT Network
  └─ 192.168.2.x (ESP32 Bluetooth Proxy)
       ↓ (BLE)
     Plejd Devices
```

## Required Firewall Rule

### Existing Rule (Verify)

You mentioned having: `192.168.1.70 → VLAN2` allowed.

**Verify this rule includes:**

```
Rule Name: HA to IoT Network
Source: 192.168.1.70/32
Destination: 192.168.2.0/24
Protocol: TCP
Destination Port: 6053
Action: ALLOW
State: ESTABLISHED,RELATED
```

### Protocol Details

**ESPHome API:**
- **Port:** 6053/TCP
- **Direction:** Bidirectional (stateful firewall handles return traffic)
- **Protocol:** Native ESPHome API (encrypted)
- **Alternative Ports:** None (6053 is fixed)

**Additional Useful Ports (Optional):**

```
# ICMP (ping) for connectivity testing
Protocol: ICMP
Type: Echo Request/Reply
Action: ALLOW

# Web Interface (if you want to access ESP32 web UI from VLAN1)
Protocol: TCP
Destination Port: 80
Action: ALLOW (optional)
```

## Testing Firewall Rule

### Before ESP32 Arrives

**Test existing rule:**
```bash
# From fedora-htpc (192.168.1.70)
# Pick any IoT device on VLAN2 to test

# Test ICMP
ping 192.168.2.1  # ASUS router gateway
# Should succeed

# Test if general TCP works (to router's web interface)
nc -zv 192.168.2.1 80
# Should succeed if firewall allows TCP traffic
```

### After ESP32 Setup

**Test ESPHome API connectivity:**
```bash
# From fedora-htpc (192.168.1.70)
nc -zv 192.168.2.x 6053
# Expected: Connection succeeded

# If it fails:
# Connection refused → ESP32 not running ESPHome
# No route to host → Firewall blocking
# Timeout → Network issue
```

**Test from Home Assistant:**
```bash
# In HA: Settings → Devices & Services → Add Integration → ESPHome
# Enter IP: 192.168.2.x
# If connection succeeds: Firewall rule is correct
# If timeout: Firewall needs update
```

## Firewall Configuration Examples

### pfSense/OPNsense

```
Firewall → Rules → VLAN1 (Main Network)

Action: Pass
Interface: VLAN1
Protocol: TCP
Source: 192.168.1.70/32
Destination: 192.168.2.0/24
Destination Port: 6053
Description: Home Assistant to ESP32 Bluetooth Proxy
```

### iptables (Linux)

```bash
# Allow HA (192.168.1.70) to reach ESP32 on VLAN2 (192.168.2.0/24)
iptables -A FORWARD -s 192.168.1.70 -d 192.168.2.0/24 -p tcp --dport 6053 -j ACCEPT
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
```

### UniFi Network

```
Settings → Firewall & Security → Rules → Create New Rule

Name: HA to IoT (ESP32)
Rule Applied: Before Predefined Rules
Action: Accept

Source:
  Type: Address/Port Group
  IPv4 Address: 192.168.1.70

Destination:
  Type: Network
  Network: IoT (VLAN2 - 192.168.2.0/24)

Protocol: TCP
Port: 6053

States: Established, Related
```

### MikroTik RouterOS

```
/ip firewall filter add \
  chain=forward \
  src-address=192.168.1.70 \
  dst-address=192.168.2.0/24 \
  protocol=tcp \
  dst-port=6053 \
  action=accept \
  comment="HA to ESP32 ESPHome API"
```

## Security Considerations

### Why VLAN2 is Better

**Pros:**
- ✅ ESP32 is untrusted hardware (low-cost IoT device)
- ✅ Compromised ESP32 cannot access main network
- ✅ Aligns with defense-in-depth principle
- ✅ Same security tier as Plejd devices (IoT)

**Cons:**
- ⚠️ Requires firewall rule (which you already have)
- ⚠️ Manual ESPHome integration (auto-discovery won't work)
- ⚠️ Slightly higher latency (~1-2ms vs ~0.5ms)

### Attack Surface

**If ESP32 is compromised (firmware exploit, WiFi attack):**

**On VLAN1 (Main Network):**
- ❌ Can access fedora-htpc directly
- ❌ Can access Unifi controller
- ❌ Can access other main network services
- ❌ Potential lateral movement to critical systems

**On VLAN2 (IoT Network):**
- ✅ Isolated to IoT devices only
- ✅ Cannot access main network (firewall blocks)
- ✅ Limited attack surface (other IoT devices)
- ✅ Can be detected and blocked at firewall

### Least Privilege Principle

**Current rule:** `192.168.1.70 → 192.168.2.0/24 (any port)`

**More restrictive (recommended):**
```
Source: 192.168.1.70/32
Destination: 192.168.2.x/32 (ESP32 specific IP)
Protocol: TCP
Port: 6053 only
```

**Consider DHCP reservation for ESP32:**
```
ASUS RT-N66U → DHCP Settings
MAC Address: [ESP32 MAC]
Reserved IP: 192.168.2.50 (example)
Hostname: esp32-bluetooth-proxy
```

Then update firewall rule to only allow `192.168.1.70 → 192.168.2.50:6053`.

## Verification Checklist

- [ ] Existing firewall rule includes TCP traffic (not just ICMP)
- [ ] Port 6053 is allowed (ESPHome API)
- [ ] Stateful return traffic allowed (ESTABLISHED,RELATED)
- [ ] Test connectivity before ESP32 arrives (ping IoT gateway)
- [ ] DHCP reservation configured for ESP32 (optional but recommended)
- [ ] Firewall rule logged for monitoring (optional)

## Troubleshooting

**Problem: Connection timeout when adding ESPHome integration**

**Diagnosis:**
```bash
# From fedora-htpc
nc -zv 192.168.2.x 6053
# If timeout: Firewall blocking
# If connection refused: ESP32 issue (not firewall)
```

**Solutions:**
1. Check firewall logs (should show dropped packets)
2. Temporarily disable firewall to isolate issue
3. Add explicit ALLOW rule for port 6053
4. Verify NAT/routing between VLANs

**Problem: mDNS discovery not working**

**Expected behavior:** mDNS doesn't work across VLANs (by design).

**Solution:** Use manual integration with IP address (documented in quick start guide).

## References

- **ESPHome API Protocol:** https://esphome.io/components/api.html
- **Home Assistant ESPHome Integration:** https://www.home-assistant.io/integrations/esphome/
- **VLAN Firewall Best Practices:** https://www.cisco.com/c/en/us/support/docs/security/ios-firewall/23602-confaccesslists.html

## Related Documentation

- Quick Start Guide: `docs/10-services/guides/esp32-plejd-quick-start.md`
- Journal Entry: `docs/98-journals/2026-02-04-esp32-bluetooth-proxy-for-plejd-integration.md`
