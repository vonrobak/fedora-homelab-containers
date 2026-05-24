#!/bin/bash
# generate-image-pin-index.sh — ADR-030 audit index (the "audit view").
#
# Parses every quadlet's Image= line and emits one reviewable document mapping
# service → repo → pinned digest → tag → mutability → egress-tier → auto-update.
# Centralises the audit view without a central write path (digests stay in the
# quadlets where Podman reads them). See ADR-030 "Architecture: where digests live".
#
# Local builds (localhost/*) have no registry digest; under Tier 2 their trust
# anchor is the build inputs. This script reports each local build's base-image
# pin state (FROM …@sha256) so an un-pinned base shows up as a regression.
set -euo pipefail

QUADLET_DIR="${QUADLET_DIR:-$HOME/containers/quadlets}"
REPO_ROOT="${REPO_ROOT:-$HOME/containers}"
OUTPUT_FILE="${OUTPUT_FILE:-$HOME/containers/docs/AUTO-IMAGE-PIN-INDEX.md}"
SIGNERS_FILE="${SIGNERS_FILE:-$REPO_ROOT/config/supply-chain/signers.yaml}"
METRIC_FILE="${METRIC_FILE:-$REPO_ROOT/data/backup-metrics/supply-chain-signatures.prom}"

is_egress() { grep -qE '^Network=systemd-reverse_proxy' "$1"; }

# ADR-030 P6 (Tier 3): the "Signed" column is derived from local state only (fast, no
# network) — signer membership (signers.yaml) + last verify result (the .prom metric
# written by verify-image-signature.sh at adopt time). It is NOT a live cosign check.
declare -A SIGNER_REPOS=()
if [ -f "$SIGNERS_FILE" ]; then
    while IFS= read -r r; do [ -n "$r" ] && SIGNER_REPOS["$r"]=1; done < <(
        python3 -c "import yaml; d=yaml.safe_load(open('$SIGNERS_FILE')) or {}; [print(s.get('repo','')) for s in (d.get('signers') or [])]" 2>/dev/null)
fi
declare -A VERIFY_RESULT=()
if [ -f "$METRIC_FILE" ]; then
    while IFS= read -r line; do
        case "$line" in
            supply_chain_signature_verify\{*)
                rp="${line#*repo=\"}"; rp="${rp%%\"*}"; VERIFY_RESULT["$rp"]="${line##* }" ;;
        esac
    done < "$METRIC_FILE"
fi

# For a localhost build, find its build file and report base-pin state.
# Echoes: "<pinned|floating|unknown> <full-base-digest-or-->"
localbuild_base() {
    local name="$1" bf="" from="" cand
    for cand in \
        "$REPO_ROOT/config/$name/Dockerfile" "$REPO_ROOT/config/$name/Containerfile" \
        "$REPO_ROOT/builds/$name/Containerfile" "$REPO_ROOT/builds/$name/Dockerfile"; do
        [ -f "$cand" ] && { bf="$cand"; break; }
    done
    if [ -z "$bf" ]; then echo "unknown —"; return; fi
    from="$(grep -m1 -E '^[[:space:]]*FROM[[:space:]]' "$bf" || true)"
    if [[ "$from" == *@sha256:* ]]; then
        local d="${from##*@}"; d="${d%% *}"   # strip any trailing token
        echo "pinned $d"
    else
        echo "floating —"
    fi
}

rows=""
pinned=0; floating=0; local_builds=0; egress_floating=0; egress_auto=0; total=0
local_base_floating=0; signers_count=0; signers_failed=0

for f in "$QUADLET_DIR"/*.container; do
    name="$(basename "$f" .container)"
    img="$(grep -m1 -E '^Image=' "$f" | sed 's/^Image=//' | tr -d '[:space:]')"
    [ -n "$img" ] || continue
    total=$((total+1))

    egress="no"; is_egress "$f" && egress="yes"
    auto="no"; grep -qE '^AutoUpdate=registry' "$f" && auto="yes"
    grep -qE '^Pull=newer' "$f" && auto="yes(+Pull)"

    if [[ "$img" == localhost/* ]]; then
        repo="${img%:*}"; tag="${img##*:}"
        read -r bstate digest <<<"$(localbuild_base "$name")"
        case "$bstate" in
            pinned)   status="🔨 base-pinned" ;;
            floating) status="🔨 base-FLOATING"; local_base_floating=$((local_base_floating+1)) ;;
            *)        status="🔨 local-build" ;;
        esac
        local_builds=$((local_builds+1))
    elif [[ "$img" == *@sha256:* ]]; then
        repo="${img%@*}"; digest="${img##*@}"; status="🔒 pinned"
        # tag preserved in the ADR-030 comment immediately above the Image line
        tag="$(grep -m1 -oE 'tag: [^,]+' "$f" | sed 's/tag: //' || true)"
        [ -n "$tag" ] || tag="?"
        pinned=$((pinned+1))
    else
        repo="${img%:*}"; tag="${img##*:}"; digest="—"; status="⚠️ FLOATING"
        floating=$((floating+1))
        [ "$egress" = yes ] && egress_floating=$((egress_floating+1))
    fi

    [ "$auto" != "no" ] && [ "$egress" = yes ] && egress_auto=$((egress_auto+1))

    # ADR-030 P6 signed-state (local-derived: signer membership + last verify metric)
    if [[ "$img" == localhost/* ]]; then
        signed="n/a (Tier 2)"
    elif [ -n "${SIGNER_REPOS[$repo]:-}" ]; then
        signers_count=$((signers_count+1))
        case "${VERIFY_RESULT[$repo]:-}" in
            1) signed="✓ verified" ;;
            0) signed="✗ FAILED"; signers_failed=$((signers_failed+1)) ;;
            *) signed="signer (pending)" ;;
        esac
    else
        signed="— unsigned"
    fi

    short_digest="$digest"
    [ "$digest" != "—" ] && short_digest="${digest:0:19}…"
    rows+="| ${name} | ${egress} | ${status} | \`${repo}\` | ${tag} | \`${short_digest}\` | ${auto} | ${signed} |"$'\n'
done

{
    echo "# Container Image Pin Index (Auto-Generated)"
    echo ""
    echo "**Generated:** $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "**Source:** \`${QUADLET_DIR}\` — ADR-030 (Container Supply-Chain Trust Model)"
    echo ""
    echo "Pins live in each quadlet's \`Image=\` line (where Podman reads them); this is"
    echo "the aggregated audit view. \`tag\` is the discovery handle; the digest is the"
    echo "execution contract. Update = resolve a new digest, bake, edit the quadlet, restart."
    echo "For local builds the \`Digest\` column shows the **base image** pin (FROM …@sha256)."
    echo ""
    echo "## Summary"
    echo ""
    echo "| Metric | Count |"
    echo "|--------|-------|"
    echo "| Total images | ${total} |"
    echo "| 🔒 Digest-pinned | ${pinned} |"
    echo "| ⚠️ Floating (mutable tag) | ${floating} |"
    echo "| 🔨 Local builds | ${local_builds} |"
    echo "| 🔨 Local builds with FLOATING base | ${local_base_floating} |"
    echo "| Egress-tier still floating | ${egress_floating} |"
    echo "| Egress-tier still auto-updating | ${egress_auto} |"
    echo "| 🔏 P6 signers (authenticity-verified on adopt) | ${signers_count} |"
    echo "| ✗ P6 signature FAILED | ${signers_failed} |"
    echo ""
    if [ "$egress_floating" -eq 0 ] && [ "$egress_auto" -eq 0 ] && [ "$local_base_floating" -eq 0 ] && [ "$signers_failed" -eq 0 ]; then
        echo "> ✅ **Supply-chain invariant holds:** no reverse_proxy-tier service is floating"
        echo "> or auto-updating, every local build pins its base image by digest, and no"
        echo "> known signer has a FAILED signature."
    else
        echo "> ❌ **Invariant VIOLATED** — see \`scripts/audit-egress-updates.sh\` (egress), pin"
        echo "> the local build base(s) flagged above (\`FROM …@sha256:\`), or investigate the"
        echo "> ✗ P6 signature FAILED row (possible tampering — do not adopt)."
    fi
    echo ""
    echo "## Images"
    echo ""
    echo "| Service | Egress | Status | Repository | Tag | Digest | Auto | Signed (P6) |"
    echo "|---------|--------|--------|------------|-----|--------|------|-------------|"
    printf "%s" "$rows" | sort
    echo ""
    echo "---"
    echo ""
    echo "*Auto-generated by \`scripts/generate-image-pin-index.sh\`. Egress-tier =="
    echo "reverse_proxy network member (ADR-030 P4). Local builds (\`localhost/*\`) are"
    echo "pinned via build inputs under Tier 2 — base image by digest, plus hash-locked"
    echo "deps (alert-discord-relay) / GPG+SHA-verified RPM (proton-bridge) — not by"
    echo "registry digest. The \`Digest\` column shows the base-image pin.*"
    echo ""
    echo "*\`Signed (P6)\` (Tier 3): \`✓ verified\` / \`✗ FAILED\` reflect the last"
    echo "deliberate-path cosign check (\`signers.yaml\` + the textfile metric), NOT a live"
    echo "verify. \`— unsigned\` = no publisher signature, tracked in \`config/supply-chain/"
    echo "known-unsigned.md\`. Survey 2026-05-24: 1/32 signed (Home Assistant). podman 5.8.2"
    echo "policy.json cannot enforce its workflow-URI identity, so authenticity is verified"
    echo "on the deliberate-update path — see the Tier 3 plan.*"
} > "$OUTPUT_FILE"

echo "✓ Image pin index generated: $OUTPUT_FILE"
echo "  pinned=$pinned floating=$floating local=$local_builds local_base_floating=$local_base_floating egress_floating=$egress_floating egress_auto=$egress_auto signers=$signers_count signers_failed=$signers_failed"
