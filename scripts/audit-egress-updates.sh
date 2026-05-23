#!/bin/bash
# audit-egress-updates.sh — ADR-030 P4 egress/blast-radius guard.
#
# Sibling to audit-update-paths.sh (which guards the STATEFULNESS axis for
# availability). This guards the EGRESS axis for supply-chain risk: every
# internet-facing service (reverse_proxy network member) must be
#   (a) digest-pinned (no mutable tag), and
#   (b) free of AutoUpdate=registry / Pull=newer (no unattended trust acceptance).
# Local builds (localhost/*) are exempt from (a) — their integrity is a Tier 2
# build-input concern — but are still held to (b).
#
# Exit: 0 clean, 1 violation, 2 usage/missing input
set -euo pipefail

QUADLET_DIR="${QUADLET_DIR:-$HOME/containers/quadlets}"
[ -d "$QUADLET_DIR" ] || { echo "ERROR: quadlet dir not found: $QUADLET_DIR" >&2; exit 2; }

is_egress() { grep -qE '^Network=systemd-reverse_proxy' "$1"; }

violations=()
for f in "$QUADLET_DIR"/*.container; do
    name="$(basename "$f" .container)"
    is_egress "$f" || continue
    img="$(grep -m1 -E '^Image=' "$f" | sed 's/^Image=//' | tr -d '[:space:]')"

    # (b) no unattended trust acceptance — applies to all egress services
    if grep -qE '^AutoUpdate=registry' "$f"; then
        violations+=("$name: egress-tier carries AutoUpdate=registry")
    fi
    if grep -qE '^Pull=newer' "$f"; then
        violations+=("$name: egress-tier carries Pull=newer")
    fi

    # (a) integrity by content address — registry images only (skip local builds)
    if [[ "$img" != localhost/* && "$img" != *@sha256:* ]]; then
        violations+=("$name: egress-tier image is floating (mutable tag): $img")
    fi
done

if [ ${#violations[@]} -eq 0 ]; then
    echo "audit-egress-updates: OK — all egress-tier services are digest-pinned and de-automated"
    exit 0
fi

echo "audit-egress-updates: VIOLATION — ${#violations[@]} egress-tier issue(s):" >&2
for v in "${violations[@]}"; do echo "  - $v" >&2; done
echo "" >&2
echo "ADR-030 P4: internet-facing (reverse_proxy) services must be digest-pinned and" >&2
echo "must not auto-update. Fix with: scripts/pin-container-image.sh <svc> --deautomate --apply" >&2
echo "then: systemctl --user daemon-reload && systemctl --user restart <svc>.service" >&2
exit 1
