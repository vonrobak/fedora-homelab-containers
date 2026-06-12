# Lessons handoff execution — three work packages, eight dead alerts, stacked-PR gotchas

**Date:** 2026-06-12
**Status:** Handoff definition-of-done met. WP1–WP3 merged (#281, #286, #283), predictive-maintenance retired (#287 / GH#285), one issue remains open by design (GH#284).
**Origin:** Executed `docs/96-project-supervisor/2026-06-12-lessons-loose-threads-handoff.md` (local-only) in a single session: implement, verify live, PR per work package, file issues for the rest.

---

## What shipped

| Package | PR | Content |
|---|---|---|
| WP1 quick alert wins | #281 | L-018 Immich mass-deletion canary (`immich_active_assets` via postgres-exporter custom query, 3 alerts incl. a guards-the-guard absence check); L-002 container memory pressure rewritten against service-cgroup ids; L-034 scrape-timeout sweep; **8 dead alerts fixed** (below); promtool unit-test suite in `config/prometheus/tests/` |
| WP2 erosion guards | #286 (recreation of #282) | ADR-035 boot-tier enforcement: alertmanager → 200, relay un-deferred per D2, 13 quadlets stamped Tier B, `check-boot-tier.sh` pre-commit gate; L-019 `audit-dump-coverage.sh` + `DbDumpCoverageGap` alerts, wired as `ExecStartPost` of db-dump.service |
| WP3 process closures | #283 | Rate-limit soak verdict (Nextcloud 800 ratified, Immich 1500→800 applied, qBt 600 kept as a decision) + closing journal; L-024 scoping footnote; L-049/L-030 deployment gates in CLAUDE.md + pattern guide; L-020 cold-cache checklist in db-dump.sh |
| Retirement | #287 | Predictive-maintenance loop retired per owner decision on GH#285 |

Deferred with a public trace: GH#284 (native-auth session/device audit residual, L-051).

## The headline find: 8 structurally dead alerts (→ L-075)

The `and ALERTS{alertname="X"} != 1` "hysteresis" pattern can never match — ALERTS
series always have value 1 while pending/firing and don't exist otherwise, so the
fire-branch was permanently empty. Six alerts in `infrastructure-warnings.yml` +
`ContainerMemoryPressure` were unable to even go *pending* since their 2026-01-17
creation. Two more in `service-health.yml` were dead for different reasons: a
kube-state metric cAdvisor never emits, and an instant selector racing cAdvisor's
5-minute staleness window. All fixed with `keep_firing_for` / range-vector reads,
and — the durable part — every new and resurrected alert now has a promtool unit
test against synthetic series. Captured as **L-075** in lessons.md.

## Premise drift — the handoff was right to demand re-verification

Every package had at least one stale premise, all caught before editing:

- alert-discord-relay's "missing" boot weight had landed in PR #242 weeks earlier —
  but sitting next to it was a real, undocumented contradiction (its
  `After=traefik.service` deferral vs ADR-035 D2's "alert path stays un-deferred").
- The handoff's SQL targeted table `assets`; Immich v2 renamed it to `asset`.
- "Both blackbox jobs" had become three (nextcloud-status added since).
- ADR-035's Tier A list doesn't actually name alertmanager — promoted anyway per the
  handoff and the ADR's own alerting-path rationale, flagged in the PR.
- The predictive retirement scope doubled on contact: a *second* live timer
  (`daily-resource-forecast`) existed solely to run the predictor — and had been
  logging "Prediction script had errors" on every run.

## GitHub / git workflow gotchas (the expensive lessons)

1. **Merging a stacked PR's base with `--delete-branch` kills the child PR
   irrecoverably.** When #281 merged and its branch was deleted, GitHub did *not*
   retarget #282 to main — it CLOSED it, and a PR whose base branch no longer
   exists cannot be reopened (`reopenPullRequest` fails). The branch survives, so
   recovery = recreate the PR (#286), but the review thread and PR number are lost.
   **Rule for next time: retarget every child PR to main *before* merging/deleting
   its base** (`gh pr edit <child> --base main`) — that's exactly what saved #283.

2. **Squash-merge breaks stacked branches' ancestry.** After #281 squashed, the wp2
   branch still carried the original wp1 commits; GitHub reported it CONFLICTING.
   Fix is mechanical but must reference the *old base tip by commit hash*:
   `git rebase --onto origin/main <old-base-tip> <child-branch>` — repeated for wp3
   after wp2 merged.

3. **`gh pr merge --delete-branch` deletes the LOCAL branch too** (when run from the
   repo). The follow-up rebase failed with "invalid upstream
   'feat/wp1-alert-quick-wins'" — keep the tip hashes from `git log` before merging,
   or skip `--delete-branch` until the whole stack is done.

4. **`git rebase --onto A B C` checks out C — and this worktree IS the live
   config.** Each rebase briefly put intermediate content on disk; during the wp2
   rebase, Traefik's `middleware.yml` momentarily reverted Immich's burst to 1500
   (auto-reloading provider!). Harmless here, but the same mechanism earlier in the
   session nearly reverted live WP1 alert rules when WP2 initially branched off
   main — which deleted a branch-new file that a running container had
   bind-mounted. Both incidents are the same root cause, now recorded as a memory
   gotcha: **stack branches during multi-PR sessions and never return the worktree
   to main (or rebase across it) until everything is merged.** A `git worktree` for
   PR mechanics, separate from the live tree, would eliminate the flicker entirely —
   worth considering if stacked sessions become routine.

5. **The daily AUTO-doc churn blocks rebases** ("cannot rebase: You have unstaged
   changes") — `git stash` around the whole merge sequence, pop at the end.

6. **A self-inflicted one:** an `until`-loop poller against Traefik's API ran
   blind for ~15 minutes because the API isn't exposed on :8080 (metrics only) —
   the access log later showed my own loop as 8.5k requests. Don't poll an endpoint
   whose existence you haven't confirmed once by hand; and Immich's vhost is
   `photos.patriark.org` (Navidrome: `musikk.`) — probing `immich.patriark.org`
   404s by design, which briefly looked like a routing breakage I'd caused.

## Verification practices that paid for themselves

- **promtool unit tests as kill-tests** — caught nothing wrong this time, but
  proved each alert fires on synthetic incident data (incl. negative cases), which
  is precisely the check whose absence let 8 alerts stay dead for five months.
- **Positive end-to-end checks over absence-of-errors:** `photos.patriark.org`
  returning 200 *through* the edited middleware chain proves the reload (a broken
  middleware drops its router); access-log inspection beats trusting silence.
- **Measure before sizing:** the 15d peak-rate query (93/33/zero req/min) turned
  the rate-limit soak closure from guesswork into three defensible decisions.

## Open threads

- GH#284 — native-auth session/device audit residual (hygiene-tier).
- Watch item: first Immich mobile bulk-upload after the burst downsize — expect
  zero 429s; the first 429 series on `immich@file` would be the signal to revisit.
- status.md updated; L-075 appended to lessons.md per its protocol.
