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

# Write status to daily digest directory (consolidated Discord notification)
DIGEST_DIR="/tmp/daily-digest"
mkdir -p "$DIGEST_DIR"

if [[ "$DRIFT_COUNT" -gt 0 ]]; then
    echo "[$(date)] Drift detected in $DRIFT_COUNT service(s)"
    DRIFT_SERVICES=$(grep "✗ DRIFT" "$DRIFT_OUTPUT" | head -5 || echo "Unknown")

    cat > "$DIGEST_DIR/drift-check.json" <<EOF
{
  "status": "drift_detected",
  "drift_count": $DRIFT_COUNT,
  "warning_count": $WARNING_COUNT,
  "services": $(echo "$DRIFT_SERVICES" | jq -Rs '.')
}
EOF

    # Save report
    cp "$DRIFT_OUTPUT" "$REPORT_DIR/drift-check-$TIMESTAMP.txt"
    echo "Report saved to: $REPORT_DIR/drift-check-$TIMESTAMP.txt"
else
    cat > "$DIGEST_DIR/drift-check.json" <<EOF
{
  "status": "ok",
  "drift_count": 0,
  "warning_count": $WARNING_COUNT
}
EOF
fi

# Cleanup
rm -f "$DRIFT_OUTPUT"

# Exit with drift status (for monitoring)
exit $DRIFT_EXIT
