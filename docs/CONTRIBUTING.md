# Documentation Standards

**Primary consumer:** Claude Code sessions | **For deployment/architecture:** see `CLAUDE.md`

This guide covers when, where, and how to write documentation. It does not repeat deployment procedures or architecture details from `CLAUDE.md`.

---

## The Two Homes (ADR-043)

Documentation lives in two places, and the boundary is a **per-document property**, not a directory convention:

- **This repo (`docs/00-40`)** — public on GitHub. Guides, ADRs, runbooks, patterns. Every document carries frontmatter with `sensitivity: public` explicit.
- **The private vault** — journals, plans, reports, supervisor docs, archive, and any document classified `internal` or `secret`. The `docs/9x` paths still resolve (gitignored symlinks), but the content is physically unstageable here; a pre-commit gate (`scripts/check-vault-boundary.sh`) rejects staged markdown carrying `sensitivity: internal|secret`. The vault has its own conventions document — consult it there.

**Birth rule (type decides, repo-public default):** guides, ADRs, and patterns are born here, public, with frontmatter from day one. A document whose *first draft* needs internal specifics (incident post-mortems, host-specific runbooks) is born in the vault; publishing it later is a deliberate copy-and-scrub. Do not word public docs for an external audience — write for the owner; the public reader is a welcome eavesdropper.

**Runbook split test:** a runbook stays public when the procedure is generic and specifics are incidental (scrub stray IPs/hostnames to placeholders). It lives in the vault when specificity *is* its value — leaving a public stub here: title, one-line purpose, "operational specifics live in the private vault."

**Commit discipline differs per home:** this repo follows ADR-038 (branch + PR, merge commits; trivia lane for public-doc/comment-only changes). Vault docs commit direct-to-main on the private forge — never here. **Documentation is written after the code lands** (code → commit/PR → journal), so records use past tense and never describe closed work as in progress.

---

## Decision Tree: Should You Document?

### Step 1: Is documentation needed?

**Do NOT create documentation for:**
- Routine config changes (the commit message is sufficient)
- Bug fixes with obvious causes (the fix speaks for itself)
- Changes already captured by auto-generated docs (`AUTO-*.md`)
- Information that duplicates `CLAUDE.md` content

**DO create documentation for:**
- Architectural decisions with non-obvious trade-offs (ADR)
- Multi-step procedures someone will repeat (guide)
- Learning or context that would be lost without a record (journal)
- Forward-looking work with milestones to track (plan)
- Security incidents requiring post-mortem (incident)

### Step 2: What type of document?

| If you need to... | Create a... | Mutable? |
|---|---|---|
| Explain how something works now | Guide | Yes (update in place) |
| Record what happened and why | Journal | No (append-only) |
| Plan future work with milestones | Plan | Yes (status updates) |
| Justify an architectural choice | ADR | No (supersede only) |
| Capture a system state snapshot | Report | No (immutable) |
| Analyze a security incident | Incident post-mortem | No (immutable) |

### Step 3: Where does it go?

| Domain | Directory | Home |
|---|---|---|
| Core design patterns, philosophy | `00-foundation/` | public (this repo) |
| Service-specific (Jellyfin, Immich, etc.) | `10-services/` | public (this repo) |
| Operational procedures, DR runbooks | `20-operations/` | public — split test applies |
| Security, incident response | `30-security/` | public — split test applies; incidents born in vault |
| Monitoring, SLOs, documentation meta | `40-monitoring-and-documentation/` | public (this repo) |
| Distilled lessons, situational awareness | `96-project-supervisor/` | **vault** (symlink; versioned privately) |
| Strategic plans, roadmaps | `97-plans/` | **vault** (symlink) |
| Chronological logs, session notes | `98-journals/` | **vault** (symlink) |
| Automated reports (JSON, snapshots) | `99-reports/` | **vault** (symlink; untracked churn) |
| Superseded documentation | `90-archive/` | **vault** (symlink) |

Within domain directories, use subdirectories: `guides/` for living docs, `decisions/` for ADRs, `runbooks/` for procedures.

---

## Document Types

### Guide (living document)

**Location:** `*/guides/<topic>.md` | **No date prefix**

```markdown
# <Title>

**Last Updated:** YYYY-MM-DD

## Overview
...

## [Sections as needed]
...
```

Update in place when information changes. Focus on current state, not history.

### Journal Entry

**Location:** `98-journals/YYYY-MM-DD-<description>.md` — **vault-resident.** Written after the related PR lands (past tense); may freely reference GitHub PRs, commits, and URLs. Carries OKF frontmatter per the vault's conventions doc. Committed in the vault, never here.

```markdown
# <Title>

**Date:** YYYY-MM-DD
**Context:** <Why this work was done>

## What Was Done
...

## Lessons Learned
...

## Next Steps
...
```

Never edited after creation. Records the journey and decision context.

### Plan

**Location:** `97-plans/YYYY-MM-DD-<description>.md` — **vault-resident**, OKF frontmatter, committed in the vault.

```markdown
# <Plan Title>

**Date Created:** YYYY-MM-DD
**Status:** Proposed | In Progress | Implemented
**Last Updated:** YYYY-MM-DD

## Objective
...

## Approach
...

## Success Criteria
...

## Progress Log
...
```

Plans stay in `97-plans/` throughout their lifecycle. Update status as work progresses.

### Architecture Decision Record (ADR)

**Location:** `*/decisions/YYYY-MM-DD-decision-NNN-<title>.md`

```markdown
# ADR-NNN: <Title>

**Date:** YYYY-MM-DD
**Status:** Accepted | Superseded by ADR-XXX | Deprecated

## Context
...

## Decision
...

## Consequences
...

## Alternatives Considered
...
```

Immutable once written. New decisions get new ADRs; never edit existing ones. Check `CLAUDE.md` for the current ADR count before numbering.

### Report

**Location:** `99-reports/` | Automated JSON (`intel-*.json`) or formal snapshots (`SYSTEM-STATE-YYYY-MM-DD.md`)

Machine-generated or rare authoritative snapshots. Do not create reports for content that belongs in journals.

### Supervisor Document (situational awareness)

**Location:** `96-project-supervisor/` | **Vault-resident (private, versioned)**

The directory is a gitignored symlink into the private vault — it aggregates operational
detail that doesn't belong in the public repo, and since 2026-07-13 it is version-controlled
there (no longer local-only). Work tracked only here still has no public trace — file GitHub
issues for anything that needs one.

Two document kinds live here:

- **Core documents (no date prefix, living):** `lessons.md` (distilled lessons with stable
  `L-NNN` IDs), `status.md` (arc state + standing caveats), `roadmap.md` (strategy,
  sequencing, horizon). Each defines its own update protocol in its header — follow it.
  Do not add new core documents casually; the directory's value is its small, stable
  surface. (A `registry.md` was considered and dropped — git history and the decisions
  directories already cover it.)
- **Handoffs (dated, transient):** `YYYY-MM-DD-<description>-handoff.md` — orientation
  for a future session on a bounded effort. A handoff is *done* when its definition-of-done
  is met; then remove its pointer from `status.md` "Waiting on" and delete or archive it
  (it is not history — journals are).

Lessons are never deleted: superseded ones move to the Superseded section of `lessons.md`
with a note naming what replaced them (mirrors ADR supersession). When a journal entry or
report yields a durable, generalizable lesson, promote it to `lessons.md` per its
"How to add a lesson" protocol. When an arc changes state, update `status.md`.

### Incident Post-Mortem

**Location:** `30-security/incidents/YYYY-MM-DD-incident-<description>.md`

```markdown
# Incident: <Title>

**Date:** YYYY-MM-DD
**Severity:** Critical | High | Medium | Low
**Status:** Resolved | Ongoing

## Summary
...

## Timeline
...

## Root Cause
...

## Resolution
...

## Prevention
...
```

---

## Naming Conventions

| Document Type | Date Prefix? | Location | Example |
|---|---|---|---|
| Guide | No | `*/guides/` | `jellyfin.md` |
| Journal | Yes | `98-journals/` (vault) | `2025-11-07-deployment-log.md` |
| Plan | Yes | `97-plans/` (vault) | `2025-11-22-disaster-recovery.md` |
| ADR | Yes | `*/decisions/` | `2026-07-14-ADR-043-title.md` |
| Report | N/A | `99-reports/` (vault) | `intel-*.json` |
| Supervisor doc (core) | No | `96-project-supervisor/` (vault) | `lessons.md` |
| Supervisor handoff | Yes | `96-project-supervisor/` (vault) | `2026-06-12-lessons-loose-threads-handoff.md` |
| Runbook (DR) | Yes | `20-operations/runbooks/` | `DR-001-system-ssd-failure.md` |
| Runbook (IR) | Yes | `30-security/runbooks/` | `IR-005-network-security-event.md` |
| Incident | Yes | `30-security/incidents/` (born in vault; publish = copy-and-scrub) | `2025-11-23-incident-data-loss.md` |

**Filename rules:** lowercase, hyphens (no underscores or spaces), `.md` extension, descriptive but concise.

---

## Writing Standards

**Tone:** Direct and practical. Write for someone solving a problem at 2 AM, not reading for pleasure. Lead with the answer, then explain why.

**Depth:** Include enough context to act without reading other docs. If a guide requires reading 3 other files first, it's not self-contained enough.

**Formatting:**
- Use headers to enable scanning -- someone should find their answer without reading the whole doc
- Prefer tables and lists over prose for structured information
- Code blocks must specify the language (`bash`, `yaml`, `markdown`)
- Keep lines under ~120 characters for terminal readability

**Cross-linking (three zones, ADR-043 D5):**
- **Public → public:** relative paths: `[SLO framework](40-monitoring-and-documentation/guides/slo-framework.md)`; ADRs by textual `ADR-NNN` reference
- **Public → vault: never as paths or links.** A PR body or ADR may mention a vault document by name only, when strictly necessary
- **Vault → public:** free — GitHub PRs, commit hashes, URLs, repo paths in prose (vault-internal linking rules live in the vault's conventions doc)
- Do not duplicate content across docs -- link instead

**Metadata (frontmatter):** Every public document carries YAML frontmatter: `type`, `title`, `description`, `sensitivity: public` (explicit), and dates. Until the backfill completes (plan WP-C), legacy docs may still carry only a title and `Last Updated` — new documents must not. Guides additionally keep `Last Updated` current.

---

## Archiving

**The archive location is always `docs/90-archive/`.** Do not create archive subdirectories inside other categories (no `98-journals/archive/`, no `10-services/archive/`, etc.). The single flat location is intentional — everything archived lives in one place, regardless of which category it came from.

Note: `90-archive/` is **vault-resident** (symlink). Archiving a *public* doc therefore crosses the boundary: `git rm` it here (a tracking change in this repo, committed via PR or trivia lane) and place the file in `90-archive/` (a vault commit). Archiving an already-private doc is a vault-only move. Reclassification generally (public → internal) is a *move*, not an edit — allowed for any document type, including otherwise-immutable ones.

### When to Archive

- **Superseded:** A newer document replaces it entirely
- **Obsolete:** Technology/service no longer in use
- **Consolidated:** Multiple docs merged into one
- **Session closure:** A postmortem, handoff, or session note whose follow-ups have been filed as issues and are being actioned — the journal's job is done, move it out of the active listing

### How to Archive

```bash
git mv docs/<category>/<file>.md docs/90-archive/
```

Add an archival header to the top of the moved file:

```markdown
> **ARCHIVED:** YYYY-MM-DD
> **Reason:** <Why archived>
> **Superseded by:** <Link to new doc if applicable>
```

Do not delete documentation -- archive it. The historical context has value. The archival header is the sole required metadata -- `90-archive/ARCHIVE-INDEX.md` is a legacy file and does not need updating.

---

## Auto-Generated Documents

The following files are regenerated by `scripts/auto-doc-orchestrator.sh` and should **never be manually edited**:

- `docs/AUTO-SERVICE-CATALOG.md` -- Service inventory and status
- `docs/AUTO-NETWORK-TOPOLOGY.md` -- Network diagrams and segmentation
- `docs/AUTO-DEPENDENCY-GRAPH.md` -- Service dependency tree
- `docs/AUTO-DOCUMENTATION-INDEX.md` -- Full documentation index

To update these, run the orchestrator script. Manual edits will be overwritten.

---

## Pre-Commit Checklist

Before committing documentation:

- [ ] File is in the correct directory for its type — and in the correct **home** (ADR-043 birth rule)
- [ ] Filename follows naming convention (date prefix where required)
- [ ] Frontmatter present: `type`, `title`, `description`, `sensitivity: public`, dates
- [ ] No sensitive information (secrets, passwords, API keys, internal IPs) — the pre-commit gate rejects `sensitivity: internal|secret` markdown, but the gate is a backstop, not the check
- [ ] Cross-links follow the three-zone policy (no paths/links into the vault)
- [ ] `CLAUDE.md` updated if architecture or process changed

---

## Quick Rules

1. **Don't document what the code already says** -- commit messages and config files are documentation too
2. **Guides are living, everything else is immutable** -- update guides in place, never edit journals/ADRs
3. **Archive, never delete** -- future context has value
4. **One source of truth** -- link, don't duplicate
5. **Date prefix = immutable** -- if the filename has a date, don't edit the content
6. **Check before creating** -- search for existing docs on the topic first
7. **Auto-docs are hands-off** -- never manually edit `AUTO-*.md` files
8. **When in doubt, journal it** -- a journal entry is always a safe choice for recording context (vault-side)
9. **Docs after the PR** -- write the record once the work is landed, in past tense
10. **Sensitivity is per-document and never guessed** -- classify explicitly; when unsure, it's `internal` until reviewed
