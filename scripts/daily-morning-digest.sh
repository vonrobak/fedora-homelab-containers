#!/bin/bash
# daily-morning-digest.sh — Consolidated morning Discord notification
#
# Collects status files from drift check, resource forecast, autonomous ops,
# and error digest into a single Discord message.
#
# Timer: daily-morning-digest.timer
# Schedule: Daily at 07:15 (after all morning scripts complete)
# Status: ACTIVE
# Created: 2026-02-27

set -uo pipefail

DIGEST_DIR="/tmp/daily-digest"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Get Discord webhook
DISCORD_WEBHOOK=$(podman exec alert-discord-relay env 2>/dev/null | grep DISCORD_WEBHOOK_URL | cut -d= -f2 || echo "")

if [[ -z "$DISCORD_WEBHOOK" ]]; then
    echo "[$(date)] No Discord webhook available, skipping digest"
    exit 0
fi

# Read status files (gracefully handle missing)
read_status() {
    local file="$DIGEST_DIR/$1"
    if [[ -f "$file" ]]; then
        cat "$file"
    else
        echo '{"status": "no_data"}'
    fi
}

DRIFT=$(read_status "drift-check.json")
FORECAST=$(read_status "resource-forecast.json")
AUTONOMOUS=$(read_status "autonomous-ops.json")
ERRORS=$(read_status "error-digest.json")

# Determine if anything needs attention
DRIFT_STATUS=$(echo "$DRIFT" | jq -r '.status // "no_data"')
FORECAST_STATUS=$(echo "$FORECAST" | jq -r '.status // "no_data"')
AUTONOMOUS_STATUS=$(echo "$AUTONOMOUS" | jq -r '.status // "no_data"')
ERROR_STATUS=$(echo "$ERRORS" | jq -r '.status // "no_data"')

# Count issues
ISSUE_COUNT=0
[[ "$DRIFT_STATUS" == "drift_detected" ]] && ((ISSUE_COUNT++)) || true
[[ "$FORECAST_STATUS" == "critical" || "$FORECAST_STATUS" == "warning" ]] && ((ISSUE_COUNT++)) || true
[[ "$AUTONOMOUS_STATUS" == "failures" || "$AUTONOMOUS_STATUS" == "executed" ]] && ((ISSUE_COUNT++)) || true
[[ "$ERROR_STATUS" == "critical" || "$ERROR_STATUS" == "warning" ]] && ((ISSUE_COUNT++)) || true

# Build status lines
build_line() {
    local component=$1 status=$2
    case "$status" in
        ok|none|no_data) echo "  $component: OK" ;;
        *) echo "  $component: needs attention" ;;
    esac
}

# Determine embed color and title
if [[ "$ISSUE_COUNT" -eq 0 ]]; then
    EMBED_COLOR=3066993   # Green
    TITLE="Daily Morning Digest — All Clear"
    # On fully quiet days, skip Discord entirely to avoid noise
    echo "[$(date)] All systems healthy, no digest needed"
    rm -rf "$DIGEST_DIR"
    exit 0
else
    if [[ "$FORECAST_STATUS" == "critical" || "$ERROR_STATUS" == "critical" || "$AUTONOMOUS_STATUS" == "failures" ]]; then
        EMBED_COLOR=15158332  # Red
        TITLE="Daily Morning Digest — $ISSUE_COUNT issue(s) need attention"
    else
        EMBED_COLOR=16744256  # Orange
        TITLE="Daily Morning Digest — $ISSUE_COUNT item(s) to review"
    fi
fi

# Build Discord fields
FIELDS="["

# Drift check field
if [[ "$DRIFT_STATUS" == "drift_detected" ]]; then
    DRIFT_COUNT=$(echo "$DRIFT" | jq -r '.drift_count // 0')
    FIELDS+="{\"name\": \"Config Drift\", \"value\": \"$DRIFT_COUNT service(s) drifted. Run check-drift.sh for details.\", \"inline\": false},"
fi

# Resource forecast field
if [[ "$FORECAST_STATUS" == "critical" || "$FORECAST_STATUS" == "warning" ]]; then
    DISK_DAYS=$(echo "$FORECAST" | jq -r '.days_until_exhaustion // "?"')
    DISK_USAGE=$(echo "$FORECAST" | jq -r '.disk_usage // "?"')
    DISK_AVAIL=$(echo "$FORECAST" | jq -r '.disk_available // "?"')
    LEVEL_EMOJI=$([[ "$FORECAST_STATUS" == "critical" ]] && echo "CRITICAL" || echo "Warning")
    FIELDS+="{\"name\": \"Resource Forecast ($LEVEL_EMOJI)\", \"value\": \"Disk exhaustion in ~$DISK_DAYS days. Currently $DISK_USAGE used, $DISK_AVAIL available.\", \"inline\": false},"
fi

# Autonomous ops field
if [[ "$AUTONOMOUS_STATUS" == "executed" || "$AUTONOMOUS_STATUS" == "failures" ]]; then
    AUTO_ACTIONS=$(echo "$AUTONOMOUS" | jq -r '.actions_taken // 0')
    AUTO_SUCCESS=$(echo "$AUTONOMOUS" | jq -r '.success // 0')
    AUTO_FAIL=$(echo "$AUTONOMOUS" | jq -r '.failures // 0')
    FIELDS+="{\"name\": \"Autonomous Operations\", \"value\": \"$AUTO_ACTIONS action(s): $AUTO_SUCCESS success, $AUTO_FAIL failed.\", \"inline\": false},"
fi

# Error digest field
if [[ "$ERROR_STATUS" == "critical" || "$ERROR_STATUS" == "warning" ]]; then
    TOTAL_ERRORS=$(echo "$ERRORS" | jq -r '.total_errors // 0')
    ERROR_SUMMARY=$(echo "$ERRORS" | jq -r '.summary // "unknown"')
    FIELDS+="{\"name\": \"Error Digest (24h)\", \"value\": \"$TOTAL_ERRORS total errors. Breakdown: $ERROR_SUMMARY\", \"inline\": false},"
fi

# Remove trailing comma and close
FIELDS="${FIELDS%,}]"

# Build payload
PAYLOAD=$(jq -n \
    --arg title "$TITLE" \
    --argjson color "$EMBED_COLOR" \
    --argjson fields "$FIELDS" \
    --arg footer "Daily Morning Digest • $(date '+%Y-%m-%d %H:%M')" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" \
    '{
      embeds: [{
        title: $title,
        color: $color,
        fields: $fields,
        footer: { text: $footer },
        timestamp: $ts
      }]
    }')

# Send to Discord
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "$DISCORD_WEBHOOK")

if echo "$HTTP_CODE" | grep -q "^20"; then
    echo "[$(date)] Daily morning digest sent to Discord (HTTP $HTTP_CODE)"
else
    echo "[$(date)] Failed to send digest to Discord (HTTP $HTTP_CODE)"
fi

# Cleanup digest directory
rm -rf "$DIGEST_DIR"

exit 0
