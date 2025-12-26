# Monitoring, Alerting & Autonomous Operations - Comprehensive Investigation

**Date:** 2025-12-26
**Type:** System Investigation & Recommendations (REVISED)
**Focus:** Alert optimization, Loki usage, autonomous ops integration, UnPoller
**Scope:** Full intelligence ecosystem (monitoring + alerting + autonomous operations)

---

## Executive Summary

Conducted comprehensive investigation of homelab monitoring, alerting, and autonomous operations capabilities. The investigation reveals a **sophisticated multi-layered intelligence system** with Google SRE-grade monitoring, OODA loop autonomous operations, and scheduled intelligence reporting. Key opportunities identified: alert routing optimization, Loki integration expansion, and autonomous operations visibility.

**Key Findings:**
- ✅ **Three-tier intelligence architecture working** (Monitoring → Alerting → Autonomous Ops)
- ✅ **SLO-based alerting is production-grade** (90% noise reduction achieved)
- ✅ **Autonomous OODA loop operational** (daily at 06:30, remediation framework integrated)
- ⚠️ **Snapshot alerts disrupting user** (routing to wrong receiver, should use weekly intelligence report)
- ⚠️ **Loki underutilized** (collecting logs but not ingesting decision logs or autonomous ops data)
- ⚠️ **Autonomous ops visibility gap** (no Grafana dashboard, decision log not in Loki)
- 🔴 **Remediation security gaps** (webhook auth missing, failure alerting missing)
- 🆕 **UnPoller opportunity** for network-layer observability

---

## Architecture Discovery: Three-Tier Intelligence System

### Tier 1: Reactive Monitoring (Prometheus + Alertmanager)

**Purpose:** Detect and alert on user-impacting issues in real-time

**Components:**
- Prometheus (metric collection, alert evaluation every 15s)
- Alertmanager (routing, grouping, inhibition)
- SLO-based burn rate alerts (4-tier detection)
- Remediation webhook integration (Phase 3-4)

**Triggers:**
- SLO violations → Discord + Remediation webhook
- Disk/memory pressure → Remediation webhook
- Container failures → Remediation webhook

**Schedule:** Continuous (15s scrape interval)

---

### Tier 2: Proactive Intelligence (Scheduled Reports + Forecasting)

**Purpose:** Predict issues before they impact SLOs, provide periodic health summaries

**Components:**

| Timer | Schedule | Script | Purpose | Output |
|-------|----------|--------|---------|--------|
| `daily-drift-check.timer` | Daily 06:00 | `daily-drift-check.sh` | Detect config drift | Discord alert if drift detected |
| `daily-resource-forecast.timer` | Daily 06:05 | `predict-resource-exhaustion.sh` | Forecast exhaustion (7-14 days) | Discord alert if critical/warning |
| `weekly-intelligence.timer` | Friday 07:30 | `weekly-intelligence-report.sh` | End-of-week health summary | Discord report |
| `monthly-slo-report.timer` | 1st of month 10:00 | `monthly-slo-report.sh` | SLO compliance report | Discord report |
| `query-cache-refresh.timer` | Every 6 hours | `precompute-queries.sh` | Pre-compute query cache | Cache file for autonomous ops |

**Key Insight:** **Weekly intelligence report already exists!** This is the natural home for snapshot count information.

---

### Tier 3: Autonomous Operations (OODA Loop)

**Purpose:** Automatically remediate known issues without human intervention

**Schedule:** Daily 06:30 via `autonomous-operations.timer`

**OODA Loop Phases:**

```
OBSERVE (autonomous-check.sh)
├─ Query cache (pre-computed metrics, 58% faster)
├─ System health (memory, CPU, disk, service status)
├─ Predictive forecasts (from daily-resource-forecast)
├─ Configuration drift (from daily-drift-check)
└─ SLO compliance (from Prometheus)

↓

ORIENT
├─ Analyze trends (compare to historical baselines)
├─ Identify root causes (memory leak, disk growth, config drift)
├─ Calculate confidence scores (based on evidence strength)
└─ Recommend skills (via recommend-skill.sh integration)

↓

DECIDE
├─ Evaluate decision matrix (confidence + risk → action threshold)
├─ Check safety controls (service overrides, circuit breaker, cooldowns)
├─ Consult preferences.yml (risk tolerance, auto-restart overrides)
└─ Generate action plan (with confidence justification)

↓

ACT (autonomous-execute.sh)
├─ Execute via remediation framework (apply-remediation.sh)
├─ Pre-action BTRFS snapshot (instant rollback capability)
├─ Log to decision-log.jsonl (audit trail)
└─ Update metrics-history.json (for analytics)
```

**Supported Actions (from remediation framework):**
- disk-cleanup (Low risk, 1h cooldown)
- service-restart (Low risk, 5min cooldown)
- drift-reconciliation (Medium risk, 15min cooldown)
- resource-pressure (Medium risk, 30min cooldown)
- predictive-maintenance (Low risk, 6h cooldown)
- self-healing-restart (Low risk, 10min cooldown)

**Safety Controls:**
- Circuit breaker (pauses after 3 consecutive failures)
- Service overrides (traefik, authelia never auto-restart)
- Confidence thresholds (>90% for auto-execute, >80% for notify+execute)
- Cooldown periods per action type
- Pre-action snapshots for rollback

**Current State:**
- Running daily at 06:30
- Integrated with remediation framework (Nov 30, 2025)
- 18 remediation executions in last 3 days (94% success rate)
- Decision log: `.claude/context/decision-log.jsonl`
- Metrics: `.claude/remediation/metrics-history.json`

---

## Integration Analysis: How The Pieces Fit Together

### Alert-Driven Remediation (Tier 1 → Tier 3 Bridge)

**Alertmanager webhook routes:**
```yaml
# SLO violations → Remediation webhook
- matchers:
    - alertname =~ "SLOBurnRateTier1_.*|SLOBurnRateTier2_.*"
  receiver: 'remediation-webhook'
  continue: true  # Also sends to Discord

# Disk/memory pressure → Remediation webhook
- matchers:
    - alertname =~ "SystemDiskSpace.*|ContainerMemoryPressure"
  receiver: 'remediation-webhook'
  continue: true
```

**Webhook handler:** `remediation-webhook.service` (localhost:9096)
- Maps alerts to playbooks (webhook-routing.yml)
- Executes via apply-remediation.sh
- Logs to decision-log.jsonl

**Overlap with Autonomous Ops:**

| Scenario | Tier 1 (Webhook) | Tier 3 (OODA Loop) | Winner |
|----------|------------------|--------------------|----|
| Disk >90% (critical) | Fires alert → webhook → disk-cleanup | Next run detects disk high → queues cleanup | ⚡ Webhook (faster) |
| Disk 75% (forecast) | No alert (predictive only) | Daily forecast → predictive-maintenance | 🤖 Autonomous (proactive) |
| Service down | Fires alert → webhook → service-restart | Next run detects down → self-healing-restart | ⚡ Webhook (faster) |
| Config drift | No alert (info only) | Daily check → drift-reconciliation | 🤖 Autonomous (scheduled) |

**Conclusion:** **Complementary, not redundant.** Webhook handles urgent reactive issues, autonomous ops handles proactive maintenance and slower-developing issues.

---

### Predictive Analytics Integration (Tier 2 → Tier 3)

**Daily forecast flow:**
```
06:05 - daily-resource-forecast.timer runs
  ↓
predict-resource-exhaustion.sh analyzes trends
  ↓
Forecast: "Disk will reach 90% in 12 days" (severity: warning)
  ↓
Triggers Discord alert (if severity critical/warning)
  ↓
06:30 - autonomous-operations.timer runs
  ↓
OBSERVE phase reads forecast data
  ↓
DECIDE: "Disk trending toward exhaustion, confidence: 65%"
  ↓
ACT: Execute predictive-maintenance playbook
  ↓
Result: Disk cleaned, forecast updated
```

**This explains Dec 24 spike:** 11 predictive-maintenance executions likely from autonomous ops responding to forecasts, not manual testing.

**Validation needed:** Confirm predictive-maintenance playbook is triggered by autonomous ops, not just webhook.

---

### Weekly Intelligence Report (Tier 2 Output)

**Current content (from automation-reference.md):**
```
Friday 07:30 - weekly-intelligence-report.sh
  ↓
Sections:
- System health summary
- Autonomous operations status, actions taken, success rate
- Persistent warnings (lasting 7+ days)
- Known issues (from known-issues.yml)
- Resource trends
  ↓
Output: Discord webhook notification
```

**Key Discovery:** **Weekly report already includes autonomous operations section!**

**Opportunity:** Add snapshot count metrics to weekly report instead of separate alerts.

---

## Current State Analysis (Revised)

### 1. SLO-Based Alerting ✅ **Excellent**

*[Same as original - no changes needed]*

**Implementation Status:** Production-ready, world-class
- 9 SLOs across 5 services
- 4-tier burn rate alerting
- 90% noise reduction achieved

---

### 2. Snapshot Count Alert Problem ⚠️ **Misrouted**

**Current Behavior:**
```yaml
# Alert: LowSnapshotCount
severity: warning
repeat_interval: 4h (inherited from default)
receiver: discord-warnings
```

**Problem:** Architectural state notification repeating every 4h during waking hours.

**Better Solution (Revised):** **Add to weekly intelligence report** instead of creating new Alertmanager receiver.

**Rationale:**
1. Weekly intelligence report already runs Friday 07:30
2. Already includes persistent warnings section
3. Aligns with existing architecture (scheduled intelligence vs real-time alerts)
4. Snapshots are checked daily by btrfs-backup-daily.timer (02:00)
5. Weekly cadence appropriate for non-urgent architectural state

**Implementation:**
```bash
# File: scripts/weekly-intelligence-report.sh
# Add new section after "Autonomous Operations Status"

## Backup Health Summary

**Local Snapshots:**
$(for subvol in subvol3-opptak subvol5-postgres subvol7-containers; do
    count=$(curl -s http://localhost:9090/api/v1/query?query=backup_snapshot_count{subvolume=\"$subvol\",location=\"local\"} | jq -r '.data.result[0].value[1]')
    echo "- $subvol: $count snapshots"
done)

**External Backup Status:**
$(curl -s http://localhost:9090/api/v1/query?query=backup_snapshot_count{location=\"external\"} | jq -r '.data.result[] | "- \(.metric.subvolume): \(.value[1]) snapshots"')

**Last Backup:**
$(curl -s http://localhost:9090/api/v1/query?query=backup_last_success_timestamp | jq -r '.data.result[] | "- \(.metric.subvolume): \(.value[1] | tonumber | strftime("%Y-%m-%d %H:%M"))"')

⚠️ **Warnings:** Low snapshot count for subvol3-opptak (< 3 expected)
```

**AND disable Prometheus alert:**
```yaml
# File: config/prometheus/alerts/backup-alerts.yml
# Comment out or delete LowSnapshotCount alert (lines 66-75)
# Reasoning: Moved to weekly intelligence report
```

---

### 3. Loki Log Aggregation ⚠️ **Underutilized**

**Current Usage:**
- Promtail collecting systemd journal only
- 3 panels in security dashboard (CrowdSec, Authelia, Traefik logs)
- 7-day retention
- No log-based alerting

**Missing Critical Integration: Decision Logs**

**Autonomous operations and remediation produce rich JSON logs:**
```
.claude/context/decision-log.jsonl        # Autonomous ops decisions
.claude/remediation/metrics-history.json  # Remediation execution results
.claude/remediation/chain-metrics-history.jsonl  # Chain executions
```

**These are NOT in Loki!** Currently only accessible via:
- Manual file inspection
- query-decisions.sh script
- Monthly remediation report

**Opportunity:** Ingest decision logs into Loki for:
- Real-time querying (LogQL)
- Alerting on remediation patterns
- Correlation with service logs
- Historical trend analysis

**Implementation:**
```yaml
# File: config/promtail/promtail-config.yml
# Add new scrape configs:

scrape_configs:
  # ... existing systemd-journal config ...

  # Autonomous operations decision log
  - job_name: autonomous-decisions
    static_configs:
      - targets:
          - localhost
        labels:
          job: autonomous-decisions
          host: fedora-htpc
          __path__: /home/patriark/containers/.claude/context/decision-log.jsonl
    pipeline_stages:
      - json:
          expressions:
            timestamp: timestamp
            action: action
            confidence: confidence
            outcome: outcome
            reason: reason
      - labels:
          action:
          outcome:
      - timestamp:
          source: timestamp
          format: RFC3339

  # Remediation execution metrics
  - job_name: remediation-metrics
    static_configs:
      - targets:
          - localhost
        labels:
          job: remediation-metrics
          host: fedora-htpc
          __path__: /home/patriark/containers/.claude/remediation/metrics-history.json
    pipeline_stages:
      - json:
          expressions:
            timestamp: timestamp
            playbook: playbook
            outcome: outcome
            duration: duration_seconds
            impact: impact
      - labels:
          playbook:
          outcome:
      - timestamp:
          source: timestamp
          format: RFC3339
```

**New Loki Queries Enabled:**
```logql
# Failed remediation rate
sum(rate({job="remediation-metrics"} | json | outcome="failure" [5m])) by (playbook)

# Autonomous ops decision confidence over time
avg_over_time({job="autonomous-decisions"} | json | confidence [1h])

# Most common remediation actions
topk(5, sum by (playbook) (count_over_time({job="remediation-metrics"} [7d])))

# Remediation failures correlated with service logs
{job="remediation-metrics"} | json | outcome="failure"
  |~ "disk-cleanup"
  | line_format "Remediation failed: {{.reason}}"
```

**Log-Based Alerting Examples:**
```yaml
# File: config/loki/rules/autonomous-ops-alerts.yml (new)

groups:
  - name: autonomous_operations_alerts
    interval: 1m
    rules:
      # Alert on autonomous ops circuit breaker
      - alert: AutonomousOpsCircuitBreakerTriggered
        expr: |
          sum(count_over_time({job="autonomous-decisions"}
            | json
            | reason="circuit_breaker_active" [15m])) > 0
        labels:
          severity: warning
          category: autonomous-ops
        annotations:
          summary: "Autonomous operations paused due to failures"
          description: "Circuit breaker triggered - check decision log"

      # Alert on repeated remediation failures
      - alert: RemediationFailurePattern
        expr: |
          sum(rate({job="remediation-metrics"}
            | json
            | outcome="failure" [10m])) by (playbook) > 0.1
        for: 10m
        labels:
          severity: warning
          category: remediation
        annotations:
          summary: "Playbook {{ $labels.playbook }} failing repeatedly"
          description: "Failure rate >0.1/min for 10 minutes"

      # Alert on low autonomous ops confidence
      - alert: AutonomousOpsLowConfidence
        expr: |
          avg_over_time({job="autonomous-decisions"}
            | json
            | unwrap confidence [1h]) < 0.5
        for: 2h
        labels:
          severity: info
          category: autonomous-ops
        annotations:
          summary: "Autonomous operations unable to make confident decisions"
          description: "Average confidence <50% for 2 hours - may need manual intervention"
```

---

### 4. Autonomous Operations Visibility ⚠️ **Missing Dashboard**

**Current State:**
- Autonomous ops running daily (06:30)
- Decision log in JSON (not easily queryable)
- Metrics in JSON (not visualized)
- Weekly report includes summary (text only)
- No real-time visibility

**Missing:**
- Grafana dashboard for autonomous ops metrics
- Prometheus exporter for decision log data
- Real-time success/failure monitoring
- Confidence score trending

**Implementation:**

**Step 1: Create Prometheus Exporter**
```bash
# File: scripts/export-autonomous-metrics.sh (new script)
#!/bin/bash
# Reads decision-log.jsonl and exports metrics in Prometheus format
# Run via cron or systemd timer every 5 minutes

OUTPUT_FILE="/var/lib/node_exporter/textfile_collector/autonomous_ops.prom"

# Parse decision log (last 24 hours)
jq -r 'select(.timestamp > (now - 86400))' ~/.claude/context/decision-log.jsonl | \
  jq -s '
    # Total decisions by outcome
    group_by(.outcome) | map({
      outcome: .[0].outcome,
      count: length
    }) | .[] |
    "autonomous_decisions_total{outcome=\"\(.outcome)\"} \(.count)"

    # Average confidence by action
    group_by(.action) | map({
      action: .[0].action,
      avg_confidence: (map(.confidence) | add / length)
    }) | .[] |
    "autonomous_decision_confidence{action=\"\(.action)\"} \(.avg_confidence)"

    # Last decision timestamp
    "autonomous_last_decision_timestamp " + (map(.timestamp) | max | tostring)
  ' > "$OUTPUT_FILE.tmp"

mv "$OUTPUT_FILE.tmp" "$OUTPUT_FILE"
```

**Step 2: Configure Node Exporter Textfile Collector**
```yaml
# File: ~/.config/containers/systemd/node_exporter.container
# Add volume mount:
Volume=/var/lib/node_exporter/textfile_collector:/textfile:ro,Z

# Add environment:
Environment=TEXTFILE_DIRECTORY=/textfile
```

**Step 3: Create Grafana Dashboard**
```json
// Panel 1: Autonomous Ops Success Rate (24h rolling)
{
  "title": "Autonomous Ops Success Rate",
  "targets": [{
    "expr": "sum(rate(autonomous_decisions_total{outcome=\"success\"}[24h])) / sum(rate(autonomous_decisions_total[24h])) * 100"
  }],
  "type": "gauge",
  "fieldConfig": {
    "defaults": {
      "thresholds": {
        "steps": [
          {"value": 0, "color": "red"},
          {"value": 80, "color": "yellow"},
          {"value": 95, "color": "green"}
        ]
      }
    }
  }
}

// Panel 2: Decision Confidence by Action
{
  "title": "Decision Confidence by Action",
  "targets": [{
    "expr": "autonomous_decision_confidence",
    "legendFormat": "{{ action }}"
  }],
  "type": "timeseries"
}

// Panel 3: Recent Decisions (from Loki)
{
  "title": "Recent Autonomous Decisions",
  "datasource": "Loki",
  "targets": [{
    "expr": "{job=\"autonomous-decisions\"} | json | line_format \"{{.action}} (confidence: {{.confidence}}) → {{.outcome}}\""
  }],
  "type": "logs"
}

// Panel 4: Failed Remediations (alert panel)
{
  "title": "Failed Remediations (Last 24h)",
  "targets": [{
    "expr": "sum(increase(remediation_executions_total{outcome=\"failure\"}[24h])) by (playbook)"
  }],
  "type": "table",
  "transformations": [{
    "id": "organize",
    "options": {
      "renameByName": {
        "playbook": "Playbook",
        "Value": "Failures"
      }
    }
  }]
}
```

---

### 5. Remediation Security Gaps 🔴 **CRITICAL**

*[Same as original, but with added context]*

**Current State:**
- Webhook running on localhost:9096
- Integrated with Alertmanager (Tier 1)
- Integrated with autonomous ops (Tier 3)
- 18 executions, 94% success rate

**Critical Issues:**

1. **No Webhook Authentication** 🔴
   - Risk: Unauthenticated POST can trigger remediation
   - Impact: Both alert-driven AND autonomous-driven remediation affected
   - Fix: HMAC signature validation (immediate)

2. **No Remediation Failure Alerting** 🔴
   - Failures only logged to decision-log.jsonl
   - User unaware unless checking logs or weekly report
   - Fix: Discord notification on all failures (immediate)

3. **No Webhook Loop Prevention** 🟡
   - Alert → Remediation → Alert cycles possible
   - Fix: Per-alert cooldown (30min)

*[Implementation details same as original]*

---

### 6. UnPoller Integration 🆕 **OPTIONAL**

*[Same as original - no changes needed]*

**Decision Criteria:** Only deploy if network visibility adds value beyond current service-layer monitoring.

---

## Recommendations (Revised & Prioritized)

### IMMEDIATE (This Week)

#### 1. Integrate Snapshot Metrics into Weekly Intelligence Report 🔴 **HIGH**

**Why This Approach:**
- Aligns with existing architecture (scheduled intelligence vs alerts)
- Weekly cadence appropriate for architectural state
- Already have weekly-intelligence.timer running Friday 07:30
- Reduces Discord notification noise immediately

**Implementation:**
```bash
# 1. Edit weekly-intelligence-report.sh
nano ~/containers/scripts/weekly-intelligence-report.sh

# Add "Backup Health Summary" section (see detailed code above)

# 2. Disable LowSnapshotCount alert in Prometheus
nano ~/containers/config/prometheus/alerts/backup-alerts.yml
# Comment out lines 66-75

# 3. Reload Prometheus
systemctl --user restart prometheus.service

# 4. Test (manually trigger weekly report)
systemctl --user start weekly-intelligence.service

# 5. Check Discord for new section
```

**Estimated effort:** 30 minutes
**Impact:** Immediate noise reduction + better information architecture

---

#### 2. Secure Remediation Webhook 🔴 **CRITICAL SECURITY**

*[Same as original - implementation details unchanged]*

**Impact:** Protects both Tier 1 (alert-driven) and Tier 3 (autonomous) remediation

---

#### 3. Add Remediation Failure Alerting 🔴 **CRITICAL VISIBILITY**

*[Same as original - implementation details unchanged]*

**Impact:** Immediate visibility into automation failures (both webhook and autonomous ops)

---

### SHORT-TERM (This Month)

#### 4. Ingest Decision Logs into Loki 🟡 **HIGH VALUE**

**Why This Matters:**
- Autonomous ops and remediation logs currently invisible to monitoring stack
- No way to query/alert on autonomous ops patterns
- Missing correlation between decisions and service behavior
- Analytics only available via monthly report (30-day lag)

**Implementation:**
```bash
# 1. Add scrape configs to Promtail (see detailed config above)
nano ~/containers/config/promtail/promtail-config.yml

# 2. Create Loki alert rules directory
mkdir -p ~/containers/config/loki/rules

# 3. Add autonomous ops alerts (see detailed rules above)
nano ~/containers/config/loki/rules/autonomous-ops-alerts.yml

# 4. Restart services
systemctl --user restart promtail.service
systemctl --user restart loki.service

# 5. Verify ingestion
curl -s 'http://localhost:3100/loki/api/v1/labels' | jq
# Should show: job="autonomous-decisions", job="remediation-metrics"

# 6. Test query in Grafana Explore
{job="autonomous-decisions"} | json
```

**Estimated effort:** 2 hours
**Impact:** Real-time visibility into autonomous operations, log-based alerting enabled

---

#### 5. Build Autonomous Operations Dashboard 🟡 **HIGH VALUE**

**Prerequisite:** Implement Prometheus exporter (Step 1 above)

**Implementation:**
```bash
# 1. Create metrics exporter script
nano ~/containers/scripts/export-autonomous-metrics.sh
# (See detailed implementation above)

# 2. Create systemd timer for exporter
cat > ~/.config/systemd/user/autonomous-metrics-export.timer << 'EOF'
[Unit]
Description=Export Autonomous Ops Metrics Timer

[Timer]
OnCalendar=*:0/5  # Every 5 minutes
Persistent=true

[Install]
WantedBy=timers.target
EOF

cat > ~/.config/systemd/user/autonomous-metrics-export.service << 'EOF'
[Unit]
Description=Export Autonomous Ops Metrics

[Service]
Type=oneshot
ExecStart=/home/patriark/containers/scripts/export-autonomous-metrics.sh
EOF

systemctl --user daemon-reload
systemctl --user enable --now autonomous-metrics-export.timer

# 3. Create Grafana dashboard
# Import dashboard JSON (see detailed panels above)

# 4. Verify metrics visible
curl -s http://localhost:9100/metrics | grep autonomous_
```

**Estimated effort:** 3 hours
**Impact:** Real-time dashboard for autonomous operations success rate, confidence, actions

---

#### 6. Enhance Loki Usage (Traefik Access Logs + Application Logs) 🟡 **MEDIUM**

*[Same as original - no changes needed]*

**Implementation:**
- Ingest Traefik JSON access logs
- Add log-based alerts (OOMKilled, error patterns)
- Build correlation dashboard

**Estimated effort:** 4 hours

---

#### 7. Add Webhook Loop Prevention 🟡 **MEDIUM**

*[Same as original - no changes needed]*

**Implementation:** 30-minute cooldown per alert type in webhook handler

**Estimated effort:** 1 hour

---

### LONG-TERM (Next Quarter)

#### 8. Validate Predictive Maintenance Integration ⏰ **INVESTIGATION**

**Goal:** Understand Dec 24 spike (11 predictive-maintenance executions)

**Questions to Answer:**
1. Are predictive-maintenance executions triggered by autonomous ops or webhook?
2. What threshold triggers predictive-maintenance?
3. Is 11 executions in one day expected behavior or runaway trigger?

**Investigation Steps:**
```bash
# 1. Check decision log for Dec 24 predictive-maintenance triggers
grep "predictive-maintenance" ~/.claude/context/decision-log.jsonl | \
  jq 'select(.timestamp | startswith("2025-12-24"))' | \
  jq -s 'group_by(.reason) | map({reason: .[0].reason, count: length})'

# 2. Check if triggered by autonomous ops (reason should be "forecast_critical")
# vs webhook (reason should be "alert_triggered")

# 3. Review autonomous-check.sh to see predictive-maintenance logic

# 4. Review webhook-routing.yml to see if forecast alerts mapped
```

**Recommendation based on findings:**
- If autonomous ops: Working as designed, adjust forecast threshold if too sensitive
- If webhook: Check if daily-resource-forecast alerts are being routed to webhook
- If manual: Document as testing, ignore spike

**Estimated effort:** 2 hours investigation

---

#### 9. Deploy UnPoller (If Network Visibility Needed) 🔵 **OPTIONAL**

*[Same as original - full 4-week implementation plan provided]*

**Decision point:** Only deploy if user wants Ubiquiti network monitoring

---

#### 10. Implement Log-Derived Metrics 🔵 **OPTIONAL**

*[Same as original - optimization, not critical]*

**Use case:** Extract rate metrics from logs for faster alerting

---

## Summary of Recommendations

### Prioritized Actions (Revised)

| Priority | Action | Estimated Effort | Impact | Architecture Tier |
|----------|--------|------------------|--------|-------------------|
| 🔴 HIGH | Snapshot metrics → weekly intelligence report | 30 min | Immediate noise reduction | Tier 2 |
| 🔴 CRITICAL | Secure webhook (HMAC auth) | 2 hours | Security hardening | Tier 1, 3 |
| 🔴 CRITICAL | Remediation failure alerting | 1 hour | Critical visibility | Tier 1, 3 |
| 🟡 HIGH | Ingest decision logs into Loki | 2 hours | Autonomous ops visibility | Tier 3 |
| 🟡 HIGH | Build autonomous ops dashboard | 3 hours | Real-time monitoring | Tier 3 |
| 🟡 MEDIUM | Enhance Loki (access logs + alerts) | 4 hours | Better incident detection | Tier 1 |
| 🟡 MEDIUM | Webhook loop prevention | 1 hour | Prevent automation loops | Tier 1 |
| ⏰ INVESTIGATE | Validate predictive maintenance | 2 hours | Understand Dec 24 spike | Tier 2, 3 |
| 🔵 OPTIONAL | Deploy UnPoller | 4 weeks | Network monitoring | New capability |
| 🔵 OPTIONAL | Log-derived metrics | 3 hours | Performance optimization | Tier 1 |

---

## Decision Framework (Revised)

### Do First (Week 1)

1. **Snapshot alert routing fix** ← User pain point + architecture improvement
2. **Webhook security hardening** ← Critical security gap
3. **Remediation failure alerting** ← Operational blind spot (affects both tiers)
4. **Investigate predictive maintenance spike** ← Understand if system working as designed

### Do Soon (This Month)

5. **Loki decision log integration** ← Enable autonomous ops visibility
6. **Autonomous ops dashboard** ← Real-time monitoring (currently only weekly report)
7. **Loki access log ingestion** ← Leverage existing capability from security review
8. **Webhook loop prevention** ← Prevent future issues

### Do Later (When Justified)

9. **UnPoller deployment** ← Only if network visibility actually needed
10. **Log-derived metrics** ← Optimization, not critical

---

## Key Insights (Revised)

### What's Working Exceptionally Well

1. **Three-Tier Intelligence Architecture:**
   - Tier 1 (Reactive): SLO-based alerting with 90% noise reduction
   - Tier 2 (Proactive): Scheduled forecasting and intelligence reports
   - Tier 3 (Autonomous): OODA loop with 94% success rate
   - **Assessment:** Well-designed, complementary layers

2. **Integration Points:**
   - Autonomous ops uses remediation framework (no code duplication)
   - Query cache improves OODA loop performance (58% faster)
   - Skill recommendations integrated into DECIDE phase
   - Weekly intelligence includes autonomous ops summary

3. **Safety Controls:**
   - Circuit breaker, service overrides, cooldowns, pre-action snapshots
   - Confidence-based decision matrix
   - Multiple layers prevent runaway automation

### What Needs Improvement

1. **Visibility Gap:** Autonomous ops and remediation logs not in Loki
   - Decision log only accessible via query-decisions.sh or monthly report
   - No real-time dashboard for autonomous operations
   - Can't correlate autonomous decisions with service behavior

2. **Alert Routing:** Snapshot count alerts routed to wrong receiver
   - Should use existing weekly intelligence report
   - Current approach: Alertmanager → Discord every 4h (noise)
   - Better approach: Scheduled report → Discord weekly (signal)

3. **Security Gaps:** Webhook lacks authentication
   - Affects both Tier 1 (alert-driven) and Tier 3 (autonomous)
   - Critical before expanding automation

4. **Loki Underutilization:** Collecting logs but not using for intelligence
   - Missing: Decision logs, remediation metrics, access logs
   - Missing: Log-based alerting on autonomous ops patterns
   - Missing: Correlation dashboards

### Strategic Alignment

**Current Focus:** Multi-tier intelligence (reactive + proactive + autonomous)

**Missing Layer:** **Visibility into autonomous tier** (logs not in monitoring stack, no dashboard)

**Future Opportunity:** Network-layer correlation (UnPoller) for complete observability stack

**Philosophy:** **Reactive alerts for urgent issues, proactive forecasting for prevention, autonomous execution for known remediations** - but all tiers need equal visibility.

---

## Architecture Diagrams

### Current State: Three-Tier Intelligence

```
┌─────────────────────────────────────────────────────────────┐
│ Tier 1: REACTIVE MONITORING (Real-Time)                     │
├─────────────────────────────────────────────────────────────┤
│ Prometheus (15s scrape) → Alertmanager → Discord + Webhook  │
│ • SLO burn rate alerts (4-tier)                             │
│ • Disk/memory pressure                                       │
│ • Container failures                                         │
│ → Triggers: Remediation webhook (localhost:9096)            │
└─────────────────────────────────────────────────────────────┘
                             ↓
┌─────────────────────────────────────────────────────────────┐
│ Tier 2: PROACTIVE INTELLIGENCE (Scheduled)                  │
├─────────────────────────────────────────────────────────────┤
│ Daily 06:00 → Drift check → Discord if drift detected       │
│ Daily 06:05 → Resource forecast → Discord if critical       │
│ Fri 07:30 → Weekly intelligence → Discord summary           │
│ 1st month → Monthly SLO report → Discord compliance         │
│ Every 6h → Query cache refresh → Cache for autonomous ops   │
└─────────────────────────────────────────────────────────────┘
                             ↓
┌─────────────────────────────────────────────────────────────┐
│ Tier 3: AUTONOMOUS OPERATIONS (OODA Loop)                   │
├─────────────────────────────────────────────────────────────┤
│ Daily 06:30 → autonomous-check.sh (OBSERVE + ORIENT)        │
│              → autonomous-execute.sh (DECIDE + ACT)          │
│                                                              │
│ ACT Phase → Remediation Framework                           │
│           → apply-remediation.sh --playbook <name>           │
│           → Logs to decision-log.jsonl                       │
│           → Updates metrics-history.json                     │
│                                                              │
│ Safety: Circuit breaker, overrides, cooldowns, snapshots    │
└─────────────────────────────────────────────────────────────┘
```

### Proposed State: Integrated Visibility

```
┌─────────────────────────────────────────────────────────────┐
│ MONITORING STACK (Unified Visibility)                       │
├─────────────────────────────────────────────────────────────┤
│ Prometheus                                                   │
│ ├─ Service metrics (Traefik, containers, SLOs)             │
│ ├─ Autonomous ops metrics (via textfile exporter)          │
│ └─ Remediation metrics (success rate, duration)            │
│                                                              │
│ Loki                                                         │
│ ├─ Systemd journal logs                                    │
│ ├─ Traefik access logs (JSON) ← NEW                        │
│ ├─ Decision logs (autonomous ops) ← NEW                    │
│ └─ Remediation metrics (execution history) ← NEW           │
│                                                              │
│ Grafana                                                      │
│ ├─ SLO Dashboard (existing)                                │
│ ├─ Security Overview (existing)                            │
│ ├─ Autonomous Ops Dashboard ← NEW                          │
│ └─ Remediation Effectiveness ← NEW                         │
└─────────────────────────────────────────────────────────────┘
                             ↓
              All tiers visible in single pane
```

---

## References

**Documentation Reviewed:**
- `/docs/40-monitoring-and-documentation/guides/slo-framework.md`
- `/docs/40-monitoring-and-documentation/guides/slo-based-alerting.md`
- `/docs/40-monitoring-and-documentation/guides/monitoring-stack.md`
- `/docs/20-operations/guides/automation-reference.md` ← **KEY ADDITION**
- `/docs/20-operations/guides/autonomous-operations.md` ← **KEY ADDITION**
- `/docs/98-journals/2025-12-19-alert-optimization-slo-enhancement.md`
- `/docs/98-journals/2025-12-21-nextcloud-monitoring-enhancement-alert-fixes.md`
- `/docs/98-journals/2025-12-25-remediation-phase-6-implementation.md`
- `/docs/99-reports/2025-12-25-remediation-critical-review.md`

**External Resources:**
- [UnPoller GitHub Repository](https://github.com/unpoller/unpoller)
- [Building Enterprise-Style UniFi Observability](https://technotim.live/posts/unpoller-unifi-metrics/) - Techno Tim (Dec 21, 2025)
- [Google SRE Book - Alerting on SLOs](https://sre.google/workbook/alerting-on-slos/)

---

## Next Steps

**For User Review:**
1. **Prioritize recommendations** based on immediate needs
2. **Decide on UnPoller deployment** (network visibility value assessment)
3. **Approve security changes** (webhook auth, failure alerting)
4. **Confirm snapshot alert approach** (weekly intelligence report vs Alertmanager digest)
5. **Validate predictive maintenance understanding** (Dec 24 spike investigation)

**After User Approval:**
- Create detailed implementation plan with timelines
- Test changes in development first
- Document new configurations
- Update automation-reference.md with new capabilities

---

**Status:** Investigation Complete - Awaiting User Review
**Next Phase:** Implementation Plan (after user feedback)
**Estimated Review Time:** 20-25 minutes
**Critical Decision Points:** 5
1. Snapshot alert routing (weekly report vs digest)
2. Webhook security (immediate implementation?)
3. Loki integration priority (decision logs + access logs)
4. Autonomous ops dashboard (build now or wait?)
5. UnPoller deployment (network visibility needed?)
