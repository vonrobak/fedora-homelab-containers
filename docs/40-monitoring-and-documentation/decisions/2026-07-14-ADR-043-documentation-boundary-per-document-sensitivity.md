# ADR-043: Documentation Boundary as a Per-Document Sensitivity Property

**Date:** 2026-07-14
**Status:** Accepted. **Amends** the Huldr knowledge-vault decision (vault mechanics are
canonical in the htpc-mgmt ADR series — the vault is substrate, hosted and versioned
outside this repo) the way ADR-036 amends ADR-030: the vault decision created the private
home; this ADR decides what belongs in each home and how documents and commits flow
between them.

---

## Context

The Huldr vault migration (PRs #326/#327, 2026-07-13) made the `docs/9x` directories
physically private: journals, plans, reports, supervisor docs, and archive live in a
private Obsidian vault (private Forgejo repo), reachable from this repo only through
gitignored symlinks. `git add` here cannot stage them; a pre-commit gate
(`scripts/check-vault-boundary.sh`) rejects staged markdown carrying
`sensitivity: internal|secret`.

That left the public half of the estate undecided. Measured 2026-07-14: `docs/00-40`
holds 124 markdown files, of which **18 contain RFC1918 addresses** — mostly incidental
mentions in guides, concentrated in `30-security` (7/20). The IR runbooks are largely
clean (IR-001/002: zero internal references; IR-005: six). This is a materially
different exposure than the journals were (270 files of full topology narrative and
credential-adjacent prose, three live credentials): the public tree is a
mostly-deliberate teaching corpus, not a leak in progress. The repo has active
followers (40 stars, 3 forks) who consume its documentation and ADRs.

Five trajectories were evaluated and scored in the 2026-07-14 documentation-boundary
plan (vault-resident; cited here by name per D5's own rule — it is this ADR's
deliberation record): hold-the-line (45), **per-document sensitivity (87)**,
vault-first-publish-by-exception (58), single-source export pipeline (55), full
privatization (30). The per-document trajectory was ratified in a full owner interview,
absorbing the vault-first idea narrowly (for sensitive-first drafts) and keeping the
export pipeline as a named future option.

## Decision

### D1 — The boundary is a property of the document, not of a directory

Every markdown document in the fleet carries frontmatter including
`sensitivity: public | internal | secret`. Directory placement *follows from*
classification: `internal`/`secret` documents live in the vault (physically unstageable
here), `public` documents live in this repo's `docs/00-40` with `sensitivity: public`
explicit. The pre-commit gate enforces the boundary for anything misplaced. The public
tree receives mechanical frontmatter backfill (`type`, `title`, `description`, dates,
`sensitivity`) to make classification universal and machine-checkable.

### D2 — ADRs are public, all of them, and new ones are born public

ADRs are design rationale, not topology; they are the repo's primary teaching value and
reveal little the public quadlets and Traefik configs do not. When an ADR needs internal
specifics, those go in a vault-side companion note linked *from* the vault — never the
reverse.

### D3 — Runbooks pass a split test; other flagged files scrub in place

A runbook stays public when the *procedure* is generic and specifics are incidental
(IR-001..004, DR-001..004 — stray internal references scrubbed). It moves to the vault
when specificity *is* its value (IR-005, nextcloud-operations), leaving a public stub:
title, one-line purpose, "operational specifics live in the private vault." For the
remaining flagged guides the default is **scrub-in-place** (placeholder incidental
IPs/hostnames); a file moves to the vault only when the review shows specificity is
load-bearing.

### D4 — Birth rule: type decides, repo-public default

Guides, ADRs, and patterns are born in this repo, public, with frontmatter from day
one. A document whose *first draft* needs internal specifics (incident post-mortems,
host-specific runbooks) is born in the vault; publishing it later is a deliberate
copy-and-scrub, never a move-and-hope. Journals, plans, reports, and supervisor docs
are always vault-born (settled by the vault migration). Public docs are **not** worded
for an external audience — they are written for the owner; the public reader is a
welcome eavesdropper. Only genuinely outward-facing files (README, CONTRIBUTING) are
audience-specific.

### D5 — Link policy: three zones, asymmetric across the boundary

1. **Vault → vault:** relative markdown links, Obsidian-managed (OKF graph edges).
   Link liberally; broken links are work items, not errors.
2. **Public → public:** relative paths and textual `ADR-NNN` references, unchanged.
3. **Across the boundary, asymmetric:** public → vault **never as paths or links**;
   a public PR body or ADR may mention a vault document **by name only, when strictly
   necessary** (as this ADR does for its deliberation record). Vault → public is free
   and encouraged — GitHub PRs, commit hashes, URLs, repo paths in prose. The vault
   journal is the record an LLM should counsel as source of truth, so its citations
   point outward.

### D6 — Two homes, two commit disciplines, documentation after the PR

This repo keeps ADR-038 (branch + PR, merge commits, owner-signed; trivia lane for
public-doc/comment-only changes). The vault commits direct-to-main on private Forgejo,
signed with the agentless software key, no PR ceremony — the journal is the review
surface. **Ordering: documentation is written after the code lands** (code →
commit/PR → vault journal → vault commit), because docs written before a PR get the
tense wrong and mislead future sessions about what is closed versus in progress. The
workflow is operationalized as skills — refreshed `/commit-push-pr` (trivia lane
encoded, no in-skill main-push override for config-touching diffs), new
`/commit-push-docs` (vault-side, frontmatter-gated, fleet-generic and bundle-aware,
user-level), and project-local `/journal` + `/session-close` — with asymmetric
cross-home dirty-check nudges at each skill's tail.

### D7 — Each home documents itself

`CONTRIBUTING.md` (public) fully covers the public tree's conventions and states only
that private documentation lives in a private vault with its own conventions — no
paths, no titles. The vault carries its own companion conventions document (OKF
frontmatter schema, journal templates, session ritual).

## Consequences

- The 00-40 frontmatter backfill and the 18-file scrub/split become scheduled work
  (plan WP-C), after which the pre-commit gate is meaningful across the whole tree and
  a standing audit view ("`sensitivity: public` AND body matches `192.168`") can hold
  the line.
- Classification work is done to the standard a future single-source export pipeline
  (the T4 trajectory) would require, keeping that evolution open at zero extra cost —
  but no generator is built now; the human pause of a manual publish is retained
  deliberately.
- Two authoring homes require a per-document call at birth; D4 makes it mechanical.
- Public runbook stubs and their vault twins can drift; the split test (move only when
  specificity is the value) keeps the affected set small (2 files today).
- Journals already on public GitHub history/forks remain there (stop-forward,
  reaffirmed). Rotation of the three exposed credentials is prerequisite work tracked
  elsewhere and is not affected by any boundary policy.

## Alternatives Considered

- **Hold the line (directory boundary only), 45/100** — leaves 18 public files
  unclassified, the gate blind where authoring continues, and the two-home workflow
  improvised; unstable equilibrium.
- **Vault-first everything, publish by exception, 58/100** — maximum drafting freedom,
  but the public repo's living docs decay into a brochure and config-adjacent guides
  drift from the config they describe. Its birth-rule idea is absorbed narrowly in D4.
- **Single-source export pipeline (vault → generated public tree), 55/100** — elegant
  single source of truth, but `git blame` lies, PRs stop reviewing authored diffs,
  outside doc contributions become impossible, and an automated export *removes* the
  human pause a manual publish provides. Named future option; D1's frontmatter work is
  its prerequisite, so nothing is lost by waiting.
- **Full privatization of docs/, 30/100** — disproportionate to measured exposure,
  amputates the learning-in-public philosophy, and the public quadlets/AUTO-* would
  still reveal the service inventory anyway.
