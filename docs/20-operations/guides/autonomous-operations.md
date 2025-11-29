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

Settings in `~/.claude/context/preferences.yml`:

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
~/.claude/context/scripts/query-decisions.sh

# Last 7 days
~/.claude/context/scripts/query-decisions.sh --last 7d

# Only failures
~/.claude/context/scripts/query-decisions.sh --outcome failure

# Statistics
~/.claude/context/scripts/query-decisions.sh --stats
```

## Monitoring

- **Weekly Report**: Includes autonomous operations section (status, actions, success rate)
- **Discord**: Notifications on action execution (configurable)
- **Logs**: `journalctl --user -u autonomous-operations.service`

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
