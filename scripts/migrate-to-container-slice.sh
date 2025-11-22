#!/bin/bash
# migrate-to-container-slice.sh
# Add container.slice to all container quadlet files
#
# This script safely adds "Slice=container.slice" to the [Service] section
# of each .container file, creating the section if it doesn't exist.

set -euo pipefail

QUADLET_DIR="$HOME/.config/containers/systemd"
BACKUP_DIR="$HOME/.config/containers/systemd/.backup-$(date +%Y%m%d-%H%M%S)"

echo "========================================="
echo "  Migrate Containers to container.slice"
echo "========================================="
echo ""

# Create backup
echo "Creating backup..."
mkdir -p "$BACKUP_DIR"
cp "$QUADLET_DIR"/*.container "$BACKUP_DIR/" 2>/dev/null || true
echo "✓ Backup saved: $BACKUP_DIR"
echo ""

# Process each container
echo "Updating quadlet files..."
for file in "$QUADLET_DIR"/*.container; do
    [[ -e "$file" ]] || continue

    filename=$(basename "$file")
    echo -n "  $filename: "

    # Check if already has Slice= line
    if grep -q "^Slice=" "$file"; then
        echo "⊘ Already has Slice directive"
        continue
    fi

    # Check if has [Service] section
    if grep -q "^\[Service\]" "$file"; then
        # Add Slice= after [Service] line
        sed -i '/^\[Service\]/a Slice=container.slice' "$file"
        echo "✓ Added to existing [Service] section"
    else
        # Add [Service] section at end of file
        echo "" >> "$file"
        echo "[Service]" >> "$file"
        echo "Slice=container.slice" >> "$file"
        echo "✓ Created [Service] section with Slice"
    fi
done

echo ""
echo "========================================="
echo "  ✅ Migration Complete"
echo "========================================="
echo ""
echo "Next steps:"
echo "  1. Review changes: diff -r $BACKUP_DIR $QUADLET_DIR"
echo "  2. Reload systemd: systemctl --user daemon-reload"
echo "  3. Restart services: systemctl --user restart <service>.service"
echo ""
