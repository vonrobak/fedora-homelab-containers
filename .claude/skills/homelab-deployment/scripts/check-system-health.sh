#!/usr/bin/env bash
# Check system health before deployment
# Integrates with homelab-intel.sh for comprehensive health assessment

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "System Health Check"
echo "=========================================="

# Check 1: Disk space
echo "Checking disk space..."
SYSTEM_USAGE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
if [[ $SYSTEM_USAGE -lt 80 ]]; then
    echo -e "${GREEN}✓${NC} System disk: ${SYSTEM_USAGE}% (healthy)"
else
    echo -e "${RED}✗${NC} System disk: ${SYSTEM_USAGE}% (too full!)"
    echo "  Run cleanup before deploying new services"
    exit 1
fi

# Check 2: Critical services
echo ""
echo "Checking critical services..."
CRITICAL_SERVICES=("traefik" "prometheus" "grafana")
ALL_UP=true

for service in "${CRITICAL_SERVICES[@]}"; do
    if systemctl --user is-active "${service}.service" &>/dev/null; then
        echo -e "${GREEN}✓${NC} ${service}.service is running"
    else
        echo -e "${RED}✗${NC} ${service}.service is NOT running"
        ALL_UP=false
    fi
done

if [[ "$ALL_UP" != "true" ]]; then
    echo -e "${RED}✗${NC} Some critical services are down. Fix before deploying."
    exit 1
fi

# Check 3: Memory available
echo ""
echo "Checking memory..."
MEM_AVAILABLE=$(free -g | awk 'NR==2 {print $7}')
if [[ $MEM_AVAILABLE -gt 2 ]]; then
    echo -e "${GREEN}✓${NC} Available memory: ${MEM_AVAILABLE}GB (sufficient)"
else
    echo -e "${YELLOW}⚠${NC} Available memory: ${MEM_AVAILABLE}GB (low)"
    echo "  Consider restarting services to free memory"
fi

# Check 4: Recent errors in logs
echo ""
echo "Checking for recent errors..."
ERROR_COUNT=$(journalctl --user --since "5 minutes ago" --priority err --no-pager 2>/dev/null | wc -l)
if [[ $ERROR_COUNT -lt 5 ]]; then
    echo -e "${GREEN}✓${NC} Recent errors: ${ERROR_COUNT} (normal)"
else
    echo -e "${YELLOW}⚠${NC} Recent errors: ${ERROR_COUNT} (investigate before deploying)"
fi

# Summary
echo ""
echo "=========================================="
echo -e "${GREEN}✓ System healthy - ready for deployment${NC}"
exit 0
