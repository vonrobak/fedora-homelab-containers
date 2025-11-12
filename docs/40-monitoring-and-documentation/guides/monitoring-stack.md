# Homelab Monitoring Stack Guide

**Created:** 2025-11-06
**Last Updated:** 2025-11-12

## Overview

This guide covers the complete monitoring and alerting infrastructure for the homelab, including how to use it, maintain it, and extend it.

## Quick Start

**Access Points:**
- Grafana Dashboards: https://grafana.patriark.org (patriark / qTR#k28w4$RPM3)
- Alertmanager: https://alertmanager.patriark.org
- Discord Notifications: Check your Discord server for alerts

**Daily Monitoring:**
1. Open Grafana "Homelab Overview" dashboard
2. Check all gauges are green
3. Review service health table
4. Check Discord for any alerts

## Architecture

### Core Components

| Component | URL | Purpose |
|-----------|-----|---------|
| **Prometheus** | prometheus:9090 | Metrics collection & alert evaluation |
| **Alertmanager** | alertmanager:9093 | Alert routing & notification management |
| **Discord Relay** | alert-discord-relay:9095 | Transforms alerts → Discord rich embeds |
| **Grafana** | grafana.patriark.org | Dashboards & visualization |
| **Node Exporter** | node_exporter:9100 | System metrics (CPU/RAM/disk) |
| **Loki** | loki:3100 | Log aggregation |
| **Promtail** | promtail:9080 | Log collection |
| **CrowdSec** | crowdsec:6060 | Security monitoring |

### Data Flow

```
Services → Prometheus (scrapes every 15s)
             ↓
         Alert Rules (evaluated every 15s)
             ↓
         Alertmanager (routes & groups)
             ↓
      Discord Relay (formats & sends)
             ↓
         Discord (instant notifications)

Logs → Promtail → Loki → Grafana
Metrics → Prometheus → Grafana
```

## Monitored Services (8 total)

1. **Prometheus** - Self-monitoring
2. **Alertmanager** - Alert system health
3. **Grafana** - Dashboard availability
4. **Traefik** - Proxy health & HTTP metrics
5. **Node Exporter** - System resources
6. **Loki** - Log system health
7. **Promtail** - Log collector health
8. **CrowdSec** - Security monitoring

## Alert Rules (15 total)

### 🚨 Critical Alerts (6 rules)
Sent immediately via Discord, repeat every 1 hour

- **HostDown** - Service unreachable >5min
- **DiskSpaceCritical** - Root <10% free
- **CertificateExpiringSoon** - TLS cert <7 days
- **PrometheusDown** - Monitoring failed >5min
- **AlertmanagerDown** - Alerts won't be sent >10min
- **TraefikDown** - All services inaccessible >5min

### ⚠️ Warning Alerts (9 rules)
Sent via Discord during waking hours only (7am-11pm)

- **DiskSpaceWarning** - Root <20% free
- **HighMemoryUsage** - Memory >85%
- **HighCPUUsage** - CPU >80% for 15min
- **CertificateExpiryWarning** - TLS cert <30 days
- **ContainerRestarting** - Restart loop detected
- **FilesystemFillingUp** - Disk full in <4 hours
- **GrafanaDown** - Dashboard unavailable >10min
- **LokiDown** - Logs unavailable >10min
- **NodeExporterDown** - Metrics stopped >5min

## Grafana Dashboards

The homelab includes 6 pre-configured dashboards for comprehensive monitoring:

### 1. Homelab Overview
**Purpose:** Single-pane-of-glass system health view
**Panels:**
- Service status table (all monitored services)
- System resource gauges (CPU, memory, disk)
- Active alerts counter
- Network traffic overview

**Use case:** Daily health checks, at-a-glance status

### 2. Security Overview
**Purpose:** Security threat visibility and access monitoring
**Panels:**
- Total requests (5-minute window)
- 4xx errors (client errors)
- 5xx errors (server errors)
- Blocked requests (403 responses from CrowdSec)
- Request rate by HTTP status code
- Request rate by service
- CrowdSec ban events (Loki logs)
- Authelia failed login attempts (Loki logs)
- Traefik access logs with IP extraction

**Use case:** Security monitoring, attack detection, access pattern analysis

### 3. Service Health
**Purpose:** Deep-dive container and resource monitoring
**Panels:**
- Container status table (all containers with Up/Down state)
- CPU usage by container (time series)
- Memory usage by container (time series)
- Network I/O by container (RX/TX rates)
- Disk I/O by container (read/write rates)
- System memory usage gauge
- System CPU usage gauge
- System disk usage gauge (root filesystem)

**Use case:** Performance troubleshooting, resource planning, capacity analysis

### 4. Traefik Overview
**Purpose:** Reverse proxy metrics and routing health
**Panels:**
- HTTP request rate
- Response codes breakdown
- Router status
- Backend latency

**Use case:** Proxy performance, routing diagnostics

### 5. Container Metrics (cAdvisor)
**Purpose:** Low-level container resource metrics
**Panels:**
- Container CPU usage
- Container memory usage
- Container network I/O
- Container filesystem I/O

**Use case:** Container performance tuning

### 6. Node Exporter Full
**Purpose:** Comprehensive system-level metrics
**Panels:**
- CPU metrics (all cores)
- Memory breakdown
- Disk I/O statistics
- Network interface stats
- System load

**Use case:** Deep system diagnostics

**Dashboard Locations:**
- Configuration: `~/containers/config/grafana/provisioning/dashboards/json/`
- Provisioning config: `~/containers/config/grafana/provisioning/dashboards/default.yml`
- Access: https://grafana.patriark.org

## Common Tasks

### View Current System Health

```bash
# Quick health check
podman ps --filter name=prometheus --filter name=alertmanager --filter name=grafana

# Check all monitored targets
podman exec prometheus wget -qO- 'http://localhost:9090/api/v1/targets' | python3 -m json.tool

# View active alerts
podman exec prometheus wget -qO- 'http://localhost:9090/api/v1/alerts' | python3 -m json.tool

# Check service logs
journalctl --user -u prometheus.service -n 50
podman logs alertmanager --tail 50
```

### Silence an Alert

During maintenance, you can temporarily silence alerts:

1. Go to https://alertmanager.patriark.org
2. Click "Silences" → "New Silence"
3. Add matchers: `alertname=HighCPUUsage`
4. Set duration (e.g., 2h)
5. Add comment: "System upgrade in progress"
6. Click "Create"

### Add a New Service to Monitoring

When deploying a service that exposes `/metrics`:

1. **Test metrics endpoint**:
```bash
podman exec prometheus wget -qO- http://newservice:9999/metrics | head
```

2. **Edit Prometheus config**:
```bash
nano ~/containers/config/prometheus/prometheus.yml
```

Add:
```yaml
  - job_name: 'newservice'
    static_configs:
      - targets: ['newservice:9999']
        labels:
          instance: 'fedora-htpc'
          service: 'newservice'
```

3. **Restart Prometheus**:
```bash
systemctl --user restart prometheus.service
```

4. **Verify**:
```bash
podman exec prometheus wget -qO- 'http://localhost:9090/api/v1/targets' | grep newservice
```

### Create a New Alert Rule

1. **Edit rules file**:
```bash
nano ~/containers/config/prometheus/alerts/rules.yml
```

2. **Add rule** (example):
```yaml
      - alert: NewServiceDown
        expr: up{job="newservice"} == 0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "New service is down on {{ $labels.instance }}"
          description: "Service has been unreachable for 5 minutes"
```

3. **Restart Prometheus**:
```bash
systemctl --user restart prometheus.service
```

### Create a Grafana Dashboard

**Option 1: Provisioned (survives restarts)**
```bash
# Create JSON file
nano ~/containers/config/grafana/provisioning/dashboards/json/my-dashboard.json

# Restart Grafana
systemctl --user restart grafana.service
```

**Option 2: Web UI (persists in database)**
1. Go to https://grafana.patriark.org
2. Create → Dashboard
3. Add panels, configure queries
4. Save

## File Locations

```
~/containers/
├── config/
│   ├── prometheus/
│   │   ├── prometheus.yml          # ← Scrape targets
│   │   └── alerts/rules.yml        # ← Alert rules
│   ├── alertmanager/
│   │   └── alertmanager.yml        # ← Notification routing
│   ├── grafana/provisioning/
│   │   ├── datasources/
│   │   └── dashboards/json/        # ← Dashboard JSON files
│   └── alert-discord-relay/
│       └── relay.py                # ← Discord webhook code
└── data/
    ├── alertmanager/                # Alert state
    └── grafana/                     # Grafana database

~/.config/containers/systemd/
├── prometheus.container             # ← Quadlet definitions
├── alertmanager.container
├── grafana.container
└── alert-discord-relay.container

/mnt/btrfs-pool/subvol7-containers/
└── prometheus/                      # ← Metrics database (15d retention)
```

## Troubleshooting

### No Discord Alerts

1. Check Discord relay is running:
```bash
podman ps | grep alert-discord-relay
podman logs alert-discord-relay --tail 20
```

2. Test Discord webhook manually:
```bash
curl -X POST "YOUR_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d '{"content": "Test from homelab"}'
```

3. Check Alertmanager → Relay connection:
```bash
podman logs alertmanager | grep discord
```

### Service Shows DOWN in Prometheus

1. Check container is running:
```bash
podman ps -a | grep servicename
```

2. Test network connectivity:
```bash
podman exec prometheus ping servicename
```

3. Test metrics endpoint:
```bash
podman exec prometheus wget -qO- http://servicename:port/metrics
```

4. Check Prometheus logs:
```bash
podman logs prometheus | grep servicename
```

### Alert Not Firing When It Should

1. Check alert rule syntax:
```bash
podman exec prometheus wget -qO- 'http://localhost:9090/api/v1/rules' | grep AlertName
```

2. Test the PromQL expression:
   - Go to https://prometheus.patriark.org (if exposed)
   - Or: `podman exec prometheus wget -qO- 'http://localhost:9090/api/v1/query?query=YOUR_EXPRESSION'`

3. Check `for` duration hasn't been reached yet

4. Check if alert is silenced in Alertmanager

## Useful PromQL Queries

Copy these into Grafana or Prometheus query interface:

**Disk space will run out in X hours:**
```promql
predict_linear(node_filesystem_avail_bytes{mountpoint="/"}[1h], 24*3600) < 0
```

**Memory available:**
```promql
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100
```

**CPU usage by core:**
```promql
100 - (avg by (cpu) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

**HTTP requests per second:**
```promql
rate(traefik_entrypoint_requests_total[1m])
```

**Alert firing count:**
```promql
ALERTS{alertstate="firing"}
```

## Maintenance

### Backup Configuration

```bash
# Backup all monitoring configs
tar -czf ~/monitoring-backup-$(date +%Y%m%d).tar.gz \
  ~/containers/config/prometheus/ \
  ~/containers/config/alertmanager/ \
  ~/containers/config/grafana/ \
  ~/containers/config/alert-discord-relay/ \
  ~/.config/containers/systemd/*{prometheus,alertmanager,grafana,discord}*
```

### Update Alert Thresholds

Based on observed patterns, you may want to adjust:

```yaml
# Example: Change disk warning from 20% to 15%
- alert: DiskSpaceWarning
  expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) < 0.15
```

After editing `~/containers/config/prometheus/alerts/rules.yml`:
```bash
systemctl --user restart prometheus.service
```

### Change Notification Times

Edit `~/containers/config/alertmanager/alertmanager.yml`:

```yaml
time_intervals:
  - name: 'waking_hours'
    time_intervals:
      - times:
          - start_time: '08:00'  # Change to your preference
            end_time: '22:00'
```

Then:
```bash
systemctl --user restart alertmanager.service
```

## Performance Tuning

### Reduce Prometheus Memory Usage

1. **Decrease retention** (currently 15 days):
```ini
# In ~/.config/containers/systemd/prometheus.container
Exec=--storage.tsdb.retention.time=7d
```

2. **Increase scrape interval** (currently 15s):
```yaml
# In ~/containers/config/prometheus/prometheus.yml
global:
  scrape_interval: 30s
```

### Reduce Alert Noise

1. Increase `for` duration in alert rules
2. Use alert inhibition rules (already configured)
3. Adjust severity thresholds based on your normal usage

## Security

- All services run rootless Podman
- Monitoring network isolated from reverse proxy network
- Discord webhook URL stored as Podman secret
- Grafana requires authentication
- Alertmanager/Prometheus only accessible via Traefik with auth middleware
- SELinux enforcing with proper volume contexts

## Resources

- **Prometheus Docs**: https://prometheus.io/docs/
- **Grafana Docs**: https://grafana.com/docs/
- **PromQL Tutorial**: https://prometheus.io/docs/prometheus/latest/querying/basics/
- **Alertmanager Config**: https://prometheus.io/docs/alerting/latest/configuration/

## Quick Reference Commands

```bash
# Service status
systemctl --user status prometheus alertmanager grafana alert-discord-relay

# View logs
journalctl --user -u prometheus.service -f

# Reload Prometheus config
systemctl --user restart prometheus.service

# Check targets
podman exec prometheus wget -qO- 'http://localhost:9090/api/v1/targets'

# Check alerts
podman exec prometheus wget -qO- 'http://localhost:9090/api/v1/alerts'

# Test Discord webhook
curl -X POST "WEBHOOK_URL" -H "Content-Type: application/json" -d '{"content":"Test"}'
```

---

For additional help, check service logs or review Grafana dashboards for visual troubleshooting.
