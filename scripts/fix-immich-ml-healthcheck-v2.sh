#!/bin/bash
#
# Fix immich-ml Health Check Issue (v2 - Simplified)
#
# Problem: immich-ml health check uses curl, but curl is not in the container
# Solution: Update health check to use python3 with proper quoting
#

set -euo pipefail

QUADLET_FILE="$HOME/.config/containers/systemd/immich-ml.container"
SERVICE_NAME="immich-ml.service"

echo "=== Immich ML Health Check Fix (v2) ==="
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

# Show current health check
echo "Current health check configuration:"
grep -E "^Health" "$QUADLET_FILE" 2>/dev/null || echo "  (no health check found)"
echo ""

# Remove all existing health check lines
sed -i '/^HealthCmd=/d; /^HealthInterval=/d; /^HealthTimeout=/d; /^HealthRetries=/d; /^HealthStartPeriod=/d' "$QUADLET_FILE"
echo "✓ Removed old health check configuration"
echo ""

# Add new health check - using a here-document to avoid quote escaping issues
echo "Adding new python-based health check..."

# Find the [Container] line number
CONTAINER_LINE=$(grep -n '^\[Container\]' "$QUADLET_FILE" | cut -d: -f1)

# Create temp file with new health check
TEMP_FILE=$(mktemp)

# Copy everything up to and including [Container]
head -n "$CONTAINER_LINE" "$QUADLET_FILE" > "$TEMP_FILE"

# Add health check with proper formatting (single quotes for Python, double quotes for shell)
cat >> "$TEMP_FILE" << 'HEALTHCHECK'
HealthCmd=/bin/sh -c 'python3 -c "import urllib.request; urllib.request.urlopen(\"http://localhost:3003/ping\", timeout=5)"'
HealthInterval=30s
HealthTimeout=10s
HealthRetries=3
HealthStartPeriod=60s
HEALTHCHECK

# Add the rest of the file
tail -n +$((CONTAINER_LINE + 1)) "$QUADLET_FILE" >> "$TEMP_FILE"

# Replace original with temp file
mv "$TEMP_FILE" "$QUADLET_FILE"

echo "✓ Added python-based health check"
echo ""

# Show new configuration
echo "New health check configuration:"
grep -E "^Health" "$QUADLET_FILE"
echo ""

# Test the health check command manually
echo "Testing health check command manually..."
if podman exec immich-ml python3 -c 'import urllib.request; urllib.request.urlopen("http://localhost:3003/ping", timeout=5)' 2>/dev/null; then
    echo "✓ Health check command works!"
else
    echo "⚠️  Health check command test failed"
fi
echo ""

# Offer to apply changes
read -p "Apply changes and restart service? (y/N) " -n 1 -r
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
    echo "Current health status:"
    podman inspect immich-ml --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}'

    echo ""
    echo "Wait 60 seconds for health check to stabilize, then run:"
    echo "  podman inspect immich-ml --format '{{.State.Health.Status}}'"
    echo "Expected result: healthy"
else
    echo "Changes saved but not applied. To apply manually:"
    echo "  systemctl --user daemon-reload"
    echo "  systemctl --user restart $SERVICE_NAME"
fi

echo ""
echo "=== Fix Complete ==="
echo ""
echo "If you need to rollback:"
echo "  cp $BACKUP_FILE $QUADLET_FILE"
echo "  systemctl --user daemon-reload"
echo "  systemctl --user restart $SERVICE_NAME"
