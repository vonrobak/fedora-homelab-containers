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
# Usage: adopt-baked.sh [--dry-run] [--report <json>] [--only svc,svc]
#                       [--allow-young svc,svc]
#   --dry-run       print the wave plan, change nothing
#   --report        candidate JSON (default: newest image-updates-*.json)
#   --only          restrict to these services
#   --allow-young   ADR-036 exception lane: adopt a TOO-YOUNG candidate
#                   (security-release override; note the reason in the commit)
set -euo pipefail

CONTAINERS_DIR="$HOME/containers"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUADLET_DIR="${QUADLET_DIR:-$CONTAINERS_DIR/quadlets}"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-120}"

DRY_RUN=false; REPORT=""; ONLY=""; ALLOW_YOUNG=""
while [ $# -gt 0 ]; do
    case "$1" in
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

WAVE_NAMES=([1]="plumbing" [2]="apps" [3]="core" [4]="data")
echo ""
echo "── Adoption plan ──"
while IFS=$'\t' read -r wv svc digest age tier note; do
    printf "  wave %s (%-8s) %-25s age %sd [%s] %s\n" "$wv" "${WAVE_NAMES[$wv]}" "$svc" "$age" "$tier" "$note"
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
