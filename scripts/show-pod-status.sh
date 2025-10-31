#!/bin/bash
# Complete Pod Status Report

echo "════════════════════════════════════════════"
echo "        POD STATUS REPORT"
echo "════════════════════════════════════════════"
echo "Generated: $(date)"
echo ""

echo "━━━ ALL PODS ━━━"
if [ $(podman pod ps -q | wc -l) -eq 0 ]; then
    echo "No pods running"
else
    podman pod ps --format "table {{.Name}}\t{{.Status}}\t{{.Created}}\t{{.InfraID}}"
fi
echo ""

for pod in $(podman pod ps --format "{{.Name}}"); do
    echo "━━━ POD: $pod ━━━"
    
    # Get pod IP
    infra_id=$(podman pod inspect $pod --format '{{.InfraContainerID}}')
    ip=$(podman inspect $infra_id 2>/dev/null | jq -r '.[].NetworkSettings | to_entries[0].value.IPAddress // "N/A"')
    network=$(podman inspect $infra_id 2>/dev/null | jq -r '.[].NetworkSettings | to_entries[0].key // "N/A"')
    
    echo "Network: $network"
    echo "IP Address: $ip"
    echo ""
    
    # List containers
    echo "Containers:"
    podman ps --filter pod=$pod --format "  ├─ {{.Names}} ({{.Image}}) - {{.Status}}" 2>/dev/null
    
    # Port mappings
    ports=$(podman pod inspect $pod 2>/dev/null | jq -r '.[] | select(.InfraConfig.PortBindings != null) | .InfraConfig.PortBindings | to_entries[] | "  └─ Host:\(.value[0].HostPort) → Container:\(.key)"')
    if [ ! -z "$ports" ]; then
        echo ""
        echo "Published Ports:"
        echo "$ports"
    fi
    echo ""
done

echo "════════════════════════════════════════════"
