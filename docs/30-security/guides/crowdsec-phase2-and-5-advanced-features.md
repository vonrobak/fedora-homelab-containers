# CrowdSec Phase 2 & 5: Advanced Features

**Version:** 1.0
**Last Updated:** 2025-11-12
**Prerequisites:** Phase 1 completed
**Combined Duration:** 90-120 minutes
**Risk Level:** Low

---

## Document Structure

This document combines two advanced feature sets:

- **Phase 2:** Observability Integration (Metrics + Dashboards + Alerts)
- **Phase 5:** Advanced Hardening (Custom Pages + Notifications + Reputation)

Both phases are optional but recommended for production operations.

---

## Phase 2: Observability Integration

**Duration:** 60-75 minutes | **Priority:** HIGH

### Overview

Integrate CrowdSec metrics into your existing Prometheus/Grafana/Alertmanager stack for comprehensive security monitoring.

### Objectives

- Expose CrowdSec metrics to Prometheus
- Create dedicated Grafana dashboard
- Configure alerting for security events
- Enable structured logging

### Prerequisites

- Prometheus/Grafana/Alertmanager deployed (already in place)
- CrowdSec running and healthy
- Network connectivity between monitoring and CrowdSec

---

### 2.1: Metrics Exporter Setup

**Duration:** 15 minutes

#### Install Prometheus CrowdSec Exporter

```bash
# CrowdSec has built-in Prometheus metrics on port 6060
# Configure in CrowdSec config.yaml (if not already enabled)

# Check if metrics are exposed
podman exec crowdsec curl -s http://localhost:6060/metrics | head -20

# Expected: Prometheus-format metrics output
```

#### Configure Prometheus Scraping

```bash
# Edit Prometheus configuration
cd ~/containers/config/prometheus

# Add CrowdSec scrape target
cat >> prometheus.yml <<'EOF'

  # CrowdSec Security Engine Metrics
  - job_name: 'crowdsec'
    static_configs:
      - targets: ['crowdsec:6060']
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        replacement: 'crowdsec-engine'
EOF

# Reload Prometheus
podman exec prometheus kill -HUP 1

# Verify target is up
# Check: http://prometheus:9090/targets
# Look for: crowdsec (1/1 up)
```

#### Verify Metrics Collection

```bash
# Query CrowdSec metrics in Prometheus
curl -s 'http://localhost:9090/api/v1/query?query=crowdsec_engine_info' | jq

# Expected: version, features, etc.

# Check key metrics
cat > /tmp/verify-crowdsec-metrics.sh <<'EOF'
#!/bin/bash
METRICS=(
    "crowdsec_lapi_decisions_total"
    "crowdsec_lapi_machine_requests_total"
    "crowdsec_engine_alerts_total"
)

for metric in "${METRICS[@]}"; do
    result=$(curl -s "http://localhost:9090/api/v1/query?query=$metric" | jq -r '.data.result[0].value[1]')
    echo "$metric: $result"
done
EOF

chmod +x /tmp/verify-crowdsec-metrics.sh
/tmp/verify-crowdsec-metrics.sh
```

**Success Criteria:**
- [ ] Metrics endpoint accessible
- [ ] Prometheus scraping successfully
- [ ] Key metrics returning data

---

### 2.2: Grafana Dashboard Creation

**Duration:** 25 minutes

#### Import CrowdSec Dashboard Template

```bash
# Download community dashboard or create custom
cd ~/containers/config/grafana/provisioning/dashboards/json

cat > crowdsec-overview.json <<'DASHBOARD'
{
  "dashboard": {
    "title": "CrowdSec Security Overview",
    "tags": ["security", "crowdsec"],
    "timezone": "browser",
    "panels": [
      {
        "title": "Active Decisions (Bans)",
        "type": "stat",
        "targets": [{
          "expr": "crowdsec_lapi_decisions_total",
          "legendFormat": "Total Bans"
        }],
        "gridPos": {"h": 4, "w": 6, "x": 0, "y": 0}
      },
      {
        "title": "Decision Origins",
        "type": "piechart",
        "targets": [{
          "expr": "sum by (origin) (crowdsec_lapi_decisions_total)",
          "legendFormat": "{{origin}}"
        }],
        "gridPos": {"h": 8, "w": 6, "x": 6, "y": 0}
      },
      {
        "title": "Alerts Over Time",
        "type": "graph",
        "targets": [{
          "expr": "rate(crowdsec_engine_alerts_total[5m])",
          "legendFormat": "Alerts/sec"
        }],
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 4}
      },
      {
        "title": "Top Banned IPs",
        "type": "table",
        "targets": [{
          "expr": "topk(10, crowdsec_lapi_decisions_total)",
          "format": "table"
        }],
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 4}
      },
      {
        "title": "Scenario Triggers",
        "type": "bargauge",
        "targets": [{
          "expr": "sum by (scenario) (crowdsec_engine_alerts_total)",
          "legendFormat": "{{scenario}}"
        }],
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 12}
      },
      {
        "title": "Bouncer Activity",
        "type": "graph",
        "targets": [{
          "expr": "rate(crowdsec_lapi_machine_requests_total{type=\"bouncer\"}[5m])",
          "legendFormat": "Bouncer Queries/sec"
        }],
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 12}
      }
    ],
    "refresh": "30s",
    "time": {"from": "now-24h", "to": "now"}
  },
  "overwrite": true
}
DASHBOARD

# Restart Grafana to load dashboard
systemctl --user restart grafana.service

# Access dashboard: http://grafana.patriark.org/d/crowdsec-overview
```

#### Create Custom Panels (Optional)

**Key Visualizations:**
1. **Decision Count by Severity** - Pie chart showing severe/aggressive/standard ban distribution
2. **CAPI vs Local Decisions** - Compare global threat intel vs local detections
3. **False Positive Rate** - Track deleted decisions (potential FPs)
4. **Geographic Distribution** - If GeoIP data available
5. **Attack Timeline** - Heatmap of attack patterns by time of day

**Dashboard Organization:**
```
Row 1: High-Level Stats
  - Total Active Bans
  - Alerts (24h)
  - CAPI Sync Status
  - Top Attack Type

Row 2: Decision Analysis
  - Decision Origins (pie)
  - Ban Durations (histogram)
  - Top Scenarios (table)

Row 3: Time Series
  - Alerts Over Time (graph)
  - Bouncer Query Rate (graph)
  - Decision Additions/Deletions (graph)

Row 4: Operational Health
  - LAPI Response Time
  - Parser Success Rate
  - Hub Update Status
```

**Success Criteria:**
- [ ] Dashboard accessible in Grafana
- [ ] All panels showing data
- [ ] Auto-refresh working
- [ ] Dashboard saved in provisioning

---

### 2.3: Alerting Configuration

**Duration:** 15 minutes

#### Create Alertmanager Alert Rules

```bash
# Add CrowdSec alert rules
cd ~/containers/config/prometheus

cat > rules/crowdsec-alerts.yml <<'EOF'
groups:
  - name: crowdsec_security
    interval: 1m
    rules:
      # Critical: CrowdSec Down
      - alert: CrowdSecDown
        expr: up{job="crowdsec"} == 0
        for: 5m
        labels:
          severity: critical
          component: security
        annotations:
          summary: "CrowdSec security engine is down"
          description: "CrowdSec has been unreachable for 5 minutes. Security layer compromised."

      # Warning: High Attack Volume
      - alert: CrowdSecHighAttackVolume
        expr: rate(crowdsec_engine_alerts_total[5m]) > 10
        for: 10m
        labels:
          severity: warning
          component: security
        annotations:
          summary: "High volume of security alerts detected"
          description: "CrowdSec is detecting >10 alerts/second for 10+ minutes. Possible attack in progress."

      # Warning: CAPI Sync Failed
      - alert: CrowdSecCAPIDown
        expr: time() - crowdsec_capi_last_pull_timestamp > 14400  # 4 hours
        for: 15m
        labels:
          severity: warning
          component: security
        annotations:
          summary: "CrowdSec CAPI not syncing"
          description: "CAPI hasn't pulled blocklist in >4 hours. Global threat intel may be stale."

      # Info: Large Ban Spike
      - alert: CrowdSecBanSpike
        expr: rate(crowdsec_lapi_decisions_total[5m]) > 50
        for: 5m
        labels:
          severity: info
          component: security
        annotations:
          summary: "Spike in CrowdSec ban decisions"
          description: "Unusually high rate of bans. Check for attacks or false positives."

      # Warning: Bouncer Disconnected
      - alert: CrowdSecBouncerDown
        expr: crowdsec_lapi_machine_last_heartbeat{type="bouncer"} < (time() - 300)
        for: 5m
        labels:
          severity: warning
          component: security
        annotations:
          summary: "CrowdSec bouncer disconnected"
          description: "Traefik bouncer hasn't checked in for 5+ minutes. Bans not being enforced."
EOF

# Reload Prometheus rules
podman exec prometheus kill -HUP 1

# Verify rules loaded
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[] | select(.name=="crowdsec_security")'
```

#### Configure Discord Notifications (Optional)

```bash
# Add Discord webhook to Alertmanager
# Already configured in your setup - just add routing

# Edit alertmanager.yml to include CrowdSec alerts
cd ~/containers/config/alertmanager

# Add route for security alerts (if not already present)
cat >> alertmanager.yml <<'EOF'
  - match:
      component: security
    receiver: discord-security
    continue: true
EOF

# Reload Alertmanager
podman exec alertmanager kill -HUP 1
```

**Success Criteria:**
- [ ] Alert rules loaded in Prometheus
- [ ] Test alert fires correctly
- [ ] Alerts routed to Discord/notification channel
- [ ] Alert descriptions are actionable

---

### 2.4: Structured Logging

**Duration:** 10 minutes

#### Configure CrowdSec JSON Logging

```bash
# Enable JSON output for better parsing
podman exec crowdsec sh -c 'echo "log_mode: json" >> /etc/crowdsec/config.yaml'

# Restart CrowdSec
systemctl --user restart crowdsec.service

# Verify JSON logging
podman logs --since 1m crowdsec | head -5 | jq

# Expected: Structured JSON logs
```

#### Configure Loki Collection (If Deployed)

```bash
# Update Promtail to scrape CrowdSec container logs
# Already configured via Docker socket autodiscovery

# Add custom labels for CrowdSec logs
# (Optional - if you want special processing)

# Query CrowdSec logs in Grafana Explore:
# {container_name="crowdsec"} |= "decision"
```

**Success Criteria:**
- [ ] CrowdSec outputting JSON logs
- [ ] Logs visible in Loki (if deployed)
- [ ] Log queries return structured data

---

### 2.5: Documentation & Runbooks

**Duration:** 10 minutes

#### Create Monitoring Runbook

```bash
cat > ~/containers/docs/crowdsec-monitoring-runbook.md <<'EOF'
# CrowdSec Monitoring Runbook

## Dashboard Locations

- **CrowdSec Overview:** http://grafana.patriark.org/d/crowdsec-overview
- **Prometheus Targets:** http://prometheus.patriark.org/targets
- **Alert Rules:** http://prometheus.patriark.org/alerts

## Key Metrics to Watch

### Healthy Baseline
- Active Decisions: 100-10,000 (varies with CAPI)
- Alert Rate: 0-5/minute (spikes during attacks)
- Bouncer Queries: 10-100/sec (varies with traffic)
- CAPI Sync: Every 2 hours

### Warning Indicators
- Alert Rate: >10/minute for >10 minutes
- No CAPI sync in 4+ hours
- Bouncer heartbeat missing >5 minutes
- Decision count dropping to zero (possible failure)

### Critical Indicators
- CrowdSec service down
- Prometheus can't scrape metrics
- All bouncers disconnected

## Alert Response Procedures

### CrowdSecDown
1. Check service: `systemctl --user status crowdsec.service`
2. Check logs: `journalctl --user -u crowdsec.service -n 100`
3. Verify container: `podman ps | grep crowdsec`
4. Restart if needed: `systemctl --user restart crowdsec.service`
5. Check for config errors: `podman logs crowdsec | grep -i error`

### CrowdSecHighAttackVolume
1. Check attack types: `podman exec crowdsec cscli alerts list --limit 20`
2. Identify targeted services (review scenarios)
3. Verify legitimate traffic not affected
4. Check if specific IP causing spike
5. Consider temporary rate limit adjustments if needed

### CrowdSecCAPIDown
1. Check CAPI status: `podman exec crowdsec cscli capi status`
2. Check internet connectivity: `podman exec crowdsec curl -s https://api.crowdsec.net/health`
3. Check CAPI credentials: `podman exec crowdsec cat /etc/crowdsec/online_api_credentials.yaml`
4. Force manual pull: `podman exec crowdsec cscli capi pull`
5. Restart CrowdSec if persistent: `systemctl --user restart crowdsec.service`

### CrowdSecBouncerDown
1. Check bouncer list: `podman exec crowdsec cscli bouncers list`
2. Check Traefik status: `systemctl --user status traefik.service`
3. Check Traefik logs: `podman logs traefik | grep -i crowdsec`
4. Verify network connectivity: `podman exec traefik ping crowdsec`
5. Restart Traefik if needed: `systemctl --user restart traefik.service`

## Periodic Health Checks

### Daily (Automated via Monitoring)
- CrowdSec service up
- Metrics being collected
- CAPI syncing
- Bouncer connected

### Weekly (Manual Review)
- Review top attack scenarios
- Check for false positive patterns
- Review ban duration effectiveness
- Update hub if needed

### Monthly
- Review alert thresholds (tune for environment)
- Check for new relevant scenario collections
- Review decision metrics (CAPI vs local ratio)
- Update documentation based on learnings
EOF

echo "✓ Monitoring runbook created"
```

**Success Criteria:**
- [ ] Runbook documents all alerts
- [ ] Response procedures clear and tested
- [ ] Dashboard locations documented
- [ ] Health check schedule defined

---

## Phase 5: Advanced Hardening

**Duration:** 30-45 minutes | **Priority:** MEDIUM

### Overview

Enhance CrowdSec with custom user experience, automated notifications, and advanced threat intelligence.

### Objectives

- Custom ban response pages
- Real-time Discord notifications
- IP reputation tracking
- Automated threat reports

---

### 5.1: Custom Ban Pages

**Duration:** 15 minutes

#### Create Custom HTML Ban Page

```bash
cd ~/containers/config/traefik

# Create custom ban page
cat > crowdsec-ban-page.html <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Access Denied - Security Block</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: #fff;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
        }
        .container {
            text-align: center;
            max-width: 600px;
            padding: 2rem;
            background: rgba(0, 0, 0, 0.3);
            border-radius: 10px;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.3);
        }
        h1 {
            font-size: 3rem;
            margin-bottom: 1rem;
        }
        .emoji {
            font-size: 5rem;
            margin-bottom: 1rem;
        }
        p {
            font-size: 1.2rem;
            line-height: 1.6;
        }
        .ip {
            font-family: monospace;
            background: rgba(255, 255, 255, 0.2);
            padding: 0.5rem 1rem;
            border-radius: 5px;
            display: inline-block;
            margin: 1rem 0;
        }
        .footer {
            margin-top: 2rem;
            font-size: 0.9rem;
            opacity: 0.8;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="emoji">🛡️</div>
        <h1>Access Denied</h1>
        <p>Your IP address has been temporarily blocked due to suspicious activity.</p>
        <div class="ip">Your IP: {{.Value}}</div>
        <p><strong>Reason:</strong> {{.Reason}}</p>
        <p><strong>Ban Duration:</strong> {{.Duration}}</p>
        <div class="footer">
            <p>If you believe this is a mistake, please contact the system administrator.</p>
            <p>Protected by CrowdSec Community Security</p>
        </div>
    </div>
</body>
</html>
EOF

# Update Traefik middleware to use custom ban page
# Edit middleware.yml
cd ~/containers/config/traefik/dynamic

# Add banTemplateFile to CrowdSec middleware
# Note: Requires mounting ban page file in Traefik container
```

#### Mount Ban Page in Traefik Container

```bash
# Update Traefik quadlet to mount ban page
cd ~/.config/containers/systemd

# Add volume mount
# Volume=%h/containers/config/traefik/crowdsec-ban-page.html:/etc/traefik/crowdsec-ban-page.html:ro,Z

# Update middleware.yml to reference it
# banTemplateFile: /etc/traefik/crowdsec-ban-page.html

# Reload and restart
systemctl --user daemon-reload
systemctl --user restart traefik.service
```

**Success Criteria:**
- [ ] Custom ban page created
- [ ] Mounted in Traefik container
- [ ] Referenced in middleware config
- [ ] Test ban shows custom page

---

### 5.2: Discord Notifications for Bans

**Duration:** 10 minutes

#### Configure CrowdSec Notification Plugin

```bash
# Install notification plugin (if not already installed)
podman exec crowdsec cscli notifications install http

# Configure Discord webhook
cat > ~/containers/data/crowdsec/config/notifications/discord.yaml <<'EOF'
type: http
name: discord_notifications
log_level: info

# Format for Discord
format: |
  {
    "username": "CrowdSec Security",
    "avatar_url": "https://crowdsec.net/wp-content/uploads/2021/03/crowdsec-logo.png",
    "embeds": [{
      "title": "🚨 Security Alert",
      "description": "New threat detected and blocked",
      "color": 15158332,
      "fields": [
        {"name": "IP Address", "value": "{{.Source.IP}}", "inline": true},
        {"name": "Scenario", "value": "{{.Scenario}}", "inline": true},
        {"name": "Duration", "value": "{{.Decision.Duration}}", "inline": true},
        {"name": "Country", "value": "{{.Source.Cn}}", "inline": true}
      ],
      "timestamp": "{{.Alert.CreatedAt}}"
    }]
  }

url: YOUR_DISCORD_WEBHOOK_URL_HERE

method: POST
headers:
  Content-Type: application/json
EOF

# Update profiles.yaml to trigger notifications
# Add: on_success: notify
# notify: discord_notifications
```

**Note:** For production, configure notification batching to avoid Discord rate limits.

**Success Criteria:**
- [ ] Notification plugin configured
- [ ] Test notification sent to Discord
- [ ] Notifications batched appropriately
- [ ] Alert format is useful

---

### 5.3: IP Reputation Tracking

**Duration:** 10 minutes

#### Enable CTI (Cyber Threat Intelligence) Plugin

```bash
# CrowdSec CTI provides IP reputation lookups
# Already available via CAPI enrollment

# Query IP reputation manually
podman exec crowdsec cscli decisions add --ip 1.2.3.4 --dry-run

# Check IP reputation via API
curl -s "https://cti.api.crowdsec.net/v2/smoke/1.2.3.4" \
  -H "X-Api-Key: YOUR_CTI_KEY" | jq

# Expected: reputation score, background, behaviors
```

#### Create Reputation Dashboard Panel

Add to Grafana dashboard:
```json
{
  "title": "Top Attacking Countries",
  "type": "geomap",
  "targets": [{
    "expr": "sum by (country) (crowdsec_lapi_decisions_total)",
    "legendFormat": "{{country}}"
  }]
}
```

**Success Criteria:**
- [ ] CTI API accessible
- [ ] Reputation queries working
- [ ] Geographic data in dashboard

---

### 5.4: Automated Threat Reports

**Duration:** 10 minutes

#### Create Weekly Report Script

```bash
cat > ~/containers/scripts/crowdsec/weekly-report.sh <<'EOF'
#!/bin/bash
# CrowdSec Weekly Security Report

REPORT_FILE="/tmp/crowdsec-weekly-$(date +%Y%m%d).txt"

cat > "$REPORT_FILE" <<REPORT
=================================================
CrowdSec Security Report - Week of $(date +%Y-%m-%d)
=================================================

SUMMARY
-------
Total Bans: $(podman exec crowdsec cscli decisions list | wc -l)
Active Scenarios: $(podman exec crowdsec cscli scenarios list | grep -c enabled)
CAPI Status: $(podman exec crowdsec cscli capi status | grep Status: | awk '{print $2}')

TOP ATTACK SCENARIOS
-------------------
$(podman exec crowdsec cscli metrics | grep -A 20 "Scenario Metrics" | head -15)

TOP BANNED IPS
--------------
$(podman exec crowdsec cscli decisions list -o json | jq -r '.[0:10] | .[] | "\(.value)\t\(.scenario)\t\(.duration)"')

ALERT DISTRIBUTION
------------------
$(podman exec crowdsec cscli alerts list -o json | jq -r 'group_by(.scenario) | .[] | "\(.[0].scenario): \(length) alerts"' | head -10)

CAPI STATISTICS
---------------
CAPI Decisions: $(podman exec crowdsec cscli decisions list -o json | jq '[.[] | select(.origin=="capi")] | length')
Local Decisions: $(podman exec crowdsec cscli decisions list -o json | jq '[.[] | select(.origin=="crowdsec")] | length')

RECOMMENDATIONS
---------------
$(podman exec crowdsec cscli hub list | grep -i "available" | head -5)

Report generated: $(date)
=================================================
REPORT

echo "Report saved to: $REPORT_FILE"

# Optionally email or send to Discord
# cat "$REPORT_FILE" | mail -s "CrowdSec Weekly Report" admin@example.com
EOF

chmod +x ~/containers/scripts/crowdsec/weekly-report.sh

# Schedule with systemd timer (optional)
# Or run manually: ./weekly-report.sh
```

**Success Criteria:**
- [ ] Report script generates output
- [ ] All sections populated with data
- [ ] Report format is readable
- [ ] Scheduled execution working (if automated)

---

## Integration Testing

### End-to-End Validation

**Test Phase 2 (Observability):**
```bash
# 1. Check Prometheus scraping
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.job=="crowdsec")'

# 2. View Grafana dashboard
# Navigate to: http://grafana.patriark.org/d/crowdsec-overview

# 3. Trigger test alert
# Temporarily stop CrowdSec to trigger "CrowdSecDown" alert
systemctl --user stop crowdsec.service
sleep 360  # Wait 6 minutes for alert
systemctl --user start crowdsec.service

# 4. Verify alert in Alertmanager
curl -s http://localhost:9093/api/v1/alerts | jq '.data[] | select(.labels.alertname=="CrowdSecDown")'
```

**Test Phase 5 (Advanced Features):**
```bash
# 1. Test custom ban page
# Ban yourself temporarily
MY_IP=$(curl -s ifconfig.me)
podman exec crowdsec cscli decisions add --ip "$MY_IP" --duration 2m
# Navigate to any service - should see custom ban page
podman exec crowdsec cscli decisions delete --ip "$MY_IP"

# 2. Test Discord notifications
# Configure webhook and trigger test alert
# (Use test scenario or manual decision)

# 3. Generate weekly report
~/containers/scripts/crowdsec/weekly-report.sh
cat /tmp/crowdsec-weekly-*.txt
```

---

## Commit to Git

```bash
cd ~/containers

# Add all new files
git add config/prometheus/prometheus.yml
git add config/prometheus/rules/crowdsec-alerts.yml
git add config/grafana/provisioning/dashboards/json/crowdsec-overview.json
git add config/traefik/crowdsec-ban-page.html
git add scripts/crowdsec/weekly-report.sh
git add docs/crowdsec-monitoring-runbook.md

git commit -m "CrowdSec: Add Phase 2 observability and Phase 5 advanced features

Phase 2 - Observability:
- Prometheus metrics scraping
- Grafana dashboard with 6 panels
- Alertmanager rules for security events
- Structured JSON logging
- Complete monitoring runbook

Phase 5 - Advanced Hardening:
- Custom HTML ban page
- Discord notification integration
- IP reputation tracking via CTI
- Automated weekly security reports

Testing: All features validated end-to-end
Impact: Enhanced visibility and user experience"

git push
```

---

## Success Criteria Summary

### Phase 2: Observability
- [x] CrowdSec metrics in Prometheus
- [x] Grafana dashboard operational
- [x] Alerts configured and firing
- [x] Logs structured and queryable
- [x] Monitoring runbook created

### Phase 5: Advanced Hardening
- [x] Custom ban page deployed
- [x] Notifications configured
- [x] Reputation tracking enabled
- [x] Automated reports working

---

## Operational Procedures

### Daily Monitoring

**Automated (via alerts):**
- CrowdSec service health
- CAPI sync status
- Bouncer connectivity

**Manual (5 min review):**
- Check Grafana dashboard for anomalies
- Review any fired alerts
- Verify metrics look normal

### Weekly Maintenance

1. Review weekly security report
2. Check for hub updates: `podman exec crowdsec cscli hub update`
3. Review top attack scenarios
4. Adjust alert thresholds if needed

### Monthly Reviews

1. Analyze attack trends over 30 days
2. Evaluate ban effectiveness (repeat offenders?)
3. Consider new scenario collections
4. Update documentation with learnings

---

## Troubleshooting

### Metrics Not Appearing in Prometheus

```bash
# Check CrowdSec metrics endpoint
podman exec crowdsec curl http://localhost:6060/metrics

# Check Prometheus config
grep -A 5 "job_name: 'crowdsec'" ~/containers/config/prometheus/prometheus.yml

# Check Prometheus targets page
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.job=="crowdsec")'
```

### Dashboard Panels Empty

```bash
# Verify data source UID matches
# Check: Grafana → Configuration → Data Sources

# Test query directly in Prometheus
curl -s 'http://localhost:9090/api/v1/query?query=crowdsec_lapi_decisions_total'

# Check panel query syntax in Grafana Explore
```

### Alerts Not Firing

```bash
# Verify rules loaded
curl http://localhost:9090/api/v1/rules | jq '.data.groups[] | select(.name=="crowdsec_security")'

# Check alert status
curl http://localhost:9090/api/v1/alerts

# Check Alertmanager routing
curl http://localhost:9093/api/v1/status
```

### Custom Ban Page Not Showing

```bash
# Verify file mounted in Traefik
podman exec traefik ls -l /etc/traefik/crowdsec-ban-page.html

# Check middleware config
grep -A 5 "banTemplateFile" ~/containers/config/traefik/dynamic/middleware.yml

# Check Traefik logs for template errors
podman logs traefik | grep -i template
```

---

## Document Control

**Version:** 1.0
**Created:** 2025-11-12
**Dependencies:** Phase 1 (required), Phase 3 (recommended for CAPI metrics)

**Related Documents:**
- `crowdsec-phase1-field-manual.md` - Foundation
- `crowdsec-phase3-threat-intelligence.md` - CAPI integration
- `crowdsec-phase4-configuration-management.md` - Config management

---

**END OF COMBINED PLAN**
