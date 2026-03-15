# Documentation Standards

**Primary consumer:** Claude Code sessions | **For deployment/architecture:** see `CLAUDE.md`

This guide covers when, where, and how to write documentation. It does not repeat deployment procedures or architecture details from `CLAUDE.md`.

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

| Domain | Directory |
|---|---|
| Core design patterns, philosophy | `00-foundation/` |
| Service-specific (Jellyfin, Immich, etc.) | `10-services/` |
| Operational procedures, DR runbooks | `20-operations/` |
| Security, incident response | `30-security/` |
| Monitoring, SLOs, documentation meta | `40-monitoring-and-documentation/` |
| Strategic plans, roadmaps | `97-plans/` |
| Chronological logs, session notes | `98-journals/` |
| Automated reports (JSON, snapshots) | `99-reports/` |
| Superseded documentation | `90-archive/` |

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

**Location:** `98-journals/YYYY-MM-DD-<description>.md`

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

**Location:** `97-plans/YYYY-MM-DD-<description>.md`

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
| Journal | Yes | `98-journals/` | `2025-11-07-deployment-log.md` |
| Plan | Yes | `97-plans/` | `2025-11-22-disaster-recovery.md` |
| ADR | Yes | `*/decisions/` | `2025-11-07-decision-001-title.md` |
| Report | N/A | `99-reports/` | `intel-*.json` |
| Runbook (DR) | Yes | `20-operations/runbooks/` | `DR-001-system-ssd-failure.md` |
| Runbook (IR) | Yes | `30-security/runbooks/` | `IR-005-network-security-event.md` |
| Incident | Yes | `30-security/incidents/` | `2025-11-23-incident-data-loss.md` |

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

**Cross-linking:**
- Link to related docs using relative paths: `[SLO framework](40-monitoring-and-documentation/guides/slo-framework.md)`
- When referencing an ADR, use the format: `ADR-NNN` (readers can find it via `docs/*/decisions/`)
- Do not duplicate content across docs -- link instead

**Metadata:** Every document needs at minimum a title (`# ...`) and a date (either in the filename or a `Last Updated` field). Guides must have `Last Updated`.

---

## Archiving

### When to Archive

- **Superseded:** A newer document replaces it entirely
- **Obsolete:** Technology/service no longer in use
- **Consolidated:** Multiple docs merged into one

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

Do not delete documentation -- archive it. The historical context has value.

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

- [ ] File is in the correct directory for its type
- [ ] Filename follows naming convention (date prefix where required)
- [ ] Required metadata is present (title, date, status for ADRs/plans)
- [ ] No sensitive information (secrets, passwords, API keys, internal IPs)
- [ ] Cross-links use relative paths and point to existing files
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
8. **When in doubt, journal it** -- a journal entry is always a safe choice for recording context
