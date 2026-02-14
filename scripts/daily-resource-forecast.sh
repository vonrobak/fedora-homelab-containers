#!/bin/bash
# daily-resource-forecast.sh
# Automated daily resource exhaustion prediction with Discord alerting
#
# Purpose:
#   - Run predict-resource-exhaustion.sh daily
#   - Alert to Discord if exhaustion predicted within 14 days
#   - Provides proactive capacity planning
#
# Automation:
#   Timer: daily-resource-forecast.timer
#   Schedule: Daily at 06:05 (after drift check)
#
# Integration:
#   Skill: homelab-intelligence (predictive analytics)
#
# Status: ACTIVE
# Created: 2025-11-28

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREDICT_SCRIPT="${SCRIPT_DIR}/predictive-analytics/predict-resource-exhaustion.sh"
REPORT_DIR="${HOME}/containers/docs/99-reports"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Thresholds for alerting (days until exhaustion)
CRITICAL_DAYS=7
WARNING_DAYS=14

# Run prediction and capture JSON output
PREDICT_OUTPUT=$(mktemp)

# Capture only stdout (JSON), discard stderr (log messages)
if ! "$PREDICT_SCRIPT" --output json 2>/dev/null > "$PREDICT_OUTPUT"; then
    echo "[$(date)] Warning: Prediction script had errors"
fi

# Parse disk prediction (correct field name is days_until_90pct, not days_until_critical)
DISK_DAYS=$(jq -r '.days_until_90pct // "999"' "$PREDICT_OUTPUT" 2>/dev/null || echo "999")

# Validate DISK_DAYS is a positive integer (prediction can return "never", empty, or non-numeric)
if ! [[ "$DISK_DAYS" =~ ^[0-9]+$ ]]; then
    DISK_DAYS="999"
fi

# Determine alert level
ALERT_LEVEL="none"
ALERT_COLOR=3066993  # Green

if [[ "$DISK_DAYS" -lt 999 ]]; then
    if [[ "$DISK_DAYS" -le "$CRITICAL_DAYS" ]]; then
        ALERT_LEVEL="critical"
        ALERT_COLOR=15158332  # Red
    elif [[ "$DISK_DAYS" -le "$WARNING_DAYS" ]]; then
        ALERT_LEVEL="warning"
        ALERT_COLOR=16744256  # Orange
    fi
fi

# Only alert if warning or critical
if [[ "$ALERT_LEVEL" != "none" ]]; then
    echo "[$(date)] Resource exhaustion predicted within $DISK_DAYS days"

    # Get Discord webhook
    DISCORD_WEBHOOK=$(podman exec alert-discord-relay env 2>/dev/null | grep DISCORD_WEBHOOK_URL | cut -d= -f2 || echo "")

    if [[ -n "$DISCORD_WEBHOOK" ]]; then
        # Get current disk usage
        DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}')
        DISK_AVAIL=$(df -h / | awk 'NR==2 {print $4}')

        # Determine emoji and title based on level
        if [[ "$ALERT_LEVEL" == "critical" ]]; then
            EMOJI="🚨"
            TITLE="Critical: Disk Exhaustion in $DISK_DAYS Days"
        else
            EMOJI="⚠️"
            TITLE="Warning: Disk Exhaustion in $DISK_DAYS Days"
        fi

        # Send Discord alert
        curl -s -H "Content-Type: application/json" \
            -d "{
                \"embeds\": [{
                    \"title\": \"$EMOJI $TITLE\",
                    \"description\": \"Based on current growth trends, the system disk will reach critical capacity.\",
                    \"color\": $ALERT_COLOR,
                    \"fields\": [
                        {\"name\": \"Current Usage\", \"value\": \"$DISK_USAGE used\", \"inline\": true},
                        {\"name\": \"Available\", \"value\": \"$DISK_AVAIL\", \"inline\": true},
                        {\"name\": \"Days Until Critical\", \"value\": \"$DISK_DAYS\", \"inline\": true},
                        {\"name\": \"Recommended Action\", \"value\": \"Run \`./scripts/maintenance-cleanup.sh\` or review large files\", \"inline\": false}
                    ],
                    \"footer\": {\"text\": \"Daily Resource Forecast • $(date '+%Y-%m-%d %H:%M')\"}
                }]
            }" \
            "$DISCORD_WEBHOOK" > /dev/null 2>&1 || echo "Warning: Discord notification failed"
    fi

    # Save report
    cp "$PREDICT_OUTPUT" "$REPORT_DIR/resource-forecast-$TIMESTAMP.json"
    echo "Report saved to: $REPORT_DIR/resource-forecast-$TIMESTAMP.json"
fi

# Cleanup
rm -f "$PREDICT_OUTPUT"

# Exit 0 for info, 1 for warning, 2 for critical
case "$ALERT_LEVEL" in
    critical) exit 2 ;;
    warning) exit 1 ;;
    *) exit 0 ;;
esac
