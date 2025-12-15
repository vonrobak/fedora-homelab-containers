#!/bin/bash
# post-update-health-check.sh
# Post-Update Service Validation and Notification
#
# Purpose: Verify services are healthy after auto-update
# Sends Discord notification with results

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo "═══════════════════════════════════════════════"
echo "     POST-UPDATE HEALTH CHECK"
echo "═══════════════════════════════════════════════"
echo ""

# Log update timestamp
echo "$(date -Iseconds)" > /home/patriark/containers/data/last-auto-update.log

CHECKS_FAILED=0
FAILED_SERVICES=""

# Give services time to start
echo "Waiting 30 seconds for services to stabilize..."
sleep 30

# Check critical services
echo "Checking service health..."
CRITICAL_SERVICES=(
    "traefik.service"
    "authelia.service"
    "immich-server.service"
    "prometheus.service"
    "grafana.service"
)

for service in "${CRITICAL_SERVICES[@]}"; do
    echo -n "  $service... "
    if systemctl --user is-active --quiet "$service"; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        CHECKS_FAILED=$((CHECKS_FAILED + 1))
        FAILED_SERVICES="${FAILED_SERVICES}\n- ${service}"
    fi
done

# Check container health checks
echo ""
echo "Checking container health..."
HEALTH_CHECK_CONTAINERS=(
    "traefik"
    "immich-server"
)

for container in "${HEALTH_CHECK_CONTAINERS[@]}"; do
    echo -n "  $container... "
    if podman healthcheck run "$container" >/dev/null 2>&1; then
        echo -e "${GREEN}HEALTHY${NC}"
    else
        echo -e "${YELLOW}WARN${NC} (health check failed or not configured)"
    fi
done

# Send Discord notification
echo ""
echo "Sending Discord notification..."

DISCORD_WEBHOOK=$(podman exec alert-discord-relay env 2>/dev/null | grep DISCORD_WEBHOOK_URL | cut -d= -f2 || echo "")

if [ -n "$DISCORD_WEBHOOK" ]; then
    if [ "$CHECKS_FAILED" -eq 0 ]; then
        # Success notification
        PAYLOAD='{
  "embeds": [{
    "title": "✅ Auto-Update Completed",
    "description": "Container auto-update completed successfully. All services are healthy.",
    "color": 5763719,
    "fields": [
      {
        "name": "Status",
        "value": "All critical services running",
        "inline": true
      },
      {
        "name": "Timestamp",
        "value": "'"$(date '+%Y-%m-%d %H:%M:%S')"'",
        "inline": true
      }
    ],
    "footer": {
      "text": "Homelab Operations • Next vulnerability scan: Today 06:00"
    },
    "timestamp": "'"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"'"
  }]
}'
    else
        # Failure notification
        PAYLOAD='{
  "embeds": [{
    "title": "⚠️ Auto-Update: Service Issues Detected",
    "description": "Container auto-update completed but some services failed health checks.",
    "color": 16753920,
    "fields": [
      {
        "name": "Failed Services",
        "value": "'"${FAILED_SERVICES}"'",
        "inline": false
      },
      {
        "name": "Action Required",
        "value": "Check service logs: `journalctl --user -u <service> -n 50`",
        "inline": false
      }
    ],
    "footer": {
      "text": "Homelab Operations • Manual intervention may be required"
    },
    "timestamp": "'"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"'"
  }]
}'
    fi

    curl -s -o /dev/null \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" \
        "$DISCORD_WEBHOOK"

    echo -e "${GREEN}Discord notification sent${NC}"
else
    echo -e "${YELLOW}Discord webhook not found, skipping notification${NC}"
fi

# Summary
echo ""
if [ "$CHECKS_FAILED" -gt 0 ]; then
    echo -e "${RED}Post-update health check found ${CHECKS_FAILED} issues${NC}"
    echo "Please investigate failed services"
    exit 1
else
    echo -e "${GREEN}Post-update health check PASSED${NC}"
    echo "All services are healthy"
    exit 0
fi
