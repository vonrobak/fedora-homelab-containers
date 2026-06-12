#!/bin/bash
# mirror-to-forgejo.sh — push-mirror main to the private Forgejo ledger
#
# Role (decided 2026-06-12, see journal + CLAUDE.md Git & PR Workflow):
# Forgejo (git.patriark.org, patriark/homelab) is the SOVEREIGNTY LEDGER —
# the owner-controlled record of main, independent of GitHub as an authority.
# It is NOT a disaster-recovery copy (Forgejo runs on this same host; Urd
# owns DR). Design consequences:
#
#   - LOCAL PUSH, never a Forgejo pull-mirror of GitHub: the machine that
#     signs is the machine that publishes. Merges materialize on GitHub
#     (merge-commit-only strategy), but they reach the ledger only after
#     this host fetches them and the gates below pass.
#   - APPEND-ONLY: a non-fast-forward origin/main (history rewrite) FAILS
#     the mirror — that is a tamper canary, not a sync problem. No --force,
#     ever. Forgejo-side branch protection is the second lock.
#   - SIGNATURE GATE: any commit in the new delta with NO signature (N) or a
#     BAD signature (B) fails the mirror. Commits that merely can't be
#     verified locally (E — e.g. GitHub web-flow merge commits, pre-switch
#     squash commits) pass but are counted in a metric, so drift is visible.
#
# Wiring: forgejo-mirror.timer (hourly). History: the manual-push "mirror"
# silently fell 18 commits behind within 3 days of its last push — this
# script + ForgejoMirror* alerts exist so that cannot recur (L-031 class).
#
# Exit: 0 mirrored/up-to-date, 1 push or gate failure (alert fires via metric).

set -uo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/containers}"
REMOTE="${MIRROR_REMOTE:-forgejo}"
METRICS_DIR="${HOME}/containers/data/backup-metrics"
METRICS_FILE="${METRICS_FILE:-${METRICS_DIR}/forgejo-mirror.prom}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$1] ${*:2}" >&2; }

SUCCESS=0
UNVERIFIED=0
LAG=0

finish() {
    mkdir -p "$METRICS_DIR"
    {
        echo "# HELP forgejo_mirror_success Last mirror run result (1=ok, 0=failed/gate-blocked)"
        echo "# TYPE forgejo_mirror_success gauge"
        echo "forgejo_mirror_success{repo=\"containers\"} ${SUCCESS}"
        echo "# HELP forgejo_mirror_last_run_timestamp Unix time of last mirror attempt"
        echo "# TYPE forgejo_mirror_last_run_timestamp gauge"
        echo "forgejo_mirror_last_run_timestamp{repo=\"containers\"} $(date +%s)"
        if [[ "$SUCCESS" == "1" ]]; then
            echo "# HELP forgejo_mirror_last_success_timestamp Unix time of last successful mirror"
            echo "# TYPE forgejo_mirror_last_success_timestamp gauge"
            echo "forgejo_mirror_last_success_timestamp{repo=\"containers\"} $(date +%s)"
        else
            # carry the previous success timestamp forward so staleness ages correctly
            prev="$(grep -oP 'forgejo_mirror_last_success_timestamp\{[^}]*\} \K[0-9]+' "$METRICS_FILE" 2>/dev/null | tail -1)"
            if [[ -n "$prev" ]]; then
                echo "# HELP forgejo_mirror_last_success_timestamp Unix time of last successful mirror"
                echo "# TYPE forgejo_mirror_last_success_timestamp gauge"
                echo "forgejo_mirror_last_success_timestamp{repo=\"containers\"} ${prev}"
            fi
        fi
        echo "# HELP forgejo_mirror_unverified_commits Locally-unverifiable (E) commits in the last mirrored delta"
        echo "# TYPE forgejo_mirror_unverified_commits gauge"
        echo "forgejo_mirror_unverified_commits{repo=\"containers\"} ${UNVERIFIED}"
    } > "${METRICS_FILE}.tmp" && mv "${METRICS_FILE}.tmp" "$METRICS_FILE"
}
trap finish EXIT

cd "$REPO_ROOT" || { log ERROR "repo not found: $REPO_ROOT"; exit 1; }

if ! git fetch --quiet origin main || ! git fetch --quiet "$REMOTE" main; then
    log ERROR "fetch failed (origin or $REMOTE unreachable)"
    exit 1
fi

NEW="$(git rev-parse origin/main)"
OLD="$(git rev-parse "$REMOTE/main")"

if [[ "$NEW" == "$OLD" ]]; then
    log INFO "ledger up to date at ${NEW:0:7}"
    SUCCESS=1
    exit 0
fi

# Gate 1 — append-only: the ledger must be an ancestor of what we publish.
if ! git merge-base --is-ancestor "$OLD" "$NEW"; then
    log ERROR "TAMPER CANARY: origin/main (${NEW:0:7}) does not descend from ledger main (${OLD:0:7}) — history rewrite upstream? Refusing to mirror. Investigate before doing ANYTHING manual."
    exit 1
fi

LAG="$(git rev-list --count "$OLD".."$NEW")"

# Gate 2 — signatures: no unsigned (N) or bad (B) commits enter the ledger.
BAD="$(git log --format='%G? %h %s' "$OLD".."$NEW" | grep -E '^[NB] ' || true)"
if [[ -n "$BAD" ]]; then
    log ERROR "signature gate: unsigned/bad commits in delta — refusing to mirror:"
    printf '%s\n' "$BAD" >&2
    exit 1
fi
UNVERIFIED="$(git log --format='%G?' "$OLD".."$NEW" | grep -c '^E' || true)"

if ! git push --quiet "$REMOTE" origin/main:refs/heads/main; then
    log ERROR "push to $REMOTE failed"
    exit 1
fi
git push --quiet "$REMOTE" --tags || log WARN "tag push failed (non-fatal)"

SUCCESS=1
log INFO "mirrored ${LAG} commit(s) ${OLD:0:7}..${NEW:0:7} to $REMOTE (${UNVERIFIED} locally-unverifiable)"
exit 0
