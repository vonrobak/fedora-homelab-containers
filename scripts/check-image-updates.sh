#!/bin/bash
# check-image-updates.sh — ADR-030 notify-only update feed (skopeo digest-diff).
#
# Replaces the old `podman auto-update --dry-run` feed, which could only see
# containers carrying AutoUpdate=registry. Now that production images are
# digest-pinned (ADR-030 P2) and de-automated (P1), this compares each pinned
# digest against the current registry digest for its tag and reports what *could*
# be deliberately bumped. It NEVER pulls or changes anything — visibility only,
# preserving "trust is accepted deliberately" (P1).
#
# To adopt an available update: bake (P3), then (the digest is verified at this step,
# ADR-030 P6):
#   scripts/pin-container-image.sh <svc> --adopt <new-digest> --apply
#   systemctl --user daemon-reload && systemctl --user restart <svc>.service
#
# NOTE: no `set -e` — a single image's skopeo failure must not abort the sweep.
set -uo pipefail

QUADLET_DIR="${QUADLET_DIR:-$HOME/containers/quadlets}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIGNERS_FILE="${SIGNERS_FILE:-$HOME/containers/config/supply-chain/signers.yaml}"
REPORT_FILE="$HOME/containers/docs/99-reports/image-updates-$(date +%Y%m%d).txt"
mkdir -p "$(dirname "$REPORT_FILE")"

# ADR-030 P6 (Tier 3): pre-load repos that have a known signer so we can verify the
# AVAILABLE digest and front-load the trust signal BEFORE a deliberate adopt (advisory).
declare -A SIGNER_REPOS=()
if [ -f "$SIGNERS_FILE" ]; then
    while IFS= read -r r; do [ -n "$r" ] && SIGNER_REPOS["$r"]=1; done < <(
        python3 -c "import yaml; d=yaml.safe_load(open('$SIGNERS_FILE')) or {}; [print(s.get('repo','')) for s in (d.get('signers') or [])]" 2>/dev/null)
fi

updates=(); failed=(); local_builds=(); uptodate=0

for f in "$QUADLET_DIR"/*.container; do
    name="$(basename "$f" .container)"
    img="$(grep -m1 -E '^Image=' "$f" | sed 's/^Image=//' | tr -d '[:space:]')"
    [ -n "$img" ] || continue

    if [[ "$img" == localhost/* ]]; then
        local_builds+=("$name (${img})"); continue
    fi
    if [[ "$img" != *@sha256:* ]]; then
        updates+=("$name: ⚠️ FLOATING (not digest-pinned): $img"); continue
    fi

    repo="${img%@*}"; pinned="${img##*@}"
    tag="$(grep -m1 -oE 'tag: [^,]+' "$f" | sed 's/tag: //')"; [ -n "$tag" ] || tag="latest"

    current="$(timeout 30 skopeo inspect "docker://${repo}:${tag}" --format '{{.Digest}}' 2>/dev/null)"
    if [ -z "$current" ]; then
        sleep 2  # registries (esp. GHCR/Docker Hub) throttle bursts — retry once
        current="$(timeout 30 skopeo inspect "docker://${repo}:${tag}" --format '{{.Digest}}' 2>/dev/null)"
    fi
    if [ -z "$current" ]; then
        failed+=("$name (${repo}:${tag})"); continue
    fi
    sleep 0.2  # be gentle on registries between checks

    # ADR-030 P6 advisory: if this repo has a known signer, verify the AVAILABLE digest
    signote=""
    if [ -n "${SIGNER_REPOS[$repo]:-}" ]; then
        "$SCRIPT_DIR/verify-image-signature.sh" "${repo}@${current}" --quiet >/dev/null 2>&1
        case $? in
            0) signote="  [✓ signature verified]" ;;
            1) signote="  [✗ SIGNATURE FAILED — do not adopt]" ;;
            *) signote="  [⚠ signature check error]" ;;
        esac
    fi

    if [ "$current" != "$pinned" ]; then
        updates+=("$name | ${repo}:${tag} | pinned ${pinned:0:19}… → available ${current:0:19}…${signote}")
    else
        uptodate=$((uptodate+1))
        [ -n "$signote" ] && updates+=("$name | ${repo}:${tag} | up-to-date${signote}")
    fi
done

{
    echo "Container Image Update Check (ADR-030 notify-only / skopeo digest-diff)"
    echo "Generated: $(date)"
    echo "========================================"
    echo ""
    echo "Up to date (pinned == current tag digest): ${uptodate}"
    echo "Updates available: ${#updates[@]}"
    echo "Local builds (rebuild to update, Tier 2): ${#local_builds[@]}"
    echo "Check failed (registry unreachable / rate-limited): ${#failed[@]}"
    echo ""
    if [ ${#updates[@]} -gt 0 ]; then
        echo "--- UPDATES AVAILABLE ---"
        printf '%s\n' "${updates[@]}"
        echo ""
    fi
    if [ ${#local_builds[@]} -gt 0 ]; then
        echo "--- LOCAL BUILDS (Tier 2 build-input pinning) ---"
        printf '%s\n' "${local_builds[@]}"
        echo ""
    fi
    if [ ${#failed[@]} -gt 0 ]; then
        echo "--- CHECK FAILED ---"
        printf '%s\n' "${failed[@]}"
        echo ""
    fi
    echo "========================================"
    echo "To adopt an update deliberately (after a bake interval, P3; digest is"
    echo "signature-verified at adopt time per ADR-030 P6):"
    echo "  scripts/pin-container-image.sh <svc> --adopt <available-digest> --apply"
    echo "  systemctl --user daemon-reload && systemctl --user restart <svc>.service"
} > "$REPORT_FILE"

echo "🔍 Image update check complete → $REPORT_FILE"
echo "   up-to-date=$uptodate  available=${#updates[@]}  local=${#local_builds[@]}  failed=${#failed[@]}"
if [ ${#updates[@]} -gt 0 ]; then
    echo ""
    printf '   • %s\n' "${updates[@]}"
fi
