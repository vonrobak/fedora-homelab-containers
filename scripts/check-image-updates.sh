#!/bin/bash
# Check for available container image updates
# Runs weekly to notify about available updates

set -e

REPORT_FILE="$HOME/containers/docs/99-reports/image-updates-$(date +%Y%m%d).txt"
mkdir -p "$(dirname "$REPORT_FILE")"

echo "🔍 Checking for container image updates..."
echo "Report: $REPORT_FILE"
echo ""

# Check for updates using podman auto-update --dry-run
# This checks all containers with AutoUpdate=registry
UPDATES=$(podman auto-update --dry-run 2>&1)

# Save to report file
{
    echo "Container Image Update Check"
    echo "Generated: $(date)"
    echo "========================================"
    echo ""
    echo "$UPDATES"
    echo ""
    echo "========================================"
    echo ""
    echo "To apply updates, run:"
    echo "  ~/containers/scripts/update-before-reboot.sh"
    echo "  sudo dnf update -y"
    echo "  sudo reboot"
} > "$REPORT_FILE"

# Count how many updates are available
UPDATE_COUNT=$(echo "$UPDATES" | grep -c "pending" || echo "0")

if [ "$UPDATE_COUNT" -gt 0 ]; then
    echo "✅ Found $UPDATE_COUNT image update(s) available"
    echo ""
    echo "$UPDATES" | grep "pending" || true
    echo ""
    echo "📄 Full report: $REPORT_FILE"
    echo ""
    echo "To apply updates:"
    echo "  ~/containers/scripts/update-before-reboot.sh"
else
    echo "✅ All images are up to date"
    echo "📄 Report saved: $REPORT_FILE"
fi
