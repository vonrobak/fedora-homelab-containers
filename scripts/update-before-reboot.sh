#!/bin/bash
# Update all container images before system reboot
# Simple workflow: stop → pull latest → ready for dnf update + reboot

set -e

echo "🔄 Updating container images before system reboot..."
echo ""

# 1. Stop all containers
echo "⏸️  Stopping all containers..."
podman stop -a
echo "✅ All containers stopped"
echo ""

# 2. Pull latest images
echo "⬇️  Pulling latest images..."
IMAGES=$(podman images --format "{{.Repository}}:{{.Tag}}" | grep -v "<none>" | sort -u)
echo "$IMAGES" | while read -r IMAGE; do
    echo "  → $IMAGE"
    podman pull "$IMAGE" 2>&1 | grep -E "(Trying to pull|Digest:|Error:)" || true
done
echo "✅ Images updated"
echo ""

# 3. Prune old images
echo "🧹 Pruning old image layers..."
podman image prune -f
echo "✅ Cleanup complete"
echo ""

# 4. Next steps
echo "================================================================"
echo "Ready for system update! 🚀"
echo "================================================================"
echo ""
echo "Next steps:"
echo "  1. sudo dnf update -y"
echo "  2. sudo reboot"
echo "  3. Services will auto-start via systemd quadlets"
echo "  4. Check health: ~/containers/scripts/homelab-intel.sh"
echo ""
