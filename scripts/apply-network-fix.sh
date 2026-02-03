#!/bin/bash
# Apply network interface ordering fix system-wide

set -euo pipefail

echo "=== Network Interface Ordering Fix ==="
echo "Root cause: Kernel 6.18.7 changed network namespace behavior"
echo "Solution: Explicit interface_name= in quadlet Network= directives"
echo

# Services in order of importance (least disruptive first)
SERVICES=(
    "alertmanager"
    "prometheus"
    "grafana"
    "authelia"
    "nextcloud"
    "immich-server"
    "jellyfin"
    "home-assistant"
    "traefik"  # Last - gateway, most critical
)

echo "Step 1: Reload systemd daemon..."
systemctl --user daemon-reload
echo "✅ Systemd daemon reloaded"
echo

echo "Step 2: Restart services with verification..."
for service in "${SERVICES[@]}"; do
    echo "--- Restarting $service ---"
    
    podman stop "$service" 2>/dev/null || true
    podman rm "$service" 2>/dev/null || true
    systemctl --user restart "$service.service"
    
    # Wait for container to be running
    sleep 3
    
    # Verify routing
    DEFAULT_GW=$(podman exec "$service" ip route 2>/dev/null | grep "^default" | head -1 | awk '{print $3}' || echo "N/A")
    
    if [[ "$DEFAULT_GW" == "10.89.2.1" ]]; then
        echo "  ✅ $service: Routes via reverse_proxy (10.89.2.1)"
    elif [[ "$DEFAULT_GW" == "N/A" ]]; then
        echo "  ⚠️  $service: No ip command (skipping routing check)"
    else
        echo "  ❌ $service: WRONG! Routes via $DEFAULT_GW"
        echo "  Full routing:"
        podman exec "$service" ip route 2>/dev/null || echo "  Cannot check routing"
    fi
    
    # Check DNS nameserver order
    FIRST_NS=$(podman exec "$service" cat /etc/resolv.conf 2>/dev/null | grep nameserver | head -1 | awk '{print $2}' || echo "N/A")
    if [[ "$FIRST_NS" == "10.89.2.1" ]]; then
        echo "  ✅ $service: DNS primary is reverse_proxy (10.89.2.1)"
    else
        echo "  ⚠️  $service: DNS primary is $FIRST_NS (expected 10.89.2.1)"
    fi
    
    echo
done

echo "=== Fix Applied ==="
echo "All services restarted with explicit interface ordering"
echo
echo "Next step: Test Home Assistant access"
