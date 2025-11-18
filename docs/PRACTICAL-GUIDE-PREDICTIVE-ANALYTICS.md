# Practical Guide: Predictive Analytics

**New Capability:** Forecast resource exhaustion and service failures **before** they happen

**Created:** 2025-11-18
**Implements:** Session 5B - Proactive Health Management
**Skill Level:** Intermediate

---

## What You Can Do Now

### Before (Reactive Firefighting)
```
Day 1: Disk at 85% - no alert
Day 2: Disk at 88% - no alert
Day 3: Disk at 92% - ALERT! Scramble to free space
Day 4: Service outage due to full disk
```

### After (Proactive Prevention)
```bash
# Run prediction analysis
cd ~/containers/scripts/predictive-analytics
./predict-resource-exhaustion.sh

# Output:
# [CRITICAL] System disk will reach 90% in 5 days
# Current: 85% used
# Trend: +1.2% per day
# Forecast (7 days): 93% used
# Recommendation: Schedule disk cleanup within next 2-3 days

# Schedule cleanup proactively
cd ~/containers/.claude/remediation/scripts
./apply-remediation.sh --playbook disk-cleanup
```

**Result:** No outage, planned maintenance, peace of mind

---

## Quick Start (5 Minutes)

### 1. Check Current Predictions

```bash
cd ~/containers/scripts/predictive-analytics

# Generate all predictions
./generate-predictions-cache.sh

# View aggregated results
cat ~/.claude/context/predictions.json | jq '.'

# Human-readable summary
cat ~/.claude/context/predictions.json | jq '.summary'
```

**Example output:**
```json
{
  "summary": {
    "total_issues": 2,
    "critical": 1,
    "warning": 1,
    "info": 0,
    "overall_severity": "critical"
  },
  "predictions": {
    "disk": {
      "system_ssd": {
        "current_usage_percent": 85,
        "days_until_critical": 5,
        "trend_percent_per_day": 1.2,
        "severity": "critical"
      }
    },
    "memory": {
      "jellyfin": {
        "current_mb": 2100,
        "hours_until_limit": 38,
        "trend_mb_per_hour": 15,
        "severity": "warning"
      }
    }
  }
}
```

### 2. Predict Disk Exhaustion

```bash
# Analyze disk usage trends
./predict-resource-exhaustion.sh --type disk

# Output:
# ╔══════════════════════════════════════════════════════════╗
# ║           DISK USAGE PREDICTION                          ║
# ╚══════════════════════════════════════════════════════════╝
#
# System SSD (/)
# ─────────────
# Current Usage:      85% (100GB / 118GB)
# Trend:              +1.2% per day (1.4GB / day)
# Confidence:         High (R² = 0.94)
#
# Forecasts:
#   +7 days:          93% (110GB)
#   +14 days:         101% (CRITICAL - will be full!)
#
# Days until 90%:     5 days (Nov 23, 2025)
#
# Recommendation:     URGENT - Schedule cleanup within 2-3 days
#
# BTRFS Pool (/mnt/btrfs-pool)
# ─────────────────────
# Current Usage:      65% (8.5TB / 13TB)
# Trend:              +0.8% per day (100GB / day)
# Confidence:         Medium (R² = 0.78)
#
# Forecasts:
#   +7 days:          71% (9.2TB)
#   +14 days:         76% (9.9TB)
#
# Days until 90%:     31 days (Dec 19, 2025)
#
# Recommendation:     Monitor - no immediate action needed
```

### 3. Detect Memory Leaks

```bash
# Analyze memory trends for all services
./predict-resource-exhaustion.sh --type memory

# Output:
# ╔══════════════════════════════════════════════════════════╗
# ║           MEMORY LEAK DETECTION                          ║
# ╚══════════════════════════════════════════════════════════╝
#
# Jellyfin
# ────────
# Current Memory:     2.1GB
# Memory Limit:       4.0GB
# Trend:              +15MB per hour
# Confidence:         High (R² = 0.91)
#
# Time until limit:   38 hours (Nov 20, 03:00)
#
# Recommendation:     Schedule restart before Nov 20
#                     Optimal window: 2-5am (low traffic)
#
# Prometheus
# ──────────
# Current Memory:     850MB
# Memory Limit:       2.0GB
# Trend:              +2MB per hour
# Confidence:         Low (R² = 0.42)
#
# Time until limit:   575 hours (24 days)
#
# Recommendation:     No action needed - normal fluctuation
```

---

## Common Workflows

### Workflow 1: Weekly Resource Health Check

**Schedule:** Run every Monday morning

```bash
#!/bin/bash
# weekly-prediction-check.sh
# Run predictive analytics and email results

cd ~/containers/scripts/predictive-analytics

# Generate fresh predictions
./generate-predictions-cache.sh

# Check for critical issues
CRITICAL=$(jq -r '.summary.critical' ~/.claude/context/predictions.json)

if [ "$CRITICAL" -gt 0 ]; then
    # Critical issues found - send alert
    echo "⚠️  CRITICAL: $CRITICAL resource issues predicted"

    # Show details
    ./predict-resource-exhaustion.sh --output human

    # Optionally: Send email/Discord notification
    # curl -X POST $DISCORD_WEBHOOK -d "..."
else
    echo "✅ All systems healthy - no critical predictions"
fi
```

**Setup as cron job:**
```bash
# Edit crontab
crontab -e

# Add weekly check (Mondays at 8am)
0 8 * * 1 ~/containers/scripts/weekly-prediction-check.sh
```

### Workflow 2: Proactive Disk Cleanup

**Trigger:** Predictions show disk will be full in <7 days

```bash
# 1. Check disk predictions
cd ~/containers/scripts/predictive-analytics
./predict-resource-exhaustion.sh --type disk --output json > /tmp/disk-pred.json

# 2. Extract days until critical
DAYS=$(jq -r '.predictions.disk.system_ssd.days_until_critical' /tmp/disk-pred.json)

# 3. If <7 days, run cleanup
if [ "$DAYS" -lt 7 ]; then
    echo "⚠️  Disk will be full in $DAYS days - running cleanup"
    cd ~/containers/.claude/remediation/scripts
    ./apply-remediation.sh --playbook disk-cleanup
else
    echo "✅ Disk healthy - $DAYS days until critical"
fi
```

### Workflow 3: Memory Leak Mitigation

**Trigger:** Service showing persistent memory growth

```bash
# 1. Detect memory leak
cd ~/containers/scripts/predictive-analytics
./predict-resource-exhaustion.sh --type memory --service jellyfin

# 2. If leak detected (hours_until_limit < 48)
# Output shows:
# "Time until limit: 38 hours"
# "Recommendation: Schedule restart before Nov 20"

# 3. Schedule restart during low-traffic window
# Option A: Immediate (if critical)
systemctl --user restart jellyfin.service

# Option B: Scheduled (preferred)
echo "systemctl --user restart jellyfin.service" | at 03:00 tomorrow
# Restarts at 3am when traffic is low

# 4. Verify memory reset
sleep 60
podman stats jellyfin --no-stream
# Should show much lower memory usage
```

### Workflow 4: Trend Analysis for Capacity Planning

**Use case:** Plan hardware upgrades based on growth trends

```bash
# Analyze long-term trends (30 days)
cd ~/containers/scripts/predictive-analytics
./analyze-trends.sh \
  --metric 'node_filesystem_avail_bytes{mountpoint="/"}' \
  --lookback 30d \
  --forecast 90d \
  --output json > /tmp/disk-trend-30d.json

# Extract key metrics
SLOPE=$(jq -r '.regression.slope' /tmp/disk-trend-30d.json)
R2=$(jq -r '.regression.r_squared' /tmp/disk-trend-30d.json)
FORECAST_90=$(jq -r '.forecast.day_90.value' /tmp/disk-trend-30d.json)

# Capacity planning decision
# If 90-day forecast shows <10% free, plan upgrade
FREE_PERCENT=$((100 - $(echo $FORECAST_90 | jq -r '.percent_used')))

if [ "$FREE_PERCENT" -lt 10 ]; then
    echo "📊 Capacity planning: Need storage upgrade within 90 days"
    echo "   Current trend: $(echo $SLOPE | awk '{printf "%.2f GB/day", -$1/1e9}')"
    echo "   Forecast (90d): ${FREE_PERCENT}% free"
    echo "   Recommendation: Add 500GB SSD or migrate to larger drive"
fi
```

---

## Advanced Usage

### Custom Metric Analysis

```bash
# Analyze ANY Prometheus metric
cd ~/containers/scripts/predictive-analytics

# Example: Predict when Traefik request rate will exceed capacity
./analyze-trends.sh \
  --metric 'traefik_service_requests_total{service="jellyfin@docker"}' \
  --lookback 14d \
  --forecast 30d \
  --output json

# Example: Predict container restart frequency
./analyze-trends.sh \
  --metric 'engine_daemon_container_states_containers{state="restarting"}' \
  --lookback 7d \
  --forecast 14d

# Example: Network bandwidth growth
./analyze-trends.sh \
  --metric 'node_network_receive_bytes_total{device="eth0"}' \
  --lookback 30d \
  --forecast 60d
```

### Confidence Intervals

**What R² (R-squared) means:**
- **0.9 - 1.0:** High confidence (strong trend, reliable forecast)
- **0.7 - 0.9:** Medium confidence (moderate trend)
- **< 0.7:** Low confidence (noisy data, unreliable forecast)

```bash
# Check prediction confidence
./analyze-trends.sh \
  --metric 'node_filesystem_avail_bytes{mountpoint="/"}' \
  --lookback 7d \
  --output json | jq -r '.regression.r_squared'

# Example output: 0.94
# Interpretation: Very strong trend (94% of variance explained)

# If R² < 0.7, extend lookback window
./analyze-trends.sh \
  --metric 'container_memory_usage_bytes{name="jellyfin"}' \
  --lookback 14d  # Longer window = more stable trend
```

### Integration with Grafana

**Create Predictive Dashboard:**

1. **Add prediction data source:**
```bash
# Generate predictions regularly (cron)
*/15 * * * * cd ~/containers/scripts/predictive-analytics && ./generate-predictions-cache.sh

# Serve predictions.json via HTTP
# (Grafana can read JSON from URL)
```

2. **Dashboard panels:**
- **Disk Usage Forecast** - Line chart showing current + predicted
- **Memory Leak Detector** - Services with positive memory trends
- **Days Until Critical** - Gauge showing time to threshold
- **Prediction Confidence** - Heatmap of R² scores

3. **Alerts:**
```yaml
# Grafana alert when predictions show critical state
- alert: DiskWillBeFull
  expr: days_until_critical < 7
  annotations:
    summary: "Disk predicted to be full in {{ $value }} days"
    recommendation: "Run disk cleanup playbook"
```

### Automated Remediation Integration

```bash
# Fully automated: Check predictions, auto-remediate
#!/bin/bash
# auto-remediate.sh

cd ~/containers/scripts/predictive-analytics
./generate-predictions-cache.sh

CRITICAL=$(jq -r '.summary.critical' ~/.claude/context/predictions.json)

if [ "$CRITICAL" -gt 0 ]; then
    # Check what's critical
    DISK_CRITICAL=$(jq -r '.predictions.disk.system_ssd.severity' ~/.claude/context/predictions.json)

    if [ "$DISK_CRITICAL" = "critical" ]; then
        # Auto-run disk cleanup
        echo "[$(date)] Auto-remediation: Running disk cleanup (predicted exhaustion)"
        cd ~/containers/.claude/remediation/scripts
        ./apply-remediation.sh --playbook disk-cleanup

        # Log to context
        echo "{\"timestamp\": \"$(date -Iseconds)\", \"action\": \"auto_cleanup\", \"trigger\": \"predictive\"}" \
          >> ~/containers/data/remediation-logs/auto-actions.log
    fi
fi
```

**Setup:**
```bash
# Run daily at 2am
crontab -e
0 2 * * * ~/containers/scripts/auto-remediate.sh >> ~/containers/data/auto-remediate.log 2>&1
```

---

## Understanding the Output

### Trend Metrics Explained

**Example output:**
```
Trend: +1.2% per day (1.4GB / day)
Confidence: High (R² = 0.94)
```

**What it means:**
- **Trend:** Disk usage increasing by 1.2 percentage points daily
- **Absolute:** 1.4GB of data added per day
- **R² = 0.94:** 94% of variance explained by trend (very reliable)

### Forecast Interpretation

```
Forecasts:
  +7 days:  93% (110GB)
  +14 days: 101% (CRITICAL - will be full!)

Days until 90%: 5 days (Nov 23, 2025)
```

**How to read:**
- **+7 days:** In 1 week, disk will be 93% full
- **+14 days:** In 2 weeks, disk will exceed capacity (101%)
- **Days until 90%:** Countdown to warning threshold

### Severity Levels

| Severity | Condition | Action |
|----------|-----------|--------|
| **Critical** | <7 days until threshold | Immediate action required |
| **Warning** | 7-14 days until threshold | Schedule action this week |
| **Info** | >14 days until threshold | Monitor, no immediate action |

---

## Troubleshooting

### Issue: "No data available for metric"

**Cause:** Prometheus doesn't have enough historical data

**Solution:**
```bash
# Check Prometheus retention
curl http://localhost:9090/api/v1/status/config | jq -r '.data.yaml' | grep retention

# If retention < 7 days, predictions won't work
# Increase retention in prometheus.yml:
# --storage.tsdb.retention.time=15d

# Or use shorter lookback window
./analyze-trends.sh --lookback 3d  # Instead of 7d
```

### Issue: "Low confidence (R² < 0.5)"

**Cause:** Data is too noisy for reliable trend

**Solutions:**
```bash
# 1. Extend lookback window (more data = smoother trend)
./analyze-trends.sh --lookback 14d  # Instead of 7d

# 2. Check if metric is appropriate for trend analysis
# Some metrics fluctuate too much (CPU usage, network traffic)
# Better for: Disk usage, memory growth (monotonic trends)

# 3. Accept low confidence for informational purposes
# Don't act on predictions with R² < 0.7
```

### Issue: Negative trend (resource decreasing)

**Example:**
```
Trend: -0.3% per day
Days until 90%: N/A (trend is negative)
```

**Interpretation:**
- Disk usage is **decreasing** (cleanup happening automatically?)
- Memory usage is **stable** or decreasing (no leak)
- **No action needed** - system is healthy

---

## Best Practices

### 1. Regular Analysis Schedule

```bash
# Daily: Quick check
./generate-predictions-cache.sh

# Weekly: Detailed review
./predict-resource-exhaustion.sh --output human

# Monthly: Long-term trend analysis
./analyze-trends.sh --lookback 30d --forecast 90d
```

### 2. Act on High-Confidence Predictions Only

```bash
# Check confidence before acting
R2=$(./analyze-trends.sh --metric '...' --output json | jq -r '.regression.r_squared')

if (( $(echo "$R2 > 0.8" | bc -l) )); then
    # High confidence - safe to act on prediction
    echo "Trend reliable, acting on forecast"
else
    # Low confidence - gather more data
    echo "Trend uncertain, monitor for 1-2 more days"
fi
```

### 3. Combine with Reactive Monitoring

**Reactive (Alertmanager):**
- Alert when disk >90% (reactive)
- Alert when service OOM (reactive)

**Predictive (This system):**
- Forecast when disk will hit 90% (proactive)
- Detect memory leak trend (proactive)

**Use both:** Predictive prevents most issues, reactive catches unexpected spikes

### 4. Document Predictions and Outcomes

```bash
# Track prediction accuracy
cat >> ~/containers/data/prediction-tracking.log <<EOF
Date: $(date -Iseconds)
Prediction: Disk will be 90% on Nov 23
Actual: Disk was 91% on Nov 23
Accuracy: Good (1% error)
Action taken: Ran cleanup on Nov 21 (proactive)
Result: No service disruption
EOF

# Learn from predictions
# - Were forecasts accurate?
# - Did proactive actions prevent outages?
# - Adjust thresholds if needed
```

---

## Integration with Context Framework

```bash
# Add prediction results to context
cd ~/containers/.claude/context/scripts
nano populate-issue-history.sh

# Add prediction-based issue
add_issue "ISS-014" \
    "Predictive analytics forecasted disk exhaustion" \
    "disk-space" \
    "warning" \
    "2025-11-18" \
    "Predictive model showed disk would hit 90% in 5 days based on +1.2%/day trend" \
    "Proactive cleanup scheduled and executed 3 days before threshold" \
    "resolved"

# Regenerate issue history
./populate-issue-history.sh

# Query prediction-based issues
./query-issues.sh --category disk-space | grep -i predict
```

---

## Learning Exercises

### Exercise 1: Basic Prediction
```bash
# 1. Generate predictions
./generate-predictions-cache.sh

# 2. Read predictions.json
cat ~/.claude/context/predictions.json | jq '.summary'

# 3. Identify most critical prediction
cat ~/.claude/context/predictions.json | jq '.predictions | to_entries[] | select(.value | .. | .severity? == "critical")'

# 4. Take action based on prediction
```

### Exercise 2: Custom Metric Analysis
```bash
# Pick a metric from Prometheus
curl http://localhost:9090/api/v1/label/__name__/values | jq -r '.data[]' | grep container

# Analyze its trend
./analyze-trends.sh --metric 'container_memory_usage_bytes{name="jellyfin"}' --lookback 7d

# Interpret results
```

### Exercise 3: Compare Prediction vs Reality
```bash
# Day 1: Make prediction
./predict-resource-exhaustion.sh --type disk > /tmp/prediction-day1.txt

# Day 7: Check actual vs predicted
./predict-resource-exhaustion.sh --type disk > /tmp/actual-day7.txt

# Compare
diff /tmp/prediction-day1.txt /tmp/actual-day7.txt
# Were forecasts accurate?
```

---

## Reference: Available Scripts

### analyze-trends.sh
**Purpose:** Generic time-series trend analysis

**Usage:**
```bash
./analyze-trends.sh \
  --metric 'PROMETHEUS_QUERY' \
  --lookback 7d \
  --forecast 14d \
  --output json
```

**Output:** Slope, intercept, R², forecasts

### predict-resource-exhaustion.sh
**Purpose:** Disk and memory exhaustion prediction

**Usage:**
```bash
./predict-resource-exhaustion.sh --type all
./predict-resource-exhaustion.sh --type disk
./predict-resource-exhaustion.sh --type memory --service jellyfin
```

**Output:** Current usage, trend, forecast, days until critical

### generate-predictions-cache.sh
**Purpose:** Aggregate all predictions into single JSON

**Usage:**
```bash
./generate-predictions-cache.sh
cat ~/.claude/context/predictions.json | jq '.'
```

**Output:** predictions.json with all forecasts + summary

---

## Next Steps

**Beginner:**
1. Run `./generate-predictions-cache.sh`
2. View `predictions.json` output
3. Understand severity levels
4. Run weekly prediction check

**Intermediate:**
1. Set up weekly cron job
2. Create Grafana dashboard
3. Integrate with auto-remediation
4. Track prediction accuracy

**Advanced:**
1. Analyze custom Prometheus metrics
2. Build predictive alerts
3. Automate remediation based on predictions
4. Create capacity planning reports

---

**Bottom Line:** Predictive analytics transforms you from **reactive** ("Disk is full, fix it now!") to **proactive** ("Disk will be full in 5 days, schedule cleanup")

**Key Advantage:** Prevent outages before they happen by forecasting resource exhaustion 7-14 days in advance.

---

**Created:** 2025-11-18
**Version:** 1.0
**Maintainer:** patriark
**Session:** 5B - Proactive Health Management
