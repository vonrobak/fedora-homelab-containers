#!/bin/bash
# predict-resource-exhaustion.sh
# Predict disk and memory exhaustion based on historical trends
#
# Purpose:
#   - Analyze disk usage trends (root /, BTRFS pool)
#   - Analyze memory usage trends per service
#   - Predict when resources will be exhausted
#   - Generate actionable recommendations
#
# Usage:
#   ./predict-resource-exhaustion.sh --type disk --output json
#   ./predict-resource-exhaustion.sh --type memory --service jellyfin

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANALYZE_TRENDS="${SCRIPT_DIR}/analyze-trends.sh"

# Configuration
TYPE="all"  # disk, memory, or all
SERVICE=""
OUTPUT_FORMAT="human"
LOOKBACK="7d"
DISK_WARN_THRESHOLD=90  # % used
MEMORY_WARN_THRESHOLD_MB=31000  # Near total system memory

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    cat <<EOF
Usage: $0 [options]

Predict resource exhaustion based on historical trends.

Options:
  --type <type>          Resource type: disk, memory, all (default: all)
  --service <name>       Specific service to analyze (for memory)
  --output <format>      Output format: human, json (default: human)
  --lookback <duration>  Historical window (default: 7d)
  --help                 Show this help

Examples:
  # Analyze all resources
  $0

  # Analyze only disk usage
  $0 --type disk

  # Analyze memory for specific service
  $0 --type memory --service jellyfin

  # JSON output for integration
  $0 --type all --output json
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

# Analyze disk usage trend
analyze_disk() {
    log INFO "Analyzing disk usage trends..."

    # Query node_filesystem_avail_bytes for root filesystem
    local trend_json=$("$ANALYZE_TRENDS" \
        --metric 'node_filesystem_avail_bytes{mountpoint="/"}' \
        --lookback "$LOOKBACK" \
        --forecast 14d \
        --output json 2>/dev/null)

    if [[ -z "$trend_json" ]]; then
        log WARNING "Could not analyze root filesystem trend"
        return 1
    fi

    # Parse trend data
    local current=$(echo "$trend_json" | python3 -c "import json, sys; print(json.load(sys.stdin)['values']['current'])")
    local forecast_7d=$(echo "$trend_json" | python3 -c "import json, sys; print(json.load(sys.stdin)['values']['forecast_7d'])")
    local slope=$(echo "$trend_json" | python3 -c "import json, sys; print(json.load(sys.stdin)['analysis']['slope'])")
    local r_squared=$(echo "$trend_json" | python3 -c "import json, sys; print(json.load(sys.stdin)['analysis']['r_squared'])")

    # Get total filesystem size
    local total_bytes=$(podman exec prometheus wget -q -O- \
        'http://localhost:9090/api/v1/query?query=node_filesystem_size_bytes{mountpoint="/"}' \
        | python3 -c "import json, sys; d=json.load(sys.stdin); print(d['data']['result'][0]['value'][1])" 2>/dev/null || echo "0")

    # Calculate usage percentages
    local current_pct=$(awk "BEGIN {printf \"%.1f\", (1 - $current / $total_bytes) * 100}")
    local forecast_7d_pct=$(awk "BEGIN {printf \"%.1f\", (1 - $forecast_7d / $total_bytes) * 100}")

    # Calculate bytes per day
    local bytes_per_day=$(awk "BEGIN {printf \"%.0f\", $slope * 86400}")
    local gb_per_day=$(awk "BEGIN {printf \"%.2f\", $bytes_per_day / 1073741824}")

    # Calculate days until threshold
    local warn_bytes=$(awk "BEGIN {printf \"%.0f\", $total_bytes * (1 - $DISK_WARN_THRESHOLD / 100)}")
    local days_until_warn=$(awk "BEGIN {
        if ($slope >= 0) {
            print \"never\"
        } else {
            days = int(($current - $warn_bytes) / ($slope * 86400 * -1))
            if (days < 0) print \"now\"
            else print days
        }
    }")

    # Determine severity
    local severity="info"
    if [[ "$days_until_warn" != "never" && "$days_until_warn" != "now" ]]; then
        if (( days_until_warn < 7 )); then
            severity="critical"
        elif (( days_until_warn < 14 )); then
            severity="warning"
        fi
    elif [[ "$days_until_warn" == "now" ]]; then
        severity="critical"
    fi

    # Output
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        cat <<EOF
{
  "resource": "disk",
  "mountpoint": "/",
  "current_usage_pct": $current_pct,
  "forecast_7d_pct": $forecast_7d_pct,
  "trend_gb_per_day": $gb_per_day,
  "days_until_${DISK_WARN_THRESHOLD}pct": "$days_until_warn",
  "confidence": $r_squared,
  "severity": "$severity",
  "recommendation": "$(get_disk_recommendation "$days_until_warn" "$gb_per_day")"
}
EOF
    else
        echo ""
        echo "=========================================="
        echo "Disk Usage Prediction (Root /)"
        echo "=========================================="
        echo ""
        echo "Current usage: ${current_pct}%"
        echo "Forecast (+7d): ${forecast_7d_pct}%"
        echo "Trend: ${gb_per_day} GB/day"
        echo "Confidence: $r_squared"
        echo ""
        echo "Days until ${DISK_WARN_THRESHOLD}%: $days_until_warn"
        echo "Severity: $(echo $severity | tr '[:lower:]' '[:upper:]')"
        echo ""
        echo "Recommendation:"
        echo "  $(get_disk_recommendation "$days_until_warn" "$gb_per_day")"
        echo "=========================================="
        echo ""
    fi
}

# Get disk recommendation
get_disk_recommendation() {
    local days=$1
    local gb_per_day=$2

    if [[ "$days" == "now" ]]; then
        echo "URGENT: Disk space critical. Run cleanup immediately."
    elif [[ "$days" == "never" ]]; then
        echo "No action needed. Disk usage is stable or decreasing."
    elif (( days < 3 )); then
        echo "URGENT: Schedule disk cleanup within 24 hours."
    elif (( days < 7 )); then
        echo "Schedule disk cleanup within next few days."
    elif (( days < 14 )); then
        echo "Plan disk cleanup within next week."
    else
        echo "Monitor disk usage. Cleanup can be scheduled during regular maintenance."
    fi
}

# Analyze memory usage trend for a service
analyze_service_memory() {
    local service_name=$1

    log INFO "Analyzing memory usage for: $service_name"

    # Query container memory usage (cAdvisor uses cgroup path as id)
    # Pattern: /user.slice/user-1000.slice/user@1000.service/app.slice/SERVICE.service
    local trend_json=$("$ANALYZE_TRENDS" --metric "container_memory_usage_bytes{id=\"/user.slice/user-1000.slice/user@1000.service/app.slice/$service_name.service\"}" --lookback "$LOOKBACK" --forecast 14d --output json 2>/dev/null)

    if [[ -z "$trend_json" ]]; then
        log WARNING "Could not analyze memory trend for $service_name"
        return 1
    fi

    # Parse trend data
    local current=$(echo "$trend_json" | python3 -c "import json, sys; print(json.load(sys.stdin)['values']['current'])")
    local forecast_7d=$(echo "$trend_json" | python3 -c "import json, sys; print(json.load(sys.stdin)['values']['forecast_7d'])")
    local slope=$(echo "$trend_json" | python3 -c "import json, sys; print(json.load(sys.stdin)['analysis']['slope'])")
    local r_squared=$(echo "$trend_json" | python3 -c "import json, sys; print(json.load(sys.stdin)['analysis']['r_squared'])")

    # Convert to MB
    local current_mb=$(awk "BEGIN {printf \"%.0f\", $current / 1048576}")
    local forecast_7d_mb=$(awk "BEGIN {printf \"%.0f\", $forecast_7d / 1048576}")
    local mb_per_hour=$(awk "BEGIN {printf \"%.2f\", $slope * 3600 / 1048576}")

    # Determine if this is a memory leak (consistent growth)
    local is_leak="false"
    if (( $(awk "BEGIN {print ($slope > 0 && $r_squared > 0.7)}") )); then
        is_leak="true"
    fi

    # Calculate hours until 4GB (typical container limit)
    local hours_until_4gb="never"
    if [[ "$is_leak" == "true" ]]; then
        local limit_bytes=$((4 * 1024 * 1024 * 1024))
        hours_until_4gb=$(awk "BEGIN {
            hours = int(($limit_bytes - $current) / ($slope * 3600))
            if (hours < 0) print \"now\"
            else print hours
        }")
    fi

    # Determine severity
    local severity="info"
    if [[ "$is_leak" == "true" ]]; then
        if [[ "$hours_until_4gb" != "never" && "$hours_until_4gb" != "now" ]]; then
            if (( hours_until_4gb < 24 )); then
                severity="critical"
            elif (( hours_until_4gb < 72 )); then
                severity="warning"
            fi
        elif [[ "$hours_until_4gb" == "now" ]]; then
            severity="critical"
        fi
    fi

    # Output
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        cat <<EOF
{
  "resource": "memory",
  "service": "$service_name",
  "current_mb": $current_mb,
  "forecast_7d_mb": $forecast_7d_mb,
  "trend_mb_per_hour": $mb_per_hour,
  "is_memory_leak": $is_leak,
  "hours_until_4gb": "$hours_until_4gb",
  "confidence": $r_squared,
  "severity": "$severity",
  "recommendation": "$(get_memory_recommendation "$is_leak" "$hours_until_4gb")"
}
EOF
    else
        echo ""
        echo "=========================================="
        echo "Memory Usage Prediction: $service_name"
        echo "=========================================="
        echo ""
        echo "Current usage: ${current_mb} MB"
        echo "Forecast (+7d): ${forecast_7d_mb} MB"
        echo "Trend: ${mb_per_hour} MB/hour"
        echo "Confidence: $r_squared"
        echo ""
        echo "Memory leak detected: $is_leak"
        if [[ "$is_leak" == "true" ]]; then
            echo "Hours until 4GB: $hours_until_4gb"
        fi
        echo "Severity: $(echo $severity | tr '[:lower:]' '[:upper:]')"
        echo ""
        echo "Recommendation:"
        echo "  $(get_memory_recommendation "$is_leak" "$hours_until_4gb")"
        echo "=========================================="
        echo ""
    fi
}

# Get memory recommendation
get_memory_recommendation() {
    local is_leak=$1
    local hours=$2

    if [[ "$is_leak" == "false" ]]; then
        echo "No action needed. Memory usage is stable."
    elif [[ "$hours" == "now" ]]; then
        echo "URGENT: Restart service immediately to prevent OOM."
    elif (( hours < 12 )); then
        echo "URGENT: Schedule service restart within next few hours."
    elif (( hours < 48 )); then
        echo "Schedule service restart during low-traffic window (e.g., 3-5am)."
    else
        echo "Monitor memory usage. Consider restart during next maintenance window."
    fi
}

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --type)
                TYPE="$2"
                shift 2
                ;;
            --service)
                SERVICE="$2"
                shift 2
                ;;
            --output)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --lookback)
                LOOKBACK="$2"
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

    # Execute based on type
    case $TYPE in
        disk)
            analyze_disk
            ;;
        memory)
            if [[ -z "$SERVICE" ]]; then
                echo "Error: --service is required for memory analysis"
                exit 1
            fi
            analyze_service_memory "$SERVICE"
            ;;
        all)
            analyze_disk
            # Could add: analyze top memory-consuming services here
            ;;
        *)
            echo "Error: Invalid type: $TYPE"
            usage
            exit 1
            ;;
    esac
}

main "$@"
