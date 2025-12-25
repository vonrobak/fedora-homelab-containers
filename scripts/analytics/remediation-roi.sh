#!/usr/bin/env bash
#
# remediation-roi.sh - Calculate remediation ROI (Return on Investment)
# Part of Phase 6: Remediation History Analytics
#
# Calculates value delivered by auto-remediation:
#   - Incidents prevented (via predictive maintenance)
#   - Manual interventions avoided
#   - Average resolution time (auto vs manual)
#   - Total time saved
#
# Usage:
#   remediation-roi.sh --last 30d    # ROI for last 30 days
#   remediation-roi.sh --summary     # Quick summary

set -euo pipefail

# Configuration
METRICS_HISTORY="$HOME/containers/.claude/remediation/metrics-history.json"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Assumptions for ROI calculation
AVG_MANUAL_TIME_MINUTES=30  # Average time for manual remediation
AVG_AUTO_TIME_SECONDS=120    # Average automated remediation time

# Parse time period
parse_time_period() {
    local period="$1"
    if [[ $period =~ ^([0-9]+)d$ ]]; then
        echo $(( ${BASH_REMATCH[1]} * 24 * 60 * 60 ))
    elif [[ $period =~ ^([0-9]+)h$ ]]; then
        echo $(( ${BASH_REMATCH[1]} * 60 * 60 ))
    else
        echo 2592000  # Default: 30 days
    fi
}

# Calculate ROI
calculate_roi() {
    local period="$1"
    local period_seconds=$(parse_time_period "$period")
    local cutoff=$(($(date +%s) - period_seconds))

    echo ""
    echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║         REMEDIATION ROI ANALYSIS - Last $period                    ║${NC}"
    echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Total successful remediations
    local total_success
    total_success=$(jq --argjson cutoff "$cutoff" \
        '[.executions[] | select(.timestamp >= $cutoff and .status == "success")] | length' \
        "$METRICS_HISTORY")

    # Total failed (would have needed manual intervention)
    local total_failures
    total_failures=$(jq --argjson cutoff "$cutoff" \
        '[.executions[] | select(.timestamp >= $cutoff and .status == "failure")] | length' \
        "$METRICS_HISTORY")

    # Predictive maintenance runs (incidents prevented)
    local predictive_runs
    predictive_runs=$(jq --argjson cutoff "$cutoff" \
        '[.executions[] | select(.playbook == "predictive-maintenance" and .timestamp >= $cutoff and .status == "success")] | length' \
        "$METRICS_HISTORY")

    # Estimate incidents prevented (assume 30% of predictive runs prevent an incident)
    local incidents_prevented=$(echo "scale=0; $predictive_runs * 0.3" | bc | cut -d. -f1)

    # Self-healing restarts (services recovered)
    local services_recovered
    services_recovered=$(jq --argjson cutoff "$cutoff" \
        '[.executions[] | select((.playbook == "self-healing-restart" or .playbook == "service-restart") and .timestamp >= $cutoff and .status == "success")] | length' \
        "$METRICS_HISTORY")

    # Total automated interventions
    local total_interventions=$((total_success + incidents_prevented))

    # Time savings calculation
    local manual_time_hours=$(echo "scale=2; ($total_interventions * $AVG_MANUAL_TIME_MINUTES) / 60" | bc)
    local auto_time_hours=$(echo "scale=2; ($total_success * $AVG_AUTO_TIME_SECONDS) / 3600" | bc)
    local time_saved=$(echo "scale=2; $manual_time_hours - $auto_time_hours" | bc)

    # Display results
    echo -e "${BLUE}═══ Automation Impact ═══${NC}"
    echo ""
    printf "  %-50s %s\n" "Total automated remediations:" "${GREEN}$total_success${NC}"
    printf "  %-50s %s\n" "Incidents prevented (predictive):" "${GREEN}$incidents_prevented${NC}"
    printf "  %-50s %s\n" "Services recovered (self-healing):" "${GREEN}$services_recovered${NC}"
    printf "  %-50s %s\n" "Manual interventions avoided:" "${GREEN}$total_interventions${NC}"
    echo ""

    echo -e "${BLUE}═══ Time Savings ═══${NC}"
    echo ""
    printf "  %-50s %s hours\n" "Estimated manual time (if done manually):" "${YELLOW}${manual_time_hours}${NC}"
    printf "  %-50s %s hours\n" "Actual automated time:" "${GREEN}${auto_time_hours}${NC}"
    printf "  %-50s %s hours\n" "Time saved:" "${GREEN}${time_saved}${NC}"
    echo ""

    # Average resolution time
    if [ "$total_success" -gt 0 ]; then
        local avg_duration
        avg_duration=$(jq --argjson cutoff "$cutoff" \
            '[.executions[] | select(.timestamp >= $cutoff and .status == "success") | .duration] | add' \
            "$METRICS_HISTORY")

        local avg_minutes=$(echo "scale=1; ($avg_duration / $total_success) / 60" | bc)

        echo -e "${BLUE}═══ Resolution Performance ═══${NC}"
        echo ""
        printf "  %-50s %s minutes\n" "Average manual resolution time:" "${YELLOW}$AVG_MANUAL_TIME_MINUTES${NC}"
        printf "  %-50s %s minutes\n" "Average automated resolution time:" "${GREEN}${avg_minutes}${NC}"

        local speedup=$(echo "scale=1; $AVG_MANUAL_TIME_MINUTES / $avg_minutes" | bc)
        printf "  %-50s %s\n" "Speedup factor:" "${GREEN}${speedup}x${NC}"
        echo ""
    fi

    # Success rate
    local total_attempts=$((total_success + total_failures))
    if [ "$total_attempts" -gt 0 ]; then
        local success_rate=$(echo "scale=0; ($total_success * 100) / $total_attempts" | bc)

        echo -e "${BLUE}═══ Reliability ═══${NC}"
        echo ""
        printf "  %-50s %s%%\n" "Overall success rate:" "${GREEN}$success_rate${NC}"
        printf "  %-50s %s\n" "Total executions:" "$total_attempts"
        printf "  %-50s %s\n" "Successful:" "${GREEN}$total_success${NC}"
        printf "  %-50s %s\n" "Failed:" "${YELLOW}$total_failures${NC}"
        echo ""
    fi

    # ROI summary
    echo -e "${CYAN}═══ ROI Summary ═══${NC}"
    echo ""
    echo "  In the last $period, auto-remediation has:"
    echo "  • Prevented $incidents_prevented incidents before they occurred"
    echo "  • Recovered $services_recovered services automatically"
    echo "  • Avoided $total_interventions manual interventions"
    echo "  • Saved ${time_saved} hours of operational time"
    echo ""

    if (( $(echo "$time_saved > 0" | bc -l) )); then
        local workdays=$(echo "scale=1; $time_saved / 8" | bc)
        echo -e "  ${GREEN}✓ Equivalent to ${workdays} workdays saved${NC}"
    fi

    echo ""
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
            --summary)
                period="30d"
                shift
                ;;
            --help)
                cat << EOF
remediation-roi.sh - Calculate remediation ROI

USAGE:
    remediation-roi.sh --last <period>
    remediation-roi.sh --summary

OPTIONS:
    --last <period>     Time period (e.g., 30d, 7d)
    --summary           Quick summary (last 30 days)
    --help              Show this help

EXAMPLES:
    # ROI for last month
    remediation-roi.sh --last 30d

    # Quick summary
    remediation-roi.sh --summary
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

    calculate_roi "$period"
}

main "$@"
