# Forge center-of-gravity & merge strategy — two ADRs from one "unverified PR" question

**Date:** 2026-06-13
**Status:** ADR-037 (forge center-of-gravity) + ADR-038 (merge-commit-only) written;
ADR-037 cross-refs reconciled; CLAUDE.md latest-pointer + Design-Guiding list + Git&PR
heading updated. Not yet committed (doc-only → trivia-lane eligible).
**Context:** A throwaway question — *"why does Forgejo show my PR merge commits as
unverified when every other commit is verified?"* — turned out to be the visible surface
of an **unrecorded architectural decision** (which forge is authoritative for a given
repo). The session's value was resisting the urge to "fix the badge" and instead naming
the missing decision. This entry records the trade-offs, the decisions, and the rejected
alternatives.

---

## The question, and the empirically confirmed answer

The hypothesis was right: GitHub signs PR merge commits **server-side** with its web-flow
key, and Forgejo doesn't know that key. Evidence from the actual ledger:

| Commit | committer | key | `%G?` |
|---|---|---|---|
| `d6a2c85` (PR #298 **merge node**) | `GitHub <noreply@github.com>` | RSA `B5690EEEBB952194` (GitHub web-flow) | `E` — "No public key" |
| `5c20e63` (**substance** commit *inside* #298) | `vonrobak` | `ED25519-SK` (FIDO2) | `G` |

Forgejo verifies a commit only when the signing key is registered to an account: the
owner's SSH key is → substance verifies; GitHub's web-flow key isn't → merge nodes don't.
Even local `git` can't verify the merge node (the web-flow pubkey isn't in the keyring).
ADR-033 §D4 already documented this for the squash era; it was never generalized.

## The framing that unlocked everything: two axes

The whole problem reduces to **(1) where the authoritative merge commit is created × (2)
whose key signs it.** Every "fix" is just a move on those two axes:

- GitHub button → GitHub web-flow key (status quo)
- Local `--no-ff` merge → owner's YubiKey
- Forgejo merge → Forgejo instance key (ADR-034)

Once framed this way it was obvious the badge is **not a signing bug** — it's a
**topology question wearing a cosmetic mask**. You can't answer "should the merge node
carry my key?" without first answering "which forge owns the authoritative merge?" — and
*that* had no recorded rule.

## What the mirror gate already does (so this wasn't urgent)

`scripts/mirror-to-forgejo.sh` gate 2 blocks unsigned (`N`) / bad (`B`) commits but
**passes `E`** (locally-unverifiable — i.e. GitHub-signed merge nodes) and counts them
into `forgejo_mirror_unverified_commits`. So the ledger *knowingly* accepts GitHub-signed
merge nodes and meters the drift. The "unverified" badge is a designed-in, metered state,
not an oversight. **Latent fragility found:** an *unsigned* (`N`) GitHub merge would
**halt** the mirror — a loud, safe failure, but a real liveness dependency on GitHub
continuing to sign. Unalerted today (only `success==0`/staleness alert); accepted.

## The core trade-off

The owner-key-on-merge-node property is **a homelab-specific value derived from the
ADR-030 ethos, not an industry norm.** The OSS world puts ~zero weight on who signs a
*merge* commit; GitHub-signed merges are the expected, healthy state. So the question was
never "how do we meet best practice" — it was "is our self-imposed sovereignty preference
worth what it costs *on this repo*?" And on `containers` it costs a lot, because **this
worktree is the running config.**

## Decisions

1. **`containers` stays GitHub-primary; accept GitHub-signed merge nodes** as honest
   *forge-action* provenance (distinct from *authorship* provenance, which is already
   owner-signed). Don't chase the badge.
2. **Codify a per-repo placement rubric** → **ADR-037**. Each repo has one authoritative
   forge; the other is a downstream mirror. Rubric = audience × sovereignty × CI locus,
   with live-config coupling as a separate *mechanic* factor. Defaults: owner-only tooling
   → Forgejo-first; GitHub-history repos → GitHub-primary.
3. **Promote the 2026-06-12 merge-commit-only switch to its own ADR** → **ADR-038**
   (it previously lived only in CLAUDE.md + a journal, yet ADR-037 leans on it).
4. **Meta-decision: ADR-037 is standalone, NOT an addendum to ADR-030.**

## Trade-offs weighed (the heart of it)

### Cosmetic badge ⇄ sovereignty purity
The substance — the actual changes and their authorship — is already 100% owner-signed and
gated. Only the structural merge *node* is foreign-signed. Reframed: GitHub's key on the
merge node is a *true statement* ("merged via GitHub's authorized flow by the owner"), not
a defect. Verdict: not worth contorting the workflow to change.

### Branch protection + live-config flicker ⇄ owner-signed merges (why "option C" lost)
The clean way to get the owner's key on the merge node is a **local `--no-ff` merge**. But
that requires `git checkout main` in a worktree that **is the running config** — a
transient flicker window (the exact failure class the merge-commit-only decision was made
to *eliminate*; see ADR-038 / the 2026-06-12 journal where a rebase reverted live Traefik
`middleware.yml`). It also requires relaxing direct-push branch protection — fat-finger
protection that matters *more* here than generically, again because the tree is live. So C
trades against **two of the repo's own invariants** to buy a property the outside world
considers a non-event. Rejected for live-config repos.

> Heuristic captured: **when a "fix" fights two of the repo's own invariants, the fix is
> probably wrong and the status quo is probably a derived consequence worth recording —
> not a gap to close.**

### GitHub social capital ⇄ Forgejo independence (why not flip the forges)
Role-reversal (Forgejo = source of truth, GitHub = curated mirror) was weighed seriously.
It's the purest sovereignty play, but for `containers` it loses: (a) abandons accumulated
GitHub stars / discoverability; (b) **same-host authority coupling** — Forgejo runs on the
very host it would authoritatively describe (the mirror script is emphatic Forgejo is *not*
off-host DR); (c) trades GitHub's *software* key for Forgejo's *software* key — **no
hardware-backed win** (only local merges get that, and those carry the flicker cost); (d)
large migration for a cosmetic root cause. Kept explicitly as a **future option** if
GitHub-*platform* divestment ever becomes a first-class goal — but the resilience-correct
form is Forgejo on a *separate host*, a bigger project than this question.

### Standalone ADR ⇄ addendum to ADR-030 (getting the parent right)
ADR-036 set an "amends ADR-030" precedent, so the addendum path was tempting. Rejected:
ADR-030 governs trust of *third-party container images*; this governs *source-repo forge
topology* — different domain, different lifecycle. The real family is the forge cluster
**ADR-032/033/034**, where ADR-030 appears only as a one-line "Related" thread. An addendum
would have implied a lineage that doesn't exist and buried a cross-cutting topology
decision inside an image-trust document. **Lesson: ADR placement is itself a decision —
"addendum" asserts same-domain lineage; "standalone" asserts a new domain. Pick the parent
deliberately, it drives future discoverability.**

## Alternatives considered and rejected (consolidated)

- **Import GitHub's web-flow key into Forgejo** to green the badge — rejected: asserts
  GitHub as a *signing authority inside the sovereignty ledger* (anti-ADR-030 ethos) and
  **blinds the `E` drift counter** the gate maintains by design.
- **Local owner-signed merges on `containers`** — rejected (live-config flicker + branch
  protection; see above). It *is*, however, effectively how the Forgejo-first tier already
  gets owner-controlled merge provenance — via instance signing (ADR-034), without touching
  a live tree.
- **Role reversal for `containers`** — rejected for now, kept as a future GitHub-divestment
  option (above).
- **Squash + Forgejo instance signing** on `containers` — gives the *forge's* key, not the
  owner's, and doesn't fix stacked-PR ancestry; correct for the Forgejo-first tier, wrong
  here.
- **ADR-037 as an addendum to ADR-030** — rejected (domain boundary, above).

## The reframe that dissolved an apparent contradiction

ADR-033/034 (2026-06-06) call squash-merge "preferred"; the repo went **merge-commit-only
on 2026-06-12**. That looked like drift. The placement rubric resolves it: **merge strategy
is per-tier.** GitHub-primary live-config repos → merge-commit-only (preserve owner
signatures, no flicker). Forgejo-first repos → squash is fine (the instance key signs the
synthesized node). Both ADRs are correct, for different tiers. Recording this was half the
value of writing ADR-037.

## Outputs

- `docs/00-foundation/decisions/2026-06-13-ADR-037-forge-center-of-gravity-per-repo.md`
- `docs/00-foundation/decisions/2026-06-12-ADR-038-merge-commit-only-strategy.md`
- `CLAUDE.md`: latest-pointer `036 → 038`; ADR-037/038 added to Design-Guiding list; Git&PR
  heading tagged `ADR-038`.

## Lessons learned

- **A "cosmetic" question can be the surface of a missing decision.** The win was finding
  the unrecorded rule (which forge is authoritative), not fixing the symptom.
- **A status quo that fights every "fix" is often a derived consequence, not a gap.** Record
  it as such (ADR-037 D3 does exactly this for "stay on A").
- **Heterogeneous-on-purpose beats forced uniformity.** A two-tier forge portfolio fits the
  repos' actual centers of gravity; mandating one forge everywhere would be ideology over
  fit.
- **Choose an ADR's parent deliberately** — addendum vs standalone encodes a domain claim.

## Next steps

- Commit the changeset (doc-only, trivia-lane) — pending owner go-ahead; would `export
  SSH_AUTH_SOCK=/run/user/1000/gcr/ssh` first (headless-session gotcha).
- Optional: run `scripts/auto-doc-orchestrator.sh` so the documentation index reflects
  ADR-037/038.
- **Follow-up gap:** the 2026-06-12 merge-commit decision is now ADR-038, but consider
  whether `forgejo_mirror_unverified_commits` deserves a low-priority alert (would catch an
  `N` before it silently halts the mirror — though the halt itself already pages).
- **Deferred strategic option:** role reversal → revisit only if GitHub-platform
  divestment becomes a goal, and then as Forgejo-on-a-separate-host.
