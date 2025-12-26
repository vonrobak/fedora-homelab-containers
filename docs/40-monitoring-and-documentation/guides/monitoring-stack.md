# Homelab Monitoring Stack Guide

**Created:** 2025-11-06
**Last Updated:** 2025-12-26

## Overview

This guide covers the complete monitoring, alerting, and autonomous remediation infrastructure for the homelab, including how to use it, maintain it, and extend it.

**Recent Enhancements (December 2025):**
- ✅ Automated remediation via webhook handler
- ✅ Decision log ingestion into Loki
- ✅ Traefik access log monitoring
- ✅ SLO-based alerting framework
- ✅ Autonomous operations integration
- ✅ Log rotation and retention management

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
| **Remediation Webhook** | localhost:9096 | Automated alert remediation (Phase 4) |
| **Grafana** | grafana.patriark.org | Dashboards & visualization |
| **Node Exporter** | node_exporter:9100 | System metrics (CPU/RAM/disk) |
| **Loki** | loki:3100 | Log aggregation & querying |
| **Promtail** | promtail:9080 | Log collection & forwarding |
| **CrowdSec** | crowdsec:6060 | Security monitoring |

### Data Flow

```
METRICS PIPELINE:
Services → Prometheus (scrapes every 15s)
             ↓
         Alert Rules (evaluated every 15s)
             ↓
         Alertmanager (routes & groups)
             ├→ Discord Relay → Discord (notifications)
             └→ Remediation Webhook → Auto-remediation → Decision Log

LOGS PIPELINE:
System Logs → Promtail ┐
Decision Logs →         ├→ Loki → Grafana (queries & dashboards)
Traefik Logs →          ┘

REMEDIATION FLOW:
Alert Fires → Alertmanager → Webhook (localhost:9096)
                                ↓
                    Route to Playbook (disk-cleanup, service-restart, etc.)
                                ↓
                    Execute → Log Decision (JSONL)
                                ↓
                    Promtail → Loki (queryable logs)
```

## Monitored Services (9 total)

1. **Prometheus** - Self-monitoring
2. **Alertmanager** - Alert system health
3. **Grafana** - Dashboard availability
4. **Traefik** - Proxy health & HTTP metrics
5. **Node Exporter** - System resources
6. **Loki** - Log system health
7. **Promtail** - Log collector health
8. **CrowdSec** - Security monitoring
9. **Remediation Webhook** - Auto-remediation system health

## Alert Rules (20+ total)

### 🚨 Critical Alerts (6 rules)
Sent immediately via Discord, repeat every 1 hour. Auto-remediation enabled for safe operations.

- **HostDown** - Service unreachable >5min
- **DiskSpaceCritical** - Root <10% free (🤖 auto: disk-cleanup playbook)
- **CertificateExpiringSoon** - TLS cert <7 days
- **PrometheusDown** - Monitoring failed >5min
- **AlertmanagerDown** - Alerts won't be sent >10min
- **TraefikDown** - All services inaccessible >5min

### ⚠️ Warning Alerts (9 rules)
Sent via Discord during waking hours only (7am-11pm). Select alerts have auto-remediation.

- **DiskSpaceWarning** - Root <20% free (🤖 auto: disk-cleanup playbook)
- **HighMemoryUsage** - Memory >85%
- **HighCPUUsage** - CPU >80% for 15min
- **CertificateExpiryWarning** - TLS cert <30 days
- **ContainerRestarting** - Restart loop detected (🤖 auto: service-restart playbook)
- **FilesystemFillingUp** - Disk full in <4 hours
- **GrafanaDown** - Dashboard unavailable >10min
- **LokiDown** - Logs unavailable >10min
- **NodeExporterDown** - Metrics stopped >5min

### 🎯 SLO-Based Alerts (5+ services)
Multi-tiered burn rate detection with auto-remediation for Tier 2/3 violations.

**Jellyfin SLO Alerts:**
- **SLOBurnRateTier1_Jellyfin** - Critical: 2% error budget consumed in 1 hour
- **SLOBurnRateTier2_Jellyfin** - High: 5% error budget consumed in 6 hours (🤖 auto: slo-violation-remediation)
- **SLOBurnRateTier3_Jellyfin** - Medium: 10% error budget consumed in 3 days (🤖 auto: slo-violation-remediation)

**Other Services:** Immich, Authelia, Traefik, OCIS (similar tiered structure)

**🤖 Auto-remediation:** Alerts marked with robot icon trigger automated remediation playbooks via webhook handler.

## Grafana Dashboards

The homelab includes 7 pre-configured dashboards for comprehensive monitoring:

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

### 7. Remediation Effectiveness
**Purpose:** Auto-remediation performance and success tracking
**Panels:**
- Remediation success rate (last 24h, 7d, 30d)
- Remediation attempts by playbook (pie chart)
- Decision log timeline (Loki query)
- Oscillation detection events
- Average confidence score by playbook
- Failure breakdown by alert type

**Use case:** Validate autonomous operations effectiveness, troubleshoot remediation failures

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

## Remediation Webhook

The remediation webhook handler provides automated remediation for select alerts with safety controls and audit logging.

### How It Works

When an alert fires in Prometheus, Alertmanager sends a webhook to the remediation handler (localhost:9096), which:

1. **Authenticates** the request using token-based auth
2. **Routes** to appropriate playbook based on alert name
3. **Checks safety** controls (idempotency, rate limiting, circuit breaker, oscillation detection)
4. **Executes** remediation playbook
5. **Logs decision** to JSONL file (~/.claude/context/decision-log.jsonl)
6. **Ingests to Loki** via Promtail for queryable audit trail
7. **Notifies Discord** on failure

### Supported Playbooks

**Currently implemented:**
- `disk-cleanup` - Remove temporary files, prune container images, vacuum journals
- `service-restart` - Restart failed containers (respects override list)
- `slo-violation-remediation` - Investigate + restart service on SLO burn
- `predictive-maintenance` - Preemptive actions on resource forecasts

**Safety overrides:** Traefik and Authelia never auto-restart (too critical).

### Configuration

**Webhook handler configuration:**
```bash
# Service file
~/.config/systemd/user/remediation-webhook.service

# Routing config
~/containers/.claude/remediation/webhook-routing.yml

# Authentication token (gitignored)
~/.config/remediation-webhook.env
```

**Alertmanager routing:**
```yaml
# ~/containers/config/alertmanager/alertmanager.yml
receivers:
  - name: 'remediation-webhook'
    webhook_configs:
      - url: 'http://host.containers.internal:9096/webhook?token=<TOKEN>'
```

### Safety Controls

1. **Rate Limiting:** Maximum 5 executions per hour
2. **Idempotency Window:** Won't re-execute same alert within 5 minutes
3. **Circuit Breaker:** Pauses after 3 consecutive failures
4. **Oscillation Detection:** Blocks if 3+ triggers in 15 minutes
5. **Authentication:** Token-based auth (fail-closed)
6. **Service Overrides:** Critical services excluded from auto-restart

### Monitoring Remediation

**View decision log:**
```bash
tail -f ~/.claude/context/decision-log.jsonl | jq '.'
```

**Query in Loki (via Grafana Explore):**
```logql
# All remediation actions
{job="remediation-decisions"} | json

# Failures only
{job="remediation-decisions"} | json | success="false"

# By playbook
{job="remediation-decisions"} | json | playbook="disk-cleanup"

# Success rate over 24h
sum by (success) (count_over_time({job="remediation-decisions"}[24h]))
```

**Check webhook handler status:**
```bash
systemctl --user status remediation-webhook.service
journalctl --user -u remediation-webhook.service -f
```

### Testing

**Health check:**
```bash
curl -s http://localhost:9096/health
# Expected: {"status": "healthy"}
```

**Manual trigger (with token):**
```bash
TOKEN=$(grep WEBHOOK_AUTH_TOKEN ~/.config/remediation-webhook.env | cut -d= -f2)
curl -X POST "http://localhost:9096/webhook?token=$TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"alerts": [{"status": "firing", "labels": {"alertname": "TestAlert"}}]}'
```

**Test playbook directly:**
```bash
~/containers/.claude/remediation/playbooks/disk-cleanup.sh
```

### Troubleshooting Remediation

**Webhook returns 401 Unauthorized:**
```bash
# Verify token matches between webhook handler and Alertmanager
grep WEBHOOK_AUTH_TOKEN ~/.config/remediation-webhook.env
grep token= ~/containers/config/alertmanager/alertmanager.yml

# Sync if needed
TOKEN=$(grep WEBHOOK_AUTH_TOKEN ~/.config/remediation-webhook.env | cut -d= -f2)
sed -i "s|token=[^']*|token=$TOKEN|" ~/containers/config/alertmanager/alertmanager.yml
systemctl --user restart alertmanager.service
```

**Remediation not executing:**
```bash
# Check webhook handler logs
journalctl --user -u remediation-webhook.service -n 50

# Verify Alertmanager is sending webhooks
podman logs alertmanager | grep webhook

# Check routing configuration
cat ~/containers/.claude/remediation/webhook-routing.yml
```

**Playbook execution fails:**
```bash
# View failure details in decision log
tail -20 ~/.claude/context/decision-log.jsonl | jq 'select(.success==false)'

# Check Discord for failure notification

# Test playbook manually
~/containers/.claude/remediation/playbooks/<playbook-name>.sh
```

**Oscillation detected (blocked loops):**
```bash
# Review decision log for rapid triggers
jq 'select(.alert=="AlertName")' ~/.claude/context/decision-log.jsonl

# Check if legitimate (restart needed) or actual loop
# If loop: investigate alert condition, may need threshold adjustment
# If legitimate: increase oscillation threshold in webhook-routing.yml
```

## File Locations

```
~/containers/
├── config/
│   ├── prometheus/
│   │   ├── prometheus.yml          # ← Scrape targets
│   │   └── alerts/rules.yml        # ← Alert rules
│   ├── alertmanager/
│   │   ├── alertmanager.yml        # ← Notification routing (gitignored - contains token)
│   │   └── alertmanager.yml.example # ← Template with placeholders
│   ├── grafana/provisioning/
│   │   ├── datasources/
│   │   └── dashboards/json/        # ← Dashboard JSON files
│   │       └── remediation-effectiveness.json # ← Auto-remediation dashboard
│   ├── promtail/
│   │   └── promtail-config.yml     # ← Log collection config (includes decision logs)
│   ├── traefik/
│   │   └── traefik.yml             # ← Access log configuration
│   └── alert-discord-relay/
│       └── relay.py                # ← Discord webhook code
├── data/
│   ├── alertmanager/                # Alert state
│   ├── grafana/                     # Grafana database
│   └── traefik-logs/                # Traefik access logs (errors only, rotated daily)
└── .claude/
    ├── context/
    │   └── decision-log.jsonl      # ← Remediation audit log (ingested to Loki)
    └── remediation/
        ├── webhook-routing.yml     # ← Webhook routing config
        ├── playbooks/              # ← Remediation scripts
        │   ├── disk-cleanup.sh
        │   ├── service-restart.sh
        │   ├── slo-violation-remediation.sh
        │   └── predictive-maintenance.sh
        └── scripts/
            └── remediation-webhook-handler.py # ← Webhook handler

~/.config/
├── remediation-webhook.env          # ← Secrets (webhook token, mode 600, NOT in Git)
└── containers/systemd/
    ├── prometheus.container         # ← Quadlet definitions
    ├── alertmanager.container
    ├── grafana.container
    ├── promtail.container
    ├── loki.container
    └── alert-discord-relay.container

~/.config/systemd/user/
└── remediation-webhook.service      # ← Webhook handler service (loads env from remediation-webhook.env)

/mnt/btrfs-pool/subvol7-containers/
└── prometheus/                      # ← Metrics database (15d retention)

/etc/logrotate.d/
└── traefik-access                   # ← Traefik log rotation (daily, 31 days retention)
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

## Useful LogQL Queries

Use these in Grafana Explore (Loki datasource) for log analysis:

### Remediation Decision Logs

**All remediation actions:**
```logql
{job="remediation-decisions"} | json
```

**Failures with error details:**
```logql
{job="remediation-decisions"} | json | success="false" | line_format "{{.alert}} → {{.playbook}}: {{.stderr}}"
```

**Success rate by playbook (last 24 hours):**
```logql
sum by (playbook, success) (count_over_time({job="remediation-decisions"} | json [24h]))
```

**Low confidence remediations (<90%):**
```logql
{job="remediation-decisions"} | json | confidence < 90 | line_format "Confidence: {{.confidence}}% | {{.alert}} → {{.playbook}}"
```

**Remediation rate (actions per hour):**
```logql
rate({job="remediation-decisions"}[1h])
```

**Oscillation detection events:**
```logql
{job="remediation-decisions"} | json | line_format "{{.stdout}}" | regexp "oscillat"
```

**Specific alert history:**
```logql
{job="remediation-decisions"} | json | alert="SystemDiskSpaceCritical"
```

### Traefik Access Logs

**All HTTP errors (4xx and 5xx):**
```logql
{job="traefik-access"} | json | status >= 400
```

**Service-specific errors:**
```logql
{job="traefik-access"} | json | service="jellyfin@docker" | status >= 500
```

**High latency requests (>1s):**
```logql
{job="traefik-access"} | json | duration > 1000
```

**Error rate by status code:**
```logql
sum by (status) (rate({job="traefik-access"} | json | status >= 400 [5m]))
```

### Correlation Queries

**Correlate remediation with service errors:**
```logql
# Step 1: Find when remediation occurred
{job="remediation-decisions"} | json | alert="SLOBurnRateTier1_Jellyfin"

# Step 2: Check Traefik errors in that timeframe
{job="traefik-access"} | json | service="jellyfin@docker" | status >= 500
```

**Full guide:** See `docs/40-monitoring-and-documentation/guides/loki-remediation-queries.md` for comprehensive query examples.

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

### Rotate Webhook Authentication Token

For security best practices, rotate the webhook token periodically (recommended: annually or after suspected exposure).

**Procedure:**

1. **Generate new token:**
```bash
NEW_TOKEN=$(openssl rand -base64 32)
echo "New token: $NEW_TOKEN"
```

2. **Update secrets file:**
```bash
sed -i "s/WEBHOOK_AUTH_TOKEN=.*/WEBHOOK_AUTH_TOKEN=$NEW_TOKEN/" \
  ~/.config/remediation-webhook.env
```

3. **Update Alertmanager config:**
```bash
sed -i "s|token=[^']*|token=$NEW_TOKEN|" \
  ~/containers/config/alertmanager/alertmanager.yml
```

4. **Restart services:**
```bash
systemctl --user restart remediation-webhook.service
systemctl --user restart alertmanager.service
```

5. **Verify:**
```bash
# Test with new token (should return 200)
curl -s -w "\nHTTP: %{http_code}\n" -X POST \
  "http://localhost:9096/webhook?token=$NEW_TOKEN" \
  -d '{"alerts": []}'
```

**See:** `docs/30-security/guides/secrets-management.md` for comprehensive secrets rotation procedures.

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

- **Rootless containers** - All services run as user processes (UID 1000), not root
- **Network isolation** - Monitoring network isolated from reverse proxy network
- **Secrets management** - Three-tier approach:
  - Podman secrets for containerized services (encrypted at rest)
  - EnvironmentFile for systemd services (remediation webhook)
  - Strict file permissions (mode 600) for all secrets
- **Webhook authentication** - Token-based auth (fail-closed, 256-bit tokens)
  - Token stored in `~/.config/remediation-webhook.env` (gitignored)
  - Alertmanager config with real token excluded from Git
  - Template files use placeholders for safe commits
- **Access control** - Authentication required for web interfaces:
  - Grafana requires login
  - Alertmanager/Prometheus accessible only via Traefik with Authelia SSO
- **SELinux enforcing** - Proper volume contexts (`:Z` labels) for all bind mounts
- **Log rotation** - Automated rotation prevents disk exhaustion attacks
- **ANSI code stripping** - Clean logs prevent injection attempts

**See:** `docs/30-security/guides/secrets-management.md` for comprehensive security documentation.

## Resources

- **Prometheus Docs**: https://prometheus.io/docs/
- **Grafana Docs**: https://grafana.com/docs/
- **PromQL Tutorial**: https://prometheus.io/docs/prometheus/latest/querying/basics/
- **Alertmanager Config**: https://prometheus.io/docs/alerting/latest/configuration/

## Quick Reference Commands

```bash
# ═══════════════════════════════════════════════════════════
# SERVICE STATUS
# ═══════════════════════════════════════════════════════════

# All monitoring services
systemctl --user status prometheus alertmanager grafana alert-discord-relay loki promtail remediation-webhook

# Individual service
systemctl --user status remediation-webhook.service

# ═══════════════════════════════════════════════════════════
# LOGS & DEBUGGING
# ═══════════════════════════════════════════════════════════

# View service logs
journalctl --user -u prometheus.service -f
journalctl --user -u remediation-webhook.service -f

# Container logs
podman logs alertmanager --tail 50
podman logs loki --tail 50

# Decision log (remediation audit trail)
tail -f ~/.claude/context/decision-log.jsonl | jq '.'

# ═══════════════════════════════════════════════════════════
# PROMETHEUS OPERATIONS
# ═══════════════════════════════════════════════════════════

# Reload Prometheus config
systemctl --user restart prometheus.service

# Check monitored targets
podman exec prometheus wget -qO- 'http://localhost:9090/api/v1/targets'

# Check active alerts
podman exec prometheus wget -qO- 'http://localhost:9090/api/v1/alerts'

# ═══════════════════════════════════════════════════════════
# REMEDIATION WEBHOOK
# ═══════════════════════════════════════════════════════════

# Health check
curl -s http://localhost:9096/health

# Manual trigger (with auth)
TOKEN=$(grep WEBHOOK_AUTH_TOKEN ~/.config/remediation-webhook.env | cut -d= -f2)
curl -X POST "http://localhost:9096/webhook?token=$TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"alerts": [{"status": "firing", "labels": {"alertname": "TestAlert"}}]}'

# View recent remediations
tail -20 ~/.claude/context/decision-log.jsonl | jq 'select(.success==true)'

# Check failure rate
jq 'select(.success==false)' ~/.claude/context/decision-log.jsonl | wc -l

# ═══════════════════════════════════════════════════════════
# LOKI QUERIES (via Grafana Explore or LogCLI)
# ═══════════════════════════════════════════════════════════

# All remediation actions
{job="remediation-decisions"} | json

# Failures only
{job="remediation-decisions"} | json | success="false"

# Traefik errors
{job="traefik-access"} | json | status >= 500

# ═══════════════════════════════════════════════════════════
# TESTING & VERIFICATION
# ═══════════════════════════════════════════════════════════

# Test Discord webhook
curl -X POST "WEBHOOK_URL" -H "Content-Type: application/json" -d '{"content":"Test"}'

# Test playbook directly
~/containers/.claude/remediation/playbooks/disk-cleanup.sh

# Verify log rotation
ls -lh ~/containers/data/traefik-logs/
journalctl --user --disk-usage
```

---

For additional help, check service logs or review Grafana dashboards for visual troubleshooting.
