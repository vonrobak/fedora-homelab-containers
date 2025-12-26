#!/usr/bin/env bash
#
# test-webhook-remediation.sh - Test Alertmanager → Webhook → Remediation integration
#
# Simulates an Alertmanager webhook payload and sends it to the remediation webhook handler
# to verify Phase 4 alert-driven remediation integration works end-to-end.
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Testing Webhook Remediation Integration${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check if webhook handler is running
echo -e "${YELLOW}[1/5] Checking webhook handler status...${NC}"
if systemctl --user is-active --quiet remediation-webhook.service; then
    echo -e "${GREEN}✓ Webhook handler is running${NC}"
else
    echo -e "${RED}✗ Webhook handler is not running${NC}"
    echo -e "${YELLOW}Start it with: systemctl --user start remediation-webhook.service${NC}"
    exit 1
fi
echo ""

# Test health endpoint
echo -e "${YELLOW}[2/5] Testing health endpoint...${NC}"
HEALTH=$(curl -s http://127.0.0.1:9096/health)
if echo "$HEALTH" | jq -e '.status == "healthy"' > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Health check passed: $HEALTH${NC}"
else
    echo -e "${RED}✗ Health check failed${NC}"
    exit 1
fi
echo ""

# Simulate Alertmanager webhook payload (SystemDiskSpaceCritical)
echo -e "${YELLOW}[3/5] Simulating SystemDiskSpaceCritical alert...${NC}"
echo -e "${CYAN}Expected: disk-cleanup playbook should be triggered${NC}"
echo ""

PAYLOAD=$(cat <<'EOF'
{
  "receiver": "remediation-webhook",
  "status": "firing",
  "alerts": [
    {
      "status": "firing",
      "labels": {
        "alertname": "SystemDiskSpaceCritical",
        "severity": "critical",
        "component": "system",
        "instance": "localhost",
        "mountpoint": "/"
      },
      "annotations": {
        "summary": "System disk space critically low",
        "description": "System SSD has only 18% free space. Immediate cleanup required!"
      },
      "startsAt": "2025-12-24T00:00:00.000Z",
      "endsAt": "0001-01-01T00:00:00Z",
      "generatorURL": "http://prometheus:9090/graph?g0.expr=...",
      "fingerprint": "test123456789"
    }
  ],
  "groupLabels": {
    "alertname": "SystemDiskSpaceCritical",
    "severity": "critical"
  },
  "commonLabels": {
    "alertname": "SystemDiskSpaceCritical",
    "severity": "critical"
  },
  "commonAnnotations": {
    "summary": "System disk space critically low"
  },
  "externalURL": "http://alertmanager:9093",
  "version": "4",
  "groupKey": "{}/{severity=\"critical\"}:{alertname=\"SystemDiskSpaceCritical\"}"
}
EOF
)

# Send webhook
RESPONSE=$(curl -s -X POST http://127.0.0.1:9096/webhook \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

echo -e "${BLUE}Webhook Response:${NC}"
echo "$RESPONSE" | jq '.'
echo ""

# Parse response
STATUS=$(echo "$RESPONSE" | jq -r '.status // "unknown"')
ALERTS_RECEIVED=$(echo "$RESPONSE" | jq -r '.alerts_received // 0')
FIRST_RESULT=$(echo "$RESPONSE" | jq -r '.results[0] // {}')

echo -e "${BLUE}Results:${NC}"
echo "  Status: $STATUS"
echo "  Alerts received: $ALERTS_RECEIVED"
echo ""

# Check result details
ACTION=$(echo "$FIRST_RESULT" | jq -r '.action // "unknown"')
PLAYBOOK=$(echo "$FIRST_RESULT" | jq -r '.playbook // "none"')
REASON=$(echo "$FIRST_RESULT" | jq -r '.reason // "none"')

echo -e "${BLUE}Action taken:${NC}"
echo "  Action: $ACTION"
echo "  Playbook: $PLAYBOOK"
echo "  Reason: $REASON"
echo ""

# Determine success
echo -e "${YELLOW}[4/5] Analyzing results...${NC}"

if [[ "$ACTION" == "executed" ]]; then
    RESULT=$(echo "$FIRST_RESULT" | jq -r '.result // "unknown"')
    echo -e "${GREEN}✅ SUCCESS: Remediation was executed!${NC}"
    echo "  Execution result: $RESULT"
elif [[ "$ACTION" == "escalate" ]]; then
    echo -e "${YELLOW}⚠️  ESCALATED: Remediation requires confirmation${NC}"
    echo "  This is expected for playbooks with requires_confirmation: true"
    echo "  or confidence <90%"
elif [[ "$ACTION" == "duplicate" ]]; then
    echo -e "${CYAN}ℹ️  DUPLICATE: Alert already processed recently (idempotency)${NC}"
    echo "  Webhook handler correctly prevented duplicate execution"
elif [[ "$ACTION" == "rate_limited" ]]; then
    echo -e "${YELLOW}⚠️  RATE LIMITED: Too many executions${NC}"
    echo "  Reason: $REASON"
else
    echo -e "${YELLOW}⚠️  OTHER: $ACTION${NC}"
    echo "  Reason: $REASON"
fi
echo ""

# Check webhook handler logs
echo -e "${YELLOW}[5/5] Recent webhook handler logs:${NC}"
journalctl --user -u remediation-webhook.service -n 20 --no-pager | grep -E "(INFO|WARNING|ERROR)" | tail -10
echo ""

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Test Complete${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${CYAN}Next steps:${NC}"
echo "  - Review decision log: ~/containers/.claude/context/decision-log.jsonl"
echo "  - Check metrics: ~/containers/data/backup-metrics/remediation.prom"
echo "  - Monitor real alerts in Alertmanager: http://alertmanager:9093"
