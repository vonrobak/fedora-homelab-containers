#!/bin/bash
# post-reboot-verify.sh
# Post-reboot verification: compare against pre-update snapshot, detect migrations
#
# Usage: ./scripts/post-reboot-verify.sh [--snapshot PATH]
# Default: reads data/update-snapshots/latest.json

set -euo pipefail

export XDG_RUNTIME_DIR=/run/user/$(id -u)
export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINERS_DIR="$(dirname "$SCRIPT_DIR")"
SNAPSHOT_DIR="$CONTAINERS_DIR/data/update-snapshots"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Parse args
SNAPSHOT_PATH="$SNAPSHOT_DIR/latest.json"
if [[ "${1:-}" == "--snapshot" && -n "${2:-}" ]]; then
    SNAPSHOT_PATH="$2"
fi

echo ""
echo "============================================"
echo "  POST-REBOOT VERIFICATION"
echo "============================================"
echo ""

# ── Section 1: Snapshot comparison ──

ISSUES=0

if [ -f "$SNAPSHOT_PATH" ]; then
    echo -e "${CYAN}Comparing against snapshot:${NC} $SNAPSHOT_PATH"
    echo ""

    # Extract pre-update values
    PRE_PODMAN=$(python3 -c "import json; d=json.load(open('$SNAPSHOT_PATH')); print(d['packages']['podman'])" 2>/dev/null || echo "unknown")
    PRE_DB=$(python3 -c "import json; d=json.load(open('$SNAPSHOT_PATH')); print(d['podman']['db_backend'])" 2>/dev/null || echo "unknown")
    PRE_COUNT=$(python3 -c "import json; d=json.load(open('$SNAPSHOT_PATH')); print(d['containers']['count'])" 2>/dev/null || echo "0")
    PRE_TIMESTAMP=$(python3 -c "import json; d=json.load(open('$SNAPSHOT_PATH')); print(d['timestamp'])" 2>/dev/null || echo "unknown")

    echo "  Pre-update snapshot taken: $PRE_TIMESTAMP"
    echo ""

    # Current values
    POST_PODMAN=$(rpm -q podman 2>/dev/null || echo "unknown")
    POST_DB=$(podman info --format '{{.Store.GraphDriverName}}' 2>/dev/null || echo "unknown")
    POST_COUNT=$(podman ps --format '{{.Names}}' 2>/dev/null | wc -l)

    # Podman version comparison
    echo -e "${BOLD}Podman Version:${NC}"
    if [ "$PRE_PODMAN" != "$POST_PODMAN" ]; then
        echo -e "  ${YELLOW}CHANGED${NC}: $PRE_PODMAN -> $POST_PODMAN"
    else
        echo -e "  ${GREEN}UNCHANGED${NC}: $POST_PODMAN"
    fi

    # DB backend migration detection
    echo -e "${BOLD}Database Backend:${NC}"
    if [ "$PRE_DB" != "$POST_DB" ]; then
        echo -e "  ${YELLOW}MIGRATED${NC}: $PRE_DB -> $POST_DB"
        if [[ "$POST_DB" == *"sqlite"* ]] || [[ "$POST_DB" == *"SQLite"* ]]; then
            echo -e "  ${GREEN}BoltDB -> SQLite migration detected (Podman 5.8+)${NC}"
        fi
    else
        echo -e "  ${GREEN}UNCHANGED${NC}: $POST_DB"
    fi

    # Container count comparison
    echo -e "${BOLD}Container Count:${NC}"
    if [ "$POST_COUNT" -lt "$PRE_COUNT" ]; then
        MISSING=$((PRE_COUNT - POST_COUNT))
        echo -e "  ${RED}DOWN${NC}: $PRE_COUNT -> $POST_COUNT ($MISSING containers not running)"
        ISSUES=$((ISSUES + 1))
    elif [ "$POST_COUNT" -eq "$PRE_COUNT" ]; then
        echo -e "  ${GREEN}MATCH${NC}: $POST_COUNT containers running"
    else
        echo -e "  ${GREEN}OK${NC}: $POST_COUNT running (was $PRE_COUNT before)"
    fi
    echo ""
else
    echo -e "${YELLOW}No snapshot found at $SNAPSHOT_PATH${NC}"
    echo "  Skipping comparison, running health checks only"
    echo ""
fi

# ── Section 2: Kernel check ──

echo -e "${BOLD}Kernel:${NC}"
echo "  Running: $(uname -r)"
echo ""

# ── Section 3: Service health ──

echo -e "${CYAN}Service Health:${NC}"
echo ""

ALL_SERVICES=(
    traefik authelia redis-authelia crowdsec
    prometheus grafana loki alertmanager promtail cadvisor node_exporter alert-discord-relay unpoller
    nextcloud nextcloud-db nextcloud-redis
    immich-server immich-ml postgresql-immich redis-immich
    jellyfin vaultwarden homepage
    home-assistant matter-server
    gathio gathio-db
)

RUNNING=0
FAILED_LIST=()

for service in "${ALL_SERVICES[@]}"; do
    unit="${service}.service"
    status=$(systemctl --user is-active "$unit" 2>/dev/null || echo "inactive")
    if [ "$status" = "active" ]; then
        RUNNING=$((RUNNING + 1))
    else
        FAILED_LIST+=("$service ($status)")
        ISSUES=$((ISSUES + 1))
    fi
done

echo -e "  Running: ${GREEN}$RUNNING${NC} / ${#ALL_SERVICES[@]}"

if [ ${#FAILED_LIST[@]} -gt 0 ]; then
    echo -e "  ${RED}Not running:${NC}"
    for svc in "${FAILED_LIST[@]}"; do
        echo -e "    - $svc"
    done
fi
echo ""

# ── Section 4: Container health checks ──

echo -e "${CYAN}Container Health Checks:${NC}"
echo ""

HEALTH_CONTAINERS=(traefik authelia nextcloud immich-server jellyfin home-assistant crowdsec
    nextcloud-db nextcloud-redis gathio gathio-db matter-server)
HEALTH_OK=0
HEALTH_FAIL=0

for container in "${HEALTH_CONTAINERS[@]}"; do
    if podman healthcheck run "$container" >/dev/null 2>&1; then
        HEALTH_OK=$((HEALTH_OK + 1))
    else
        status=$(podman inspect "$container" --format '{{.State.Health.Status}}' 2>/dev/null || echo "no-healthcheck")
        if [ "$status" = "no-healthcheck" ] || [ "$status" = "" ]; then
            # No health check configured, not an error
            true
        else
            echo -e "  ${YELLOW}$container${NC}: $status"
            HEALTH_FAIL=$((HEALTH_FAIL + 1))
        fi
    fi
done

echo -e "  Healthy: ${GREEN}$HEALTH_OK${NC} / ${#HEALTH_CONTAINERS[@]}"
if [ "$HEALTH_FAIL" -gt 0 ]; then
    echo -e "  ${YELLOW}$HEALTH_FAIL containers with health issues${NC}"
    ISSUES=$((ISSUES + $HEALTH_FAIL))
fi
echo ""

# ── Section 5: Run existing health check if available ──

HEALTH_CHECK_SCRIPT="$SCRIPT_DIR/post-update-health-check.sh"
if [ -x "$HEALTH_CHECK_SCRIPT" ]; then
    echo -e "${CYAN}Running detailed health check (Nextcloud DB upgrade, Discord notification)...${NC}"
    echo ""
    "$HEALTH_CHECK_SCRIPT" || ISSUES=$((ISSUES + 1))
    echo ""
fi

# ── Section 6: Summary ──

echo "============================================"
echo "  VERIFICATION SUMMARY"
echo "============================================"
echo ""

if [ "$ISSUES" -eq 0 ]; then
    echo -e "  ${GREEN}ALL CHECKS PASSED${NC}"
    echo ""
    echo "  Next steps:"
    echo "    - Update MEMORY.md with new Podman version if changed"
    echo "    - Run homelab-intel.sh for full health score"
    echo "    - Monitor Grafana dashboards for anomalies"
else
    echo -e "  ${RED}$ISSUES ISSUE(S) DETECTED${NC}"
    echo ""
    echo "  Troubleshooting:"
    echo "    journalctl --user -u <service>.service -n 50"
    echo "    podman logs <container> --tail 50"
    echo "    systemctl --user restart <service>.service"
fi

exit $ISSUES
