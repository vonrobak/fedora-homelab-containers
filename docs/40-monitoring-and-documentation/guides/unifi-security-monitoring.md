# UniFi Security Monitoring Guide

**Created:** 2026-01-08
**Purpose:** Network-layer security monitoring using Unpoller and UDM Pro metrics

---

## Overview

This guide documents the integration of UniFi network metrics into your homelab's security monitoring stack. Unpoller exports metrics from your UDM Pro, providing visibility into network-layer threats, client behavior, and traffic patterns toward your port-forwarded services (80/443 → 192.168.1.70).

---

## Architecture

```
UDM Pro (192.168.1.1)
  ↓ API (unifipoller account, custom readonly role)
Unpoller Container (monitoring network)
  ↓ Prometheus scrape (unpoller:9130, every 15s)
Prometheus (recording rules + alerts)
  ↓
Grafana Dashboards + Alertmanager
```

**Key Components:**
- **Unpoller:** Metrics exporter for UniFi Network Application
- **Prometheus:** Scrapes 544 metrics every 30s from Unpoller
- **Grafana:** 3 dashboards (Client Insights, Network Sites, Switch stats)
- **Recording Rules:** 12 pre-computed metrics for performance
- **Alert Rules:** 7 conservative critical/warning alerts
- **SLO Tracking:** 10 rules for UDM Pro availability (99.9% target)

---

## Dashboards

### 1. UniFi-Poller: Client Insights (ID 11313)
**Purpose:** Monitor individual client connections, bandwidth, and presence detection

**Key Panels:**
- Connected clients by device type
- Bandwidth usage per client
- Signal strength and connection quality
- VPN client presence (WireGuard)

**Security Use Cases:**
- Detect unknown/rogue clients on network
- Identify bandwidth anomalies per device
- Track VPN connections for presence-based automations

**Access:** https://grafana.patriark.org → Dashboards → UniFi-Poller: Client Insights

---

### 2. UniFi-Poller: Network Sites (ID 11314)
**Purpose:** Network-wide health and aggregate statistics

**Key Panels:**
- Total clients (wired + wireless)
- Aggregate bandwidth across all clients
- UDM Pro system stats (CPU, memory, uptime)
- Access point performance

**Security Use Cases:**
- Baseline network traffic patterns
- Detect abnormal client count spikes
- Monitor UDM Pro resource exhaustion

**Access:** https://grafana.patriark.org → Dashboards → UniFi-Poller: Network Sites

---

### 3. UniFi-Poller: USW (Switch) (ID 11315)
**Purpose:** Switch port statistics and PoE usage

**Key Panels:**
- Port utilization and errors
- PoE power consumption
- Uplink health

**Access:** https://grafana.patriark.org → Dashboards → UniFi-Poller: USW

---

## Recording Rules

Pre-computed metrics for faster dashboard rendering:

| Metric | Description | Query Frequency |
|--------|-------------|-----------------|
| `homelab:bandwidth_bytes_per_second:rate5m` | Total bandwidth to 192.168.1.70 | Every 15s |
| `homelab:vpn_clients:count` | WireGuard VPN client count | Every 15s |
| `homelab:udm_health:up` | UDM Pro scrape status (0 or 1) | Every 15s |
| `homelab:firewall_blocks_per_minute:rate5m` | Firewall block rate | Every 15s |
| `homelab:wireless_clients:count` | Connected wireless clients | Every 15s |
| `homelab:wired_clients:count` | Connected wired clients | Every 15s |
| `homelab:total_clients:count` | Total connected clients | Every 15s |
| `homelab:avg_wireless_signal_db` | Average wireless signal strength | Every 15s |
| `homelab:udm_cpu_percent` | UDM Pro CPU usage | Every 15s |
| `homelab:udm_memory_percent` | UDM Pro memory usage | Every 15s |
| `homelab:udm_uptime_days` | UDM Pro uptime in days | Every 15s |
| `homelab:dpi_security_bytes:rate5m` | DPI-detected security threats | Every 15s |

**File:** `/home/patriark/containers/config/prometheus/rules/unifi-recording-rules.yml`

---

## Alert Rules

### Critical Alerts (Immediate Action Required)

#### UDMProDown
**Trigger:** Unpoller cannot scrape UDM Pro for 5+ minutes
**Severity:** Critical
**Impact:** All internet access lost, network gateway offline
**Action:** Check UDM Pro physical status, power cycle if needed
**Runbook:** `docs/30-security/runbooks/IR-001-network-outage.md`

#### UnpollerScrapeFailed
**Trigger:** Prometheus cannot scrape Unpoller for 3+ minutes
**Severity:** Critical
**Impact:** Network monitoring blind spot
**Action:** `systemctl --user restart unpoller.service`
**Remediation:** Automatic via service-restart playbook

#### ExtremeBandwidthSpike
**Trigger:** Sustained bandwidth >100 MB/s (~800 Mbps) to homelab for 5+ minutes
**Severity:** Critical
**Impact:** Possible DDoS attack or data exfiltration
**Action:** Investigate source IPs, correlate with Traefik access logs, check CrowdSec bans

#### DPISecurityThreatDetected
**Trigger:** UDM Pro DPI identifies malicious traffic (any non-zero rate)
**Severity:** Critical
**Impact:** Active security threat targeting homelab
**Action:** Check UDM Pro DPI logs, identify source IP, verify CrowdSec ban status

---

### Warning Alerts (Monitor, No Immediate Action)

#### HighFirewallBlockRate
**Trigger:** UDM Pro blocking >10 connections/minute for 10+ minutes
**Severity:** Warning
**Impact:** Possible attack or misconfiguration
**Action:** Review firewall logs, correlate with CrowdSec decisions

#### UDMProHighCPU / UDMProHighMemory
**Trigger:** UDM Pro CPU >90% or memory >85% for 15+ minutes
**Severity:** Warning
**Impact:** Network performance degradation
**Action:** Investigate UDM Pro processes, consider reboot if sustained

**File:** `/home/patriark/containers/config/prometheus/alerts/unifi-alerts.yml`

---

## SLO Tracking

### UDM Pro Availability
**Target:** 99.9% uptime (43 minutes/month error budget)
**Measurement:** `up{job="unpoller"}` over 30-day window
**Dashboard:** https://grafana.patriark.org/d/slo-dashboard/

**Key Metrics:**
- `slo:udm_availability:ratio_30d` - Actual availability percentage
- `slo:udm_availability:error_budget_remaining_minutes_30d` - Budget remaining
- `slo:udm_availability:error_budget_burn_rate_*` - Burn rate (1h, 6h, 24h, 7d windows)

**Burn Rate Thresholds:**
- Burn rate <1.0: Within budget (sustainable)
- Burn rate 1.0-2.0: Burning budget faster than ideal
- Burn rate >2.0: Error budget exhaustion risk

---

### Client Signal Quality SLO
**Target:** >80% of wireless clients have good signal (>-70 dBm)
**Measurement:** `slo:client_signal_quality:ratio`
**Purpose:** Ensure reliable wireless coverage

**File:** `/home/patriark/containers/config/prometheus/rules/unifi-slo-rules.yml`

---

## Security Correlation Patterns

### Pattern 1: Network + Application Layer Threat Correlation

**Scenario:** Detect coordinated attacks across network and application layers

**Query:**
```promql
# Network-layer firewall blocks
homelab:firewall_blocks_per_minute:rate5m

# Application-layer rate limits (Traefik)
rate(traefik_entrypoint_requests_total{code=~"429"}[5m])

# IP reputation bans (CrowdSec)
crowdsec_decisions{type="ban"}
```

**Dashboard Panel:** Unified timeline showing concurrent events

---

### Pattern 2: Bandwidth Anomaly Detection

**Baseline:** Establish 7-day traffic baseline to homelab (192.168.1.70)

**Query:**
```promql
# Current bandwidth
homelab:bandwidth_bytes_per_second:rate5m

# 7-day average
avg_over_time(homelab:bandwidth_bytes_per_second:rate5m[7d])

# Standard deviation
stddev_over_time(homelab:bandwidth_bytes_per_second:rate5m[7d])

# Alert if >3 std dev from mean
abs(
  homelab:bandwidth_bytes_per_second:rate5m
  - avg_over_time(homelab:bandwidth_bytes_per_second:rate5m[7d])
) > (3 * stddev_over_time(homelab:bandwidth_bytes_per_second:rate5m[7d]))
```

**Use Case:** Detect unusual traffic spikes that may indicate data exfiltration or DDoS

---

### Pattern 3: VPN-Based Presence Detection

**Integration:** Home Assistant automation triggered by VPN client count

**Query:**
```promql
# WireGuard VPN clients currently connected
homelab:vpn_clients:count
```

**Automation Trigger:** When `homelab:vpn_clients:count > 0`
- Action: Execute "Home" scene (lights, heating, etc.)
- Reference: Matter home automation plan Phase 2

---

## Key Metrics Reference

### Client Metrics
- `unpoller_client_uptime_seconds{...}` - Client connection uptime
- `unpoller_client_receive_bytes_total{...}` - Bytes received by client
- `unpoller_client_transmit_bytes_total{...}` - Bytes transmitted by client
- `unpoller_client_radio_signal_db{...}` - Wireless signal strength (dBm)
- `unpoller_client_radio_receive_rate_bps{...}` - PHY receive rate (bps)
- `unpoller_client_radio_transmit_rate_bps{...}` - PHY transmit rate (bps)

### Device Metrics
- `unpoller_device_stat_gw_uptime_seconds` - UDM Pro uptime
- `unpoller_device_stat_gw_system_stats_cpu_percent` - UDM Pro CPU usage
- `unpoller_device_stat_gw_system_stats_mem_percent` - UDM Pro memory usage
- `unpoller_device_stat_gw_user_num_blocked_total` - Firewall block counter

### DPI Metrics (if available)
- `unpoller_device_dpi_app_bytes{category=...}` - Traffic by application category

---

## Troubleshooting

### Unpoller Not Authenticating

**Symptom:** `403 Forbidden` or `429 Too Many Requests` errors

**Common Causes:**
1. **Username mismatch:** Verify podman secret `unpoller_user` matches UDM Pro username exactly
2. **Password mismatch:** Regenerate password and sync both UDM Pro and podman secret
3. **Insufficient role:** UDM Pro account needs "Full Management" for Control Plane (custom roles with "View Only" don't grant API access)
4. **Rate limiting:** Wait 30+ minutes after repeated failed auth attempts

**Verification:**
```bash
# Check service status
systemctl --user status unpoller.service

# Check authentication logs
journalctl --user -u unpoller.service | grep -i "auth\|error"

# Verify secrets exist
podman secret ls | grep unpoller

# Test UDM Pro connectivity
curl -k -I https://192.168.1.1
```

---

### Metrics Not Appearing in Prometheus

**Symptom:** Dashboards show "No data" or queries return empty results

**Checks:**
1. **Unpoller exporting:** `curl -s http://localhost:9130/metrics | grep unpoller_`
2. **Prometheus scraping:** `podman exec prometheus wget -qO- http://unpoller:9130/metrics`
3. **Scrape config:** `podman exec prometheus cat /etc/prometheus/prometheus.yml | grep unpoller`
4. **Recording rules loaded:** `podman logs prometheus | grep "rules="`

---

### Dashboards Not Auto-Importing

**Symptom:** UniFi dashboards missing from Grafana

**Checks:**
1. **Files exist:** `ls -lh ~/containers/config/grafana/provisioning/dashboards/json/unifi-*.json`
2. **Grafana logs:** `podman logs grafana | grep -i dashboard`
3. **Provisioning config:** Check `updateIntervalSeconds` in `dashboards.yml` (default: 30s)

**Manual reimport:**
```bash
# Force Grafana restart to reimport dashboards
systemctl --user restart grafana.service
```

---

## Related Documentation

- [Secrets Management Guide](../../../30-security/guides/secrets-management.md) - Podman secrets Pattern 2
- [SLO Framework](./slo-framework.md) - SLO targets and burn rate calculations
- [Loki Remediation Queries](./loki-remediation-queries.md) - LogQL correlation patterns
- [Security Audit Guide](../../../30-security/guides/security-audit.md) - Network monitoring checklist
- [Matter Home Automation Plan](../../../97-plans/2025-12-30-matter-home-automation-implementation-plan.md) - VPN presence detection integration

---

## Next Steps

1. **Establish Baseline:** Monitor `homelab:bandwidth_bytes_per_second:rate5m` for 7 days to establish normal traffic patterns
2. **Tune Alerts:** Adjust `ExtremeBandwidthSpike` threshold based on baseline (currently 100 MB/s)
3. **Enhance Security Overview Dashboard:** Add 6 UniFi panels as planned (see Matter automation plan Phase 2)
4. **Integrate with Home Assistant:** Configure VPN presence detection automation
5. **Review SLO Burn Rates:** Weekly review of error budget consumption

---

**End of Guide**
