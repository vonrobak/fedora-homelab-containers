# Context & Remediation Framework Analysis

**Date:** 2025-11-30
**Purpose:** Evaluate utilization of context and remediation systems with current capabilities

---

## Executive Summary

The Context and Remediation frameworks (Session 4) have evolved significantly with Sessions 5 and 6. However, documentation is **outdated** and the systems are **only partially integrated** with new capabilities.

**Key Findings:**
- ✅ **Context framework is actively used** by autonomous operations and query system
- ⚠️ **Two separate context directories** causing confusion (~/containers/.claude/context vs ~/.claude/context)
- ⚠️ **Remediation playbooks exist but underutilized** - autonomous operations could use them more
- ❌ **Documentation doesn't reflect Sessions 5C, 5D, 6 additions**
- ⚠️ **Session 5D (skill recommendations) partially implemented** but not documented

---

## Context Framework Status

### Local Context (~/containers/.claude/context/)

**Session 4 Files (Documented in README):**
- ✅ `system-profile.json` - System inventory (last updated 2025-11-22)
- ✅ `issue-history.json` - 12 tracked issues (last updated 2025-11-22)
- ✅ `deployment-log.json` - 20 service deployments (last updated 2025-11-22)
- ✅ `preferences.yml` - User preferences and risk tolerance

**Session 6 Additions (NOT in README):**
- ✅ `autonomous-state.json` - Autonomous operations state tracking
- ✅ `decision-log.json` - Audit trail of autonomous decisions
- ✅ `scripts/query-decisions.sh` - Decision history query tool

### Global Context (~/.claude/context/)

**Session 5C - Natural Language Queries:**
- ✅ `query-cache.json` (12KB) - Pre-computed query results
- ✅ `query-patterns.json` (6.5KB) - Pattern matching database

**Session 5D - Skill Recommendations (Partial):**
- ✅ `task-skill-map.json` (7.2KB) - Task → Skill mapping **[IMPLEMENTED!]**
- ✅ `skill-usage.json` (1.7KB) - Usage tracking **[IMPLEMENTED!]**

**Session 5B - Predictive Analytics:**
- ✅ `~/containers/data/predictions.json` - Resource exhaustion forecasts

---

## Integration Analysis

### What's Working Well

**1. Autonomous Operations ← Context Framework**
```bash
# autonomous-check.sh uses:
- preferences.yml (risk tolerance, service overrides)
- query-cache.json (fast OBSERVE phase)
- autonomous-state.json (circuit breaker, statistics)
- decision-log.json (audit trail)
```
**Status:** ✅ Fully integrated

**2. Natural Language Queries ← Context**
```bash
# query-homelab.sh uses:
- query-patterns.json (pattern matching)
- query-cache.json (cached results)
# precompute-queries.sh populates cache every 5 minutes
```
**Status:** ✅ Fully integrated

**3. Skill Recommendations ← Context**
```bash
# recommend-skill.sh uses:
- task-skill-map.json (8 categories → 6 skills)
- skill-usage.json (usage analytics)
```
**Status:** ✅ Implemented but NOT documented in Session 4 README

### What's Missing

**1. Remediation Framework ← Autonomous Operations**

**Current State:**
- Remediation playbooks exist: disk-cleanup, service-restart, drift-reconciliation, resource-pressure
- Autonomous operations has its own action execution (in autonomous-execute.sh)
- **NOT using remediation playbooks!**

**Gap:**
```bash
# Autonomous operations should call:
~/containers/.claude/remediation/scripts/apply-remediation.sh --playbook disk-cleanup

# Instead it has inline implementations
# This creates code duplication and maintenance burden
```

**Impact:** Remediation playbooks are **underutilized** - they work standalone but aren't integrated into autonomous loop.

**2. Context Updates Are Manual**

**Current Process:**
- system-profile.json: Regenerate manually via `generate-system-profile.sh`
- issue-history.json: Manually add issues to populate script
- deployment-log.json: Manually add deployments to build script

**Missing:**
- No automated updates after deployments
- No automated issue tracking from autonomous operations
- deployment-log hasn't been updated since 2025-11-22 (missing recent work!)

**3. Issue History Not Learning from Autonomous Operations**

**Should happen:**
```
Autonomous op detects issue → Executes fix → Logs to issue-history.json
Next time: "Last time (ISS-013), disk-cleanup freed 8GB. Running same fix."
```

**Currently:**
- Autonomous operations logs to decision-log.json
- Issue history is manually curated
- **No automatic learning loop**

---

## Documentation Gaps

### Context README (~/containers/.claude/context/README.md)

**Missing:**
1. autonomous-state.json schema and usage
2. decision-log.json schema and usage
3. query-decisions.sh script documentation
4. Reference to global ~/.claude/context directory
5. Integration with Sessions 5C, 5D, 6
6. Updated statistics (still showing 2025-11-18 data)

### Remediation README (~/containers/.claude/remediation/README.md)

**Missing:**
1. Integration status with autonomous operations
2. Updated implementation status (still shows "Session 4B in progress")
3. drift-reconciliation and resource-pressure implementation status
4. Reference to autonomous operations using remediation patterns
5. Updated statistics

---

## Utilization Assessment

### Context Framework: 75% Utilized

**What's Used:**
- ✅ preferences.yml - Used by autonomous operations
- ✅ autonomous-state.json - Active state tracking
- ✅ decision-log.json - Audit trail maintained
- ✅ Query scripts - Used by autonomous and manual operations

**What's Underutilized:**
- ⚠️ system-profile.json - Not auto-updated, stale data
- ⚠️ issue-history.json - Manual curation, not learning from autonomous ops
- ⚠️ deployment-log.json - Not updated after recent deployments
- ⚠️ Context-aware recommendations - Not exposed to user in homelab-intelligence skill

### Remediation Framework: 40% Utilized

**What's Used:**
- ✅ disk-cleanup playbook - Can be run manually
- ✅ service-restart playbook - Can be run manually
- ✅ apply-remediation.sh - Works for implemented playbooks

**What's Underutilized:**
- ❌ Autonomous operations doesn't call remediation playbooks (reimplements logic)
- ❌ drift-reconciliation playbook not implemented in execution engine
- ❌ resource-pressure playbook not implemented in execution engine
- ❌ No automated triggers (should run on alerts, health checks)
- ❌ No remediation history analytics

---

## Recommendations

### Priority 1: Update Documentation (1 hour)

**Context README:**
1. Add autonomous-state.json, decision-log.json
2. Clarify two context directories (local vs global)
3. Document Session 5C, 5D, 6 integrations
4. Update statistics to 2025-11-30

**Remediation README:**
1. Update implementation status (mark Session 4B complete)
2. Document autonomous operations integration (or lack thereof)
3. Add recommendation for future refactoring
4. Update statistics

### Priority 2: Integrate Autonomous Ops with Remediation (2-3 hours)

**Refactor autonomous-execute.sh:**
```bash
# Instead of inline disk cleanup:
execute_disk_cleanup() {
    # ... 50 lines of cleanup logic ...
}

# Call remediation playbook:
execute_disk_cleanup() {
    ~/containers/.claude/remediation/scripts/apply-remediation.sh \
        --playbook disk-cleanup \
        --log-to decision-log.json
}
```

**Benefits:**
- Single source of truth for remediation logic
- Better testing (test playbooks independently)
- Easier to add new remediation actions
- Consistent logging and safety checks

### Priority 3: Automate Context Updates (1-2 hours)

**Add hooks to deployment scripts:**
```bash
# In deploy-from-pattern.sh, after successful deployment:
~/.claude/context/scripts/build-deployment-log.sh --add \
    "$service" "$date" "$pattern" "$memory" "$networks" "$notes"
```

**Add hooks to autonomous operations:**
```bash
# In autonomous-execute.sh, after resolving issue:
~/.claude/context/scripts/populate-issue-history.sh --add \
    "AUTO-$(date +%Y%m)" "Auto-resolved: $issue" "$category" "$severity"
```

### Priority 4: Expose Context to Skills (2 hours)

**Enhance homelab-intelligence skill:**
```bash
# Current: "Disk at 84%"
# Enhanced: "Disk at 84%. Historical pattern (ISS-001, ISS-005):
#            Journal logs + image pruning typically frees 10-15GB.
#            Run disk-cleanup remediation? (y/n)"
```

**Implement in skill:**
- Query issue-history for similar issues
- Suggest proven solutions
- Offer to execute remediation playbook

---

## Architectural Insight

### Current State: Three Parallel Systems

```
Context Framework (Session 4)
    ↓ (weak integration)
Remediation Framework (Session 4B)
    ↓ (no integration!)
Autonomous Operations (Session 6)
    ↑ (reimplements remediation logic)
```

### Desired State: Unified Architecture

```
Context Framework (data layer)
    ↓ (strong integration)
Remediation Framework (execution layer)
    ↓ (calls playbooks)
Autonomous Operations (decision layer)
    ↓ (uses context for decisions)
Skills (presentation layer)
    ↑ (exposes context-aware recommendations)
```

---

## Session 5D Discovery

**Surprise Finding:** Session 5D (Skill Recommendations) is **actually implemented**!

**Evidence:**
```bash
$ ls -lh ~/.claude/context/
-rw-------. 1 patriark patriark 7.2K nov.  30 20:23 task-skill-map.json
-rw-r--r--. 1 patriark patriark 1.7K nov.  30 20:49 skill-usage.json
```

**Scripts exist:**
- ~/containers/scripts/recommend-skill.sh
- ~/containers/scripts/analyze-skill-usage.sh

**BUT:**
- Not mentioned in Session 4 README
- Not mentioned in 2025-11-30 synthesis report as "missing"
- Implementation date: 2025-11-30 (very recent!)

**Status:** Session 5D is **83% complete** (missing monthly analytics timer)

---

## Conclusion

**Context Framework:** Well-designed but **needs documentation updates** and **automated refresh**

**Remediation Framework:** Solid foundation but **underutilized** - autonomous operations should call playbooks

**Integration:** **Fragmented** - three systems working in parallel rather than unified architecture

**Next Steps:**
1. Update READMEs (Priority 1) - **Highest impact, lowest effort**
2. Automate context updates (Priority 3) - **Medium effort, high value**
3. Refactor autonomous ops to use remediation playbooks (Priority 2) - **High effort, highest long-term value**

---

**Analysis By:** Claude Code
**Recommendation:** Start with Priority 1 (documentation) to make current capabilities discoverable
