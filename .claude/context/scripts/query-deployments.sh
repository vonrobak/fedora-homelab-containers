#!/bin/bash
#
# query-deployments.sh
# Query deployment history by service, pattern, or method
#
# Usage: ./query-deployments.sh [--service NAME] [--pattern PAT] [--method METH]
#

set -euo pipefail

DEPLOY_FILE="../deployment-log.json"

# Parse arguments
SERVICE=""
PATTERN=""
METHOD=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --service)
            SERVICE="$2"
            shift 2
            ;;
        --pattern)
            PATTERN="$2"
            shift 2
            ;;
        --method)
            METHOD="$2"
            shift 2
            ;;
        *)
            echo "Usage: $0 [--service NAME] [--pattern PAT] [--method METH]"
            echo "Methods: pattern-based, manual quadlet, deploy script, multi-container stack, custom script"
            exit 1
            ;;
    esac
done

# Build jq filter
FILTER=".deployments[]"

if [[ -n "$SERVICE" ]]; then
    FILTER="$FILTER | select(.service == \"$SERVICE\")"
fi

if [[ -n "$PATTERN" ]]; then
    FILTER="$FILTER | select(.pattern_used == \"$PATTERN\")"
fi

if [[ -n "$METHOD" ]]; then
    FILTER="$FILTER | select(.deployment_method == \"$METHOD\")"
fi

# Execute query
if [[ ! -f "$DEPLOY_FILE" ]]; then
    echo "Error: Deployment log file not found: $DEPLOY_FILE"
    exit 1
fi

jq -r "$FILTER | \"\(.service): \(.pattern_used) (\(.memory_limit), \(.deployed_date))\"" "$DEPLOY_FILE"
