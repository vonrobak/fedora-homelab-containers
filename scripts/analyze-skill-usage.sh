#!/usr/bin/env bash
#
# analyze-skill-usage.sh - Skill Usage Analytics & Reporting
#
# Analyzes skill usage patterns to validate effectiveness and identify improvements.
# Generates insights on most/least used skills, success rates, recommendation accuracy.
#
# Usage:
#   ./analyze-skill-usage.sh                    # Terminal summary
#   ./analyze-skill-usage.sh --json             # JSON output
#   ./analyze-skill-usage.sh --monthly-report   # Full monthly report
#   ./analyze-skill-usage.sh --days 30          # Last 30 days only
#   ./analyze-skill-usage.sh --skill <name>     # Specific skill analysis
#
# Output:
#   - Skill usage statistics
#   - Success rates per skill/category
#   - Trend analysis
#   - Recommendations for improvement
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTEXT_DIR="$HOME/.claude/context"
SKILL_USAGE="$CONTEXT_DIR/skill-usage.json"
TASK_SKILL_MAP="$CONTEXT_DIR/task-skill-map.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Flags
JSON_OUTPUT=false
MONTHLY_REPORT=false
DAYS_FILTER=""
SKILL_FILTER=""

# Check if skill-usage.json exists
check_data_exists() {
    if [[ ! -f "$SKILL_USAGE" ]]; then
        echo "Error: No skill usage data found at $SKILL_USAGE" >&2
        echo "Skills must be used and logged before analysis is possible." >&2
        exit 1
    fi

    local session_count
    session_count=$(jq '.sessions | length' "$SKILL_USAGE")

    if (( session_count == 0 )); then
        echo "Error: No skill usage sessions recorded yet." >&2
        echo "Use skills and log usage with: recommend-skill.sh --log <skill> <outcome>" >&2
        exit 1
    fi
}

# Filter sessions by date range
filter_sessions() {
    local days="$1"

    if [[ -z "$days" ]]; then
        jq '.sessions' "$SKILL_USAGE"
    else
        local cutoff_date
        cutoff_date=$(date -d "$days days ago" -Iseconds)
        jq --arg cutoff "$cutoff_date" \
            '.sessions | map(select(.timestamp >= $cutoff))' \
            "$SKILL_USAGE"
    fi
}

# Get most used skills
get_top_skills() {
    local sessions="$1"
    local limit="${2:-5}"

    echo "$sessions" | jq -r \
        --argjson limit "$limit" \
        'group_by(.skill_used) |
         map({skill: .[0].skill_used, count: length}) |
         sort_by(.count) |
         reverse |
         .[:$limit] |
         .[]' | \
    while IFS= read -r line; do
        echo "$line"
    done
}

# Get least used skills (among those in task-skill-map)
get_underutilized_skills() {
    local sessions="$1"

    # Get all skills from task-skill-map
    local all_skills
    all_skills=$(jq -r '.task_categories[].skills[].name' "$TASK_SKILL_MAP" 2>/dev/null | sort -u)

    # Get used skills
    local used_skills
    used_skills=$(echo "$sessions" | jq -r '.[] | .skill_used' | sort -u)

    # Find unused skills
    local unused=()
    while IFS= read -r skill; do
        if ! echo "$used_skills" | grep -q "^${skill}$"; then
            unused+=("$skill")
        fi
    done <<< "$all_skills"

    # Get low-usage skills (used but <3 times)
    local low_usage
    low_usage=$(echo "$sessions" | jq -r \
        'group_by(.skill_used) |
         map({skill: .[0].skill_used, count: length}) |
         map(select(.count < 3)) |
         .[].skill')

    # Combine and output
    {
        for skill in "${unused[@]}"; do
            echo "$skill|0|never"
        done
        echo "$low_usage" | while IFS= read -r skill; do
            local count
            count=$(echo "$sessions" | jq -r --arg s "$skill" \
                'map(select(.skill_used == $s)) | length')
            echo "$skill|$count|rarely"
        done
    } | sort -t'|' -k2 -n
}

# Calculate success rate for a skill
get_skill_success_rate() {
    local sessions="$1"
    local skill="$2"

    local total
    total=$(echo "$sessions" | jq -r \
        --arg skill "$skill" \
        'map(select(.skill_used == $skill)) | length')

    if (( total == 0 )); then
        echo "0|0|0.00"
        return
    fi

    local successes
    successes=$(echo "$sessions" | jq -r \
        --arg skill "$skill" \
        'map(select(.skill_used == $skill and .outcome == "success")) | length')

    local rate
    rate=$(awk "BEGIN {printf \"%.2f\", ($successes / $total) * 100}")

    echo "$total|$successes|$rate"
}

# Calculate success rate by category
get_category_success_rate() {
    local sessions="$1"
    local category="$2"

    local total
    total=$(echo "$sessions" | jq -r \
        --arg cat "$category" \
        'map(select(.task_category == $cat)) | length')

    if (( total == 0 )); then
        echo "0|0|0.00"
        return
    fi

    local successes
    successes=$(echo "$sessions" | jq -r \
        --arg cat "$category" \
        'map(select(.task_category == $cat and .outcome == "success")) | length')

    local rate
    rate=$(awk "BEGIN {printf \"%.2f\", ($successes / $total) * 100}")

    echo "$total|$successes|$rate"
}

# Analyze trends over time
analyze_trends() {
    local sessions="$1"

    # Get first and last 7 days of data
    local first_week
    first_week=$(echo "$sessions" | jq -r \
        'sort_by(.timestamp) | .[0:7]')

    local last_week
    last_week=$(echo "$sessions" | jq -r \
        'sort_by(.timestamp) | .[-7:]')

    # Compare success rates
    local first_success_rate
    first_success_rate=$(echo "$first_week" | jq -r \
        'if length > 0 then
            (map(select(.outcome == "success")) | length) / length * 100
         else 0 end')

    local last_success_rate
    last_success_rate=$(echo "$last_week" | jq -r \
        'if length > 0 then
            (map(select(.outcome == "success")) | length) / length * 100
         else 0 end')

    # Compare most common category
    local first_top_cat
    first_top_cat=$(echo "$first_week" | jq -r \
        'group_by(.task_category) |
         map({cat: .[0].task_category, count: length}) |
         sort_by(.count) |
         reverse |
         .[0].cat // "NONE"')

    local last_top_cat
    last_top_cat=$(echo "$last_week" | jq -r \
        'group_by(.task_category) |
         map({cat: .[0].task_category, count: length}) |
         sort_by(.count) |
         reverse |
         .[0].cat // "NONE"')

    echo "$first_success_rate|$last_success_rate|$first_top_cat|$last_top_cat"
}

# Generate recommendations
generate_recommendations() {
    local sessions="$1"

    local recommendations=()

    # Check for underutilized skills
    local underutilized
    underutilized=$(get_underutilized_skills "$sessions")

    if [[ -n "$underutilized" ]]; then
        while IFS='|' read -r skill count usage; do
            if [[ "$usage" == "never" ]]; then
                recommendations+=("Skill '$skill' has never been used. Consider promoting it or removing from task-skill-map.json.")
            elif [[ "$usage" == "rarely" ]]; then
                recommendations+=("Skill '$skill' only used $count time(s). Review if task-skill-map keywords match common user requests.")
            fi
        done <<< "$underutilized"
    fi

    # Check for low success rates
    local skills
    skills=$(echo "$sessions" | jq -r '.[] | .skill_used' | sort -u)

    while IFS= read -r skill; do
        [[ -z "$skill" ]] && continue

        IFS='|' read -r total successes rate <<< "$(get_skill_success_rate "$sessions" "$skill")"

        if (( total >= 5 )) && awk "BEGIN {exit !($rate < 70)}"; then
            recommendations+=("Skill '$skill' has low success rate ($rate%). Investigate why it's not meeting user needs.")
        fi
    done <<< "$skills"

    # Check for category imbalance
    local total_sessions
    total_sessions=$(echo "$sessions" | jq 'length')

    local categories
    categories=$(jq -r '.task_categories[].category' "$TASK_SKILL_MAP" 2>/dev/null)

    while IFS= read -r category; do
        [[ -z "$category" ]] && continue

        local cat_count
        cat_count=$(echo "$sessions" | jq -r \
            --arg cat "$category" \
            'map(select(.task_category == $cat)) | length')

        local percentage
        percentage=$(awk "BEGIN {printf \"%.0f\", ($cat_count / $total_sessions) * 100}")

        if (( percentage >= 60 )); then
            recommendations+=("Category '$category' dominates usage ($percentage%). Consider if keywords are too broad.")
        fi
    done <<< "$categories"

    # Output recommendations
    if (( ${#recommendations[@]} == 0 )); then
        echo "No specific recommendations. Skill usage appears healthy."
    else
        printf '%s\n' "${recommendations[@]}"
    fi
}

# Terminal output (human-readable)
output_terminal() {
    local sessions="$1"

    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         Skill Usage Analytics Report                      ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Summary statistics
    local total_sessions
    total_sessions=$(echo "$sessions" | jq 'length')

    local date_range_start date_range_end
    date_range_start=$(echo "$sessions" | jq -r 'sort_by(.timestamp) | .[0].timestamp' | cut -d'T' -f1)
    date_range_end=$(echo "$sessions" | jq -r 'sort_by(.timestamp) | .[-1].timestamp' | cut -d'T' -f1)

    local overall_success_rate
    overall_success_rate=$(echo "$sessions" | jq -r \
        '(map(select(.outcome == "success")) | length) / length * 100')

    echo -e "${YELLOW}📊 Summary${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Total Sessions: $total_sessions"
    echo "  Date Range: $date_range_start to $date_range_end"
    LC_NUMERIC=C printf "  Overall Success Rate: %.1f%%\n" "$overall_success_rate"
    echo ""

    # Most used skills
    echo -e "${YELLOW}🏆 Most Used Skills${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local top_skills
    top_skills=$(get_top_skills "$sessions" 5)

    local rank=1
    echo "$top_skills" | jq -r '. | "\(.skill)|\(.count)"' | while IFS='|' read -r skill count; do
        IFS='|' read -r total successes rate <<< "$(get_skill_success_rate "$sessions" "$skill")"

        # Color code by success rate
        local color="$GREEN"
        if awk "BEGIN {exit !($rate < 70)}"; then
            color="$RED"
        elif awk "BEGIN {exit !($rate < 85)}"; then
            color="$YELLOW"
        fi

        LC_NUMERIC=C printf "  %d. %-25s %3d uses  ${color}%.0f%% success${NC}\n" "$rank" "$skill" "$count" "$rate"
        ((rank++)) || true
    done
    echo ""

    # Underutilized skills
    echo -e "${YELLOW}⚠️  Underutilized Skills${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local underutilized
    underutilized=$(get_underutilized_skills "$sessions")

    if [[ -z "$underutilized" ]]; then
        echo "  ${GREEN}✓ All skills are being used${NC}"
    else
        echo "$underutilized" | while IFS='|' read -r skill count usage; do
            if [[ "$usage" == "never" ]]; then
                echo "  ${RED}✗ $skill${NC} - Never used"
            else
                echo "  ${YELLOW}⚠ $skill${NC} - Only $count time(s)"
            fi
        done
    fi
    echo ""

    # Success rates by category
    echo -e "${YELLOW}📈 Success Rates by Category${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local categories
    categories=$(echo "$sessions" | jq -r '.[] | .task_category' | sort -u)

    while IFS= read -r category; do
        [[ -z "$category" ]] && continue

        IFS='|' read -r total successes rate <<< "$(get_category_success_rate "$sessions" "$category")"

        if (( total > 0 )); then
            local color="$GREEN"
            if awk "BEGIN {exit !($rate < 70)}"; then
                color="$RED"
            elif awk "BEGIN {exit !($rate < 85)}"; then
                color="$YELLOW"
            fi

            LC_NUMERIC=C printf "  %-20s %3d sessions  ${color}%.0f%% success${NC}\n" "$category" "$total" "$rate"
        fi
    done
    echo ""

    # Trends
    if (( total_sessions >= 14 )); then
        echo -e "${YELLOW}📊 Trends${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        IFS='|' read -r first_rate last_rate first_cat last_cat <<< "$(analyze_trends "$sessions")"

        local rate_change
        rate_change=$(awk "BEGIN {printf \"%.1f\", $last_rate - $first_rate}")

        if awk "BEGIN {exit !($rate_change > 5)}"; then
            echo -e "  Success Rate: ${GREEN}↑ Improving${NC} (${first_rate}% → ${last_rate}%)"
        elif awk "BEGIN {exit !($rate_change < -5)}"; then
            echo -e "  Success Rate: ${RED}↓ Declining${NC} (${first_rate}% → ${last_rate}%)"
        else
            echo "  Success Rate: → Stable (~${last_rate}%)"
        fi

        if [[ "$first_cat" != "$last_cat" ]]; then
            echo "  Primary Category Shift: $first_cat → $last_cat"
        else
            echo "  Primary Category: $last_cat (stable)"
        fi
        echo ""
    fi

    # Recommendations
    echo -e "${YELLOW}💡 Recommendations${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    generate_recommendations "$sessions" | while IFS= read -r rec; do
        echo "  • $rec"
    done
    echo ""
}

# JSON output
output_json() {
    local sessions="$1"

    local total_sessions
    total_sessions=$(echo "$sessions" | jq 'length')

    # Get top skills with success rates
    local top_skills
    top_skills=$(echo "$sessions" | jq -r \
        'group_by(.skill_used) |
         map({
           skill: .[0].skill_used,
           count: length,
           successes: map(select(.outcome == "success")) | length
         }) |
         map(.success_rate = (.successes / .count * 100)) |
         sort_by(.count) |
         reverse')

    # Get category stats
    local category_stats
    category_stats=$(echo "$sessions" | jq -r \
        'group_by(.task_category) |
         map({
           category: .[0].task_category,
           count: length,
           successes: map(select(.outcome == "success")) | length
         }) |
         map(.success_rate = (.successes / .count * 100))')

    # Overall success rate
    local overall_success_rate
    overall_success_rate=$(echo "$sessions" | jq -r \
        '(map(select(.outcome == "success")) | length) / length * 100')

    # Combine into report
    jq -n \
        --argjson total "$total_sessions" \
        --argjson success_rate "$overall_success_rate" \
        --argjson top_skills "$top_skills" \
        --argjson categories "$category_stats" \
        '{
            total_sessions: $total,
            overall_success_rate: $success_rate,
            top_skills: $top_skills,
            category_stats: $categories
        }'
}

# Main
main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                JSON_OUTPUT=true
                shift
                ;;
            --monthly-report)
                MONTHLY_REPORT=true
                shift
                ;;
            --days)
                DAYS_FILTER="$2"
                shift 2
                ;;
            --skill)
                SKILL_FILTER="$2"
                shift 2
                ;;
            -h|--help)
                cat <<EOF
Usage: $0 [OPTIONS]

Analyze skill usage patterns and generate insights.

Options:
  --json              Output in JSON format
  --monthly-report    Generate full monthly report (saves to docs/99-reports/)
  --days N            Analyze last N days only
  --skill <name>      Analyze specific skill only
  -h, --help          Show this help

Examples:
  $0                        # Terminal summary of all data
  $0 --days 30              # Last 30 days
  $0 --skill systematic-debugging
  $0 --monthly-report       # Full report saved to file
EOF
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                exit 1
                ;;
        esac
    done

    check_data_exists

    # Get sessions (filtered if requested)
    local sessions
    sessions=$(filter_sessions "$DAYS_FILTER")

    # Filter by skill if requested
    if [[ -n "$SKILL_FILTER" ]]; then
        sessions=$(echo "$sessions" | jq -r \
            --arg skill "$SKILL_FILTER" \
            'map(select(.skill_used == $skill))')
    fi

    # Check if we have data after filtering
    local count
    count=$(echo "$sessions" | jq 'length')
    if (( count == 0 )); then
        echo "No data found matching filters." >&2
        exit 1
    fi

    # Output
    if $JSON_OUTPUT; then
        output_json "$sessions"
    elif $MONTHLY_REPORT; then
        # Generate report file
        local report_file
        report_file="$(dirname "$SCRIPT_DIR")/docs/99-reports/$(date +%Y-%m-%d)-skill-usage-report.md"

        echo "Generating monthly report: $report_file"

        {
            echo "# Skill Usage Analytics Report"
            echo ""
            echo "**Generated:** $(date -Iseconds)"
            echo "**Period:** Last 30 days"
            echo ""
            echo "---"
            echo ""
            output_terminal "$(filter_sessions 30)"
        } > "$report_file"

        echo "Report saved: $report_file"
    else
        output_terminal "$sessions"
    fi
}

main "$@"
