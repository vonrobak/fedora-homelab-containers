# ADR-038: Merge-Commit-Only Strategy (signature provenance + stacked-PR safety)

**Date:** 2026-06-12
**Status:** Accepted (Implemented 2026-06-12; recorded retroactively 2026-06-13)

---

## Context

The `containers` repo previously merged PRs by **squash** (the default through the
ADR-033/034 era, which still name squash-merge "preferred"). A single multi-PR handoff
session on 2026-06-12 — three stacked work packages merged in sequence — surfaced two
independent failures that made squash (and rebase) merge the wrong strategy *for this
repo specifically*, because **this worktree is the running config**: history mechanics
here are live-service risk, not just hygiene.

**Failure 1 — squash destroys owner-key provenance.** When GitHub squash-merges, it
synthesises a *new* commit and signs it with its **web-flow GPG key**
(`B5690EEEBB952194`). The owner's per-commit FIDO2/SSH signatures (ADR-033) do **not**
survive onto `main` — `main`'s provenance ends up attesting to GitHub's key, not the
owner's hardware key. That directly contradicts the ADR-030 ethos that `main` should
attest to the owner.

**Failure 2 — squash/rebase is unsafe for stacked PRs against a live tree.** The
session's stacked branches (wp1 → wp2 → wp3) hit a cascade of sharp edges, all recorded
in the incident journal:

- Squashing wp1's base broke wp2's ancestry — GitHub marked the child **CONFLICTING**,
  forcing a `git rebase --onto origin/main <old-base-tip> <child>` dance (and so for wp3
  after wp2). Rebasing replays commits → **force-push** semantics.
- `gh pr merge --delete-branch` on a stacked **base** did *not* retarget the child to
  `main` — it **closed #282 irrecoverably** (a PR whose base branch is gone cannot be
  reopened). Recovery cost a recreated PR (#286) and the lost review thread/number.
- The rebase dance **checks out child branches in the live worktree**: Traefik's
  `middleware.yml` momentarily reverted Immich's burst limit (auto-reloading provider!),
  and an earlier branch-off-main nearly reverted live alert rules and deleted a
  branch-new file a running container had bind-mounted. **Same root cause as the
  live-config flicker rule.**

Both failures point the same way: keep substance commits (and their owner signatures)
intact on `main`, and never rewrite/replay history across a worktree that running
services read.

## Decision

### D1 — Merge strategy is **merge-commit-only**; squash and rebase merge are disabled repo-side

GitHub repo settings disable both "Squash and merge" and "Rebase and merge." Every PR
lands as a `--no-ff` merge commit. Substance commits keep their **owner SSH signatures**
(`%G?` → `G`); only the **merge node** is GitHub-web-flow-signed (`E` locally) — a
cosmetic residual governed by **ADR-037** (this repo is the GitHub-primary tier).

### D2 — Branch discipline

**1–2 clean, SSH-signed commits per branch** (no fixup litter — it lands on `main`
forever). **Branch + PR per work package.** **Stacked branches merge in order with no
rebasing needed** — merge commits preserve ancestry, so a child stays mergeable after
its base merges.

### D3 — Stacked-PR handling rules (learned the hard way)

- **Retarget every child PR to `main` *before* merging/deleting its base**
  (`gh pr edit <child> --base main`) — this is what saved #283.
- **Live-config rule stands:** never return the worktree to `main`, and never rebase
  across applied-but-unmerged changes — running services read this tree. A dedicated
  `git worktree` for PR mechanics (separate from the live tree) eliminates the flicker
  entirely and is recommended if stacked sessions become routine.
- Avoid `--delete-branch` on a stacked base until the whole stack is merged (it also
  deletes the *local* branch, breaking the follow-up rebase).

### D4 — Trivia lane

Journals, comment fixes, and doc-only commits may be pushed **directly to `main`
(signed)** — PR ceremony adds nothing there. Substantive work always gets a PR (the PR
body is the owner's review surface).

### Operational equivalents

- **PR-level history view:** `git log --first-parent --oneline` (recovers the old
  squash-style one-line-per-PR view).
- **Revert a merged PR:** `git revert -m 1 <merge-sha>`; individual substance commits
  revert normally.

## Consequences

### Positive

- **`main` attests to the owner's hardware key** — substance commits retain their SSH
  signatures; the only GitHub-signed object is the merge node (governed, metered,
  cosmetic — ADR-037).
- **Stacked PRs merge in order with no rebasing or force-pushing** → no live-config
  flicker from PR mechanics.
- **PR-per-package preserves the owner's review surface** (the PR body), and
  `--first-parent` keeps a clean PR-level history view.
- **Clean reverts:** `git revert -m 1 <merge-sha>` undoes a whole PR atomically.

### Negative / Risks

- **Busier `main` graph** than squash (a merge node + substance commits per PR rather
  than one flattened commit). Mitigated by the `--first-parent` view.
- **Branch-discipline burden:** authors must curate 1–2 clean commits per branch (no
  fixup litter), since everything lands on `main` permanently.
- **The merge node itself is GitHub-web-flow-signed (`E`).** Accepted and governed by
  ADR-037; flipping it to an owner signature would require off-GitHub local merges, which
  reintroduce live-config flicker (rejected there).

## Alternatives Considered

- **Squash-merge (the prior default).** Cleanest linear history, but **replaces owner
  signatures with GitHub's web-flow key** (Failure 1) and **breaks stacked-PR ancestry**
  (Failure 2). Rejected for this repo.
- **Rebase-merge.** Preserves individual commits *and* gives linear history, but rewrites
  commit hashes and replays onto `main` → force-push semantics and the same
  stacked-ancestry fragility; rebasing in a live-config worktree flickers running
  services. Rejected.
- **Squash + Forgejo instance signing** (sign the synthesised squash commit). Restores a
  signature, but it is the *forge's* key, not the owner's hardware key, and it does
  nothing for the stacked-PR ancestry breakage. This is exactly the **Forgejo-first
  tier's** model (ADR-034/037) — correct *there*, wrong for this GitHub-primary repo.
  Rejected here.
- **Keep squash but do PR mechanics in a separate `git worktree`.** Removes the
  live-config flicker but not the signature-replacement problem. Kept as an **orthogonal
  good practice** for stacked sessions regardless of merge strategy, not a substitute for
  this decision.

## Related

- **ADR-037** — Forge Center-of-Gravity (governs the residual GitHub-signed merge node;
  merge-commit-only is the GitHub-primary, live-config tier's merge mechanic).
- **ADR-033** — Per-Host Commit-Signing Policy *(private)* (the owner signatures squash
  was destroying).
- **ADR-034** — Forgejo Instance Commit Signing (the Forgejo-first tier's alternative:
  squash + instance-signed merge node).
- **ADR-030** — Container Supply-Chain Trust Model (the "attest to the owner's key, not
  GitHub's" ethos this defends).
- Incident journal:
  `docs/98-journals/2026-06-12-lessons-handoff-execution-and-stacked-pr-gotchas.md`
  (the stacked-PR gotchas, §"GitHub / git workflow gotchas").
- CLAUDE.md "Git & PR Workflow" — the day-to-day operational reference for this policy.
- `scripts/mirror-to-forgejo.sh` — append-only Forgejo ledger; a reverted PR mirrors as
  a normal forward commit (`git revert -m 1`), never a history rewrite.

---

**Decision made by:** User (patriark) + Claude Code analysis
**Trigger:** A multi-PR handoff session (2026-06-12) where squash-merge irrecoverably
closed a stacked child PR and the rebase-to-recover dance flickered live Traefik config —
exposing that squash both destroys owner-key provenance on `main` and is unsafe for
stacked PRs against a worktree that *is* the running configuration. Recorded as an ADR
on 2026-06-13 so ADR-037 references a peer rather than prose.
