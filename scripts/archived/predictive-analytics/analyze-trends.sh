#!/bin/bash
# analyze-trends.sh
# Time-series trend analysis engine for Prometheus metrics
#
# Purpose:
#   - Query Prometheus for historical data
#   - Calculate linear regression (slope, intercept, R²)
#   - Extrapolate future values with forecasts
#   - Detect trend changes and anomalies
#
# Usage:
#   ./analyze-trends.sh \
#     --metric 'node_filesystem_avail_bytes{mountpoint="/"}' \
#     --lookback 7d \
#     --forecast 14d \
#     --output json

set -euo pipefail

# Configuration
PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9090}"
PROMETHEUS_CONTAINER="${PROMETHEUS_CONTAINER:-prometheus}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
METRIC=""
LOOKBACK="7d"
FORECAST="14d"
OUTPUT_FORMAT="human"
USE_CONTAINER=true  # Query Prometheus from inside container by default

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    cat <<EOF
Usage: $0 --metric <query> [options]

Analyze time-series trends from Prometheus metrics.

Required:
  --metric <query>         Prometheus metric query (e.g., 'up', 'node_filesystem_avail_bytes')

Options:
  --lookback <duration>    Historical window (default: 7d)
  --forecast <duration>    Forecast window (default: 14d)
  --output <format>        Output format: human, json (default: human)
  --help                   Show this help

Examples:
  # Analyze disk usage trend
  $0 --metric 'node_filesystem_avail_bytes{mountpoint="/"}' --lookback 7d --forecast 14d

  # Analyze memory growth
  $0 --metric 'container_memory_usage_bytes{name="jellyfin"}' --lookback 14d --output json

  # Analyze response time degradation
  $0 --metric 'probe_duration_seconds{job="traefik"}' --lookback 30d
EOF
}

log() {
    local level=$1
    shift
    local message="$*"

    # Always output to stderr to avoid interfering with JSON output
    case $level in
        ERROR)   echo -e "${RED}[ERROR]${NC} $message" >&2 ;;
        SUCCESS) echo -e "${GREEN}[SUCCESS]${NC} $message" >&2 ;;
        WARNING) echo -e "${YELLOW}[WARNING]${NC} $message" >&2 ;;
        INFO)    echo -e "${BLUE}[INFO]${NC} $message" >&2 ;;
    esac
}

# Parse duration string to seconds
parse_duration() {
    local duration=$1

    case $duration in
        *d) echo $((${duration%d} * 86400)) ;;
        *h) echo $((${duration%h} * 3600)) ;;
        *m) echo $((${duration%m} * 60)) ;;
        *s) echo ${duration%s} ;;
        *)  echo "$duration" ;;  # Assume already in seconds
    esac
}

# Query Prometheus (from inside container)
query_prometheus() {
    local metric=$1
    local lookback=$2

    local end_time=$(date +%s)
    local start_time=$((end_time - $(parse_duration "$lookback")))
    local step=3600  # 1-hour resolution

    log INFO "Querying Prometheus: $metric (lookback: $lookback)"

    # Create a temporary file for the result
    local tmpfile="/tmp/prometheus-query-$$.json"

    # Use Python to query and extract data in one go
    python3 <<EOF
import urllib.parse
import json
import subprocess
import sys

metric = '''$metric'''
start_time = $start_time
end_time = $end_time
step = $step

# URL-encode the metric
encoded_metric = urllib.parse.quote(metric)

# Build query URL
query_url = f"http://localhost:9090/api/v1/query_range?query={encoded_metric}&start={start_time}&end={end_time}&step={step}"

try:
    # Query Prometheus from inside container
    result = subprocess.run(
        ['podman', 'exec', '$PROMETHEUS_CONTAINER', 'wget', '-q', '-O-', query_url],
        capture_output=True,
        text=True,
        check=True
    )

    # Parse JSON response
    data = json.loads(result.stdout)

    if data['status'] != 'success':
        print("ERROR: Query failed", file=sys.stderr)
        sys.exit(1)

    results = data['data']['result']
    if not results:
        print("ERROR: No data in result", file=sys.stderr)
        sys.exit(1)

    # Take first result series and print timestamp-value pairs
    values = results[0]['values']
    for timestamp, value in values:
        print(f"{timestamp}\\t{value}")

except subprocess.CalledProcessError as e:
    print(f"ERROR: Failed to query Prometheus: {e}", file=sys.stderr)
    sys.exit(1)
except json.JSONDecodeError as e:
    print(f"ERROR: Failed to parse JSON: {e}", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
EOF
}

# Calculate linear regression using awk
calculate_regression() {
    # Input: timestamp value pairs (tab-separated)
    # Output: slope intercept r_squared data_points

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
        if (n < 2) {
            print "ERROR: Not enough data points" > "/dev/stderr"
            exit 1
        }

        # Calculate slope and intercept
        denom = n * sum_xx - sum_x * sum_x
        if (denom == 0) {
            slope = 0
            intercept = sum_y / n
        } else {
            slope = (n * sum_xy - sum_x * sum_y) / denom
            intercept = (sum_y - slope * sum_x) / n
        }

        # Calculate R² (coefficient of determination)
        mean_y = sum_y / n
        ss_tot = 0
        ss_res = 0

        # We need to recalculate from stored values
        # Simplified R²: Use variance approach
        var_y = (sum_yy - sum_y * sum_y / n) / n
        if (var_y == 0) {
            r_squared = 0
        } else {
            # Approximate R² using correlation
            var_x = (sum_xx - sum_x * sum_x / n) / n
            if (var_x == 0) {
                r_squared = 0
            } else {
                cov_xy = (sum_xy - sum_x * sum_y / n) / n
                corr = cov_xy / sqrt(var_x * var_y)
                r_squared = corr * corr
            }
        }

        printf "%.10f %.10f %.4f %d\n", slope, intercept, r_squared, n
    }
    '
}

# Forecast future values
forecast_value() {
    local slope=$1
    local intercept=$2
    local current_time=$3
    local days_ahead=$4

    local future_time=$((current_time + days_ahead * 86400))
    awk "BEGIN {printf \"%.2f\", $slope * $future_time + $intercept}"
}

# Calculate when value will hit threshold (for disk exhaustion, etc.)
calculate_threshold_crossing() {
    local slope=$1
    local intercept=$2
    local threshold=$3
    local current_time=$4

    # Solve: threshold = slope * t + intercept
    # t = (threshold - intercept) / slope

    if (( $(awk "BEGIN {print ($slope == 0)}") )); then
        echo "never"  # No trend
        return
    fi

    local crossing_time=$(awk "BEGIN {print ($threshold - $intercept) / $slope}")
    local days_until=$(awk "BEGIN {print int(($crossing_time - $current_time) / 86400)}")

    if (( $(awk "BEGIN {print ($days_until < 0)}") )); then
        echo "already_crossed"
    else
        echo "$days_until"
    fi
}

# Human-readable output
output_human() {
    local metric=$1
    local slope=$2
    local intercept=$3
    local r_squared=$4
    local data_points=$5
    local current_value=$6
    local forecast_7d=$7
    local forecast_14d=$8

    echo ""
    echo "=========================================="
    echo "Trend Analysis Results"
    echo "=========================================="
    echo ""
    echo "Metric: $metric"
    echo "Data points: $data_points"
    echo "R² (fit quality): $r_squared"
    echo ""
    echo "Current value: $current_value"
    echo "Forecast (+7 days): $forecast_7d"
    echo "Forecast (+14 days): $forecast_14d"
    echo ""
    echo "Trend slope: $slope per second"
    echo ""

    # Determine trend direction
    if (( $(awk "BEGIN {print ($slope > 0)}") )); then
        echo "Trend: ↗ INCREASING"
    elif (( $(awk "BEGIN {print ($slope < 0)}") )); then
        echo "Trend: ↘ DECREASING"
    else
        echo "Trend: → STABLE"
    fi

    # Confidence assessment
    if (( $(awk "BEGIN {print ($r_squared >= 0.8)}") )); then
        echo "Confidence: HIGH (R² >= 0.8)"
    elif (( $(awk "BEGIN {print ($r_squared >= 0.5)}") )); then
        echo "Confidence: MEDIUM (R² >= 0.5)"
    else
        echo "Confidence: LOW (R² < 0.5)"
    fi

    echo "=========================================="
    echo ""
}

# JSON output
output_json() {
    local metric=$1
    local slope=$2
    local intercept=$3
    local r_squared=$4
    local data_points=$5
    local current_value=$6
    local forecast_7d=$7
    local forecast_14d=$8

    # Escape metric string for JSON (replace " with \")
    local escaped_metric=$(echo "$metric" | sed 's/"/\\"/g')

    cat <<EOF
{
  "metric": "$escaped_metric",
  "analysis": {
    "data_points": $data_points,
    "r_squared": $r_squared,
    "slope": $slope,
    "intercept": $intercept
  },
  "values": {
    "current": $current_value,
    "forecast_7d": $forecast_7d,
    "forecast_14d": $forecast_14d
  },
  "trend": {
    "direction": "$(awk "BEGIN {if ($slope > 0) print \"increasing\"; else if ($slope < 0) print \"decreasing\"; else print \"stable\"}")",
    "confidence": "$(awk "BEGIN {if ($r_squared >= 0.8) print \"high\"; else if ($r_squared >= 0.5) print \"medium\"; else print \"low\"}")"
  },
  "generated_at": "$(date -Iseconds)"
}
EOF
}

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --metric)
                METRIC="$2"
                shift 2
                ;;
            --lookback)
                LOOKBACK="$2"
                shift 2
                ;;
            --forecast)
                FORECAST="$2"
                shift 2
                ;;
            --output)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    if [[ -z "$METRIC" ]]; then
        echo "Error: --metric is required"
        usage
        exit 1
    fi

    # Query Prometheus
    local data=$(query_prometheus "$METRIC" "$LOOKBACK")

    if [[ -z "$data" ]]; then
        log ERROR "Failed to query Prometheus"
        exit 1
    fi

    local line_count=$(echo "$data" | wc -l)
    if [[ $line_count -lt 2 ]]; then
        log ERROR "Not enough data points (need at least 2, got $line_count)"
        exit 1
    fi

    log INFO "Received $line_count data points"

    # Calculate regression
    local regression=$(echo "$data" | calculate_regression)
    local slope=$(echo "$regression" | awk '{print $1}')
    local intercept=$(echo "$regression" | awk '{print $2}')
    local r_squared=$(echo "$regression" | awk '{print $3}')
    local data_points=$(echo "$regression" | awk '{print $4}')

    # Get current time and value
    local current_time=$(date +%s)
    local current_value=$(forecast_value "$slope" "$intercept" "$current_time" 0)

    # Forecast future values
    local forecast_7d=$(forecast_value "$slope" "$intercept" "$current_time" 7)
    local forecast_14d=$(forecast_value "$slope" "$intercept" "$current_time" 14)

    # Output results
    case $OUTPUT_FORMAT in
        json)
            output_json "$METRIC" "$slope" "$intercept" "$r_squared" "$data_points" \
                       "$current_value" "$forecast_7d" "$forecast_14d"
            ;;
        *)
            output_human "$METRIC" "$slope" "$intercept" "$r_squared" "$data_points" \
                        "$current_value" "$forecast_7d" "$forecast_14d"
            ;;
    esac
}

main "$@"
