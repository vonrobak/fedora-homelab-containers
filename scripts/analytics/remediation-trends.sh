#!/usr/bin/env bash
#
# remediation-trends.sh - Analyze remediation trends over time
# Part of Phase 6: Remediation History Analytics
#
# Identifies patterns and trends in remediation execution:
#   - Execution frequency changes (increasing/decreasing)
#   - Success rate trends
#   - Common root causes
#   - Prediction accuracy evolution
#   - Most active playbooks
#
# Usage:
#   remediation-trends.sh --last 30d     # Trends for last 30 days
#   remediation-trends.sh --last 7d      # Trends for last 7 days
#   remediation-trends.sh --compare      # Compare periods

set -euo pipefail

# Configuration
METRICS_HISTORY="$HOME/containers/.claude/remediation/metrics-history.json"
CHAIN_METRICS="$HOME/containers/.claude/remediation/chain-metrics-history.jsonl"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Check if metrics history exists
if [ ! -f "$METRICS_HISTORY" ]; then
    echo -e "${RED}✗ Metrics history not found: $METRICS_HISTORY${NC}"
    exit 1
fi

# Parse time period (e.g., "30d", "7d", "24h")
parse_time_period() {
    local period="$1"

    if [[ $period =~ ^([0-9]+)d$ ]]; then
        local days="${BASH_REMATCH[1]}"
        echo $((days * 24 * 60 * 60))
    elif [[ $period =~ ^([0-9]+)h$ ]]; then
        local hours="${BASH_REMATCH[1]}"
        echo $((hours * 60 * 60))
    else
        echo "Invalid period format: $period" >&2
        exit 1
    fi
}

# Get execution frequency trend
analyze_execution_frequency() {
    local period_seconds="$1"
    local period_label="$2"

    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Execution Frequency Trends${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    local now=$(date +%s)
    local period_start=$((now - period_seconds))
    local half_period=$((period_seconds / 2))
    local first_half_start=$period_start
    local first_half_end=$((period_start + half_period))
    local second_half_start=$first_half_end
    local second_half_end=$now

    # Get unique playbooks
    local playbooks
    playbooks=$(jq -r '[.executions[].playbook] | unique | .[]' "$METRICS_HISTORY" | sort)

    printf "%-30s %15s %15s %15s\n" "Playbook" "First Half" "Second Half" "Trend"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    while IFS= read -r playbook; do
        local first_half_count
        local second_half_count

        first_half_count=$(jq --arg pb "$playbook" \
            --argjson start "$first_half_start" \
            --argjson end "$first_half_end" \
            '[.executions[] | select(.playbook == $pb and .timestamp >= $start and .timestamp < $end)] | length' \
            "$METRICS_HISTORY")

        second_half_count=$(jq --arg pb "$playbook" \
            --argjson start "$second_half_start" \
            --argjson end "$second_half_end" \
            '[.executions[] | select(.playbook == $pb and .timestamp >= $start and .timestamp < $end)] | length' \
            "$METRICS_HISTORY")

        # Calculate trend
        local trend
        local trend_label
        if [ "$first_half_count" -eq 0 ] && [ "$second_half_count" -eq 0 ]; then
            trend_label="No data"
        elif [ "$first_half_count" -eq 0 ]; then
            trend_label="${GREEN}↑ New${NC}"
        elif [ "$second_half_count" -eq 0 ]; then
            trend_label="${RED}↓ Stopped${NC}"
        else
            local change_pct=$(echo "scale=0; (($second_half_count - $first_half_count) * 100) / $first_half_count" | bc)

            if [ "$change_pct" -gt 20 ]; then
                trend_label="${GREEN}↑ +${change_pct}%${NC}"
            elif [ "$change_pct" -lt -20 ]; then
                trend_label="${YELLOW}↓ ${change_pct}%${NC}"
            else
                trend_label="→ Stable"
            fi
        fi

        printf "%-30s %15s %15s %s\n" "$playbook" "$first_half_count" "$second_half_count" "$trend_label"
    done <<< "$playbooks"

    echo ""
}

# Analyze success rate trends
analyze_success_rate_trends() {
    local period_seconds="$1"

    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Success Rate Trends${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    local now=$(date +%s)
    local period_start=$((now - period_seconds))
    local half_period=$((period_seconds / 2))

    local playbooks
    playbooks=$(jq -r '[.executions[].playbook] | unique | .[]' "$METRICS_HISTORY" | sort)

    printf "%-30s %15s %15s %15s\n" "Playbook" "First Half" "Second Half" "Trend"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    while IFS= read -r playbook; do
        # First half success rate
        local first_success
        local first_total
        first_success=$(jq --arg pb "$playbook" \
            --argjson start "$period_start" \
            --argjson end "$((period_start + half_period))" \
            '[.executions[] | select(.playbook == $pb and .timestamp >= $start and .timestamp < $end and .status == "success")] | length' \
            "$METRICS_HISTORY")

        first_total=$(jq --arg pb "$playbook" \
            --argjson start "$period_start" \
            --argjson end "$((period_start + half_period))" \
            '[.executions[] | select(.playbook == $pb and .timestamp >= $start and .timestamp < $end)] | length' \
            "$METRICS_HISTORY")

        # Second half success rate
        local second_success
        local second_total
        second_success=$(jq --arg pb "$playbook" \
            --argjson start "$((period_start + half_period))" \
            --argjson end "$now" \
            '[.executions[] | select(.playbook == $pb and .timestamp >= $start and .timestamp < $end and .status == "success")] | length' \
            "$METRICS_HISTORY")

        second_total=$(jq --arg pb "$playbook" \
            --argjson start "$((period_start + half_period))" \
            --argjson end "$now" \
            '[.executions[] | select(.playbook == $pb and .timestamp >= $start and .timestamp < $end)] | length' \
            "$METRICS_HISTORY")

        if [ "$first_total" -eq 0 ] && [ "$second_total" -eq 0 ]; then
            continue
        fi

        local first_rate=0
        local second_rate=0

        if [ "$first_total" -gt 0 ]; then
            first_rate=$(echo "scale=0; ($first_success * 100) / $first_total" | bc)
        fi

        if [ "$second_total" -gt 0 ]; then
            second_rate=$(echo "scale=0; ($second_success * 100) / $second_total" | bc)
        fi

        # Calculate trend
        local trend_label
        if [ "$first_total" -eq 0 ]; then
            trend_label="${CYAN}New${NC}"
        elif [ "$second_total" -eq 0 ]; then
            trend_label="No recent data"
        else
            local change=$((second_rate - first_rate))

            if [ "$change" -gt 10 ]; then
                trend_label="${GREEN}↑ Improving${NC}"
            elif [ "$change" -lt -10 ]; then
                trend_label="${RED}↓ Degrading${NC}"
            else
                trend_label="→ Stable"
            fi
        fi

        printf "%-30s %14s%% %14s%% %s\n" "$playbook" "$first_rate" "$second_rate" "$trend_label"
    done <<< "$playbooks"

    echo ""
}

# Analyze most common root causes (from self-healing playbook)
analyze_root_causes() {
    local period_seconds="$1"

    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Most Common Root Causes${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    local cutoff=$(($(date +%s) - period_seconds))

    # Extract root causes from history
    local root_causes
    root_causes=$(jq --argjson cutoff "$cutoff" \
        '[.executions[] | select(.playbook == "self-healing-restart" and .timestamp >= $cutoff and .root_cause != "")] | group_by(.root_cause) | map({cause: .[0].root_cause, count: length}) | sort_by(-.count)' \
        "$METRICS_HISTORY")

    local total_incidents
    total_incidents=$(echo "$root_causes" | jq '[.[].count] | add // 0')

    if [ "$total_incidents" -eq 0 ]; then
        echo "  No self-healing incidents recorded in this period."
        echo ""
        return
    fi

    echo "$root_causes" | jq -r '.[] | "\(.cause):\(.count)"' | while IFS=: read -r cause count; do
        local pct=$(echo "scale=0; ($count * 100) / $total_incidents" | bc)
        printf "  %-40s %5s (%s%%)\n" "$cause" "$count" "$pct"
    done

    echo ""
    echo "  Total incidents: $total_incidents"
    echo ""
}

# Analyze most active playbooks
analyze_most_active() {
    local period_seconds="$1"

    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Most Active Playbooks${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    local cutoff=$(($(date +%s) - period_seconds))

    # Get execution counts per playbook
    local playbook_counts
    playbook_counts=$(jq --argjson cutoff "$cutoff" \
        '[.executions[] | select(.timestamp >= $cutoff)] | group_by(.playbook) | map({playbook: .[0].playbook, count: length, success: [.[] | select(.status == "success")] | length}) | sort_by(-.count)' \
        "$METRICS_HISTORY")

    local total_executions
    total_executions=$(echo "$playbook_counts" | jq '[.[].count] | add // 0')

    if [ "$total_executions" -eq 0 ]; then
        echo "  No executions recorded in this period."
        echo ""
        return
    fi

    printf "%-30s %12s %12s %12s\n" "Playbook" "Executions" "Success" "Rate"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    echo "$playbook_counts" | jq -r '.[] | "\(.playbook):\(.count):\(.success)"' | while IFS=: read -r playbook count success; do
        local rate=$(echo "scale=0; ($success * 100) / $count" | bc)
        local pct=$(echo "scale=0; ($count * 100) / $total_executions" | bc)

        printf "%-30s %11s %11s %10s%%\n" "$playbook" "$count ($pct%)" "$success" "$rate"
    done

    echo ""
    echo "  Total executions: $total_executions"
    echo ""
}

# Show comprehensive trend report
show_trend_report() {
    local period="$1"
    local period_seconds=$(parse_time_period "$period")

    echo ""
    echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║         REMEDIATION TREND ANALYSIS - Last $period                 ║${NC}"
    echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    analyze_execution_frequency "$period_seconds" "$period"
    analyze_success_rate_trends "$period_seconds"
    analyze_root_causes "$period_seconds"
    analyze_most_active "$period_seconds"

    echo -e "${CYAN}Key Insights:${NC}"
    echo ""

    # Calculate some insights
    local total_executions
    total_executions=$(jq --argjson cutoff "$(($(date +%s) - period_seconds))" \
        '[.executions[] | select(.timestamp >= $cutoff)] | length' \
        "$METRICS_HISTORY")

    local total_success
    total_success=$(jq --argjson cutoff "$(($(date +%s) - period_seconds))" \
        '[.executions[] | select(.timestamp >= $cutoff and .status == "success")] | length' \
        "$METRICS_HISTORY")

    local overall_rate
    if [ "$total_executions" -gt 0 ]; then
        overall_rate=$(echo "scale=0; ($total_success * 100) / $total_executions" | bc)
    else
        overall_rate=0
    fi

    echo "  • Overall success rate: ${overall_rate}%"
    echo "  • Total remediation actions: $total_executions"

    # Check if success rate is improving
    local half_period=$((period_seconds / 2))
    local now=$(date +%s)

    local first_half_success
    first_half_success=$(jq --argjson start "$((now - period_seconds))" \
        --argjson end "$((now - half_period))" \
        '[.executions[] | select(.timestamp >= $start and .timestamp < $end and .status == "success")] | length' \
        "$METRICS_HISTORY")

    local first_half_total
    first_half_total=$(jq --argjson start "$((now - period_seconds))" \
        --argjson end "$((now - half_period))" \
        '[.executions[] | select(.timestamp >= $start and .timestamp < $end)] | length' \
        "$METRICS_HISTORY")

    local second_half_success
    second_half_success=$(jq --argjson start "$((now - half_period))" \
        --argjson end "$now" \
        '[.executions[] | select(.timestamp >= $start and .timestamp < $end and .status == "success")] | length' \
        "$METRICS_HISTORY")

    local second_half_total
    second_half_total=$(jq --argjson start "$((now - half_period))" \
        --argjson end "$now" \
        '[.executions[] | select(.timestamp >= $start and .timestamp < $end)] | length' \
        "$METRICS_HISTORY")

    if [ "$first_half_total" -gt 0 ] && [ "$second_half_total" -gt 0 ]; then
        local first_rate=$(echo "scale=0; ($first_half_success * 100) / $first_half_total" | bc)
        local second_rate=$(echo "scale=0; ($second_half_success * 100) / $second_half_total" | bc)

        if [ "$second_rate" -gt "$first_rate" ]; then
            echo -e "  • Trend: ${GREEN}↑ Success rate improving${NC} ($first_rate% → $second_rate%)"
        elif [ "$second_rate" -lt "$first_rate" ]; then
            echo -e "  • Trend: ${YELLOW}↓ Success rate declining${NC} ($first_rate% → $second_rate%)"
        else
            echo "  • Trend: → Success rate stable ($first_rate%)"
        fi
    fi

    echo ""
}

# Main execution
main() {
    local period="30d"
    local mode="report"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --last)
                period="$2"
                shift 2
                ;;
            --help)
                cat << EOF
remediation-trends.sh - Analyze remediation trends over time

USAGE:
    remediation-trends.sh --last <period>

OPTIONS:
    --last <period>     Time period (e.g., 30d, 7d, 24h)
    --help              Show this help

EXAMPLES:
    # Trends for last 30 days
    remediation-trends.sh --last 30d

    # Trends for last week
    remediation-trends.sh --last 7d

    # Trends for last 24 hours
    remediation-trends.sh --last 24h
EOF
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    show_trend_report "$period"
}

main "$@"
