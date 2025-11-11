#!/usr/bin/env bash
#
# Complete Day 3 Deployment - Achieve 100% Coverage
#
# This script completes the Day 3 deployment by:
# 1. Applying fixed tinyauth health check
# 2. Applying cadvisor MemoryMax limit
# 3. Verifying 100% achievement
#

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}     DAY 3 DEPLOYMENT COMPLETION${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Check we're in the right place
if [[ ! -f "$REPO_ROOT/quadlets/tinyauth.container" ]]; then
    echo -e "${RED}Error: Cannot find quadlets directory. Are you in the right repo?${NC}"
    exit 1
fi

echo -e "${YELLOW}▶ Step 1: Updating tinyauth.container with fixed health check${NC}"
echo "  Old: /api/auth/traefik (requires Traefik headers)"
echo "  New: / (login page, no auth required)"
echo

# Check if secrets are still placeholders
if grep -q "REPLACE_WITH" "$REPO_ROOT/quadlets/tinyauth.container"; then
    echo -e "${RED}⚠️  WARNING: tinyauth.container still has placeholder secrets!${NC}"
    echo "  Please replace REPLACE_WITH_YOUR_SECRET_KEY and REPLACE_WITH_USERNAME:BCRYPT_HASH"
    echo "  with your actual secrets before continuing."
    echo
    read -p "Have you replaced the placeholder secrets? (yes/no): " CONFIRM
    if [[ "$CONFIRM" != "yes" ]]; then
        echo -e "${RED}Deployment cancelled. Please update secrets first.${NC}"
        exit 1
    fi
fi

cp "$REPO_ROOT/quadlets/tinyauth.container" ~/.config/containers/systemd/
echo -e "${GREEN}✓ Copied tinyauth.container${NC}"

echo
echo -e "${YELLOW}▶ Step 2: Updating cadvisor.container with MemoryMax=256M${NC}"
cp "$REPO_ROOT/quadlets/cadvisor.container" ~/.config/containers/systemd/
echo -e "${GREEN}✓ Copied cadvisor.container${NC}"

echo
echo -e "${YELLOW}▶ Step 3: Reloading systemd${NC}"
systemctl --user daemon-reload
echo -e "${GREEN}✓ Systemd reloaded${NC}"

echo
echo -e "${YELLOW}▶ Step 4: Stopping old containers to avoid port conflicts${NC}"
echo "  Stopping old containers..."
podman stop tinyauth cadvisor 2>/dev/null || true
podman rm -f tinyauth cadvisor 2>/dev/null || true
echo "  Waiting for ports to be released..."
sleep 3
echo -e "${GREEN}✓ Old containers cleaned up${NC}"

echo
echo -e "${YELLOW}▶ Step 5: Starting services with new configuration${NC}"
echo "  Starting tinyauth..."
systemctl --user start tinyauth.service || {
    echo -e "${RED}  ✗ tinyauth failed to start${NC}"
    systemctl --user status tinyauth.service --no-pager -l
}
echo "  Starting cadvisor..."
systemctl --user start cadvisor.service || {
    echo -e "${RED}  ✗ cadvisor failed to start${NC}"
    systemctl --user status cadvisor.service --no-pager -l
}
echo -e "${GREEN}✓ Services started${NC}"

echo
echo -e "${YELLOW}▶ Step 6: Waiting for health checks to stabilize (60 seconds)...${NC}"
echo "  TinyAuth and cAdvisor need time for health checks to run"
for i in {60..1}; do
    printf "\r  Waiting: %2d seconds remaining..." "$i"
    sleep 1
done
echo
echo -e "${GREEN}✓ Health checks should have run${NC}"

echo
echo -e "${YELLOW}▶ Step 7: Verifying service status${NC}"
echo

# Check tinyauth
TINYAUTH_HEALTH=$(podman healthcheck run tinyauth 2>&1 || echo "unhealthy")
if [[ "$TINYAUTH_HEALTH" == *"unhealthy"* ]]; then
    echo -e "${RED}  ✗ tinyauth: unhealthy${NC}"
    echo "    Running diagnostics..."
    podman logs --tail 20 tinyauth
else
    echo -e "${GREEN}  ✓ tinyauth: healthy${NC}"
fi

# Check cadvisor
CADVISOR_HEALTH=$(podman healthcheck run cadvisor 2>&1 || echo "unhealthy")
if [[ "$CADVISOR_HEALTH" == *"unhealthy"* ]]; then
    echo -e "${RED}  ✗ cadvisor: unhealthy${NC}"
else
    echo -e "${GREEN}  ✓ cadvisor: healthy${NC}"
fi

echo
echo -e "${YELLOW}▶ Step 8: Taking snapshot to verify 100% coverage${NC}"
"$REPO_ROOT/scripts/homelab-snapshot.sh"

# Parse the latest snapshot
LATEST_SNAPSHOT=$(ls -t "$REPO_ROOT/docs/99-reports"/snapshot-*.json | head -1)

if [[ -f "$LATEST_SNAPSHOT" ]]; then
    echo
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}     COVERAGE REPORT${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo

    # Health check coverage
    HC_TOTAL=$(jq -r '.health_check_analysis.total_services' "$LATEST_SNAPSHOT")
    HC_WITH=$(jq -r '.health_check_analysis.with_health_checks' "$LATEST_SNAPSHOT")
    HC_PERCENT=$(jq -r '.health_check_analysis.coverage_percent' "$LATEST_SNAPSHOT")
    HC_HEALTHY=$(jq -r '.health_check_analysis.healthy' "$LATEST_SNAPSHOT")
    HC_UNHEALTHY=$(jq -r '.health_check_analysis.unhealthy' "$LATEST_SNAPSHOT")

    echo -e "${YELLOW}Health Check Coverage:${NC}"
    if [[ "$HC_PERCENT" == "100" ]]; then
        echo -e "  ${GREEN}✓ $HC_PERCENT% ($HC_WITH/$HC_TOTAL services)${NC}"
    else
        echo -e "  ${RED}✗ $HC_PERCENT% ($HC_WITH/$HC_TOTAL services)${NC}"
    fi

    if [[ "$HC_UNHEALTHY" -gt 0 ]]; then
        echo -e "  ${RED}⚠️  $HC_UNHEALTHY unhealthy service(s)${NC}"
        # Show which services are unhealthy
        jq -r '.services | to_entries[] | select(.value.health == "unhealthy") | "    - " + .key' "$LATEST_SNAPSHOT"
    else
        echo -e "  ${GREEN}✓ All services healthy${NC}"
    fi

    echo

    # Resource limit coverage
    RL_TOTAL=$(jq -r '.resource_limits_analysis.total_services' "$LATEST_SNAPSHOT")
    RL_WITH=$(jq -r '.resource_limits_analysis.with_limits' "$LATEST_SNAPSHOT")
    RL_PERCENT=$(jq -r '.resource_limits_analysis.coverage_percent' "$LATEST_SNAPSHOT")

    echo -e "${YELLOW}Resource Limit Coverage:${NC}"
    if [[ "$RL_PERCENT" == "100" ]]; then
        echo -e "  ${GREEN}✓ $RL_PERCENT% ($RL_WITH/$RL_TOTAL services)${NC}"
    else
        echo -e "  ${RED}✗ $RL_PERCENT% ($RL_WITH/$RL_TOTAL services)${NC}"
        # Show which services are missing limits
        jq -r '.resource_limits_analysis.services_without_limits[]? | "    - " + .' "$LATEST_SNAPSHOT"
    fi

    echo
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"

    # Final verdict
    if [[ "$HC_PERCENT" == "100" && "$RL_PERCENT" == "100" && "$HC_UNHEALTHY" == "0" ]]; then
        echo
        echo -e "${GREEN}🎉 SUCCESS! 100% COVERAGE ACHIEVED! 🎉${NC}"
        echo
        echo -e "${GREEN}✓ Health checks: 100% (16/16)${NC}"
        echo -e "${GREEN}✓ Resource limits: 100% (16/16)${NC}"
        echo -e "${GREEN}✓ All services healthy${NC}"
        echo
        echo -e "${BLUE}Day 3: Complete the Foundation ✅${NC}"
        echo
    else
        echo
        echo -e "${YELLOW}⚠️  Not quite there yet...${NC}"
        echo
        if [[ "$HC_UNHEALTHY" -gt 0 ]]; then
            echo -e "${RED}Issue: $HC_UNHEALTHY service(s) still unhealthy${NC}"
            echo "Recommendation: Check logs with: podman logs <service-name>"
        fi
        if [[ "$RL_PERCENT" != "100" ]]; then
            echo -e "${RED}Issue: Resource limits not at 100%${NC}"
            echo "Recommendation: Verify MemoryMax is in quadlet and service was restarted"
        fi
        echo
    fi
else
    echo -e "${RED}Error: Could not find snapshot file${NC}"
fi
