# Loki Remediation Query Guide

**Created:** 2025-12-26
**Purpose:** Powerful log analysis for autonomous operations and remediation effectiveness

---

## Overview

Remediation decision logs are now ingested into Loki, enabling powerful querying, filtering, and analysis of autonomous operations. This guide provides practical LogQL queries for common use cases.

**Log Source:** `decision-log.jsonl` → Promtail → Loki
**Job Label:** `remediation-decisions`
**Available Labels:** `alert`, `playbook`, `success`, `confidence`, `host`

---

## Basic Queries

### View All Remediation Actions

```logql
{job="remediation-decisions"}
```

**Use Case:** See complete remediation history
**Output:** All decision log entries with timestamps

### Filter by Success/Failure

```logql
# All successful remediations
{job="remediation-decisions"} | json | success="true"

# All failed remediations
{job="remediation-decisions"} | json | success="false"
```

**Use Case:** Quickly identify failures for investigation
**Output:** Filtered log entries with full context

### Filter by Alert Type

```logql
# Disk space remediations
{job="remediation-decisions", alert="SystemDiskSpaceCritical"}

# SLO violation remediations
{job="remediation-decisions", alert=~"SLOBurnRateTier1_.*"}

# Container health remediations
{job="remediation-decisions", alert="ContainerNotRunning"}
```

**Use Case:** Analyze remediation patterns for specific alert types
**Output:** Filtered by alert name (exact or regex match)

### Filter by Playbook

```logql
# Disk cleanup actions
{job="remediation-decisions", playbook="disk-cleanup"}

# Service restarts
{job="remediation-decisions", playbook=~".*restart"}

# SLO violation remediations
{job="remediation-decisions", playbook="slo-violation-remediation"}
```

**Use Case:** Evaluate playbook effectiveness and frequency
**Output:** All executions of a specific playbook

---

## Analysis Queries

### Remediation Rate Over Time

```logql
# All remediations per minute
rate({job="remediation-decisions"}[5m])

# Successful remediations per minute
rate({job="remediation-decisions"} | json | success="true" [5m])

# Failed remediations per minute
rate({job="remediation-decisions"} | json | success="false" [5m])
```

**Use Case:** Understand remediation frequency and identify spikes
**Visualization:** Time series graph in Grafana

### Success Rate by Playbook

```logql
# Count by playbook and success
sum by (playbook, success) (
  count_over_time({job="remediation-decisions"}[24h])
)
```

**Use Case:** Identify which playbooks have high failure rates
**Visualization:** Bar chart grouped by playbook

### Confidence Analysis

```logql
# Low confidence remediations (<90%)
{job="remediation-decisions"} | json | confidence < 90

# High confidence failures (unexpected)
{job="remediation-decisions"} | json | confidence >= 95 | success="false"
```

**Use Case:** Investigate remediations with low confidence or unexpected failures
**Output:** Entries where confidence doesn't match outcome

### Remediation Count (Last 24 Hours)

```logql
count_over_time({job="remediation-decisions"}[24h])
```

**Use Case:** Get total remediation count for reporting
**Output:** Single metric value

---

## Failure Analysis

### Detailed Failure View

```logql
{job="remediation-decisions"} | json | success="false"
| line_format "{{.alert}} → {{.playbook}}: {{.stderr_preview}}"
```

**Use Case:** Quick scan of all failures with error messages
**Output:** Human-readable failure summary with errors

### Failures by Alert

```logql
sum by (alert) (
  count_over_time({job="remediation-decisions"} | json | success="false" [7d])
)
```

**Use Case:** Identify which alerts have the highest failure rate
**Visualization:** Pie chart or bar chart

### Recent Failures (Last Hour)

```logql
{job="remediation-decisions"} | json | success="false"
| line_format "{{.timestamp | unixEpoch}} - Alert: {{.alert}}, Playbook: {{.playbook}}, Error: {{.stderr_preview}}"
```

**Time Range:** Last 1 hour
**Use Case:** Real-time failure monitoring and immediate investigation
**Output:** Chronological list of recent failures with context

---

## Performance Queries

### Playbook Execution Frequency

```logql
# Top 5 most-used playbooks (last 7 days)
topk(5,
  sum by (playbook) (
    count_over_time({job="remediation-decisions"}[7d])
  )
)
```

**Use Case:** Understand which playbooks are used most often
**Visualization:** Bar chart

### Alert-to-Remediation Correlation

```logql
# Show which alerts trigger which playbooks
{job="remediation-decisions"} | json
| line_format "{{.alert}} → {{.playbook}} ({{.confidence}}% confidence)"
```

**Use Case:** Understand alert routing and remediation patterns
**Output:** Alert-playbook mapping with confidence scores

---

## Webhook Loop Detection

### Rapid Remediation Detection

```logql
# More than 3 remediations in 5 minutes (potential loop)
rate({job="remediation-decisions"}[5m]) > 0.6
```

**Use Case:** Detect potential remediation loops or oscillations
**Alert Threshold:** >3 executions in 5 minutes
**Action:** Investigate for alert → remediation → alert cycles

### Same Alert Repetition

```logql
# Same alert firing multiple times
sum by (alert) (
  count_over_time({job="remediation-decisions"}[15m])
) > 3
```

**Use Case:** Identify alerts that aren't being resolved by remediation
**Output:** Alerts with >3 occurrences in 15 minutes

---

## Correlation Queries

### Correlate with Traefik Errors

```logql
# Find remediation timestamp
{job="remediation-decisions", alert=~".*Jellyfin"} | json
| line_format "{{.timestamp}}"

# Then query Traefik around that time
{job="traefik-access"} | json | service="jellyfin@docker" | status >= 500
```

**Use Case:** Verify if remediation actions reduce user-facing errors
**Time Range:** Compare 10 minutes before and after remediation
**Visualization:** Overlay remediation events on error rate graph

### Correlate with Service Logs

```logql
# Remediation timestamp
{job="remediation-decisions", playbook="self-healing-restart"} | json | alert="ContainerNotRunning"

# Service restart logs from systemd
{job="systemd-journal", unit=~"jellyfin.service"}
| logfmt
| line_format "{{.MESSAGE}}"
```

**Use Case:** Trace remediation action through to service logs
**Output:** Full picture of remediation → restart → recovery

---

## Grafana Dashboard Queries

### Remediation Success Rate (Stat Panel)

```logql
# Success rate as percentage
(
  sum(count_over_time({job="remediation-decisions"} | json | success="true" [24h]))
  /
  sum(count_over_time({job="remediation-decisions"}[24h]))
) * 100
```

**Panel Type:** Stat
**Unit:** Percent (0-100)
**Thresholds:** <90% red, 90-95% yellow, >95% green

### Remediation Timeline (Logs Panel)

```logql
{job="remediation-decisions"} | json
| line_format "{{.alert}} → {{.playbook}} | Success: {{.success}} | Confidence: {{.confidence}}%"
```

**Panel Type:** Logs
**Use Case:** Live view of remediation activity
**Labels:** `alert`, `playbook`, `success`

### Failure Alerts (Bar Gauge)

```logql
sum by (alert) (
  count_over_time({job="remediation-decisions"} | json | success="false" [7d])
)
```

**Panel Type:** Bar gauge
**Orientation:** Horizontal
**Display:** Show unfilled background

---

## Advanced Use Cases

### Confidence vs Success Correlation

```logql
# Low confidence that succeeded (surprising)
{job="remediation-decisions"} | json | confidence < 80 | success="true"

# High confidence that failed (investigate!)
{job="remediation-decisions"} | json | confidence >= 95 | success="false"
```

**Use Case:** Audit confidence model accuracy
**Action:** Adjust confidence thresholds in webhook-routing.yml if needed

### Parameter Analysis

```logql
# See what parameters were used
{job="remediation-decisions", playbook="disk-cleanup"} | json
| line_format "Parameters: {{.parameters}}, Success: {{.success}}"
```

**Use Case:** Understand if certain parameters correlate with success/failure
**Output:** Parameter strings with outcomes

### Time-of-Day Analysis

```logql
# Remediations during off-hours (potential unattended issues)
{job="remediation-decisions"} | json
| line_format "{{.timestamp | date \"15:04\"}} - {{.alert}}"
```

**Time Range:** Filter to 23:00-07:00 in Grafana
**Use Case:** Identify if issues occur when users aren't active
**Action:** Schedule preventive maintenance

---

## Query Optimization Tips

### 1. Use Label Filters First

```logql
# Good (label filter narrows data early)
{job="remediation-decisions", playbook="disk-cleanup"} | json

# Less efficient (parses all then filters)
{job="remediation-decisions"} | json | playbook="disk-cleanup"
```

**Performance:** Label filters are indexed, line filters are not

### 2. Limit Time Ranges

```logql
# Add reasonable time ranges to reduce data scanned
{job="remediation-decisions"}[24h]  # vs scanning all data
```

**Tip:** Use Grafana's time picker to auto-apply time ranges

### 3. Use `count_over_time` for Metrics

```logql
# For graphing, use metrics queries
count_over_time({job="remediation-decisions"}[5m])

# Not log queries (slower for time series)
{job="remediation-decisions"}
```

**Visualization:** Metrics queries are much faster for dashboards

---

## Alerting on Remediation Metrics

### High Failure Rate Alert

```logql
(
  sum(count_over_time({job="remediation-decisions"} | json | success="false" [15m]))
  /
  sum(count_over_time({job="remediation-decisions"}[15m]))
) > 0.3
```

**Threshold:** >30% failure rate in 15 minutes
**Alert:** Send to Discord (potential remediation framework issue)

### Remediation Loop Alert

```logql
rate({job="remediation-decisions"}[5m]) > 0.6
```

**Threshold:** >3 remediations in 5 minutes
**Alert:** Investigate for oscillation (alert → remediation → alert cycle)

### Playbook-Specific Failure Alert

```logql
sum by (playbook) (
  count_over_time({job="remediation-decisions"} | json | success="false" [1h])
) > 3
```

**Threshold:** >3 failures of same playbook in 1 hour
**Alert:** Specific playbook may need attention

---

## Common Troubleshooting

### No Data in Loki?

**Check Promtail:**
```bash
podman logs promtail | grep "remediation"
# Should see: "Adding target" for decision-log.jsonl
```

**Check File Mount:**
```bash
podman exec promtail ls -lh /var/log/remediation/
# Should see: decision-log.jsonl
```

**Check Loki Labels:**
```bash
podman exec grafana curl -s 'http://loki:3100/loki/api/v1/label/job/values'
# Should include: "remediation-decisions"
```

### Slow Queries?

- **Narrow time range:** Use 1h or 24h instead of "All time"
- **Use label filters:** `{job="...", playbook="..."}` before `| json`
- **Limit results:** Add `| limit 100` for exploration
- **Use metrics aggregations:** `count_over_time()` instead of raw logs

### Missing Labels?

**Check Promtail Config:**
- Labels must be defined in `pipeline_stages → labels`
- Restart Promtail after config changes: `systemctl --user restart promtail.service`

---

## References

- **Promtail Config:** `~/containers/config/promtail/promtail-config.yml`
- **Decision Log:** `~/.claude/context/decision-log.jsonl`
- **LogQL Documentation:** https://grafana.com/docs/loki/latest/logql/
- **Grafana Explore:** https://grafana.patriark.org/explore

---

**Next Steps:**
1. Create Grafana dashboard with example queries from this guide
2. Set up alerting rules for high failure rates and loops
3. Correlate with Traefik access logs (Phase 2.2) for full picture

**Useful LogQL Cheat Sheet:** https://grafana.com/docs/loki/latest/logql/log_queries/
