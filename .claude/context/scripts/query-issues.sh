#!/bin/bash
#
# query-issues.sh
# Query issue history by category, severity, or status
#
# Usage: ./query-issues.sh [--category CAT] [--severity SEV] [--status STATUS]
#

set -euo pipefail

ISSUE_FILE="../issue-history.json"

# Parse arguments
CATEGORY=""
SEVERITY=""
STATUS=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --category)
            CATEGORY="$2"
            shift 2
            ;;
        --severity)
            SEVERITY="$2"
            shift 2
            ;;
        --status|--outcome)
            STATUS="$2"
            shift 2
            ;;
        *)
            echo "Usage: $0 [--category CAT] [--severity SEV] [--status STATUS]"
            echo "Categories: disk-space, deployment, authentication, scripting, monitoring, performance, ssl, media, architecture, operations"
            echo "Severities: critical, high, medium, low"
            echo "Statuses: resolved, ongoing, mitigated, investigating"
            exit 1
            ;;
    esac
done

# Build jq filter
FILTER=".issues[]"

if [[ -n "$CATEGORY" ]]; then
    FILTER="$FILTER | select(.category == \"$CATEGORY\")"
fi

if [[ -n "$SEVERITY" ]]; then
    FILTER="$FILTER | select(.severity == \"$SEVERITY\")"
fi

if [[ -n "$STATUS" ]]; then
    FILTER="$FILTER | select(.outcome == \"$STATUS\")"
fi

# Execute query
if [[ ! -f "$ISSUE_FILE" ]]; then
    echo "Error: Issue history file not found: $ISSUE_FILE"
    exit 1
fi

jq -r "$FILTER | \"[\(.id)] \(.title) (\(.severity), \(.outcome))\"" "$ISSUE_FILE"
