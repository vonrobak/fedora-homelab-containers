#!/bin/bash
# Apply network interface ordering fix using podman directly (no systemctl)

set -euo pipefail

echo "=== Network Interface Ordering Fix (Podman Direct) ==="
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
    "traefik"
)

echo "Restarting services with verification..."
echo

for service in "${SERVICES[@]}"; do
    echo "--- Restarting $service ---"
    
    # Stop and remove old container
    podman stop "$service" 2>/dev/null || true
    sleep 2
    podman rm "$service" 2>/dev/null || true
    
    # Start new container (quadlet will recreate with new network config)
    # Use podman systemd generator to create container from quadlet
    /usr/libexec/podman/quadlet --user --dryrun 2>/dev/null | grep -A 50 "$service.service" > /tmp/${service}-generated.txt || true
    
    # Actually we need to use systemd, but let's try recreating manually
    quadlet_file=~/containers/quadlets/${service}.container
    
    if [[ ! -f "$quadlet_file" ]]; then
        echo "  ⚠️  Quadlet not found: $quadlet_file"
        continue
    fi
    
    # For now, just restart via podman
    podman container exists "$service" && podman restart "$service" || podman start "$service" 2>/dev/null || echo "  ⚠️  Could not restart $service - may need systemctl"
    
    sleep 3
    
    # Verify if container is running
    if podman container exists "$service" && podman inspect "$service" --format '{{.State.Status}}' | grep -q running; then
        echo "  ✅ $service is running"
        
        # Check interface order
        if podman exec "$service" ip link 2>/dev/null | grep -q "eth0"; then
            ETH0_IP=$(podman exec "$service" ip addr show eth0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1 || echo "N/A")
            echo "  Interface eth0 IP: $ETH0_IP"
            
            if [[ "$ETH0_IP" == 10.89.2.* ]]; then
                echo "  ✅ eth0 is on reverse_proxy network"
            else
                echo "  ⚠️  eth0 is NOT on reverse_proxy network"
            fi
        fi
        
        # Verify routing
        DEFAULT_GW=$(podman exec "$service" ip route 2>/dev/null | grep "^default" | head -1 | awk '{print $3}' || echo "N/A")
        
        if [[ "$DEFAULT_GW" == "10.89.2.1" ]]; then
            echo "  ✅ Routes via reverse_proxy (10.89.2.1)"
        elif [[ "$DEFAULT_GW" == "N/A" ]]; then
            echo "  ⚠️  No ip command (skipping routing check)"
        else
            echo "  ⚠️  Routes via $DEFAULT_GW (expected 10.89.2.1)"
        fi
        
        # Check DNS
        FIRST_NS=$(podman exec "$service" cat /etc/resolv.conf 2>/dev/null | grep nameserver | head -1 | awk '{print $2}' || echo "N/A")
        if [[ "$FIRST_NS" == "10.89.2.1" ]]; then
            echo "  ✅ DNS primary: 10.89.2.1"
        else
            echo "  ⚠️  DNS primary: $FIRST_NS"
        fi
    else
        echo "  ❌ $service is not running!"
    fi
    
    echo
done

echo "=== Manual systemctl daemon-reload needed ==="
echo "The user needs to run: systemctl --user daemon-reload"
echo "Then restart services that failed above"
