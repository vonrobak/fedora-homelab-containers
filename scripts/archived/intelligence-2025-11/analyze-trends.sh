#!/usr/bin/env bash
#
# Homelab Trend Analyzer
# Analyzes multiple snapshots to detect trends, predict issues, and recommend optimizations
#
# Usage: ./analyze-trends.sh [--snapshots N] [--output FILE]
#
# Options:
#   --snapshots N    Analyze last N snapshots (default: all available)
#   --output FILE    Write report to FILE (default: stdout)
#   --json           Output JSON format instead of markdown
#   --verbose        Show detailed analysis
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the snapshot parser library
# shellcheck source=lib/snapshot-parser.sh
source "${SCRIPT_DIR}/lib/snapshot-parser.sh"

# ============================================================================
# Configuration
# ============================================================================

SNAPSHOT_COUNT="${SNAPSHOT_COUNT:-all}"
OUTPUT_FILE="${OUTPUT_FILE:-}"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-markdown}"
VERBOSE="${VERBOSE:-0}"

# Thresholds
DISK_WARNING_THRESHOLD=80
MEMORY_WARNING_THRESHOLD=90
DAYS_WARNING_THRESHOLD=14

# ============================================================================
# Argument Parsing
# ============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --snapshots)
            SNAPSHOT_COUNT="$2"
            shift 2
            ;;
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --json)
            OUTPUT_FORMAT="json"
            shift
            ;;
        --verbose)
            VERBOSE=1
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# ============================================================================
# Data Collection
# ============================================================================

# Get snapshots to analyze
if [[ "$SNAPSHOT_COUNT" == "all" ]]; then
    mapfile -t SNAPSHOTS < <(get_all_snapshots)
else
    mapfile -t SNAPSHOTS < <(get_recent_snapshots "$SNAPSHOT_COUNT")
fi

SNAPSHOT_TOTAL="${#SNAPSHOTS[@]}"

if [[ $SNAPSHOT_TOTAL -lt 2 ]]; then
    echo "Error: Need at least 2 snapshots for trend analysis. Found: $SNAPSHOT_TOTAL" >&2
    exit 1
fi

OLDEST_SNAPSHOT="${SNAPSHOTS[0]}"
LATEST_SNAPSHOT="${SNAPSHOTS[-1]}"

OLDEST_TS=$(get_snapshot_timestamp "$OLDEST_SNAPSHOT")
LATEST_TS=$(get_snapshot_timestamp "$LATEST_SNAPSHOT")
TIMESPAN_SECONDS=$(get_snapshot_age "$OLDEST_SNAPSHOT" "$LATEST_SNAPSHOT")
TIMESPAN_HOURS=$((TIMESPAN_SECONDS / 3600))

# ============================================================================
# Analysis Functions
# ============================================================================

analyze_system_memory() {
    local timeseries=$(build_timeseries extract_system_memory "${SNAPSHOTS[@]}")
    local slope=$(echo "$timeseries" | calculate_slope)
    local mean=$(echo "$timeseries" | calculate_mean)
    local first=$(echo "$timeseries" | get_first_value)
    local last=$(echo "$timeseries" | get_last_value")
    local pct_change=$(calculate_percent_change "$first" "$last")

    # Get total memory
    local total=$(extract_system_memory_total "$LATEST_SNAPSHOT")
    local threshold=$((total * MEMORY_WARNING_THRESHOLD / 100))

    # Predict when we'll hit threshold
    local seconds_to_threshold=$(predict_threshold_time "$last" "$slope" "$threshold")
    local days_to_threshold=$((seconds_to_threshold / 86400))

    # Convert slope to MB/day
    local mb_per_day=$(echo "scale=1; $slope * 86400" | bc -l)

    echo "system_memory|$first|$last|$pct_change|$mean|$mb_per_day|$days_to_threshold"
}

analyze_system_disk() {
    local timeseries=$(build_timeseries extract_system_disk_used "${SNAPSHOTS[@]}")
    local slope=$(echo "$timeseries" | calculate_slope)
    local first=$(echo "$timeseries" | get_first_value)
    local last=$(echo "$timeseries" | get_last_value)
    local pct_change=$(calculate_percent_change "$first" "$last")

    # Get total disk and calculate threshold
    local total=$(jq -r '.storage.system_disk.total_gb' "$LATEST_SNAPSHOT")
    local threshold=$(echo "scale=2; $total * $DISK_WARNING_THRESHOLD / 100" | bc -l)

    # Predict when we'll hit threshold
    local seconds_to_threshold=$(predict_threshold_time "$last" "$slope" "$threshold")
    local days_to_threshold=$((seconds_to_threshold / 86400))

    # Convert slope to MB/day
    local mb_per_day=$(echo "scale=1; $slope * 1024 * 86400" | bc -l)

    echo "system_disk|$first|$last|$pct_change|$mb_per_day|$days_to_threshold|$total|$threshold"
}

analyze_btrfs_pool() {
    local timeseries=$(build_timeseries extract_btrfs_used "${SNAPSHOTS[@]}")
    local slope=$(echo "$timeseries" | calculate_slope)
    local first=$(echo "$timeseries" | get_first_value)
    local last=$(echo "$timeseries" | get_last_value)
    local pct_change=$(calculate_percent_change "$first" "$last")

    # Get total and calculate threshold
    local total=$(jq -r '.storage.btrfs_pool.total_gb' "$LATEST_SNAPSHOT")
    local threshold=$(echo "scale=2; $total * $DISK_WARNING_THRESHOLD / 100" | bc -l)

    # Predict when we'll hit threshold
    local seconds_to_threshold=$(predict_threshold_time "$last" "$slope" "$threshold")
    local days_to_threshold=$((seconds_to_threshold / 86400))

    # Convert slope to GB/day
    local gb_per_day=$(echo "scale=2; $slope * 86400" | bc -l)

    echo "btrfs_pool|$first|$last|$pct_change|$gb_per_day|$days_to_threshold|$total|$threshold"
}

analyze_service_health() {
    local timeseries=$(build_timeseries extract_healthy_count "${SNAPSHOTS[@]}")
    local first=$(echo "$timeseries" | get_first_value)
    local last=$(echo "$timeseries" | get_last_value)
    local min=$(echo "$timeseries" | awk '{print $3}' | sort -n | head -1)

    local unhealthy_timeseries=$(build_timeseries extract_unhealthy_count "${SNAPSHOTS[@]}")
    local max_unhealthy=$(echo "$unhealthy_timeseries" | awk '{print $3}' | sort -n | tail -1)

    echo "service_health|$first|$last|$min|$max_unhealthy"
}

# Analyze individual service memory
analyze_service_memory() {
    local service="$1"

    # Check if service exists in all snapshots
    local exists=$(jq -r ".services.\"$service\" // empty" "$LATEST_SNAPSHOT")
    if [[ -z "$exists" ]]; then
        return
    fi

    # Build timeseries
    local timeseries=""
    for snapshot in "${SNAPSHOTS[@]}"; do
        local timestamp=$(get_snapshot_timestamp "$snapshot")
        local value=$(extract_service_memory "$snapshot" "$service")
        timeseries+="$timestamp $value"$'\n'
    done

    local slope=$(echo "$timeseries" | calculate_slope)
    local mean=$(echo "$timeseries" | calculate_mean)
    local first=$(echo "$timeseries" | get_first_value)
    local last=$(echo "$timeseries" | get_last_value)

    # Only report if meaningful data
    if [[ "$last" == "0" || "$last" == "null" ]]; then
        return
    fi

    local mb_per_day=$(echo "scale=1; $slope * 86400" | bc -l)
    local pct_change=$(calculate_percent_change "$first" "$last")

    echo "$service|$first|$last|$mean|$mb_per_day|$pct_change"
}

# ============================================================================
# Report Generation
# ============================================================================

generate_markdown_report() {
    cat <<EOF
# Homelab Intelligence Report

**Generated:** $(date '+%Y-%m-%d %H:%M:%S')
**Analysis Period:** $OLDEST_TS to $LATEST_TS
**Snapshots Analyzed:** $SNAPSHOT_TOTAL
**Time Span:** ${TIMESPAN_HOURS} hours

---

## 📊 Executive Summary

EOF

    # Analyze data
    local sys_mem=$(analyze_system_memory)
    local sys_disk=$(analyze_system_disk)
    local btrfs=$(analyze_btrfs_pool)
    local health=$(analyze_service_health)

    # Parse results
    IFS='|' read -r _ mem_first mem_last mem_pct mem_mean mem_rate mem_days <<< "$sys_mem"
    IFS='|' read -r _ disk_first disk_last disk_pct disk_rate disk_days disk_total disk_threshold <<< "$sys_disk"
    IFS='|' read -r _ btrfs_first btrfs_last btrfs_pct btrfs_rate btrfs_days btrfs_total btrfs_threshold <<< "$btrfs"
    IFS='|' read -r _ health_first health_last health_min health_max_unhealthy <<< "$health"

    # Determine criticality
    local has_critical=0
    local has_warnings=0

    # Check for critical issues
    if [[ "$disk_days" != "-1" && "$disk_days" -lt "$DAYS_WARNING_THRESHOLD" ]]; then
        has_critical=1
    fi

    if [[ "$health_max_unhealthy" -gt "0" ]]; then
        has_warnings=1
    fi

    # Print summary
    if [[ $has_critical -eq 1 ]]; then
        echo "🔴 **Status:** Critical - Action Required"
        echo ""
    elif [[ $has_warnings -eq 1 ]]; then
        echo "🟡 **Status:** Warnings Detected"
        echo ""
    else
        echo "✅ **Status:** Healthy - All Systems Normal"
        echo ""
    fi

    # Critical Warnings Section
    if [[ "$has_critical" -eq 1 ]] || [[ "$has_warnings" -eq 1 ]]; then
        echo "## Critical Warnings - Action Required"
        echo ""

        if [[ "$disk_days" != "-1" && "$disk_days" -lt "$DAYS_WARNING_THRESHOLD" ]]; then
            echo "- **System SSD** will reach ${DISK_WARNING_THRESHOLD}% in **${disk_days} days** at current growth rate"
            echo "  - Current: ${disk_last}GB / ${disk_total}GB"
            echo "  - Growth rate: ${disk_rate}MB/day"
            echo "  - **Action:** Review log retention, clear temporary files, or expand storage"
            echo ""
        fi

        if [[ "$health_max_unhealthy" -gt "0" ]]; then
            echo "- **Service Health Issues:** Detected ${health_max_unhealthy} unhealthy services during analysis period"
            echo "  - **Action:** Review service logs, check for restart loops"
            echo ""
        fi
    fi

    # Capacity Predictions
    echo "## 🔮 Capacity Predictions"
    echo ""

    echo "### System SSD"
    local disk_percent=$(echo "scale=1; $disk_last / $disk_total * 100" | bc)
    printf -- "- **Current Usage:** %sGB / %sGB [%s%%]\n" "$disk_last" "$disk_total" "$disk_percent"
    printf -- "- **Growth Rate:** %sMB/day\n" "$disk_rate"
    if [[ "$disk_days" != "-1" ]]; then
        printf -- "- **Prediction:** Will reach %s%% [%sGB] in **%s days**\n" "$DISK_WARNING_THRESHOLD" "$disk_threshold" "$disk_days"
    else
        echo "- **Prediction:** Stable or shrinking - no growth detected"
    fi
    echo ""

    echo "### BTRFS Pool"
    local btrfs_percent=$(echo "scale=1; $btrfs_last / $btrfs_total * 100" | bc)
    printf -- "- **Current Usage:** %sGB / %sGB [%s%%]\n" "$btrfs_last" "$btrfs_total" "$btrfs_percent"
    printf -- "- **Growth Rate:** %sGB/day\n" "$btrfs_rate"
    if [[ "$btrfs_days" != "-1" ]]; then
        printf -- "- **Prediction:** Will reach %s%% [%sGB] in **%s days**\n" "$DISK_WARNING_THRESHOLD" "$btrfs_threshold" "$btrfs_days"
    else
        echo "- **Prediction:** Stable - no significant growth"
    fi
    echo ""

    echo "### System Memory"
    local mem_total=$(extract_system_memory_total "$LATEST_SNAPSHOT")
    printf -- "- **Current Usage:** %sMB / %sMB\n" "$mem_last" "$mem_total"
    printf -- "- **Average:** %sMB\n" "$mem_mean"
    printf -- "- **Trend:** %sMB/day [%s%% change over period]\n" "$mem_rate" "$mem_pct"
    if [[ "$mem_days" != "-1" && "$mem_days" -lt "30" ]]; then
        printf -- "- **Warning:** Memory trending up significantly - will reach %s%% in %s days\n" "$MEMORY_WARNING_THRESHOLD" "$mem_days"
    else
        echo "- **Status:** Healthy memory usage pattern"
    fi
    echo ""

    # Service Health Trends
    echo "## Service Health Trends"
    echo ""
    printf -- "- **Services with Health Checks:** %s\n" "$health_last"
    printf -- "- **Minimum Healthy:** %s during analysis period\n" "$health_min"
    printf -- "- **Maximum Unhealthy:** %s\n" "$health_max_unhealthy"
    echo ""

    if [[ "$health_first" == "$health_last" && "$health_max_unhealthy" == "0" ]]; then
        echo "**All services remained healthy throughout the analysis period**"
    elif [[ "$health_max_unhealthy" -gt "0" ]]; then
        echo "**Health fluctuations detected** - review service stability"
    fi
    echo ""

    # Per-Service Memory Analysis
    echo "## 💾 Per-Service Memory Analysis"
    echo ""

    # Get list of services from latest snapshot
    local services=$(get_service_names "$LATEST_SNAPSHOT")

    echo "| Service | Start | Current | Avg | Trend | Change |"
    echo "|---------|-------|---------|-----|-------|--------|"

    while IFS= read -r service; do
        local analysis=$(analyze_service_memory "$service")
        if [[ -n "$analysis" ]]; then
            IFS='|' read -r svc svc_first svc_last svc_mean svc_rate svc_pct <<< "$analysis"

            # Format trend indicator
            local trend_indicator=""
            if (( $(echo "$svc_rate > 1" | bc -l) )); then
                trend_indicator="📈 ↑"
            elif (( $(echo "$svc_rate < -1" | bc -l) )); then
                trend_indicator="📉 ↓"
            else
                trend_indicator="➡️ →"
            fi

            printf "| %-20s | %5.0fMB | %5.0fMB | %5.0fMB | %s %+.1fMB/d | %+.1f%% |\n" \
                "$svc" "$svc_first" "$svc_last" "$svc_mean" "$trend_indicator" "$svc_rate" "$svc_pct"
        fi
    done <<< "$services"

    echo ""

    # Optimization Opportunities
    echo "## 💡 Optimization Opportunities"
    echo ""

    local found_optimizations=0

    # Check for services with allocated memory much higher than usage
    while IFS= read -r service; do
        local mem_usage=$(extract_service_memory "$LATEST_SNAPSHOT" "$service")
        local mem_max=$(jq -r ".quadlet_configs.\"$service\".memory_max // empty" "$LATEST_SNAPSHOT" | sed 's/[^0-9]//g')

        if [[ -n "$mem_max" && "$mem_usage" -gt "0" ]]; then
            # Convert MemoryMax to MB (assuming M or G suffix)
            local mem_max_str=$(jq -r ".quadlet_configs.\"$service\".memory_max" "$LATEST_SNAPSHOT")
            if [[ "$mem_max_str" =~ ([0-9]+)G ]]; then
                mem_max=$((${BASH_REMATCH[1]} * 1024))
            elif [[ "$mem_max_str" =~ ([0-9]+)M ]]; then
                mem_max=${BASH_REMATCH[1]}
            fi

            # Check if usage is less than 50% of allocated
            local usage_pct=$(echo "scale=0; $mem_usage / $mem_max * 100" | bc)
            if [[ "$usage_pct" -lt "50" && "$mem_max" -gt "256" ]]; then
                local savings=$((mem_max - mem_usage - 100))
                printf -- "- **%s**: MemoryMax=%s, current usage %sMB [%s%%]\n" "$service" "$mem_max_str" "$mem_usage" "$usage_pct"
                printf -- "  - Consider reducing MemoryMax to save ~%sMB\n" "$savings"
                found_optimizations=1
            fi
        fi
    done <<< "$services"

    if [[ $found_optimizations -eq 0 ]]; then
        echo "✅ **No obvious resource over-allocation detected**"
        echo ""
        echo "All services appear to be using resources efficiently relative to their limits."
    fi

    echo ""

    # Footer
    echo "---"
    echo ""
    echo "**Intelligence Engine:** homelab-snapshot.sh + analyze-trends.sh"

    # Calculate confidence level
    local confidence_level
    if [[ $SNAPSHOT_TOTAL -gt 10 ]]; then
        confidence_level="High - ${SNAPSHOT_TOTAL} snapshots"
    elif [[ $SNAPSHOT_TOTAL -gt 5 ]]; then
        confidence_level="Medium - ${SNAPSHOT_TOTAL} snapshots"
    else
        confidence_level="Low - ${SNAPSHOT_TOTAL} snapshots"
    fi
    printf -- "**Confidence Level:** %s\n" "$confidence_level"
    echo "**Next Analysis:** Run daily or after significant changes"
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "JSON output not yet implemented" >&2
        exit 1
    fi

    if [[ -n "$OUTPUT_FILE" ]]; then
        generate_markdown_report > "$OUTPUT_FILE"
        echo "Report written to: $OUTPUT_FILE" >&2
    else
        generate_markdown_report
    fi
}

main "$@"
