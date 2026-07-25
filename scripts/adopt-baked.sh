#!/bin/bash
# adopt-baked.sh — ADR-036 batch adoption of BAKED image updates.
#
# Consumes the JSON companion written by check-image-updates.sh and adopts
# every candidate whose digest has passed the P3 bake interval, in
# dependency-ordered waves:
#
#   wave 1  plumbing   exporters, syslog, log shippers (cheap canaries)
#   wave 2  apps       user-facing services
#   wave 3  core       gateway / auth / monitoring — one at a time
#   wave 4  data       databases & caches, each followed by a restart of its
#                      dependent apps (derived from quadlet After=/Requires=)
#
# Per service: pin-container-image.sh --adopt (ADR-030 P6 signature gate)
# → restart → wait for systemd active + container healthcheck → HTTP verify
# via the Traefik route (service-url.sh) when one exists. Halts on the first
# failure with rollback instructions — a halted batch is a feature, not a bug.
#
# ADR-049 splits application into two paths, selected by whether a reboot follows:
#
#   --live (default)  today's behaviour: adopt → restart → verify, every service,
#                     serially, on a live system. Correct when NO reboot is coming
#                     and the adoption must be proven working immediately.
#   --cold            pin + ensure-pulled only; the REBOOT performs the rollout.
#                     Nothing is restarted except CRITICAL_TIER. Verification moves
#                     to post-reboot-verify.sh.
#
# Why: when a reboot follows, a live pass restarts every service twice and does it in
# the hostile environment (serving traffic, inline pulls, fixed 120s gates) rather
# than the tolerant one (ADR-035 boot tiers, systemd retries). The 2026-07-25 run
# produced two halts, both false positives the batch manufactured itself, and zero
# real defects. See ADR-049.
#
# CRITICAL_TIER = services whose failure would obstruct DIAGNOSIS of the others:
# a dead front door hides everything, a dead auth backend locks the operator out of
# the dashboards. Databases deliberately excluded — they fail loudly and locally.
#
# Usage: adopt-baked.sh [--cold|--live] [--dry-run] [--report <json>]
#                       [--only svc,svc] [--allow-young svc,svc]
#   --cold          pin + pull only; restart/verify CRITICAL_TIER alone
#   --live          restart + verify every adopted service (default)
#   --dry-run       print the wave plan, change nothing
#   --report        candidate JSON (default: newest image-updates-*.json)
#   --only          restrict to these services
#   --allow-young   ADR-036 exception lane: adopt a TOO-YOUNG candidate
#                   (security-release override; note the reason in the commit)
set -euo pipefail

CONTAINERS_DIR="$HOME/containers"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUADLET_DIR="${QUADLET_DIR:-$CONTAINERS_DIR/quadlets}"
# 120s was too tight: navidrome's 2026-07-25 bump ran two schema migrations and took
# 4m38s to serve, which the old default recorded as a 502 failure (ADR-049).
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-600}"
# Dependency order matters: redis before the auth server that uses it, front door last.
CRITICAL_TIER="${CRITICAL_TIER:-redis-authelia authelia traefik}"

DRY_RUN=false; REPORT=""; ONLY=""; ALLOW_YOUNG=""; MODE=live
while [ $# -gt 0 ]; do
    case "$1" in
        --cold) MODE=cold ;;
        --live) MODE=live ;;
        --dry-run) DRY_RUN=true ;;
        --report) REPORT="$2"; shift ;;
        --only) ONLY="$2"; shift ;;
        --allow-young) ALLOW_YOUNG="$2"; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done

if [ -z "$REPORT" ]; then
    REPORT="$(ls -t "$CONTAINERS_DIR"/docs/99-reports/image-updates-*.json 2>/dev/null | head -1)"
fi
[ -f "${REPORT:-}" ] || { echo "❌ No candidate JSON found — run scripts/check-image-updates.sh first." >&2; exit 2; }

age_hours=$(( ($(date +%s) - $(stat -c %Y "$REPORT")) / 3600 ))
echo "📋 Candidates: $REPORT (${age_hours}h old)"
if [ "$age_hours" -gt 24 ]; then
    echo "⚠️  Report is >24h old — digests may have moved. Re-run check-image-updates.sh." >&2
    $DRY_RUN || exit 2
fi

# Select adoptable candidates and order them into waves. TSV out:
# wave svc digest age tier verdict
plan="$(python3 - "$REPORT" "$ONLY" "$ALLOW_YOUNG" <<'EOF'
import json, re, sys
report, only, allow_young = sys.argv[1], sys.argv[2], sys.argv[3]
only = {s for s in only.split(',') if s}
allow_young = {s for s in allow_young.split(',') if s}
data = json.load(open(report))

def wave(svc):
    if re.search(r'exporter|syslog|promtail|cadvisor|unpoller|relay|blackbox', svc):
        return 1
    if re.search(r'-db$|^postgresql|^redis-|valkey|mongo', svc):
        return 4
    if svc in ('traefik', 'authelia', 'crowdsec', 'prometheus', 'grafana',
               'loki', 'alertmanager'):
        return 3
    return 2

rows = []
for c in data['candidates']:
    svc, verdict = c['service'], c['verdict']
    if only and svc not in only:
        continue
    if c.get('signature') == 'FAILED':
        print(f"SKIP\t{svc}\t-\t-\t-\tSIGNATURE-FAILED", file=sys.stderr)
        continue
    if verdict == 'BAKED' or (verdict == 'TOO-YOUNG' and svc in allow_young):
        note = 'BAKED' if verdict == 'BAKED' else 'YOUNG-OVERRIDE'
        rows.append((wave(svc), svc, c['available'], c['age_days'], c['tier'], note))
    elif verdict in ('TOO-YOUNG', 'FLOATING', 'AGE-UNKNOWN'):
        print(f"SKIP\t{svc}\t-\t{c.get('age_days','-')}\t{c.get('tier','-')}\t{verdict}", file=sys.stderr)

for r in sorted(rows):
    print('\t'.join(str(x) for x in r))
EOF
)" || true

if [ -z "$plan" ]; then
    echo "✅ Nothing to adopt — no BAKED candidates in the report."
    exit 0
fi

is_critical() {
    local s
    for s in $CRITICAL_TIER; do [ "$s" = "$1" ] && return 0; done
    return 1
}

WAVE_NAMES=([1]="plumbing" [2]="apps" [3]="core" [4]="data")
echo ""
if [ "$MODE" = cold ]; then
    echo "── Adoption plan (COLD — reboot performs the rollout, ADR-049) ──"
else
    echo "── Adoption plan (LIVE — restart + verify each service) ──"
fi
while IFS=$'\t' read -r wv svc digest age tier note; do
    marker=""
    if [ "$MODE" = cold ]; then
        if is_critical "$svc"; then marker="  ← critical: restart+verify now"
        else marker="  (pin+pull only)"; fi
    fi
    printf "  wave %s (%-8s) %-25s age %sd [%s] %s%s\n" "$wv" "${WAVE_NAMES[$wv]}" "$svc" "$age" "$tier" "$note" "$marker"
done <<< "$plan"
echo ""

if $DRY_RUN; then
    echo "(dry-run — nothing changed)"
    exit 0
fi

# Dependent apps of a data-tier service: quadlets that declare After=/Requires=
# on it. Restarting the DB drops their connections; restart them deliberately.
dependents_of() {
    grep -lE "^(After|Requires|Wants)=.*\b$1\.service" "$QUADLET_DIR"/*.container 2>/dev/null \
        | xargs -rn1 basename | sed 's/\.container$//' | grep -vx "$1" || true
}

verify_service() {
    local svc="$1" deadline=$((SECONDS + HEALTH_TIMEOUT)) state="" health=""
    while [ $SECONDS -lt $deadline ]; do
        state="$(systemctl --user is-active "$svc.service" 2>/dev/null || true)"
        health="$(podman inspect "$svc" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' 2>/dev/null || echo missing)"
        if [ "$state" = "active" ] && { [ "$health" = "healthy" ] || [ "$health" = "no-healthcheck" ]; }; then
            break
        fi
        [ "$state" = "failed" ] && break
        sleep 3
    done
    if [ "$state" != "active" ]; then
        echo "    ❌ $svc: systemd state '$state' (health: $health)"; return 1
    fi

    local url code=""
    if url="$("$SCRIPT_DIR/service-url.sh" "$svc" 2>/dev/null)"; then
        code="$(curl -s -o /dev/null -m 15 -w '%{http_code}' "$url" || echo 000)"
        # 2xx/3xx/401/403 all mean "responding behind the middleware chain"
        if [[ "$code" =~ ^[23] ]] || [ "$code" = "401" ] || [ "$code" = "403" ]; then
            echo "    ✓ $svc: active / $health / $url → $code"
        else
            echo "    ❌ $svc: active but $url → $code"; return 1
        fi
    elif [ "$health" = "healthy" ] || [ "$health" = "no-healthcheck" ]; then
        echo "    ✓ $svc: active / $health (no Traefik route)"
    else
        echo "    ❌ $svc: active but healthcheck stuck in '$health'"; return 1
    fi

    # Workload smoke (GH#314): HTTP health can stay green while the service's
    # real path is broken. Assert it; a failure halts the adoption right here.
    workload_smoke "$svc"
}

# Smoke-test a service's NON-HTTP workload when it has one. Forgejo 15.0.3
# shipped the go1.26.4 fix for CVE-2026-39831 (x/crypto/ssh enforces FIDO
# User-Presence) and silently broke git-over-SSH while :3000 stayed healthy —
# the mirror push only failed hours later, after a reboot. Probe the SSH push
# path with the dedicated deploy key: "successfully authenticated" = good,
# connection-drop/deny = bad.
workload_smoke() {
    case "$1" in
        forgejo)
            local key="${MIRROR_SSH_KEY:-$HOME/.ssh/id_ed25519_forgejo_mirror}"
            if [ ! -f "$key" ]; then
                echo "    ⚠ forgejo: SSH smoke skipped (deploy key $key not on this host)"
                return 0
            fi
            local out
            out="$(ssh -n -F none -i "$key" -o IdentitiesOnly=yes -o IdentityAgent=none \
                       -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$HOME/.ssh/known_hosts" \
                       -o BatchMode=yes -o ConnectTimeout=8 -p 2222 -T git@127.0.0.1 2>&1 || true)"
            if grep -q "successfully authenticated" <<< "$out"; then
                echo "    ✓ forgejo: SSH push path (:2222) authenticates"
                return 0
            fi
            echo "    ❌ forgejo: SSH push path (:2222) BROKEN — the mirror would fail."
            echo "       probe: $(grep -iE 'closed|denied|authenticated|timeout' <<< "$out" | head -1)"
            echo "       (Forgejo SSH-auth regression — cf. CVE-2026-39831 / GH#314)"
            return 1
            ;;
        *) return 0 ;;
    esac
}

# Cold-path gate. A reboot onto an unpulled digest is slow at best and fails at
# worst, so presence is asserted BEFORE anything is committed or the machine goes
# down. Unlike a health timeout this cannot be manufactured by system load.
ensure_pulled() {
    local svc="$1" img
    img="$(grep -m1 -E '^Image=' "$QUADLET_DIR/$svc.container" | sed 's/^Image=//' | tr -d '[:space:]')"
    if [ -z "$img" ]; then
        echo "    ❌ $svc: no Image= in quadlet"; return 1
    fi
    if podman image exists "$img"; then
        echo "    ✓ $svc: pinned, image present"
    elif podman pull "$img" >/dev/null 2>&1; then
        echo "    ✓ $svc: pinned, image pulled"
    else
        echo "    ❌ $svc: image pull FAILED — $img"; return 1
    fi
}

cold_halt() {
    local svc="$1"
    cat >&2 <<EOM

❌ HALTED at $svc — remaining candidates NOT pinned.
Nothing has been restarted, so the running fleet is untouched; the pins already
written are inert until a restart or reboot picks them up.
DO NOT REBOOT until this is resolved.
Roll back the pins written so far:
  git -C "$CONTAINERS_DIR" checkout -- quadlets/
EOM
    exit 1
}

halt() {
    local svc="$1"
    cat >&2 <<EOM

❌ HALTED at $svc — remaining candidates NOT adopted.
Rollback this service:
  git -C "$CONTAINERS_DIR" checkout -- quadlets/$svc.container
  systemctl --user daemon-reload && systemctl --user restart $svc.service
Already-adopted services from this run keep their new digests (each verified
healthy); commit or revert them per quadlet via git.
EOM
    exit 1
}

adopted=()

if [ "$MODE" = cold ]; then
    # Pass 1 — pin every candidate and assert its image is local. No restarts, so
    # no wave ordering is needed: nothing is running the new digests yet.
    echo "═══ Pass 1: pin + pull (no restarts) ═══"
    while IFS=$'\t' read -r wv svc digest age tier note; do
        echo "  ▶ $svc → ${digest:0:19}… (age ${age}d, $tier, $note)"
        "$SCRIPT_DIR/pin-container-image.sh" "$svc" --adopt "$digest" --apply || cold_halt "$svc"
        ensure_pulled "$svc" || cold_halt "$svc"
        adopted+=("$svc")
    done <<< "$plan"

    # One reload for every pin written above. This regenerates units; it does NOT
    # restart anything, so non-critical services keep serving their old image until
    # the reboot.
    systemctl --user daemon-reload

    # Pass 2 — only the services whose failure would obstruct diagnosing the rest.
    crit_done=()
    for svc in $CRITICAL_TIER; do
        grep -qP "^\d+\t$svc\t" <<< "$plan" || continue
        echo "═══ Pass 2: critical — $svc ═══"
        systemctl --user restart "$svc.service" || halt "$svc"
        verify_service "$svc" || halt "$svc"
        crit_done+=("$svc")
    done

    echo ""
    echo "✅ Pinned ${#adopted[@]} service(s): ${adopted[*]}"
    if [ ${#crit_done[@]} -gt 0 ]; then
        echo "   verified live (critical tier): ${crit_done[*]}"
    fi
    echo "   everything else is pinned but still running its OLD image —"
    echo "   the reboot performs the rollout (ADR-049)."
    echo ""
    echo "Next steps:"
    echo "  ./scripts/generate-image-pin-index.sh        # refresh AUTO-IMAGE-PIN-INDEX.md"
    echo "  git add quadlets/ docs/AUTO-IMAGE-PIN-INDEX.md && commit via PR"
    echo "  ./scripts/prepare-for-reboot.sh → dnf update → reboot"
    echo "  ./scripts/post-reboot-verify.sh              # verification happens HERE"
    exit 0
fi

current_wave=""
while IFS=$'\t' read -r wv svc digest age tier note; do
    if [ "$wv" != "$current_wave" ]; then
        current_wave="$wv"
        echo "═══ Wave $wv: ${WAVE_NAMES[$wv]} ═══"
    fi
    echo "  ▶ $svc → ${digest:0:19}… (age ${age}d, $tier, $note)"
    "$SCRIPT_DIR/pin-container-image.sh" "$svc" --adopt "$digest" --apply || halt "$svc"
    systemctl --user daemon-reload
    systemctl --user restart "$svc.service" || halt "$svc"
    verify_service "$svc" || halt "$svc"
    adopted+=("$svc")

    if [ "$wv" = "4" ]; then
        for dep in $(dependents_of "$svc"); do
            systemctl --user is-active --quiet "$dep.service" 2>/dev/null || continue
            echo "    ↻ dependent: $dep"
            systemctl --user restart "$dep.service" || halt "$dep"
            verify_service "$dep" || halt "$dep"
        done
    fi
done <<< "$plan"

echo ""
echo "✅ Adopted ${#adopted[@]} service(s): ${adopted[*]}"
echo ""
echo "Next steps:"
echo "  ./scripts/generate-image-pin-index.sh        # refresh AUTO-IMAGE-PIN-INDEX.md"
echo "  git add quadlets/ docs/AUTO-IMAGE-PIN-INDEX.md && commit via PR"
