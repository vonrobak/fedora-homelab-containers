#!/usr/bin/env bash
#
# query-decisions.sh - Query the autonomous operations decision log
#
# Usage:
#   ./query-decisions.sh                    # Show last 10 decisions
#   ./query-decisions.sh --last 7d          # Show decisions from last 7 days
#   ./query-decisions.sh --pending          # Show pending actions
#   ./query-decisions.sh --type disk-cleanup # Filter by action type
#   ./query-decisions.sh --outcome failure  # Filter by outcome
#   ./query-decisions.sh --stats            # Show statistics
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTEXT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DECISION_LOG="$CONTEXT_DIR/decision-log.json"
STATE_FILE="$CONTEXT_DIR/autonomous-state.json"

# Defaults
LIMIT=10
PERIOD=""
ACTION_TYPE=""
OUTCOME=""
SHOW_PENDING=false
SHOW_STATS=false

##############################################################################
# Argument Parsing
##############################################################################

while [[ $# -gt 0 ]]; do
    case $1 in
        --last)
            PERIOD="$2"
            shift 2
            ;;
        --limit)
            LIMIT="$2"
            shift 2
            ;;
        --type)
            ACTION_TYPE="$2"
            shift 2
            ;;
        --outcome)
            OUTCOME="$2"
            shift 2
            ;;
        --pending)
            SHOW_PENDING=true
            shift
            ;;
        --stats)
            SHOW_STATS=true
            shift
            ;;
        --help|-h)
            cat << EOF
Usage: $0 [OPTIONS]

Query the autonomous operations decision log.

Options:
  --last PERIOD      Show decisions from last period (e.g., 7d, 24h, 1w)
  --limit N          Limit results to N entries (default: 10)
  --type TYPE        Filter by action type (disk-cleanup, service-restart, etc.)
  --outcome STATUS   Filter by outcome (success, failure, skipped)
  --pending          Show pending actions from state
  --stats            Show statistics summary
  --help, -h         Show this help

Examples:
  $0 --last 7d                     # Decisions from last 7 days
  $0 --type service-restart        # Only service restart decisions
  $0 --outcome failure             # Only failed actions
  $0 --stats                       # Summary statistics
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

##############################################################################
# Helper Functions
##############################################################################

period_to_seconds() {
    local period=$1
    local value=${period%[dhwm]}
    local unit=${period: -1}

    case $unit in
        h) echo $((value * 3600)) ;;
        d) echo $((value * 86400)) ;;
        w) echo $((value * 604800)) ;;
        m) echo $((value * 2592000)) ;;  # 30 days
        *) echo $((value * 86400)) ;;  # Default to days
    esac
}

##############################################################################
# Main
##############################################################################

if [[ ! -f "$DECISION_LOG" ]]; then
    echo "No decision log found at: $DECISION_LOG"
    exit 0
fi

# Show pending actions
if $SHOW_PENDING; then
    echo "=== Pending Actions ==="
    if [[ -f "$STATE_FILE" ]]; then
        jq -r '.pending_actions[] | "[\(.id)] \(.type): \(.reason) (confidence: \(.confidence))"' "$STATE_FILE" 2>/dev/null || echo "(none)"
    else
        echo "(no state file)"
    fi
    exit 0
fi

# Show statistics
if $SHOW_STATS; then
    echo "=== Decision Statistics ==="
    echo ""

    local total success failure
    total=$(jq '.decisions | length' "$DECISION_LOG")
    success=$(jq '[.decisions[] | select(.outcome == "success")] | length' "$DECISION_LOG")
    failure=$(jq '[.decisions[] | select(.outcome == "failure")] | length' "$DECISION_LOG")

    echo "Total Decisions:  $total"
    echo "Successful:       $success"
    echo "Failed:           $failure"

    if (( total > 0 )); then
        echo "Success Rate:     $(awk "BEGIN {printf \"%.1f%%\", ($success / $total) * 100}")"
    fi

    echo ""
    echo "=== By Action Type ==="
    jq -r '.decisions | group_by(.action_type) | .[] | "\(.[0].action_type): \(length)"' "$DECISION_LOG" 2>/dev/null || echo "(none)"

    echo ""
    echo "=== Recent Activity (last 7 days) ==="
    local cutoff
    cutoff=$(date -d "7 days ago" -Iseconds)
    jq -r --arg cutoff "$cutoff" '[.decisions[] | select(.timestamp > $cutoff)] | length' "$DECISION_LOG" 2>/dev/null
    echo "decisions in last 7 days"

    exit 0
fi

# Build jq filter
filter='.decisions'

# Time filter
if [[ -n "$PERIOD" ]]; then
    seconds=$(period_to_seconds "$PERIOD")
    cutoff=$(date -d "$seconds seconds ago" -Iseconds)
    filter="$filter | map(select(.timestamp > \"$cutoff\"))"
fi

# Type filter
if [[ -n "$ACTION_TYPE" ]]; then
    filter="$filter | map(select(.action_type == \"$ACTION_TYPE\"))"
fi

# Outcome filter
if [[ -n "$OUTCOME" ]]; then
    filter="$filter | map(select(.outcome == \"$OUTCOME\"))"
fi

# Apply limit (get last N entries)
filter="$filter | .[-$LIMIT:]"

# Output format
filter="$filter | .[] | \"[\(.timestamp)] \(.action_type): \(.outcome) - \(.details // \"no details\")\""

echo "=== Decision Log ==="
jq -r "$filter" "$DECISION_LOG" 2>/dev/null || echo "(no matching decisions)"
