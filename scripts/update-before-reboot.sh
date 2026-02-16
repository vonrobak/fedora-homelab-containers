#!/bin/bash
# update-before-reboot.sh
# Orchestrates pre-update workflow: snapshot -> graceful shutdown -> pull -> prune
#
# Usage: ./scripts/update-before-reboot.sh [--skip-pull] [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SKIP_PULL=false
DRY_RUN=""

for arg in "$@"; do
    case "$arg" in
        --skip-pull) SKIP_PULL=true ;;
        --dry-run) DRY_RUN="--dry-run" ;;
    esac
done

echo "================================================================"
echo "  PRE-UPDATE WORKFLOW"
echo "================================================================"
echo ""

# Phase 1: Capture state snapshot
echo "--- Phase 1: State Snapshot ---"
"$SCRIPT_DIR/pre-update-snapshot.sh"
echo ""

# Phase 2: Graceful shutdown
echo "--- Phase 2: Graceful Shutdown ---"
"$SCRIPT_DIR/graceful-shutdown.sh" $DRY_RUN
echo ""

# Phase 3: Pull latest images
if ! $SKIP_PULL && [ -z "$DRY_RUN" ]; then
    echo "--- Phase 3: Pull Latest Images ---"
    echo "Pulling latest images..."
    IMAGES=$(podman images --format "{{.Repository}}:{{.Tag}}" | grep -v "<none>" | sort -u)
    PULLED=0
    FAILED=0
    echo "$IMAGES" | while read -r IMAGE; do
        echo -n "  $IMAGE... "
        if podman pull "$IMAGE" >/dev/null 2>&1; then
            echo "OK"
            PULLED=$((PULLED + 1))
        else
            echo "SKIP (pull failed or unchanged)"
            FAILED=$((FAILED + 1))
        fi
    done
    echo ""
else
    echo "--- Phase 3: Pull Latest Images (skipped) ---"
    echo ""
fi

# Phase 4: Prune old images
if [ -z "$DRY_RUN" ]; then
    echo "--- Phase 4: Prune Old Images ---"
    podman image prune -f
    echo ""
fi

# Summary
echo "================================================================"
echo "  PRE-UPDATE COMPLETE"
echo "================================================================"
echo ""
echo "Next steps:"
echo "  1. sudo dnf update -y"
echo "  2. sudo reboot"
echo ""
echo "After reboot:"
echo "  3. Services auto-start via systemd quadlets"
echo "  4. Run: ./scripts/post-reboot-verify.sh"
echo ""
