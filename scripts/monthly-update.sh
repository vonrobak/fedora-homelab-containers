#!/bin/bash
# monthly-update.sh — the one script name to remember (ADR-036 layer 2).
#
# Chains the whole monthly update ritual interactively. The human's job:
# read the plan, say yes (the ADR-030 P1 deliberate-trust moment), reboot
# when told. Every step underneath is the existing gated path — this adds
# orchestration, not new trust decisions.
#
#   1. check-image-updates.sh        fresh sweep (verdicts, JSON, metrics)
#   2. adopt-baked.sh --dry-run      show the plan
#   3. [confirm]                     pin + pull (COLD, ADR-049); only the critical
#                                    tier is restarted and verified here
#   4. pin index + git commit + PR   (optional merge from here)
#   5. [confirm] prepare-for-reboot.sh   manifest → graceful shutdown → image presence
#   6. print the manual tail: dnf update → reboot → post-reboot-verify.sh
#
# ADR-049: the reboot IS the rollout. Restarting the whole fleet before a reboot
# restarts everything twice, and does it in the hostile environment — so the cold
# path pins and pre-pulls, and verification moves to post-reboot-verify.sh. Use
# --live only when NO reboot is coming (then the adoption must be proven now).
#
# Usage: monthly-update.sh [--live] [--allow-young svc,svc] [--skip-os]
#   --live         restart + verify every adopted service before the reboot
#                  (pre-ADR-049 behaviour; correct when not rebooting)
#   --allow-young  ADR-036 exception lane, passed through to adopt-baked.sh
#                  (security-release override — name the CVE when prompted)
#   --skip-os      stop after the container phase (no pre-reboot workflow)
set -euo pipefail

CONTAINERS_DIR="$HOME/containers"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ALLOW_YOUNG=""; SKIP_OS=false; MODE=--cold
while [ $# -gt 0 ]; do
    case "$1" in
        --live) MODE=--live ;;
        --cold) MODE=--cold ;;
        --allow-young) ALLOW_YOUNG="$2"; shift ;;
        --skip-os) SKIP_OS=true ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done

# Interactive by design — the confirm prompts ARE the P1 gate.
if [ ! -t 0 ]; then
    echo "❌ monthly-update.sh is interactive (ADR-030 P1: adoption needs a human)." >&2
    echo "   For unattended visibility use the check-image-updates.timer feed." >&2
    exit 2
fi

# --live is only the right choice when no reboot follows. If the OS phase is still
# in play, the operator is about to restart everything twice — say so up front.
if [ "$MODE" = --live ] && ! $SKIP_OS; then
    echo "ℹ️  --live restarts and verifies every service now, and the OS phase is"
    echo "   still enabled — so each service restarts twice (ADR-049). Use --cold"
    echo "   when a reboot follows, or --skip-os if it does not."
    echo ""
fi

confirm() {  # confirm "question" → 0 yes / 1 no
    local reply
    read -r -p "$1 [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

echo "════════════════════════════════════════════════════════════════"
echo "  MONTHLY UPDATE — $(date +%Y-%m-%d)"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "── Step 1/5: Discovery sweep (registry digest-diff + bake verdicts) ──"
"$SCRIPT_DIR/check-image-updates.sh"
echo ""

# ADR-039: notify-only check for AWS published-range drift in crowdsec's egress
# allow-list (deliberate, offline — never writes here). "No change" = nothing to do.
echo "── Egress range drift (ADR-039): crowdsec AWS eu-west-1 published-range check ──"
"$SCRIPT_DIR/sync-aws-egress-ranges.sh" 2>&1 | grep -E '^#|No change|ERROR|markers' || true
echo "   (to apply drift: sync-aws-egress-ranges.sh --write, review the diff, commit)"
echo ""

echo "── Step 2/5: Adoption plan ──"
ADOPT_ARGS=("$MODE")
[ -n "$ALLOW_YOUNG" ] && ADOPT_ARGS+=(--allow-young "$ALLOW_YOUNG")
plan_output="$("$SCRIPT_DIR/adopt-baked.sh" --dry-run "${ADOPT_ARGS[@]}" 2>&1)"
echo "$plan_output"
echo ""

if [ "$MODE" = --cold ]; then
    prompt="Pin + pull the plan above now (cold — only the critical tier restarts)?"
else
    prompt="Adopt the plan above now (per-service restart + verification, halts on failure)?"
fi

adopted_any=false
if grep -q "Adoption plan" <<< "$plan_output"; then
    if [ -n "$ALLOW_YOUNG" ]; then
        echo "⚠️  --allow-young is the ADR-036 security-release exception lane:"
        echo "    the commit message must name the CVE/advisory that justifies it."
    fi
    if confirm "$prompt"; then
        echo ""
        echo "── Step 3/5: Adopting ──"
        "$SCRIPT_DIR/adopt-baked.sh" "${ADOPT_ARGS[@]}"
        adopted_any=true
    else
        echo "   Skipped adoption."
    fi
else
    echo "   Nothing baked — container phase is a no-op this month."
fi
echo ""

if $adopted_any; then
    echo "── Step 4/5: Pin index + commit ──"
    "$SCRIPT_DIR/generate-image-pin-index.sh" >/dev/null 2>&1 || true
    cd "$CONTAINERS_DIR"
    if [ -n "$(git status --porcelain -- quadlets/)" ]; then
        if confirm "Commit adopted pins and open a PR?"; then
            # SSH-login sessions lack the agent socket → signing hangs without this
            export SSH_AUTH_SOCK="${SSH_AUTH_SOCK:-/run/user/1000/gcr/ssh}"
            branch="chore/image-adoption-$(date +%Y%m%d)"
            services="$(git status --porcelain -- quadlets/ | awk '{print $2}' | xargs -rn1 basename | sed 's/\.container$//' | paste -sd', ')"
            git checkout -b "$branch"
            git add quadlets/ docs/AUTO-IMAGE-PIN-INDEX.md
            git commit -m "chore(supply-chain): monthly digest adoption — ${services}

Adopted via monthly-update.sh → adopt-baked.sh (ADR-036): bake-gated,
wave-ordered, per-service verified. See docs/99-reports/image-updates-$(date +%Y%m%d).txt

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
            git push -u origin "$branch"
            pr_url="$(gh pr create --fill 2>/dev/null | tail -1)"
            echo "   PR: $pr_url"
            if confirm "Merge the PR now (merge commit — ADR-038)?"; then
                gh pr merge --merge --delete-branch
                echo "   ✓ merged; back on $(git branch --show-current)"
            else
                echo "   PR left open — merge when ready: gh pr merge $pr_url --merge --delete-branch"
            fi
        else
            echo "   ⚠️  Adopted pins are UNCOMMITTED — the git-revert rollback path"
            echo "      doesn't exist until they're committed. Don't forget."
        fi
    fi
    echo ""
fi

if $SKIP_OS; then
    echo "── Step 5/5: skipped (--skip-os) ──"
    if [ "$MODE" = --cold ]; then
        echo ""
        echo "⚠️  Cold path with no reboot: the pinned digests are NOT running."
        echo "   Nothing rolls out until you reboot (or restart each service)."
    fi
    exit 0
fi

echo "── Step 5/5: OS pre-reboot workflow ──"
if confirm "Run prepare-for-reboot.sh (manifest → graceful shutdown → image presence)?"; then
    "$SCRIPT_DIR/prepare-for-reboot.sh"
else
    echo ""
    echo "Skipped. Container phase is complete; run it later with:"
    echo "  ./scripts/prepare-for-reboot.sh"
fi

echo ""
echo "── Step 6/6: after the reboot ──"
if [ "$MODE" = --cold ]; then
    echo "The pinned digests are still INERT — the reboot is what rolls them out."
fi
cat <<'EOM'
  sudo dnf update && sudo reboot
  ./scripts/post-reboot-verify.sh     # ← the verification step (ADR-049)

post-reboot-verify.sh closes with a short manual smoke list. Do it. Route-level
checks assert "Traefik answered", not "the workload works" — that is exactly how
the 2026-07-25 vaultwarden breakage stayed invisible while every check was green.
EOM
