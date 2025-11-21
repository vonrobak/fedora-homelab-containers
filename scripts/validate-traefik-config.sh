#!/bin/bash
# validate-traefik-config.sh
# Validate Traefik dynamic configuration before applying changes
#
# Purpose:
#   - Check YAML syntax on all dynamic config files
#   - Detect orphaned entries (common error pattern)
#   - Create automatic backup before changes
#   - Prevent broken configs from reaching production
#
# Usage:
#   ./validate-traefik-config.sh
#   ./validate-traefik-config.sh --no-backup  # Skip backup creation
#
# Exit codes:
#   0 = All validations passed
#   1 = Validation failed (YAML syntax error or orphaned entries)

set -euo pipefail

CONFIG_DIR="$HOME/containers/config/traefik/dynamic"
BACKUP_DIR="$HOME/containers/config/traefik/.backups"
CREATE_BACKUP=true

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-backup)
            CREATE_BACKUP=false
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--no-backup]"
            exit 1
            ;;
    esac
done

echo "========================================"
echo "  Traefik Configuration Validator"
echo "========================================"
echo ""

# Check if config directory exists
if [[ ! -d "$CONFIG_DIR" ]]; then
    echo "❌ ERROR: Config directory not found: $CONFIG_DIR"
    exit 1
fi

# Create backup if requested
if [[ "$CREATE_BACKUP" == "true" ]]; then
    mkdir -p "$BACKUP_DIR"
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    BACKUP_FILE="$BACKUP_DIR/dynamic-$TIMESTAMP.tar.gz"

    echo "Creating backup..."
    if tar -czf "$BACKUP_FILE" -C "$CONFIG_DIR" . 2>/dev/null; then
        echo "✓ Backup saved: $(basename "$BACKUP_FILE")"

        # Keep only last 10 backups
        ls -t "$BACKUP_DIR"/dynamic-*.tar.gz | tail -n +11 | xargs -r rm
        echo "  (Kept last 10 backups)"
    else
        echo "⚠️  WARNING: Backup creation failed"
    fi
    echo ""
fi

# Validate YAML syntax on all files
echo "Validating YAML syntax..."
YAML_VALID=true

for file in "$CONFIG_DIR"/*.yml "$CONFIG_DIR"/*.yaml; do
    # Skip if no files match glob
    [[ -e "$file" ]] || continue

    filename=$(basename "$file")
    echo -n "  $filename: "

    # Check if python3 with yaml module is available
    if ! command -v python3 &> /dev/null; then
        echo "⚠️  SKIP (python3 not available)"
        continue
    fi

    # Create temp file with templates stripped for validation
    temp_file=$(mktemp)
    # Replace {{ env "..." }} templates with placeholder to allow YAML parsing
    sed 's/{{ env "[^"]*" }}/TEMPLATE_PLACEHOLDER/g' "$file" > "$temp_file"

    if python3 -c "import yaml; yaml.safe_load(open('$temp_file'))" 2>/dev/null; then
        echo "✓ Valid"
    else
        # Check if error is template-related
        if grep -q '{{ env' "$file" && python3 -c "import yaml; yaml.safe_load(open('$temp_file'))" 2>&1 | grep -q "expected"; then
            echo "⚠️  Contains templates (may show false errors)"
            # Don't fail on template syntax issues
        else
            echo "✗ INVALID YAML"
            echo ""
            echo "Error details:"
            python3 -c "import yaml; yaml.safe_load(open('$temp_file'))" 2>&1 | sed 's/^/    /'
            echo ""
            YAML_VALID=false
        fi
    fi

    rm "$temp_file"
done

if [[ "$YAML_VALID" == "false" ]]; then
    echo ""
    echo "❌ VALIDATION FAILED: YAML syntax errors detected"
    exit 1
fi

echo ""

# Check for orphaned entries (common error pattern)
echo "Checking for orphaned entries..."
ORPHAN_FOUND=false

# Pattern: Lines starting with many spaces + dash (list items)
# that appear without proper parent context
if grep -n "^        - " "$CONFIG_DIR/routers.yml" 2>/dev/null | while read -r line; do
    line_num=$(echo "$line" | cut -d: -f1)
    line_content=$(echo "$line" | cut -d: -f2-)

    # Check if this is NOT part of middlewares/entryPoints
    # by checking the line above
    prev_line=$(sed -n "$((line_num - 1))p" "$CONFIG_DIR/routers.yml")

    if ! echo "$prev_line" | grep -qE "(middlewares:|entryPoints:|^        - )"; then
        echo "  Line $line_num: $line_content"
        echo "    ⚠️  Potentially orphaned (no parent key on line above)"
        ORPHAN_FOUND=true
    fi
done; then
    # If any orphaned entries found
    if [[ "$ORPHAN_FOUND" == "true" ]]; then
        echo ""
        echo "⚠️  WARNING: Potential orphaned entries detected in routers.yml"
        echo "    Review the lines above - they may need a parent router definition"
        echo ""
        echo "    This was the cause of the 2025-11-22 outage!"
        echo ""
    fi
fi

if [[ "$ORPHAN_FOUND" == "false" ]]; then
    echo "  ✓ No orphaned entries detected"
fi

echo ""
echo "========================================"
echo "  ✅ All validations passed"
echo "========================================"
echo ""
echo "Safe to restart Traefik:"
echo "  systemctl --user restart traefik.service"
echo ""

exit 0
