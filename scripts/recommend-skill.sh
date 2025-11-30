#!/usr/bin/env bash
#
# recommend-skill.sh - Skill Recommendation Engine
#
# Analyzes user requests and recommends the most appropriate Claude skill(s).
# Implements task classification, confidence scoring, and usage tracking.
#
# Usage:
#   ./recommend-skill.sh "user request"           # Human-readable output
#   ./recommend-skill.sh --json "user request"    # JSON output
#   ./recommend-skill.sh --log <skill> <outcome>  # Log skill usage
#   ./recommend-skill.sh --stats                  # Show usage statistics
#
# Exit codes:
#   0 - Recommendation found
#   1 - No recommendation / UNKNOWN category
#   2 - Error
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTEXT_DIR="$HOME/containers/.claude/context"
TASK_SKILL_MAP="$CONTEXT_DIR/task-skill-map.json"
SKILL_USAGE="$CONTEXT_DIR/skill-usage.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Flags
JSON_OUTPUT=false
LOG_MODE=false
STATS_MODE=false

# Initialize files if not exist
init_files() {
    mkdir -p "$CONTEXT_DIR"

    if [[ ! -f "$SKILL_USAGE" ]]; then
        cat > "$SKILL_USAGE" <<'EOF'
{
  "sessions": [],
  "statistics": {
    "total_invocations": 0,
    "by_skill": {},
    "by_category": {},
    "success_rate": 0.0
  }
}
EOF
    fi

    if [[ ! -f "$TASK_SKILL_MAP" ]]; then
        echo "Error: task-skill-map.json not found at $TASK_SKILL_MAP" >&2
        exit 2
    fi
}

# Extract meaningful keywords from user request
extract_keywords() {
    local request="$1"

    # Convert to lowercase, remove punctuation, extract words
    # Filter out common stop words
    echo "$request" \
        | tr '[:upper:]' '[:lower:]' \
        | sed 's/[^a-z0-9 ]/ /g' \
        | tr -s ' ' '\n' \
        | grep -vE '^(a|an|the|is|are|was|were|be|been|being|have|has|had|do|does|did|will|would|should|could|may|might|can|i|me|my|you|your|it|its|we|our|they|their|this|that|of|to|in|for|on|with|at|by|from|as|or|and|but|if|so|than|too|very|just|now|then|also|only|more|some|no|not|all|any|each|about|into)$' \
        | grep -E '^.{2,}$' \
        | sort -u
}

# Calculate keyword match score for a category
calculate_category_score() {
    local keywords="$1"
    local category_keywords="$2"

    local matches=0
    local total=0

    while IFS= read -r cat_kw; do
        [[ -z "$cat_kw" ]] && continue
        ((total++)) || true

        # Handle multi-word keywords (like "won't start") - check if all words present
        if [[ "$cat_kw" == *" "* ]]; then
            local all_found=true
            for word in $cat_kw; do
                if ! echo "$keywords" | grep -qi "$word" 2>/dev/null; then
                    all_found=false
                    break
                fi
            done
            if $all_found; then
                ((matches++)) || true
            fi
        else
            # Single word - use partial match (error matches errors, fail matches failure)
            if echo "$keywords" | grep -qi "$cat_kw" 2>/dev/null; then
                ((matches++)) || true
            fi
        fi
    done <<< "$category_keywords"

    if (( total == 0 )); then
        echo "0.0"
    else
        awk "BEGIN {printf \"%.3f\", $matches / $total}"
    fi
}

# Classify task based on keywords
classify_task() {
    local keywords="$1"

    local best_category="UNKNOWN"
    local best_score="0.0"

    # Read each category from task-skill-map.json
    local categories
    categories=$(jq -r '.task_categories[] | @base64' "$TASK_SKILL_MAP")

    while IFS= read -r category_b64; do
        [[ -z "$category_b64" ]] && continue

        local category_json
        category_json=$(echo "$category_b64" | base64 -d)

        local category
        category=$(echo "$category_json" | jq -r '.category')

        local category_keywords
        category_keywords=$(echo "$category_json" | jq -r '.keywords[]')

        local score
        score=$(calculate_category_score "$keywords" "$category_keywords")

        # Compare scores using awk for floating point
        if awk "BEGIN {exit !($score > $best_score)}"; then
            best_score="$score"
            best_category="$category"
        fi
    done <<< "$categories"

    # Require minimum 8% match for a category (at least 1-2 keywords)
    if awk "BEGIN {exit !($best_score < 0.08)}"; then
        echo "UNKNOWN|0.0"
    else
        echo "${best_category}|${best_score}"
    fi
}

# Calculate historical success score for a skill in a category
calculate_historical_score() {
    local category="$1"
    local skill_name="$2"

    if [[ ! -f "$SKILL_USAGE" ]]; then
        echo "0.5"
        return
    fi

    local total_uses
    total_uses=$(jq -r \
        --arg cat "$category" \
        --arg skill "$skill_name" \
        '[.sessions[] | select(.task_category == $cat and .skill_used == $skill)] | length' \
        "$SKILL_USAGE" 2>/dev/null || echo "0")

    if (( total_uses == 0 )); then
        echo "0.5"  # Neutral score (no data)
        return
    fi

    local successful_uses
    successful_uses=$(jq -r \
        --arg cat "$category" \
        --arg skill "$skill_name" \
        '[.sessions[] | select(.task_category == $cat and .skill_used == $skill and .outcome == "success")] | length' \
        "$SKILL_USAGE" 2>/dev/null || echo "0")

    awk "BEGIN {printf \"%.3f\", $successful_uses / $total_uses}"
}

# Get skill recommendations for a category
get_skill_recommendations() {
    local category="$1"
    local keywords="$2"
    local category_score="$3"

    # Get skills for this category
    local skills
    skills=$(jq -r \
        --arg cat "$category" \
        '.task_categories[] | select(.category == $cat) | .skills[] | @base64' \
        "$TASK_SKILL_MAP" 2>/dev/null || echo "")

    if [[ -z "$skills" ]]; then
        echo "[]"
        return
    fi

    local recommendations="[]"

    while IFS= read -r skill_b64; do
        [[ -z "$skill_b64" ]] && continue

        local skill_json
        skill_json=$(echo "$skill_b64" | base64 -d)

        local skill_name priority description
        skill_name=$(echo "$skill_json" | jq -r '.name')
        priority=$(echo "$skill_json" | jq -r '.priority')
        description=$(echo "$skill_json" | jq -r '.description')

        # Calculate confidence score
        # Components:
        # - Category match score (40%)
        # - Skill-specific keyword bonus (25%)
        # - Historical success rate (25%)
        # - Priority boost (10%)

        local keyword_bonus
        keyword_bonus=$(calculate_keyword_bonus "$keywords" "$skill_name")

        local historical_score
        historical_score=$(calculate_historical_score "$category" "$skill_name")

        local priority_score
        priority_score=$(awk "BEGIN {printf \"%.3f\", 1.0 / $priority}")

        local total_score
        total_score=$(awk "BEGIN {printf \"%.3f\", ($category_score * 0.40) + ($keyword_bonus * 0.25) + ($historical_score * 0.25) + ($priority_score * 0.10)}")

        # Add to recommendations
        recommendations=$(echo "$recommendations" | jq \
            --arg name "$skill_name" \
            --argjson score "$total_score" \
            --arg desc "$description" \
            '. += [{name: $name, confidence: $score, description: $desc}]')
    done <<< "$skills"

    # Sort by confidence descending
    echo "$recommendations" | jq 'sort_by(.confidence) | reverse'
}

# Calculate keyword bonus for specific skill
calculate_keyword_bonus() {
    local keywords="$1"
    local skill_name="$2"

    case "$skill_name" in
        homelab-deployment)
            if echo "$keywords" | grep -qE '(deploy|install|setup|new|stack|quadlet)' 2>/dev/null; then
                echo "1.0"
            else
                echo "0.4"
            fi
            ;;
        systematic-debugging)
            if echo "$keywords" | grep -qE '(error|fail|broken|debug|troubleshoot|bug|fix|issue)' 2>/dev/null; then
                echo "1.0"
            else
                echo "0.4"
            fi
            ;;
        homelab-intelligence)
            if echo "$keywords" | grep -qE '(health|status|check|analyze|recommend|intel|report)' 2>/dev/null; then
                echo "1.0"
            else
                echo "0.5"  # Intelligence is generally useful
            fi
            ;;
        git-advanced-workflows)
            if echo "$keywords" | grep -qE '(git|rebase|merge|conflict|cherry|bisect|reflog)' 2>/dev/null; then
                echo "1.0"
            else
                echo "0.3"
            fi
            ;;
        claude-code-analyzer)
            if echo "$keywords" | grep -qE '(claude|code|optimize|workflow|usage)' 2>/dev/null; then
                echo "1.0"
            else
                echo "0.3"
            fi
            ;;
        autonomous-operations)
            if echo "$keywords" | grep -qE '(autonomous|ooda|action|maintenance|operate)' 2>/dev/null; then
                echo "1.0"
            else
                echo "0.4"
            fi
            ;;
        *)
            echo "0.5"
            ;;
    esac
}

# Determine invocation strategy based on confidence
determine_invocation() {
    local confidence="$1"

    if awk "BEGIN {exit !($confidence >= 0.85)}"; then
        echo "auto"
    elif awk "BEGIN {exit !($confidence >= 0.60)}"; then
        echo "suggest"
    elif awk "BEGIN {exit !($confidence >= 0.40)}"; then
        echo "mention"
    else
        echo "none"
    fi
}

# Log skill usage
log_usage() {
    local skill="$1"
    local outcome="$2"
    local category="${3:-UNKNOWN}"
    local keywords="${4:-}"

    init_files

    local keywords_json="[]"
    if [[ -n "$keywords" ]]; then
        keywords_json=$(echo "$keywords" | jq -R -s -c 'split("\n") | map(select(length > 0))')
    fi

    local entry
    entry=$(jq -n \
        --arg ts "$(date -Iseconds)" \
        --arg cat "$category" \
        --arg skill "$skill" \
        --argjson kw "$keywords_json" \
        --arg outcome "$outcome" \
        '{timestamp: $ts, task_category: $cat, skill_used: $skill, task_keywords: $kw, outcome: $outcome}')

    # Update skill-usage.json
    local updated
    updated=$(jq --argjson entry "$entry" '
        .sessions += [$entry] |
        .statistics.total_invocations += 1 |
        .statistics.by_skill[$entry.skill_used] = ((.statistics.by_skill[$entry.skill_used] // 0) + 1) |
        .statistics.by_category[$entry.task_category] = ((.statistics.by_category[$entry.task_category] // 0) + 1) |
        .statistics.success_rate = (
            ([.sessions[] | select(.outcome == "success")] | length) /
            ([.sessions[]] | length)
        )
    ' "$SKILL_USAGE")

    echo "$updated" > "$SKILL_USAGE"
    echo "Logged: $skill ($outcome) for category $category"
}

# Show usage statistics
show_stats() {
    init_files

    echo -e "${CYAN}=== Skill Usage Statistics ===${NC}"
    echo ""

    local total
    total=$(jq -r '.statistics.total_invocations' "$SKILL_USAGE")
    echo -e "Total invocations: ${GREEN}$total${NC}"
    echo ""

    echo -e "${YELLOW}By Skill:${NC}"
    jq -r '.statistics.by_skill | to_entries | sort_by(.value) | reverse | .[] | "  \(.key): \(.value)"' "$SKILL_USAGE"
    echo ""

    echo -e "${YELLOW}By Category:${NC}"
    jq -r '.statistics.by_category | to_entries | sort_by(.value) | reverse | .[] | "  \(.key): \(.value)"' "$SKILL_USAGE"
    echo ""

    local success_rate
    success_rate=$(jq -r '.statistics.success_rate // 0' "$SKILL_USAGE")
    echo -e "Success rate: ${GREEN}$(awk "BEGIN {printf \"%.1f%%\", $success_rate * 100}")${NC}"
    echo ""

    echo -e "${YELLOW}Recent Sessions (last 5):${NC}"
    jq -r '.sessions | .[-5:] | reverse | .[] | "  \(.timestamp | split("T")[0]) - \(.skill_used) (\(.outcome))"' "$SKILL_USAGE"
}

# Output recommendation in JSON format
output_json() {
    local category="$1"
    local category_score="$2"
    local recommendations="$3"

    local top_skill top_confidence invocation
    top_skill=$(echo "$recommendations" | jq -r '.[0].name // null')
    top_confidence=$(echo "$recommendations" | jq -r '.[0].confidence // 0')
    invocation=$(determine_invocation "$top_confidence")

    jq -n \
        --arg category "$category" \
        --argjson category_score "$category_score" \
        --arg top_skill "$top_skill" \
        --argjson top_confidence "$top_confidence" \
        --arg invocation "$invocation" \
        --argjson recommendations "$recommendations" \
        '{
            category: $category,
            category_confidence: $category_score,
            top_recommendation: {
                skill: $top_skill,
                confidence: $top_confidence,
                invocation: $invocation
            },
            all_recommendations: $recommendations
        }'
}

# Output recommendation in human-readable format
output_human() {
    local category="$1"
    local category_score="$2"
    local recommendations="$3"

    local top_skill top_confidence top_desc invocation
    top_skill=$(echo "$recommendations" | jq -r '.[0].name // "none"')
    top_confidence=$(echo "$recommendations" | jq -r '.[0].confidence // 0')
    top_desc=$(echo "$recommendations" | jq -r '.[0].description // ""')
    invocation=$(determine_invocation "$top_confidence")

    local confidence_pct
    confidence_pct=$(awk "BEGIN {printf \"%.0f\", $top_confidence * 100}")

    echo -e "${CYAN}=== Skill Recommendation ===${NC}"
    echo ""
    echo -e "Task Category: ${YELLOW}$category${NC} ($(awk "BEGIN {printf \"%.0f\", $category_score * 100}")% match)"
    echo ""

    if [[ "$top_skill" == "none" || "$top_skill" == "null" ]]; then
        echo -e "${YELLOW}No skill recommendation for this task.${NC}"
        return 1
    fi

    # Color based on invocation strategy
    case "$invocation" in
        auto)
            echo -e "Recommended Skill: ${GREEN}$top_skill${NC} (${GREEN}${confidence_pct}%${NC} confidence)"
            echo -e "Invocation: ${GREEN}AUTO-INVOKE${NC} - Skill will be used automatically"
            ;;
        suggest)
            echo -e "Recommended Skill: ${YELLOW}$top_skill${NC} (${YELLOW}${confidence_pct}%${NC} confidence)"
            echo -e "Invocation: ${YELLOW}SUGGEST${NC} - Recommend using this skill"
            ;;
        mention)
            echo -e "Recommended Skill: ${BLUE}$top_skill${NC} (${BLUE}${confidence_pct}%${NC} confidence)"
            echo -e "Invocation: ${BLUE}MENTION${NC} - Consider using this skill"
            ;;
        *)
            echo -e "Recommended Skill: $top_skill (${confidence_pct}% confidence)"
            echo -e "Invocation: No strong recommendation"
            ;;
    esac

    echo -e "Description: $top_desc"
    echo ""

    # Show all recommendations
    local rec_count
    rec_count=$(echo "$recommendations" | jq 'length')

    if (( rec_count > 1 )); then
        echo -e "${YELLOW}All Recommendations:${NC}"
        echo "$recommendations" | jq -r '.[] | "  \(.name): \(.confidence * 100 | floor)% - \(.description)"'
        echo ""
    fi

    # If auto-invoke, output special marker for wrapper scripts
    if [[ "$invocation" == "auto" ]]; then
        echo "AUTO_INVOKE:$top_skill"
    fi
}

# Main function
main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                JSON_OUTPUT=true
                shift
                ;;
            --log)
                LOG_MODE=true
                shift
                if [[ $# -lt 2 ]]; then
                    echo "Usage: $0 --log <skill> <outcome> [category] [keywords]" >&2
                    exit 2
                fi
                log_usage "$1" "$2" "${3:-UNKNOWN}" "${4:-}"
                exit 0
                ;;
            --stats)
                STATS_MODE=true
                shift
                ;;
            -h|--help)
                cat <<EOF
Usage: $0 [OPTIONS] "user request"

Options:
  --json          Output in JSON format
  --log           Log skill usage: --log <skill> <outcome> [category] [keywords]
  --stats         Show usage statistics
  -h, --help      Show this help

Examples:
  $0 "Jellyfin won't start, seeing permission errors"
  $0 --json "Deploy a new wiki service"
  $0 --log systematic-debugging success DEBUGGING "jellyfin error"
  $0 --stats
EOF
                exit 0
                ;;
            -*)
                echo "Unknown option: $1" >&2
                exit 2
                ;;
            *)
                break
                ;;
        esac
    done

    if $STATS_MODE; then
        show_stats
        exit 0
    fi

    local user_request="$*"

    if [[ -z "$user_request" ]]; then
        echo "Usage: $0 [--json] \"user request\"" >&2
        exit 2
    fi

    init_files

    # 1. Extract keywords
    local keywords
    keywords=$(extract_keywords "$user_request")

    # 2. Classify task
    local classification
    classification=$(classify_task "$keywords")

    local category category_score
    category=$(echo "$classification" | cut -d'|' -f1)
    category_score=$(echo "$classification" | cut -d'|' -f2)

    # 3. Get recommendations
    local recommendations
    if [[ "$category" == "UNKNOWN" ]]; then
        recommendations="[]"
    else
        recommendations=$(get_skill_recommendations "$category" "$keywords" "$category_score")
    fi

    # 4. Output
    if $JSON_OUTPUT; then
        output_json "$category" "$category_score" "$recommendations"
    else
        output_human "$category" "$category_score" "$recommendations"
        if [[ "$category" == "UNKNOWN" ]]; then
            exit 1
        fi
    fi
}

# Only run main if script is executed (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
