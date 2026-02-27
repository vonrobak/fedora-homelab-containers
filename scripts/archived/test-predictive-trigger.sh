#!/usr/bin/env bash
#
# test-predictive-trigger.sh - Test predictive maintenance integration
#
# Temporarily overrides predict-resource-exhaustion.sh to inject a critical forecast
# and verify that autonomous-check.sh triggers predictive-maintenance action.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREDICT_SCRIPT="$SCRIPT_DIR/predictive-analytics/predict-resource-exhaustion.sh"
PREDICT_BACKUP="$PREDICT_SCRIPT.backup-test"
AUTONOMOUS_CHECK="$SCRIPT_DIR/autonomous-check.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

cleanup() {
    # Restore original script
    if [[ -f "$PREDICT_BACKUP" ]]; then
        mv "$PREDICT_BACKUP" "$PREDICT_SCRIPT"
        echo -e "${GREEN}✓ Restored original prediction script${NC}"
    fi
}

trap cleanup EXIT

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Testing Predictive Maintenance Trigger${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Backup original script
echo -e "${YELLOW}[1/4] Backing up prediction script...${NC}"
cp "$PREDICT_SCRIPT" "$PREDICT_BACKUP"
chmod +x "$PREDICT_BACKUP"
echo -e "${GREEN}✓ Backed up to $PREDICT_BACKUP${NC}"
echo ""

# Create mock script that returns critical forecast
echo -e "${YELLOW}[2/4] Creating mock prediction script with critical forecast...${NC}"
cat > "$PREDICT_SCRIPT" << 'EOF'
#!/usr/bin/env bash
# Mock prediction script for testing - returns critical forecast

# Check for --output json flag
if [[ "${1:-}" == "--output" && "${2:-}" == "json" ]]; then
    cat << 'JSONEOF'
{
  "resource": "disk",
  "mountpoint": "/",
  "current_usage_pct": 75.0,
  "forecast_7d_pct": 92.5,
  "trend_gb_per_day": 5.2,
  "days_until_90pct": "5",
  "confidence": 0.85,
  "severity": "critical",
  "recommendation": "Predicted to reach 90% in 5 days. Immediate action recommended."
}
JSONEOF
else
    # Human-readable output
    echo "Resource: disk"
    echo "Current: 75.0%"
    echo "7-day forecast: 92.5%"
    echo "Severity: CRITICAL"
    echo "Days until 90%: 5"
    echo "Confidence: 0.85"
fi
EOF

chmod +x "$PREDICT_SCRIPT"
echo -e "${GREEN}✓ Mock script created (critical: disk at 92.5% in 7 days, confidence 0.85)${NC}"
echo ""

# Run autonomous-check
echo -e "${YELLOW}[3/4] Running autonomous-check.sh...${NC}"
echo -e "${CYAN}Expected: predictive-maintenance action should be recommended${NC}"
echo ""

RESULT=$("$AUTONOMOUS_CHECK" --json 2>/dev/null || echo '{}')

# Parse results
STATUS=$(echo "$RESULT" | jq -r '.status // "unknown"' 2>/dev/null || echo "unknown")
ACTIONS_COUNT=$(echo "$RESULT" | jq '.recommended_actions | length' 2>/dev/null || echo "0")
PREDICTIVE_ACTION=$(echo "$RESULT" | jq '.recommended_actions[]? | select(.type == "predictive-maintenance")' 2>/dev/null || echo "")

echo -e "${BLUE}Results:${NC}"
echo "  Status: $STATUS"
echo "  Total actions recommended: $ACTIONS_COUNT"
echo ""

# Check if predictive-maintenance action was triggered
if [[ -n "$PREDICTIVE_ACTION" ]]; then
    echo -e "${GREEN}✅ SUCCESS: Predictive maintenance action triggered!${NC}"
    echo ""
    echo -e "${BLUE}Action details:${NC}"
    echo "$PREDICTIVE_ACTION" | jq '{
        type,
        reason,
        confidence,
        prediction_confidence,
        resource,
        forecast,
        risk,
        decision,
        priority
    }'
else
    echo -e "${RED}❌ FAILURE: Predictive maintenance action NOT triggered${NC}"
    echo ""
    echo -e "${YELLOW}All recommended actions:${NC}"
    echo "$RESULT" | jq '.recommended_actions'
fi

echo ""
echo -e "${YELLOW}[4/4] Cleaning up (restoring original script)...${NC}"
# Cleanup happens in trap

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Test Complete${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
