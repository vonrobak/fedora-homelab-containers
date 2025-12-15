#!/bin/bash
# pre-update-health-check.sh
# Pre-Update System Health Validation
#
# Purpose: Verify system is healthy before running auto-updates
# Exit codes: 0 = healthy, 1 = unhealthy (aborts update)

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "═══════════════════════════════════════════════"
echo "     PRE-UPDATE HEALTH CHECK"
echo "═══════════════════════════════════════════════"
echo ""

CHECKS_FAILED=0

# Check 1: Disk space (system SSD)
echo -n "Checking disk space (system SSD)... "
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 80 ]; then
    echo -e "${RED}FAIL${NC} (${DISK_USAGE}% used)"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
else
    echo -e "${GREEN}OK${NC} (${DISK_USAGE}% used)"
fi

# Check 2: Memory usage
echo -n "Checking memory usage... "
MEM_USAGE=$(free | grep Mem | awk '{printf "%.0f", ($3/$2)*100}')
if [ "$MEM_USAGE" -gt 90 ]; then
    echo -e "${RED}FAIL${NC} (${MEM_USAGE}% used)"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
else
    echo -e "${GREEN}OK${NC} (${MEM_USAGE}% used)"
fi

# Check 3: Critical services running
echo -n "Checking critical services... "
CRITICAL_SERVICES="traefik.service authelia.service"
SERVICES_DOWN=0

for service in $CRITICAL_SERVICES; do
    if ! systemctl --user is-active --quiet "$service"; then
        echo -e "${RED}FAIL${NC} ($service is down)"
        SERVICES_DOWN=$((SERVICES_DOWN + 1))
        CHECKS_FAILED=$((CHECKS_FAILED + 1))
    fi
done

if [ "$SERVICES_DOWN" -eq 0 ]; then
    echo -e "${GREEN}OK${NC} (all critical services running)"
fi

# Check 4: No recent update in last hour (prevent rapid re-updates)
echo -n "Checking for recent updates... "
LAST_UPDATE_LOG="/home/patriark/containers/data/last-auto-update.log"
if [ -f "$LAST_UPDATE_LOG" ]; then
    LAST_UPDATE=$(stat -c %Y "$LAST_UPDATE_LOG" 2>/dev/null || echo "0")
    NOW=$(date +%s)
    TIME_SINCE=$((NOW - LAST_UPDATE))

    if [ "$TIME_SINCE" -lt 3600 ]; then
        echo -e "${YELLOW}WARN${NC} (updated $((TIME_SINCE / 60)) minutes ago, skipping)"
        exit 1
    else
        echo -e "${GREEN}OK${NC} (last update: $((TIME_SINCE / 3600)) hours ago)"
    fi
else
    echo -e "${GREEN}OK${NC} (no previous update log)"
fi

# Summary
echo ""
if [ "$CHECKS_FAILED" -gt 0 ]; then
    echo -e "${RED}Pre-update health check FAILED${NC} ($CHECKS_FAILED checks failed)"
    echo "Aborting auto-update to prevent issues"
    exit 1
else
    echo -e "${GREEN}Pre-update health check PASSED${NC}"
    echo "System is healthy, proceeding with auto-update"
    exit 0
fi
