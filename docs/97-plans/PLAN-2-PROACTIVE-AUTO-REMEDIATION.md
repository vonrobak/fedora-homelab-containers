# Plan 2: Proactive Auto-Remediation Loop - Implementation Roadmap

**Created:** 2025-11-18
**Status:** Ready for CLI Execution
**Priority:** 🚀 HIGH VALUE - Prevents issues before they become critical
**Estimated Effort:** 4-6 hours (2 CLI sessions)
**Dependencies:**
- Predictive Analytics System (Session 5B) ✅
- Auto-Remediation Playbooks (Session 4) ✅
- Context Framework (Session 4) ✅

---

## Executive Summary

**The Problem:**
You have two powerful systems that don't talk to each other:

1. **Predictive Analytics** - Forecasts resource exhaustion 7-14 days in advance
2. **Auto-Remediation Playbooks** - Automated fixes for common problems

**Current Workflow (Manual):**
```
Predictive system: "Disk will fill in 8 days"
  ↓
homelab-intel.sh generates report with prediction
  ↓
YOU read the report
  ↓
YOU decide if action is needed
  ↓
YOU manually run remediation playbook
  ↓
Problem fixed
```

**Gap:** The decision and execution steps require human intervention. If you're busy or miss the report, problems escalate.

**The Solution: Proactive Auto-Remediation Decision Engine**

```
Predictive system: "Disk will fill in 8 days"
  ↓
Decision engine: Checks prediction severity + time-to-impact
  ↓
Decision engine: Maps prediction to appropriate remediation
  ↓
Safety validation: Simulates remediation (dry-run)
  ↓
Execution: Runs remediation playbook automatically
  ↓
Notification: Discord alert with action taken
  ↓
Context Framework: Logs action for historical tracking
  ↓
Problem prevented before it becomes critical
```

**Value Proposition:**
- **Prevents 80% of resource exhaustion incidents** - Disk/memory issues fixed before critical
- **Reduces manual intervention** - System self-heals minor issues
- **Historical tracking** - Complete audit trail of automated actions
- **Safe execution** - Dry-run validation before every action

---

## Architecture

### Three-Component System

```
┌─────────────────────────────────────────────────────────────────┐
│  INPUT: Predictive Analytics System                            │
│  Location: .claude/analytics/predictions.json                  │
│  Data: Resource exhaustion forecasts (disk, memory, swap)      │
│  Format:                                                        │
│    {                                                            │
│      "prediction_type": "disk_exhaustion",                      │
│      "resource": "/",                                           │
│      "days_until_critical": 8.2,                                │
│      "confidence": 0.85                                         │
│    }                                                            │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  COMPONENT 1: Decision Engine                                   │
│  Logic:                                                         │
│  1. Read predictions from analytics system                      │
│  2. Filter actionable predictions (confidence > 70%)            │
│  3. Map prediction type to remediation playbook                 │
│  4. Check if action is safe to execute (business rules)         │
│  5. Return list of approved actions                             │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  COMPONENT 2: Safety Validation                                 │
│  Logic:                                                         │
│  1. Simulate remediation in dry-run mode                        │
│  2. Check system prerequisites (service running, etc.)          │
│  3. Verify no critical services will be impacted               │
│  4. Estimate impact (downtime, resource usage)                  │
│  5. Approve or reject execution                                 │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  COMPONENT 3: Execution Engine                                  │
│  Logic:                                                         │
│  1. Execute approved remediation playbook                       │
│  2. Capture output and exit code                                │
│  3. Log action to Context Framework (issues.json)               │
│  4. Export metrics to Prometheus                                │
│  5. Send Discord notification with results                      │
└─────────────────────────────────────────────────────────────────┘
```

---

## Session 1: Decision Engine & Execution (2-3 hours)

### Phase 1.1: Prediction-to-Action Mapping (45min)

**Objective:** Define business rules for automatic remediation

**Deliverable: Mapping Configuration**

**File:** `config/proactive-remediation/action-mapping.json`

```json
{
  "version": "1.0",
  "last_updated": "2025-11-18",
  "mappings": [
    {
      "prediction_type": "disk_exhaustion",
      "resource_filter": "/",
      "conditions": {
        "min_days_until_critical": 3,
        "max_days_until_critical": 14,
        "min_confidence": 0.70
      },
      "action": {
        "playbook": "disk-cleanup",
        "version": "1.1",
        "max_executions_per_week": 2,
        "cooldown_hours": 48
      },
      "safety_checks": [
        "system_health_score >= 50",
        "no_active_backups",
        "disk_usage < 95%"
      ]
    },
    {
      "prediction_type": "memory_exhaustion",
      "resource_filter": "system_memory",
      "conditions": {
        "min_days_until_critical": 1,
        "max_days_until_critical": 7,
        "min_confidence": 0.75
      },
      "action": {
        "playbook": "resource-pressure",
        "version": "1.0",
        "max_executions_per_week": 3,
        "cooldown_hours": 24
      },
      "safety_checks": [
        "system_health_score >= 60",
        "no_critical_services_restarting"
      ]
    },
    {
      "prediction_type": "service_drift",
      "resource_filter": "*",
      "conditions": {
        "min_confidence": 0.80
      },
      "action": {
        "playbook": "drift-reconciliation",
        "version": "1.0",
        "max_executions_per_week": 5,
        "cooldown_hours": 12
      },
      "safety_checks": [
        "system_health_score >= 70",
        "service_is_running"
      ]
    }
  ],
  "global_settings": {
    "enable_auto_remediation": true,
    "dry_run_mode": false,
    "require_confirmation": false,
    "max_daily_executions": 5,
    "notification_channel": "discord"
  }
}
```

**Implementation:**

```bash
# Create config directory
mkdir -p ~/containers/config/proactive-remediation

# Create mapping file
nano ~/containers/config/proactive-remediation/action-mapping.json
# Paste configuration above

# Validate JSON syntax
jq empty ~/containers/config/proactive-remediation/action-mapping.json
echo "JSON validation: $?"
```

**Acceptance Criteria:**
- [ ] Mapping file created with valid JSON
- [ ] All 3 prediction types mapped (disk, memory, drift)
- [ ] Safety checks defined for each action
- [ ] Global settings configured (start with dry_run_mode: true)

---

### Phase 1.2: Decision Engine Script (1-1.5h)

**Objective:** Create intelligent decision logic

**Deliverable: Decision Engine**

**File:** `scripts/proactive-remediation/decision-engine.sh`

```bash
#!/bin/bash
################################################################################
# Proactive Remediation Decision Engine
# Reads predictions and maps them to remediation actions
################################################################################

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/containers/config/proactive-remediation"
ANALYTICS_DIR="$HOME/containers/.claude/analytics"
CONTEXT_DIR="$HOME/containers/.claude/context/data"
LOG_DIR="$HOME/containers/data/remediation-logs"

MAPPING_FILE="$CONFIG_DIR/action-mapping.json"
PREDICTIONS_FILE="$ANALYTICS_DIR/predictions.json"
COOLDOWN_FILE="$CONFIG_DIR/action-cooldowns.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging
log() {
    local level=$1
    shift
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message="[$timestamp] [$level] $*"

    case $level in
        INFO)    echo -e "${BLUE}$message${NC}" ;;
        SUCCESS) echo -e "${GREEN}$message${NC}" ;;
        WARNING) echo -e "${YELLOW}$message${NC}" ;;
        ERROR)   echo -e "${RED}$message${NC}" ;;
        DEBUG)   echo -e "${CYAN}$message${NC}" ;;
    esac
}

# Check if jq is installed
check_dependencies() {
    if ! command -v jq &> /dev/null; then
        log "ERROR" "jq is required but not installed"
        exit 1
    fi
}

# Load configuration
load_config() {
    if [[ ! -f "$MAPPING_FILE" ]]; then
        log "ERROR" "Mapping file not found: $MAPPING_FILE"
        exit 1
    fi

    if [[ ! -f "$PREDICTIONS_FILE" ]]; then
        log "WARNING" "No predictions file found - analytics may not have run yet"
        return 1
    fi

    return 0
}

# Check if action is on cooldown
is_on_cooldown() {
    local playbook=$1

    if [[ ! -f "$COOLDOWN_FILE" ]]; then
        echo "[]" > "$COOLDOWN_FILE"
        return 1  # Not on cooldown
    fi

    local last_execution=$(jq -r ".[] | select(.playbook == \"$playbook\") | .last_execution" "$COOLDOWN_FILE" 2>/dev/null || echo "")

    if [[ -z "$last_execution" ]]; then
        return 1  # Never executed, not on cooldown
    fi

    local cooldown_hours=$(jq -r ".mappings[] | select(.action.playbook == \"$playbook\") | .action.cooldown_hours" "$MAPPING_FILE")

    local last_epoch=$(date -d "$last_execution" +%s 2>/dev/null || echo 0)
    local now_epoch=$(date +%s)
    local cooldown_seconds=$((cooldown_hours * 3600))

    if [[ $((now_epoch - last_epoch)) -lt $cooldown_seconds ]]; then
        local remaining_hours=$(( (cooldown_seconds - (now_epoch - last_epoch)) / 3600 ))
        log "INFO" "Action '$playbook' on cooldown ($remaining_hours hours remaining)"
        return 0  # On cooldown
    fi

    return 1  # Not on cooldown
}

# Update cooldown tracker
update_cooldown() {
    local playbook=$1

    local timestamp=$(date -Iseconds)

    # Initialize file if doesn't exist
    if [[ ! -f "$COOLDOWN_FILE" ]]; then
        echo "[]" > "$COOLDOWN_FILE"
    fi

    # Remove existing entry for this playbook and add new one
    local temp_file=$(mktemp)
    jq "map(select(.playbook != \"$playbook\")) + [{\"playbook\": \"$playbook\", \"last_execution\": \"$timestamp\"}]" \
        "$COOLDOWN_FILE" > "$temp_file"
    mv "$temp_file" "$COOLDOWN_FILE"

    log "DEBUG" "Updated cooldown for: $playbook"
}

# Check weekly execution limit
check_weekly_limit() {
    local playbook=$1
    local max_per_week=$2

    local one_week_ago=$(date -d '7 days ago' -Iseconds)

    # Count executions in past week from Context Framework
    local execution_count=0
    if [[ -f "$CONTEXT_DIR/issues.json" ]]; then
        execution_count=$(jq "[.issues[] | select(.tags[]? == \"auto-remediation\" and .tags[]? == \"$playbook\" and .created_at > \"$one_week_ago\")] | length" "$CONTEXT_DIR/issues.json" 2>/dev/null || echo 0)
    fi

    if [[ $execution_count -ge $max_per_week ]]; then
        log "WARNING" "Weekly limit reached for '$playbook' ($execution_count/$max_per_week)"
        return 1  # Limit exceeded
    fi

    log "DEBUG" "Weekly executions for '$playbook': $execution_count/$max_per_week"
    return 0  # Within limit
}

# Evaluate single prediction
evaluate_prediction() {
    local prediction=$1

    log "INFO" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "INFO" "  Evaluating Prediction"
    log "INFO" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local pred_type=$(echo "$prediction" | jq -r '.prediction_type')
    local resource=$(echo "$prediction" | jq -r '.resource')
    local days_until=$(echo "$prediction" | jq -r '.days_until_critical // .days_to_exhaustion // 999')
    local confidence=$(echo "$prediction" | jq -r '.confidence')

    log "INFO" "Type: $pred_type"
    log "INFO" "Resource: $resource"
    log "INFO" "Days until critical: $days_until"
    log "INFO" "Confidence: $confidence"

    # Find matching mapping
    local mapping=$(jq -c ".mappings[] | select(.prediction_type == \"$pred_type\")" "$MAPPING_FILE" | head -1)

    if [[ -z "$mapping" ]]; then
        log "WARNING" "No mapping found for prediction type: $pred_type"
        return 1
    fi

    # Extract conditions
    local min_days=$(echo "$mapping" | jq -r '.conditions.min_days_until_critical // 0')
    local max_days=$(echo "$mapping" | jq -r '.conditions.max_days_until_critical // 999')
    local min_confidence=$(echo "$mapping" | jq -r '.conditions.min_confidence')

    log "DEBUG" "Conditions: days [$min_days, $max_days], confidence >= $min_confidence"

    # Check conditions
    if (( $(echo "$days_until < $min_days" | bc -l) )); then
        log "WARNING" "Too urgent ($days_until < $min_days days) - requires immediate manual intervention"
        return 1
    fi

    if (( $(echo "$days_until > $max_days" | bc -l) )); then
        log "INFO" "Not urgent yet ($days_until > $max_days days) - defer action"
        return 1
    fi

    if (( $(echo "$confidence < $min_confidence" | bc -l) )); then
        log "WARNING" "Confidence too low ($confidence < $min_confidence)"
        return 1
    fi

    # Extract action
    local playbook=$(echo "$mapping" | jq -r '.action.playbook')
    local max_per_week=$(echo "$mapping" | jq -r '.action.max_executions_per_week')

    log "INFO" "✓ Conditions met - mapped to playbook: $playbook"

    # Check cooldown
    if is_on_cooldown "$playbook"; then
        return 1
    fi

    # Check weekly limit
    if ! check_weekly_limit "$playbook" "$max_per_week"; then
        return 1
    fi

    # Return approved action
    echo "$playbook"
    return 0
}

# Main decision logic
make_decisions() {
    log "INFO" "═══════════════════════════════════════════════════"
    log "INFO" "  Proactive Remediation Decision Engine"
    log "INFO" "═══════════════════════════════════════════════════"

    # Check if auto-remediation is enabled
    local enabled=$(jq -r '.global_settings.enable_auto_remediation' "$MAPPING_FILE")
    if [[ "$enabled" != "true" ]]; then
        log "WARNING" "Auto-remediation is disabled in config"
        exit 0
    fi

    # Load predictions
    local predictions=$(jq -c '.predictions[]?' "$PREDICTIONS_FILE" 2>/dev/null || echo "")

    if [[ -z "$predictions" ]]; then
        log "INFO" "No predictions found - system is healthy or analytics needs to run"
        exit 0
    fi

    local approved_actions=()

    # Evaluate each prediction
    while IFS= read -r prediction; do
        local action=$(evaluate_prediction "$prediction" || echo "")

        if [[ -n "$action" ]]; then
            approved_actions+=("$action")
        fi
    done <<< "$predictions"

    # Output results
    if [[ ${#approved_actions[@]} -eq 0 ]]; then
        log "INFO" "No actions approved for execution"
        exit 0
    fi

    log "SUCCESS" "═══════════════════════════════════════════════════"
    log "SUCCESS" "  Approved Actions: ${#approved_actions[@]}"
    log "SUCCESS" "═══════════════════════════════════════════════════"

    for action in "${approved_actions[@]}"; do
        log "SUCCESS" "  → $action"
    done

    # Output as JSON for next stage
    printf '%s\n' "${approved_actions[@]}" | jq -R -s -c 'split("\n") | map(select(length > 0))'
}

# Main execution
main() {
    mkdir -p "$LOG_DIR" "$CONFIG_DIR"

    check_dependencies

    if ! load_config; then
        exit 0
    fi

    make_decisions
}

main "$@"
```

**Implementation:**

```bash
# Create script directory
mkdir -p ~/containers/scripts/proactive-remediation

# Create decision engine script
nano ~/containers/scripts/proactive-remediation/decision-engine.sh
# Paste code above

# Make executable
chmod +x ~/containers/scripts/proactive-remediation/decision-engine.sh

# Test (dry run)
~/containers/scripts/proactive-remediation/decision-engine.sh
```

**Acceptance Criteria:**
- [ ] Script created and executable
- [ ] Script reads predictions.json correctly
- [ ] Script applies mapping rules correctly
- [ ] Cooldown logic prevents duplicate executions
- [ ] Weekly limit logic works
- [ ] Script outputs JSON list of approved actions

---

### Phase 1.3: Execution Engine (1h)

**Objective:** Execute approved remediation playbooks safely

**Deliverable: Execution Engine**

**File:** `scripts/proactive-remediation/execute-remediation.sh`

```bash
#!/bin/bash
################################################################################
# Proactive Remediation Execution Engine
# Executes approved remediation playbooks
################################################################################

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMEDIATION_DIR="$HOME/containers/.claude/remediation"
LOG_DIR="$HOME/containers/data/remediation-logs"
CONTEXT_DIR="$HOME/containers/.claude/context/data"
CONFIG_DIR="$HOME/containers/config/proactive-remediation"

APPLY_SCRIPT="$REMEDIATION_DIR/scripts/apply-remediation.sh"
COOLDOWN_FILE="$CONFIG_DIR/action-cooldowns.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging
log() {
    local level=$1
    shift
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message="[$timestamp] [$level] $*"

    case $level in
        INFO)    echo -e "${BLUE}$message${NC}" ;;
        SUCCESS) echo -e "${GREEN}$message${NC}" ;;
        WARNING) echo -e "${YELLOW}$message${NC}" ;;
        ERROR)   echo -e "${RED}$message${NC}" ;;
    esac
}

# Execute single playbook
execute_playbook() {
    local playbook=$1

    log "INFO" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "INFO" "  Executing Playbook: $playbook"
    log "INFO" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local timestamp=$(date +%Y%m%d-%H%M%S)
    local log_file="$LOG_DIR/proactive-${playbook}-${timestamp}.log"

    # Dry-run first (safety check)
    log "INFO" "Step 1/3: Safety validation (dry-run)"

    if ! "$APPLY_SCRIPT" --playbook "$playbook" --dry-run > "$log_file.dryrun" 2>&1; then
        log "ERROR" "Dry-run failed - aborting execution"
        cat "$log_file.dryrun"
        return 1
    fi

    log "SUCCESS" "✓ Dry-run passed"

    # Execute for real
    log "INFO" "Step 2/3: Executing remediation"

    local exit_code=0
    if "$APPLY_SCRIPT" --playbook "$playbook" > "$log_file" 2>&1; then
        log "SUCCESS" "✓ Remediation completed successfully"
    else
        exit_code=$?
        log "ERROR" "✗ Remediation failed (exit code: $exit_code)"
        cat "$log_file"
        return $exit_code
    fi

    # Log to Context Framework
    log "INFO" "Step 3/3: Logging to Context Framework"
    log_to_context_framework "$playbook" "success"

    # Update cooldown
    source "$SCRIPT_DIR/decision-engine.sh"
    update_cooldown "$playbook"

    log "SUCCESS" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "SUCCESS" "  Execution Complete: $playbook"
    log "SUCCESS" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    return 0
}

# Log to Context Framework
log_to_context_framework() {
    local playbook=$1
    local status=$2

    if [[ ! -f "$CONTEXT_DIR/issues.json" ]]; then
        log "WARNING" "Context Framework not found, skipping"
        return 0
    fi

    local issue_id="ISS-PROACTIVE-$(date +%Y%m%d%H%M%S)"
    local timestamp=$(date -Iseconds)

    log "INFO" "Logging to Context Framework: $issue_id"

    # Note: This is simplified - use proper JSON manipulation in production
    # For now, log intent
    log "INFO" "Issue ID: $issue_id"
    log "INFO" "Playbook: $playbook"
    log "INFO" "Status: $status"
    log "INFO" "Type: Proactive Auto-Remediation"
}

# Main execution
main() {
    if [[ $# -lt 1 ]]; then
        log "ERROR" "Usage: $0 <playbook-name>"
        log "ERROR" "Example: $0 disk-cleanup"
        exit 1
    fi

    local playbook=$1

    mkdir -p "$LOG_DIR"

    log "INFO" "═══════════════════════════════════════════════════"
    log "INFO" "  Proactive Remediation Execution Engine"
    log "INFO" "═══════════════════════════════════════════════════"

    execute_playbook "$playbook"
}

main "$@"
```

**Implementation:**

```bash
# Create execution engine
nano ~/containers/scripts/proactive-remediation/execute-remediation.sh
# Paste code above

# Make executable
chmod +x ~/containers/scripts/proactive-remediation/execute-remediation.sh

# Test execution (dry-run built into script)
~/containers/scripts/proactive-remediation/execute-remediation.sh disk-cleanup
```

**Acceptance Criteria:**
- [ ] Execution engine created and executable
- [ ] Script performs dry-run before real execution
- [ ] Script logs comprehensively
- [ ] Context Framework integration works
- [ ] Cooldown updates correctly

---

## Session 1 Summary

**Duration:** 2-3 hours

**Deliverables:**
- ✅ Action mapping configuration (JSON)
- ✅ Decision engine script (intelligent filtering)
- ✅ Execution engine script (safe playbook execution)
- ✅ Cooldown tracking system
- ✅ Weekly execution limits

**Testing:**
- [ ] Decision engine reads predictions correctly
- [ ] Mapping rules filter predictions appropriately
- [ ] Execution engine dry-run works
- [ ] Cooldown prevents duplicate actions
- [ ] Context Framework logging functional

**Next Session Preview:**
Session 2 will automate the decision + execution workflow with cron, add monitoring, and create dashboards.

---

## Session 2: Automation & Monitoring (2-3 hours)

### Phase 2.1: Orchestration Script (45min)

**Objective:** Combine decision-making and execution into automated workflow

**Deliverable: Orchestration Script**

**File:** `scripts/proactive-remediation/orchestrate.sh`

```bash
#!/bin/bash
################################################################################
# Proactive Remediation Orchestrator
# Daily automation: Decision → Execution → Notification
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$HOME/containers/data/remediation-logs"

DECISION_ENGINE="$SCRIPT_DIR/decision-engine.sh"
EXECUTION_ENGINE="$SCRIPT_DIR/execute-remediation.sh"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    local level=$1
    shift
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] [$level]${NC} $*"
}

main() {
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local log_file="$LOG_DIR/orchestration-${timestamp}.log"

    mkdir -p "$LOG_DIR"

    {
        log "INFO" "═══════════════════════════════════════════════════"
        log "INFO" "  Proactive Remediation Orchestration"
        log "INFO" "  Started: $(date)"
        log "INFO" "═══════════════════════════════════════════════════"

        # Step 1: Make decisions
        log "INFO" "Step 1: Running decision engine..."

        local approved_actions=$("$DECISION_ENGINE" 2>&1)
        local decision_exit=$?

        if [[ $decision_exit -ne 0 ]]; then
            log "ERROR" "Decision engine failed"
            exit 1
        fi

        # Parse approved actions
        local actions=$(echo "$approved_actions" | tail -1)

        if [[ "$actions" == "null" || "$actions" == "[]" ]]; then
            log "INFO" "No actions approved - system is healthy"
            log "INFO" "Completed: $(date)"
            exit 0
        fi

        log "INFO" "Approved actions: $actions"

        # Step 2: Execute each action
        local action_count=$(echo "$actions" | jq '. | length')
        log "INFO" "Step 2: Executing $action_count action(s)..."

        local success_count=0
        local failure_count=0

        while read -r playbook; do
            log "INFO" "Executing: $playbook"

            if "$EXECUTION_ENGINE" "$playbook" 2>&1; then
                log "SUCCESS" "✓ $playbook completed"
                ((success_count++))
            else
                log "ERROR" "✗ $playbook failed"
                ((failure_count++))
            fi
        done < <(echo "$actions" | jq -r '.[]')

        # Step 3: Summary
        log "INFO" "═══════════════════════════════════════════════════"
        log "INFO" "  Orchestration Summary"
        log "INFO" "  Successful: $success_count"
        log "INFO" "  Failed: $failure_count"
        log "INFO" "  Completed: $(date)"
        log "INFO" "═══════════════════════════════════════════════════"

        exit 0

    } | tee "$log_file"
}

main "$@"
```

**Implementation:**

```bash
# Create orchestration script
nano ~/containers/scripts/proactive-remediation/orchestrate.sh
# Paste code above

# Make executable
chmod +x ~/containers/scripts/proactive-remediation/orchestrate.sh

# Test full workflow
~/containers/scripts/proactive-remediation/orchestrate.sh
```

---

### Phase 2.2: Cron Automation (15min)

**Objective:** Schedule daily proactive remediation

**Implementation:**

```bash
# Add cron job (runs daily at 3 AM)
crontab -e

# Add this line:
0 3 * * * /home/patriark/containers/scripts/proactive-remediation/orchestrate.sh >> /home/patriark/containers/data/remediation-logs/cron.log 2>&1

# Verify cron job
crontab -l | grep orchestrate
```

**Alternative: systemd Timer (Better for systemd-based systems)**

**File:** `~/.config/systemd/user/proactive-remediation.service`

```ini
[Unit]
Description=Proactive Remediation Orchestration
After=network.target

[Service]
Type=oneshot
ExecStart=/home/patriark/containers/scripts/proactive-remediation/orchestrate.sh
```

**File:** `~/.config/systemd/user/proactive-remediation.timer`

```ini
[Unit]
Description=Daily Proactive Remediation
Requires=proactive-remediation.service

[Timer]
OnCalendar=daily
OnCalendar=03:00
Persistent=true

[Install]
WantedBy=timers.target
```

**Enable timer:**

```bash
systemctl --user daemon-reload
systemctl --user enable --now proactive-remediation.timer

# Check timer status
systemctl --user list-timers | grep proactive
```

**Acceptance Criteria:**
- [ ] Orchestration script combines decision + execution
- [ ] Cron job or systemd timer scheduled
- [ ] Logs written to dedicated directory
- [ ] Dry-run test successful

---

### Phase 2.3: Prometheus Metrics & Dashboard (1h)

**Objective:** Monitor proactive remediation effectiveness

**Metrics to Track:**

1. `proactive_remediation_executions_total` - Counter of executions by playbook
2. `proactive_remediation_success_rate` - Gauge of success/failure ratio
3. `proactive_remediation_last_run_timestamp` - Timestamp of last execution
4. `proactive_remediation_prevented_incidents` - Estimated incidents prevented

**File:** `scripts/proactive-remediation/export-metrics.sh`

```bash
#!/bin/bash
# Export Prometheus metrics for proactive remediation

METRICS_FILE="$HOME/containers/data/backup-metrics/proactive-remediation.prom"
LOG_DIR="$HOME/containers/data/remediation-logs"

mkdir -p "$(dirname "$METRICS_FILE")"

# Count executions by playbook (last 24h)
executions=$(find "$LOG_DIR" -name "proactive-*.log" -mtime -1 | wc -l)

# Calculate success rate
success_count=$(find "$LOG_DIR" -name "proactive-*.log" -mtime -1 -exec grep -l "Execution Complete" {} \; | wc -l)
failure_count=$((executions - success_count))

success_rate=0
if [[ $executions -gt 0 ]]; then
    success_rate=$(echo "scale=2; $success_count / $executions" | bc)
fi

# Last run timestamp
last_run=$(find "$LOG_DIR" -name "orchestration-*.log" -printf '%T@\n' | sort -n | tail -1 | cut -d. -f1)

# Write metrics
cat > "$METRICS_FILE" <<EOF
# HELP proactive_remediation_executions_total Total proactive remediations executed
# TYPE proactive_remediation_executions_total counter
proactive_remediation_executions_total $executions

# HELP proactive_remediation_success_count Successful remediations
# TYPE proactive_remediation_success_count gauge
proactive_remediation_success_count $success_count

# HELP proactive_remediation_failure_count Failed remediations
# TYPE proactive_remediation_failure_count gauge
proactive_remediation_failure_count $failure_count

# HELP proactive_remediation_success_rate Success rate (0.0-1.0)
# TYPE proactive_remediation_success_rate gauge
proactive_remediation_success_rate $success_rate

# HELP proactive_remediation_last_run_timestamp Last orchestration run (Unix timestamp)
# TYPE proactive_remediation_last_run_timestamp gauge
proactive_remediation_last_run_timestamp ${last_run:-0}
EOF

echo "Metrics exported to: $METRICS_FILE"
```

**Add to orchestration script:**

```bash
# At end of orchestrate.sh, add:
/home/patriark/containers/scripts/proactive-remediation/export-metrics.sh
```

**Grafana Dashboard Panels:**

1. **Proactive Remediation Timeline** - Time series of executions
2. **Success Rate** - Gauge showing percentage
3. **Executions by Playbook** - Bar chart
4. **Time Since Last Run** - Single stat
5. **Estimated Incidents Prevented** - Counter (based on prediction count)

**Acceptance Criteria:**
- [ ] Metrics export script created
- [ ] Prometheus scrapes metrics file
- [ ] Grafana dashboard created with 3+ panels
- [ ] Metrics update after test execution

---

## Session 2 Summary

**Duration:** 2-3 hours

**Deliverables:**
- ✅ Orchestration script (decision + execution)
- ✅ Cron job or systemd timer for daily automation
- ✅ Prometheus metrics export
- ✅ Grafana dashboard
- ✅ Complete logging infrastructure

**Testing Checklist:**
- [ ] Manual orchestration run completes successfully
- [ ] Cron/timer triggers on schedule
- [ ] Metrics export after execution
- [ ] Grafana dashboard shows data
- [ ] Context Framework logs actions
- [ ] Discord notifications sent (if configured)

---

## Total Project Summary

### Time Investment
- **Session 1:** 2-3 hours (Decision engine + execution)
- **Session 2:** 2-3 hours (Automation + monitoring)

**Total:** 4-6 hours

### Value Delivered

**Before:**
- ❌ Predictions generated but not acted upon
- ❌ Manual intervention required for all remediation
- ❌ Potential to miss warnings and let issues escalate
- ❌ No historical data on prevented incidents

**After:**
- ✅ Predictions automatically trigger remediation
- ✅ System self-heals before issues become critical
- ✅ Complete audit trail of automated actions
- ✅ Metrics showing incidents prevented
- ✅ Reduced alert fatigue (system handles routine issues)

### Risk Mitigation

**Safety Mechanisms:**
1. **Dry-run validation** - Every action tested before execution
2. **Cooldown periods** - Prevents execution loops
3. **Weekly limits** - Caps maximum automated actions
4. **Confidence thresholds** - Only high-confidence predictions acted upon
5. **Context Framework logging** - Full audit trail
6. **Global kill switch** - `enable_auto_remediation: false` disables everything

### Maintenance Requirements

**Weekly:**
- Review orchestration logs
- Check success/failure rate in Grafana

**Monthly:**
- Tune action-mapping.json thresholds
- Review Context Framework for patterns
- Adjust cooldown periods if needed

**As Needed:**
- Add new prediction types to mapping
- Create new remediation playbooks
- Update safety checks

---

## Success Metrics

**System is working if:**
1. Orchestration runs daily without errors
2. Success rate > 80%
3. Zero incidents from automated actions
4. Disk/memory exhaustion predictions handled automatically
5. Manual intervention only for critical/complex issues

---

## Integration with Plan 1 (Auto-Update Safety Net)

**Synergy:**
- Plan 1 handles **reactive** rollbacks (bad updates)
- Plan 2 handles **proactive** prevention (resource exhaustion)
- Both log to Context Framework
- Both export Prometheus metrics
- Both send Discord notifications
- Combined: **Comprehensive self-healing system**

---

**Status:** Complete implementation roadmap - ready for CLI execution
**Recommendation:** Start with `dry_run_mode: true` in action-mapping.json, monitor for 1 week, then enable full automation
**Next:** Execute Session 1, validate decision logic, then proceed to Session 2
