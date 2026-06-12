#!/bin/bash
# check-boot-tier.sh — ADR-035 boot-tier enforcement (WP2, 2026-06-12)
#
# Every quadlet .container file must take an explicit position on its boot tier:
#   - declare StartupCPUWeight= AND StartupIOWeight= (Tier A=200 / Tier C=50), or
#   - carry a literal "# Tier B (default 100)" comment.
# Without this gate, new services silently land at default weight and the
# tiering scheme decays one service at a time (the exact erosion that put
# prometheus/loki/grafana — the heaviest boot I/O producers — at default
# weight until the 2026-06-09 storm; see ADR-035).
#
# Wired into the local pre-commit chain (.git/hooks/pre-commit, which is not
# version-controlled — re-add a call to this script if the hook is rebuilt):
#   if ! "$REPO_ROOT/scripts/check-boot-tier.sh"; then CHECK_FAILED=1; fi
#
# Exit: 0 = all quadlets compliant, 1 = violations listed on stdout.

set -euo pipefail

# Worktree-aware root: pre-commit hooks run with cwd = the committing
# worktree's toplevel, so prefer the enclosing repo — validate the tree being
# committed, not the live one. REPO_ROOT env overrides; fall back to the live
# tree for ad-hoc runs outside any repo.
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
REPO_ROOT="${REPO_ROOT:-$HOME/containers}"
QUADLET_DIR="$REPO_ROOT/quadlets"
[[ -d "$QUADLET_DIR" ]] || { echo "ERROR: quadlet dir not found: $QUADLET_DIR" >&2; exit 2; }
FAIL=0

for f in "$QUADLET_DIR"/*.container; do
    name="$(basename "$f")"
    if grep -q '^StartupCPUWeight=' "$f" && grep -q '^StartupIOWeight=' "$f"; then
        continue
    fi
    if grep -q '# Tier B (default 100)' "$f"; then
        continue
    fi
    if [[ $FAIL -eq 0 ]]; then
        echo "ADR-035 boot-tier violations (declare Startup{CPU,IO}Weight or a '# Tier B (default 100)' comment):"
    fi
    echo "  ✗ $name"
    FAIL=1
done

if [[ $FAIL -eq 0 ]]; then
    echo "  ✓ All quadlets declare a boot tier (ADR-035)"
fi
exit $FAIL
