#!/usr/bin/env bash
#
# remediation-recommendations.sh - Generate actionable recommendations
# Part of Phase 6: Remediation History Analytics
#
# Analyzes remediation history and suggests optimizations:
#   - Memory limit adjustments (based on OOM events)
#   - Threshold tuning (too aggressive/passive)
#   - Service override additions
#   - Effectiveness improvements
#
# Usage:
#   remediation-recommendations.sh --last 30d
#   remediation-recommendations.sh --priority high

set -euo pipefail

# Configuration
METRICS_HISTORY="$HOME/containers/.claude/remediation/metrics-history.json"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

# Parse time period
parse_time_period() {
    local period="$1"
    if [[ $period =~ ^([0-9]+)d$ ]]; then
        echo $(( ${BASH_REMATCH[1]} * 24 * 60 * 60 ))
    else
        echo 2592000  # Default: 30 days
    fi
}

# Generate recommendations
generate_recommendations() {
    local period="$1"
    local period_seconds=$(parse_time_period "$period")
    local cutoff=$(($(date +%s) - period_seconds))

    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║         REMEDIATION RECOMMENDATIONS - Last $period                ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local rec_count=0

    # Recommendation 1: OOM-related memory adjustments
    local oom_services
    oom_services=$(jq --argjson cutoff "$cutoff" -r \
        '[.executions[] | select(.timestamp >= $cutoff and .oom_detected > 0) | .services_restarted] | unique | .[]' \
        "$METRICS_HISTORY" 2>/dev/null | sort -u)

    if [ -n "$oom_services" ]; then
        while IFS= read -r service; do
            if [ -z "$service" ]; then continue; fi

            local oom_count
            oom_count=$(jq --arg svc "$service" --argjson cutoff "$cutoff" \
                '[.executions[] | select(.services_restarted == $svc and .oom_detected > 0 and .timestamp >= $cutoff)] | length' \
                "$METRICS_HISTORY")

            if [ "$oom_count" -gt 2 ]; then
                ((rec_count++))
                echo -e "${YELLOW}[$rec_count] Memory Limit Adjustment${NC}"
                echo "  Service: $service"
                echo "  Issue: $oom_count OOM (Out of Memory) events detected"
                echo "  Priority: HIGH"
                echo "  Action: Consider increasing memory limit for $service"
                echo "  Impact: Reduce service crashes and restarts"
                echo ""
            fi
        done <<< "$oom_services"
    fi

    # Recommendation 2: High-frequency disk cleanup
    local disk_cleanup_count
    disk_cleanup_count=$(jq --argjson cutoff "$cutoff" \
        '[.executions[] | select(.playbook == "disk-cleanup" and .timestamp >= $cutoff)] | length' \
        "$METRICS_HISTORY")

    local cleanup_per_week=$(echo "scale=0; ($disk_cleanup_count * 7 * 24 * 60 * 60) / $period_seconds" | bc)

    if [ "$cleanup_per_week" -gt 2 ]; then
        ((rec_count++))
        echo -e "${YELLOW}[$rec_count] Disk Cleanup Frequency${NC}"
        echo "  Current: Running $cleanup_per_week times per week"
        echo "  Issue: Cleanup frequency may be too high"
        echo "  Priority: MEDIUM"
        echo "  Action: Review disk usage patterns and adjust cleanup thresholds"
        echo "  Options:"
        echo "    - Increase disk space allocation"
        echo "    - Adjust cleanup trigger thresholds"
        echo "    - Investigate root cause of high disk usage"
        echo ""
    fi

    # Recommendation 3: Database maintenance effectiveness
    local db_success_count
    local db_total_count

    db_success_count=$(jq --argjson cutoff "$cutoff" \
        '[.executions[] | select(.playbook == "database-maintenance" and .timestamp >= $cutoff and .status == "success")] | length' \
        "$METRICS_HISTORY")

    db_total_count=$(jq --argjson cutoff "$cutoff" \
        '[.executions[] | select(.playbook == "database-maintenance" and .timestamp >= $cutoff)] | length' \
        "$METRICS_HISTORY")

    if [ "$db_total_count" -gt 0 ]; then
        local db_success_rate=$(echo "scale=0; ($db_success_count * 100) / $db_total_count" | bc)

        if [ "$db_success_rate" -gt 80 ] && [ "$db_success_count" -gt 3 ]; then
            ((rec_count++))
            echo -e "${GREEN}[$rec_count] Database Maintenance Effective${NC}"
            echo "  Success rate: ${db_success_rate}%"
            echo "  Runs: $db_success_count successful"
            echo "  Priority: INFO"
            echo "  Action: Continue current database maintenance schedule"
            echo "  Impact: Maintaining database performance"
            echo ""
        elif [ "$db_success_rate" -lt 60 ]; then
            ((rec_count++))
            echo -e "${RED}[$rec_count] Database Maintenance Issues${NC}"
            echo "  Success rate: ${db_success_rate}%"
            echo "  Priority: HIGH"
            echo "  Action: Investigate database maintenance failures"
            echo "  Impact: Database performance may degrade"
            echo ""
        fi
    fi

    # Recommendation 4: Self-healing success patterns
    local self_healing_by_service
    self_healing_by_service=$(jq --argjson cutoff "$cutoff" \
        '[.executions[] | select((.playbook == "self-healing-restart" or .playbook == "service-restart") and .timestamp >= $cutoff)] | group_by(.services_restarted) | map({service: .[0].services_restarted, success: [.[] | select(.status == "success")] | length, total: length})' \
        "$METRICS_HISTORY")

    echo "$self_healing_by_service" | jq -r '.[] | select(.total >= 3) | "\(.service):\(.success):\(.total)"' | while IFS=: read -r service success total; do
        if [ -z "$service" ]; then continue; fi

        local success_rate=$(echo "scale=0; ($success * 100) / $total" | bc)

        if [ "$success_rate" -eq 100 ] && [ "$total" -gt 3 ]; then
            ((rec_count++))
            echo -e "${GREEN}[$rec_count] Service Override Candidate${NC}"
            echo "  Service: $service"
            echo "  Success: $success/$total (100%)"
            echo "  Priority: MEDIUM"
            echo "  Action: Consider adding $service to autonomous-operations overrides"
            echo "  Rationale: 100% success rate indicates safe for autonomous restart"
            echo ""
        elif [ "$success_rate" -lt 50 ]; then
            ((rec_count++))
            echo -e "${RED}[$rec_count] Service Restart Issues${NC}"
            echo "  Service: $service"
            echo "  Success: $success/$total (${success_rate}%)"
            echo "  Priority: HIGH"
            echo "  Action: Investigate why $service restarts frequently fail"
            echo "  Impact: Manual intervention often required"
            echo ""
        fi
    done

    # Recommendation 5: Predictive maintenance accuracy
    local predictive_runs
    predictive_runs=$(jq --argjson cutoff "$cutoff" \
        '[.executions[] | select(.playbook == "predictive-maintenance" and .timestamp >= $cutoff)] | length' \
        "$METRICS_HISTORY")

    if [ "$predictive_runs" -lt 5 ]; then
        ((rec_count++))
        echo -e "${YELLOW}[$rec_count] Predictive Maintenance Underutilized${NC}"
        echo "  Runs: $predictive_runs in last $period"
        echo "  Priority: MEDIUM"
        echo "  Action: Increase predictive maintenance frequency"
        echo "  Options:"
        echo "    - Schedule daily predictive-preemption chain"
        echo "    - Integrate into autonomous-operations OODA loop"
        echo "  Impact: More proactive incident prevention"
        echo ""
    fi

    # Recommendation 6: Chain usage
    if [ -f "$HOME/containers/.claude/remediation/chain-metrics-history.jsonl" ]; then
        local chain_count
        chain_count=$(wc -l < "$HOME/containers/.claude/remediation/chain-metrics-history.jsonl" 2>/dev/null || echo 0)

        if [ "$chain_count" -eq 0 ]; then
            ((rec_count++))
            echo -e "${CYAN}[$rec_count] Multi-Playbook Chains Available${NC}"
            echo "  Priority: INFO"
            echo "  Action: Consider using chain orchestration for complex scenarios"
            echo "  Available chains:"
            echo "    - full-recovery: Comprehensive system recovery"
            echo "    - predictive-preemption: Proactive maintenance"
            echo "    - database-health: DB maintenance + restart"
            echo "  Impact: More sophisticated remediation workflows"
            echo ""
        fi
    fi

    # Recommendation 7: Low effectiveness playbooks
    local playbooks
    playbooks=$(jq -r '[.executions[].playbook] | unique | .[]' "$METRICS_HISTORY" | sort)

    while IFS= read -r playbook; do
        if [ -z "$playbook" ]; then continue; fi

        local pb_success
        local pb_total

        pb_success=$(jq --arg pb "$playbook" --argjson cutoff "$cutoff" \
            '[.executions[] | select(.playbook == $pb and .timestamp >= $cutoff and .status == "success")] | length' \
            "$METRICS_HISTORY")

        pb_total=$(jq --arg pb "$playbook" --argjson cutoff "$cutoff" \
            '[.executions[] | select(.playbook == $pb and .timestamp >= $cutoff)] | length' \
            "$METRICS_HISTORY")

        if [ "$pb_total" -ge 5 ]; then
            local pb_rate=$(echo "scale=0; ($pb_success * 100) / $pb_total" | bc)

            if [ "$pb_rate" -lt 60 ]; then
                ((rec_count++))
                echo -e "${RED}[$rec_count] Low Effectiveness Playbook${NC}"
                echo "  Playbook: $playbook"
                echo "  Success: $pb_success/$pb_total (${pb_rate}%)"
                echo "  Priority: HIGH"
                echo "  Action: Review and improve $playbook implementation"
                echo "  Options:"
                echo "    - Add pre-flight checks"
                echo "    - Improve error handling"
                echo "    - Review failure logs for patterns"
                echo ""
            fi
        fi
    done <<< "$playbooks"

    # Summary
    if [ "$rec_count" -eq 0 ]; then
        echo -e "${GREEN}✓ No recommendations - system performing well${NC}"
        echo ""
    else
        echo -e "${CYAN}═══ Summary ═══${NC}"
        echo "  Total recommendations: $rec_count"
        echo "  Review and prioritize based on your operational needs"
        echo ""
    fi
}

# Main execution
main() {
    local period="30d"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --last)
                period="$2"
                shift 2
                ;;
            --help)
                cat << EOF
remediation-recommendations.sh - Generate actionable recommendations

USAGE:
    remediation-recommendations.sh --last <period>

OPTIONS:
    --last <period>     Time period (e.g., 30d, 7d)
    --help              Show this help

EXAMPLES:
    # Recommendations for last month
    remediation-recommendations.sh --last 30d

    # Recommendations for last week
    remediation-recommendations.sh --last 7d
EOF
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    if [ ! -f "$METRICS_HISTORY" ]; then
        echo "Error: Metrics history not found"
        exit 1
    fi

    generate_recommendations "$period"
}

main "$@"
