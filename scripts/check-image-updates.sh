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
# ADR-036: each available update is annotated with the digest's age and a
# BAKED / TOO-YOUNG verdict against the P3 bake policy
# (config/supply-chain/bake-policy.yml; egress tier = quadlet on the
# reverse_proxy network). A machine-readable JSON companion (full digests,
# ages, tiers, verdicts) is written next to the text report — it is the
# input contract for scripts/adopt-baked.sh.
#
# To adopt baked updates in dependency-ordered waves:
#   scripts/adopt-baked.sh [--dry-run]
# To adopt a single update by hand (digest is signature-verified at this
# step, ADR-030 P6):
#   scripts/pin-container-image.sh <svc> --adopt <new-digest> --apply
#   systemctl --user daemon-reload && systemctl --user restart <svc>.service
#
# NOTE: no `set -e` — a single image's skopeo failure must not abort the sweep.
set -uo pipefail

QUADLET_DIR="${QUADLET_DIR:-$HOME/containers/quadlets}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIGNERS_FILE="${SIGNERS_FILE:-$HOME/containers/config/supply-chain/signers.yaml}"
BAKE_POLICY="${BAKE_POLICY:-$HOME/containers/config/supply-chain/bake-policy.yml}"
REPORT_FILE="$HOME/containers/docs/99-reports/image-updates-$(date +%Y%m%d).txt"
JSON_FILE="${REPORT_FILE%.txt}.json"
mkdir -p "$(dirname "$REPORT_FILE")"

# ADR-036 P3 bake thresholds (days). Policy file overrides the defaults.
BAKE_EGRESS=7
BAKE_INTERNAL=3
if [ -f "$BAKE_POLICY" ]; then
    v="$(python3 -c "import yaml; print((yaml.safe_load(open('$BAKE_POLICY')) or {}).get('egress_days',''))" 2>/dev/null)"
    [ -n "$v" ] && BAKE_EGRESS="$v"
    v="$(python3 -c "import yaml; print((yaml.safe_load(open('$BAKE_POLICY')) or {}).get('internal_days',''))" 2>/dev/null)"
    [ -n "$v" ] && BAKE_INTERNAL="$v"
fi

is_egress() { grep -qE '^Network=systemd-reverse_proxy' "$1"; }

# ADR-030 P6 (Tier 3): pre-load repos that have a known signer so we can verify the
# AVAILABLE digest and front-load the trust signal BEFORE a deliberate adopt (advisory).
declare -A SIGNER_REPOS=()
if [ -f "$SIGNERS_FILE" ]; then
    while IFS= read -r r; do [ -n "$r" ] && SIGNER_REPOS["$r"]=1; done < <(
        python3 -c "import yaml; d=yaml.safe_load(open('$SIGNERS_FILE')) or {}; [print(s.get('repo','')) for s in (d.get('signers') or [])]" 2>/dev/null)
fi

NOW_EPOCH=$(date +%s)
updates=(); failed=(); local_builds=(); uptodate=0; baked_count=0; young_count=0
json_rows=()  # TSV: service repo tag pinned available created age_days tier bake_days verdict signature

for f in "$QUADLET_DIR"/*.container; do
    name="$(basename "$f" .container)"
    img="$(grep -m1 -E '^Image=' "$f" | sed 's/^Image=//' | tr -d '[:space:]')"
    [ -n "$img" ] || continue

    tier="internal"; bake_days="$BAKE_INTERNAL"
    if is_egress "$f"; then tier="egress"; bake_days="$BAKE_EGRESS"; fi

    if [[ "$img" == localhost/* ]]; then
        local_builds+=("$name (${img})"); continue
    fi
    if [[ "$img" != *@sha256:* ]]; then
        updates+=("$name: ⚠️ FLOATING (not digest-pinned): $img")
        json_rows+=("$name"$'\t'"$img"$'\t'"-"$'\t'"-"$'\t'"-"$'\t'"-"$'\t'"-"$'\t'"$tier"$'\t'"$bake_days"$'\t'"FLOATING"$'\t'"-")
        continue
    fi

    repo="${img%@*}"; pinned="${img##*@}"
    tag="$(grep -m1 -oE 'tag: [^,]+' "$f" | sed 's/tag: //')"; [ -n "$tag" ] || tag="latest"

    # --no-tags: `inspect` unconditionally paginates the full repo tag list to
    # populate RepoTags (unused here) even when --format only needs Digest/Created.
    # immich-machine-learning's tag list is blown up by per-commit x per-hardware-
    # variant CI tagging (cuda/openvino/armnn/rocm/rknn) and never finishes within
    # any reasonable timeout without this flag (root-caused 2026-07-13 via
    # `skopeo --debug inspect`, which showed it looping on tags/list?last=... instead
    # of returning after the manifest+config fetch that already succeeded).
    probe="$(timeout 30 skopeo inspect --no-tags "docker://${repo}:${tag}" --format '{{.Digest}}|{{.Created}}' 2>/dev/null)"
    if [ -z "$probe" ]; then
        sleep 2  # registries (esp. GHCR/Docker Hub) throttle bursts — retry once
        probe="$(timeout 30 skopeo inspect --no-tags "docker://${repo}:${tag}" --format '{{.Digest}}|{{.Created}}' 2>/dev/null)"
    fi
    if [ -z "$probe" ]; then
        failed+=("$name (${repo}:${tag})"); continue
    fi
    sleep 0.2  # be gentle on registries between checks

    current="${probe%%|*}"
    created_raw="${probe#*|}"
    # skopeo emits e.g. "2026-06-05 16:06:15.177357755 +0000 UTC" — strip
    # fractional seconds and the trailing zone name for GNU date.
    created_clean="$(echo "$created_raw" | sed 's/\.[0-9]*//; s/ UTC$//; s/ m=.*$//')"
    created_epoch="$(date -d "$created_clean" +%s 2>/dev/null)"
    age_days="?"
    [ -n "$created_epoch" ] && age_days=$(( (NOW_EPOCH - created_epoch) / 86400 ))

    # ADR-030 P6 advisory: if this repo has a known signer, verify the AVAILABLE digest
    signote=""; sigstate="unsigned"
    if [ -n "${SIGNER_REPOS[$repo]:-}" ]; then
        "$SCRIPT_DIR/verify-image-signature.sh" "${repo}@${current}" --quiet >/dev/null 2>&1
        case $? in
            0) signote="  [✓ signature verified]"; sigstate="verified" ;;
            1) signote="  [✗ SIGNATURE FAILED — do not adopt]"; sigstate="FAILED" ;;
            *) signote="  [⚠ signature check error]"; sigstate="check-error" ;;
        esac
    fi

    if [ "$current" != "$pinned" ]; then
        # ADR-036 bake verdict: digest age vs per-tier threshold
        if [ "$age_days" = "?" ]; then
            verdict="AGE-UNKNOWN"
            bakenote="age unknown [${tier}, bake ${bake_days}d] → verify manually"
        elif [ "$age_days" -ge "$bake_days" ]; then
            verdict="BAKED"; baked_count=$((baked_count+1))
            bakenote="age ${age_days}d [${tier}, bake ${bake_days}d] → BAKED ✓"
        else
            verdict="TOO-YOUNG"; young_count=$((young_count+1))
            bakenote="age ${age_days}d [${tier}, bake ${bake_days}d] → TOO YOUNG (wait $((bake_days - age_days))d)"
        fi
        updates+=("$name | ${repo}:${tag} | pinned ${pinned:0:19}… → available ${current:0:19}… | ${bakenote}${signote}")
        json_rows+=("$name"$'\t'"$repo"$'\t'"$tag"$'\t'"$pinned"$'\t'"$current"$'\t'"$created_clean"$'\t'"$age_days"$'\t'"$tier"$'\t'"$bake_days"$'\t'"$verdict"$'\t'"$sigstate")
    else
        uptodate=$((uptodate+1))
        [ -n "$signote" ] && updates+=("$name | ${repo}:${tag} | up-to-date${signote}")
    fi
done

# Textfile metrics → node_exporter → Prometheus → ImageUpdatesBaked* alerts
# (ADR-036 layer 1: the system nudges the human; nothing adopts automatically).
# Temp MUST be in-dir (a /tmp temp keeps user_tmp_t, unreadable to node_exporter)
# and 0644 (node_exporter runs unprivileged).
METRIC_DIR="${METRIC_DIR:-$HOME/containers/data/backup-metrics}"
if mkdir -p "$METRIC_DIR" 2>/dev/null && tmp_metric="$(mktemp -p "$METRIC_DIR" 2>/dev/null)"; then
    {
        echo "# HELP image_updates_baked_count Available image updates past their ADR-036 bake interval (adoptable now)."
        echo "# TYPE image_updates_baked_count gauge"
        echo "image_updates_baked_count ${baked_count}"
        echo "# HELP image_updates_young_count Available image updates still inside their bake interval."
        echo "# TYPE image_updates_young_count gauge"
        echo "image_updates_young_count ${young_count}"
        echo "# HELP image_updates_check_failed_count Images whose registry check failed this sweep."
        echo "# TYPE image_updates_check_failed_count gauge"
        echo "image_updates_check_failed_count ${#failed[@]}"
        echo "# HELP image_updates_last_run_timestamp_seconds Unix time of the last completed update sweep."
        echo "# TYPE image_updates_last_run_timestamp_seconds gauge"
        echo "image_updates_last_run_timestamp_seconds $(date +%s)"
    } > "$tmp_metric"
    chmod 0644 "$tmp_metric"
    mv "$tmp_metric" "$METRIC_DIR/image-updates.prom"
fi

# Machine-readable companion — the input contract for adopt-baked.sh.
printf '%s\n' "${json_rows[@]:-}" | python3 -c "
import sys, json
cols = ['service','repo','tag','pinned','available','created','age_days','tier','bake_days','verdict','signature']
rows = [dict(zip(cols, l.rstrip('\n').split('\t'))) for l in sys.stdin if l.strip()]
for r in rows:
    for k in ('age_days','bake_days'):
        try: r[k] = int(r[k])
        except (ValueError, TypeError): pass
json.dump({'generated': '$(date -Iseconds)', 'bake_policy': {'egress_days': $BAKE_EGRESS, 'internal_days': $BAKE_INTERNAL}, 'candidates': rows}, open('$JSON_FILE','w'), indent=1)
"

{
    echo "Container Image Update Check (ADR-030 notify-only / skopeo digest-diff)"
    echo "Generated: $(date)"
    echo "Bake policy (ADR-036): egress ${BAKE_EGRESS}d, internal ${BAKE_INTERNAL}d"
    echo "========================================"
    echo ""
    echo "Up to date (pinned == current tag digest): ${uptodate}"
    echo "Updates available: ${#updates[@]} (baked: ${baked_count}, too young: ${young_count})"
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
    echo "Machine-readable: $JSON_FILE"
    echo ""
    echo "To adopt all BAKED updates in dependency-ordered waves (ADR-036):"
    echo "  scripts/adopt-baked.sh --dry-run   # review the plan"
    echo "  scripts/adopt-baked.sh             # execute with per-service verification"
    echo "To adopt a single update by hand (signature-verified at adopt, ADR-030 P6):"
    echo "  scripts/pin-container-image.sh <svc> --adopt <available-digest> --apply"
    echo "  systemctl --user daemon-reload && systemctl --user restart <svc>.service"
} > "$REPORT_FILE"

echo "🔍 Image update check complete → $REPORT_FILE"
echo "   up-to-date=$uptodate  available=${#updates[@]} (baked=$baked_count young=$young_count)  local=${#local_builds[@]}  failed=${#failed[@]}"
if [ ${#updates[@]} -gt 0 ]; then
    echo ""
    printf '   • %s\n' "${updates[@]}"
fi
