# Documentation Structure Discussion

**Date:** 2025-12-18
**Context:** Quarterly review refinement before implementation
**Related:** See `QUARTERLY-REVIEW-2025-Q4.md` for full analysis

---

## User Decisions & Clarifications

### ✅ Confirmed Decisions

1. **98-journals will be FLAT (no subdirectories)**
   - All journals in single directory
   - Sorted by YYYY-MM-DD prefix
   - Simpler than month-based hierarchy

2. **97-plans directory for planning documents**
   - Strategic plans, roadmaps, proposals
   - Forward-looking (vs journals = historical)

### ❓ Open Questions for Discussion

Let's work through these together:

---

## Question 1: 97-plans Content & Lifecycle

**What goes in 97-plans?**

Candidates from 99-reports:
```
PLAN-1-AUTO-UPDATE-SAFETY-NET.md
PLAN-2-PROACTIVE-AUTO-REMEDIATION.md
PROJECT-A-DISASTER-RECOVERY-PLAN.md
PROJECT-A-IMPLEMENTATION-ROADMAP.md
PROJECT-B-SECURITY-HARDENING.md
PROJECT-C-AUTO-DOCUMENTATION.md
SESSION-5-MULTI-SERVICE-ORCHESTRATION-PLAN.md
SESSION-5B-PREDICTIVE-ANALYTICS-PLAN.md
SESSION-5C-NATURAL-LANGUAGE-QUERIES-PLAN.md
SESSION-5D-SKILL-RECOMMENDATION-ENGINE-PLAN.md
SESSION-5E-BACKUP-INTEGRATION-PLAN.md
SESSION-6-AUTONOMOUS-OPERATIONS-PLAN.md
STANDALONE-PROJECTS-INDEX.md
```

**Lifecycle question:** When plans are implemented, what happens?

**Option A: Archive implemented plans**
- Move to 90-archive with "Implemented YYYY-MM-DD" header
- 97-plans contains only active/future plans
- Pro: Clean separation, clear "what's next"
- Con: Lose historical context of planning

**Option B: Keep implemented plans in 97-plans**
- Add status metadata: "Status: Implemented | In Progress | Proposed"
- 97-plans becomes permanent planning archive
- Pro: See full planning evolution
- Con: Mixes active and historical

**Option C: Move to 98-journals when work completes**
- Plan created → 97-plans
- Work completed → Add journal entry to 98-journals
- Plan archived → 90-archive
- Pro: Journals show what happened, plans show what's next
- Con: Plan and execution story split across directories

**Your preference?**

---

## Question 2: Journal Directory Scale

**Concern:** 98-journals could grow to 100+ files

Current: 36 journals
Growth rate: ~5-10 per month (estimated)
In 1 year: ~100-150 files in single directory

**Is flat structure sustainable long-term?**

**Option A: Keep flat indefinitely**
- Pro: Simple, consistent
- Pro: File managers handle hundreds of files fine
- Pro: `ls 98-journals/2025-11-*.md` still works for filtering
- Con: Visual clutter in file browsers

**Option B: Plan to subdivide later**
- Start flat now
- Add YYYY/ subdirs when directory hits ~100 files
- Pro: Solves problem when it becomes a problem
- Con: Migration work later

**Option C: Use YYYY/ subdirs from start**
- docs/98-journals/2025/*.md
- Pro: Scales naturally
- Pro: Year-based browsing
- Con: Extra hierarchy
- Con: Need to specify year to browse

**Option D: Use YYYY-MM/ subdirs (original proposal)**
- docs/98-journals/2025-10/*.md
- Pro: Best granularity for browsing
- Con: You already rejected this

**Your preference?** (You said flat, but want to confirm given scale concerns)

---

## Question 3: Deployment Summaries - Journal or Report?

**These files are borderline:**
```
20251106-monitoring-stack-deployment-summary.md
20251107-backup-implementation-summary.md
20251107-btrfs-backup-automation-report.md
2025-11-12-vaultwarden-deployment-complete.md
2025-11-12-crowdsec-security-enhancements.md
```

**They contain:**
- What was deployed (report-like)
- How it was done (journal-like)
- Final configuration (reference-like)

**Option A: Move to 98-journals**
- Treat as chronological work logs
- Pro: Complete historical timeline
- Con: Lose "authoritative deployment reference" concept

**Option B: Keep in 99-reports**
- Treat as reference documentation
- Pro: Go-to place for "how is X deployed?"
- Con: Not really "system state snapshots"

**Option C: Extract to service guides**
- Update `10-services/guides/<service>.md` with deployment details
- Move chronological log to 98-journals
- Archive the deployment summary
- Pro: Living documentation in guides
- Con: Most work

**Option D: Keep some, move others**
- Keep major service deployments in 99-reports as reference
- Move routine/session-based deployments to 98-journals
- Pro: Pragmatic
- Con: Subjective boundary

**Your preference?**

---

## Question 4: Report Naming - ARCH-* Pattern

**Proposal:** Architecture snapshots use `ARCH-<subsystem>-YYYY-MM-DD.md`

**Example:**
```
20251025-storage-architecture-authoritative-rev2.md
  → ARCH-storage-2025-10-25-rev2.md
```

**Questions:**

1. **Should architecture docs go in 99-reports at all?**
   - Alternative: Put in `20-operations/guides/` and update in place
   - Snapshots capture point-in-time, but maybe storage architecture should be living doc?

2. **ARCH- prefix vs SYSTEM-STATE-* pattern?**
   - `ARCH-storage-2025-10-25.md`
   - `SYSTEM-STATE-storage-2025-10-25.md`
   - Something else?

3. **What qualifies as an architecture snapshot?**
   - Storage layout
   - Network topology
   - Service dependencies
   - All of the above?

**Your thoughts?**

---

## Question 5: Session vs Strategic Docs

**Currently mixing two types in 99-reports:**

**Type 1: Session work logs**
```
2025-11-12-session-summary.md
2025-11-14-session-3-completion-summary.md
2025-11-11-cli-work-session-summary.md
```
- What happened in a work session
- Clearly journals (chronological logs)

**Type 2: Strategic assessments**
```
2025-11-09-strategic-assessment.md
2025-11-09-strategic-direction-next-week.md
2025-11-18-session-4-vs-5-honest-comparison.md
```
- Reflections, analysis, planning thinking
- More strategic than tactical

**Should these be treated differently?**

**Option A: All go to 98-journals**
- Both are chronological documents
- Distinction doesn't matter for organization

**Option B: Strategic docs go to 97-plans**
- Strategic thinking lives with plans
- Session logs go to journals
- Pro: Clearer purpose
- Con: Harder boundary to define

**Your preference?**

---

## Question 6: 99-reports Final Purpose

**After reorganization, what IS 99-reports?**

**Option A: Machine-generated reports ONLY**
- All JSON files
- No markdown at all
- Clearest definition
- Markdown reports go elsewhere based on type

**Option B: Machine + formal snapshots**
- JSON reports
- SYSTEM-STATE-* formal snapshots
- ARCH-* architecture snapshots
- Basically: system state only, no logs

**Option C: System intelligence hub**
- JSON reports
- Deployment reference docs
- System state snapshots
- Basically: reference material, not logs

**Your preference?**

---

## Question 7: Documentation Review Metadata

**Some reports have metadata:**
```
DOCUMENTATION-REVIEW-2025-11-07.md
QUARTERLY-REVIEW-2025-Q4.md (this review)
```

**Where should documentation reviews live?**

**Option A: 40-monitoring-and-documentation/journal/**
- They're about documentation, go in that category
- But you're removing journal/ subdirs...

**Option B: 98-journals**
- Chronological, like other journals

**Option C: 99-reports**
- Meta-documentation, stays in reports

**Option D: docs/ root**
- Special status, live at top level
- QUARTERLY-REVIEW-*.md as root-level files

**Your preference?**

---

## Question 8: Migration Approach

**How aggressive should the reorganization be?**

**Option A: Conservative (recommended)**
- Phase 1: Move journals to 98-journals
- Phase 2: Create 97-plans, move obvious plans
- Stop and validate
- Phase 3: Tackle 99-reports reorganization later
- Pro: Low risk, iterative
- Con: Multiple migration phases

**Option B: Comprehensive**
- Do everything in one migration
- Journals → 98-journals
- Plans → 97-plans
- Reports → reorganized 99-reports
- Pro: One-time disruption
- Con: Higher risk, harder to rollback

**Option C: Minimal**
- Only do journals → 98-journals
- Leave everything else as-is for now
- Tackle plans/reports in future quarters
- Pro: Minimal risk
- Con: Doesn't fully solve problems

**Your preference?**

---

## Question 9: README.md Rewrite Scope

**docs/README.md is dated 2025-11-10 and quite detailed**

After structure changes, should we:

**Option A: Full rewrite**
- Reflect new structure completely
- Update all examples and paths
- Clean up outdated "Recent Achievements" section
- Pro: Fresh, accurate
- Con: Significant work

**Option B: Targeted updates**
- Update structure section only
- Leave rest as-is
- Pro: Less work
- Con: May have inconsistencies

**Option C: Incremental updates**
- Update structure now
- Update other sections over time
- Pro: Pragmatic
- Con: Temporary inconsistency

**Your preference?**

---

## Question 10: Naming Convention for Plans

**Should plans follow YYYY-MM-DD prefix?**

**Current (in 99-reports):**
```
PROJECT-A-DISASTER-RECOVERY-PLAN.md
SESSION-5B-PREDICTIVE-ANALYTICS-PLAN.md
PLAN-1-AUTO-UPDATE-SAFETY-NET.md
```

**Option A: Keep current naming**
- UPPERCASE-DESCRIPTIVE-NAME.md
- No date prefix (plans are timeless until implemented)
- Pro: Clearly distinguishes plans from journals
- Con: Inconsistent with overall naming convention

**Option B: Add date prefix, keep uppercase**
- 2025-11-22-PROJECT-A-DISASTER-RECOVERY-PLAN.md
- Pro: Sorts chronologically, clear it's a plan
- Con: Long filenames

**Option C: Standard date + lowercase**
- 2025-11-22-disaster-recovery-plan.md
- Pro: Consistent with all other naming
- Con: Loses visual distinction from journals

**Option D: Date + PLAN- prefix**
- 2025-11-22-PLAN-disaster-recovery.md
- Pro: Clear type, chronological sort
- Con: Redundant (directory already says "plans")

**Your preference?**

---

## Proposed Structure (Based on Your Input)

```
docs/
├── 97-plans/                           # Strategic plans and roadmaps
│   ├── [naming convention TBD]
│   └── [lifecycle management TBD]
│
├── 98-journals/                        # Chronological project history (FLAT)
│   ├── 2025-10-20-day01-foundation-learnings.md
│   ├── 2025-10-21-day02-networking-exploration.md
│   ├── ...
│   └── [all 36+ journals, no subdirs]
│
├── 99-reports/                         # [purpose TBD - see Question 6]
│   ├── intel-*.json                    # Automated system health (94 files)
│   ├── resource-forecast-*.json        # Predictive analytics (7 files)
│   └── [markdown reports TBD]
│
├── 00-foundation/
│   ├── guides/                         # Living reference docs
│   └── decisions/                      # ADRs
│   # (no more journal/ subdir)
│
├── [10, 20, 30, 40]-*/
│   ├── guides/
│   └── decisions/
│   # (no more journal/ subdirs)
│
└── 90-archive/                         # Superseded documentation
```

---

## Let's Discuss

Please share your thoughts on:
1. Which options appeal to you for each question?
2. Any concerns I haven't addressed?
3. Are there other alternatives you'd like to explore?
4. What's your priority order? (e.g., "solve journals first, tackle reports later")

I can then refine the migration plan based on your preferences.

---

## My Initial Recommendations (for discussion)

Based on your feedback so far:

**Q1 (Plans lifecycle):** Option A - Archive when implemented
- Keeps 97-plans focused on active planning

**Q2 (Journal scale):** Option A - Keep flat
- 100-150 files is manageable, can subdivide later if needed

**Q3 (Deployment summaries):** Option C - Extract to guides
- Most aligned with "living documentation" philosophy
- But most work, so maybe Phase 2

**Q4 (ARCH naming):** Consider if architecture should be snapshots or living docs
- Maybe storage-layout.md in 20-operations/guides/, updated in place?

**Q5 (Session vs strategic):** Option A - All to 98-journals
- Simpler boundary, both are historical

**Q6 (99-reports purpose):** Option B - Machine + formal snapshots
- Clear definition, useful distinction

**Q7 (Doc reviews):** Option D - docs/ root
- Special status, easy to find

**Q8 (Migration approach):** Option A - Conservative
- Lower risk, validates each phase

**Q9 (README scope):** Option B - Targeted updates
- Update structure, iterate on the rest

**Q10 (Plan naming):** Option C - Standard date + lowercase
- Consistency over visual distinction
- Directory name already indicates purpose

But I want YOUR input before proceeding!
