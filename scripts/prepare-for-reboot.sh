#!/bin/bash
# prepare-for-reboot.sh — make a host reboot clean, safe, and verifiable.
#
# This script does NOT update containers. Image updates are deliberate and live
# elsewhere (ADR-030/036): scripts/adopt-baked.sh, driven by the monthly ritual
# in scripts/monthly-update.sh. The job here is the *reboot* itself:
#
#   1. Reboot-state manifest  pre-update-snapshot.sh writes a JSON inventory
#                             (images, every unit state, kernel/podman pkgs);
#                             post-reboot-verify.sh diffs it to prove a clean boot.
#   2. Graceful shutdown      graceful-shutdown.sh stops every container in
#                             reverse dependency order (apps -> DBs -> gateway) so
#                             databases quiesce cleanly. systemd would order this
#                             too (the quadlets carry After=/Requires= on their
#                             DBs), but doing it while the host is still up dodges
#                             the user@.service 60s stop budget — a slow neighbor
#                             can't SIGKILL a mid-flush DB.
#   3. Pinned-image presence  ensure every quadlet's pinned digest is in local
#                             storage so post-reboot auto-start can't strand a
#                             service on a missing image. ADR-030: pins are only
#                             *ensured present*, never re-floated (that takes a
#                             deliberate scripts/pin-container-image.sh edit).
#   4. Prune dangling images  housekeeping — untagged layers only.
#
# Then, by hand: sudo dnf update && sudo reboot && scripts/post-reboot-verify.sh
#
# Usage: ./scripts/prepare-for-reboot.sh [--skip-pull] [--dry-run]
#   --skip-pull   skip the pinned-image presence check (phase 3)
#   --dry-run     show the shutdown plan without stopping anything

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
echo "  PRE-REBOOT PREPARATION"
echo "================================================================"
echo ""

# Phase 1: Capture state manifest (the 'before' half of post-reboot-verify.sh)
echo "--- Phase 1: Reboot-State Manifest ---"
"$SCRIPT_DIR/pre-update-snapshot.sh"
echo ""

# Phase 2: Graceful shutdown
echo "--- Phase 2: Graceful Shutdown ---"
"$SCRIPT_DIR/graceful-shutdown.sh" $DRY_RUN
echo ""

# Phase 3: Verify quadlet images present (digest-aware, ADR-030)
# Reboot-readiness check, NOT an update. Pull list is derived from quadlet
# Image= lines, NOT `podman images`. Pinned (@sha256:) refs are *ensured present*
# (a no-op if already local) and never re-floated; only mutable tags are pulled
# fresh. Digest pins move only via a deliberate edit (scripts/pin-container-image.sh),
# never via this reboot path.
if ! $SKIP_PULL && [ -z "$DRY_RUN" ]; then
    echo "--- Phase 3: Verify Pinned Images Present (digest-aware) ---"
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
    echo "--- Phase 3: Verify Pinned Images Present (skipped) ---"
    echo ""
fi

# Phase 4: Prune dangling images (housekeeping — untagged layers only)
if [ -z "$DRY_RUN" ]; then
    echo "--- Phase 4: Prune Dangling Images ---"
    podman image prune -f
    echo ""
fi

# Summary
echo "================================================================"
echo "  PRE-REBOOT PREPARATION COMPLETE"
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
