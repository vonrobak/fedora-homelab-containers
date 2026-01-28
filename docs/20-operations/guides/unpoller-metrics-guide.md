# Unpoller Metrics Guide

**Purpose:** Reference guide for working with Unpoller metrics in Prometheus, Grafana, and Home Assistant
**Last Updated:** 2026-01-28
**Unpoller Version:** v1.6.4+

---

## Overview

Unpoller is a UniFi metrics exporter that scrapes data from the UniFi Network Application (controller) and exposes it as Prometheus metrics. This enables monitoring of UniFi devices (UDM, access points, switches) and connected clients (WiFi/wired devices).

**Architecture:**
```
UniFi Controller → Unpoller (scraper) → Prometheus (storage) → Grafana/Home Assistant (visualization)
                    Port 9130           15s scrape interval
```

**Current Deployment:**
- **Service:** `unpoller.service` (systemd quadlet)
- **Container:** `ghcr.io/unpoller/unpoller:latest`
- **Network:** `systemd-monitoring` (10.89.4.0/24)
- **Metrics Endpoint:** `http://unpoller:9130/metrics`
- **Config:** `~/containers/config/unpoller/up.conf`
- **Secrets:** Podman secrets (UP_UNIFI_DEFAULT_URL, UP_UNIFI_DEFAULT_USER, UP_UNIFI_DEFAULT_PASS)

---

## Quick Reference

### Common Metrics

| Metric | Description | Example Query |
|--------|-------------|---------------|
| `unpoller_client_uptime_seconds` | Client connection duration | `unpoller_client_uptime_seconds{name="iPhone"}` |
| `unpoller_client_receive_bytes_total` | Total bytes received by client | `rate(unpoller_client_receive_bytes_total{ip="192.168.1.70"}[5m])` |
| `unpoller_client_transmit_bytes_total` | Total bytes transmitted by client | `rate(unpoller_client_transmit_bytes_total{ip="192.168.1.70"}[5m])` |
| `unpoller_client_radio_signal_db` | WiFi signal strength (dBm) | `avg(unpoller_client_radio_signal_db)` |
| `unpoller_device_stat_gw_system_stats_cpu_percent` | UDM CPU usage | `avg(unpoller_device_stat_gw_system_stats_cpu_percent)` |
| `unpoller_device_stat_gw_system_stats_mem_percent` | UDM memory usage | `avg(unpoller_device_stat_gw_system_stats_mem_percent)` |
| `unpoller_device_stat_gw_uptime_seconds` | UDM uptime | `avg(unpoller_device_stat_gw_uptime_seconds)` |

### Recording Rules (Pre-Computed Metrics)

Defined in `~/containers/config/prometheus/rules/unifi-recording-rules.yml`:

| Recording Rule | PromQL Expression | Use Case |
|----------------|-------------------|----------|
| `homelab:wireless_clients:count` | `count(unpoller_client_uptime_seconds{wired="false"})` | Count of connected WiFi devices |
| `homelab:wired_clients:count` | `count(unpoller_client_uptime_seconds{wired="true"})` | Count of connected wired devices |
| `homelab:total_clients:count` | `count(unpoller_client_uptime_seconds)` | Total connected devices |
| `homelab:vpn_clients:count` | `count(unpoller_client_uptime_seconds{network=~".*WireGuard.*\|.*VPN.*"})` | VPN-connected clients |
| `homelab:bandwidth_bytes_per_second:rate5m` | Sum of receive + transmit rates for homelab server | Homelab bandwidth usage |
| `homelab:avg_wireless_signal_db` | `avg(unpoller_client_radio_signal_db)` | Average WiFi signal strength |

**Benefit of recording rules:** Faster dashboard queries, pre-computed at 15s intervals.

---

## Grafana Dashboards

Three pre-configured Grafana dashboards exist with working Unpoller queries:

### 1. UniFi-Poller: USG Insights - Prometheus
**File:** `config/grafana/provisioning/dashboards/json/unifi-client-insights.json`
**URL:** https://grafana.patriark.org/d/unifi-usg-insights

**Panels:**
- UDM Pro system stats (CPU, memory, uptime)
- WAN/LAN interface throughput
- Firewall statistics (blocks, rules)
- DPI (Deep Packet Inspection) data
- Threat detection metrics

**Use Cases:**
- Monitoring gateway health
- Tracking firewall activity
- Analyzing network throughput
- Security threat detection

### 2. UniFi-Poller: UAP Insights - Prometheus
**File:** `config/grafana/provisioning/dashboards/json/unifi-network-sites.json`
**URL:** https://grafana.patriark.org/d/unifi-uap-insights

**Panels:**
- Access point status and health
- WiFi channel utilization
- Connected clients per AP
- Radio statistics (2.4GHz / 5GHz)
- Interference and noise levels

**Use Cases:**
- WiFi performance optimization
- Channel interference analysis
- AP load balancing
- Client distribution monitoring

### 3. UniFi-Poller: Client Insights - Prometheus
**File:** `config/grafana/provisioning/dashboards/json/unifi-usw.json`
**URL:** https://grafana.patriark.org/d/unifi-client-insights

**Panels:**
- Connected clients list (WiFi + wired)
- Per-client bandwidth usage
- Signal strength per client
- Client connection history
- Top bandwidth consumers

**Use Cases:**
- Identifying bandwidth hogs
- Troubleshooting client connectivity
- Presence detection (see who's home)
- Network usage analysis

---

## Discovery: Finding Available Metrics

Unpoller's metric schema evolves between versions. **Never assume metric names from documentation** - always query Prometheus directly.

### List All Unpoller Metrics

```bash
# From Prometheus container:
podman exec prometheus wget -qO- 'http://localhost:9090/api/v1/label/__name__/values' | \
  jq -r '.data[]' | grep "^unpoller" | sort

# Alternative: From Unpoller directly (if testing connectivity):
curl -s http://10.89.4.64:9130/metrics | grep "^unpoller" | awk '{print $1}' | cut -d'{' -f1 | sort -u
```

### Discover Metric Labels

```bash
# See all available labels for a specific metric:
podman exec prometheus wget -qO- 'http://localhost:9090/api/v1/query?query=unpoller_client_uptime_seconds' | \
  jq '.data.result[0].metric'

# Example output:
{
  "__name__": "unpoller_client_uptime_seconds",
  "instance": "fedora-htpc",
  "job": "unpoller",
  "mac": "fa:bc:60:be:f0:35",
  "name": "iPhone",
  "ip": "192.168.1.52",
  "wired": "false",
  "network": "Default",
  "ap_name": "U6-Lite",
  "site_name": "default"
}
```

### Find Clients by Name

```bash
# List all connected clients with their details:
podman exec prometheus wget -qO- 'http://localhost:9090/api/v1/query?query=unpoller_client_uptime_seconds' | \
  jq -r '.data.result[] | .metric | {name, ip, mac, wired}'

# Example output:
{"name": "iPhone", "ip": "192.168.1.52", "mac": "fa:bc:60:be:f0:35", "wired": "false"}
{"name": "Mac", "ip": "192.168.1.63", "mac": "72:8c:d0:84:87:22", "wired": "false"}
{"name": "ipadpro", "ip": "192.168.1.101", "mac": "88:66:5a:83:6f:43", "wired": "false"}
```

### Explore in Grafana

**Best method:** Use Grafana Explore to test queries interactively:
1. Navigate to https://grafana.patriark.org/explore
2. Select "Prometheus" datasource
3. Enter query: `unpoller_`
4. Press Ctrl+Space for autocomplete
5. Select a metric and press "Run Query"
6. Inspect the "Table" view to see all labels and values

---

## Common Use Cases

### 1. Presence Detection (Home Assistant)

**Goal:** Detect when a device is connected to WiFi (e.g., "Is iPhone home?")

**Method 1: Query uptime (recommended):**
```yaml
# Home Assistant configuration.yaml
sensor:
  - platform: rest
    name: iPhone UniFi Connection
    resource: http://prometheus:9090/api/v1/query?query=unpoller_client_uptime_seconds{name="iPhone",wired="false"}
    value_template: >-
      {% if value_json.data.result %}
        {{ value_json.data.result[0].value[1] }}
      {% else %}
        0
      {% endif %}
    scan_interval: 30
    unit_of_measurement: "s"

template:
  - binary_sensor:
      - name: "iPhone Home"
        device_class: presence
        state: "{{ states('sensor.iphone_unifi_connection') | float(0) > 0 }}"
```

**How it works:**
- Queries Prometheus every 30 seconds
- If iPhone connected → uptime > 0 seconds → binary sensor = "home"
- If iPhone disconnected → no result → uptime = 0 → binary sensor = "not_home"

**Method 2: Count occurrences (simpler):**
```yaml
sensor:
  - platform: rest
    name: iPhone Connected
    resource: http://prometheus:9090/api/v1/query?query=count(unpoller_client_uptime_seconds{name="iPhone"})
    value_template: "{{ value_json.data.result[0].value[1] if value_json.data.result else 0 }}"
    scan_interval: 30

# Returns 1 if connected, 0 if not
```

**Important Notes:**
- Replace `name="iPhone"` with actual device name from UniFi controller
- Find device name: Settings → Client Devices in UniFi UI, or query Prometheus (see "Discovery" section)
- This is **WiFi-based** presence detection - does NOT detect VPN connections
- For VPN presence: Use recording rule `homelab:vpn_clients:count` or query `unpoller_client_uptime_seconds{network=~".*WireGuard.*"}`

### 2. Bandwidth Monitoring

**Per-client bandwidth usage (last 5 minutes):**
```promql
# Receive rate (bytes/sec)
rate(unpoller_client_receive_bytes_total{name="iPhone"}[5m])

# Transmit rate (bytes/sec)
rate(unpoller_client_transmit_bytes_total{name="iPhone"}[5m])

# Total bandwidth (receive + transmit)
sum(rate(unpoller_client_receive_bytes_total{name="iPhone"}[5m])) +
sum(rate(unpoller_client_transmit_bytes_total{name="iPhone"}[5m]))
```

**Top 5 bandwidth consumers:**
```promql
topk(5,
  sum by (name) (
    rate(unpoller_client_receive_bytes_total[5m]) +
    rate(unpoller_client_transmit_bytes_total[5m])
  )
)
```

**Homelab server bandwidth (pre-computed recording rule):**
```promql
homelab:bandwidth_bytes_per_second:rate5m
```

### 3. WiFi Performance Monitoring

**Average signal strength (all clients):**
```promql
avg(unpoller_client_radio_signal_db)
```

**Weakest WiFi client:**
```promql
min(unpoller_client_radio_signal_db)
```

**Clients with poor signal (< -70 dBm):**
```promql
unpoller_client_radio_signal_db < -70
```

**Client count per access point:**
```promql
count by (ap_name) (unpoller_client_uptime_seconds)
```

### 4. Gateway Health Monitoring

**UDM Pro CPU usage:**
```promql
avg(unpoller_device_stat_gw_system_stats_cpu_percent)
```

**UDM Pro memory usage:**
```promql
avg(unpoller_device_stat_gw_system_stats_mem_percent)
```

**UDM Pro uptime (in days):**
```promql
avg(unpoller_device_stat_gw_uptime_seconds) / 86400
```

**WAN throughput (5-minute rate):**
```promql
# Download (bytes/sec)
rate(unpoller_device_stat_gw_wan_rx_bytes[5m])

# Upload (bytes/sec)
rate(unpoller_device_stat_gw_wan_tx_bytes[5m])
```

---

## Alerting Examples

### Client Count Anomaly

Alert when total client count drops significantly (possible network issue):

```yaml
# config/prometheus/alerts/unifi.yml
groups:
  - name: unifi_network
    rules:
      - alert: UniFiClientCountLow
        expr: homelab:total_clients:count < 5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Low UniFi client count"
          description: "Only {{ $value }} clients connected (expected 10+). Possible WiFi/network issue."
```

### Poor WiFi Performance

Alert when average signal strength is poor:

```yaml
- alert: UniFiPoorWiFiSignal
  expr: homelab:avg_wireless_signal_db < -75
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "Poor average WiFi signal strength"
    description: "Average WiFi signal is {{ $value }} dBm (threshold: -75 dBm). Check AP placement or interference."
```

### UDM Resource Exhaustion

Alert when UDM Pro resources are high:

```yaml
- alert: UniFiUDMHighCPU
  expr: homelab:udm_cpu_percent > 80
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "UDM Pro high CPU usage"
    description: "UDM CPU at {{ $value }}% (threshold: 80%). Check for resource-intensive processes."

- alert: UniFiUDMHighMemory
  expr: homelab:udm_memory_percent > 90
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "UDM Pro high memory usage"
    description: "UDM memory at {{ $value }}% (threshold: 90%). Risk of OOM crashes."
```

---

## Troubleshooting

### Unpoller Not Exporting Metrics

**Symptom:** Prometheus shows `up{job="unpoller"}=0` or no metrics at all.

**Debug Steps:**

1. **Check Unpoller container is running:**
   ```bash
   systemctl --user status unpoller.service
   podman ps | grep unpoller
   ```

2. **Check Unpoller logs for errors:**
   ```bash
   podman logs unpoller --tail 50
   ```

   **Common errors:**
   - `Failed to connect to UniFi controller` → Check UP_UNIFI_DEFAULT_URL secret
   - `Invalid credentials` → Verify UP_UNIFI_DEFAULT_USER/PASS secrets
   - `TLS/SSL error` → Check `verify_ssl = false` in up.conf for self-signed certs

3. **Test Unpoller metrics endpoint:**
   ```bash
   curl -s http://10.89.4.64:9130/metrics | head -20
   # Should see Prometheus-format metrics
   ```

4. **Verify Prometheus can reach Unpoller:**
   ```bash
   podman exec prometheus wget -O/dev/null http://unpoller:9130/metrics
   # Should succeed with 200 OK
   ```

5. **Check Prometheus target status:**
   ```bash
   podman exec prometheus wget -qO- 'http://localhost:9090/api/v1/targets' | \
     jq -r '.data.activeTargets[] | select(.labels.job == "unpoller") | {health: .health, lastError: .lastError}'
   ```

### Metric Not Found

**Symptom:** Query returns empty result: `{"status": "success", "data": {"resultType": "vector", "result": []}}`

**Solutions:**

1. **List all available metrics:**
   ```bash
   podman exec prometheus wget -qO- 'http://localhost:9090/api/v1/label/__name__/values' | \
     jq -r '.data[]' | grep unpoller
   ```

2. **Check Grafana dashboards** - they contain working queries for current Unpoller version

3. **Verify metric exists in raw Unpoller output:**
   ```bash
   curl -s http://10.89.4.64:9130/metrics | grep "your_metric_name"
   ```

4. **Check if it's a recording rule:**
   ```bash
   cat ~/containers/config/prometheus/rules/unifi-recording-rules.yml | grep "your_metric_name"
   ```

### Stale Metrics

**Symptom:** Metrics show old/stale data.

**Check scrape freshness:**
```promql
# Time since last successful scrape (should be < 30s)
time() - timestamp(up{job="unpoller"})
```

**Force reload Prometheus config:**
```bash
podman exec prometheus kill -SIGHUP 1
```

**Restart Unpoller to clear cache:**
```bash
systemctl --user restart unpoller.service
```

---

## Configuration Files

### Unpoller Configuration

**Location:** `~/containers/config/unpoller/up.conf`

**Key settings:**
```toml
[poller]
  interval = "30s"          # How often to poll UniFi controller
  debug = false             # Enable debug logging
  quiet = false             # Minimal logging

[prometheus]
  http_listen = "0.0.0.0:9130"  # Metrics endpoint
  report_errors = false     # Report errors as separate metrics

[unifi.defaults]
  url = "${UP_UNIFI_DEFAULT_URL}"      # From Podman secret
  user = "${UP_UNIFI_DEFAULT_USER}"    # From Podman secret
  pass = "${UP_UNIFI_DEFAULT_PASS}"    # From Podman secret
  verify_ssl = false        # Allow self-signed certs
  save_sites = true         # Export site metrics
```

**To modify:**
```bash
nano ~/containers/config/unpoller/up.conf
systemctl --user restart unpoller.service
```

### Prometheus Scrape Configuration

**Location:** `~/containers/config/prometheus/prometheus.yml`

```yaml
scrape_configs:
  - job_name: 'unpoller'
    static_configs:
      - targets: ['unpoller:9130']
        labels:
          instance: 'fedora-htpc'
          service: 'unpoller'
```

**Scrape interval:** 15s (global default)
**Scrape timeout:** 10s (global default)

### Unpoller Quadlet

**Location:** `~/.config/containers/systemd/unpoller.container`

**Key directives:**
```ini
[Container]
Image=ghcr.io/unpoller/unpoller:latest
Network=systemd-monitoring
Secret=unpoller_url,type=env,target=UP_UNIFI_DEFAULT_URL
Secret=unpoller_user,type=env,target=UP_UNIFI_DEFAULT_USER
Secret=unpoller_pass,type=env,target=UP_UNIFI_DEFAULT_PASS

[Service]
MemoryMax=256M
MemoryHigh=230M
```

**To modify:**
```bash
nano ~/.config/containers/systemd/unpoller.container
systemctl --user daemon-reload
systemctl --user restart unpoller.service
```

---

## Performance Considerations

### Resource Usage

**Typical usage:**
- **Memory:** 25-30MB (current: 25.8M)
- **CPU:** <1% (scraping every 30s)
- **Network:** ~200KB/scrape (15 clients, 1 AP, 1 UDM)

**Scaling factors:**
- Each client adds ~7-10 metrics
- Each AP adds ~50 metrics
- DPI data significantly increases metric count (disabled by default)

### Optimizing Queries

**Slow queries:**
```promql
# BAD: Forces Prometheus to scan all time series
sum(unpoller_client_receive_bytes_total)

# GOOD: Use recording rules for expensive aggregations
homelab:total_clients:count
```

**Use recording rules for:**
- Dashboard queries that run every 5-30s
- Aggregations across many labels
- Complex calculations (rate + sum + division)

**Recording rule benefits:**
- Pre-computed at 15s intervals
- Stored as new time series (fast to query)
- Reduces dashboard load time from seconds to milliseconds

### Scrape Interval Tuning

**Default: 15s** (good balance for most use cases)

**When to increase interval:**
- Many UniFi sites (> 5 sites)
- Hundreds of clients (> 100 clients)
- UniFi controller on slow hardware
- Want to reduce Prometheus storage usage

**When to decrease interval:**
- Need real-time presence detection (10s minimum)
- Monitoring fast-changing metrics (bandwidth spikes)
- High-resolution alerting required

**To change:**
```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'unpoller'
    scrape_interval: 30s  # Override global default
    static_configs:
      - targets: ['unpoller:9130']
```

---

## Integration Examples

### Home Assistant Automation

**Turn on lights when iPhone arrives home:**
```yaml
# automations.yaml
- alias: "Welcome Home - Lights On"
  trigger:
    - platform: state
      entity_id: binary_sensor.iphone_home
      from: "not_home"
      to: "home"
  action:
    - service: light.turn_on
      target:
        entity_id: light.living_room
      data:
        brightness_pct: 75
```

**Notify when bandwidth exceeds threshold:**
```yaml
# configuration.yaml - Add bandwidth sensor
sensor:
  - platform: rest
    name: Homelab Bandwidth Mbps
    resource: http://prometheus:9090/api/v1/query?query=homelab:bandwidth_bytes_per_second:rate5m
    value_template: "{{ (value_json.data.result[0].value[1] | float * 8 / 1000000) | round(2) if value_json.data.result else 0 }}"
    scan_interval: 30
    unit_of_measurement: "Mbps"

# automations.yaml
- alias: "High Bandwidth Alert"
  trigger:
    - platform: numeric_state
      entity_id: sensor.homelab_bandwidth_mbps
      above: 100
      for:
        minutes: 5
  action:
    - service: notify.mobile_app
      data:
        message: "Homelab bandwidth is {{ states('sensor.homelab_bandwidth_mbps') }} Mbps"
```

### Grafana Variables

**Dynamic device selection in dashboards:**
```
# Variable name: client_name
# Type: Query
# Query: label_values(unpoller_client_uptime_seconds, name)
# Refresh: On Dashboard Load

# Use in panel query:
unpoller_client_receive_bytes_total{name="$client_name"}
```

### Loki Log Correlation

**Example: Correlate high bandwidth with application logs**
```promql
# In Grafana Explore, split view:
# Top panel (Prometheus):
sum by (name) (rate(unpoller_client_receive_bytes_total[5m]))

# Bottom panel (Loki):
{job="traefik"} |= "192.168.1.70" | json | line_format "{{.ClientHost}} {{.RequestMethod}} {{.RequestPath}}"
```

---

## Additional Resources

**Official Documentation:**
- Unpoller Docs: https://unpoller.com/docs/
- Metric Reference: https://unpoller.com/docs/metrics/
- UniFi API: https://ubntwiki.com/products/software/unifi-controller/api

**Homelab-Specific:**
- Recording Rules: `~/containers/config/prometheus/rules/unifi-recording-rules.yml`
- Grafana Dashboards: `~/containers/config/grafana/provisioning/dashboards/json/unifi-*.json`
- Deployment Journal: `docs/98-journals/2026-01-28-matter-hybrid-week2-matter-server-deployment.md`

**Community Resources:**
- Unpoller GitHub: https://github.com/unpoller/unpoller
- Grafana Dashboard Library: Search for "UniFi Poller" at https://grafana.com/grafana/dashboards/

---

## Version History

| Date | Version | Changes |
|------|---------|---------|
| 2026-01-28 | 1.0 | Initial guide created (Unpoller v1.6.4, Week 2 Matter deployment) |
