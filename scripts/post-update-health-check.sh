#!/bin/bash
# post-update-health-check.sh
# Post-Update Service Validation and Notification
#
# Purpose: Verify services are healthy after auto-update
# Includes Nextcloud-specific DB upgrade detection and auto-remediation
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
NC_UPGRADE_PERFORMED=""

# Give services time to start
echo "Waiting 30 seconds for services to stabilize..."
sleep 30

# Check critical services
echo "Checking service health..."
CRITICAL_SERVICES=(
    "traefik.service"
    "authelia.service"
    "nextcloud.service"
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
    "nextcloud"
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

# Nextcloud-specific: check for pending DB upgrade
# Race condition: podman auto-update restarts Nextcloud and MariaDB simultaneously.
# The entrypoint rsync's version.php BEFORE running occ upgrade. If MariaDB isn't
# ready yet, occ upgrade fails but version.php is already updated, making the failure
# unrecoverable on subsequent restarts. We detect and auto-remediate this here.
echo ""
echo "Checking Nextcloud database upgrade status..."
if systemctl --user is-active --quiet nextcloud.service; then
    NC_STATUS=$(podman exec -u www-data nextcloud php occ status --output=json 2>/dev/null || echo '{}')
    NEEDS_UPGRADE=$(echo "$NC_STATUS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('needsDbUpgrade', False))" 2>/dev/null || echo "Unknown")

    if [ "$NEEDS_UPGRADE" = "True" ]; then
        echo -e "  needsDbUpgrade: ${YELLOW}TRUE${NC} — attempting auto-remediation..."

        # Wait for MariaDB to accept connections (up to 60 seconds)
        DB_READY=false
        for i in $(seq 1 12); do
            if podman exec nextcloud-db healthcheck 2>/dev/null || podman healthcheck run nextcloud-db >/dev/null 2>&1; then
                DB_READY=true
                break
            fi
            echo "  Waiting for MariaDB... (attempt $i/12)"
            sleep 5
        done

        if [ "$DB_READY" = true ]; then
            echo "  MariaDB is ready, running occ upgrade..."
            if podman exec -u www-data nextcloud php occ upgrade 2>&1; then
                echo -e "  ${GREEN}Nextcloud DB upgrade completed successfully${NC}"
                NC_UPGRADE_PERFORMED="auto-remediated"
            else
                echo -e "  ${RED}Nextcloud DB upgrade FAILED${NC}"
                CHECKS_FAILED=$((CHECKS_FAILED + 1))
                FAILED_SERVICES="${FAILED_SERVICES}\n- nextcloud (DB upgrade failed)"
                NC_UPGRADE_PERFORMED="failed"
            fi
        else
            echo -e "  ${RED}MariaDB not ready after 60 seconds, cannot run occ upgrade${NC}"
            CHECKS_FAILED=$((CHECKS_FAILED + 1))
            FAILED_SERVICES="${FAILED_SERVICES}\n- nextcloud (DB upgrade pending, MariaDB unreachable)"
            NC_UPGRADE_PERFORMED="failed-db-unreachable"
        fi
    elif [ "$NEEDS_UPGRADE" = "False" ]; then
        echo -e "  needsDbUpgrade: ${GREEN}false${NC}"
    else
        echo -e "  ${YELLOW}Could not determine upgrade status${NC}"
    fi
else
    echo -e "  ${YELLOW}Nextcloud not running, skipping DB upgrade check${NC}"
fi

# Send Discord notification
echo ""
echo "Sending Discord notification..."

DISCORD_WEBHOOK=$(podman exec alert-discord-relay env 2>/dev/null | grep DISCORD_WEBHOOK_URL | cut -d= -f2 || echo "")

if [ -n "$DISCORD_WEBHOOK" ]; then
    # Build extra fields for Nextcloud upgrade if it happened
    NC_FIELD=""
    if [ -n "$NC_UPGRADE_PERFORMED" ]; then
        if [ "$NC_UPGRADE_PERFORMED" = "auto-remediated" ]; then
            NC_FIELD=',{"name":"Nextcloud","value":"DB upgrade auto-remediated after auto-update race condition","inline":false}'
        else
            NC_FIELD=',{"name":"Nextcloud","value":"DB upgrade FAILED: '"$NC_UPGRADE_PERFORMED"'","inline":false}'
        fi
    fi

    if [ "$CHECKS_FAILED" -eq 0 ]; then
        # Success notification
        PAYLOAD='{
  "embeds": [{
    "title": "Auto-Update Completed",
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
      }'"$NC_FIELD"'
    ],
    "footer": {
      "text": "Homelab Operations"
    },
    "timestamp": "'"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"'"
  }]
}'
    else
        # Failure notification
        PAYLOAD='{
  "embeds": [{
    "title": "Auto-Update: Service Issues Detected",
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
      }'"$NC_FIELD"'
    ],
    "footer": {
      "text": "Homelab Operations - Manual intervention may be required"
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
