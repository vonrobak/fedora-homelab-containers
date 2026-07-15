---
type: ADR
title: "ADR-044: CLAUDE.md Untracked and Vault-Resident"
description: "ADR deciding that CLAUDE.md itself moves into the private Huldr vault (gitignored symlink), closing the public-instruction-injection surface a mergeable CLAUDE.md represents — adopts urd ADR-118 delta 7 for this repo."
sensitivity: public
created: 2026-07-15
updated: 2026-07-15
---

# ADR-044: CLAUDE.md Untracked and Vault-Resident

**Date:** 2026-07-15
**Status:** Accepted. **Amends** ADR-043 the way ADR-036 amends ADR-030: ADR-043 decided
the doc boundary is a per-document sensitivity property; this ADR carves out one
specific file — `CLAUDE.md` itself — as a categorical exception to D4's "guides are
born in this repo, public" default.

---

## Context

The sibling `urd` repo's own documentation-boundary ADR (ADR-118, 2026-07-15) went one
step further than this repo's ADR-043: it untracked `CLAUDE.md` itself, moving it into
urd's vault bundle behind a gitignored symlink, not just the internal doc tiers
(`90-archive` … `99-reports`). urd's stated reasoning (ADR-118, delta 7):

> `CLAUDE.md` is loaded automatically by every AI-assisted session in this repo, which
> makes a public, mergeable copy a real attack surface: an external PR that alters it
> (if merged) would have its instructions picked up by the next session that reads it,
> with no separate review lens for "does this instruction look like an operator would
> write it." Untracking it removes that surface entirely.

The same argument applies here unchanged. This repo's `CLAUDE.md` is public, tracked,
and loaded into every session's context automatically — a merged PR that edited it
would have its content followed by the next session with no distinct scrutiny beyond
ordinary code review (which is tuned to catch bugs, not to catch "does this read like
an instruction an attacker planted"). Checked 2026-07-15: the file also still names the
private Forgejo repo (`patriark/huldr`) inline — an accepted precedent under ADR-043,
not a leak, but evidence the file has never been reconsidered under this specific lens
before now.

urd's ADR-118 explicitly scoped this delta to urd only ("whether to apply it to
containers or other repos is a separate future decision, not part of this ADR"). This
ADR is that separate decision for `containers`.

## Decision

`CLAUDE.md` is untracked (`git rm --cached CLAUDE.md`) and replaced with a gitignored
symlink to `~/Huldr/projects/homelab/CLAUDE.md` — the same mechanism already used for
the `docs/9x` tiers (ADR-043, physical boundary + `.gitignore`, no trailing slash so
the pattern matches the symlink and not a directory). The vault copy carries no OKF
frontmatter (unlike other vault documents) — it is loaded verbatim as session
instructions, not browsed as a knowledge-graph node, and prepending YAML to it would
put non-instruction content at the top of every session's context for no benefit.

This is a **categorical exception to ADR-043 D4**, not a reclassification via
`sensitivity:` frontmatter: `CLAUDE.md` was never assessed as containing
internal-sensitivity *content* (it mostly doesn't — it's teaching prose about
architecture and conventions, the same character as any other guide). The move is
justified purely by what the file **is** — an auto-loaded instruction surface — not by
what it **says**. `docs/CONTRIBUTING.md` remains public and unaffected; it is not
auto-loaded and carries no comparable injection risk.

## Consequences

- **Closes the injection surface.** A malicious or careless external PR can no longer
  alter the instructions an AI session reads automatically on every future invocation
  of this repo — the only edit path is the vault, reached solely by the owner.
- **External contributors and CI lose `CLAUDE.md` entirely, not just internal notes.**
  A fresh clone, a fork, or a contributor without vault access now sees no
  architecture/conventions guidance at all — `docs/CONTRIBUTING.md` is what remains.
  This repo has an active public audience (40 stars, 3 forks at last count) who lose a
  genuinely useful teaching document as a direct cost of this change.
- **One-way GitHub-history exposure, unaffected either way.** Every prior public
  version of `CLAUDE.md` remains visible in this repo's GitHub history regardless of
  this decision — untracking does not and cannot retroactively hide it. The decision
  only affects versions from this point forward.
- **This ADR is itself public** (ADR-043 D2: all ADRs are born public), which means the
  reasoning for hiding `CLAUDE.md` is not itself hidden — consistent with D2's
  rationale that ADRs are design rationale, not the operational specifics an attacker
  would want.
- Future `CLAUDE.md` edits follow the vault's commit discipline (direct-to-main,
  signed, no PR ceremony — ADR-043 D6), not this repo's branch+PR workflow. A session
  that wants to propose a `CLAUDE.md` change now does so through the owner directly,
  not through a mergeable diff.

## Alternatives Considered

- **Keep `CLAUDE.md` public and tracked (status quo).** Preserves the external-teaching
  value and this repo's GitHub-primary posture (ADR-037); accepts the injection-surface
  risk as a known, unmitigated trade-off. Rejected because the risk is real and the
  mitigation (vaulting) is cheap and already precedented in the sibling repo.
- **Minimal public stub + detailed content in the vault.** Keeps some external-facing
  value (a short "this project uses Podman quadlets, see CONTRIBUTING.md" pointer)
  while moving operational conventions private. Not adopted here: a stub still has to
  be hand-authored and kept from silently becoming a second `CLAUDE.md` by a future
  session that forgets the split exists; the clean symlink boundary that already works
  for `docs/9x` is simpler and has zero drift risk. Revisitable if the external-teaching
  cost of a fully empty file turns out to matter more in practice than expected.

## Related

- **ADR-043** — the per-document sensitivity model this ADR amends with a categorical
  (file-identity-based, not content-based) exception.
- **urd ADR-118** (`github.com/vonrobak/urd`,
  `docs/00-foundation/decisions/2026-07-15-ADR-118-documentation-boundary-per-document-sensitivity.md`)
  — delta 7 is the adopted precedent; this ADR is the "separate future decision" that
  ADR-118 explicitly deferred.
