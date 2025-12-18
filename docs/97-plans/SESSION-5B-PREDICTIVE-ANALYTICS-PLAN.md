# Session 5B: Predictive Analytics & Proactive Health Management

**Status**: Ready for Implementation
**Priority**: HIGH
**Estimated Effort**: 8-10 hours across 3-4 CLI sessions
**Dependencies**: Session 4 (Context Framework), existing monitoring stack
**Branch**: TBD (create `feature/predictive-analytics` during implementation)

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Problem Statement](#problem-statement)
3. [Architecture Overview](#architecture-overview)
4. [Core Components](#core-components)
5. [Implementation Phases](#implementation-phases)
6. [Integration Points](#integration-points)
7. [Testing Strategy](#testing-strategy)
8. [Success Metrics](#success-metrics)
9. [Future Enhancements](#future-enhancements)

---

## Executive Summary

**What**: Machine learning-based predictive analytics engine that forecasts system issues before they become critical, enabling proactive maintenance and preventing service disruptions.

**Why**:
- Current monitoring is **reactive** (alerts after problems occur)
- Resource exhaustion (disk, memory) often catches us by surprise
- Service failures could be predicted from usage patterns
- Optimal backup/maintenance windows are guessed, not calculated

**How**:
- Analyze historical Prometheus metrics to detect patterns
- Build lightweight prediction models (linear regression, moving averages)
- Generate proactive recommendations before thresholds are crossed
- Integrate with homelab-intelligence skill for actionable insights

**Key Deliverables**:
- `scripts/analyze-trends.sh` - Historical data analysis engine
- `scripts/predict-resource-exhaustion.sh` - Disk/memory forecasting
- `scripts/predict-service-failure.sh` - Service health degradation detection
- `.claude/context/predictions.json` - Prediction cache for skill integration
- `docs/40-monitoring-and-documentation/guides/predictive-analytics.md` - Usage guide

---

## Problem Statement

### Current State: Reactive Monitoring

Our monitoring stack (Prometheus + Grafana + Alertmanager) is **excellent at detecting problems**, but **poor at preventing them**:

**Example 1: Disk Exhaustion**
```
❌ Current Behavior:
- Disk usage: 65% → 75% → 85% → 🚨 ALERT at 90%
- By the time we're alerted, only 10% headroom remains
- Scramble to free space under pressure

✅ Desired Behavior:
- Detect trend: +2% per day over last 7 days
- Predict: Will hit 90% in 12 days
- Proactive alert: "Disk will be full by Nov 28 - schedule cleanup"
```

**Example 2: Memory Leak Detection**
```
❌ Current Behavior:
- Service restarts every 3 days due to OOM
- Pattern not obvious without manual correlation
- Each restart causes service disruption

✅ Desired Behavior:
- Detect: Jellyfin memory grows 15MB/hour consistently
- Predict: Will OOM in 48 hours
- Proactive recommendation: "Schedule restart during low-usage window (3-5am)"
```

**Example 3: Service Degradation**
```
❌ Current Behavior:
- Health checks pass, but response times degrading
- Users notice slowness before monitoring alerts

✅ Desired Behavior:
- Detect: Authelia response time increasing 50ms/day
- Predict: Will exceed 500ms threshold in 6 days
- Investigate before users are impacted
```

### Goals

1. **Predict resource exhaustion** 7-14 days in advance
2. **Detect memory leaks** and recommend optimal restart windows
3. **Forecast service failures** based on health check degradation
4. **Recommend optimal maintenance windows** based on usage patterns
5. **Integrate predictions** into homelab-intelligence skill for conversational access

---

## Architecture Overview

### Data Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                     PROMETHEUS (Metrics Source)                      │
│  - node_filesystem_avail_bytes (disk usage)                         │
│  - container_memory_usage_bytes (memory trends)                     │
│  - probe_success (health check history)                             │
│  - probe_duration_seconds (response time trends)                    │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│              ANALYSIS ENGINE (scripts/analyze-trends.sh)             │
│                                                                      │
│  1. Query Prometheus for historical data (7-30 days)                │
│  2. Calculate trends using linear regression                        │
│  3. Extrapolate to predict future values                            │
│  4. Generate confidence intervals                                   │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│           PREDICTION MODELS (specialized analyzers)                  │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ predict-resource-exhaustion.sh                               │  │
│  │ - Disk usage forecasting (root /, BTRFS pool)               │  │
│  │ - Memory usage trends per service                            │  │
│  │ - Model: Linear regression with 7-day moving average        │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ predict-service-failure.sh                                   │  │
│  │ - Health check success rate trends                           │  │
│  │ - Response time degradation                                  │  │
│  │ - Restart frequency analysis                                 │  │
│  │ - Model: Exponential moving average + threshold crossing    │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ find-optimal-maintenance-window.sh                           │  │
│  │ - Analyze HTTP request patterns                              │  │
│  │ - Find low-traffic time windows                              │  │
│  │ - Model: Time-series clustering                              │  │
│  └──────────────────────────────────────────────────────────────┘  │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│         PREDICTION CACHE (.claude/context/predictions.json)          │
│                                                                      │
│  {                                                                   │
│    "generated_at": "2025-11-16T10:30:00Z",                          │
│    "predictions": [                                                  │
│      {                                                               │
│        "type": "disk_exhaustion",                                   │
│        "resource": "/",                                              │
│        "current_usage_pct": 67.4,                                   │
│        "trend_pct_per_day": 2.1,                                    │
│        "predicted_full_date": "2025-11-28",                         │
│        "days_until_full": 12,                                       │
│        "confidence": 0.89,                                           │
│        "severity": "warning",                                        │
│        "recommendation": "Schedule disk cleanup within 7 days"      │
│      },                                                              │
│      {                                                               │
│        "type": "memory_leak",                                       │
│        "service": "jellyfin",                                       │
│        "current_usage_mb": 512,                                     │
│        "trend_mb_per_hour": 15,                                     │
│        "predicted_oom_hours": 48,                                   │
│        "confidence": 0.76,                                           │
│        "severity": "warning",                                        │
│        "recommendation": "Schedule restart during 3-5am window"     │
│      }                                                               │
│    ]                                                                 │
│  }                                                                   │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│              INTEGRATION POINTS                                      │
│                                                                      │
│  1. homelab-intelligence skill reads predictions.json               │
│  2. Grafana dashboard displays forecasts                            │
│  3. Alertmanager sends proactive alerts (optional)                  │
│  4. Auto-remediation playbooks triggered by predictions             │
└─────────────────────────────────────────────────────────────────────┘
```

### Technology Stack

**Data Source**: Prometheus (already deployed)
**Analysis Language**: Bash + awk (for lightweight regression)
**Alternative**: Python (if complex models needed - install scipy)
**Storage**: JSON files in `.claude/context/` (integrated with Session 4)
**Visualization**: Grafana annotations (display predictions on dashboards)

---

## Core Components

### Component 1: Analysis Engine

**File**: `scripts/analyze-trends.sh`

**Purpose**: Generic time-series analysis engine for Prometheus metrics.

**Features**:
- Query Prometheus for historical data (7-90 day windows)
- Calculate linear regression (slope, intercept, R²)
- Extrapolate future values with confidence intervals
- Detect trend changes (acceleration/deceleration)

**Usage**:
```bash
# Analyze disk usage trend
./scripts/analyze-trends.sh \
  --metric 'node_filesystem_avail_bytes{mountpoint="/"}' \
  --lookback 7d \
  --forecast 14d \
  --output json

# Output:
# {
#   "metric": "node_filesystem_avail_bytes",
#   "data_points": 1008,
#   "trend": {
#     "slope": -2147483648,  # bytes per day
#     "slope_human": "-2.0 GB/day",
#     "r_squared": 0.89,
#     "confidence": "high"
#   },
#   "forecast": {
#     "current_value": 42949672960,
#     "current_human": "40.0 GB free",
#     "predicted_7d": 28991029248,
#     "predicted_14d": 15032385536,
#     "predicted_zero_date": "2025-11-28"
#   }
# }
```

**Implementation** (400 lines):
```bash
#!/bin/bash
# scripts/analyze-trends.sh

set -euo pipefail

# Configuration
PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9090}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --metric)
                METRIC="$2"
                shift 2
                ;;
            --lookback)
                LOOKBACK="$2"  # e.g., 7d, 30d
                shift 2
                ;;
            --forecast)
                FORECAST="$2"  # e.g., 14d, 30d
                shift 2
                ;;
            --output)
                OUTPUT_FORMAT="$2"  # json or human
                shift 2
                ;;
            *)
                echo "Unknown option: $1" >&2
                exit 1
                ;;
        esac
    done
}

# Query Prometheus
query_prometheus() {
    local metric=$1
    local lookback=$2

    # Query range vector for last N days at 1-hour resolution
    local end_time=$(date +%s)
    local start_time=$((end_time - $(parse_duration "$lookback")))

    curl -s "${PROMETHEUS_URL}/api/v1/query_range" \
        --data-urlencode "query=${metric}" \
        --data-urlencode "start=${start_time}" \
        --data-urlencode "end=${end_time}" \
        --data-urlencode "step=3600" \
        | jq -r '.data.result[0].values | .[] | @tsv'
}

# Linear regression using awk
calculate_regression() {
    # Input: timestamp value pairs
    # Output: slope intercept r_squared

    awk '
    BEGIN {
        n = 0
        sum_x = 0
        sum_y = 0
        sum_xx = 0
        sum_xy = 0
        sum_yy = 0
    }
    {
        x = $1  # timestamp
        y = $2  # metric value

        n++
        sum_x += x
        sum_y += y
        sum_xx += x * x
        sum_xy += x * y
        sum_yy += y * y
    }
    END {
        # Calculate slope and intercept
        slope = (n * sum_xy - sum_x * sum_y) / (n * sum_xx - sum_x * sum_x)
        intercept = (sum_y - slope * sum_x) / n

        # Calculate R² (coefficient of determination)
        mean_y = sum_y / n
        ss_tot = sum_yy - n * mean_y * mean_y
        ss_res = sum_yy - intercept * sum_y - slope * sum_xy
        r_squared = 1 - (ss_res / ss_tot)

        printf "%.10f %.10f %.4f\n", slope, intercept, r_squared
    }
    '
}

# Extrapolate future values
forecast_values() {
    local slope=$1
    local intercept=$2
    local current_time=$3
    local forecast_days=$4

    local forecast_seconds=$((forecast_days * 86400))

    for days in $(seq 1 "$forecast_days"); do
        local future_time=$((current_time + days * 86400))
        local predicted_value=$(awk "BEGIN {print $slope * $future_time + $intercept}")
        echo "$days $predicted_value"
    done
}

# Determine when metric will hit zero (for decreasing trends)
calculate_zero_crossing() {
    local slope=$1
    local intercept=$2
    local current_time=$3

    if (( $(awk "BEGIN {print ($slope >= 0)}") )); then
        echo "never"  # Increasing trend
        return
    fi

    # Solve: 0 = slope * t + intercept
    # t = -intercept / slope
    local zero_time=$(awk "BEGIN {print -1 * $intercept / $slope}")
    local days_until_zero=$(awk "BEGIN {print int(($zero_time - $current_time) / 86400)}")

    if (( days_until_zero < 0 )); then
        echo "already_zero"
    else
        echo "$days_until_zero"
    fi
}

# Main execution
main() {
    parse_args "$@"

    # Query data
    local data=$(query_prometheus "$METRIC" "$LOOKBACK")

    if [[ -z "$data" ]]; then
        echo "Error: No data returned from Prometheus" >&2
        exit 1
    fi

    # Calculate regression
    local regression=$(echo "$data" | calculate_regression)
    read slope intercept r_squared <<< "$regression"

    # Forecast
    local current_time=$(date +%s)
    local forecast_days=$(parse_duration "$FORECAST" | awk '{print int($1 / 86400)}')
    local forecasts=$(forecast_values "$slope" "$intercept" "$current_time" "$forecast_days")

    # Calculate zero crossing
    local zero_days=$(calculate_zero_crossing "$slope" "$intercept" "$current_time")

    # Output
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        cat <<EOF
{
  "metric": "${METRIC}",
  "analysis": {
    "slope": ${slope},
    "intercept": ${intercept},
    "r_squared": ${r_squared}
  },
  "forecast": $(echo "$forecasts" | jq -Rs 'split("\n") | map(select(length > 0) | split(" ") | {days: .[0]|tonumber, value: .[1]|tonumber})'),
  "zero_crossing_days": ${zero_days}
}
EOF
    else
        echo "Trend Analysis for: ${METRIC}"
        echo "Slope: ${slope}"
        echo "R²: ${r_squared}"
        echo "Days until zero: ${zero_days}"
    fi
}

# Helper: Parse duration strings (7d → seconds)
parse_duration() {
    local duration=$1
    local value=${duration%?}
    local unit=${duration: -1}

    case $unit in
        d) echo $((value * 86400)) ;;
        h) echo $((value * 3600)) ;;
        *) echo "Invalid duration: $duration" >&2; exit 1 ;;
    esac
}

main "$@"
```

---

### Component 2: Resource Exhaustion Predictor

**File**: `scripts/predict-resource-exhaustion.sh`

**Purpose**: Forecast when disk/memory will be exhausted based on current trends.

**Prediction Types**:
1. **Disk Exhaustion** (root filesystem `/`)
2. **Disk Exhaustion** (BTRFS pool `/mnt/btrfs-pool`)
3. **Memory Exhaustion** (per-service)
4. **Container Image Storage** (`/var/lib/containers`)

**Usage**:
```bash
# Check all resources
./scripts/predict-resource-exhaustion.sh --all

# Check specific resource
./scripts/predict-resource-exhaustion.sh --resource disk --mount /

# Output to predictions cache
./scripts/predict-resource-exhaustion.sh --all --output ~/.claude/context/predictions.json
```

**Output Example**:
```json
{
  "predictions": [
    {
      "type": "disk_exhaustion",
      "resource": "/",
      "current_usage_pct": 67.4,
      "current_free_gb": 40.2,
      "trend_gb_per_day": -2.1,
      "predicted_full_date": "2025-11-28",
      "days_until_full": 12,
      "confidence": 0.89,
      "severity": "warning",
      "recommendation": "Schedule disk cleanup within 7 days. Run: ./scripts/homelab-diagnose.sh --disk-usage"
    },
    {
      "type": "memory_trend",
      "service": "jellyfin",
      "current_usage_mb": 512,
      "memory_limit_mb": 4096,
      "trend_mb_per_hour": 15,
      "predicted_oom_hours": 48,
      "confidence": 0.76,
      "severity": "warning",
      "recommendation": "Possible memory leak. Schedule restart during 3-5am window."
    }
  ]
}
```

**Implementation** (300 lines):
```bash
#!/bin/bash
# scripts/predict-resource-exhaustion.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREDICTIONS_FILE="${PREDICTIONS_FILE:-$HOME/.claude/context/predictions.json}"

# Predict disk exhaustion for a mount point
predict_disk_exhaustion() {
    local mount=$1

    # Query available bytes trend
    local trend_analysis=$("$SCRIPT_DIR/analyze-trends.sh" \
        --metric "node_filesystem_avail_bytes{mountpoint=\"${mount}\"}" \
        --lookback 7d \
        --forecast 30d \
        --output json)

    # Extract key metrics
    local slope=$(echo "$trend_analysis" | jq -r '.analysis.slope')
    local r_squared=$(echo "$trend_analysis" | jq -r '.analysis.r_squared')
    local zero_days=$(echo "$trend_analysis" | jq -r '.zero_crossing_days')

    # Get current usage
    local current_free=$(df -B1 "$mount" | tail -1 | awk '{print $4}')
    local current_total=$(df -B1 "$mount" | tail -1 | awk '{print $2}')
    local current_pct=$(awk "BEGIN {print 100 - ($current_free / $current_total * 100)}")

    # Determine severity
    local severity="info"
    if [[ "$zero_days" != "never" ]] && (( zero_days < 7 )); then
        severity="critical"
    elif [[ "$zero_days" != "never" ]] && (( zero_days < 14 )); then
        severity="warning"
    fi

    # Generate recommendation
    local recommendation="No action needed"
    if [[ "$severity" == "critical" ]]; then
        recommendation="URGENT: Disk will be full in ${zero_days} days. Run cleanup immediately."
    elif [[ "$severity" == "warning" ]]; then
        recommendation="Schedule disk cleanup within 7 days. Run: ./scripts/homelab-diagnose.sh --disk-usage"
    fi

    # Output JSON
    cat <<EOF
{
  "type": "disk_exhaustion",
  "resource": "${mount}",
  "current_usage_pct": ${current_pct},
  "current_free_gb": $(awk "BEGIN {print $current_free / 1024^3}"),
  "trend_gb_per_day": $(awk "BEGIN {print $slope * 86400 / 1024^3}"),
  "predicted_full_date": $(if [[ "$zero_days" != "never" ]]; then date -d "+${zero_days} days" +%Y-%m-%d; else echo "null"; fi),
  "days_until_full": ${zero_days},
  "confidence": ${r_squared},
  "severity": "${severity}",
  "recommendation": "${recommendation}"
}
EOF
}

# Predict memory exhaustion for a service
predict_memory_exhaustion() {
    local service=$1

    # Query memory usage trend
    local trend_analysis=$("$SCRIPT_DIR/analyze-trends.sh" \
        --metric "container_memory_usage_bytes{name=\"${service}\"}" \
        --lookback 7d \
        --forecast 7d \
        --output json)

    local slope=$(echo "$trend_analysis" | jq -r '.analysis.slope')
    local r_squared=$(echo "$trend_analysis" | jq -r '.analysis.r_squared')

    # Get current memory and limit
    local current_mem=$(podman stats --no-stream --format "{{.MemUsage}}" "$service" | awk '{print $1}' | numfmt --from=iec)
    local mem_limit=$(podman inspect "$service" | jq -r '.[0].HostConfig.Memory')

    if [[ "$mem_limit" == "0" ]] || [[ "$mem_limit" == "null" ]]; then
        mem_limit=$((4 * 1024**3))  # Default 4GB if no limit
    fi

    # Calculate hours until OOM (if trend is positive)
    local hours_until_oom="null"
    if (( $(awk "BEGIN {print ($slope > 0)}") )); then
        local remaining=$((mem_limit - current_mem))
        hours_until_oom=$(awk "BEGIN {print int($remaining / ($slope * 3600))}")
    fi

    # Determine severity
    local severity="info"
    if [[ "$hours_until_oom" != "null" ]] && (( hours_until_oom < 48 )); then
        severity="warning"
    fi

    # Output JSON
    cat <<EOF
{
  "type": "memory_trend",
  "service": "${service}",
  "current_usage_mb": $(awk "BEGIN {print int($current_mem / 1024^2)}"),
  "memory_limit_mb": $(awk "BEGIN {print int($mem_limit / 1024^2)}"),
  "trend_mb_per_hour": $(awk "BEGIN {print $slope * 3600 / 1024^2}"),
  "predicted_oom_hours": ${hours_until_oom},
  "confidence": ${r_squared},
  "severity": "${severity}",
  "recommendation": "$(if [[ "$severity" == "warning" ]]; then echo "Possible memory leak. Schedule restart during 3-5am window."; else echo "Memory usage stable."; fi)"
}
EOF
}

main() {
    # Initialize predictions array
    local predictions="[]"

    # Predict disk exhaustion for critical mounts
    for mount in / /mnt/btrfs-pool; do
        if mountpoint -q "$mount" 2>/dev/null; then
            local pred=$(predict_disk_exhaustion "$mount")
            predictions=$(echo "$predictions" | jq ". += [$pred]")
        fi
    done

    # Predict memory exhaustion for running services
    while IFS= read -r service; do
        local pred=$(predict_memory_exhaustion "$service")
        predictions=$(echo "$predictions" | jq ". += [$pred]")
    done < <(podman ps --format "{{.Names}}")

    # Output final predictions
    cat <<EOF
{
  "generated_at": "$(date -Iseconds)",
  "predictions": $predictions
}
EOF
}

main "$@"
```

---

### Component 3: Service Failure Predictor

**File**: `scripts/predict-service-failure.sh`

**Purpose**: Detect degrading service health before total failure.

**Indicators**:
1. **Health Check Success Rate** declining
2. **Response Time** increasing steadily
3. **Restart Frequency** increasing
4. **Error Rate** in logs increasing

**Usage**:
```bash
# Analyze specific service
./scripts/predict-service-failure.sh --service jellyfin

# Analyze all services
./scripts/predict-service-failure.sh --all
```

**Output Example**:
```json
{
  "service": "authelia",
  "indicators": [
    {
      "type": "response_time_degradation",
      "current_avg_ms": 245,
      "trend_ms_per_day": 18,
      "predicted_threshold_crossing": "2025-11-22",
      "threshold_ms": 500,
      "severity": "warning",
      "recommendation": "Investigate Authelia performance. Check Redis connection pool."
    },
    {
      "type": "health_check_success_rate",
      "current_rate": 0.98,
      "trend_per_day": -0.02,
      "severity": "info",
      "recommendation": "Health check success rate stable."
    }
  ]
}
```

**Implementation** (350 lines - similar structure to resource predictor)

---

### Component 4: Optimal Maintenance Window Finder

**File**: `scripts/find-optimal-maintenance-window.sh`

**Purpose**: Analyze traffic patterns to recommend best time for maintenance.

**Analysis**:
- Query Traefik request metrics over 30 days
- Group by hour of day and day of week
- Find 2-hour windows with lowest traffic
- Account for service-specific patterns

**Usage**:
```bash
# Find best window for general maintenance
./scripts/find-optimal-maintenance-window.sh

# Output:
# Optimal Maintenance Window Analysis (30-day history)
#
# Recommended Windows:
# 1. Tuesday 3:00-5:00 AM (avg: 12 req/hour, 95th %ile: 28 req/hour)
# 2. Wednesday 3:00-5:00 AM (avg: 15 req/hour, 95th %ile: 32 req/hour)
# 3. Monday 2:00-4:00 AM (avg: 18 req/hour, 95th %ile: 35 req/hour)
#
# Avoid:
# - Friday 8:00-10:00 PM (avg: 450 req/hour) - Peak usage
# - Saturday 7:00-11:00 PM (avg: 520 req/hour) - Peak usage
```

**Implementation** (250 lines):
```bash
#!/bin/bash
# scripts/find-optimal-maintenance-window.sh

set -euo pipefail

PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9090}"

# Query Traefik request rate by hour
query_traffic_patterns() {
    local lookback_days=${1:-30}

    # Query: rate of HTTP requests per hour, grouped by hour
    local query='sum by (hour) (
        increase(traefik_service_requests_total[1h])
    )'

    # Execute query for each hour over the lookback period
    local end_time=$(date +%s)
    local start_time=$((end_time - lookback_days * 86400))

    curl -s "${PROMETHEUS_URL}/api/v1/query_range" \
        --data-urlencode "query=${query}" \
        --data-urlencode "start=${start_time}" \
        --data-urlencode "end=${end_time}" \
        --data-urlencode "step=3600" \
        | jq -r '.data.result[] | .values[] | "\(.[0]) \(.[1])"'
}

# Group by hour of day and calculate statistics
calculate_hourly_stats() {
    # Input: timestamp request_count pairs
    # Output: hour avg_requests p95_requests

    awk '
    {
        timestamp = $1
        requests = $2

        # Convert timestamp to hour of day (0-23)
        hour = strftime("%H", timestamp)

        # Accumulate data
        hours[hour] = hours[hour] " " requests
    }
    END {
        for (hour in hours) {
            # Calculate avg and p95
            split(hours[hour], values, " ")
            n = length(values)

            sum = 0
            for (i in values) sum += values[i]
            avg = sum / n

            # Sort for p95
            asort(values)
            p95_idx = int(n * 0.95)
            p95 = values[p95_idx]

            printf "%02d %.1f %.1f\n", hour, avg, p95
        }
    }
    ' | sort -n
}

# Find 2-hour windows with lowest traffic
find_optimal_windows() {
    # Input: hour avg p95
    # Output: sorted 2-hour windows

    while read -r hour avg p95; do
        next_hour=$(printf "%02d" $(( (10#$hour + 1) % 24 )))

        # Calculate 2-hour average
        echo "$hour $avg $p95"
    done | awk '
    {
        hour[NR] = $1
        avg[NR] = $2
        p95[NR] = $3
    }
    END {
        # Calculate 2-hour windows
        for (i = 1; i <= NR; i++) {
            j = (i % NR) + 1
            window_avg = (avg[i] + avg[j]) / 2
            window_p95 = (p95[i] > p95[j]) ? p95[i] : p95[j]

            printf "%s:00-%s:00 %.1f %.1f\n", hour[i], hour[j], window_avg, window_p95
        }
    }
    ' | sort -t' ' -k2 -n | head -5
}

main() {
    echo "Analyzing traffic patterns (30-day history)..."

    local traffic=$(query_traffic_patterns 30)
    local hourly_stats=$(echo "$traffic" | calculate_hourly_stats)
    local optimal_windows=$(echo "$hourly_stats" | find_optimal_windows)

    echo ""
    echo "Recommended Maintenance Windows:"
    echo "$optimal_windows" | nl | awk '{printf "%s. %s (avg: %.0f req/hour)\n", $1, $2, $3}'
}

main "$@"
```

---

## Implementation Phases

### Phase 1: Foundation (3-4 hours)

**Session 5B-1: Core Analysis Engine**

**Objective**: Build reusable trend analysis engine.

**Tasks**:
1. Create `scripts/analyze-trends.sh` (400 lines)
   - Prometheus query helper
   - Linear regression calculator
   - Forecasting logic
   - JSON output formatter

2. Test with existing metrics:
   ```bash
   # Test disk trend
   ./scripts/analyze-trends.sh \
     --metric 'node_filesystem_avail_bytes{mountpoint="/"}' \
     --lookback 7d \
     --forecast 14d

   # Test memory trend
   ./scripts/analyze-trends.sh \
     --metric 'container_memory_usage_bytes{name="jellyfin"}' \
     --lookback 7d \
     --forecast 7d
   ```

3. Validate regression accuracy:
   - Compare predictions against actual data
   - Tune lookback window for optimal R²
   - Document confidence thresholds

**Success Criteria**:
- ✅ analyze-trends.sh executes without errors
- ✅ R² > 0.7 for stable metrics (disk usage)
- ✅ JSON output format matches schema
- ✅ Manual validation: predicted value ≈ actual value (±10%)

**Deliverables**:
- `scripts/analyze-trends.sh` (executable, documented)
- Test results in `docs/99-reports/test-trend-analysis.md`

---

### Phase 2: Resource Exhaustion Prediction (2-3 hours)

**Session 5B-2: Disk & Memory Forecasting**

**Objective**: Predict when resources will be exhausted.

**Tasks**:
1. Create `scripts/predict-resource-exhaustion.sh` (300 lines)
   - Disk exhaustion predictor (/, BTRFS pool)
   - Memory exhaustion predictor (per-service)
   - Severity classification logic
   - Recommendation generator

2. Create predictions cache structure:
   ```bash
   mkdir -p ~/.claude/context
   touch ~/.claude/context/predictions.json
   ```

3. Integrate with homelab-intelligence:
   ```bash
   # Update skill to read predictions
   nano .claude/skills/homelab-intelligence/skill.md
   # Add: Read ~/.claude/context/predictions.json for proactive insights
   ```

4. Schedule automatic updates:
   ```bash
   # Add to crontab (run every 6 hours)
   0 */6 * * * ~/fedora-homelab-containers/scripts/predict-resource-exhaustion.sh --all --output ~/.claude/context/predictions.json
   ```

**Success Criteria**:
- ✅ Correctly predicts disk exhaustion within ±2 days
- ✅ Detects memory leaks (positive trend + high confidence)
- ✅ predictions.json updated automatically
- ✅ homelab-intelligence skill reads predictions

**Deliverables**:
- `scripts/predict-resource-exhaustion.sh`
- `.claude/context/predictions.json` (auto-updated)
- Updated `homelab-intelligence` skill

---

### Phase 3: Service Health Prediction (2-3 hours)

**Session 5B-3: Degradation Detection**

**Objective**: Predict service failures before they happen.

**Tasks**:
1. Create `scripts/predict-service-failure.sh` (350 lines)
   - Response time degradation detector
   - Health check success rate analyzer
   - Restart frequency analyzer
   - Composite health score calculator

2. Define health score formula:
   ```
   Health Score = 100 - (
     response_time_penalty +
     health_check_penalty +
     restart_penalty
   )

   Where:
   - response_time_penalty = min(50, (current - baseline) / baseline * 100)
   - health_check_penalty = (1 - success_rate) * 30
   - restart_penalty = min(20, restart_count_7d * 5)
   ```

3. Add to predictions cache:
   - Append service health predictions to `predictions.json`
   - Include composite health score
   - Flag services with score < 70

**Success Criteria**:
- ✅ Detects response time degradation (>20% increase)
- ✅ Flags services with declining health check rates
- ✅ Composite health score accurately reflects service state
- ✅ Integrated into predictions.json

**Deliverables**:
- `scripts/predict-service-failure.sh`
- Updated predictions cache with health scores

---

### Phase 4: Maintenance Window Optimization (1-2 hours)

**Session 5B-4: Traffic Analysis**

**Objective**: Find optimal times for maintenance based on usage patterns.

**Tasks**:
1. Create `scripts/find-optimal-maintenance-window.sh` (250 lines)
   - Query Traefik request metrics (30-day history)
   - Calculate hourly traffic statistics
   - Identify low-traffic 2-hour windows
   - Account for day-of-week patterns

2. Generate maintenance schedule recommendation:
   ```bash
   ./scripts/find-optimal-maintenance-window.sh > docs/20-operations/guides/maintenance-schedule.md
   ```

3. Add to homelab-intelligence skill:
   - Skill can answer: "When should I schedule maintenance?"
   - Response includes data-driven recommendations

**Success Criteria**:
- ✅ Identifies 3-5 optimal maintenance windows
- ✅ Windows have <20% of peak traffic
- ✅ Recommendations account for day-of-week patterns
- ✅ homelab-intelligence skill provides recommendations

**Deliverables**:
- `scripts/find-optimal-maintenance-window.sh`
- `docs/20-operations/guides/maintenance-schedule.md`

---

### Phase 5: Visualization & Integration (1-2 hours)

**Session 5B-5: Grafana Dashboards**

**Objective**: Display predictions in Grafana for visual monitoring.

**Tasks**:
1. Create Grafana dashboard: "Predictive Analytics"
   - Panel: Disk exhaustion forecast (line graph with prediction overlay)
   - Panel: Memory trends per service
   - Panel: Service health scores (gauge)
   - Panel: Upcoming maintenance recommendations (table)

2. Use Grafana annotations for predictions:
   ```bash
   # Script to push predictions as annotations
   scripts/push-predictions-to-grafana.sh
   ```

3. Alertmanager integration (optional):
   - Create alert: "Predicted disk exhaustion within 7 days"
   - Route to Discord webhook

**Success Criteria**:
- ✅ Grafana dashboard displays all predictions
- ✅ Forecasts visually overlay on historical data
- ✅ Annotations mark predicted events
- ✅ Dashboard accessible at grafana.patriark.org/d/predictive

**Deliverables**:
- Grafana dashboard JSON
- `scripts/push-predictions-to-grafana.sh`
- Updated Alertmanager config (if using alerts)

---

## Integration Points

### 1. Session 4 Context Framework

**Integration**: Predictions stored in `.claude/context/predictions.json`

**Why**: Provides persistent prediction history for Claude skills to reference.

**Usage**:
```bash
# homelab-intelligence skill reads predictions
cat ~/.claude/context/predictions.json | jq '.predictions[] | select(.severity == "critical")'
```

---

### 2. Homelab-Intelligence Skill

**Enhancement**: Add proactive recommendation mode.

**Example Interaction**:
```
User: "What should I be worried about?"

Claude (via homelab-intelligence):
"Based on predictive analysis:
1. 🚨 CRITICAL: Root filesystem will be full in 6 days (Nov 22)
   - Current: 78% used
   - Trend: +2.1% per day
   - Action: Run disk cleanup immediately

2. ⚠️ WARNING: Jellyfin memory growing steadily
   - Current: 1.2GB / 4GB limit
   - Trend: +15MB/hour
   - Action: Schedule restart during 3-5am window

3. ℹ️ INFO: Optimal maintenance window is Tuesday 3-5am
   - Lowest traffic: 12 req/hour (vs 450 req/hour peak)
"
```

**Implementation**:
```markdown
<!-- In .claude/skills/homelab-intelligence/skill.md -->

## Proactive Insights

When answering questions about system health, ALWAYS check predictions:

1. Read ~/.claude/context/predictions.json
2. Filter by severity (critical > warning > info)
3. Present actionable recommendations
4. Include confidence levels and data sources
```

---

### 3. Auto-Remediation Playbooks (Session 4)

**Integration**: Trigger remediation based on predictions.

**Example**: Auto-cleanup when disk exhaustion predicted within 7 days.

```yaml
# .claude/remediation/playbooks/predictive-disk-cleanup.yml
name: Predictive Disk Cleanup
trigger:
  type: prediction
  condition: disk_exhaustion AND days_until_full < 7

steps:
  - name: Run diagnostic
    command: ./scripts/homelab-diagnose.sh --disk-usage

  - name: Execute cleanup
    command: ./scripts/homelab-intel.sh --fix disk_cleanup

  - name: Verify
    command: ./scripts/predict-resource-exhaustion.sh --resource /
    validation: days_until_full > 14
```

---

### 4. Grafana + Prometheus

**Integration**: Visualize predictions alongside real-time metrics.

**Grafana Panel Example** (disk forecast):
```json
{
  "title": "Disk Usage Forecast",
  "targets": [
    {
      "expr": "node_filesystem_avail_bytes{mountpoint=\"/\"}",
      "legendFormat": "Actual Available"
    }
  ],
  "annotations": {
    "list": [
      {
        "name": "Predicted Exhaustion",
        "datasource": "-- Grafana --",
        "enable": true,
        "iconColor": "red",
        "tags": ["prediction", "disk"]
      }
    ]
  }
}
```

---

## Testing Strategy

### Unit Tests

**Test 1: Regression Accuracy**
```bash
# Generate synthetic data with known trend
# Verify slope/intercept calculation

test_regression_accuracy() {
    # y = 2x + 10 (known slope=2, intercept=10)
    echo -e "1 12\n2 14\n3 16\n4 18\n5 20" | calculate_regression
    # Expected: 2.0000 10.0000 1.0000
}
```

**Test 2: Forecast Correctness**
```bash
# Compare 7-day forecast against actual data from 7 days ago
test_forecast_accuracy() {
    # Use data from Nov 1-7 to predict Nov 8
    # Compare prediction to actual Nov 8 value
}
```

**Test 3: Zero Crossing Calculation**
```bash
# Test with known decreasing trend
# Verify days_until_zero matches expected
```

---

### Integration Tests

**Test 1: End-to-End Prediction**
```bash
# Run full prediction pipeline
./scripts/predict-resource-exhaustion.sh --all

# Verify output:
# - predictions.json created
# - Contains disk + memory predictions
# - Severities assigned correctly
# - Recommendations are actionable
```

**Test 2: Skill Integration**
```bash
# Invoke homelab-intelligence skill
# Verify it reads predictions.json
# Verify recommendations are surfaced
```

---

### Validation Tests

**Test 1: Prediction vs Reality** (7-day delay)
```bash
# Store predictions from 7 days ago
# Compare to actual values today
# Calculate prediction error (MAPE)

# Acceptable: Mean Absolute Percentage Error < 15%
```

**Test 2: Confidence Calibration**
```bash
# For predictions with confidence > 0.8:
#   - At least 80% should be accurate within ±10%
# For predictions with confidence < 0.5:
#   - Flag as unreliable, don't recommend action
```

---

## Success Metrics

### Quantitative Metrics

1. **Prediction Accuracy**
   - Target: MAPE < 15% for 7-day forecasts
   - Measure: Weekly validation test

2. **Lead Time**
   - Target: Predict critical issues 7+ days in advance
   - Measure: Days between prediction and actual threshold crossing

3. **False Positive Rate**
   - Target: < 20% (predictions that don't materialize)
   - Measure: Predicted events vs actual events over 30 days

4. **Confidence Calibration**
   - Target: High-confidence (>0.8) predictions are 80%+ accurate
   - Measure: Accuracy rate grouped by confidence buckets

### Qualitative Metrics

1. **Proactive vs Reactive Ratio**
   - Before: 100% reactive (alert after problem)
   - Target: 70% proactive (action before problem)

2. **User Satisfaction**
   - "I was surprised by a disk full error" → Never
   - "I scheduled maintenance at optimal times" → Always

3. **Integration Quality**
   - homelab-intelligence skill provides useful recommendations
   - Predictions appear in Grafana without manual effort

---

## Future Enhancements

### Enhancement 1: Machine Learning Models (Session 6+)

Replace linear regression with more sophisticated models:

**ARIMA (AutoRegressive Integrated Moving Average)**:
- Better for time-series with seasonality
- Handles weekly/monthly patterns in traffic

**LSTM (Long Short-Term Memory)**:
- Deep learning for complex patterns
- Requires TensorFlow/PyTorch (heavier dependency)

**Implementation Path**:
1. Install Python + scipy/statsmodels (lightweight)
2. Rewrite analyze-trends.sh as analyze-trends.py
3. Use ARIMA for disk/memory forecasting
4. Benchmark: Does accuracy improve >10%? If not, stick with linear regression.

---

### Enhancement 2: Anomaly Detection

Detect unusual patterns that don't fit trend models:

**Use Case**: Sudden spike in Authelia auth failures (possible attack)

**Approach**: Z-score anomaly detection
```python
# If current value > mean + 3*stddev → anomaly
```

**Integration**: Add to `predict-service-failure.sh`

---

### Enhancement 3: Capacity Planning

Long-term (6-12 month) forecasts for hardware upgrades:

**Questions to Answer**:
- "When will 128GB system SSD be insufficient?"
- "Should I add more RAM for Jellyfin transcoding?"

**Approach**: Extrapolate trends to 6-12 months, account for growth acceleration

---

### Enhancement 4: Feedback Loop

Improve prediction models based on accuracy:

**Process**:
1. Store predictions in database (SQLite)
2. Compare predictions to actuals weekly
3. Adjust model parameters (lookback window, smoothing)
4. Retrain on historical data

**Goal**: Self-improving prediction engine

---

## Documentation

### Usage Guide

**File**: `docs/40-monitoring-and-documentation/guides/predictive-analytics.md`

**Contents**:
- How predictions work (high-level)
- How to interpret predictions.json
- How to run manual predictions
- How to integrate with Claude skills
- Troubleshooting common issues

**Example Section**:
```markdown
## Interpreting Predictions

Each prediction includes:

- **type**: Category (disk_exhaustion, memory_trend, etc.)
- **severity**: info / warning / critical
- **confidence**: 0.0-1.0 (higher = more reliable)
- **recommendation**: Actionable next step

### Action Thresholds

| Severity | Confidence | Action Required |
|----------|-----------|-----------------|
| critical | >0.7 | Immediate (within 24h) |
| warning | >0.7 | Scheduled (within 7 days) |
| warning | <0.7 | Monitor (may be false positive) |
| info | any | Informational only |

### Example

"disk_exhaustion" + "critical" + confidence 0.89 + 6 days until full
→ **Run disk cleanup within 24 hours**

"memory_trend" + "warning" + confidence 0.55 + 48 hours until OOM
→ **Monitor for another day** (confidence too low for action)
```

---

### ADR (Architecture Decision Record)

**File**: `docs/40-monitoring-and-documentation/decisions/2025-11-16-decision-006-predictive-analytics.md`

**Decision**: Use lightweight linear regression over machine learning for initial implementation.

**Rationale**:
- Bash + awk = no additional dependencies
- Linear trends work well for stable metrics (disk, memory)
- R² provides simple confidence measure
- Can upgrade to ML later if needed

**Trade-offs**:
- Won't handle seasonality well (weekly traffic patterns)
- Less accurate for volatile metrics
- Can't detect non-linear relationships

**Status**: Approved for Session 5B implementation

---

## Appendix: Mathematical Background

### Linear Regression

**Goal**: Fit line `y = mx + b` to data points

**Formulas**:
```
slope (m) = (n·Σxy - Σx·Σy) / (n·Σx² - (Σx)²)
intercept (b) = (Σy - m·Σx) / n

R² = 1 - (SS_res / SS_tot)
where:
  SS_res = Σ(y_actual - y_predicted)²  # Residual sum of squares
  SS_tot = Σ(y_actual - y_mean)²       # Total sum of squares
```

**R² Interpretation**:
- 1.0 = Perfect fit (all points on line)
- 0.8-0.9 = Strong linear relationship
- 0.5-0.8 = Moderate relationship
- <0.5 = Weak/no linear relationship

---

### Confidence Intervals

For predictions, we use R² as a simple confidence proxy:

```
confidence = R²

If R² > 0.8 → High confidence
If R² < 0.5 → Low confidence (don't recommend action)
```

**More sophisticated**: Calculate prediction interval using standard error of regression.

---

## Conclusion

Session 5B delivers a **production-ready predictive analytics engine** that:

✅ Forecasts resource exhaustion 7-14 days in advance
✅ Detects service health degradation before failure
✅ Recommends optimal maintenance windows based on data
✅ Integrates seamlessly with existing monitoring + Claude skills
✅ Uses lightweight, dependency-free implementation

**Timeline**: 8-10 hours across 3-4 sessions
**Prerequisites**: Session 4 (Context Framework), Prometheus/Grafana deployed
**Value**: Shift from reactive firefighting to proactive maintenance

Ready for CLI execution when you are! 🚀
