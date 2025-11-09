#!/bin/bash
#
# Fix immich-ml Health Check Issue
#
# Problem: immich-ml health check uses curl, but curl is not in the container
# Solution: Update health check to use wget (which is available) or Python
#
# Usage: ./scripts/fix-immich-ml-healthcheck.sh
#

set -euo pipefail

QUADLET_FILE="$HOME/.config/containers/systemd/immich-ml.container"
SERVICE_NAME="immich-ml.service"

echo "=== Immich ML Health Check Fix ==="
echo ""

# Check if quadlet exists
if [ ! -f "$QUADLET_FILE" ]; then
    echo "❌ Error: Quadlet file not found: $QUADLET_FILE"
    exit 1
fi

echo "✓ Found quadlet: $QUADLET_FILE"
echo ""

# Backup original
BACKUP_FILE="${QUADLET_FILE}.backup-$(date +%Y%m%d-%H%M%S)"
cp "$QUADLET_FILE" "$BACKUP_FILE"
echo "✓ Created backup: $BACKUP_FILE"
echo ""

# Check current health check
echo "Current health check configuration:"
grep -E "^Health" "$QUADLET_FILE" || echo "  (no health check found)"
echo ""

# Check what's available in the container
echo "Checking available binaries in immich-ml container..."
if podman exec immich-ml which wget &>/dev/null; then
    echo "✓ wget is available - will use wget for health check"
    USE_WGET=true
elif podman exec immich-ml which python3 &>/dev/null; then
    echo "✓ python3 is available - will use python for health check"
    USE_WGET=false
else
    echo "❌ Error: Neither wget nor python3 found in container"
    echo "   Cannot create a working health check without these tools"
    exit 1
fi
echo ""

# Remove existing health check lines
echo "Removing old health check configuration..."
sed -i '/^HealthCmd=/d' "$QUADLET_FILE"
sed -i '/^HealthInterval=/d' "$QUADLET_FILE"
sed -i '/^HealthTimeout=/d' "$QUADLET_FILE"
sed -i '/^HealthRetries=/d' "$QUADLET_FILE"
sed -i '/^HealthStartPeriod=/d' "$QUADLET_FILE"
echo "✓ Removed old health check lines"
echo ""

# Add new health check using wget or python
echo "Adding new health check configuration..."
if [ "$USE_WGET" = true ]; then
    # Use wget --spider (doesn't download, just checks if URL is accessible)
    sed -i '/^\[Container\]/a \
HealthCmd=/bin/sh -c "wget --no-verbose --tries=1 --spider http://localhost:3003/ping || exit 1"\
HealthInterval=30s\
HealthTimeout=10s\
HealthRetries=3\
HealthStartPeriod=60s' "$QUADLET_FILE"
    echo "✓ Added wget-based health check"
else
    # Use python3 with urllib
    sed -i '/^\[Container\]/a \
HealthCmd=/bin/sh -c "python3 -c \"import urllib.request; urllib.request.urlopen('\''http://localhost:3003/ping'\'', timeout=5)\" || exit 1"\
HealthInterval=30s\
HealthTimeout=10s\
HealthRetries=3\
HealthStartPeriod=60s' "$QUADLET_FILE"
    echo "✓ Added python-based health check"
fi
echo ""

# Show new configuration
echo "New health check configuration:"
grep -E "^Health" "$QUADLET_FILE"
echo ""

# Ask user to reload and restart
echo "=== Next Steps ==="
echo ""
echo "1. Reload systemd daemon:"
echo "   systemctl --user daemon-reload"
echo ""
echo "2. Restart immich-ml service:"
echo "   systemctl --user restart $SERVICE_NAME"
echo ""
echo "3. Wait 60 seconds for health check to stabilize (HealthStartPeriod)"
echo ""
echo "4. Check new health status:"
echo "   podman inspect immich-ml --format '{{.State.Health.Status}}'"
echo ""
echo "Expected result: 'healthy' (after startup period)"
echo ""

# Offer to apply changes automatically
read -p "Apply changes now? (y/N) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Applying changes..."
    systemctl --user daemon-reload
    echo "✓ Daemon reloaded"

    systemctl --user restart "$SERVICE_NAME"
    echo "✓ Service restarted"

    echo ""
    echo "Waiting 10 seconds for service to start..."
    sleep 10

    echo ""
    echo "Current status:"
    systemctl --user status "$SERVICE_NAME" --no-pager || true

    echo ""
    echo "Note: Health check may show 'starting' for up to 60 seconds (HealthStartPeriod)"
    echo "      Run this command in 60 seconds to verify:"
    echo "      podman inspect immich-ml --format '{{.State.Health.Status}}'"
else
    echo "Changes saved but not applied. Run the commands above when ready."
fi

echo ""
echo "=== Fix Complete ==="
echo ""
echo "If you need to rollback:"
echo "  cp $BACKUP_FILE $QUADLET_FILE"
echo "  systemctl --user daemon-reload"
echo "  systemctl --user restart $SERVICE_NAME"
