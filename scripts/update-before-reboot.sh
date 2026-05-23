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

# Phase 3: Ensure quadlet images present (digest-aware, ADR-030)
# Pull list is derived from quadlet Image= lines, NOT `podman images`. This is
# the ADR-030 fix: pinned (@sha256:) refs are *ensured present* (a no-op if
# already local) and never re-floated; only mutable tags are pulled fresh.
# Digest pins move only via a deliberate edit (scripts/pin-container-image.sh),
# never via this reboot path.
if ! $SKIP_PULL && [ -z "$DRY_RUN" ]; then
    echo "--- Phase 3: Ensure Images Present (digest-aware) ---"
    QUADLET_DIR="${QUADLET_DIR:-$HOME/containers/quadlets}"
    ENSURED=0; PULLED=0; SKIPPED=0; FAILED=0
    while IFS= read -r IMAGE; do
        [ -n "$IMAGE" ] || continue
        case "$IMAGE" in
            localhost/*)
                echo "  $IMAGE... SKIP (local build)"; SKIPPED=$((SKIPPED+1)) ;;
            *@sha256:*)
                if podman image exists "$IMAGE"; then
                    echo "  ${IMAGE%@*}@…${IMAGE##*:}... present (pinned, no float)"; ENSURED=$((ENSURED+1))
                elif podman pull "$IMAGE" >/dev/null 2>&1; then
                    echo "  $IMAGE... fetched pinned digest"; ENSURED=$((ENSURED+1))
                else
                    echo "  $IMAGE... FAIL (pinned digest unavailable)"; FAILED=$((FAILED+1))
                fi ;;
            *)
                echo -n "  $IMAGE (mutable tag)... "
                if podman pull "$IMAGE" >/dev/null 2>&1; then echo "pulled"; PULLED=$((PULLED+1));
                else echo "SKIP (failed/unchanged)"; FAILED=$((FAILED+1)); fi ;;
        esac
    done < <(grep -hE '^Image=' "$QUADLET_DIR"/*.container | sed 's/^Image=//; s/[[:space:]]//g' | sort -u)
    echo "  (pinned ensured: $ENSURED, tags pulled: $PULLED, local skipped: $SKIPPED, failed: $FAILED)"
    echo ""
else
    echo "--- Phase 3: Ensure Images Present (skipped) ---"
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
