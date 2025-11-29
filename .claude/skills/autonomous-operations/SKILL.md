---
name: autonomous-operations
description: Autonomous homelab operations using OODA loop (Observe, Orient, Decide, Act) - use when reviewing system state, planning autonomous actions, or investigating operational issues
---

# Autonomous Operations Engine

## Overview

The autonomous operations engine implements an OODA (Observe, Orient, Decide, Act) loop that orchestrates all homelab components into a self-managing system. It leverages existing infrastructure:

- **Context Framework** - Historical patterns and preferences
- **Auto-Remediation** - Playbook-based fixes
- **Predictive Analytics** - Resource exhaustion forecasting
- **Backup Integration** - Snapshot-protected operations
- **Homelab Intelligence** - Health scoring and diagnostics

**Philosophy:** Proactive over reactive. Predict and prevent rather than detect and fix.

## When to Use

**Always use for:**
- Reviewing current autonomous operations state
- Understanding what actions the system would take
- Investigating why an action was/wasn't taken
- Adjusting autonomy settings
- Querying the decision log

**Triggers:**
- User asks "what would the system do about..."
- User asks about autonomous actions taken
- User wants to review pending actions
- User asks to adjust autonomy level

## Architecture: OODA Loop

```
┌─────────────────────────────────────────────────────────────────────┐
│                           OBSERVE                                   │
│  • Predictive analytics (resource exhaustion forecasts)             │
│  • Health scoring (homelab-intel.sh)                                │
│  • Drift detection (check-drift.sh)                                 │
│  • Backup health verification                                       │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                           ORIENT                                    │
│  • Historical patterns (issue-history.json)                         │
│  • User preferences (preferences.yml)                               │
│  • Service overrides (traefik: no auto-restart)                     │
│  • Current state (autonomous-state.json)                            │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                           DECIDE                                    │
│  Confidence = (prediction × 0.30) + (historical × 0.30)             │
│             + (impact × 0.20) + (rollback × 0.20)                   │
│                                                                     │
│  ┌────────────────────┬──────────────────────────────────┐          │
│  │ Confidence + Risk  │ Action                           │          │
│  ├────────────────────┼──────────────────────────────────┤          │
│  │ >90% + Low Risk    │ AUTO-EXECUTE                     │          │
│  │ >80% + Med Risk    │ NOTIFY + EXECUTE                 │          │
│  │ >70% + Any Risk    │ QUEUE (for approval)             │          │
│  │ <70%               │ ALERT ONLY                       │          │
│  └────────────────────┴──────────────────────────────────┘          │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                            ACT                                      │
│  1. Create pre-action snapshot (BTRFS)                              │
│  2. Execute via appropriate skill/playbook                          │
│  3. Validate outcome (health check)                                 │
│  4. Auto-rollback if validation fails                               │
│  5. Log decision and outcome                                        │
└─────────────────────────────────────────────────────────────────────┘
```

## Core Scripts

### autonomous-check.sh

Evaluates current system state and outputs recommended actions:

```bash
# Run assessment (outputs JSON)
~/containers/scripts/autonomous-check.sh

# Verbose output
~/containers/scripts/autonomous-check.sh --verbose

# Output to file
~/containers/scripts/autonomous-check.sh --output /tmp/assessment.json
```

**Output structure:**
```json
{
  "timestamp": "2025-11-29T22:00:00+01:00",
  "health_score": 94,
  "observations": [...],
  "recommended_actions": [
    {
      "id": "action-001",
      "type": "disk-cleanup",
      "reason": "Disk predicted 90% full in 8 days",
      "confidence": 0.92,
      "risk": "low",
      "decision": "auto-execute"
    }
  ],
  "pending_queue": []
}
```

### autonomous-execute.sh

Executes approved actions from the queue:

```bash
# Execute pending low-risk actions
~/containers/scripts/autonomous-execute.sh

# Execute specific action
~/containers/scripts/autonomous-execute.sh --action-id action-001

# Dry run (simulate only)
~/containers/scripts/autonomous-execute.sh --dry-run
```

### Emergency Controls

```bash
# Emergency stop all autonomous operations
~/containers/scripts/autonomous-execute.sh --stop

# Pause (stop acting, keep observing)
~/containers/scripts/autonomous-execute.sh --pause

# Resume operations
~/containers/scripts/autonomous-execute.sh --resume

# View current state
~/containers/scripts/autonomous-execute.sh --status
```

## State Files

### autonomous-state.json

Location: `~/.claude/context/autonomous-state.json`

Tracks operational state:
```json
{
  "enabled": true,
  "mode": "active",
  "paused": false,
  "circuit_breaker": {
    "triggered": false,
    "consecutive_failures": 0,
    "last_failure": null
  },
  "last_check": "2025-11-29T22:00:00+01:00",
  "pending_actions": [],
  "cooldowns": {
    "jellyfin.restart": "2025-11-29T20:00:00+01:00"
  },
  "statistics": {
    "actions_24h": 2,
    "actions_7d": 8,
    "success_rate": 0.95
  }
}
```

### decision-log.json

Location: `~/.claude/context/decision-log.json`

Audit trail of all decisions:
```json
{
  "decisions": [
    {
      "id": "decision-001",
      "timestamp": "2025-11-29T03:00:00+01:00",
      "action_type": "disk-cleanup",
      "trigger": "prediction: disk 90% in 9 days",
      "confidence": 0.92,
      "risk": "low",
      "decision": "auto-execute",
      "outcome": "success",
      "details": "Freed 15 GB, new prediction: 21 days",
      "duration_seconds": 45
    }
  ]
}
```

## Integration Points

### With Existing Playbooks

The engine routes actions to existing remediation playbooks:

| Action Type | Playbook | Risk |
|-------------|----------|------|
| disk-cleanup | `.claude/remediation/playbooks/disk-cleanup.yml` | Low |
| service-restart | `.claude/remediation/playbooks/service-restart.yml` | Low |
| drift-reconciliation | `.claude/remediation/playbooks/drift-reconciliation.yml` | Medium |
| resource-pressure | `.claude/remediation/playbooks/resource-pressure.yml` | Medium |

### With Preferences

Respects all settings in `~/.claude/context/preferences.yml`:

- `risk_tolerance` - Affects confidence thresholds
- `service_overrides` - Per-service restrictions (traefik: no auto-restart)
- `safety.max_restarts_per_hour` - Rate limiting
- `safety.restart_cooldown_seconds` - Cooldown periods

### With Backups

Every action is protected:

1. Pre-action snapshot created via `btrfs-snapshot-backup.sh`
2. Snapshot tagged: `autonomous-<action>-<timestamp>`
3. Auto-rollback if validation fails
4. Snapshot retained for 7 days minimum

## Decision Matrix

### Risk Classification

| Action | Data Risk | Availability Risk | Overall |
|--------|-----------|-------------------|---------|
| Disk cleanup | None (snapshot) | None | **LOW** |
| Service restart | None (stateless) | 2-5s downtime | **LOW** |
| Config reconciliation | None (snapshot) | Potential failure | **MEDIUM** |
| Multi-service change | Medium | Cascading risk | **HIGH** |

### Confidence Calculation

```
confidence = (
    prediction_confidence × 0.30 +    # How sure about the problem?
    historical_success × 0.30 +       # Has this fix worked before?
    impact_certainty × 0.20 +         # Are we sure about outcome?
    rollback_feasibility × 0.20       # Can we undo if it fails?
)
```

**Example: Disk cleanup**
```
prediction_confidence = 0.89  # Linear trend, high confidence
historical_success = 1.00     # 12/12 successful cleanups
impact_certainty = 0.95       # Known outcome
rollback_feasibility = 1.00   # Instant snapshot restore

confidence = 0.89×0.3 + 1.0×0.3 + 0.95×0.2 + 1.0×0.2
           = 0.267 + 0.300 + 0.190 + 0.200
           = 0.957 (95.7%)

Decision: AUTO-EXECUTE (>90% + low risk)
```

## Safety Controls

### Circuit Breaker

Automatically pauses after 3 consecutive failures:

```json
{
  "circuit_breaker": {
    "threshold": 3,
    "triggered": true,
    "consecutive_failures": 3,
    "last_failure": "2025-11-29T04:00:00+01:00",
    "reason": "service-restart failed 3 times"
  }
}
```

**Recovery:** Manual reset via `--resume` or automatically after 24 hours.

### Cooldowns

Prevent action storms:

- Service restart: 5 minute cooldown between restarts
- Disk cleanup: 1 hour cooldown
- Drift reconciliation: 15 minute cooldown

### Service Overrides

Critical services have special handling:

```yaml
# From preferences.yml
service_overrides:
  traefik:
    auto_restart: false         # Never auto-restart
    requires_confirmation: true
  authelia:
    auto_restart: false         # SSO is critical
    requires_confirmation: true
  prometheus:
    auto_restart: true          # Can auto-restart
    restart_timeout_seconds: 90
```

## Systemd Integration

### Timer: autonomous-check.timer

Runs daily assessment at 06:00 (after backups):

```ini
[Timer]
OnCalendar=*-*-* 06:00:00
RandomizedDelaySec=300
Persistent=true
```

### Service: autonomous-execute.service

Executes approved actions after check completes.

## Query Interface

### Via Claude Code

```
"What autonomous actions were taken this week?"
"Show me pending actions"
"Why didn't the system restart Jellyfin?"
"What's the current autonomous operations status?"
```

### Via Scripts

```bash
# Query decision log
~/containers/.claude/context/scripts/query-decisions.sh --last 7d

# Query pending actions
~/containers/.claude/context/scripts/query-decisions.sh --pending

# Query by action type
~/containers/.claude/context/scripts/query-decisions.sh --type disk-cleanup
```

## Reporting

### Weekly Intelligence Report Integration

The weekly report includes autonomous operations section:

```
## Autonomous Operations (Last 7 Days)

Actions Taken: 8
  - disk-cleanup: 2 (100% success)
  - service-restart: 5 (100% success)
  - drift-reconciliation: 1 (100% success)

Success Rate: 100%
Average Confidence: 91%

Pending Actions: 0
Circuit Breaker: Not triggered
```

### Discord Notifications

- Action execution: Notify on execute (configurable)
- Failures: Always notify
- Weekly summary: Included in intelligence report

## Troubleshooting

### Check Current State

```bash
# View state file
cat ~/.claude/context/autonomous-state.json | jq '.'

# View recent decisions
cat ~/.claude/context/decision-log.json | jq '.decisions[-5:]'

# Check if paused
cat ~/.claude/context/autonomous-state.json | jq '.paused'
```

### Circuit Breaker Triggered

```bash
# Check why
cat ~/.claude/context/autonomous-state.json | jq '.circuit_breaker'

# View failing action
cat ~/.claude/context/decision-log.json | jq '.decisions | map(select(.outcome == "failure")) | .[-3:]'

# Reset manually
~/containers/scripts/autonomous-execute.sh --resume
```

### Action Not Executing

Check in order:
1. Is autonomous operations enabled? (`enabled: true`)
2. Is it paused? (`paused: false`)
3. Is circuit breaker triggered?
4. Is the service in overrides with `auto_restart: false`?
5. Is there a cooldown active?
6. Is confidence below threshold?

## Success Metrics

- **Proactive ratio:** 80%+ issues prevented before impact
- **Success rate:** >95% of autonomous actions succeed
- **MTTR reduction:** Minutes instead of hours
- **Manual interventions:** <10% of issues require human action

---

**This skill orchestrates all homelab components into a self-managing system.**
