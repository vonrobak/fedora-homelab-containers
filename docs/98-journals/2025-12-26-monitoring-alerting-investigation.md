# Monitoring and Alerting Investigation - Deep Dive Analysis

**Date:** 2025-12-26
**Type:** System Investigation & Recommendations
**Focus:** Alert optimization, Loki usage, UnPoller integration, remediation monitoring

---

## Executive Summary

Conducted comprehensive investigation of homelab monitoring and alerting capabilities following user request to reduce alert noise (particularly snapshot count alerts) and improve log aggregation usage. The investigation reveals a **well-architected SLO-based monitoring system** (90% noise reduction achieved in December) with specific opportunities for improvement in alert routing, Loki utilization, and network visibility.

**Key Findings:**
- ✅ **SLO-based alerting is production-grade** (Google SRE methodology implemented)
- ⚠️ **Snapshot count alerts need routing adjustment** (currently repeating every 4h)
- ⚠️ **Loki is underutilized** (collecting logs but limited querying/alerting)
- ✅ **Remediation integration working** but has critical security gaps (webhook auth missing)
- 🆕 **UnPoller opportunity** for Ubiquiti network monitoring integration

---

## Current State Analysis

### 1. SLO-Based Alerting Framework ✅ **Excellent**

**Implementation Status:** Production-ready, world-class

**What's Working:**
- **9 SLOs** across 5 critical services (Jellyfin, Immich, Authelia, Traefik, Nextcloud)
- **4-tier burn rate alerting** (Tier 1: <3h to exhaustion → Tier 4: <2 weeks)
- **Multi-window detection** prevents false positives (long + short window confirmation)
- **Error budget forecasting** provides proactive capacity planning
- **90% alert noise reduction** achieved (Dec 19 work)

**Evidence from Recent Work:**
```
2025-12-19: Alert Optimization & SLO Enhancement
- Reduced notifications: ~40/day → ~3-5/day (87-92% reduction)
- Signal-to-noise ratio: 2% → 60-80% (40x improvement)
- Eliminated flapping alerts via hysteresis

2025-12-21: Nextcloud Monitoring Enhancement
- Added complete SLO monitoring for Nextcloud
- Fixed false positive HostDown alerts
- 5 services now have full SLO coverage
```

**Dashboard Coverage:**
- 10 Grafana dashboards operational
- SLO Dashboard provides error budget visibility
- Security Overview dashboard with Loki integration

**Assessment:** This is **industry best practice** - no changes needed to core SLO framework.

---

### 2. Snapshot Count Alert Problem ⚠️ **Needs Fix**

**Current Behavior:**
```yaml
# Alert: LowSnapshotCount
# File: config/prometheus/alerts/backup-alerts.yml
expr: backup_snapshot_count{location="local"} < 2
for: 1h
severity: warning  # Routes to discord-warnings receiver
```

**Routing (from alertmanager.yml):**
```yaml
# Warning alerts
- match:
    severity: warning
  receiver: 'discord-warnings'
  repeat_interval: # Inherits from root: 4h
  active_time_intervals:
    - waking_hours  # 7am-11pm only
```

**Problem:** Snapshot count is **architectural state**, not an actionable incident. It repeats every 4 hours during waking hours, creating notification fatigue.

**Why It's Alerting:**
- Snapshot retention policy keeps 3-7 snapshots
- Count fluctuates below threshold during cleanup cycles
- Not urgent (snapshots are for recovery, <2 is concerning but not critical)

**User Request:** Change to weekly or monthly information digest instead of repeated alerts.

---

### 3. Loki Log Aggregation Usage ⚠️ **Underutilized**

**Current Configuration:**

**Promtail Collection (config/promtail/promtail-config.yml):**
```yaml
scrape_configs:
  - job_name: systemd-journal
    # Only collecting: systemd journal from /var/log/journal-export/journal.log
    # Extracting: MESSAGE, PRIORITY, _SYSTEMD_UNIT, _HOSTNAME, SYSLOG_IDENTIFIER
```

**Loki Storage:**
- Retention: 7 days (168 hours)
- Storage: Filesystem-based (TSDB)
- Compaction: 10-minute intervals

**Current Usage (Limited):**
```
Security Overview Dashboard - 3 Loki panels:
├─ CrowdSec Ban Events
├─ Authelia Failed Login Attempts
└─ Traefik Access Logs (Recent IPs)
```

**What's Missing:**

1. **No Loki-based Alerting**
   - Prometheus alerts don't use LogQL queries
   - Missing log pattern detection (e.g., repeated errors, anomaly patterns)
   - No correlation between logs and metrics

2. **Limited Log Sources**
   - Only systemd journal (container logs via journald)
   - Missing: Direct container stdout/stderr
   - Missing: Application-specific log files
   - Missing: Traefik JSON access logs (now enabled, not in Loki)

3. **No Log-Based Derived Metrics**
   - Could extract rate metrics from logs (login failures/min, errors/min)
   - Could track error patterns over time
   - Could correlate with SLO violations

4. **Minimal Dashboarding**
   - Only 3 panels use Loki (all in security dashboard)
   - Homelab Overview doesn't show logs
   - Service Health dashboard purely metric-based

**Opportunities:**

**High-Value Additions:**
- **Log-based alerts** for error patterns (e.g., "OOMKilled" in container logs)
- **Correlation dashboards** showing logs alongside metrics during incidents
- **Traefik access log ingestion** (JSON logs now available from security review)
- **Failed remediation alerting** via Loki (currently only in decision-log.jsonl)

**Medium-Value Additions:**
- **Derived metrics** from logs (e.g., rate(level="error") by service)
- **Log retention tiers** (7 days full, 30 days sampled for patterns)
- **Application log collection** for services with file-based logging

---

### 4. Remediation System Integration ⚠️ **Working But Gaps**

**Current Implementation:**

**Webhook Integration (Phase 3-4 complete):**
```yaml
# Alertmanager routes to remediation webhook
- matchers:
    - alertname =~ "SLOBurnRateTier1_.*|SLOBurnRateTier2_.*"
  receiver: 'remediation-webhook'
  continue: true  # Also sends to Discord
```

**Active Service:**
```
remediation-webhook.service: running on localhost:9096
```

**Production Usage (Dec 23-25):**
```
Total executions: 18
Active playbooks: 7 (disk-cleanup, predictive-maintenance, slo-violation-remediation, etc.)
Success rate: 94% (17 success, 1 failure)
```

**Critical Issues from 2025-12-25 Review:**

1. 🔴 **CRITICAL: No Webhook Authentication**
   - Endpoint: http://localhost:9096/webhook (unauthenticated)
   - Risk: Remote command execution if exposed
   - Fix: Add HMAC signature validation

2. 🔴 **CRITICAL: No Remediation Failure Alerting**
   - Failed remediations only logged to decision-log.jsonl
   - User unaware of automation failures
   - Fix: Send Discord notification on all failures

3. 🟡 **No Webhook Loop Prevention**
   - Alert → Remediation → Alert cycles possible
   - Fix: Add per-alert cooldown (30min)

4. 🟡 **Monitoring Integration Missing**
   - No Grafana dashboard for remediation metrics
   - Analytics premature (18 executions, 2 days data)
   - Fix: Wait 30 days for baseline, then build dashboard

**Assessment:** Webhook automation works but needs security hardening before expansion.

---

### 5. UnPoller Integration Opportunity 🆕 **New Capability**

**What is UnPoller:**
- Golang application that polls UniFi Controller API
- Exports metrics in Prometheus format
- Provides network-layer visibility (clients, bandwidth, DPI, device health)

**Data Flow:**
```
UniFi Devices → UniFi Controller → UnPoller → Prometheus → Grafana
```

**Available Dashboards (Grafana Hub):**
- UniFi-Poller: Client Insights (Dashboard ID: 11315)
- UniFi-Poller: UAP Insights (Dashboard ID: 11314) - Access Points
- UniFi-Poller: USG Insights (Dashboard ID: 11313) - Gateway
- UniFi-Poller: Network Sites (Dashboard ID: 11311)
- UniFi-Poller: Switch Insights (Dashboard ID: multiple)

**Metrics Exposed:**
- **Client metrics:** Connection quality, signal strength, data transfer
- **AP metrics:** Channel utilization, interference, connected clients
- **Gateway metrics:** WAN/LAN throughput, DPI classification, firewall activity
- **Switch metrics:** Port status, PoE usage, bandwidth per port

**Value for Homelab:**

**Operational Benefits:**
- Network performance correlation with service issues
- Client connectivity troubleshooting (WiFi signal, roaming)
- Bandwidth usage visibility (identify heavy users/applications)
- DPI insights (understand traffic patterns)

**Learning Value:**
- Enterprise observability patterns (network + application correlation)
- Time-series analysis of network behavior
- Capacity planning for network infrastructure
- Understanding WiFi performance metrics

**Integration Approach:**

**Deployment Pattern:**
```yaml
# Container: unpoller.container (systemd quadlet)
Image: ghcr.io/unpoller/unpoller:latest
Network: systemd-monitoring  # Internal network with Prometheus

Environment:
  UP_UNIFI_DEFAULT_URL: "https://unifi.patriark.org"
  UP_UNIFI_DEFAULT_USER: "unpoller-readonly"  # Create service account
  UP_UNIFI_DEFAULT_PASS: <secret>  # Use podman secret
  UP_PROMETHEUS_NAMESPACE: "unifi_"  # Metric prefix

PublishPort: 9130:9130  # Metrics endpoint for Prometheus
```

**Prometheus Scrape Config:**
```yaml
# config/prometheus/prometheus.yml
- job_name: 'unifi'
  static_configs:
    - targets: ['unpoller:9130']
      labels:
        instance: 'fedora-htpc'
        service: 'unifi-network'
  scrape_interval: 30s  # Longer interval (network metrics change slowly)
```

**Grafana Dashboards:**
```bash
# Import pre-built dashboards from Grafana Hub
curl -so ~/containers/config/grafana/provisioning/dashboards/json/unifi-clients.json \
  https://grafana.com/api/dashboards/11315/revisions/latest/download

# Repeat for other dashboards (UAP, USG, Network Sites)
```

**SLO Opportunity:**
```yaml
# Example: Network availability SLO
SLO-010: WAN Uptime
  Target: 99.9% (ISP SLA)
  SLI: avg_over_time(up{job="unifi", device_type="gateway"}[5m])

SLO-011: WiFi Client Satisfaction
  Target: 95% of clients with signal >-70 dBm
  SLI: Derived from unifi_client_signal_dbm histogram
```

**Recommended Timeline:**
1. **Week 1:** Deploy UnPoller container, verify Prometheus scraping
2. **Week 2:** Import 2-3 key dashboards (Clients, UAP, Gateway)
3. **Week 3:** Baseline data collection (understand normal patterns)
4. **Week 4:** Define network SLOs if valuable patterns emerge

**Caveats:**
- **UniFi Controller required:** Must have existing UniFi network setup
- **API access:** Create read-only service account (don't use admin)
- **Metric volume:** ~500-1500 metrics depending on device count (manageable)
- **Value vs complexity:** Only deploy if network visibility is actually needed

---

## Recommendations (Prioritized)

### IMMEDIATE (This Week)

#### 1. Fix Snapshot Count Alert Routing 🔴 **HIGH PRIORITY**

**Problem:** LowSnapshotCount repeating every 4h creates noise

**Solution A: Weekly Digest (Recommended)**
```yaml
# config/alertmanager/alertmanager.yml

# Add new receiver for informational digests
receivers:
  - name: 'digest-weekly'
    webhook_configs:
      - url: 'http://alert-discord-relay:9095/webhook'
        send_resolved: false  # Don't spam resolves

# Add route for architectural alerts
routes:
  - match:
      category: backup
      alertname: LowSnapshotCount
    receiver: 'digest-weekly'
    repeat_interval: 168h  # 1 week
    group_interval: 24h    # Batch daily checks into weekly notification

  # Same for ExternalBackupMissing (also architectural)
  - match:
      category: backup
      alertname: ExternalBackupMissing
    receiver: 'digest-weekly'
    repeat_interval: 168h
```

**Solution B: Monthly Report (Alternative)**
```bash
# Add snapshot metrics to existing monthly SLO report
# File: scripts/monthly-slo-report.sh

# Add section:
## Backup Health Summary
- Local snapshot count (by subvolume)
- External backup status
- Last successful backup timestamps
```

**Recommendation:** **Use Solution A** (weekly digest) for timely awareness without noise.

**Implementation:**
```bash
# 1. Edit alertmanager config
nano ~/containers/config/alertmanager/alertmanager.yml

# 2. Reload Alertmanager
systemctl --user restart alertmanager.service

# 3. Verify routing
curl -s http://localhost:9093/api/v2/status | jq '.config.route'
```

---

#### 2. Add Remediation Failure Alerting 🔴 **HIGH PRIORITY**

**Problem:** Failed remediations invisible to user (only in decision-log.jsonl)

**Solution:** Discord webhook notification on remediation failures

**Implementation:**
```python
# File: .claude/remediation/scripts/remediation-webhook-handler.py
# Add after line ~85 (after logging failure):

def send_failure_notification(alert_name, playbook, reason):
    """Send Discord notification when remediation fails"""
    import requests

    webhook_url = os.getenv('DISCORD_WEBHOOK_URL')  # Reuse existing webhook

    payload = {
        "content": "🚨 **Remediation Failed**",
        "embeds": [{
            "title": f"Failed to remediate: {alert_name}",
            "description": f"Playbook `{playbook}` execution failed",
            "color": 15158332,  # Red
            "fields": [
                {"name": "Alert", "value": alert_name, "inline": True},
                {"name": "Playbook", "value": playbook, "inline": True},
                {"name": "Reason", "value": reason or "Unknown", "inline": False}
            ],
            "footer": {"text": "Check ~/containers/.claude/remediation/metrics-history.json"},
            "timestamp": datetime.utcnow().isoformat()
        }]
    }

    try:
        requests.post(webhook_url, json=payload, timeout=5)
    except Exception as e:
        logger.error(f"Failed to send Discord notification: {e}")

# Call after remediation failure (line ~90):
send_failure_notification(alert_name, playbook, result.get('error'))
```

**Testing:**
```bash
# Trigger a known failure (safe test)
curl -X POST http://localhost:9096/webhook \
  -H "Content-Type: application/json" \
  -d '{"alerts": [{"labels": {"alertname": "TestFailure"}}]}'

# Check Discord for failure notification
```

---

#### 3. Secure Remediation Webhook 🔴 **CRITICAL SECURITY**

**Problem:** Unauthenticated webhook endpoint (localhost:9096)

**Solution:** Add HMAC signature validation (matches Alertmanager capability)

**Implementation:**
```yaml
# 1. Generate shared secret
SECRET=$(openssl rand -hex 32)
echo "$SECRET" | podman secret create remediation-webhook-secret -

# 2. Configure Alertmanager to sign requests
# File: config/alertmanager/alertmanager.yml
receivers:
  - name: 'remediation-webhook'
    webhook_configs:
      - url: 'http://host.containers.internal:9096/webhook'
        http_config:
          authorization:
            type: Bearer
            credentials_file: /run/secrets/remediation-webhook-secret

# 3. Update webhook handler to validate
# File: .claude/remediation/scripts/remediation-webhook-handler.py
import hmac
import hashlib

EXPECTED_SECRET = os.getenv('WEBHOOK_SECRET')  # From podman secret

@app.route('/webhook', methods=['POST'])
def webhook():
    # Validate authorization header
    auth_header = request.headers.get('Authorization', '')
    if not auth_header.startswith('Bearer '):
        return jsonify({'error': 'Unauthorized'}), 401

    provided_secret = auth_header[7:]  # Remove 'Bearer ' prefix
    if not hmac.compare_digest(provided_secret, EXPECTED_SECRET):
        logger.warning(f"Unauthorized webhook attempt from {request.remote_addr}")
        return jsonify({'error': 'Invalid credentials'}), 403

    # Continue with existing logic...
```

**Note:** This is **CRITICAL** - implement before exposing beyond localhost.

---

### SHORT-TERM (This Month)

#### 4. Enhance Loki Usage for Log-Based Insights 🟡 **MEDIUM PRIORITY**

**Goal:** Move from passive log collection to active log-driven monitoring

**Phase 1: Traefik Access Log Ingestion**

**Context:** Security review enabled JSON access logging (Dec 26)

**Implementation:**
```yaml
# File: config/promtail/promtail-config.yml
# Add new scrape config:

scrape_configs:
  # ... existing systemd-journal config ...

  - job_name: traefik-access-logs
    docker_sd_configs:
      - host: unix:///run/user/1000/podman/podman.sock
        filters:
          - name: name
            values: [traefik]
    relabel_configs:
      - source_labels: ['__meta_docker_container_name']
        target_label: 'container'
    pipeline_stages:
      - docker: {}      # Parse Docker log wrapper
      - json:           # Parse Traefik JSON logs
          expressions:
            time: time
            level: level
            msg: msg
            method: RequestMethod
            path: RequestPath
            status: DownstreamStatus
            duration: Duration
            client_addr: ClientAddr
      - labels:
          method:
          status:
          container:
      - timestamp:
          source: time
          format: RFC3339
```

**Restart Promtail:**
```bash
systemctl --user restart promtail.service

# Verify ingestion
curl -s 'http://localhost:3100/loki/api/v1/label/__name__/values' | jq
# Should show: method, status, container labels
```

**Phase 2: Log-Based Alerting**

**Use Case:** Detect error patterns not visible in metrics

**Example Alerts:**
```yaml
# File: config/loki/rules/log-alerts.yml (new file)

groups:
  - name: log_pattern_alerts
    interval: 1m
    rules:
      # Alert on OOMKilled containers
      - alert: ContainerOOMKilled
        expr: |
          sum(count_over_time({unit=~".*.service"}
            |~ "OOMKilled|Out of memory" [5m])) > 0
        labels:
          severity: critical
          category: resource-pressure
        annotations:
          summary: "Container killed due to OOM"
          description: "Check memory limits and usage patterns"

      # Alert on repeated authentication failures
      - alert: RepeatedAuthFailures
        expr: |
          sum(rate({syslog_id="authelia"}
            |= "authentication failed" [5m])) by (container) > 5
        for: 10m
        labels:
          severity: warning
          category: security
        annotations:
          summary: "Elevated authentication failures"
          description: "{{ $value }} failed attempts/sec - possible brute force"

      # Alert on application errors in logs
      - alert: HighLogErrorRate
        expr: |
          sum(rate({unit=~".*.service"}
            | json
            | level="error" [5m])) by (unit) > 1
        for: 5m
        labels:
          severity: warning
          category: application
        annotations:
          summary: "High error log rate in {{ $labels.unit }}"
          description: "{{ $value }} errors/sec - investigate application health"
```

**Enable Loki Ruler:**
```yaml
# File: config/loki/loki-config.yml (already configured!)
# Ruler section exists at line 72-83, just needs rule files:

# Create rules directory
mkdir -p ~/containers/config/loki/rules

# Copy alert rules
cp <alert-file> ~/containers/config/loki/rules/log-alerts.yml

# Restart Loki
systemctl --user restart loki.service

# Verify rules loaded
curl -s http://localhost:3100/loki/api/v1/rules | jq
```

**Phase 3: Correlation Dashboard**

**Goal:** Show logs alongside metrics during incident investigation

**Grafana Panel Configuration:**
```json
// Add to Service Health dashboard
// Panel: "Recent Error Logs"
{
  "datasource": "Loki",
  "targets": [{
    "expr": "{unit=~\".*.service\"} | json | level=\"error\"",
    "refId": "A"
  }],
  "transformations": [{
    "id": "organize",
    "options": {
      "excludeByName": {},
      "indexByName": {},
      "renameByName": {
        "message": "Error Message",
        "unit": "Service"
      }
    }
  }]
}
```

**Value:** During SLO violation, immediately see correlated error logs.

---

#### 5. Build Remediation Effectiveness Dashboard 🟡 **MEDIUM PRIORITY**

**Goal:** Visualize remediation metrics without waiting for monthly reports

**Prerequisite:** Wait 30 days for baseline data (currently only 2 days)

**Grafana Dashboard Panels:**

**Panel 1: Remediation Success Rate (7-day rolling)**
```promql
# Custom exporter needed - expose metrics from metrics-history.json
# Pattern: remediation_executions_total{playbook="disk-cleanup", outcome="success"}

sum(rate(remediation_executions_total{outcome="success"}[7d]))
  /
sum(rate(remediation_executions_total[7d]))
  * 100
```

**Panel 2: Top Playbooks by Execution Count**
```promql
topk(5, sum by (playbook) (increase(remediation_executions_total[7d])))
```

**Panel 3: Failed Remediations (alert on any)**
```promql
# Table panel showing all failures in last 24h
remediation_executions_total{outcome="failure"} > 0
```

**Panel 4: Time Saved (from ROI calculations)**
```
# Gauge panel showing monthly time savings
# Source: Manual calculation from monthly report
# Future: Export from remediation-roi.sh to JSON, ingest to Prometheus
```

**Implementation Note:** Requires custom Prometheus exporter for remediation metrics.

**Alternative:** Embed monthly report markdown in Grafana using "Text" panel (simpler).

---

#### 6. Add Webhook Loop Prevention 🟡 **MEDIUM PRIORITY**

**Problem:** Alert → Remediation → Alert → Remediation loops possible

**Solution:** Cooldown tracking in webhook handler

**Implementation:**
```python
# File: .claude/remediation/scripts/remediation-webhook-handler.py

import time
from collections import defaultdict

# Cooldown tracker: {alert_name: last_execution_timestamp}
cooldown_tracker = defaultdict(float)
COOLDOWN_SECONDS = 1800  # 30 minutes

@app.route('/webhook', methods=['POST'])
def webhook():
    # ... existing auth validation ...

    for alert in data.get('alerts', []):
        alert_name = alert['labels'].get('alertname')

        # Check cooldown
        last_execution = cooldown_tracker.get(alert_name, 0)
        time_since_last = time.time() - last_execution

        if time_since_last < COOLDOWN_SECONDS:
            remaining = COOLDOWN_SECONDS - time_since_last
            logger.info(f"Skipping {alert_name} - cooldown active "
                       f"({remaining:.0f}s remaining)")

            # Log skipped execution
            log_decision(alert_name, 'skipped', 'cooldown_active',
                        {'cooldown_remaining_sec': remaining})
            continue

        # Execute remediation
        result = execute_remediation(alert_name, playbook)

        # Update cooldown tracker
        cooldown_tracker[alert_name] = time.time()

        # ... rest of existing logic ...
```

**Testing:**
```bash
# Trigger same alert twice within 30 min
curl -X POST http://localhost:9096/webhook \
  -d '{"alerts": [{"labels": {"alertname": "TestAlert"}}]}'

sleep 5

# Second call should be skipped (cooldown active)
curl -X POST http://localhost:9096/webhook \
  -d '{"alerts": [{"labels": {"alertname": "TestAlert"}}]}'

# Check decision log for "cooldown_active" reason
jq 'select(.reason == "cooldown_active")' ~/.claude/remediation/decision-log.jsonl
```

---

### LONG-TERM (Next Quarter)

#### 7. Deploy UnPoller for Network Monitoring 🔵 **OPTIONAL**

**Decision Criteria:** Only deploy if network visibility is actually needed

**Use Cases That Justify Deployment:**
- Troubleshooting WiFi connectivity issues
- Understanding bandwidth patterns by client/application
- Capacity planning for network infrastructure
- Correlating network issues with service degradation
- Learning enterprise network observability patterns

**Implementation Plan (4 weeks):**

**Week 1: UniFi Controller Preparation**
```bash
# Create read-only service account in UniFi Controller
# Settings → Admins → Add Admin
#   Role: Read Only
#   Username: unpoller-readonly
#   Password: <generate strong password>
```

**Week 2: UnPoller Deployment**
```bash
# Create podman secret for UniFi credentials
echo -n 'password' | podman secret create unifi-password -

# Create quadlet file
cat > ~/.config/containers/systemd/unpoller.container << 'EOF'
[Unit]
Description=UnPoller - UniFi Metrics Exporter
After=network-online.target monitoring-network.service
Wants=network-online.target
Requires=monitoring-network.service

[Container]
Image=ghcr.io/unpoller/unpoller:latest
ContainerName=unpoller
AutoUpdate=registry

# Network (monitoring only - internal metrics)
Network=systemd-monitoring

# Environment - UniFi Controller connection
Environment=UP_UNIFI_DEFAULT_URL=https://unifi.patriark.org
Environment=UP_UNIFI_DEFAULT_USER=unpoller-readonly
Environment=UP_UNIFI_DEFAULT_VERIFY_SSL=true
Secret=unifi-password,type=env,target=UP_UNIFI_DEFAULT_PASS

# Environment - Prometheus export
Environment=UP_PROMETHEUS_NAMESPACE=unifi_
Environment=UP_PROMETHEUS_HTTP_LISTEN=0.0.0.0:9130

# Expose metrics port
PublishPort=9130:9130

# Resource limits
Memory=256M

[Service]
Slice=container.slice
Restart=on-failure
TimeoutStartSec=120

# Resource Limits (systemd cgroup)
MemoryMax=256M

[Install]
WantedBy=default.target
EOF

# Deploy
systemctl --user daemon-reload
systemctl --user enable --now unpoller.service

# Verify metrics
curl http://localhost:9130/metrics | grep unifi_
```

**Week 3: Prometheus Integration**
```yaml
# config/prometheus/prometheus.yml
scrape_configs:
  - job_name: 'unifi'
    static_configs:
      - targets: ['unpoller:9130']
        labels:
          instance: 'fedora-htpc'
          service: 'unifi-network'
    scrape_interval: 30s
    scrape_timeout: 10s
```

**Week 4: Grafana Dashboards**
```bash
# Import pre-built dashboards from Grafana Hub
cd ~/containers/config/grafana/provisioning/dashboards/json/

# Client Insights (most valuable for homelab)
curl -so unifi-client-insights.json \
  https://grafana.com/api/dashboards/11315/revisions/latest/download

# Access Point Insights
curl -so unifi-uap-insights.json \
  https://grafana.com/api/dashboards/11314/revisions/latest/download

# Network Sites Overview
curl -so unifi-network-sites.json \
  https://grafana.com/api/dashboards/11311/revisions/latest/download

# Restart Grafana to load dashboards
systemctl --user restart grafana.service
```

**Baseline & Validation (Week 5+):**
- Collect 2 weeks of baseline data
- Identify normal patterns (bandwidth by hour, client count by day)
- Determine if insights are valuable enough to maintain
- Consider SLO definitions if patterns emerge

**Cost/Benefit Analysis:**
- **Resource cost:** ~256MB RAM, minimal CPU, ~500-1500 Prometheus metrics
- **Operational cost:** One more service to maintain, UniFi account to manage
- **Learning value:** High (enterprise network observability patterns)
- **Operational value:** Variable (depends on network troubleshooting needs)

**Recommendation:** **Deploy if user has existing UniFi network and wants network visibility.** Skip if not using UniFi equipment.

---

#### 8. Implement Log-Derived Metrics 🔵 **OPTIONAL**

**Goal:** Extract rate metrics from logs for alerting without regex queries

**Use Case:** Faster alerts using Prometheus instead of LogQL

**Example:**
```yaml
# Loki recording rule (config/loki/rules/derived-metrics.yml)
# Extracts error rate metric from logs

name: derived_metrics
interval: 1m
rules:
  - record: log_error_rate:1m
    expr: |
      sum by (unit) (
        rate({unit=~".*.service"} | json | level="error" [1m])
      )
```

**Prometheus alert using derived metric:**
```yaml
# Faster than LogQL query (uses pre-computed metric)
- alert: HighLogErrorRate
  expr: log_error_rate:1m > 1
  for: 5m
```

**Value:** Reduces Loki query load, enables faster alerting.

**Caveat:** Requires Loki 2.8+ for recording rules (check version).

---

## Summary of Recommendations

### Prioritized Actions

| Priority | Action | Estimated Effort | Impact |
|----------|--------|------------------|--------|
| 🔴 HIGH | Fix snapshot alert routing (weekly digest) | 30 min | Immediate noise reduction |
| 🔴 HIGH | Add remediation failure alerting | 1 hour | Critical visibility gap |
| 🔴 CRITICAL | Secure webhook endpoint (HMAC auth) | 2 hours | Security hardening |
| 🟡 MEDIUM | Enhance Loki usage (access logs + alerts) | 4 hours | Better incident detection |
| 🟡 MEDIUM | Build remediation dashboard (after 30d) | 2 hours | Operational visibility |
| 🟡 MEDIUM | Add webhook loop prevention | 1 hour | Prevent automation loops |
| 🔵 OPTIONAL | Deploy UnPoller (if network visibility needed) | 4 weeks | Network monitoring |
| 🔵 OPTIONAL | Implement log-derived metrics | 3 hours | Performance optimization |

### Decision Framework

**Do First (Week 1):**
1. Snapshot alert routing fix ← **Immediate user pain point**
2. Webhook security hardening ← **Critical security gap**
3. Remediation failure alerting ← **Operational blind spot**

**Do Soon (This Month):**
4. Loki access log ingestion ← **Leverage existing capability**
5. Log-based alerting (OOMKilled, auth failures) ← **Catch new failure modes**
6. Webhook loop prevention ← **Prevent future issues**

**Do Later (When Justified):**
7. Remediation dashboard ← **Wait for 30 days of data**
8. UnPoller deployment ← **Only if network visibility actually needed**
9. Log-derived metrics ← **Optimization, not critical**

---

## Key Insights

### What's Working Exceptionally Well

1. **SLO-Based Alerting:** World-class implementation, 90% noise reduction achieved
2. **Multi-Window Burn Rate Detection:** Prevents false positives while catching real issues
3. **Remediation Webhook Integration:** Actually working in production (18 executions)
4. **Grafana Dashboard Ecosystem:** 10 dashboards providing comprehensive visibility

### What Needs Improvement

1. **Alert Routing Granularity:** Architectural alerts (snapshots) need different cadence than incidents
2. **Loki Underutilization:** Collecting logs but not actively alerting or correlating
3. **Remediation Security:** Webhook lacks authentication, failure alerting missing
4. **Network Visibility Gap:** No visibility into network layer (UnPoller could fill this)

### Strategic Alignment

**Current Focus:** Metric-driven SLO monitoring (excellent)

**Missing Layer:** Log-driven pattern detection (Loki capable but underused)

**Future Opportunity:** Network-layer correlation (UnPoller for complete observability)

**Philosophy:** **Start with user impact (SLOs), add context via logs, optionally expand to network layer if valuable**

---

## Implementation Notes

### Testing Strategy

**Before Production:**
1. **Alertmanager changes:** Test routing with `amtool` before deploying
2. **Webhook changes:** Test with curl before relying on automation
3. **Loki rules:** Validate LogQL queries in Grafana Explore before alerting
4. **New services:** Run for 1 week with verbose logging before trusting

**Validation:**
```bash
# Alertmanager routing test
amtool --alertmanager.url=http://localhost:9093 config routes test \
  severity=warning alertname=LowSnapshotCount

# Expected: Routes to 'digest-weekly' receiver

# Webhook security test (should fail without auth)
curl -X POST http://localhost:9096/webhook -d '{"alerts": []}'
# Expected: 401 Unauthorized
```

### Rollback Plan

**All changes are configuration-based:**
- Alertmanager: `git revert` + `systemctl restart`
- Promtail: `git revert` + `systemctl restart`
- Loki rules: Delete rule file + `systemctl restart`
- Webhook: `git revert` + `systemctl restart`

**No schema changes, no data loss risk.**

---

## References

**Documentation Reviewed:**
- `/docs/40-monitoring-and-documentation/guides/slo-framework.md`
- `/docs/40-monitoring-and-documentation/guides/slo-based-alerting.md`
- `/docs/40-monitoring-and-documentation/guides/monitoring-stack.md`
- `/docs/98-journals/2025-12-19-alert-optimization-slo-enhancement.md`
- `/docs/98-journals/2025-12-21-nextcloud-monitoring-enhancement-alert-fixes.md`
- `/docs/98-journals/2025-12-25-remediation-phase-6-implementation.md`
- `/docs/99-reports/2025-12-25-remediation-critical-review.md`

**External Resources:**
- [UnPoller GitHub Repository](https://github.com/unpoller/unpoller)
- [Building Enterprise-Style UniFi Observability](https://technotim.live/posts/unpoller-unifi-metrics/) - Techno Tim (Dec 21, 2025)
- [UnPoller Grafana Dashboards](https://grafana.com/grafana/dashboards/) - Dashboard IDs: 11311, 11313, 11314, 11315
- [Google SRE Book - Alerting on SLOs](https://sre.google/workbook/alerting-on-slos/)

**Configuration Files Analyzed:**
- `config/alertmanager/alertmanager.yml`
- `config/prometheus/alerts/*.yml` (8 files)
- `config/prometheus/rules/*.yml` (2 files)
- `config/loki/loki-config.yml`
- `config/promtail/promtail-config.yml`
- `config/grafana/provisioning/dashboards/json/` (10 dashboards)

---

## Next Steps

**For User Review:**
1. Prioritize recommendations based on immediate needs
2. Decide on UnPoller deployment (network visibility value assessment)
3. Approve security changes (webhook auth, failure alerting)
4. Confirm preferred approach for snapshot alerts (weekly digest vs monthly report)

**After User Approval:**
- Create implementation plan with specific timelines
- Test changes in non-production first
- Document new configurations
- Update monitoring-stack.md guide with new capabilities

---

**Status:** Investigation Complete - Awaiting User Review
**Next Phase:** Implementation Plan (after user feedback)
**Estimated Review Time:** 15-20 minutes
**Decision Points:** 4 (snapshot routing, webhook security, UnPoller deployment, Loki enhancement priority)
