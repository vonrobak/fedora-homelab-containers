# Project Supervisor Directory: Lessons Synthesis, Orientation Docs, and Loose-Threads Audit

**Date:** 2026-06-12
**Context:** Eight months of journals and reports held the project's hard-won lessons in
scattered, effectively unfindable form. This session established `docs/96-project-supervisor/`
as a situational-awareness home for both human operators and LLM sessions, synthesized its
first documents, and then audited the lessons against actual system state.

## What Was Done

### 1. lessons.md synthesis (PR #278)

Mined all prose journals (232 entries, Oct 2025 – Jun 2026) and prose reports (~30
postmortems, forensic reviews, audits) via parallel extraction agents, then curated ~70
candidates into **73 lessons** with stable `L-NNN` IDs across 7 categories (container/quadlet
ops, storage & backup, security architecture, monitoring & alerting, debugging & forensics,
architecture & design process, process & collaboration). Design decisions:

- **Superseded lessons stay in the file** (4 at synthesis: the ADR-015 auto-update model,
  the shell-script backup era, log-presence alerting, static thresholds) — negative
  knowledge prevents re-recommending retired approaches; mirrors ADR supersession.
- **Compact structured entries** — one-sentence lesson, 2–4 lines of evidence, source
  links, date, status; an Index section gives a one-line-per-lesson scan surface.
- **Self-documenting capture protocol** in the header; CLAUDE.md gained a capture rule so
  future sessions both consult and feed the file.

Verification: every source link resolved, Index count matched entries, factual spot-checks
passed against source documents.

### 2. status.md and roadmap.md

Adapted the Urd repo's supervisor-doc pattern to the homelab's different context:

- **status.md** — deliberately thin: live state is machine-owned (AUTO docs, intel
  scripts) and tasks live in GitHub issues, so the file holds only what nothing else owns —
  *arc state* and *standing operational caveats*. Update trigger: arc-state change, not
  per session. (During drafting, session memory claimed ADR-029 Phase B was still pending;
  it had executed 2026-06-09 — exactly the staleness the repo-visible file fixes.)
- **roadmap.md** — completed arcs compressed to six paragraphs, four active arcs with
  goal/state/gate, a horizon section, and four sequencing principles derived from lessons
  (reversible-first, redundancy-before-monitoring, validation-beats-features,
  usage-proves-need).
- **registry.md considered and dropped** — git history, ADR directories, and dated
  journals already provide the work-item → artifact mapping.

### 3. Directory made local-only (PR #279)

Decision: the supervisor docs aggregate operational detail that doesn't belong in a public
repo. Following the existing `*-private.md` convention, `docs/96-project-supervisor/` is
now gitignored; the two briefly-public files were untracked (history not rewritten —
accepted); the doc-index generator skips the directory so the public
AUTO-DOCUMENTATION-INDEX carries no dead links; references in CLAUDE.md / CONTRIBUTING.md /
docs/README.md are kept but annotated local-only.

**Incident during the migration:** `git rm --cached` on the feature branch did not protect
the files through the merge — pulling the squashed deletion onto local main (where they
were still tracked) deleted them from the working tree, including uncommitted edits. Both
files were recovered (git history + session context). Recorded as **L-074** per the
capture protocol — the directory's first post-synthesis lesson, fittingly about protecting
the directory.

### 4. Loose-threads audit

Verified every implementation-bearing lesson against actual configs, scripts, alert rules,
and quadlets. Headline: **the major incident loops closed properly** — Pi-hole watchdog
stack, restore-test hardening (all 6 fixes + monthly/weekly timers), Vaultwarden rate-limit
router split, remediation webhook auth + failure escalation, gated backup alerts, and SLO
burn-rate coverage (further along than even the fresh status.md claimed; corrected). The
remaining gaps — a handful of unbuilt alerts, two silent-erosion risks (boot-tier
assignment, dump-coverage discovery), and several process closures — were written up as
10 prioritized work packages in a **handoff document** in the supervisor directory
(local-only), pointed to from status.md "Waiting on". Public traces for unimplemented
items will be GitHub issues, per the new convention.

### 5. Documentation system integration

- CONTRIBUTING.md: placement-table row, "Supervisor Document" type section (later revised
  to distinguish core documents from dated transient handoffs and their lifecycle),
  naming-convention rows.
- docs/README.md: fourth organizational tier ("Synthesis"), marked local-only.
- CLAUDE.md: Quick Reference row + lesson capture rule.
- `generate-doc-index.sh`: explicitly skips the gitignored directory (both the category
  section and "Recently Updated").

## Lessons Learned

- **L-074** (recorded in lessons.md): `git rm --cached` does not protect files through a
  merge round-trip — copy gitignore-migrating files outside the repo first.
- **Session memory is a cache, not a source of truth.** Two stale-memory hits in one
  session (ADR-029 phase state, SLO coverage state) — both caught only by verifying
  against the repo. The supervisor docs exist precisely to make this state repo-visible
  and correctable.
- **Synthesis exposes convergence.** Three separate incidents (cAdvisor OOM, scrape-timeout
  false outage, zram threshold noise) turned out to be one meta-lesson — "defaults encode
  someone else's context" (L-064) — visible only when the corpus was read together.
- **An audit right after synthesis is the cheapest one.** With all 73 lessons fresh in
  context, checking them against system state took one fan-out; the same audit cold would
  cost a full session of re-reading.

## Artifacts

| Artifact | Location | Visibility |
|----------|----------|------------|
| lessons.md (74 lessons incl. L-074) | `docs/96-project-supervisor/` | local-only |
| status.md, roadmap.md, README.md | `docs/96-project-supervisor/` | local-only |
| Loose-threads handoff (10 work packages) | `docs/96-project-supervisor/2026-06-12-lessons-loose-threads-handoff.md` | local-only |
| PR #278 (synthesis; superseded by gitignore) | merged `15fbeb9` | public |
| PR #279 (gitignore + index cleanup) | merged `c954ff4` | public |
| CONTRIBUTING/README/CLAUDE.md integration | repo | public |
