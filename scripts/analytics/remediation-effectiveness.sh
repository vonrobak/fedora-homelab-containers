#!/usr/bin/env bash
#
# remediation-effectiveness.sh - Calculate playbook effectiveness scores
# Part of Phase 6: Remediation History Analytics
#
# Calculates a 0-100 effectiveness score for each playbook based on:
#   - Success rate (40% weight)
#   - Impact (disk reclaimed, services recovered) (30% weight)
#   - Execution time (faster = better) (20% weight)
#   - Prediction accuracy (10% weight, for predictive-maintenance only)
#
# Usage:
#   remediation-effectiveness.sh --playbook <name>   # Score specific playbook
#   remediation-effectiveness.sh --all               # Score all playbooks
#   remediation-effectiveness.sh --summary           # Summary table

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
NC='\033[0m'

# Check if metrics history exists
if [ ! -f "$METRICS_HISTORY" ]; then
    echo -e "${RED}✗ Metrics history not found: $METRICS_HISTORY${NC}"
    exit 1
fi

# Calculate success rate score (0-100, weighted 40%)
calculate_success_rate_score() {
    local playbook="$1"
    local time_window="${2:-30}"  # Default 30 days

    local cutoff=$(($(date +%s) - time_window * 24 * 60 * 60))

    local success_count
    local total_count

    success_count=$(jq --arg pb "$playbook" --argjson cutoff "$cutoff" \
        '[.executions[] | select(.playbook == $pb and .timestamp >= $cutoff and .status == "success")] | length' \
        "$METRICS_HISTORY")

    total_count=$(jq --arg pb "$playbook" --argjson cutoff "$cutoff" \
        '[.executions[] | select(.playbook == $pb and .timestamp >= $cutoff)] | length' \
        "$METRICS_HISTORY")

    if [ "$total_count" -eq 0 ]; then
        echo "0"
        return
    fi

    # Success rate as percentage
    local success_rate=$(echo "scale=2; ($success_count * 100) / $total_count" | bc)

    # Weight: 40% of total score
    local weighted_score=$(echo "scale=2; ($success_rate * 0.4)" | bc)

    echo "$weighted_score"
}

# Calculate impact score (0-100, weighted 30%)
calculate_impact_score() {
    local playbook="$1"
    local time_window="${2:-30}"

    local cutoff=$(($(date +%s) - time_window * 24 * 60 * 60))

    # Different playbooks have different impact metrics
    case "$playbook" in
        disk-cleanup)
            # Impact = total disk reclaimed (normalize to 0-100 scale)
            # Assume 10GB reclaimed = perfect score
            local disk_reclaimed
            disk_reclaimed=$(jq --arg pb "$playbook" --argjson cutoff "$cutoff" \
                '[.executions[] | select(.playbook == $pb and .timestamp >= $cutoff) | .disk_reclaimed] | add // 0' \
                "$METRICS_HISTORY")

            local disk_gb=$(echo "scale=2; $disk_reclaimed / 1073741824" | bc)
            local score=$(echo "scale=2; if ($disk_gb > 10) 100 else ($disk_gb * 10)" | bc)
            local weighted=$(echo "scale=2; $score * 0.3" | bc)
            echo "$weighted"
            ;;

        self-healing-restart|service-restart)
            # Impact = number of services recovered
            # Assume 10 services recovered = perfect score
            local services_count
            services_count=$(jq --arg pb "$playbook" --argjson cutoff "$cutoff" \
                '[.executions[] | select(.playbook == $pb and .timestamp >= $cutoff and .services_restarted != "")] | length' \
                "$METRICS_HISTORY")

            local score=$(echo "scale=2; if ($services_count > 10) 100 else ($services_count * 10)" | bc)
            local weighted=$(echo "scale=2; $score * 0.3" | bc)
            echo "$weighted"
            ;;

        predictive-maintenance)
            # Impact = prediction accuracy (already 0-1, scale to 0-100)
            # This is complex - simplified to 70% (medium impact)
            echo "21.0"  # 70% * 0.3 = 21
            ;;

        database-maintenance)
            # Impact = number of successful maintenance runs
            # Assume 5 runs = perfect score
            local success_count
            success_count=$(jq --arg pb "$playbook" --argjson cutoff "$cutoff" \
                '[.executions[] | select(.playbook == $pb and .timestamp >= $cutoff and .status == "success")] | length' \
                "$METRICS_HISTORY")

            local score=$(echo "scale=2; if ($success_count > 5) 100 else ($success_count * 20)" | bc)
            local weighted=$(echo "scale=2; $score * 0.3" | bc)
            echo "$weighted"
            ;;

        *)
            # Default: moderate impact
            echo "15.0"  # 50% * 0.3 = 15
            ;;
    esac
}

# Calculate execution time score (0-100, weighted 20%)
# Faster execution = higher score
calculate_execution_time_score() {
    local playbook="$1"
    local time_window="${2:-30}"

    local cutoff=$(($(date +%s) - time_window * 24 * 60 * 60))

    # Get average execution time
    local total_duration
    local execution_count

    total_duration=$(jq --arg pb "$playbook" --argjson cutoff "$cutoff" \
        '[.executions[] | select(.playbook == $pb and .timestamp >= $cutoff) | .duration] | add // 0' \
        "$METRICS_HISTORY")

    execution_count=$(jq --arg pb "$playbook" --argjson cutoff "$cutoff" \
        '[.executions[] | select(.playbook == $pb and .timestamp >= $cutoff)] | length' \
        "$METRICS_HISTORY")

    if [ "$execution_count" -eq 0 ]; then
        echo "0"
        return
    fi

    local avg_duration=$(echo "scale=2; $total_duration / $execution_count" | bc)

    # Score inversely proportional to duration
    # Assume >300s = 0 score, <30s = perfect score
    local score
    if (( $(echo "$avg_duration < 30" | bc -l) )); then
        score=100
    elif (( $(echo "$avg_duration > 300" | bc -l) )); then
        score=0
    else
        score=$(echo "scale=2; 100 - (($avg_duration - 30) / 2.7)" | bc)
    fi

    local weighted=$(echo "scale=2; $score * 0.2" | bc)
    echo "$weighted"
}

# Calculate prediction accuracy score (0-100, weighted 10%)
# Only applies to predictive-maintenance
calculate_prediction_accuracy_score() {
    local playbook="$1"

    if [ "$playbook" != "predictive-maintenance" ]; then
        echo "0"
        return
    fi

    # Simplified: assume 80% accuracy
    # In real implementation, would compare predictions vs actuals
    local accuracy=80
    local weighted=$(echo "scale=2; $accuracy * 0.1" | bc)
    echo "$weighted"
}

# Calculate overall effectiveness score
calculate_effectiveness_score() {
    local playbook="$1"
    local time_window="${2:-30}"

    echo -e "${CYAN}Calculating effectiveness score for: $playbook${NC}"
    echo ""

    local success_score
    local impact_score
    local time_score
    local prediction_score

    success_score=$(calculate_success_rate_score "$playbook" "$time_window")
    impact_score=$(calculate_impact_score "$playbook" "$time_window")
    time_score=$(calculate_execution_time_score "$playbook" "$time_window")
    prediction_score=$(calculate_prediction_accuracy_score "$playbook")

    local total_score=$(echo "scale=2; $success_score + $impact_score + $time_score + $prediction_score" | bc)

    # Round to integer
    total_score=$(printf "%.0f" "$total_score")

    # Display breakdown
    echo "  Success Rate Score:     ${success_score} / 40"
    echo "  Impact Score:           ${impact_score} / 30"
    echo "  Execution Time Score:   ${time_score} / 20"
    if [ "$playbook" = "predictive-maintenance" ]; then
        echo "  Prediction Accuracy:    ${prediction_score} / 10"
    fi
    echo ""

    # Color-code total score
    if [ "$total_score" -ge 80 ]; then
        echo -e "${GREEN}✓ Overall Effectiveness: ${total_score}/100 (Excellent)${NC}"
    elif [ "$total_score" -ge 60 ]; then
        echo -e "${YELLOW}⚠ Overall Effectiveness: ${total_score}/100 (Good)${NC}"
    else
        echo -e "${RED}✗ Overall Effectiveness: ${total_score}/100 (Needs Improvement)${NC}"
    fi

    echo ""
}

# Show summary table for all playbooks
show_summary() {
    local time_window="${1:-30}"

    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Remediation Effectiveness Summary (Last $time_window days)${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Get all unique playbooks
    local playbooks
    playbooks=$(jq -r '[.executions[].playbook] | unique | .[]' "$METRICS_HISTORY" | sort)

    printf "%-30s %10s %10s %10s %10s\n" "Playbook" "Success%" "Impact" "Speed" "Total"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    while IFS= read -r playbook; do
        local success=$(calculate_success_rate_score "$playbook" "$time_window")
        local impact=$(calculate_impact_score "$playbook" "$time_window")
        local speed=$(calculate_execution_time_score "$playbook" "$time_window")
        local prediction=$(calculate_prediction_accuracy_score "$playbook")

        local total=$(echo "scale=0; ($success + $impact + $speed + $prediction) / 1" | bc)

        # Convert weighted scores back to percentages for display
        local success_pct=$(echo "scale=0; $success / 0.4" | bc)
        local impact_pct=$(echo "scale=0; ($impact / 0.3) / 1" | bc)
        local speed_pct=$(echo "scale=0; ($speed / 0.2) / 1" | bc)

        # Color code total score
        if [ "$total" -ge 80 ]; then
            printf "%-30s %9s%% %9s%% %9s%% ${GREEN}%9s${NC}\n" "$playbook" "$success_pct" "$impact_pct" "$speed_pct" "$total"
        elif [ "$total" -ge 60 ]; then
            printf "%-30s %9s%% %9s%% %9s%% ${YELLOW}%9s${NC}\n" "$playbook" "$success_pct" "$impact_pct" "$speed_pct" "$total"
        else
            printf "%-30s %9s%% %9s%% %9s%% ${RED}%9s${NC}\n" "$playbook" "$success_pct" "$impact_pct" "$speed_pct" "$total"
        fi
    done <<< "$playbooks"

    echo ""
    echo -e "${CYAN}Legend:${NC} ${GREEN}≥80 Excellent${NC} | ${YELLOW}60-79 Good${NC} | ${RED}<60 Needs Improvement${NC}"
    echo ""
}

# Main execution
main() {
    local mode="summary"
    local playbook=""
    local time_window=30

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --playbook)
                mode="single"
                playbook="$2"
                shift 2
                ;;
            --all)
                mode="all"
                shift
                ;;
            --summary)
                mode="summary"
                shift
                ;;
            --days)
                time_window="$2"
                shift 2
                ;;
            --help)
                cat << EOF
remediation-effectiveness.sh - Calculate playbook effectiveness scores

USAGE:
    remediation-effectiveness.sh --playbook <name> [--days N]
    remediation-effectiveness.sh --all [--days N]
    remediation-effectiveness.sh --summary [--days N]

OPTIONS:
    --playbook <name>    Calculate score for specific playbook
    --all                Calculate scores for all playbooks
    --summary            Show summary table (default)
    --days N             Time window in days (default: 30)
    --help               Show this help

EXAMPLES:
    # Score specific playbook
    remediation-effectiveness.sh --playbook disk-cleanup

    # Summary table
    remediation-effectiveness.sh --summary

    # Last 7 days only
    remediation-effectiveness.sh --summary --days 7
EOF
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    case "$mode" in
        single)
            if [ -z "$playbook" ]; then
                echo "Error: --playbook requires a playbook name"
                exit 1
            fi
            calculate_effectiveness_score "$playbook" "$time_window"
            ;;
        all)
            local playbooks
            playbooks=$(jq -r '[.executions[].playbook] | unique | .[]' "$METRICS_HISTORY" | sort)

            while IFS= read -r pb; do
                calculate_effectiveness_score "$pb" "$time_window"
                echo ""
            done <<< "$playbooks"
            ;;
        summary)
            show_summary "$time_window"
            ;;
    esac
}

main "$@"
