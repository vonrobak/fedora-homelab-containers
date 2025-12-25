#!/usr/bin/env bash
#
# generate-monthly-report.sh - Generate monthly remediation report
# Part of Phase 6: Remediation History Analytics
#
# Generates comprehensive monthly report combining:
#   - Effectiveness scores
#   - Trend analysis
#   - ROI calculations
#   - Recommendations
#
# Usage:
#   generate-monthly-report.sh                    # Current month
#   generate-monthly-report.sh --month 2025-12    # Specific month

set -euo pipefail

# Configuration
METRICS_HISTORY="$HOME/containers/.claude/remediation/metrics-history.json"
REPORTS_DIR="$HOME/containers/docs/99-reports"
ANALYTICS_DIR="$(dirname "$0")"

# Ensure reports directory exists
mkdir -p "$REPORTS_DIR"

# Get month to report on
get_report_month() {
    local month="${1:-}"

    if [ -z "$month" ]; then
        # Default to last month
        date -d "last month" +%Y-%m
    else
        echo "$month"
    fi
}

# Generate report
generate_report() {
    local month="$1"
    local year_month=$(echo "$month" | tr -d '-')
    local report_file="$REPORTS_DIR/remediation-monthly-$year_month.md"

    # Calculate time range for the month
    local month_start=$(date -d "$month-01" +%s)
    local next_month=$(date -d "$month-01 + 1 month" +"%Y-%m")
    local month_end=$(date -d "$next_month-01" +%s)
    local month_duration=$((month_end - month_start))
    local days_in_month=$(echo "scale=0; $month_duration / 86400" | bc)

    echo "Generating remediation report for $month..."
    echo "Report will be saved to: $report_file"
    echo ""

    # Start building report
    cat > "$report_file" << EOF
# Remediation Monthly Report - $(date -d "$month-01" +"%B %Y")

**Generated:** $(date +"%Y-%m-%d %H:%M:%S")
**Period:** $month (${days_in_month} days)
**Report Type:** Automated Analytics

---

## Executive Summary

EOF

    # Get summary statistics
    local total_executions
    local total_success
    local total_failures

    total_executions=$(jq --argjson start "$month_start" --argjson end "$month_end" \
        '[.executions[] | select(.timestamp >= $start and .timestamp < $end)] | length' \
        "$METRICS_HISTORY")

    total_success=$(jq --argjson start "$month_start" --argjson end "$month_end" \
        '[.executions[] | select(.timestamp >= $start and .timestamp < $end and .status == "success")] | length' \
        "$METRICS_HISTORY")

    total_failures=$((total_executions - total_success))

    local success_rate=0
    if [ "$total_executions" -gt 0 ]; then
        success_rate=$(echo "scale=0; ($total_success * 100) / $total_executions" | bc)
    fi

    # Disk reclaimed
    local total_disk_reclaimed
    total_disk_reclaimed=$(jq --argjson start "$month_start" --argjson end "$month_end" \
        '[.executions[] | select(.timestamp >= $start and .timestamp < $end) | .disk_reclaimed] | add // 0' \
        "$METRICS_HISTORY")

    local disk_gb=$(echo "scale=1; $total_disk_reclaimed / 1073741824" | bc)

    # Services recovered
    local services_recovered
    services_recovered=$(jq --argjson start "$month_start" --argjson end "$month_end" \
        '[.executions[] | select((.playbook == "self-healing-restart" or .playbook == "service-restart") and .timestamp >= $start and .timestamp < $end and .status == "success")] | length' \
        "$METRICS_HISTORY")

    # Calculate time saved
    local manual_time=$(echo "scale=1; ($total_success * 30) / 60" | bc)
    local auto_time=$(echo "scale=1; ($total_success * 2) / 60" | bc)
    local time_saved=$(echo "scale=1; $manual_time - $auto_time" | bc)

    cat >> "$report_file" << EOF
**Key Metrics:**

- **Total Executions:** $total_executions
- **Success Rate:** $success_rate%
- **Time Saved:** $time_saved hours
- **Disk Reclaimed:** $disk_gb GB
- **Services Recovered:** $services_recovered

**Performance Status:** $(if [ "$success_rate" -ge 90 ]; then echo "✅ Excellent"; elif [ "$success_rate" -ge 75 ]; then echo "⚠️ Good"; else echo "❌ Needs Attention"; fi)

---

## Top Performers

EOF

    # Get top 5 playbooks by execution count
    jq --argjson start "$month_start" --argjson end "$month_end" \
        '[.executions[] | select(.timestamp >= $start and .timestamp < $end)] | group_by(.playbook) | map({playbook: .[0].playbook, count: length, success: [.[] | select(.status == "success")] | length}) | sort_by(-.count) | .[:5]' \
        "$METRICS_HISTORY" | jq -r '.[] | "\(.playbook):\(.count):\(.success)"' | while IFS=: read -r playbook count success; do

        local rate=$(echo "scale=0; ($success * 100) / $count" | bc)
        echo "1. **$playbook** - $count runs, $rate% success" >> "$report_file"
    done

    cat >> "$report_file" << EOF

---

## Incidents Prevented

EOF

    # Predictive maintenance
    local predictive_runs
    predictive_runs=$(jq --argjson start "$month_start" --argjson end "$month_end" \
        '[.executions[] | select(.playbook == "predictive-maintenance" and .timestamp >= $start and .timestamp < $end and .status == "success")] | length' \
        "$METRICS_HISTORY")

    local incidents_prevented=$(echo "scale=0; $predictive_runs * 0.3" | bc | cut -d. -f1)

    cat >> "$report_file" << EOF
- **Predictive Maintenance Runs:** $predictive_runs
- **Estimated Incidents Prevented:** $incidents_prevented
- **Self-Healing Recoveries:** $services_recovered

**Impact:** Proactive remediation prevented approximately $incidents_prevented potential incidents before they affected users.

---

## Effectiveness Analysis

EOF

    # Run effectiveness analysis
    echo "Running effectiveness analysis..."
    "$ANALYTICS_DIR/remediation-effectiveness.sh" --summary --days "$days_in_month" > /tmp/effectiveness.txt 2>&1 || true

    # Extract summary table (remove color codes)
    if [ -f /tmp/effectiveness.txt ]; then
        sed 's/\x1b\[[0-9;]*m//g' /tmp/effectiveness.txt | tail -n +6 >> "$report_file"
    fi

    cat >> "$report_file" << EOF

---

## Trend Analysis

EOF

    echo "Running trend analysis..."
    "$ANALYTICS_DIR/remediation-trends.sh" --last "${days_in_month}d" > /tmp/trends.txt 2>&1 || true

    # Extract key trends (remove color codes and formatting)
    if [ -f /tmp/trends.txt ]; then
        sed 's/\x1b\[[0-9;]*m//g' /tmp/trends.txt | grep -A 50 "Execution Frequency Trends" | head -n 20 >> "$report_file"
    fi

    cat >> "$report_file" << EOF

---

## ROI Summary

EOF

    echo "Calculating ROI..."
    "$ANALYTICS_DIR/remediation-roi.sh" --last "${days_in_month}d" > /tmp/roi.txt 2>&1 || true

    if [ -f /tmp/roi.txt ]; then
        sed 's/\x1b\[[0-9;]*m//g' /tmp/roi.txt | grep -A 20 "ROI Summary" >> "$report_file"
    fi

    cat >> "$report_file" << EOF

---

## Recommendations

EOF

    echo "Generating recommendations..."
    "$ANALYTICS_DIR/remediation-recommendations.sh" --last "${days_in_month}d" > /tmp/recommendations.txt 2>&1 || true

    if [ -f /tmp/recommendations.txt ]; then
        # Extract recommendations (remove color codes)
        sed 's/\x1b\[[0-9;]*m//g' /tmp/recommendations.txt | tail -n +6 >> "$report_file"
    fi

    cat >> "$report_file" << EOF

---

## Next Steps

Based on this month's analysis:

1. **Review High-Priority Recommendations** - Address any HIGH priority items identified above
2. **Monitor Trending Metrics** - Track success rates and execution frequencies
3. **Optimize Underperforming Playbooks** - Focus on playbooks with <80% effectiveness
4. **Continue Proactive Maintenance** - Predictive maintenance showing positive impact

---

**Report Generated By:** remediation-analytics (Phase 6)
**Next Report:** $(date -d "$month-01 + 2 months" +"%Y-%m")

EOF

    # Cleanup temp files
    rm -f /tmp/effectiveness.txt /tmp/trends.txt /tmp/roi.txt /tmp/recommendations.txt

    echo "✓ Report generated successfully: $report_file"
    echo ""
    echo "Summary:"
    echo "  Total executions: $total_executions"
    echo "  Success rate: $success_rate%"
    echo "  Time saved: $time_saved hours"
    echo ""
}

# Main execution
main() {
    local month=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --month)
                month="$2"
                shift 2
                ;;
            --help)
                cat << EOF
generate-monthly-report.sh - Generate monthly remediation report

USAGE:
    generate-monthly-report.sh                # Current month
    generate-monthly-report.sh --month YYYY-MM    # Specific month

OPTIONS:
    --month YYYY-MM     Month to report on (e.g., 2025-12)
    --help              Show this help

EXAMPLES:
    # Generate report for last month
    generate-monthly-report.sh

    # Generate report for specific month
    generate-monthly-report.sh --month 2025-12

OUTPUT:
    Report saved to: ~/containers/docs/99-reports/remediation-monthly-YYYYMM.md
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
        echo "Error: Metrics history not found: $METRICS_HISTORY"
        exit 1
    fi

    month=$(get_report_month "$month")
    generate_report "$month"
}

main "$@"
