#!/usr/bin/env bash
#
# Compare actual quadlets with git-tracked copies
# Purpose: Identify differences between deployed and version-controlled quadlets
#

set -euo pipefail

ACTUAL_DIR="${HOME}/.config/containers/systemd"
GIT_DIR="${HOME}/containers/quadlets"

echo "════════════════════════════════════════════════════════"
echo "  QUADLET COMPARISON: Actual vs Git"
echo "════════════════════════════════════════════════════════"
echo ""
echo "Actual location:  ${ACTUAL_DIR}"
echo "Git location:     ${GIT_DIR}"
echo ""

# Check if directories exist
if [ ! -d "$ACTUAL_DIR" ]; then
    echo "ERROR: Actual quadlets directory not found: $ACTUAL_DIR"
    exit 1
fi

if [ ! -d "$GIT_DIR" ]; then
    echo "ERROR: Git quadlets directory not found: $GIT_DIR"
    exit 1
fi

# Services we modified in Phase 1
MODIFIED_SERVICES=(
    "crowdsec.container"
    "promtail.container"
    "alert-discord-relay.container"
    "traefik.container"
    "redis-immich.container"
    "alertmanager.container"
)

echo "════════════════════════════════════════════════════════"
echo "  PHASE 1 MODIFIED FILES"
echo "════════════════════════════════════════════════════════"
echo ""

for service in "${MODIFIED_SERVICES[@]}"; do
    echo "─────────────────────────────────────────────────────"
    echo "  $service"
    echo "─────────────────────────────────────────────────────"

    actual_file="${ACTUAL_DIR}/${service}"
    git_file="${GIT_DIR}/${service}"

    if [ ! -f "$actual_file" ]; then
        echo "⚠️  MISSING in actual directory"
        echo ""
        continue
    fi

    if [ ! -f "$git_file" ]; then
        echo "⚠️  MISSING in git directory"
        echo ""
        continue
    fi

    # Compare files
    if diff -q "$actual_file" "$git_file" &>/dev/null; then
        echo "✅ Files are IDENTICAL"
    else
        echo "❌ Files are DIFFERENT"
        echo ""
        echo "Showing diff (actual -> git):"
        echo ""
        diff -u "$actual_file" "$git_file" || true
    fi

    echo ""
done

echo "════════════════════════════════════════════════════════"
echo "  CONFIGURATION DRIFT (alloy.container)"
echo "════════════════════════════════════════════════════════"
echo ""

if [ -f "${ACTUAL_DIR}/alloy.container" ]; then
    echo "⚠️  alloy.container EXISTS in actual directory"
    echo "   (We removed it from git, but it's still deployed)"
else
    echo "✅ alloy.container REMOVED from actual directory"
fi

echo ""

echo "════════════════════════════════════════════════════════"
echo "  SUMMARY"
echo "════════════════════════════════════════════════════════"
echo ""
echo "Files in actual directory:"
ls -1 "$ACTUAL_DIR"/*.container 2>/dev/null | wc -l

echo "Files in git directory:"
ls -1 "$GIT_DIR"/*.container 2>/dev/null | wc -l

echo ""
echo "To sync git → actual:"
echo "  cp ~/containers/quadlets/*.container ~/.config/containers/systemd/"
echo "  systemctl --user daemon-reload"
echo ""
echo "To sync actual → git:"
echo "  cp ~/.config/containers/systemd/*.container ~/containers/quadlets/"
echo "  cd ~/containers && git add quadlets/ && git status"
echo ""
