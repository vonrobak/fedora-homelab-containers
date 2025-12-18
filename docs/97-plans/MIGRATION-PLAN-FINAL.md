# Documentation Migration Plan - Final

**Date:** 2025-12-18
**Status:** Ready for execution
**Approach:** Comprehensive (Option B)
**Backup:** BTRFS snapshots + Git

---

## User Decisions Summary

| Question | Decision | Details |
|----------|----------|---------|
| Q1: Plans lifecycle | Hybrid B+C | Plans stay in 97-plans with status; implementation in 98-journals; manual archival only |
| Q2: Journal scale | Flat OK | No concerns about 100+ files |
| Q3: Deployment summaries | Option A | Move to 98-journals |
| Q4: Architecture docs | Living docs | Move existing dated docs to journals; future ones update in place |
| Q5: 99-reports purpose | Option B | Machine-generated + formal snapshots only |
| Q6: Session vs Strategic | **Needs discussion** | Leaning toward Option A |
| Q7: Doc reviews location | 98-journals | Chronological like other journals |
| Q8: Migration approach | Option B | Comprehensive migration |
| Q9: README scope | Option A | Full rewrite |
| Q10: Plan naming | Option C | Standard YYYY-MM-DD-description.md with status |

---

## Q6 Deep Dive: Session Logs vs Strategic Assessments

### The Question

Should strategic assessment documents be treated differently from tactical session logs?

**Type 1: Tactical session logs**
```
2025-11-12-session-summary.md
2025-11-14-session-3-completion-summary.md
2025-11-11-cli-work-session-summary.md
```
Content: "Today I deployed X, fixed Y, discovered Z"

**Type 2: Strategic assessments**
```
2025-11-09-strategic-assessment.md
2025-11-09-strategic-direction-next-week.md
2025-11-18-session-4-vs-5-honest-comparison.md
```
Content: "Here's where the project stands, here are the options, here's my thinking on direction"

### Option A: All go to 98-journals (User's preference)

**Pros:**
1. **Simplest mental model** - One clear rule: dated historical documents = journals
2. **Complete timeline** - Strategic thinking appears in chronological context
3. **No subjective boundaries** - Don't need to judge "strategic enough?"
4. **Natural flow** - Can read Nov 9 tactical work, then Nov 9 strategic reflection, then Nov 10 tactical work
5. **Easy decision making** - When writing docs, clear where they go
6. **Grep still works** - `grep -l "strategic" 98-journals/*.md` finds them

**Cons:**
1. **Strategic insights buried** - Harder to browse just strategic thinking
2. **Mixed purposes** - Tactical execution mixed with high-level reflection
3. **Can't filter easily** - Can't `ls 98-journals/strategic-*.md` to see strategy docs only

**Mitigations for cons:**
- Use consistent naming: `YYYY-MM-DD-strategic-assessment-*.md`
- Tag in frontmatter: Add `Type: Strategic Assessment` to file headers
- Create index: `docs/STRATEGIC-TIMELINE.md` linking to key assessments

### Option B: Strategic docs go to 97-plans

**Pros:**
1. **Discoverability** - All strategic thinking in one place
2. **Association** - Strategy lives with planning
3. **Thematic browsing** - Can review all strategic thinking together
4. **Clear curation** - 97-plans is the "thinking hub"

**Cons:**
1. **Boundary confusion** - Strategic assessments are retrospective (past), plans are prospective (future)
2. **Subjective classification** - Many docs mix tactical and strategic
3. **Broken timeline** - Nov 9 assessment in different directory than Nov 9 work
4. **Naming confusion** - Plans should be forward-looking; assessments review the past
5. **Harder to understand history** - "What was I thinking when I made that choice?" requires searching two directories

**Example problem with Option B:**
```
2025-11-09: Working on deployment
2025-11-09: Strategic assessment - "Should we pivot to approach X?"
2025-11-10: Decided to pursue approach X, here's how

Timeline in journals:
- 2025-11-09-deployment-work.md
- [assessment is in different directory]
- 2025-11-10-pivot-to-approach-x.md

Reader asks: "Why did they suddenly pivot?" → Must remember to check 97-plans
```

### Option C: Create separate directory (not originally proposed)

Could create `docs/96-strategic/` or similar.

**Pros:**
- Dedicated space for strategic thinking
- Clear separation from both journals and plans

**Cons:**
- Another directory = more complexity
- Still breaks chronological timeline
- Probably overengineering

### My Recommendation: Option A with Enhanced Discoverability

**Why Option A:**
1. **Strategic assessments are point-in-time snapshots** - They're "what I'm thinking NOW", not "what I plan to do LATER"
2. **Context matters** - Strategic thinking should appear in chronological context with the work that prompted it
3. **Simpler = better** - One clear rule is easier to maintain
4. **Search works** - Can always find strategic docs via grep/search
5. **Plans directory stays focused** - 97-plans is for forward-looking plans, not reflective assessments

**Enhanced discoverability strategies:**

1. **Consistent naming convention:**
   ```
   2025-MM-DD-strategic-assessment-<topic>.md
   2025-MM-DD-strategic-direction-<topic>.md
   2025-MM-DD-analysis-<topic>.md
   ```

2. **Metadata in files:**
   ```markdown
   # Strategic Assessment: Project Direction

   **Date:** 2025-11-09
   **Type:** Strategic Assessment
   **Keywords:** planning, architecture, decision

   ...
   ```

3. **Optional: Create strategic index** (living document):
   ```
   docs/STRATEGIC-INDEX.md

   # Strategic Thinking Timeline

   ## 2025-11
   - [2025-11-09 Strategic Assessment](98-journals/2025-11-09-strategic-assessment.md)
   - [2025-11-18 Session 4 vs 5 Comparison](98-journals/2025-11-18-session-4-vs-5-honest-comparison.md)

   ## 2025-10
   - ...
   ```

4. **Use grep aliases:**
   ```bash
   # Add to ~/.bashrc
   alias strategic-docs='grep -l "strategic\|Strategic Assessment" ~/containers/docs/98-journals/*.md'
   ```

**When strategic thinking connects to plans:**
- Strategic assessment in 98-journals can link to related plan: `See [DR Plan](../97-plans/2025-11-22-disaster-recovery-plan.md)`
- Plan can link back to assessment: `Based on [strategic assessment](../98-journals/2025-11-09-strategic-assessment.md)`

### User Decision Needed

Given this analysis, do you want to:
- **A1:** Proceed with Option A (all to journals) with enhanced discoverability
- **A2:** Proceed with Option A (all to journals) without extra indexing
- **B:** Switch to Option B (strategic to plans) despite the cons
- **C:** Consider a different approach

### My Vote
**Option A2** - All to journals, no extra indexing.

**Reasoning:**
- Keep it simple
- Strategic docs naturally have distinctive filenames
- Can add indexing later if discoverability becomes a problem
- Don't over-engineer for a problem we don't have yet

---

## Final Structure (Pending Q6 Decision)

```
docs/
├── 97-plans/                           # Strategic plans (forward-looking)
│   ├── 2025-11-22-disaster-recovery-plan.md
│   ├── 2025-11-28-autonomous-operations-plan.md
│   └── [Status: Proposed | In Progress | Implemented]
│
├── 98-journals/                        # Complete chronological history (FLAT)
│   ├── 2025-10-20-day01-foundation-learnings.md
│   ├── 2025-11-09-strategic-assessment.md     [if Q6 = Option A]
│   ├── 2025-11-12-session-summary.md
│   ├── 2025-11-14-vaultwarden-deployment-complete.md
│   └── [all chronological documentation]
│
├── 99-reports/                         # Machine-generated + formal snapshots
│   ├── intel-*.json                    (94 files - automated)
│   ├── resource-forecast-*.json        (7 files - automated)
│   ├── SYSTEM-STATE-2025-11-06.md      (formal snapshots only)
│   └── [no session logs, no strategic docs]
│
├── 00-foundation/
│   ├── guides/                         # Living reference docs
│   └── decisions/                      # ADRs
│
├── [10, 20, 30, 40]-*/
│   ├── guides/                         # Living reference docs
│   ├── decisions/                      # ADRs
│   └── [runbooks/]                     # Where applicable
│
└── 90-archive/                         # Manually archived docs
```

---

## Next Steps

1. **User decides Q6** - Session vs strategic document placement
2. **Create BTRFS snapshot** - Pre-migration safety
3. **Execute migration** - Comprehensive, all phases
4. **Update documentation** - Full README.md rewrite
5. **Validate** - Test navigation, check links
6. **Commit** - Push to GitHub

Awaiting your decision on Q6 to finalize the plan.
