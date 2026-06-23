#!/bin/bash
# graceful-shutdown.sh
# Dependency-aware, tiered graceful shutdown of all homelab containers.
#
# Fleet membership is DERIVED AT RUNTIME from quadlets/*.container (the systemd
# source of truth) and classified into shutdown tiers by role — it is NOT a
# hardcoded list. A hardcoded list silently omits any service deployed after it
# was last edited: the previous version's static array skipped forgejo-db (a
# PostgreSQL database) plus 8 other running services, which then fell to the
# reboot transition instead of being quiesced while the host was up — defeating
# the script's entire purpose for a database. See GH#307 / lesson L-079.
#
# Tiers (reverse startup order — supporting first, gateway last):
#   1 Supporting     exporters, ML, relays, log shippers
#   2 Applications   user-facing services (stop before their DBs)   [catch-all]
#   3 Infrastructure monitoring + security
#   4 Auth           authentication stack
#   5 Data           databases & caches (quiesce last-but-one)
#   6 Gateway        traefik (last to stop, first to start)
#
# Classification is by name pattern, first match wins (so *-exporter is caught
# before the database name patterns — postgres-exporter is tier 1, not tier 5).
# Anything matching no known role falls to tier 2 (Applications); it still gets
# stopped and is visible in the roster, never silently skipped. After the run a
# loud guard fails if ANY container survives (catches non-quadlet orphans too).
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

QUADLET_DIR="${QUADLET_DIR:-$HOME/containers/quadlets}"

declare -A TIER_NAME=(
    [1]="Supporting services"
    [2]="Applications"
    [3]="Infrastructure"
    [4]="Auth"
    [5]="Data (databases & caches)"
    [6]="Gateway"
)

# classify <service> -> tier 1..6. First matching pattern wins.
classify() {
    case "$1" in
        traefik)
            echo 6 ;;                                              # gateway
        authelia)
            echo 4 ;;                                              # auth
        *-exporter|cadvisor|node_exporter|promtail|unpoller|*-ml|*-relay)
            echo 1 ;;                                              # supporting
        prometheus|loki|grafana|alertmanager|crowdsec)
            echo 3 ;;                                              # infrastructure
        *-db|*-redis|redis-*|postgres*|postgresql-*|mariadb*|mongo*)
            echo 5 ;;                                              # data
        *)
            echo 2 ;;                                              # apps + catch-all
    esac
}

# --- Discover the fleet from quadlet sources -------------------------------
declare -A SVC_TIER
shopt -s nullglob
for f in "$QUADLET_DIR"/*.container; do
    svc="$(basename "$f" .container)"
    SVC_TIER["$svc"]="$(classify "$svc")"
done
shopt -u nullglob

if [ "${#SVC_TIER[@]}" -eq 0 ]; then
    echo -e "${RED}No quadlet .container files found in $QUADLET_DIR — refusing to run.${NC}" >&2
    exit 1
fi

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
echo "  GRACEFUL SHUTDOWN - tiers derived from quadlets/"
if $DRY_RUN; then
    echo -e "  ${CYAN}(DRY RUN - no services will be stopped)${NC}"
fi
echo "============================================"
echo "  Discovered ${#SVC_TIER[@]} quadlet services"
echo ""

for tier in 1 2 3 4 5 6; do
    # Services in this tier, sorted for stable, readable output.
    mapfile -t svcs < <(
        for svc in "${!SVC_TIER[@]}"; do
            [[ "${SVC_TIER[$svc]}" == "$tier" ]] && echo "$svc"
        done | sort
    )
    [ "${#svcs[@]}" -eq 0 ] && continue

    echo -e "${CYAN}Tier $tier: ${TIER_NAME[$tier]}${NC}"
    for service in "${svcs[@]}"; do
        stop_service "$service"
    done

    # Brief pause between tiers to allow clean TCP teardown.
    if ! $DRY_RUN && [ "$tier" -lt 6 ]; then
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
    # Loud drift guard: nothing must survive. A container left running here is
    # either a unit that failed to stop or one with no quadlet behind it (an
    # orphan) — exactly the silent gap GH#307 closed. Fail, don't whisper.
    REMAINING=$(podman ps --format '{{.Names}}' 2>/dev/null | wc -l)
    if [ "$REMAINING" -gt 0 ]; then
        echo -e "${RED}Drift: $REMAINING container(s) still running after shutdown:${NC}"
        podman ps --format '  {{.Names}} ({{.Status}})' 2>/dev/null
        echo -e "${YELLOW}If these have no quadlets/*.container, they were never covered.${NC}"
        exit 1
    fi
    echo -e "${GREEN}All containers stopped successfully.${NC}"
fi
