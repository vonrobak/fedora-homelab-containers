# Autonomous Operations Guide

The autonomous operations engine implements an OODA loop (Observe, Orient, Decide, Act) that monitors system health and takes corrective actions automatically.

## Quick Reference

```bash
# Check status
~/containers/scripts/autonomous-execute.sh --status

# Run assessment only
~/containers/scripts/autonomous-check.sh --verbose

# Run full cycle (dry-run)
~/containers/scripts/autonomous-execute.sh --from-check --dry-run

# Emergency controls
~/containers/scripts/autonomous-execute.sh --pause   # Stop actions
~/containers/scripts/autonomous-execute.sh --stop    # Full shutdown
~/containers/scripts/autonomous-execute.sh --resume  # Resume operations
```

## How It Works

### Daily Automation

The `autonomous-operations.timer` runs at **06:30 daily**:
1. Collects system health, predictions, drift status
2. Evaluates against preferences and history
3. Calculates confidence scores for potential actions
4. Executes approved low-risk actions automatically

### Decision Matrix

| Confidence + Risk | Action |
|-------------------|--------|
| >90% + Low Risk | AUTO-EXECUTE |
| >80% + Medium Risk | NOTIFY + EXECUTE |
| >70% + Any Risk | QUEUE (for approval) |
| <70% | ALERT ONLY |

### Supported Actions

| Action | Risk | Cooldown | Description |
|--------|------|----------|-------------|
| disk-cleanup | Low | 1 hour | Prune containers, rotate logs |
| service-restart | Low | 5 min | Restart unhealthy services |
| drift-reconciliation | Medium | 15 min | Reload systemd, restart drifted services |

## Safety Controls

### Circuit Breaker
Automatically pauses after 3 consecutive failures. Reset with `--resume`.

### Service Overrides
Critical services never auto-restart (configured in `preferences.yml`):
- traefik
- authelia

### Pre-Action Snapshots
Every action creates a BTRFS snapshot before execution for instant rollback.

## Configuration

Settings in `~/containers/.claude/context/preferences.yml`:

```yaml
risk_tolerance: medium  # low | medium | high
service_overrides:
  traefik:
    auto_restart: false
  authelia:
    auto_restart: false
```

## State Files

| File | Purpose |
|------|---------|
| `autonomous-state.json` | Current operational state, statistics |
| `decision-log.json` | Audit trail of all decisions |

## Query Decisions

```bash
# Last 10 decisions
~/containers/.claude/context/scripts/query-decisions.sh

# Last 7 days
~/containers/.claude/context/scripts/query-decisions.sh --last 7d

# Only failures
~/containers/.claude/context/scripts/query-decisions.sh --outcome failure

# Statistics
~/containers/.claude/context/scripts/query-decisions.sh --stats
```

## Monitoring

- **Weekly Report**: Includes autonomous operations section (status, actions, success rate)
- **Discord**: Notifications on action execution (configurable)
- **Logs**: `journalctl --user -u autonomous-operations.service`

## Integrations

### Query Cache Integration

The autonomous operations OBSERVE phase uses cached query results for improved performance:

**Benefits:**
- **58% faster**: OBSERVE phase completes in ~1-2 seconds (was 3-5 seconds)
- **Reduced load**: Fewer concurrent podman/systemctl calls
- **Graceful fallback**: Automatically falls back to direct calls if cache stale

**How it works:**
1. `precompute-queries.sh` runs every 5 minutes (cron job)
2. Caches results for: memory usage, CPU usage, disk usage, service health
3. `autonomous-check.sh` reads cache (if fresh) or falls back to direct calls

**Cache locations:**
- Cache file: `~/containers/.claude/context/query-cache.json`
- TTL: 60 seconds for most queries
- See: `docs/40-monitoring-and-documentation/guides/natural-language-queries.md`

**Performance metrics:**
```bash
# Before cache integration
OBSERVE phase: 12-21 system calls, 3-5 seconds

# After cache integration (cache hit)
OBSERVE phase: ~7 system calls, 1-2 seconds
```

### Skill Recommendation Integration

The autonomous operations DECIDE phase includes skill recommendations based on observed issues:

**How it works:**
1. DECIDE phase detects issues (unhealthy services, disk usage, drift)
2. Constructs natural language summary of situation
3. Calls `recommend-skill.sh` for skill suggestion
4. Includes recommendation in assessment output

**Example output:**
```json
{
  "skill_recommendations": {
    "category": "DEBUGGING",
    "top_recommendation": {
      "skill": "systematic-debugging",
      "confidence": 0.63,
      "invocation": "suggest"
    }
  }
}
```

**Skill mapping:**
| System State | Recommended Skill |
|--------------|-------------------|
| Unhealthy services | systematic-debugging |
| Configuration drift | homelab-deployment |
| High disk usage | homelab-intelligence |

**See:** `docs/10-services/guides/skill-recommendation.md`

### Remediation Framework Integration

The autonomous operations ACT phase executes actions via the remediation framework:

**Architecture:**
```
DECIDE phase (autonomous-execute.sh)
  ↓ Identifies action needed
  ↓ Calculates confidence score
  ↓
ACT phase calls remediation playbook
  ↓
apply-remediation.sh --playbook disk-cleanup --log-to decision-log.json
  ↓
Remediation playbook executes
  ↓
Result logged to decision-log.json
```

**Benefits:**
- **Single source of truth:** Remediation logic only in playbooks
- **Consistency:** Same behavior whether manual or autonomous
- **Testability:** Test playbooks independently of autonomous operations
- **Maintainability:** Update remediation logic in one place

**Implementation (2025-11-30):**
- Refactored 3 execute functions to call remediation playbooks
- Eliminated 85 lines of duplicated remediation logic
- Added --log-to parameter for decision log integration
- All autonomous actions now use remediation framework

**Execution Flow:**
```bash
# Disk cleanup example
execute_disk_cleanup() {
    "$APPLY_REMEDIATION" \
        --playbook disk-cleanup \
        --log-to "$DECISION_LOG" \
        2>&1 | tee -a "$LOG_FILE"
}
```

**Available Remediation Actions:**
| Playbook | Risk | Used By Autonomous Ops |
|----------|------|------------------------|
| disk-cleanup | Low | ✅ Yes |
| service-restart | Low | ✅ Yes |
| drift-reconciliation | Medium | ✅ Yes |
| resource-pressure | Medium | ⏳ Playbook pending |

**See:**
- Remediation framework: `~/containers/.claude/remediation/README.md`
- Implementation report: `docs/99-reports/2025-11-30-remediation-integration-implementation.md`

## Troubleshooting

### Check Why Actions Aren't Running

1. Is it paused? Check `--status`
2. Circuit breaker triggered? Check `--status`
3. Service override? Check `preferences.yml`
4. On cooldown? Check `--status` for active cooldowns
5. Confidence too low? Run `autonomous-check.sh --verbose`

### Reset After Issues

```bash
# Resume and reset circuit breaker
~/containers/scripts/autonomous-execute.sh --resume
```
