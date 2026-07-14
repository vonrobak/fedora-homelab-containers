---
type: ADR
title: "ADR-037: Forge Center-of-Gravity — Per-Repo Placement"
description: "ADR codifying a per-repo forge center-of-gravity rubric (GitHub-primary vs Forgejo-first) and the signing/merge consequences that follow from placement."
sensitivity: public
created: 2026-06-13
updated: 2026-06-13
---

# ADR-037: Forge Center-of-Gravity — Per-Repo Placement

**Date:** 2026-06-13
**Status:** Accepted (ratifies existing practice; codifies the rubric)

---

## Context

Two git forges are in play across the owner's projects:

- **GitHub** — public, discoverable, ecosystem-rich. The `containers` repo
  (`vonrobak/fedora-homelab-containers`) *started* here and has accumulated stars —
  i.e. real social capital and an external audience.
- **Self-hosted Forgejo** (`git.patriark.org`) — owner-controlled, private, the
  sovereignty substrate. `containers` mirrors to it as the append-only ledger
  `patriark/homelab` (transport: ADR-032 loopback SSH; gate: `scripts/mirror-to-forgejo.sh`).
  Newer **owner-only** projects (`jern-mgmt`, `htpc-mgmt`) are authored Forgejo-first.

The forge+signing substrate is built (ADR-032 transport, ADR-033 per-host author
signing, ADR-034 Forgejo instance merge signing), but it assumes a single implicit
topology and the **now-superseded squash-merge default** — ADR-033/034 (2026-06-06)
still name squash-merge "preferred," while `containers` went **merge-commit-only on
2026-06-12** (CLAUDE.md "Git & PR Workflow" + journal
`2026-06-12-lessons-handoff-execution-and-stacked-pr-gotchas.md`). That switch is now
recorded as **ADR-038**.

A recurring question keeps surfacing — *"why are PR merge commits 'unverified' in the
Forgejo ledger?"* and *"should we flip the forges so Forgejo is the source of truth?"* —
and gets re-litigated each time because **there is no recorded rule for which forge is
authoritative for a given repo.** The proximate observation:

- On a GitHub-primary repo, the **merge node** is signed by GitHub's web-flow key
  (`B5690EEEBB952194`, RSA). It shows `E`/"No public key" locally and "unverified" in
  the Forgejo ledger UI. This is **cosmetic and already metered**: the mirror gate
  blocks unsigned (`N`)/bad (`B`) commits but *passes* `E` and counts it into
  `forgejo_mirror_unverified_commits` (drift stays visible). Every **substance** commit
  is owner-signed (ADR-033) and verifies as `G`.
- Whether to "fix" the unverified merge node is, on inspection, **not a signing question
  but a forge-topology question** — it only has an answer once you decide which forge
  owns the authoritative merge. This ADR records that decision rule.

## Decision

### D1 — Forge center-of-gravity is assigned per repo, not globally

There is **no single primary forge.** Each repo has exactly one **authoritative forge**
(its *center of gravity*) where merges happen; any other forge is a **downstream
mirror**. Two standard placements:

- **GitHub-primary + Forgejo sovereignty ledger.** PRs/merges happen on GitHub; this
  host fetches `origin/main`, gates it (append-only + signature presence), and
  push-mirrors to the private Forgejo ledger. For repos carrying GitHub history/audience.
- **Forgejo-first + GitHub curated mirror (or none).** PRs/merges happen on Forgejo;
  GitHub, if present, is a downstream public mirror. For owner-only repos with no GitHub
  audience to court.

The mirror direction always follows the center of gravity: **the authoritative forge is
upstream, the mirror is downstream and never authored against.**

### D2 — The placement rubric

Three factors decide the center of gravity. A fourth decides **merge mechanics** *within*
the chosen forge (it does not move the center of gravity).

| Factor | Pulls **GitHub-primary** | Pulls **Forgejo-first** |
|---|---|---|
| **1. Audience & social capital** | Existing stars, external contributors, discoverability value | Owner-only; no external audience to court |
| **2. Sovereignty requirement** | Public legibility valued over key-purity on the merge node | Owner-controlled merge provenance end-to-end is a goal |
| **3. CI / automation locus** | GitHub Actions / `gh`-native tooling already in use | Local / Forgejo-side / no external CI |
| **4. Live-config coupling** *(mechanic, not placement)* | — | The worktree **is** the running config → raises the cost of any off-forge merge dance; favours forge-side merges + direct-push branch protection |

**Decision procedure.** Score factors 1–3.

- **Default for new owner-only tooling → Forgejo-first.** No audience to lose; sovereignty
  is free here (instance signing, ADR-034).
- **Default for repos carrying GitHub social capital → GitHub-primary.** You cannot
  un-publish stars; the public face is an asset.
- **When factors conflict:** audience/social-capital wins for *already-public* repos;
  sovereignty wins for *owner-only* repos. CI locus is a tiebreaker, not a driver — move
  CI to follow the chosen center of gravity, don't choose the forge to follow CI.

### D3 — Signing/merge consequences follow from placement (they are not chosen per-commit)

- **GitHub-primary tier.** The merge node is signed by GitHub's web-flow key, and that
  is **accepted as honest forge-action provenance** — it attests "merged through
  GitHub's authorized flow by the owner," which is *true and distinct* from authorship
  provenance (the substance commits, owner-signed per ADR-033). The Forgejo ledger
  preserves every substance signature and meters the merge node as `E`. Two standing
  "do nots":
  - **Do not import GitHub's web-flow key into Forgejo** to green the badge — it would
    assert GitHub as a *signing authority inside the sovereignty ledger* (anti-ADR-030
    ethos) and blind the `E` drift counter.
  - **Do not replace GitHub-side merges with local owner-signed merges on a live-config
    repo** — it reintroduces the live-config flicker window the merge-commit-only
    decision closed (checking out `main` transiently strips applied-but-unmerged changes
    from the running tree) and normalizes exercising the admin branch-protection bypass
    against a live tree (protection itself isn't a hard blocker — see Alternatives).
  - Merge strategy for live-config repos in this tier = **merge-commit-only** (ADR-038, 2026-06-12),
    which preserves the owner's substance signatures rather than squash-replacing them.

- **Forgejo-first tier.** The merge node is signed by the **Forgejo instance key**
  (ADR-034, owner-controlled software key) — so **squash-merge is fine**, because the
  synthesised commit is instance-signed and verifies. A GitHub mirror, if present, is
  downstream; the verification status GitHub assigns its mirror copy is irrelevant to
  provenance.

This **dissolves the apparent squash-vs-merge-commit inconsistency**: merge strategy is
a *per-tier* property. ADR-034's squash premise and the 2026-06-12 merge-commit decision
are both correct — for different tiers.

### D4 — Current assignments (the register)

| Repo | Center of gravity | Mirror | Merge strategy |
|---|---|---|---|
| `containers` (`fedora-homelab-containers`, has stars, **live-config**) | **GitHub-primary** | Forgejo ledger `patriark/homelab` | merge-commit-only (2026-06-12) |
| `jern-mgmt` (owner-only substrate) | **Forgejo-first** | GitHub mirror optional | squash OK (instance-signed, ADR-034) |
| `htpc-mgmt` (owner-only substrate) | **Forgejo-first** | GitHub mirror optional | squash OK (instance-signed, ADR-034) |

New repos are sorted into this table at creation using the D2 rubric.

## Consequences

### Positive

- **Settles a recurring decision with a rule** instead of re-deriving it every time the
  "unverified merge node / should we flip forges" question reappears.
- **Reframes the unverified merge node** on the `containers` ledger as *expected and
  correct* (honest forge-action provenance, metered), not a defect to chase.
- **Resolves the squash-vs-merge-commit drift** between ADR-034 and the 2026-06-12
  decision by making merge strategy per-tier.
- **New repos get sorted consistently** — owner tooling defaults to Forgejo-first, where
  sovereignty is free; public repos stay legible on GitHub.

### Negative / Risks

- **Heterogeneous topology** is more to hold in mind than "everything on one forge."
  Mitigated by this ADR and the D4 register.
- **GitHub-primary repos retain a liveness dependency on GitHub continuing to sign merge
  nodes.** An *unsigned* GitHub merge (status `N`, not `E`) would **halt the mirror gate**
  — a loud, safe failure (`forgejo_mirror_success=0` → `ForgejoMirrorFailed`), not silent
  corruption. Low probability; accepted and noted rather than engineered around.

## Alternatives Considered

- **Uniform GitHub-primary (all repos).** Simple and maximally legible, but **denies the
  sovereignty goal for owner-only tooling** and couples every repo's authoritative record
  to a third party. Rejected.

- **Uniform Forgejo-first, including `containers` (the "role reversal").** Explicitly
  weighed: make Forgejo the source of truth and GitHub a curated mirror. Rejected *for
  `containers`* because (a) it **abandons accumulated GitHub social capital** and
  discoverability; (b) **same-host authority coupling** — Forgejo runs on the very host it
  would now authoritatively describe (the mirror script is emphatic that Forgejo is *not*
  off-host DR; Urd owns DR), so the authoritative record of the infrastructure would live
  inside that infrastructure; (c) it **trades GitHub's web-flow software key for Forgejo's
  instance software key** — no hardware-backed provenance win (only local owner-signed
  merges get that, and those carry the flicker + branch-protection cost above); (d) it is
  a **large migration** (invert the mirror, re-tier Forgejo backups to "authority," move
  the review surface) for a **cosmetic root cause**. **Kept as a future option** if
  reducing GitHub-*platform* dependence (CI, availability, account risk) becomes a
  first-class goal — but the resilience-correct form is Forgejo on a *separate host*, a
  larger project than this question.

- **Import GitHub's web-flow key into Forgejo (or the local keyring).** Flips the merge
  nodes to "Verified," but asserts GitHub as a trusted signing authority inside the
  sovereignty ledger and **blinds the `E` drift counter** that the mirror gate maintains
  by design. Rejected.

- **Local owner-signed merges on `containers`.** Would put the owner's *hardware* key on
  the merge node end-to-end (verified on both forges). But the merge requires checking out
  `main` in a worktree that **is the running config** (transient live-config flicker).
  Branch protection is *not* a hard blocker here — the owner's admin **bypass** already
  lets signed commits reach `main` directly (confirmed 2026-06-13: a trivia-lane push went
  through, GitHub logging *"Bypassed rule violations … Changes must be made through a pull
  request"*). The cost is subtler: routinely local-merging would **normalize exercising
  that bypass**, eroding *in practice* the fat-finger protection that matters precisely
  because the tree is live — and the live-config flicker remains the hard disqualifier
  regardless. Cost outweighs a cosmetic gain on a private ledger. Rejected for live-config
  repos — and effectively how Forgejo-first repos already obtain owner-controlled merge
  provenance, via instance signing (ADR-034), without touching a live tree.

## Related

- **ADR-032** — Forgejo Git-over-SSH Loopback (the ledger push/transport).
- **ADR-033** — Per-Host Commit-Signing Policy *(private)* (author/substance signing; the
  GitHub-primary tier depends on it, and its §D4 already documents GitHub's web-flow
  re-signing).
- **ADR-034** — Forgejo Instance Commit Signing (the Forgejo-first tier's owner-controlled
  merge signing — the forge-side complement to GitHub's web-flow key).
- **ADR-030** — Container Supply-Chain Trust Model. **Deliberately NOT the parent of this
  ADR:** 030 governs trust of *third-party container images*; this governs *source-repo
  forge topology*. Different domain, different lifecycle (see this ADR's standalone-vs-
  addendum rationale).
- **ADR-038** — Merge-Commit-Only Strategy (the GitHub-primary, live-config tier's merge
  mechanic; defends the owner-key provenance this tier relies on). Decided 2026-06-12,
  recorded 2026-06-13. See also CLAUDE.md "Git & PR Workflow" + journal
  `docs/98-journals/2026-06-12-lessons-handoff-execution-and-stacked-pr-gotchas.md`.
- `scripts/mirror-to-forgejo.sh` — append-only, signature-gated ledger push (`N`/`B`
  block, `E` meter via `forgejo_mirror_unverified_commits`).
- Memory: `project_config_as_code_substrate`, `project_forgejo`.

---

**Decision made by:** User (patriark) + Claude Code analysis
**Trigger:** A standing "why are PR merge commits unverified in the Forgejo ledger, and
should Forgejo become the source of truth?" discussion surfaced that the homelab has two
forges but no recorded rule for which one is authoritative per repo — so the answer was
re-litigated each time and the squash-vs-merge-commit strategy read as inconsistent
across ADR-034 and the 2026-06-12 merge-commit-only switch. This ADR records the
per-repo placement rubric and the signing/merge consequences that follow from it.
