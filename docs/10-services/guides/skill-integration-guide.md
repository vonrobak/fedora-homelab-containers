# Claude Skills Integration Guide

**Purpose:** Help Claude Code choose and combine skills appropriately

**Audience:** Claude Code AI assistants

**Last Updated:** 2025-11-14

---

## Available Skills

| Skill | Purpose | When to Invoke |
|-------|---------|----------------|
| homelab-intelligence | System health assessment | "How is the system?", before major changes, proactive checks |
| homelab-deployment | Service deployment automation | Deploying new services, using patterns |
| systematic-debugging | Root cause analysis | Bugs, failures, unexpected behavior |
| git-advanced-workflows | Advanced git operations | Rebasing, bisect, complex history |
| claude-code-analyzer | Usage optimization | Analyzing Claude usage, suggesting improvements |

---

## Skill Invocation Decision Tree

```
User Request Type?

├─ "How is the system?" / "Check health" / "Any issues?"
│  └─ INVOKE: homelab-intelligence
│     THEN: Analyze output, provide recommendations
│
├─ "Deploy [service]" / "Set up [service]" / "Install [service]"
│  ├─ Check if service type matches existing pattern
│  │  ├─ YES → INVOKE: homelab-deployment (pattern-based)
│  │  └─ NO → Use pattern as reference, deploy manually
│  └─ BEFORE deployment:
│     └─ INVOKE: homelab-intelligence (verify system ready)
│
├─ "[Service] not working" / "Error in [service]" / "Bug in [code]"
│  └─ INVOKE: systematic-debugging
│     THEN: Follow 4-phase debugging framework
│
├─ "Rebase branch" / "Bisect bug" / "Clean up history"
│  └─ INVOKE: git-advanced-workflows
│
└─ "Optimize my Claude usage" / "Analyze my workflows"
   └─ INVOKE: claude-code-analyzer
```

---

## Integration Patterns

### Pattern 1: Health-Check-Before-Deploy

**Workflow:**
1. User: "Deploy Jellyfin"
2. INVOKE: homelab-intelligence
3. Verify health score ≥ 70
4. INVOKE: homelab-deployment (if healthy)
5. Deploy using media-server-stack pattern

**Example interaction:**
```
User: "I want to deploy Jellyfin for my media"

Claude: Let me first check system health before deploying.
[Invokes homelab-intelligence skill]

Result: Health score 85/100 - system ready

Claude: System is healthy. I'll deploy Jellyfin using the media-server-stack pattern.
[Invokes homelab-deployment skill with pattern media-server-stack]

Result: Service deployed successfully at jellyfin.patriark.org
```

**When to use:**
- Any new service deployment request
- System modifications that consume resources
- Before deploying resource-intensive services (databases, media servers)

**Don't use if:**
- User explicitly says "skip health check"
- Emergency fix (system down, need quick deployment)

---

### Pattern 2: Debug-Then-Fix

**Workflow:**
1. User: "[Service] is broken"
2. INVOKE: systematic-debugging
3. Follow 4-phase framework (investigate → analyze → test → implement)
4. If fix requires redeployment → INVOKE: homelab-deployment
5. If fix requires code change → INVOKE: git-advanced-workflows (for commits)

**Example interaction:**
```
User: "Traefik isn't routing to Jellyfin anymore"

Claude: Let me use systematic debugging to investigate.
[Invokes systematic-debugging skill]

Phase 1 - Investigation:
- Checked Traefik logs: No errors
- Checked Jellyfin logs: Service running
- Checked Traefik labels: Missing updated hostname

Root cause: Traefik labels not updated after hostname change

Claude: Found it - the Traefik labels have the old hostname. I'll update the quadlet and redeploy.
[Updates quadlet, uses homelab-deployment for orchestrated restart]

Result: Service now accessible at new hostname
```

**When to use:**
- Service failures
- Unexpected behavior
- Performance issues
- Configuration problems

**Don't skip debugging if:**
- Issue might recur (need root cause)
- Affects multiple services
- Security implications

---

### Pattern 3: Deploy-Monitor-Drift

**Workflow:**
1. INVOKE: homelab-deployment (deploy new service)
2. Wait for deployment completion
3. Run drift detection: `./scripts/check-drift.sh <service>`
4. Document deployment in git

**Example interaction:**
```
User: "Set up Redis for session storage"

Claude: I'll deploy Redis using the cache-service pattern.
[Invokes homelab-deployment skill]

Result: Redis deployed as redis-sessions

Claude: Let me verify there's no configuration drift.
[Runs check-drift.sh]

Result: Configuration matches - no drift detected

Claude: Deployment successful. Redis available at redis-sessions:6379 on systemd-auth_services network.
```

**When to use:**
- After every deployment
- Periodic configuration audits
- Before major system changes

---

### Pattern 4: Intelligence-Informed-Decisions

**Workflow:**
1. INVOKE: homelab-intelligence
2. Parse health score and issues
3. Make recommendations based on data
4. If actionable → suggest next steps

**Example interaction:**
```
User: "Should I deploy the new monitoring exporter?"

Claude: Let me check system state first.
[Invokes homelab-intelligence skill]

Result:
- Health score: 72/100
- Warning: System disk at 78%
- Warning: High memory usage (85%)

Claude: System health is at 72/100. I recommend:
1. Clear disk space first (currently 78%, target <70%)
2. Investigate memory usage (85% is elevated)
3. Deploy monitoring exporter AFTER cleanup (it will help diagnose memory)

Would you like me to help with cleanup first?
```

**When to use:**
- User asks "should I...?"
- User mentions system performance concerns
- Before recommending resource-intensive actions
- Regular check-ins (proactive)

**Intelligence score interpretation:**
- 90-100: Excellent - proceed with any deployment
- 75-89: Good - proceed but monitor
- 50-74: Degraded - address warnings first
- 0-49: Critical - fix issues before new deployments

---

## Skill Combination Workflows

### Workflow A: Full Deployment Lifecycle

**Steps:**
1. **Pre-deployment health check**
   - INVOKE: homelab-intelligence
   - Verify score ≥ 70

2. **Pattern selection**
   - Review `docs/10-services/guides/pattern-selection-guide.md`
   - Choose appropriate pattern

3. **Deployment**
   - INVOKE: homelab-deployment
   - Use selected pattern
   - Monitor deployment progress

4. **Verification**
   - Run drift detection
   - Test service access
   - Verify monitoring integration

5. **Documentation**
   - Update CLAUDE.md if needed
   - Commit changes with git-advanced-workflows if complex

**Example command sequence:**
```bash
# 1. Health check
./scripts/homelab-intel.sh

# 2. Deploy from pattern
cd .claude/skills/homelab-deployment
./scripts/deploy-from-pattern.sh \
  --pattern cache-service \
  --service-name myapp-redis \
  --memory 512M

# 3. Verify
./scripts/check-drift.sh myapp-redis

# 4. Test
redis-cli -h localhost -p 6379 ping
```

---

### Workflow B: Troubleshooting & Recovery

**Steps:**
1. **Problem detection**
   - User reports issue OR
   - Intelligence skill detects problem

2. **Systematic debugging**
   - INVOKE: systematic-debugging
   - Follow 4-phase framework
   - Identify root cause

3. **Fix implementation**
   - If config issue → update quadlet, redeploy
   - If code issue → fix, test, commit
   - If resource issue → scale or cleanup

4. **Verification**
   - Rerun health check
   - Verify fix resolved issue
   - Check for drift

5. **Prevention**
   - Document in ADR if architectural
   - Add monitoring if needed
   - Update patterns if applies broadly

---

### Workflow C: Routine Maintenance

**Frequency:** Weekly or bi-weekly

**Steps:**
1. **Health assessment**
   ```bash
   ./scripts/homelab-intel.sh
   ```

2. **Drift detection**
   ```bash
   cd .claude/skills/homelab-deployment
   ./scripts/check-drift.sh  # All services
   ```

3. **Review findings**
   - Any critical issues? → Address immediately
   - Any warnings? → Schedule fixes
   - Any drift? → Reconcile or document as intentional

4. **Cleanup if needed**
   ```bash
   podman system prune -f
   journalctl --user --vacuum-time=7d
   ```

**Proactive invocation:**
If Claude notices it's been >1 week since last health check, suggest running intelligence skill.

---

## Skill-Specific Invocation Criteria

### homelab-intelligence

**INVOKE when:**
- User asks: "how is", "status", "health", "any issues", "check system"
- Before deploying resource-intensive services (>2GB RAM)
- User mentions performance concerns
- User reports errors or issues
- Proactively: If >1 week since last check
- Before major system changes (multi-service deployment)

**DON'T invoke if:**
- User explicitly skips with `--skip-health-check`
- Just checking status of single service (use systemctl)
- Emergency quick fix needed
- Just gathering information (reading files)

**Parse output for:**
- health_score (0-100)
- critical[] array (immediate action items)
- warnings[] array (future action items)
- metrics{} (specific values for decision-making)

---

### homelab-deployment

**INVOKE when:**
- User wants to: "deploy", "install", "set up", "create" a service
- Service type matches one of 9 patterns
- System health allows (score ≥ 70)

**Pattern matching:**
| User says... | Pattern to use |
|--------------|----------------|
| "media server", "Jellyfin", "Plex" | media-server-stack |
| "wiki", "Nextcloud", "blog" | web-app-with-database |
| "Paperless", "document management" | document-management |
| "Authelia", "SSO", "authentication" | authentication-stack |
| "Vaultwarden", "password manager" | password-manager |
| "PostgreSQL", "MySQL", "database" | database-service |
| "Redis", "cache", "sessions" | cache-service |
| "internal API", "admin panel" | reverse-proxy-backend |
| "exporter", "metrics" | monitoring-exporter |

**Use pattern-based deployment when:**
- Clear match to existing pattern
- Standard configuration acceptable
- User doesn't require heavy customization

**Use manual deployment when:**
- No pattern matches
- Heavy customization needed
- Multi-service stack (use patterns as reference)

---

### systematic-debugging

**INVOKE when:**
- User reports: "broken", "not working", "error", "failing"
- Service unexpectedly stopped
- Performance degraded
- Configuration issues
- Test failures

**4-Phase Framework:**
1. **Investigation:** Gather facts (logs, status, config)
2. **Pattern Analysis:** Compare to working state, identify changes
3. **Hypothesis Testing:** Test root cause theories
4. **Implementation:** Fix with confidence

**DON'T invoke for:**
- Simple status checks (use direct commands)
- Expected behavior (not a bug)
- Already know root cause (just fix it)

---

## Common Integration Scenarios

### Scenario 1: New Service Deployment

**User:** "I want to set up Jellyfin"

**Claude workflow:**
1. ✓ Matches pattern (media-server-stack)
2. INVOKE: homelab-intelligence
3. Check health score
4. INVOKE: homelab-deployment with pattern
5. Verify deployment
6. Provide access URL + credentials

**Commands executed:**
```bash
./scripts/homelab-intel.sh
cd .claude/skills/homelab-deployment
./scripts/deploy-from-pattern.sh \
  --pattern media-server-stack \
  --service-name jellyfin \
  --hostname jellyfin.patriark.org \
  --memory 4G
```

---

### Scenario 2: Service Troubleshooting

**User:** "Grafana isn't showing Prometheus data"

**Claude workflow:**
1. INVOKE: systematic-debugging
2. Phase 1: Check Prometheus status, Grafana datasource config
3. Phase 2: Compare to working configuration
4. Phase 3: Test connectivity, query datasource
5. Phase 4: Fix configuration issue
6. Verify: Query returns data

**Commands executed:**
```bash
# Investigation
systemctl --user status prometheus grafana
podman logs grafana | grep -i prometheus

# Testing
curl http://localhost:9090/-/healthy
curl http://localhost:3000/api/datasources

# Fix (example - update datasource UID)
# Edit grafana provisioning config
systemctl --user restart grafana
```

---

### Scenario 3: System Health Concern

**User:** "System seems slow lately"

**Claude workflow:**
1. INVOKE: homelab-intelligence
2. Analyze output for resource pressure
3. Check for:
   - High disk usage → cleanup recommendations
   - High memory → identify memory hogs
   - High CPU → check for runaway processes
   - Swap thrashing → memory pressure
4. Provide specific fixes based on findings

---

### Scenario 4: Configuration Audit

**User:** "Are all my services configured correctly?"

**Claude workflow:**
1. INVOKE: homelab-intelligence (overall health)
2. Run drift detection on all services
3. Compare results:
   - Services with drift → list differences
   - Services matching → confirm correct
   - Services with warnings → explain
4. Suggest reconciliation if drift found

**Commands executed:**
```bash
./scripts/homelab-intel.sh
cd .claude/skills/homelab-deployment
./scripts/check-drift.sh
```

---

## Decision Criteria Quick Reference

### When NOT Sure Which Skill

**Ask yourself:**
1. **Is user deploying something new?** → homelab-deployment
2. **Is something broken/failing?** → systematic-debugging
3. **Is user asking about system state?** → homelab-intelligence
4. **Is this a git history task?** → git-advanced-workflows
5. **Is this about Claude usage?** → claude-code-analyzer
6. **Is this none of the above?** → Don't invoke skill, handle directly

### Skill Priority Order

If multiple skills could apply:
1. systematic-debugging (if there's a problem)
2. homelab-intelligence (if need system state)
3. homelab-deployment (if deploying)
4. Others as appropriate

### Multi-Skill Tasks

For complex tasks requiring multiple skills:
1. Start with intelligence (understand state)
2. Use debugging if problem exists
3. Use deployment for fixes requiring new services
4. Use git workflows for committing changes

**Execute sequentially, not in parallel**

---

## Proactive Skill Usage

### When Claude Should Be Proactive

**Suggest homelab-intelligence when:**
- User mentions performance concerns
- User mentions "lately" or "recently" (indicates change)
- User asks "should I...?" (decision needs data)
- Session just started after >1 week gap

**Suggest homelab-deployment when:**
- User describes a service type matching existing pattern
- User asks "how do I set up X?" where X matches pattern
- User mentions specific service names (Jellyfin, Redis, etc.)

**Suggest systematic-debugging when:**
- User says "not sure why..." or "strange behavior"
- User reports intermittent issues
- User mentions recent changes that broke things

---

## Anti-Patterns (Don't Do This)

### ❌ Over-Invoking Skills

**Wrong:**
```
User: "What port does Jellyfin use?"
Claude: [Invokes homelab-deployment skill]
```

**Right:**
```
User: "What port does Jellyfin use?"
Claude: Jellyfin typically uses port 8096. Check your quadlet:
cat ~/.config/containers/systemd/jellyfin.container | grep PublishPort
```

**Rule:** Only invoke skills for tasks that truly need their specialized capabilities.

---

### ❌ Skipping Health Checks

**Wrong:**
```
User: "Deploy this database"
Claude: [Immediately invokes homelab-deployment]
```

**Right:**
```
User: "Deploy this database"
Claude: Let me first check system health.
[Invokes homelab-intelligence]
Result: Health 85/100 - Good
Claude: System ready. Deploying PostgreSQL.
[Invokes homelab-deployment]
```

**Rule:** Always check health before resource-intensive deployments.

---

### ❌ Using Wrong Skill

**Wrong:**
```
User: "My service won't start"
Claude: [Invokes homelab-deployment to redeploy]
```

**Right:**
```
User: "My service won't start"
Claude: Let me debug this systematically.
[Invokes systematic-debugging]
[Identifies missing network]
Claude: Fixed - network didn't exist. Creating it now.
```

**Rule:** Debug before redeploying. Redeploying masks root causes.

---

## Skill Output Parsing

### homelab-intelligence Output

```json
{
  "health_score": 85,
  "critical": [
    {"code": "C001", "message": "...", "action": "..."}
  ],
  "warnings": [
    {"code": "W001", "message": "...", "action": "..."}
  ],
  "metrics": {
    "disk_usage_system": 65,
    "disk_usage_btrfs": 42,
    "memory_used_percent": 55
  }
}
```

**Key values to check:**
- `health_score < 70` → Don't deploy new services
- `critical.length > 0` → Address before proceeding
- `disk_usage_system > 75` → Cleanup needed
- `memory_used_percent > 85` → Memory pressure

---

### homelab-deployment Output

Pattern deployment provides:
- Quadlet generation status
- Health check results
- Prerequisites validation
- Deployment success/failure
- Post-deployment checklist

**Check for:**
- Exit code (0 = success)
- Service status (active/inactive)
- Health check passing

---

### check-drift.sh Output

```
Service: jellyfin
  ✓ Image: matches
  ✓ Memory: matches
  ⚠ Networks: order differs (warning)
  ✓ Volumes: matches
  ✓ Labels: matches
Status: MATCH
```

**Categorization:**
- MATCH → No action needed
- DRIFT → Reconcile (restart service)
- WARNING → Informational, may be intentional

---

## Summary Checklist

Before invoking a skill, verify:

- [ ] Skill matches the task type
- [ ] User's request requires skill's capabilities
- [ ] Not a simple task better done directly
- [ ] System health checked if deploying
- [ ] Previous skill output parsed and used
- [ ] Will provide value to user's goal

**Good skill invocation = Right skill + Right time + Right task**

---

**Related Documentation:**
- Pattern selection: `docs/10-services/guides/pattern-selection-guide.md`
- Deployment skill: `.claude/skills/homelab-deployment/SKILL.md`
- Intelligence skill: `.claude/skills/homelab-intelligence/SKILL.md`
- Quick recipes: `.claude/skills/homelab-deployment/COOKBOOK.md`
