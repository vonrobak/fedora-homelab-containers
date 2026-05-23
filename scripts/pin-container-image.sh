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
# Usage: pin-container-image.sh <container> [--deautomate] [--apply]
#   no --apply  -> dry-run, prints the proposed change
#   --deautomate -> also strip AutoUpdate=registry / Pull=newer lines
#
# Exit: 0 ok/dry-run/already-pinned, 2 error, 3 local build (Tier 2, skipped)
set -euo pipefail

QUADLET_DIR="${QUADLET_DIR:-$HOME/containers/quadlets}"
TODAY="$(date +%Y-%m-%d)"

c="${1:?usage: pin-container-image.sh <container> [--deautomate] [--apply]}"
shift || true
DEAUTO=false; APPLY=false
for a in "$@"; do
    case "$a" in
        --deautomate) DEAUTO=true ;;
        --apply)      APPLY=true ;;
        *) echo "unknown arg: $a" >&2; exit 2 ;;
    esac
done

f="$QUADLET_DIR/${c}.container"
[ -f "$f" ] || { echo "ERROR: no quadlet $f" >&2; exit 2; }

img="$(grep -m1 -E '^Image=' "$f" | sed 's/^Image=//' | tr -d '[:space:]')"
[ -n "$img" ] || { echo "ERROR: no Image= in $f" >&2; exit 2; }

case "$img" in
    *@sha256:*)  echo "$c: already digest-pinned — skipping"; exit 0 ;;
    localhost/*) echo "$c: local build ($img) — Tier 2 (build inputs), skipping"; exit 3 ;;
esac

repo="${img%:*}"   # strip :tag (no registry ports in use)
tag="${img##*:}"

D="$(podman inspect "$c" --format '{{.ImageDigest}}' 2>/dev/null || true)"
[ -n "$D" ] || { echo "ERROR: $c not running or no .ImageDigest" >&2; exit 2; }
case "$D" in sha256:*) ;; *) echo "ERROR: unexpected digest for $c: '$D'" >&2; exit 2 ;; esac

newref="${repo}@${D}"
podman image exists "$newref" || { echo "ERROR: pinned ref not present locally: $newref" >&2; exit 2; }

echo "== $c =="
echo "  was: Image=$img"
echo "  now: Image=$newref   (# tag: $tag)"
if $DEAUTO; then
    auto="$(grep -E '^(AutoUpdate|Pull)=' "$f" | paste -sd, - || true)"
    [ -n "$auto" ] && echo "  de-automate: removing [$auto]"
fi

$APPLY || { echo "  (dry-run — pass --apply to write)"; exit 0; }

cp "$f" "/tmp/$(basename "$f").bak.$(date +%s)"
tmp="$(mktemp)"
awk -v repo="$repo" -v digest="$D" -v tag="$tag" -v today="$TODAY" -v deauto="$DEAUTO" '
    /^Image=/ && !done {
        print "# ADR-030 P2: digest-pinned (integrity). tag: " tag ", resolved " today " (index digest, multi-arch)"
        if (deauto == "true")
            print "# ADR-030 P1/P4: AutoUpdate removed — deliberate updates only. Bump = resolve new digest, bake, edit, restart."
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
