#!/bin/bash

# Apply resource limits to critical services
# Usage: ./apply-resource-limits.sh

QUADLET_DIR="${HOME}/.config/containers/systemd"

services=(
    "prometheus:2G"
    "grafana:1G"
    "loki:1G"
    "postgresql-immich:2G"
    "immich-server:3G"
    "immich-ml:4G"
)

for entry in "${services[@]}"; do
    service="${entry%:*}"
    limit="${entry#*:}"
    quadlet="${QUADLET_DIR}/${service}.container"

    if [ ! -f "$quadlet" ]; then
        echo "⚠ Skipping $service - quadlet not found"
        continue
    fi

    # Check if MemoryMax already exists
    if grep -q '^MemoryMax=' "$quadlet"; then
        echo "✓ $service already has MemoryMax configured"
        continue
    fi

    # Add MemoryMax to [Service] section
    echo "▶ Adding MemoryMax=$limit to $service"
    sed -i '/^\[Service\]/a MemoryMax='"$limit" "$quadlet"
done

echo ""
echo "✓ Resource limits applied!"
echo ""
echo "Next steps:"
echo "  1. Review changes: git diff ~/.config/containers/systemd/"
echo "  2. Reload systemd: systemctl --user daemon-reload"
echo "  3. Restart services: systemctl --user restart <service>.service"
echo ""
echo "Or restart all at once:"
echo "  systemctl --user restart prometheus grafana loki postgresql-immich immich-server immich-ml"
