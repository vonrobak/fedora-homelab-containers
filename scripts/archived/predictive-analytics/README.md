# Predictive Analytics for Homelab

**Session 5B: Proactive Health Management**

Predictive analytics system that forecasts resource exhaustion and service failures before they occur, enabling proactive maintenance instead of reactive firefighting.

---

## Table of Contents

1. [Overview](#overview)
2. [Components](#components)
3. [Quick Start](#quick-start)
4. [Usage Examples](#usage-examples)
5. [Integration](#integration)
6. [Troubleshooting](#troubleshooting)

---

## Overview

### What is Predictive Analytics?

Instead of waiting for alerts when disk space hits 90%, predictive analytics forecasts **when** resources will be exhausted based on historical trends:

**Before (Reactive):**
```
Day 1: Disk at 85% - no alert
Day 2: Disk at 88% - no alert
Day 3: Disk at 92% - ALERT! Scramble to free space
Day 4: Service outage due to full disk
```

**After (Predictive):**
```
Day 1: Disk at 85% - predictive analysis shows:
  "Based on 7-day trend, disk will hit 90% in 5 days"
  Recommendation: "Schedule cleanup within next few days"
Day 2-4: Planned cleanup during maintenance window
Day 5+: No outage, proactive resolution
```

### Key Capabilities

1. **Disk Exhaustion Prediction**
   - Current usage percentage
   - Forecast for +7 and +14 days
   - Days until critical threshold (90%)
   - Trend analysis (GB/day usage rate)
   - Confidence scoring (R²)

2. **Memory Leak Detection**
   - Per-service memory trends
   - Leak detection (persistent upward trend)
   - Hours until container limit (4GB)
   - Restart recommendations

3. **Predictions Cache**
   - Aggregated view of all predictions
   - Overall severity assessment
   - Issue summary (critical/warning/info counts)
   - Single JSON file for easy monitoring integration

### Why This Matters

**Learning Value:**
- Time-series analysis (linear regression)
- Prometheus query_range API usage
- Statistical analysis with basic tools (awk)
- Proactive vs reactive monitoring mindset

**Operational Value:**
- Prevent service outages before they occur
- Plan maintenance during low-traffic windows
- Track resource trends over time
- Identify memory leaks early

---

## Components

### 1. analyze-trends.sh

**Purpose:** Generic time-series trend analysis engine

**Features:**
- Query Prometheus for historical metrics
- Calculate linear regression (slope, intercept, R²)
- Forecast future values
- Support for any Prometheus metric
- JSON and human-readable output

**Usage:**
```bash
./analyze-trends.sh \
  --metric 'node_filesystem_avail_bytes{mountpoint="/"}' \
  --lookback 7d \
  --forecast 14d \
  --output json
```

**Output:**
```json
{
  "metric": "node_filesystem_avail_bytes{mountpoint=\"/\"}",
  "analysis": {
    "data_points": 169,
    "r_squared": 0.4522,
    "slope": -15125.6107356563,
    "intercept": 26693924551910.41
  },
  "values": {
    "current": 19918883188.41,
    "forecast_7d": 10770913815.49,
    "forecast_14d": 1622944442.57
  },
  "trend": {
    "direction": "decreasing",
    "confidence": "low"
  }
}
```

### 2. predict-resource-exhaustion.sh

**Purpose:** Predict disk and memory exhaustion

**Features:**
- Disk usage prediction (root filesystem)
- Memory usage prediction (per-service)
- Severity assessment (critical/warning/info)
- Actionable recommendations
- Days/hours until threshold crossing

**Usage:**
```bash
# Disk prediction
./predict-resource-exhaustion.sh --type disk

# Memory prediction for specific service
./predict-resource-exhaustion.sh --type memory --service jellyfin

# JSON output
./predict-resource-exhaustion.sh --type disk --output json
```

**Output (Disk):**
```
==========================================
Disk Usage Prediction (Root /)
==========================================

Current usage: 84.2%
Forecast (+7d): 91.4%
Trend: -1.21 GB/day
Confidence: 0.4514

Days until 90%: 5
Severity: CRITICAL

Recommendation:
  Schedule disk cleanup within next few days.
==========================================
```

**Output (Memory - JSON):**
```json
{
  "resource": "memory",
  "service": "jellyfin",
  "current_mb": 1210,
  "forecast_7d_mb": 183,
  "trend_mb_per_hour": -6.11,
  "is_memory_leak": false,
  "hours_until_4gb": "never",
  "confidence": 0.1503,
  "severity": "info",
  "recommendation": "No action needed. Memory usage is stable."
}
```

### 3. generate-predictions-cache.sh

**Purpose:** Aggregate all predictions into single JSON cache

**Features:**
- Run predictions for all monitored resources
- Calculate overall severity
- Count issues by severity level
- Single file output for easy consumption
- Timestamped results

**Usage:**
```bash
# Generate cache (default: ~/containers/data/predictions.json)
./generate-predictions-cache.sh

# Custom output location
./generate-predictions-cache.sh --output /tmp/predictions.json

# Longer lookback window
./generate-predictions-cache.sh --lookback 14d
```

**Output:**
```json
{
  "generated_at": "2025-11-18T22:14:04.777331",
  "lookback_window": "7d",
  "overall_severity": "critical",
  "issue_summary": {
    "critical": 1,
    "warning": 0,
    "info": 6
  },
  "predictions": {
    "disk": {
      "resource": "disk",
      "mountpoint": "/",
      "current_usage_pct": 83.9,
      "forecast_7d_pct": 90.7,
      "trend_gb_per_day": -1.14,
      "days_until_90pct": "6",
      "confidence": 0.3758,
      "severity": "critical",
      "recommendation": "Schedule disk cleanup within next few days."
    },
    "memory": [
      {
        "resource": "memory",
        "service": "jellyfin",
        "current_mb": 1193,
        "forecast_7d_mb": 150,
        "trend_mb_per_hour": -6.21,
        "is_memory_leak": false,
        "hours_until_4gb": "never",
        "confidence": 0.1573,
        "severity": "info",
        "recommendation": "No action needed. Memory usage is stable."
      }
    ]
  }
}
```

---

## Quick Start

### 1. Verify Prerequisites

```bash
# Ensure Prometheus is running and accessible
podman ps | grep prometheus
curl -f http://localhost:9090/-/healthy

# Check for historical data (need at least 2 days)
podman exec prometheus wget -q -O- \
  'http://localhost:9090/api/v1/query?query=up' | \
  python3 -c "import json, sys; print(len(json.load(sys.stdin)['data']['result']))"
```

### 2. Run First Prediction

```bash
cd ~/containers/scripts/predictive-analytics

# Analyze disk usage trend
./analyze-trends.sh \
  --metric 'node_filesystem_avail_bytes{mountpoint="/"}' \
  --lookback 7d

# Predict disk exhaustion
./predict-resource-exhaustion.sh --type disk

# Predict memory usage for Jellyfin
./predict-resource-exhaustion.sh --type memory --service jellyfin
```

### 3. Generate Predictions Cache

```bash
# Create aggregated predictions
./generate-predictions-cache.sh

# View results
cat ~/containers/data/predictions.json | python3 -m json.tool
```

---

## Usage Examples

### Example 1: Disk Space Monitoring

**Scenario:** You want to know when disk cleanup is needed.

```bash
# Human-readable output
./predict-resource-exhaustion.sh --type disk

# Output:
# Current usage: 84.2%
# Forecast (+7d): 91.4%
# Days until 90%: 5
# Recommendation: Schedule disk cleanup within next few days.
```

**Action:** Schedule cleanup within 2-3 days (before the 5-day prediction).

---

### Example 2: Memory Leak Detection

**Scenario:** Jellyfin seems to be using more memory over time.

```bash
# Check memory trend
./predict-resource-exhaustion.sh --type memory --service jellyfin

# Output:
# Current usage: 1210 MB
# Trend: -6.11 MB/hour
# Memory leak detected: false
# Recommendation: No action needed. Memory usage is stable.
```

**Result:** Memory is actually stable or decreasing. No leak detected.

---

### Example 3: Custom Metric Analysis

**Scenario:** You want to analyze Prometheus scrape duration trends.

```bash
# Analyze scrape duration
./analyze-trends.sh \
  --metric 'scrape_duration_seconds{job="prometheus"}' \
  --lookback 14d \
  --forecast 7d \
  --output json

# Check if scrape times are increasing (performance degradation)
```

---

### Example 4: Scheduled Predictions via Cron

**Scenario:** Run predictions daily and alert on critical issues.

```bash
# Add to crontab
crontab -e

# Run predictions every day at 6 AM
0 6 * * * /home/patriark/containers/scripts/predictive-analytics/generate-predictions-cache.sh

# Check for critical issues and notify
5 6 * * * grep -q '"overall_severity": "critical"' ~/containers/data/predictions.json && \
  echo "Critical prediction detected - check predictions.json" | mail -s "Homelab Alert" you@example.com
```

---

## Integration

### Integration with Grafana

Create a dashboard panel that reads the predictions cache:

**Panel Type:** Stat/Gauge

**Query:**
```json
# Use JSON API datasource or file-based data source
# Read: ~/containers/data/predictions.json

# Display:
# - overall_severity as colored badge
# - days_until_90pct as gauge
# - issue_summary as stat
```

**Alert Rules:**
```yaml
- name: Disk Exhaustion Predicted
  condition: predictions.disk.severity == "critical"
  notification: "Disk will hit 90% in {{ predictions.disk.days_until_90pct }} days"
```

---

### Integration with Alertmanager

Create alert based on predictions cache:

**Alert Rule (PromQL):**
```yaml
# File: prometheus/rules/predictive-alerts.yml

groups:
  - name: predictive_analytics
    interval: 1h
    rules:
      - alert: DiskExhaustionPredicted
        expr: |
          (100 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100) > 85
        for: 4h
        annotations:
          summary: "Disk space will be exhausted soon"
          description: "Based on trend analysis, root filesystem will hit 90% within {{ $value }} days. Run cleanup."
```

**Note:** For more sophisticated predictions, use the predictions cache as a separate data source.

---

### Integration with Monitoring Scripts

```bash
#!/bin/bash
# check-predictions.sh
# Check predictions cache and take action

PREDICTIONS_FILE="$HOME/containers/data/predictions.json"

# Check overall severity
SEVERITY=$(python3 -c "import json; print(json.load(open('$PREDICTIONS_FILE'))['overall_severity'])")

case $SEVERITY in
    critical)
        echo "CRITICAL: Immediate action required"
        # Trigger cleanup script
        ~/containers/scripts/cleanup-disk.sh --auto
        ;;
    warning)
        echo "WARNING: Plan maintenance soon"
        # Send notification
        ;;
    *)
        echo "INFO: System healthy"
        ;;
esac
```

---

## Troubleshooting

### Issue: "Not enough data points"

**Symptom:**
```
[ERROR] Not enough data points (need at least 2, got 1)
```

**Cause:** Prometheus doesn't have enough historical data (metrics recently started collecting).

**Solution:**
- Wait for more data to accumulate (at least 2-3 hours with hourly steps)
- Use shorter lookback window: `--lookback 1d`
- Check metric exists: `podman exec prometheus wget -q -O- 'http://localhost:9090/api/v1/query?query=YOUR_METRIC'`

---

### Issue: "Could not analyze memory trend for service"

**Symptom:**
```
[WARNING] Could not analyze memory trend for jellyfin
```

**Cause:** Service name doesn't match cgroup path pattern.

**Solution:**

1. Check container is running:
   ```bash
   systemctl --user status jellyfin.service
   ```

2. Verify cAdvisor is collecting metrics:
   ```bash
   podman exec prometheus wget -q -O- \
     'http://localhost:9090/api/v1/query?query=container_memory_usage_bytes' | \
     python3 -c "import json, sys; print([r['metric']['id'] for r in json.load(sys.stdin)['data']['result'] if 'jellyfin' in r['metric'].get('id', '')])"
   ```

3. If metric not found, check cAdvisor configuration or use different service name.

---

### Issue: Low Confidence (R² < 0.5)

**Symptom:**
```
Confidence: LOW (R² < 0.5)
```

**Meaning:** Data has high variability, linear trend doesn't fit well.

**Implications:**
- Prediction may not be accurate
- Resource usage is erratic or cyclic
- More data needed for better fit

**What to Do:**
- Take prediction with grain of salt
- Use longer lookback window: `--lookback 14d`
- Check for cyclic patterns (e.g., nightly backups causing spikes)
- Consider median-based analysis instead of linear regression

---

### Issue: Negative Forecast Values

**Symptom:**
```
Forecast (+14d): -64899.16
```

**Cause:** Strong downward trend extrapolated too far into future.

**Solution:**
- Linear regression can produce nonsensical forecasts when extrapolated
- Treat negative values as "approaching zero"
- Use shorter forecast windows
- Interpretation: Resource is being freed faster than consumed

---

## Technical Details

### Linear Regression Implementation

The trend analysis uses least-squares linear regression:

**Formulas:**
```
slope = (n * Σ(xy) - Σx * Σy) / (n * Σ(x²) - (Σx)²)
intercept = (Σy - slope * Σx) / n

R² = (correlation)² where:
  correlation = covariance(x,y) / (σ_x * σ_y)
```

**Implementation:** Pure awk (no external dependencies).

**Data Resolution:** 1-hour steps (3600 seconds).

**Why awk?** Lightweight, available everywhere, surprisingly capable for statistical analysis.

---

### Prometheus Query Pattern

**Query Type:** `query_range` (time-series data over range)

**Parameters:**
- `start`: Current time - lookback window
- `end`: Current time
- `step`: 3600 (1-hour resolution)

**Execution:** Inside Prometheus container via `podman exec` + `wget`.

**Why inside container?** Avoids network auth, simplifies configuration.

---

### Memory Leak Detection Logic

**Criteria for Memory Leak:**
1. Slope > 0 (upward trend)
2. R² > 0.7 (high confidence, consistent growth)

**Why R² > 0.7?** Filters out noisy/erratic growth. True leaks show consistent upward trend.

**False Positives:** Services with legitimate growth (e.g., cache warming).

---

## Future Enhancements

1. **predict-service-failure.sh**
   - Analyze service health check trends
   - Predict service degradation before failure
   - Detect anomalies in response times

2. **Exponential Smoothing**
   - Better handling of seasonal patterns
   - Weighted recent data more heavily
   - Handle cyclic usage (daily/weekly patterns)

3. **Anomaly Detection**
   - Detect sudden changes in trends
   - Alert on unexpected behavior
   - Baseline deviation analysis

4. **Multi-Metric Correlation**
   - Correlate disk and memory usage
   - Identify cascading failures
   - Root cause analysis

---

## Related Documentation

- **Session 5 Plan:** `~/containers/docs/99-reports/SESSION-5-MULTI-SERVICE-ORCHESTRATION-PLAN.md`
- **Monitoring Guide:** `~/containers/docs/40-monitoring-and-documentation/guides/monitoring-stack.md`
- **Prometheus Documentation:** `~/containers/config/prometheus/README.md`

---

**Created:** 2025-11-18 (Session 5B)
**Status:** Production-ready
**Maintainer:** homelab-deployment skill
