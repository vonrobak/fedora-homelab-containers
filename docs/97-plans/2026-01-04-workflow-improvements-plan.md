# Claude Code Workflow Enhancement Plan

## Executive Summary

This plan implements workflow enhancements inspired by Boris Cherny's Claude Code tips:

**Components:**
1. **commit-push-pr slash command** - Fast git workflow automation with gh CLI
2. **3 specialized subagents** - code-simplifier, service-validator, infrastructure-architect
3. **Verification feedback loops** - Integrated into homelab-deployment and autonomous-operations
4. **Confidence learning** - Autonomous operations learn from verification outcomes

**Timeline:** 4 weeks, 22-28 hours total
**Organization:** Extends existing skills (homelab-deployment, autonomous-operations)

---

## Implementation Overview

### Phase 1: Foundation (Week 1, 3-4 hours)
**Deliverables:**
- `/home/patriark/containers/.claude/commands/commit-push-pr.md` - Slash command
- `/home/patriark/containers/.claude/agents/infrastructure-architect.md` - Design subagent
- Update CLAUDE.md with usage instructions

**Key Features:**
- Pre-compute git status for speed (~0.5s parallel vs ~2s sequential)
- Auto-detect change type (deployment, config, docs)
- Generate structured commit messages with homelab context
- Create PR with verification checklist
- Reference deployment logs and issue history

### Phase 2: Verification Infrastructure (Week 1-2, 4-5 hours)
**Deliverables:**
- `/home/patriark/containers/scripts/verify-security-posture.sh` - Security checks
- `/home/patriark/containers/scripts/verify-monitoring.sh` - Monitoring integration
- `/home/patriark/containers/scripts/verify-autonomous-outcome.sh` - Outcome verification
- `/home/patriark/containers/.claude/skills/homelab-deployment/scripts/verify-deployment.sh` - Wrapper
- `/home/patriark/containers/.claude/agents/service-validator.md` - Validation subagent

**Key Features:**
- 7-level verification framework (health, network, routing, auth, monitoring, drift, security)
- "Assume failure until proven otherwise" mindset
- Structured verification reports
- Integration with existing test-deployment.sh

### Phase 3: Homelab-Deployment Integration (Week 2, 3-4 hours)
**Deliverables:**
- Update `homelab-deployment/SKILL.md` - Add Phase 5.5 (verification) and 5.6 (simplification)
- Update `homelab-deployment/COOKBOOK.md` - Add verification recipes
- `/home/patriark/containers/.claude/agents/code-simplifier.md` - Refactoring subagent

**Key Features:**
- Automatic verification after deployment
- Optional code simplification (pattern compliance)
- Deployment stops if verification fails
- Verification reports included in deployment journals

### Phase 4: Autonomous Operations Integration (Week 2-3, 4-5 hours)
**Deliverables:**
- Update `autonomous-operations/SKILL.md` - Add verification feedback loop
- Modify `~/containers/scripts/autonomous-execute.sh` - Add verification calls
- Update `autonomous-state.json` schema - Add verification fields

**Key Features:**
- Verify autonomous actions actually solved the problem
- Update confidence scores based on verification (+5% success, -10% failure)
- Auto-rollback if verification fails
- Confidence learning (system improves over time)

### Phase 5: Testing & Documentation (Week 3, 5-6 hours)
**Deliverables:**
- End-to-end testing scenarios (5 scenarios)
- Update CLAUDE.md (slash commands, subagents sections)
- Create ADR-017: Slash Commands and Subagents Architecture
- Create training docs (verification-workflow.md, subagent-usage.md)

### Phase 6: Refinement & Optimization (Week 4, 3-4 hours)
**Deliverables:**
- Performance optimization (verification < 30s)
- Error message improvements
- Subagent prompt tuning
- Summary journal entry

---

## Critical Files

### New Files (13 total)

**Slash Commands:**
1. `.claude/commands/commit-push-pr.md` - Git workflow automation

**Subagents:**
2. `.claude/agents/infrastructure-architect.md` - Design decisions
3. `.claude/agents/service-validator.md` - Deployment verification
4. `.claude/agents/code-simplifier.md` - Config refactoring

**Verification Scripts:**
5. `scripts/verify-security-posture.sh` - Security checks
6. `scripts/verify-monitoring.sh` - Monitoring integration
7. `scripts/verify-autonomous-outcome.sh` - Outcome verification
8. `.claude/skills/homelab-deployment/scripts/verify-deployment.sh` - Wrapper

**Documentation:**
9. `docs/10-services/guides/verification-workflow.md` - Training
10. `docs/10-services/guides/subagent-usage.md` - Training
11. `docs/10-services/guides/slash-commands.md` - Training
12. `docs/*/decisions/ADR-017-slash-commands-and-subagents.md` - Architecture
13. `docs/98-journals/2026-01-XX-claude-workflow-enhancement.md` - Summary

### Modified Files (4 total)

1. `.claude/skills/homelab-deployment/SKILL.md` - Add verification phases
2. `.claude/skills/homelab-deployment/COOKBOOK.md` - Add recipes
3. `.claude/skills/autonomous-operations/SKILL.md` - Add feedback loop
4. `scripts/autonomous-execute.sh` - Add verification calls

---

## Key Design Decisions

### 1. Slash Command vs Skill for commit-push-pr
**Decision:** Slash command (simpler, faster)
**Rationale:**
- Linear workflow (stage → commit → push → PR)
- No multi-phase orchestration needed
- User requested "simpler, faster" implementation
- Commands perfect for "one-shot" workflows

### 2. Subagents vs Extending Skills
**Decision:** Both - subagents for specialized roles, extend skills for workflow integration
**Rationale:**
- Subagents: Different "persona" (assume failure, architect mindset, refactoring expert)
- Skills: Multi-phase workflows with state management
- Service-validator has strict "assume failure" mindset
- Code-simplifier runs post-deployment (different context)

### 3. Verification Integration Point
**Decision:** Phase 5.5 in homelab-deployment (after deployment, before documentation)
**Rationale:**
- Never document failed deployments
- Catch issues before git commit
- Allow simplification after verification
- Follows fail-fast principle

### 4. Confidence Learning Strategy
**Decision:** ±5-10% delta based on verification outcomes
**Rationale:**
- Verified success → +5% (reward good decisions)
- Warnings → +2% (partial success)
- Failed verification → -10% (strong negative signal)
- Prevents over-confidence and under-confidence

---

## Verification Framework

### 7-Level Verification Checklist

**Level 1: Service Health (CRITICAL)**
- ✓ Systemd service active
- ✓ Container running
- ✓ Health check passing
- ✓ No crash loops
- ✓ Logs clean

**Level 2: Network Connectivity (HIGH)**
- ✓ On expected networks
- ✓ Internal endpoint accessible
- ✓ DNS resolution working

**Level 3: External Routing (HIGH for public)**
- ✓ Traefik route exists
- ✓ External URL responds
- ✓ TLS certificate valid
- ✓ Security headers present

**Level 4: Authentication Flow (HIGH for protected)**
- ✓ Redirects to Authelia
- ✓ Authelia responding
- ✓ Middleware chain correct

**Level 5: Monitoring Integration (MEDIUM)**
- ✓ Prometheus scraping
- ✓ Metrics available
- ✓ Grafana dashboard (optional)

**Level 6: Configuration Drift (LOW)**
- ✓ Running config matches quadlet

**Level 7: Security Posture (CRITICAL for public)**
- ✓ CrowdSec active
- ✓ Rate limiting active
- ✓ No direct host exposure

---

## Success Metrics

### Before Implementation
- Verification: Manual, inconsistent
- Deployment failures: ~10%
- Autonomous confidence: Static
- Time to verify: 5-10 minutes

### After Implementation (Targets)
- Verification: Automatic, comprehensive
- Deployment failures: <5%
- Autonomous confidence: Dynamic (learns)
- Time to verify: <30 seconds

### Leading Indicators
- Week 1: Slash command faster than manual workflow
- Week 2: Verification catches real issues (no false positives)
- Week 3: Autonomous verification prevents rollbacks
- Week 4: Overall workflow smoother, less manual verification

---

## Testing Strategy

### Unit Tests (Per Component)
- commit-push-pr: Test with different scenarios (clean, unstaged, branches)
- Subagents: Test each independently
- Verification scripts: Test each level independently

### Integration Tests (Workflows)
- Full deployment: design → deploy → verify → simplify → commit → PR
- Autonomous: observe → decide → act → verify → learn

### Regression Tests
- Existing deployments still work
- Existing autonomous operations unchanged
- Existing drift detection working

### Acceptance Tests (User Scenarios)
- Deploy new service (end-to-end)
- Fix unhealthy service (autonomous)
- Manual verification request

---

## Rollback Plan

### Low Risk (Phase 1-2)
- Remove new files
- No changes to existing systems
- Impact: Low

### Medium Risk (Phase 3)
- Revert SKILL.md changes
- Keep verification scripts (useful standalone)
- Impact: Medium

### High Risk (Phase 4)
- Revert autonomous-execute.sh
- Keep state schema (backward compatible)
- Impact: High

### Partial Rollback
- Can keep some enhancements independently
- Slash command works without subagents
- Verification scripts useful standalone

---

## Next Steps After Approval

1. Create directory structure (.claude/commands/, .claude/agents/)
2. Start Phase 1: commit-push-pr command
3. Test slash command with simple change
4. Create infrastructure-architect subagent
5. Test design consultation workflow
6. Proceed to Phase 2 (verification infrastructure)

**Estimated first deliverable:** commit-push-pr command (2-3 hours)
