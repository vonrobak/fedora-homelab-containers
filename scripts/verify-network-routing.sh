#!/bin/bash
# Verify that internet-facing services route through reverse_proxy network ONLY

set -euo pipefail

echo "=== Network Routing Verification ==="
echo "Checking that internet traffic routes through reverse_proxy (10.89.2.0/24)..."
echo

FAILED=0

# Services that MUST route internet through reverse_proxy
SERVICES=(
    "home-assistant"
    "jellyfin"
    "immich-server"
    "nextcloud"
    "traefik"
    "grafana"
    "prometheus"
    "alertmanager"
)

for service in "${SERVICES[@]}"; do
    if ! podman container exists "$service" 2>/dev/null; then
        echo "⚠️  $service: Container not found"
        continue
    fi
    
    echo -n "Checking $service... "
    
    # Get first default route
    DEFAULT_ROUTE=$(podman exec "$service" ip route show | grep "^default" | head -1 | awk '{print $3}')
    
    # Check if it's reverse_proxy gateway (10.89.2.1)
    if [[ "$DEFAULT_ROUTE" == "10.89.2.1" ]]; then
        echo "✅ Routes via reverse_proxy (10.89.2.1)"
    else
        echo "❌ WRONG! Routes via $DEFAULT_ROUTE (expected 10.89.2.1)"
        FAILED=$((FAILED + 1))
        
        # Show full routing table for debugging
        echo "   Full routing table:"
        podman exec "$service" ip route show | sed 's/^/   /'
    fi
done

echo
if [[ $FAILED -eq 0 ]]; then
    echo "✅ All services routing correctly through reverse_proxy network"
    exit 0
else
    echo "❌ $FAILED services routing incorrectly - ARCHITECTURE VIOLATION!"
    exit 1
fi
