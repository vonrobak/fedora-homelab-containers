# Remediation Chains - Multi-Playbook Orchestration

**Phase 5: Advanced Orchestration**
**Status:** ✅ Production
**Last Updated:** 2025-12-24

---

## Overview

Remediation chains enable complex remediation workflows by orchestrating multiple playbooks in sequence. Instead of running individual playbooks, you can define sophisticated recovery strategies that combine cleanup, maintenance, and service recovery operations.

**Key Benefits:**
- **Comprehensive recovery:** Execute multiple remediation steps in a coordinated sequence
- **Conditional execution:** Skip playbooks based on system state
- **Failure strategies:** Control how the chain responds to playbook failures
- **State management:** Resume interrupted chains from the last successful step
- **Metrics tracking:** Monitor chain-level success rates and duration

---

## Quick Start

### List Available Chains

```bash
cd ~/.claude/remediation/scripts
./execute-chain.sh --list-chains
```

**Available chains:**
- `full-recovery` - Complete system recovery (disk cleanup + memory relief + service restart + drift fix)
- `predictive-preemption` - Proactive maintenance based on resource exhaustion forecasts
- `database-health` - Database maintenance + service restart with health verification

### Validate Chain Configuration

```bash
./execute-chain.sh --validate full-recovery
```

### Dry Run (Preview Execution)

```bash
./execute-chain.sh --chain predictive-preemption --dry-run
```

### Execute Chain

```bash
# With confirmation prompt (for high-risk chains)
./execute-chain.sh --chain full-recovery

# Skip confirmation (for low-risk chains)
./execute-chain.sh --chain predictive-preemption --force

# Verbose logging
./execute-chain.sh --chain database-health --verbose
```

---

## Chain Specification Format

Chains are defined in YAML files stored in `.claude/remediation/chains/*.yml`.

### Basic Structure

```yaml
# Chain metadata
name: my-chain
description: Human-readable description of what this chain does
risk_level: medium  # low, medium, high
requires_confirmation: yes  # Prompt user before execution

# Playbook sequence
playbooks:
  - name: playbook-name
    description: "What this playbook does"
    timeout: 300  # Seconds (optional, default: 300)
    on_failure: continue  # continue, skip, stop, abort, rollback
    priority: 1  # Display order (optional)
    condition: "some_condition"  # Optional conditional execution
    parameters:  # Optional playbook parameters
      service: jellyfin
      option: value

# Execution settings
execution_strategy: sequential  # Only sequential supported in Phase 5
rollback_on_failure: false  # Enable/disable rollback on failures
max_duration: 900  # Maximum chain execution time (seconds)
stop_on_abort: true  # Stop immediately if any playbook aborts

# Metrics
metrics:
  track_duration: true
  track_success_rate: true
  report_to_prometheus: true
```

### Complete Example

```yaml
name: full-recovery
description: Complete system recovery sequence
risk_level: high
requires_confirmation: yes

playbooks:
  - name: disk-cleanup
    description: "Remove old logs and container layers"
    timeout: 300
    on_failure: continue  # Continue even if cleanup fails
    priority: 1

  - name: resource-pressure
    description: "Clear caches if memory pressure detected"
    timeout: 180
    condition: "memory_pressure_detected"  # Only run if condition is true
    on_failure: skip
    priority: 2

  - name: self-healing-restart
    description: "Restart Jellyfin service"
    parameters:
      service: jellyfin
    timeout: 120
    on_failure: abort  # Abort entire chain if restart fails
    priority: 3

execution_strategy: sequential
rollback_on_failure: false
max_duration: 900  # 15 minutes total
```

---

## Failure Strategies

Control how the chain responds when a playbook fails:

| Strategy | Behavior | Use Case |
|----------|----------|----------|
| **continue** | Continue to next playbook, ignore failure | Non-critical cleanup operations |
| **skip** | Skip to next playbook (same as continue) | Optional optimization steps |
| **stop** | Stop chain execution, return failure status | Default conservative behavior |
| **abort** | Immediately abort chain, no further playbooks | Critical operations that must succeed |
| **rollback** | Restore system to pre-chain state (BTRFS snapshot) | Database operations requiring atomicity |

**Example:**

```yaml
playbooks:
  - name: disk-cleanup
    on_failure: continue  # Cleanup is nice-to-have, not critical

  - name: database-maintenance
    on_failure: abort  # Database maintenance is critical

  - name: self-healing-restart
    on_failure: rollback  # Service restart can be rolled back
```

---

## Conditional Execution

Skip playbooks based on system state using conditions:

### Available Conditions

| Condition | Evaluates True When |
|-----------|---------------------|
| `memory_pressure_detected` | Available memory <20% OR swap usage >80% |
| `disk_exhaustion_predicted` | Predictive analytics forecasts disk exhaustion within 7 days |
| `memory_exhaustion_predicted` | Predictive analytics forecasts memory exhaustion within 7 days |

**Example:**

```yaml
playbooks:
  - name: resource-pressure
    condition: "memory_pressure_detected"
    # Only runs if memory pressure exists

  - name: disk-cleanup
    condition: "disk_exhaustion_predicted"
    # Only runs if disk exhaustion is predicted
```

### Adding New Conditions

Edit `execute-chain.sh` and add a check function:

```bash
check_my_condition() {
    # Your logic here
    if [ some_condition ]; then
        return 0  # Condition is true
    else
        return 1  # Condition is false
    fi
}

# Add to evaluate_condition() function
evaluate_condition() {
    case "$condition" in
        "my_condition")
            check_my_condition
            ;;
        # ... other conditions
    esac
}
```

---

## State Management

Every chain execution creates a state file in `.claude/remediation/state/` that tracks:

- Execution ID (unique identifier)
- Start and end timestamps
- Current playbook index
- Completed playbooks
- Failed playbooks
- Skipped playbooks
- Final status (running, success, failed, aborted)

**State File Example:**

```json
{
  "chain": "full-recovery",
  "execution_id": "full-recovery_1735027200",
  "start_time": 1735027200,
  "end_time": 1735027485,
  "status": "success",
  "playbooks_completed": ["disk-cleanup", "self-healing-restart"],
  "playbooks_failed": [],
  "playbooks_skipped": ["resource-pressure"],
  "current_playbook_index": 3,
  "total_playbooks": 4
}
```

### Resume Interrupted Chains (Future)

```bash
# Resume from last successful playbook
./execute-chain.sh --resume full-recovery_1735027200
```

**Status:** Not yet implemented (roadmap: Phase 5b)

---

## Prometheus Metrics

Chain executions emit metrics to `~/containers/data/backup-metrics/remediation.prom`.

### Metrics Emitted

```prometheus
# Total executions by chain and status
remediation_chain_executions_total{chain="full-recovery",status="success"} 5
remediation_chain_executions_total{chain="full-recovery",status="failed"} 1
remediation_chain_executions_total{chain="full-recovery",status="aborted"} 0

# Last execution timestamp
remediation_chain_last_execution_timestamp{chain="full-recovery"} 1735027485

# Last execution duration
remediation_chain_duration_seconds{chain="full-recovery"} 285

# Playbooks in last execution
remediation_chain_playbooks_total{chain="full-recovery",outcome="succeeded"} 3
remediation_chain_playbooks_total{chain="full-recovery",outcome="failed"} 0
remediation_chain_playbooks_total{chain="full-recovery",outcome="skipped"} 1

# Success rate (last 30 days)
remediation_chain_success_rate{chain="full-recovery"} 0.8333
```

### Querying Metrics

```bash
# View chain metrics
grep "remediation_chain" ~/containers/data/backup-metrics/remediation.prom

# Query in Prometheus
curl 'http://localhost:9090/api/v1/query?query=remediation_chain_success_rate'

# Grafana dashboard query
rate(remediation_chain_executions_total{status="success"}[5m])
```

---

## Pre-Built Chains

### 1. Full Recovery

**Purpose:** Comprehensive system recovery when multiple issues are detected

**Playbooks:**
1. `disk-cleanup` - Free up disk space
2. `resource-pressure` - Reduce memory pressure (conditional)
3. `self-healing-restart` - Restart Jellyfin
4. `drift-reconciliation` - Fix configuration drift

**Risk Level:** HIGH
**Requires Confirmation:** YES
**Max Duration:** 15 minutes

**Usage:**

```bash
./execute-chain.sh --chain full-recovery
```

**When to Use:**
- System health score <50
- Multiple services experiencing issues
- After major system updates
- Manual recovery after incident

---

### 2. Predictive Preemption

**Purpose:** Proactive maintenance before resources are exhausted

**Playbooks:**
1. `predictive-maintenance` - Run forecasting analysis
2. `disk-cleanup` - Free disk if exhaustion predicted (conditional)
3. `database-maintenance` - VACUUM and optimize databases

**Risk Level:** MEDIUM
**Requires Confirmation:** NO (safe for autonomous execution)
**Max Duration:** 20 minutes

**Usage:**

```bash
./execute-chain.sh --chain predictive-preemption --force
```

**Automation:**

```bash
# Add to autonomous-operations or create dedicated timer
# Recommended: Daily at 06:00 (before autonomous-operations)

# ~/.config/systemd/user/predictive-preemption-chain.timer
[Unit]
Description=Predictive Preemption Chain
Documentation=file:///home/patriark/containers/docs/20-operations/guides/remediation-chains.md

[Timer]
OnCalendar=daily
OnCalendar=*-*-* 06:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

**When to Use:**
- Daily proactive maintenance
- After predictive analytics detects critical forecasts
- As part of weekly maintenance routine

---

### 3. Database Health

**Purpose:** Database maintenance with service restart and health verification

**Playbooks:**
1. `database-maintenance` - VACUUM PostgreSQL, analyze Redis
2. `self-healing-restart` - Restart PostgreSQL service

**Risk Level:** MEDIUM
**Requires Confirmation:** YES (service restart)
**Max Duration:** 15 minutes
**Rollback:** ENABLED (BTRFS snapshots)

**Usage:**

```bash
./execute-chain.sh --chain database-health
```

**Pre-flight Checks:**
- Immich service must be running
- PostgreSQL backup must be <24h old (warn only)

**Post-execution Verification:**
- PostgreSQL must respond to queries
- Immich API must return 200 OK

**When to Use:**
- Weekly database maintenance (Sunday 03:00)
- After database performance degradation
- Following large data ingestion (Immich photo uploads)

---

## Creating Custom Chains

### Step 1: Create Chain YAML

Create a new file: `.claude/remediation/chains/my-custom-chain.yml`

```yaml
name: my-custom-chain
description: Brief description of the chain purpose
risk_level: medium
requires_confirmation: yes

playbooks:
  - name: first-playbook
    timeout: 300
    on_failure: continue

  - name: second-playbook
    timeout: 180
    on_failure: abort

execution_strategy: sequential
max_duration: 600
```

### Step 2: Validate Configuration

```bash
./execute-chain.sh --validate my-custom-chain
```

Fix any errors reported (missing playbooks, invalid fields, etc.)

### Step 3: Test with Dry Run

```bash
./execute-chain.sh --chain my-custom-chain --dry-run --verbose
```

Review the execution plan without making changes.

### Step 4: Execute

```bash
./execute-chain.sh --chain my-custom-chain
```

### Step 5: Monitor Metrics

```bash
# Check execution state
cat ~/.claude/remediation/state/my-custom-chain_*.json | tail -1 | jq

# View metrics
grep "my-custom-chain" ~/containers/data/backup-metrics/remediation.prom
```

---

## Best Practices

### Design Principles

1. **Start conservative:** Use `on_failure: abort` for critical playbooks
2. **Add conditions:** Skip unnecessary playbooks based on system state
3. **Set realistic timeouts:** Allow enough time but prevent runaway execution
4. **Test with dry-run:** Always validate before real execution
5. **Monitor metrics:** Track success rates and adjust chains accordingly

### Risk Assessment

| Risk Level | Characteristics | Confirmation Required | Examples |
|------------|----------------|----------------------|----------|
| **Low** | Read-only, no service restarts | No | Predictive analytics, health checks |
| **Medium** | Service restarts, conditional cleanups | Optional | Database maintenance, targeted recovery |
| **High** | Multiple service restarts, aggressive cleanup | Yes | Full system recovery, major maintenance |

### Timeout Guidelines

- **Disk cleanup:** 300s (5 minutes)
- **Memory optimization:** 180s (3 minutes)
- **Service restart:** 120s (2 minutes)
- **Database VACUUM:** 600s (10 minutes)
- **Full chain:** max_duration = sum of playbook timeouts + 20% buffer

### Failure Strategy Selection

```
Is the playbook critical for the chain to succeed?
├─ Yes → on_failure: abort
└─ No → Is it a nice-to-have optimization?
    ├─ Yes → on_failure: continue
    └─ No → on_failure: stop (default)
```

---

## Troubleshooting

### Chain Validation Fails

**Symptom:** `Chain validation failed with N error(s)`

**Common Causes:**
1. Unknown playbook name (typo or playbook doesn't exist)
2. Missing required field (name, description, risk_level)
3. Invalid YAML syntax

**Solution:**

```bash
# Check YAML syntax
yq eval . ~/.claude/remediation/chains/my-chain.yml

# List available playbooks
~/.claude/remediation/scripts/apply-remediation.sh --list-playbooks

# Fix errors and re-validate
./execute-chain.sh --validate my-chain
```

---

### Chain Times Out

**Symptom:** Chain execution aborted due to `max_duration` exceeded

**Solution:**

1. Increase `max_duration` in chain YAML
2. Reduce individual playbook timeouts
3. Remove non-critical playbooks
4. Add conditions to skip unnecessary playbooks

---

### Playbook Failure Stops Chain

**Symptom:** Chain stops at first playbook failure

**Cause:** Default behavior is `on_failure: stop`

**Solution:**

Choose appropriate failure strategy:

```yaml
playbooks:
  - name: optional-cleanup
    on_failure: continue  # Allow chain to proceed

  - name: critical-restart
    on_failure: abort  # Stop immediately on failure
```

---

### Condition Never Triggers

**Symptom:** Playbook with condition is always skipped

**Debugging:**

```bash
# Run with verbose logging
./execute-chain.sh --chain my-chain --verbose

# Check condition logic in execute-chain.sh
grep -A 10 "check_memory_pressure" ~/.claude/remediation/scripts/execute-chain.sh

# Manually test condition
free | awk '/^Mem:/ {print ($7/$2)*100}'  # Memory available %
```

---

## Integration Points

### Autonomous Operations

Chains can be triggered by the autonomous operations OODA loop:

```bash
# In autonomous-check.sh, add chain trigger logic
if [ $HEALTH_SCORE -lt 50 ]; then
    RECOMMENDED_ACTIONS+=("chain:full-recovery")
fi
```

### Alertmanager Webhooks

Trigger chains from SLO alerts:

```yaml
# In webhook-routing.yml
routes:
  - alert: SystemDegraded
    chain: full-recovery
    confidence: 90
    requires_confirmation: yes
```

**Status:** Not yet implemented (roadmap: Phase 5b)

---

### Scheduled Execution

Create systemd timers for regular chain execution:

```bash
# ~/.config/systemd/user/database-health-chain.timer
[Unit]
Description=Weekly Database Health Chain
Documentation=file:///home/patriark/containers/docs/20-operations/guides/remediation-chains.md

[Timer]
OnCalendar=weekly
OnCalendar=Sun *-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
# ~/.config/systemd/user/database-health-chain.service
[Unit]
Description=Database Health Remediation Chain
Documentation=file:///home/patriark/containers/docs/20-operations/guides/remediation-chains.md

[Service]
Type=oneshot
ExecStart=/home/patriark/containers/.claude/remediation/scripts/execute-chain.sh --chain database-health --force
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
systemctl --user daemon-reload
systemctl --user enable --now database-health-chain.timer
systemctl --user list-timers  # Verify scheduled
```

---

## Roadmap

### Phase 5a (Complete)
- ✅ Sequential chain execution
- ✅ Failure strategy handling
- ✅ Conditional playbook execution
- ✅ State management and tracking
- ✅ Prometheus metrics integration
- ✅ 3 pre-built chains (full-recovery, predictive-preemption, database-health)

### Phase 5b (Future)
- ⏳ Resume interrupted chains from state files
- ⏳ Parallel playbook execution (where safe)
- ⏳ Webhook trigger integration
- ⏳ Pre-flight and post-execution health checks
- ⏳ BTRFS snapshot rollback implementation
- ⏳ Chain dependency management (chain A requires chain B)

### Phase 5c (Future)
- ⏳ Chain composition (chains calling other chains)
- ⏳ Dynamic chain generation based on system state
- ⏳ Machine learning for optimal chain selection
- ⏳ Automated chain optimization based on success metrics

---

## Related Documentation

- **Playbooks:** `.claude/remediation/README.md` - Individual playbook documentation
- **Autonomous Operations:** `docs/20-operations/guides/autonomous-operations.md`
- **Roadmap:** `docs/97-plans/2025-12-23-remediation-phase-3-roadmap.md`
- **Metrics:** `docs/40-monitoring-and-documentation/guides/prometheus-metrics.md`

---

## Support

**Questions or Issues:**
- Review chain state files: `~/.claude/remediation/state/*.json`
- Check execution logs: `journalctl --user -u <chain-service>.service`
- Examine metrics: `~/containers/data/backup-metrics/remediation.prom`
- Validate chain: `./execute-chain.sh --validate <chain-name>`

**Last Updated:** 2025-12-24
**Phase:** 5 (Multi-Playbook Chaining)
**Status:** Production Ready
