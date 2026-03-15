# CONTRIBUTING.md Rewrite and Documentation Quality Strategy

**Date:** 2026-03-15
**Context:** CONTRIBUTING.md had grown to 500 lines and was flagged in the Feb 5 documentation audit as a "headline file" needing refresh. Rewrote it to 280 lines with a decision tree structure, then evaluated documentation growth trends and proposed strategies for sustained quality.

## What Was Done

Rewrote `docs/CONTRIBUTING.md` from 500 to 282 lines (44% reduction):

- **Decision tree** — "Should you document?" flow replaces verbose explanations with a three-step decision process (Is it needed? → What type? → Where does it go?)
- **Document type templates** — consolidated from scattered examples into one section with minimal, copy-paste-ready templates for each type
- **Writing standards** — extracted from prose into scannable rules (tone, depth, formatting, cross-linking, metadata)
- **Naming conventions table** — all document types with location, date prefix rules, and examples in one table (added DR/IR runbook entries during self-review)
- **Quick rules** — 8 rules distilled from the full guide, placed at the end for reference

Removed:
- Redundant explanations that restated CLAUDE.md content
- Over-detailed archiving procedures (reduced to the essential `git mv` + header)
- Verbose introductions and transitions

## Self-Review Findings

Three items checked during review:

1. **Runbook naming missing** — DR-NNN and IR-NNN runbooks exist in `20-operations/runbooks/` and `30-security/runbooks/` but weren't in the naming conventions table. Fixed: added two rows.
2. **Incident post-mortem path** — Already correctly references `30-security/incidents/`. No fix needed.
3. **Cross-link example path** — `40-monitoring-and-documentation/guides/slo-framework.md` is correct relative to `docs/`. No fix needed.

## Evaluation Against Feb 5 Audit

The [Feb 5 documentation accuracy audit](2026-02-05-documentation-accuracy-audit-and-strategic-assessment.md) provided baseline measurements and a warning about documentation scale. Five weeks later, here's where things stand:

| Metric | Feb 5 baseline | Mar 15 current | Delta |
|--------|---------------|----------------|-------|
| Total docs | 373 | 408 | +35 (+9.4%) |
| Journal entries | 156 | 181 | +25 |
| Guides | ~65 | 69 | +4 |
| ADRs | 18 | 19 | +1 |
| Archived files | ~58 | 62 | +4 |
| CLAUDE.md lines | ~230 | 185 | -45 |
| CONTRIBUTING.md lines | ~500 | 282 | -218 |

**Growth rate:** ~7 docs/week over 5 weeks, overwhelmingly journals (25 of 35 new files). Guides and ADRs growing slowly, which is healthy — it means existing guides are being updated in place rather than spawning new ones.

**The Feb 5 warning was prescient:** "The documentation volume (373 files) is approaching the point where navigation becomes harder than searching." At 408 files, this is more relevant than ever. The 4 AUTO-*.md files (regenerated daily) help, but they're indexes — they don't solve the question of whether any given guide is still accurate.

**What's working:**
- CLAUDE.md and CONTRIBUTING.md are now tight, current, and complementary (185 + 282 = 467 lines total for governance)
- Archiving is happening (62 files moved out of active docs)
- Journal-heavy growth preserves institutional memory without polluting the guide layer

**What's not addressed:**
- No mechanism detects when a guide becomes stale (e.g., references a config that's since changed)
- Documentation volume will keep growing — journals alone add ~5/week
- Context window pressure: a Claude Code session that loads CLAUDE.md + CONTRIBUTING.md + AUTO-*.md consumes significant tokens before any work begins

## Three Alternatives for Sustained Documentation Quality

### Alternative A: Automated Documentation Decay Detection

Extend `auto-doc-orchestrator.sh` with a staleness checker that cross-references each guide's `Last Updated` date against git history of files it references. If a guide references `config/traefik/dynamic/routers.yml` and that file changed after the guide's last update, flag it.

**Mechanism:** Parse guide cross-links and config paths → check git log for those paths → compare timestamps → generate a `STALE-DOCS-REPORT.md` or add a staleness column to `AUTO-DOCUMENTATION-INDEX.md`.

**Trade-offs:** Catches real drift (a guide says "3 networks" when there are now 8). False positives likely — not every config change invalidates a guide. Would need a threshold (e.g., flag if referenced file changed 3+ times since guide was last touched).

**Effort:** Medium. The orchestrator already parses doc metadata; adding git log cross-referencing is incremental.

### Alternative B: Context-Window-Aware Documentation Tiers

Assign explicit token budgets to files consumed by Claude Code sessions. Currently, CLAUDE.md is always loaded (~185 lines). CONTRIBUTING.md, AUTO-*.md, and memory files also compete for context. As docs grow, more context is consumed before any task-specific code is read.

**Mechanism:** Define three tiers:
- **Tier 1 (always loaded):** CLAUDE.md, MEMORY.md — strict line limits enforced
- **Tier 2 (loaded on demand):** CONTRIBUTING.md, AUTO-*.md — loaded only when documentation or architecture tasks are active
- **Tier 3 (agent-loaded):** Individual guides, journals, ADRs — fetched by subagents, never bulk-loaded

The practical change: ensure Tier 1 files stay under ~200 lines each. Review Tier 2 files quarterly for bloat. Structure Tier 3 files so their first 10 lines contain enough metadata for an agent to decide relevance without reading the full file.

**Trade-offs:** Reduces context pollution. Requires discipline — every "just add one more line to CLAUDE.md" erodes the budget. The tier model itself needs to be documented (meta-documentation problem).

**Effort:** Low to implement the discipline; medium to build tooling that enforces limits.

### Alternative C: Annual Consolidation Protocol

Once per year (suggest January, alongside the State of Homelab snapshot), perform a systematic documentation consolidation:

1. **Journal indexing:** Group the year's journals by theme (security, deployment, monitoring, etc.) and create a yearly journal index (e.g., `98-journals/2025-journal-index.md`). This makes 180+ journals navigable without scrolling.
2. **Guide merging:** Identify guides covering overlapping topics and merge them. Example: if three separate guides cover CrowdSec (field manual phases 1-4, CrowdSec ADR, CrowdSec config reference), evaluate whether they should be one guide.
3. **Archive sweep:** Move guides for decommissioned services, superseded plans, and completed one-off procedures to `90-archive/`.
4. **Metric tracking:** Record total file counts, lines, and growth rate in the State of Homelab entry to establish year-over-year trends.

**Trade-offs:** Low-frequency means drift accumulates between consolidations. But annual cadence matches the State of Homelab snapshot rhythm and avoids documentation-about-documentation overhead. The risk is that it becomes a large, unpleasant task if deferred.

**Effort:** Medium per occurrence (half-day annually). No tooling required — just discipline and a checklist.

## Next Steps

No immediate action required on the three alternatives — they're proposals for future consideration. The CONTRIBUTING.md rewrite is ready for commit alongside the other governance file optimizations on the current branch.
