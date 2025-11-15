# Session 4 Quick Start Guide

**Plan Document:** `docs/99-reports/2025-11-15-session-4-hybrid-plan.md`
**Approach:** Hybrid (70% Context + 30% Auto-Remediation)
**Target:** Level 2 Automation (Intelligent Semi-Autonomous)

---

## What You're Building

**Context Framework (70%)** - Make Claude remember your system:
- System profile: Hardware, networks, services inventory
- Issue history: Past problems and their solutions
- Deployment memory: Learn from successful deployments
- Context-aware skills: "Last time this happened..."

**Auto-Remediation (30%)** - Let Claude fix common issues:
- Disk cleanup: Automatically free space when >75%
- Drift reconciliation: Auto-fix config mismatches
- Service recovery: Smart restart patterns
- Resource pressure: Handle memory/CPU spikes

---

## Before You Start (on fedora-htpc)

```bash
# 1. Pull the plan
cd ~/containers
git fetch origin
git checkout claude/plan-skills-enhancement-01FRfDgNytQdvP6uKqkCR1CL
git pull

# 2. Review the full plan
less docs/99-reports/2025-11-15-session-4-hybrid-plan.md

# 3. Verify prerequisites
~/containers/scripts/homelab-intel.sh  # Should complete without hanging
ls -lh docs/99-reports/*.json | head -5  # Verify historical data exists
```

---

## Session 4A: Context Framework (3-4 hours)

**Quick execution:**

```bash
# Create directory structure
mkdir -p .claude/context/scripts
mkdir -p .claude/remediation/{playbooks,scripts}

# Follow detailed steps in plan document:
# Section: "Session 4A: Context Framework (3-4 hours)"
# Located at: docs/99-reports/2025-11-15-session-4-hybrid-plan.md (lines 658-703)

# Key deliverables:
# - .claude/context/system-profile.json
# - .claude/context/issue-history.json
# - .claude/context/deployment-log.json
# - Context query scripts

# Validation checkpoint:
# Should have 10+ issues, 15+ deployments, all 20 services in profile
```

---

## Session 4B: Auto-Remediation (2-3 hours)

**Quick execution:**

```bash
# Follow detailed steps in plan document:
# Section: "Session 4B: Auto-Remediation (2-3 hours)"
# Located at: docs/99-reports/2025-11-15-session-4-hybrid-plan.md (lines 705-760)

# Key deliverables:
# - 4 remediation playbooks
# - Execution engine (apply-remediation.sh)
# - Enhanced skills with auto-remediation
# - User preferences template

# Validation checkpoint:
# Test disk cleanup in dry-run mode, verify drift auto-fix offers
```

---

## What Success Looks Like

After Session 4, Claude will say things like:

**Context-Aware Intelligence:**
```
"System disk at 78%. I've seen this before (ISS-002, 2025-11-12):
 Last time we freed 12GB by pruning images + rotating logs.
 Would you like me to run the same automated cleanup now?"
```

**Deployment Memory:**
```
"Deploying Redis. Based on your cache-service pattern from 2025-11-10,
 I'm setting memory to 512MB and enabling AOF persistence..."
```

**Auto-Remediation:**
```
"Drift detected in jellyfin. Auto-reconciliation available:
 I can regenerate from pattern and restart. Proceed? (y/n)"
```

---

## Key Files Reference

**Plans:**
- Full plan: `docs/99-reports/2025-11-15-session-4-hybrid-plan.md`
- This quickstart: `.claude/SESSION-4-QUICKSTART.md`

**Context Files (will be created):**
- System profile: `.claude/context/system-profile.json`
- Issue history: `.claude/context/issue-history.json`
- Deployment log: `.claude/context/deployment-log.json`
- User prefs: `.claude/context/preferences.yml`

**Remediation Files (will be created):**
- Playbooks: `.claude/remediation/playbooks/*.yml`
- Executor: `.claude/remediation/scripts/apply-remediation.sh`

**Enhanced Skills:**
- Intelligence: `.claude/skills/homelab-intelligence/SKILL.md`
- Deployment: `.claude/skills/homelab-deployment/SKILL.md`
- Integration: `.claude/skills/skill-integration-guide.md`

---

## Estimated Time

**Session 4A (Context):** 3-4 hours
- System profile generation: 1h
- Issue history population: 1h
- Deployment log building: 1h
- Integration & testing: 1h

**Session 4B (Remediation):** 2-3 hours
- Playbook creation: 1.5h
- Execution engine: 1h
- Testing & validation: 1h
- Skill integration: 0.5h

**Total:** 6-8 hours (split across 2-3 CLI sessions)

---

## Testing Scenarios

After implementation, test these:

1. **Context-aware health check** (test issue history)
2. **Deployment with memory** (test deployment log)
3. **Automated drift fix** (test auto-remediation)

See full testing scenarios in main plan document (lines 762-855).

---

## Questions Before Starting?

**Should auto-remediation require confirmation?**
→ Recommended: Yes (change in preferences.yml later if desired)

**How many days of history to keep?**
→ Recommended: 90 days (configurable in context scripts)

**Commit context data to git?**
→ Recommended: Commit schemas/templates, gitignore actual data

---

## Ready to Execute

```bash
# On fedora-htpc:
cd ~/containers
cat .claude/SESSION-4-QUICKSTART.md  # This file

# Start Session 4A
# Follow: docs/99-reports/2025-11-15-session-4-hybrid-plan.md
#   Section: "Session 4A: Context Framework (3-4 hours)"

# When 4A complete, start 4B
# Follow: Same document, section "Session 4B: Auto-Remediation"
```

---

**Plan created:** 2025-11-15
**Status:** Ready for CLI execution
**Branch:** `claude/plan-skills-enhancement-01FRfDgNytQdvP6uKqkCR1CL`
**Commit:** d1342a6
