#!/bin/bash
# pin-container-image.sh — ADR-030 P2 digest-pinning helper.
#
# Pins a quadlet's Image= to the digest of the CURRENTLY RUNNING container
# (`podman inspect .ImageDigest` — the index digest the container was created
# from). This is drift-proof "pin what's baked": if the upstream tag has moved
# since the image was pulled, we still freeze the proven, running image rather
# than adopting an untested one. The human tag is preserved as a comment.
#
# Optionally removes AutoUpdate=registry / Pull=newer (ADR-030 P1/P4 de-automation).
#
# ADR-030 P6 (Tier 3): before applying a pin, the new digest is verified against the
# publisher's known signing identity via scripts/verify-image-signature.sh. A signer
# with a FAILED signature aborts the pin (fail-closed); an image with no signer entry
# proceeds (unsigned-but-tracked). This is authenticity enforcement at the moment of
# DELIBERATE adoption (P1) — see docs/97-plans/2026-05-24-tier3-…-deliberate-path.md.
#
# Two modes:
#   • first-pin (default): pin Image= to the running container's baked digest.
#   • adopt (--adopt <digest>): deliberately move an ALREADY-pinned service to a new
#     digest — the P1 "bump" path (resolve new digest → bake → adopt → restart). The
#     P6 gate verifies the target digest before it is written; the restart pulls it.
#
# Usage: pin-container-image.sh <container> [--adopt <digest|repo@digest>] \
#                               [--deautomate] [--apply] [--skip-verify]
#   no --apply    -> dry-run, prints the proposed change (and the signature status)
#   --adopt <d>   -> bump an already-pinned service to digest <d> (bare sha256:… or repo@sha256:…)
#   --deautomate  -> also strip AutoUpdate=registry / Pull=newer lines
#   --skip-verify -> bypass the P6 signature gate (LOUD, logged; for a reviewed
#                    publisher identity change only)
#
# Exit: 0 ok/dry-run/already-pinned, 2 error or P6 gate refused, 3 local build (Tier 2, skipped)
set -euo pipefail

QUADLET_DIR="${QUADLET_DIR:-$HOME/containers/quadlets}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TODAY="$(date +%Y-%m-%d)"

c="${1:?usage: pin-container-image.sh <container> [--adopt <digest>] [--deautomate] [--apply] [--skip-verify]}"
shift || true
DEAUTO=false; APPLY=false; SKIPVERIFY=false; ADOPT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --deautomate)  DEAUTO=true; shift ;;
        --apply)       APPLY=true; shift ;;
        --skip-verify) SKIPVERIFY=true; shift ;;
        --adopt)       ADOPT="${2:?--adopt needs a digest or repo@digest}"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

f="$QUADLET_DIR/${c}.container"
[ -f "$f" ] || { echo "ERROR: no quadlet $f" >&2; exit 2; }

img="$(grep -m1 -E '^Image=' "$f" | sed 's/^Image=//' | tr -d '[:space:]')"
[ -n "$img" ] || { echo "ERROR: no Image= in $f" >&2; exit 2; }

case "$img" in
    localhost/*) echo "$c: local build ($img) — Tier 2 (build inputs), skipping"; exit 3 ;;
esac

if [ -n "$ADOPT" ]; then
    # ADOPT MODE — deliberate bump of an already-pinned (or floating) service.
    repo="${img%@*}"; case "$repo" in *:*) repo="${repo%:*}";; esac
    case "$ADOPT" in
        *@sha256:*) D="${ADOPT##*@}"; adoptrepo="${ADOPT%@*}"
                    [ "$adoptrepo" = "$repo" ] || { echo "ERROR: --adopt repo ($adoptrepo) != quadlet repo ($repo)" >&2; exit 2; } ;;
        sha256:*)   D="$ADOPT" ;;
        *) echo "ERROR: --adopt must be sha256:… or ${repo}@sha256:…" >&2; exit 2 ;;
    esac
    tag="$(grep -m1 -oE 'tag: [^,]+' "$f" | sed 's/tag: //')"; [ -n "$tag" ] || tag="${img##*:}"
    case "$tag" in "$repo"|"$img") tag="latest" ;; esac
    REQUIRE_LOCAL=false
else
    # FIRST-PIN MODE — freeze the running container's baked digest ("pin what's baked").
    case "$img" in *@sha256:*) echo "$c: already digest-pinned — skipping (use --adopt <digest> to bump)"; exit 0 ;; esac
    repo="${img%:*}"   # strip :tag (no registry ports in use)
    tag="${img##*:}"
    D="$(podman inspect "$c" --format '{{.ImageDigest}}' 2>/dev/null || true)"
    [ -n "$D" ] || { echo "ERROR: $c not running or no .ImageDigest" >&2; exit 2; }
    REQUIRE_LOCAL=true
fi
case "$D" in sha256:*) ;; *) echo "ERROR: unexpected digest for $c: '$D'" >&2; exit 2 ;; esac

newref="${repo}@${D}"
if $REQUIRE_LOCAL; then
    podman image exists "$newref" || { echo "ERROR: pinned ref not present locally: $newref" >&2; exit 2; }
fi

echo "== $c =="
echo "  was: Image=$img"
echo "  now: Image=$newref   (# tag: $tag)"
if $DEAUTO; then
    auto="$(grep -E '^(AutoUpdate|Pull)=' "$f" | paste -sd, - || true)"
    [ -n "$auto" ] && echo "  de-automate: removing [$auto]"
fi

# --- ADR-030 P6 signature gate (Tier 3, deliberate-path authenticity) ---------
P6COMMENT=""
if $SKIPVERIFY; then
    echo "  ⚠️  P6 signature gate SKIPPED (--skip-verify) for $newref"
    P6COMMENT="# ADR-030 P6: signature verification SKIPPED via --skip-verify ($TODAY)"
else
    vargs=("$newref" --service "$c")
    $APPLY && vargs+=(--metric)
    set +e
    "$SCRIPT_DIR/verify-image-signature.sh" "${vargs[@]}"
    vrc=$?
    set -e
    case "$vrc" in
        0) P6COMMENT="# ADR-030 P6: publisher signature verified ($TODAY)" ;;
        3) P6COMMENT="# ADR-030 P6: no publisher signature (tracked unsigned)" ;;
        1) echo "  ❌ P6 GATE: signature verification FAILED for $newref — refusing to pin." >&2
           echo "     Review the publisher's signing identity; use --skip-verify only after manual verification." >&2
           exit 2 ;;
        2) echo "  ⚠️  P6 GATE: signature check could not complete (tooling/network) for $newref — not pinning." >&2
           echo "     Retry, or pass --skip-verify to override deliberately." >&2
           exit 2 ;;
        *) echo "  ⚠️  P6 GATE: unexpected verifier exit ($vrc) — not pinning." >&2; exit 2 ;;
    esac
fi

$APPLY || { echo "  (dry-run — pass --apply to write)"; exit 0; }

cp "$f" "/tmp/$(basename "$f").bak.$(date +%s)"
had_p14=0; grep -q '^# ADR-030 P1/P4:' "$f" && had_p14=1
tmp="$(mktemp)"
awk -v repo="$repo" -v digest="$D" -v tag="$tag" -v today="$TODAY" -v deauto="$DEAUTO" \
    -v p6="$P6COMMENT" -v had_p14="$had_p14" '
    # drop any pre-existing ADR-030 pin comments so re-pin (--adopt) stays idempotent
    /^# ADR-030 P2:/      { next }
    /^# ADR-030 P1\/P4:/  { next }
    /^# ADR-030 P6:/      { next }
    /^Image=/ && !done {
        print "# ADR-030 P2: digest-pinned (integrity). tag: " tag ", resolved " today " (index digest, multi-arch)"
        if (deauto == "true" || had_p14 == "1")
            print "# ADR-030 P1/P4: AutoUpdate removed — deliberate updates only. Bump = adopt new digest (pin-container-image.sh --adopt), bake, restart."
        if (p6 != "") print p6
        print "Image=" repo "@" digest
        done=1
        next
    }
    deauto == "true" && /^AutoUpdate=registry[[:space:]]*$/ { next }
    deauto == "true" && /^Pull=newer[[:space:]]*$/          { next }
    { print }
' "$f" > "$tmp"
mv "$tmp" "$f"
echo "  applied: $f"
