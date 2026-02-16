#!/bin/bash
# graceful-shutdown.sh
# Dependency-aware 6-phase graceful shutdown of all homelab containers
#
# Phases (reverse startup order):
#   1. Supporting services (exporters, ML, matter)
#   2. Applications (user-facing services)
#   3. Infrastructure (monitoring, security)
#   4. Auth (authentication stack)
#   5. Data (databases, caches)
#   6. Gateway (traefik - last to stop, first to start)
#
# Usage: ./scripts/graceful-shutdown.sh [--dry-run]

set -euo pipefail

export XDG_RUNTIME_DIR=/run/user/$(id -u)
export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Phase definitions: name and services
declare -A PHASES
PHASES=(
    [1_name]="Supporting services"
    [1_services]="alert-discord-relay cadvisor node_exporter promtail unpoller immich-ml matter-server"
    [2_name]="Applications"
    [2_services]="nextcloud gathio immich-server jellyfin home-assistant homepage vaultwarden"
    [3_name]="Infrastructure"
    [3_services]="grafana prometheus loki alertmanager crowdsec"
    [4_name]="Auth"
    [4_services]="authelia"
    [5_name]="Data"
    [5_services]="nextcloud-db nextcloud-redis gathio-db postgresql-immich redis-immich redis-authelia"
    [6_name]="Gateway"
    [6_services]="traefik"
)

TOTAL_STOPPED=0
TOTAL_SKIPPED=0
TOTAL_FAILED=0

stop_service() {
    local service="$1"
    local unit="${service}.service"

    if ! systemctl --user is-active --quiet "$unit" 2>/dev/null; then
        echo -e "    ${YELLOW}SKIP${NC} $service (not running)"
        TOTAL_SKIPPED=$((TOTAL_SKIPPED + 1))
        return 0
    fi

    if $DRY_RUN; then
        echo -e "    ${CYAN}DRY-RUN${NC} would stop $service"
        return 0
    fi

    echo -n "    Stopping $service... "
    if systemctl --user stop "$unit" 2>/dev/null; then
        echo -e "${GREEN}OK${NC}"
        TOTAL_STOPPED=$((TOTAL_STOPPED + 1))
    else
        echo -e "${RED}FAILED${NC}"
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
    fi
}

echo "============================================"
echo "  GRACEFUL SHUTDOWN - 6-Phase Dependency Order"
if $DRY_RUN; then
    echo -e "  ${CYAN}(DRY RUN - no services will be stopped)${NC}"
fi
echo "============================================"
echo ""

for phase in 1 2 3 4 5 6; do
    name="${PHASES[${phase}_name]}"
    services="${PHASES[${phase}_services]}"

    echo -e "${CYAN}Phase $phase: $name${NC}"

    for service in $services; do
        stop_service "$service"
    done

    # Brief pause between phases to allow clean TCP teardown
    if ! $DRY_RUN && [ "$phase" -lt 6 ]; then
        sleep 2
    fi

    echo ""
done

echo "============================================"
echo "  Shutdown Summary"
echo "============================================"
echo -e "  Stopped: ${GREEN}$TOTAL_STOPPED${NC}"
echo -e "  Skipped: ${YELLOW}$TOTAL_SKIPPED${NC} (already stopped)"
echo -e "  Failed:  ${RED}$TOTAL_FAILED${NC}"
echo ""

if [ "$TOTAL_FAILED" -gt 0 ]; then
    echo -e "${RED}Some services failed to stop. Check logs.${NC}"
    exit 1
fi

if ! $DRY_RUN; then
    # Verify nothing is running
    REMAINING=$(podman ps --format '{{.Names}}' 2>/dev/null | wc -l)
    if [ "$REMAINING" -gt 0 ]; then
        echo -e "${YELLOW}Warning: $REMAINING containers still running:${NC}"
        podman ps --format '  {{.Names}} ({{.Status}})' 2>/dev/null
    else
        echo -e "${GREEN}All containers stopped successfully.${NC}"
    fi
fi
