#!/bin/bash
# daily-drift-check.sh
# Automated daily configuration drift detection with Discord alerting
#
# Purpose:
#   - Run check-drift.sh daily to catch configuration drift early
#   - Alert to Discord if drift is detected
#   - Silent on success (no noise)
#
# Automation:
#   Timer: daily-drift-check.timer
#   Schedule: Daily at 06:00
#
# Integration:
#   Skill: homelab-deployment (uses check-drift.sh)
#
# Status: ACTIVE
# Created: 2025-11-28

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIFT_SCRIPT="${HOME}/containers/.claude/skills/homelab-deployment/scripts/check-drift.sh"
REPORT_DIR="${HOME}/containers/docs/99-reports"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Run drift check and capture output
DRIFT_OUTPUT=$(mktemp)
DRIFT_EXIT=0

if ! "$DRIFT_SCRIPT" > "$DRIFT_OUTPUT" 2>&1; then
    DRIFT_EXIT=$?
fi

# Parse results
DRIFT_COUNT=$(grep -c "✗ DRIFT" "$DRIFT_OUTPUT" 2>/dev/null || echo "0")
WARNING_COUNT=$(grep -c "⚠ WARNING" "$DRIFT_OUTPUT" 2>/dev/null || echo "0")

# Only alert if actual drift detected (not warnings)
if [[ "$DRIFT_COUNT" -gt 0 ]]; then
    echo "[$(date)] Drift detected in $DRIFT_COUNT service(s)"

    # Get Discord webhook from alert-discord-relay
    DISCORD_WEBHOOK=$(podman exec alert-discord-relay env 2>/dev/null | grep DISCORD_WEBHOOK_URL | cut -d= -f2 || echo "")

    if [[ -n "$DISCORD_WEBHOOK" ]]; then
        # Build drift summary
        DRIFT_SERVICES=$(grep "✗ DRIFT" "$DRIFT_OUTPUT" | head -5 || echo "Unknown")

        # Send Discord alert
        curl -s -H "Content-Type: application/json" \
            -d "{
                \"embeds\": [{
                    \"title\": \"⚠️ Configuration Drift Detected\",
                    \"description\": \"$DRIFT_COUNT service(s) have drifted from their quadlet definitions.\",
                    \"color\": 16744256,
                    \"fields\": [
                        {\"name\": \"Services with Drift\", \"value\": \"\`\`\`$DRIFT_SERVICES\`\`\`\", \"inline\": false},
                        {\"name\": \"Action Required\", \"value\": \"Run \`systemctl --user restart <service>\` to reconcile\", \"inline\": false}
                    ],
                    \"footer\": {\"text\": \"Daily Drift Check • $(date '+%Y-%m-%d %H:%M')\"}
                }]
            }" \
            "$DISCORD_WEBHOOK" > /dev/null 2>&1 || echo "Warning: Discord notification failed"
    fi

    # Save report
    cp "$DRIFT_OUTPUT" "$REPORT_DIR/drift-check-$TIMESTAMP.txt"
    echo "Report saved to: $REPORT_DIR/drift-check-$TIMESTAMP.txt"
fi

# Cleanup
rm -f "$DRIFT_OUTPUT"

# Exit with drift status (for monitoring)
exit $DRIFT_EXIT
