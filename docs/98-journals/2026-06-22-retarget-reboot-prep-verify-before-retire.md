# Verify a component's *current* job before retiring it: update-before-reboot → prepare-for-reboot

**Date:** 2026-06-22
**Status:** Both work packages merged in #303 (merge commit `f0c58ae`); follow-up doc-rot tracked in #304.
**Origin:** Started as a read-only question — "what would `monthly-update.sh` do if run now, and are there closed issues about the update script?" — ahead of the first real run of the post-ADR-036 monthly ritual. Turned into a squash-defect fix and a refactor of the reboot-prep script.

---

## What shipped

| Package | PR/Issue | Content |
|---|---|---|
| Squash → merge fix | #303 (commit `b1626d3`) | `monthly-update.sh` step 4 auto-merge called `gh pr merge --squash`; squash is disabled repo-side (ADR-038, `squashMergeAllowed:false`). The script predated ADR-038 by **one day** (PR #272) and was never reconciled. Switched the prompt + both invocations to `--merge` |
| Retarget reboot-prep | #303 (commit `9e2d0e0`) | `git mv update-before-reboot.sh → prepare-for-reboot.sh`; logic byte-for-byte unchanged, framing retargeted away from "updates containers". Updated active callers + docs; dropped a phantom health-check gate and the long-removed `podman-auto-update-weekly.timer` from the automation-reference |
| Doc-rot follow-up | #304 | Pre-ADR-030 staleness left out of #303 scope: field-guide `:latest` claims + a manual `podman pull` recipe that would re-float a pin; `graceful-shutdown.sh` hard-coded fleet; `pre-update-snapshot.sh` stale name |

The squash fix confirmed itself: merging #303 with `--merge` succeeded on the exact path the old code would have hit with `--squash` and had rejected.

## The starting question (for the record)

As of 2026-06-22 a `monthly-update.sh` run would discover **9 BAKED** (alertmanager, forgejo, forgejo-db, gathio-db, jellyfin, navidrome, nextcloud, traefik, unifi-syslog), **4 TOO-YOUNG** (home-assistant, prometheus, unpoller, qbittorrent — the last bakes 06-23), **2 check-failed** (immich-server/-ml, ghcr rate-limit; version-locked set anyway), **2 local builds** untouched. Adoption is wave-ordered (plumbing → apps → core → DBs+dependents). No closed issue ever named the "June-18 first run" — that was a plan, not a ticket; the tooling arrived via PRs #271/#272.

## Lesson 1 — before retiring a thing, read what it does *now*, not what you remember it doing

The owner proposed dropping `update-before-reboot.sh`: *"previously it served a concrete purpose — it updated all containers in a gentle, step-by-step way; taking a snapshot is now easy with `urd backup`."* Both halves were stale, and the script's own body said so:

- The "gentle container update" job was **deliberately removed by ADR-030 Tier 1** (PR #222). Phase 3 no longer updates — it *ensures pinned digests are present and explicitly refuses to re-float them*. The function being "lost" was already gone.
- This is `feedback_verify_issue_premise_before_executing` applied to a **retire/refactor** decision, not a bug fix. The premise that justified deletion was a memory of the script's *old* contract. One `Read` of the file refuted it.

The right move with a "this looks superfluous" instinct is to open the file and diff its current behavior against the claimed behavior — the gap is usually the answer.

## Lesson 2 — a shared word ("snapshot") can hide non-equivalence

"`urd backup` already takes a snapshot" conflated two unrelated artifacts that happen to share a noun:

| | `pre-update-snapshot.sh` | `urd backup` |
|---|---|---|
| Produces | a **JSON state manifest** (images, every unit state, kernel/podman pkgs) | a **BTRFS data snapshot** + incremental send |
| For | the *before* half of `post-reboot-verify.sh`'s diff | data rollback/restore |
| Substitute for the other? | no | no |

When someone proposes "X already does what Y does," check that the two outputs are the same *kind* of thing, not just the same word. They were orthogonal: one protects data, the other makes a reboot verifiable.

## Lesson 3 — systemd already orders the shutdown; the real risk is the user@ stop budget (and I couldn't fully prove it)

The owner asked me to settle empirically whether a plain `reboot` already shuts containers down cleanly, so we'd know if graceful-shutdown was load-bearing. Findings:

- **Ordering is native.** Every DB consumer quadlet carries `After=`/`Requires=` on its DB (`nextcloud After=nextcloud-db`, `immich-server Requires=postgresql-immich`, …). `After=` governs *stop* order too, so systemd already stops apps before DBs. The manual ordering in `graceful-shutdown.sh` **duplicates** what the units encode — which weakened my own earlier "this is the load-bearing part" claim.
- **The non-obvious risk is a timer, not ordering.** `user@1000.service` has a **60s `TimeoutStopUSec`** (per-unit 45s; podman default stop 10s, no explicit `StopTimeout` on any DB). In the common case 37 containers stop well inside 60s. But one container that ignores SIGTERM can burn ~45s, and if the cumulative stop crosses 60s the *system* manager SIGKILLs the whole `user@` cgroup — killing whatever's stopped last, which by reverse-order is exactly the DBs and traefik. That's the only corruption-relevant failure mode, and it's what graceful-shutdown (running while the host is still up, no global cap) actually insures against.
- **Honest limitation:** I could not empirically confirm. The box hasn't rebooted since 2026-06-09 (`uptime -s`), the system journal is volatile across boots (only a stub for boot −1), and DB container logs had rotated past their startup banners. So "systemd suffices in the common case" is a **config-based inference, not an observation** — flagged as such. The clean test (deliberately reboot once without graceful-shutdown, then read DB recovery logs) was proposed, not run.

Net verdict: keep graceful-shutdown as **asymmetric tail-risk insurance** (severe failure, near-free, reboots are rare), not as the daily necessity I first implied. Correcting my own overconfidence mid-investigation was part of the value.

## Lesson 4 — stale self-description masquerades as redundancy; retarget, don't delete

The script *looked* deletable mainly because its **name and header advertised a job it no longer performed**. The fix was not removal but retargeting: rename to `prepare-for-reboot.sh`, rewrite the header to "does NOT update containers," and retitle the phases to their real jobs (state manifest → graceful shutdown → pinned-image presence → prune). The Phase-2 comment now records the 60s-budget rationale so the "isn't this redundant with systemd?" question isn't re-litigated next time. Mislabeling is a maintenance footgun: it invites correct-sounding but wrong decisions.

## Scope discipline — active refs move, historical refs stay

The rename had a wide blast radius (`grep update-before-reboot` → ~25 hits). The discipline that kept it sane:

- **Active references move with the file:** `monthly-update.sh`, `migrate-db-to-subvol8.sh`, CLAUDE.md, the automation-reference catalog, two guides, the (gitignored) `system-update` skill.
- **Historical records stay verbatim:** ADR-015/029, `docs/97-plans/*`, `docs/98-journals/*` describe what happened *at the time* and keep the old name. Rewriting them would falsify point-in-time history.
- **Deeper rot is flagged, not half-fixed:** the field guide still claims `:latest` tags and gives a pin-refloating recipe — actively wrong, but rewriting it is its own work package (#304), not collateral to a rename.

## Loose ends
- **#304** — the field-guide `:latest`/manual-pull rot (highest value: the recipe breaks the ADR-030 invariant), `graceful-shutdown.sh` hard-coded fleet (still references decommissioned `matter`), `pre-update-snapshot.sh` rename.
- Optional hardening that would make graceful-shutdown matter even less: add `TimeoutStopSec` to the DB quadlets and/or raise the `user@` stop budget, so a hung neighbor can't SIGKILL a mid-flush DB on the native path.
- The empirical reboot test (Lesson 3) remains the one way to convert inference into fact — worth doing on the next planned reboot.
