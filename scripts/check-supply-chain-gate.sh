#!/bin/bash
# check-supply-chain-gate.sh — ADR-030 supply-chain invariant gate (pre-commit / CI).
#
# Fails (exit 1) if any ADR-030 invariant is violated, so a regression can't land silently:
#   (P4) egress: a reverse_proxy-tier image is floating (mutable tag) or auto-updating
#        — delegates to audit-egress-updates.sh.
#   (P5) build inputs: a local build's base image (FROM) is not digest-pinned (…@sha256).
#   (P6) authenticity: a known signer's image LAST FAILED verification (a tamper signal;
#        the metric only carries a 0 when verify-image-signature.sh fail-closed).
#
# Fast (greps + one metric read) and side-effect-free → safe to run on every commit.
# Escape hatch (documented in the hook): git commit --no-verify.
# Exit: 0 all invariants hold, 1 one or more violated.
set -uo pipefail

# Worktree-aware root: pre-commit hooks run with cwd = the committing
# worktree's toplevel, so prefer the enclosing repo — validate the tree being
# committed, not the live one. REPO_ROOT env overrides; fall back to the live
# tree for ad-hoc runs outside any repo.
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
REPO_ROOT="${REPO_ROOT:-$HOME/containers}"
QUADLET_DIR="${QUADLET_DIR:-$REPO_ROOT/quadlets}"
# Runtime state, NOT tree content: data/ is gitignored (absent in worktrees),
# and the latest signature verdict is a property of the live system either way.
METRIC_FILE="${METRIC_FILE:-$HOME/containers/data/backup-metrics/supply-chain-signatures.prom}"
fail=0

# (P4) egress integrity + de-automation — reuse the existing guard verbatim.
if [ -x "$REPO_ROOT/scripts/audit-egress-updates.sh" ]; then
    if ! out="$(QUADLET_DIR="$QUADLET_DIR" "$REPO_ROOT/scripts/audit-egress-updates.sh" 2>&1)"; then
        echo "  ✗ P4 egress invariant violated:" >&2
        printf '%s\n' "$out" | sed 's/^/      /' >&2
        fail=1
    fi
fi

# (P5) local-build base images must be digest-pinned.
for f in "$QUADLET_DIR"/*.container; do
    [ -e "$f" ] || continue
    img="$(grep -m1 -E '^Image=' "$f" 2>/dev/null | sed 's/^Image=//' | tr -d '[:space:]')"
    [[ "$img" == localhost/* ]] || continue
    name="$(basename "$f" .container)"
    bf=""
    for cand in "$REPO_ROOT/config/$name/Containerfile" "$REPO_ROOT/config/$name/Dockerfile" \
                "$REPO_ROOT/builds/$name/Containerfile"  "$REPO_ROOT/builds/$name/Dockerfile"; do
        [ -f "$cand" ] && { bf="$cand"; break; }
    done
    [ -n "$bf" ] || continue
    if ! grep -m1 -E '^[[:space:]]*FROM[[:space:]]' "$bf" | grep -q '@sha256:'; then
        echo "  ✗ P5 build-input invariant violated: $name base not digest-pinned (FROM …@sha256) in ${bf#$REPO_ROOT/}" >&2
        fail=1
    fi
done

# (P6) a known signer's last verification FAILED → possible tampering; block the commit.
if [ -f "$METRIC_FILE" ] && grep -qE '^supply_chain_signature_verify\{[^}]*\} 0$' "$METRIC_FILE"; then
    svc="$(grep -E '^supply_chain_signature_verify\{[^}]*\} 0$' "$METRIC_FILE" \
           | sed -E 's/.*service="([^"]+)".*/\1/' | paste -sd, -)"
    echo "  ✗ P6 authenticity invariant violated: signature FAILED for: $svc" >&2
    echo "      investigate scripts/verify-image-signature.sh before committing (possible tampering)" >&2
    fail=1
fi

[ "$fail" -eq 0 ] && echo "  ✓ ADR-030 invariants hold (egress pinned+de-automated, local bases pinned, no signature failures)"
exit $fail
