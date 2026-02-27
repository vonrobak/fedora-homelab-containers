#!/usr/bin/env bash
#
# autonomous-execute.sh - Autonomous Operations Executor
#
# Implements the ACT phase of the OODA loop.
# Executes approved actions with safety controls and logging.
#
# Usage:
#   ./autonomous-execute.sh                    # Execute pending actions
#   ./autonomous-execute.sh --action-id ID     # Execute specific action
#   ./autonomous-execute.sh --from-check       # Run check first, then execute
#   ./autonomous-execute.sh --dry-run          # Simulate execution
#   ./autonomous-execute.sh --status           # Show current status
#   ./autonomous-execute.sh --stop             # Emergency stop
#   ./autonomous-execute.sh --pause            # Pause operations
#   ./autonomous-execute.sh --resume           # Resume operations
#
# Exit codes:
#   0 - Success
#   1 - Execution had failures
#   2 - Error or paused/stopped
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINERS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONTEXT_DIR="$CONTAINERS_DIR/.claude/context"
STATE_FILE="$CONTEXT_DIR/autonomous-state.json"
DECISION_LOG="$CONTEXT_DIR/decision-log.json"
PREFERENCES="$CONTEXT_DIR/preferences.yml"

# Remediation playbooks
PLAYBOOK_DIR="$CONTAINERS_DIR/.claude/remediation/playbooks"
APPLY_REMEDIATION="$CONTAINERS_DIR/.claude/remediation/scripts/apply-remediation.sh"

# Backup script
BACKUP_SCRIPT="$SCRIPT_DIR/btrfs-snapshot-backup.sh"

# Check script
AUTONOMOUS_CHECK="$SCRIPT_DIR/autonomous-check.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Flags
DRY_RUN=false
FROM_CHECK=false
ACTION_ID=""
FORCE=false

# Circuit breaker settings
CIRCUIT_BREAKER_THRESHOLD=3
CIRCUIT_BREAKER_RESET_HOURS=24

# Discord webhook (from environment or file)
DISCORD_WEBHOOK="${DISCORD_WEBHOOK:-}"
if [[ -z "$DISCORD_WEBHOOK" && -f "$CONTAINERS_DIR/config/alertmanager/discord-webhook.txt" ]]; then
    DISCORD_WEBHOOK=$(cat "$CONTAINERS_DIR/config/alertmanager/discord-webhook.txt" 2>/dev/null || echo "")
fi

##############################################################################
# Argument Parsing
##############################################################################

# Command to run (set during argument parsing, executed after functions defined)
RUN_COMMAND=""

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --from-check)
                FROM_CHECK=true
                shift
                ;;
            --action-id)
                ACTION_ID="$2"
                shift 2
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --status)
                RUN_COMMAND="status"
                shift
                ;;
            --stop)
                RUN_COMMAND="stop"
                shift
                ;;
            --pause)
                RUN_COMMAND="pause"
                shift
                ;;
            --resume)
                RUN_COMMAND="resume"
                shift
                ;;
            --help|-h)
                cat << EOF
Usage: $0 [OPTIONS]

Autonomous operations executor - ACT phase of OODA loop.

Options:
  --dry-run          Simulate execution without making changes
  --from-check       Run autonomous-check.sh first, then execute
  --action-id ID     Execute specific action by ID
  --force            Force execution (bypass cooldowns)
  --status           Show current autonomous operations status
  --stop             Emergency stop all autonomous operations
  --pause            Pause operations (keep monitoring)
  --resume           Resume operations (reset circuit breaker)
  --help, -h         Show this help

Safety Controls:
  - Pre-action BTRFS snapshots
  - Circuit breaker (pauses after $CIRCUIT_BREAKER_THRESHOLD consecutive failures)
  - Cooldown periods between same action types
  - Service-specific overrides from preferences.yml

Exit Codes:
  0 - Success
  1 - Execution had failures
  2 - Error or paused/stopped
EOF
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                exit 2
                ;;
        esac
    done
}

# Parse arguments now, execute commands later
parse_args "$@"

##############################################################################
# Logging
##############################################################################

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case $level in
        INFO)    echo -e "${BLUE}[$timestamp INFO]${NC} $message" ;;
        SUCCESS) echo -e "${GREEN}[$timestamp SUCCESS]${NC} $message" ;;
        WARNING) echo -e "${YELLOW}[$timestamp WARNING]${NC} $message" ;;
        ERROR)   echo -e "${RED}[$timestamp ERROR]${NC} $message" ;;
        DEBUG)   echo -e "${CYAN}[$timestamp DEBUG]${NC} $message" ;;
    esac
}

##############################################################################
# State Management
##############################################################################

load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        cat "$STATE_FILE"
    else
        echo '{"enabled": true, "paused": false, "circuit_breaker": {"triggered": false, "consecutive_failures": 0}}'
    fi
}

save_state() {
    local state="$1"
    echo "$state" | jq '.' > "$STATE_FILE"
}

is_paused() {
    local state
    state=$(load_state)
    [[ "$(echo "$state" | jq -r '.paused // false')" == "true" ]]
}

is_circuit_breaker_triggered() {
    local state
    state=$(load_state)
    [[ "$(echo "$state" | jq -r '.circuit_breaker.triggered // false')" == "true" ]]
}

increment_failure() {
    local state
    state=$(load_state)

    local failures
    failures=$(echo "$state" | jq '.circuit_breaker.consecutive_failures + 1')

    local triggered=false
    if (( failures >= CIRCUIT_BREAKER_THRESHOLD )); then
        triggered=true
        log ERROR "Circuit breaker TRIGGERED after $failures consecutive failures"
        send_notification "Circuit Breaker Triggered" "Autonomous operations paused after $failures consecutive failures. Manual intervention required."
    fi

    state=$(echo "$state" | jq \
        --argjson failures "$failures" \
        --argjson triggered "$triggered" \
        --arg ts "$(date -Iseconds)" \
        '.circuit_breaker.consecutive_failures = $failures |
         .circuit_breaker.triggered = $triggered |
         .circuit_breaker.last_failure = $ts')

    save_state "$state"
}

reset_failure_count() {
    local state
    state=$(load_state)
    state=$(echo "$state" | jq '.circuit_breaker.consecutive_failures = 0')
    save_state "$state"
}

set_cooldown() {
    local action_type=$1
    local cooldown_seconds=$2

    local state
    state=$(load_state)

    local cooldown_end
    cooldown_end=$(date -d "+${cooldown_seconds} seconds" -Iseconds)

    state=$(echo "$state" | jq \
        --arg key "$action_type" \
        --arg val "$cooldown_end" \
        '.cooldowns[$key] = $val')

    save_state "$state"
}

is_on_cooldown() {
    local action_type=$1

    local state
    state=$(load_state)

    local cooldown_end
    cooldown_end=$(echo "$state" | jq -r ".cooldowns[\"$action_type\"] // \"\"")

    if [[ -n "$cooldown_end" && "$cooldown_end" != "null" ]]; then
        local cooldown_epoch current_epoch
        cooldown_epoch=$(date -d "$cooldown_end" +%s 2>/dev/null || echo 0)
        current_epoch=$(date +%s)

        if (( cooldown_epoch > current_epoch )); then
            return 0  # On cooldown
        fi
    fi

    return 1  # Not on cooldown
}

##############################################################################
# Control Commands
##############################################################################

show_status() {
    local state
    state=$(load_state)

    echo "=== Autonomous Operations Status ==="
    echo ""

    local enabled paused triggered failures last_check last_action
    enabled=$(echo "$state" | jq -r '.enabled // true')
    paused=$(echo "$state" | jq -r '.paused // false')
    triggered=$(echo "$state" | jq -r '.circuit_breaker.triggered // false')
    failures=$(echo "$state" | jq -r '.circuit_breaker.consecutive_failures // 0')
    last_check=$(echo "$state" | jq -r '.last_check // "never"')
    last_action=$(echo "$state" | jq -r '.last_action // "never"')

    echo "Enabled:          $enabled"
    echo "Paused:           $paused"
    echo "Circuit Breaker:  $triggered (failures: $failures/$CIRCUIT_BREAKER_THRESHOLD)"
    echo "Last Check:       $last_check"
    echo "Last Action:      $last_action"
    echo ""

    # Statistics
    echo "=== Statistics ==="
    local stats
    stats=$(echo "$state" | jq '.statistics // {}')
    echo "Total Checks:     $(echo "$stats" | jq -r '.total_checks // 0')"
    echo "Total Actions:    $(echo "$stats" | jq -r '.total_actions // 0')"
    echo "Success Rate:     $(echo "$stats" | jq -r '.success_rate // 1.0' | awk '{printf "%.1f%%", $1 * 100}')"
    echo ""

    # Active cooldowns
    echo "=== Active Cooldowns ==="
    local cooldowns
    cooldowns=$(echo "$state" | jq -r '.cooldowns // {}')
    if [[ "$cooldowns" == "{}" ]]; then
        echo "  (none)"
    else
        echo "$cooldowns" | jq -r 'to_entries[] | "  \(.key): \(.value)"'
    fi
    echo ""

    # Recent decisions
    echo "=== Recent Decisions (last 5) ==="
    if [[ -f "$DECISION_LOG" ]]; then
        jq -r '.decisions[-5:][] | "  [\(.timestamp)] \(.action_type): \(.outcome)"' "$DECISION_LOG" 2>/dev/null || echo "  (none)"
    else
        echo "  (none)"
    fi
}

emergency_stop() {
    log WARNING "EMERGENCY STOP activated"

    local state
    state=$(load_state)
    state=$(echo "$state" | jq \
        --arg ts "$(date -Iseconds)" \
        '.enabled = false | .paused = true | .emergency_stop = $ts')
    save_state "$state"

    send_notification "Emergency Stop" "Autonomous operations have been stopped. All automation is disabled."

    echo "Autonomous operations STOPPED"
    echo "To resume: $0 --resume"
}

pause_operations() {
    log INFO "Pausing autonomous operations"

    local state
    state=$(load_state)
    state=$(echo "$state" | jq '.paused = true')
    save_state "$state"

    echo "Autonomous operations PAUSED"
    echo "Monitoring continues, but no actions will be taken."
    echo "To resume: $0 --resume"
}

resume_operations() {
    log INFO "Resuming autonomous operations"

    local state
    state=$(load_state)
    state=$(echo "$state" | jq \
        '.enabled = true |
         .paused = false |
         .circuit_breaker.triggered = false |
         .circuit_breaker.consecutive_failures = 0 |
         del(.emergency_stop)')
    save_state "$state"

    echo "Autonomous operations RESUMED"
    echo "Circuit breaker reset."
}

##############################################################################
# Notification
##############################################################################

send_notification() {
    local title=$1
    local message=$2

    if [[ -z "$DISCORD_WEBHOOK" ]]; then
        log DEBUG "No Discord webhook configured, skipping notification"
        return
    fi

    local payload
    payload=$(jq -n \
        --arg title "$title" \
        --arg msg "$message" \
        '{
          embeds: [{
            title: ("Autonomous Operations: " + $title),
            description: $msg,
            color: 3447003,
            timestamp: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
          }]
        }')

    curl -s -X POST "$DISCORD_WEBHOOK" \
        -H "Content-Type: application/json" \
        -d "$payload" >/dev/null 2>&1 || true
}

##############################################################################
# Pre-Action Safety
##############################################################################

create_snapshot() {
    local operation=$1

    if $DRY_RUN; then
        log INFO "[DRY RUN] Would create snapshot for: $operation"
        return 0
    fi

    if [[ -x "$BACKUP_SCRIPT" ]]; then
        log INFO "Creating pre-action snapshot..."
        local snapshot_name="autonomous-${operation}-$(date +%Y%m%d-%H%M%S)"

        # Create snapshot of containers subvolume
        if "$BACKUP_SCRIPT" --tier 1 --subvolume containers --quiet 2>/dev/null; then
            log SUCCESS "Pre-action snapshot created"
            return 0
        else
            log WARNING "Failed to create snapshot, proceeding with caution"
            return 1
        fi
    else
        log WARNING "Backup script not found, skipping snapshot"
        return 0
    fi
}

##############################################################################
# Action Execution
##############################################################################

execute_disk_cleanup() {
    log INFO "Executing disk cleanup via remediation playbook..."

    if $DRY_RUN; then
        log INFO "[DRY RUN] Would execute: $APPLY_REMEDIATION --playbook disk-cleanup --log-to $DECISION_LOG"
        return 0
    fi

    # Check if remediation script exists
    if [[ ! -x "$APPLY_REMEDIATION" ]]; then
        log ERROR "Remediation script not found or not executable: $APPLY_REMEDIATION"
        return 1
    fi

    # Execute disk-cleanup playbook
    if "$APPLY_REMEDIATION" --playbook disk-cleanup --log-to "$DECISION_LOG" 2>&1 | tee -a "$LOG_FILE"; then
        log SUCCESS "Disk cleanup playbook completed successfully"
        return 0
    else
        log ERROR "Disk cleanup playbook failed"
        return 1
    fi
}

execute_service_restart() {
    local service=$1
    local cascade=${2:-false}  # Phase 3: cascade restart dependents
    local dep_graph="$CONTEXT_DIR/dependency-graph.json"

    log INFO "Restarting service: $service via remediation playbook..."

    # Phase 3: Check for dependent services (cascade restart logic)
    local blast_radius=0
    local dependents=()
    if [[ -f "$dep_graph" ]] && [[ "$cascade" == "true" ]]; then
        blast_radius=$(jq -r ".services[\"$service\"].blast_radius // 0" "$dep_graph" 2>/dev/null || echo "0")

        if (( blast_radius > 0 )); then
            log INFO "Service $service has blast radius of $blast_radius - checking dependents..."

            # Get list of dependent services
            mapfile -t dependents < <(jq -r ".services[\"$service\"].dependents[]? // empty" "$dep_graph" 2>/dev/null)

            if [[ ${#dependents[@]} -gt 0 ]]; then
                log WARNING "Service $service has ${#dependents[@]} dependent(s): ${dependents[*]}"
                log INFO "These services may need restart after $service recovers"
            fi
        fi
    fi

    if $DRY_RUN; then
        log INFO "[DRY RUN] Would execute: $APPLY_REMEDIATION --playbook service-restart --service $service --log-to $DECISION_LOG"

        if [[ ${#dependents[@]} -gt 0 ]] && [[ "$cascade" == "true" ]]; then
            for dependent in "${dependents[@]}"; do
                log INFO "[DRY RUN] Would cascade restart dependent: $dependent"
            done
        fi
        return 0
    fi

    # Check if remediation script exists
    if [[ ! -x "$APPLY_REMEDIATION" ]]; then
        log ERROR "Remediation script not found or not executable: $APPLY_REMEDIATION"
        return 1
    fi

    # Execute service-restart playbook
    if "$APPLY_REMEDIATION" --playbook service-restart --service "$service" --log-to "$DECISION_LOG" 2>&1 | tee -a "$LOG_FILE"; then
        log SUCCESS "Service restart playbook completed successfully for: $service"

        # Phase 3: Cascade restart dependents if requested
        if [[ ${#dependents[@]} -gt 0 ]] && [[ "$cascade" == "true" ]]; then
            log INFO "Cascade restarting ${#dependents[@]} dependent service(s)..."

            local cascade_success=true
            for dependent in "${dependents[@]}"; do
                log INFO "Cascade restarting dependent: $dependent"

                # Wait for primary service to be healthy before restarting dependents
                sleep 5

                # Recursively restart dependent (without further cascade to prevent infinite loops)
                if ! execute_service_restart "$dependent" "false"; then
                    log ERROR "Cascade restart failed for dependent: $dependent"
                    cascade_success=false
                fi
            done

            if [[ "$cascade_success" == "true" ]]; then
                log SUCCESS "Cascade restart completed successfully for all dependents"
            else
                log WARNING "Some cascade restarts failed - check logs"
            fi
        fi

        return 0
    else
        log ERROR "Service restart playbook failed for: $service"
        return 1
    fi
}

execute_drift_reconciliation() {
    log INFO "Reconciling configuration drift via remediation playbook..."

    if $DRY_RUN; then
        log INFO "[DRY RUN] Would execute: $APPLY_REMEDIATION --playbook drift-reconciliation --log-to $DECISION_LOG"
        return 0
    fi

    # Check if remediation script exists
    if [[ ! -x "$APPLY_REMEDIATION" ]]; then
        log WARNING "Remediation script not found, falling back to basic reconciliation"
        # Basic reconciliation: reload systemd
        systemctl --user daemon-reload
        log SUCCESS "Systemd reloaded (basic reconciliation)"
        return 0
    fi

    # Execute drift-reconciliation playbook
    if "$APPLY_REMEDIATION" --playbook drift-reconciliation --log-to "$DECISION_LOG" 2>&1 | tee -a "$LOG_FILE"; then
        log SUCCESS "Drift reconciliation playbook completed successfully"
        return 0
    else
        log ERROR "Drift reconciliation playbook failed"
        return 1
    fi
}

execute_action() {
    local action="$1"

    local action_id action_type service confidence risk decision
    action_id=$(echo "$action" | jq -r '.id')
    action_type=$(echo "$action" | jq -r '.type')
    service=$(echo "$action" | jq -r '.service // ""')
    confidence=$(echo "$action" | jq -r '.confidence')
    risk=$(echo "$action" | jq -r '.risk')
    decision=$(echo "$action" | jq -r '.decision')

    log INFO "=========================================="
    log INFO "Action: $action_id"
    log INFO "Type: $action_type"
    [[ -n "$service" ]] && log INFO "Service: $service"
    log INFO "Confidence: $(awk "BEGIN {printf \"%.0f%%\", $confidence * 100}")"
    log INFO "Risk: $risk"
    log INFO "Decision: $decision"
    log INFO "=========================================="

    # Check decision type
    case "$decision" in
        auto-execute|notify-execute)
            # Proceed with execution
            ;;
        queue)
            log INFO "Action queued for approval, skipping"
            return 0
            ;;
        alert-only)
            log INFO "Alert-only action, skipping execution"
            return 0
            ;;
        *)
            log WARNING "Unknown decision type: $decision"
            return 0
            ;;
    esac

    # Check cooldown
    local cooldown_key="$action_type"
    [[ -n "$service" ]] && cooldown_key="${service}.${action_type}"

    if ! $FORCE && is_on_cooldown "$cooldown_key"; then
        log INFO "Action on cooldown, skipping"
        return 0
    fi

    # Create pre-action snapshot
    create_snapshot "$action_type" || true

    # Notify if required
    if [[ "$decision" == "notify-execute" ]]; then
        send_notification "Executing Action" "Type: $action_type\nService: ${service:-N/A}\nConfidence: $(awk "BEGIN {printf \"%.0f%%\", $confidence * 100}")"
    fi

    # Execute
    local start_time outcome details duration
    start_time=$(date +%s)
    outcome="success"
    details=""

    case "$action_type" in
        disk-cleanup)
            if execute_disk_cleanup; then
                details="Disk cleanup completed"
            else
                outcome="failure"
                details="Disk cleanup failed"
            fi
            ;;
        service-restart)
            if [[ -z "$service" ]]; then
                outcome="failure"
                details="No service specified"
            else
                # Phase 3: Determine if cascade restart should be enabled
                # Enable cascade if dep_safety_score is high (>0.8) and blast_radius > 0
                local dep_safety_score
                dep_safety_score=$(echo "$action" | jq -r '.dep_safety_score // 1.0')
                local enable_cascade="false"

                if (( $(awk "BEGIN {print ($dep_safety_score >= 0.8)}") )); then
                    enable_cascade="true"
                    log INFO "Dep safety score $dep_safety_score >= 0.8 - enabling cascade restart"
                else
                    log INFO "Dep safety score $dep_safety_score < 0.8 - cascade restart disabled"
                fi

                if execute_service_restart "$service" "$enable_cascade"; then
                    details="Service $service restarted (cascade: $enable_cascade)"
                else
                    outcome="failure"
                    details="Failed to restart $service"
                fi
            fi
            ;;
        drift-reconciliation)
            if execute_drift_reconciliation; then
                details="Drift reconciliation completed"
            else
                outcome="failure"
                details="Drift reconciliation failed"
            fi
            ;;
        *)
            log WARNING "Unknown action type: $action_type"
            outcome="skipped"
            details="Unknown action type"
            ;;
    esac

    duration=$(($(date +%s) - start_time))

    # Log decision
    log_decision "$action" "$outcome" "$details" "$duration"

    # Update counters
    if [[ "$outcome" == "success" ]]; then
        reset_failure_count
        log SUCCESS "$details (${duration}s)"
    else
        increment_failure
        log ERROR "$details"
    fi

    # Set cooldown
    local cooldown_seconds=300  # Default 5 minutes
    case "$action_type" in
        disk-cleanup) cooldown_seconds=3600 ;;  # 1 hour
        service-restart) cooldown_seconds=300 ;; # 5 minutes
        drift-reconciliation) cooldown_seconds=900 ;; # 15 minutes
    esac
    set_cooldown "$cooldown_key" "$cooldown_seconds"

    [[ "$outcome" == "success" ]]
}

log_decision() {
    local action="$1"
    local outcome="$2"
    local details="$3"
    local duration="$4"

    local entry
    entry=$(cat << EOF
{
  "id": "decision-$(date +%Y%m%d%H%M%S)-$RANDOM",
  "timestamp": "$(date -Iseconds)",
  "action_type": $(echo "$action" | jq '.type'),
  "action_id": $(echo "$action" | jq '.id'),
  "service": $(echo "$action" | jq '.service // null'),
  "trigger": $(echo "$action" | jq '.reason'),
  "confidence": $(echo "$action" | jq '.confidence'),
  "risk": $(echo "$action" | jq '.risk'),
  "decision": $(echo "$action" | jq '.decision'),
  "outcome": "$outcome",
  "details": "$details",
  "duration_seconds": $duration
}
EOF
    )

    # Update decision log
    if [[ -f "$DECISION_LOG" ]]; then
        local updated
        updated=$(jq --argjson entry "$entry" '.decisions += [$entry]' "$DECISION_LOG")
        echo "$updated" > "$DECISION_LOG"
    fi

    # Update state statistics
    local state
    state=$(load_state)
    state=$(echo "$state" | jq \
        --arg ts "$(date -Iseconds)" \
        '.last_action = $ts | .statistics.total_actions += 1')

    if [[ "$outcome" == "success" ]]; then
        state=$(echo "$state" | jq '.statistics.success_count += 1')
    else
        state=$(echo "$state" | jq '.statistics.failure_count += 1')
    fi

    # Recalculate success rate
    local success_count total_actions
    success_count=$(echo "$state" | jq '.statistics.success_count // 0')
    total_actions=$(echo "$state" | jq '.statistics.total_actions // 1')
    state=$(echo "$state" | jq \
        --argjson rate "$(awk "BEGIN {printf \"%.2f\", $success_count / $total_actions}")" \
        '.statistics.success_rate = $rate')

    save_state "$state"

    # Log successful actions to issue history
    if [[ "$outcome" == "success" ]]; then
        log_issue_to_context "$action" "$details"
    fi
}

log_issue_to_context() {
    local action="$1"
    local details="$2"
    local context_script="$HOME/containers/.claude/context/scripts/append-issue.sh"

    # Skip if context logging not available
    if [[ ! -x "$context_script" ]]; then
        return 0
    fi

    # Extract action details
    local action_type=$(echo "$action" | jq -r '.type')
    local action_service=$(echo "$action" | jq -r '.service // "system"')
    local action_reason=$(echo "$action" | jq -r '.reason')

    # Generate issue ID (AUTO-YYYYMMDD format)
    local issue_id="AUTO-$(date +%Y%m%d)"

    # Map action type to category and title
    local category="operations"
    local title=""
    local description=""
    local severity="medium"

    case "$action_type" in
        disk-cleanup)
            category="disk-space"
            title="Automated disk cleanup executed"
            description="$action_reason. Autonomous operations executed disk cleanup playbook."
            severity="medium"
            ;;
        service-restart)
            category="operations"
            title="Automated service restart: $action_service"
            description="$action_reason. Autonomous operations restarted service."
            severity="low"
            ;;
        drift-reconciliation)
            category="deployment"
            title="Automated drift reconciliation: $action_service"
            description="$action_reason. Autonomous operations reconciled configuration drift."
            severity="medium"
            ;;
        *)
            category="operations"
            title="Automated action: $action_type"
            description="$action_reason. Details: $details"
            severity="low"
            ;;
    esac

    # Log to context (suppress errors - non-critical)
    "$context_script" \
        "$issue_id" \
        "$title" \
        "$category" \
        "$severity" \
        "$(date +%Y-%m-%d)" \
        "$description" \
        "Executed successfully via autonomous operations (OODA loop)" \
        "resolved" 2>/dev/null || true
}

##############################################################################
# Pre-Check Gate (skip expensive assessment when system is healthy)
##############################################################################

signals_all_clear() {
    # Check 1: Did predictive-maintenance find anything critical?
    # Match the healthy message positively — the log contains "No critical predictions"
    # on healthy days, so grepping for "critical" would false-match every time.
    local pred_log
    pred_log=$(find "$CONTAINERS_DIR/.claude/data/remediation-logs/" \
        -name "predictive-maintenance-*.log" -printf '%T@ %p\n' 2>/dev/null \
        | sort -rn | head -1 | cut -d' ' -f2-)

    # No log at all = no data to trust, fall through to drift/alert checks
    if [[ -n "$pred_log" ]]; then
        # Reject stale logs (>36h) — if the timer failed to run, don't trust old data
        local log_age_ok
        log_age_ok=$(find "$pred_log" -mmin -2160 -print -quit 2>/dev/null)
        if [[ -z "$log_age_ok" ]]; then
            log INFO "Pre-check: predictive maintenance log is stale (>36h), running full assessment"
            return 1
        fi
        if ! grep -q "No critical predictions\|System healthy\|no_action_required" "$pred_log" 2>/dev/null; then
            log INFO "Pre-check: predictive maintenance flagged issues"
            return 1
        fi
    fi

    # Check 2: Did daily-drift-check detect drift?
    # Read the digest JSON if available (written by daily-drift-check.sh),
    # fall back to journalctl if the file doesn't exist yet
    local drift_status="0"
    if [[ -f /tmp/daily-digest/drift-check.json ]]; then
        local drift_json_status
        drift_json_status=$(jq -r '.status // "ok"' /tmp/daily-digest/drift-check.json 2>/dev/null || echo "ok")
        if [[ "$drift_json_status" == "drift_detected" ]]; then
            drift_status="1"
        fi
    else
        drift_status=$(journalctl --user -u daily-drift-check.service --since "2 hours ago" --no-pager 2>/dev/null \
            | grep -c "Drift detected\|✗ DRIFT" || echo "0")
    fi

    if [[ "$drift_status" -gt 0 ]]; then
        log INFO "Pre-check: drift detected in recent drift check"
        return 1
    fi

    # Check 3: Are any alerts currently firing in Alertmanager?
    local firing
    firing=$(curl -sf http://localhost:9093/api/v2/alerts 2>/dev/null \
        | python3 -c "import sys,json; alerts=json.load(sys.stdin); print(sum(1 for a in alerts if a.get('status',{}).get('state')=='active'))" 2>/dev/null \
        || echo "unknown")

    if [[ "$firing" == "unknown" ]]; then
        log INFO "Pre-check: Alertmanager unreachable, running full assessment to be safe"
        return 1
    fi
    if [[ "$firing" != "0" ]]; then
        log INFO "Pre-check: $firing alert(s) currently firing"
        return 1
    fi

    # All signals clear
    return 0
}

##############################################################################
# Main
##############################################################################

main() {
    # Check safety conditions
    if is_paused; then
        log WARNING "Autonomous operations are PAUSED"
        echo "Use '$0 --resume' to resume operations"
        exit 2
    fi

    if is_circuit_breaker_triggered; then
        log ERROR "Circuit breaker is TRIGGERED"
        echo "Manual intervention required. Use '$0 --resume' to reset."
        exit 2
    fi

    # Get actions to execute
    local actions='[]'

    if $FROM_CHECK; then
        # Pre-check gate: skip expensive assessment when all signals are clear
        if ! $FORCE && signals_all_clear; then
            log INFO "All signals clear (no predictions, no drift, no alerts) — skipping full assessment"
            DIGEST_DIR="/tmp/daily-digest"
            mkdir -p "$DIGEST_DIR"
            cat > "$DIGEST_DIR/autonomous-ops.json" <<EOF
{"status": "ok", "actions_taken": 0, "skipped_reason": "all_signals_clear"}
EOF
            exit 0
        fi

        log INFO "Running autonomous check first..."
        local check_output
        check_output=$("$AUTONOMOUS_CHECK" --json 2>/dev/null || echo '{"recommended_actions": []}')
        actions=$(echo "$check_output" | jq '.recommended_actions // []')
    elif [[ -n "$ACTION_ID" ]]; then
        # Execute specific action from state
        local state
        state=$(load_state)
        actions=$(echo "$state" | jq --arg id "$ACTION_ID" '[.pending_actions[] | select(.id == $id)]')
    else
        # Get pending actions from state
        local state
        state=$(load_state)
        actions=$(echo "$state" | jq '.pending_actions // []')

        if [[ "$actions" == "[]" ]]; then
            log INFO "No pending actions. Running check..."
            local check_output
            check_output=$("$AUTONOMOUS_CHECK" --json 2>/dev/null || echo '{"recommended_actions": []}')
            actions=$(echo "$check_output" | jq '.recommended_actions // []')
        fi
    fi

    local action_count
    action_count=$(echo "$actions" | jq 'length')

    # Write status to daily digest directory (consolidated Discord notification)
    DIGEST_DIR="/tmp/daily-digest"
    mkdir -p "$DIGEST_DIR"

    if (( action_count == 0 )); then
        log INFO "No actions to execute"
        cat > "$DIGEST_DIR/autonomous-ops.json" <<EOF
{"status": "ok", "actions_taken": 0}
EOF
        exit 0
    fi

    log INFO "Found $action_count action(s) to evaluate"

    # Execute actions
    local success_count=0
    local failure_count=0

    local i=0
    while (( i < action_count )); do
        local action
        action=$(echo "$actions" | jq ".[$i]")

        if execute_action "$action"; then
            ((success_count++)) || true
        else
            ((failure_count++)) || true
        fi

        ((i++)) || true

        # Check circuit breaker after each action
        if is_circuit_breaker_triggered; then
            log ERROR "Circuit breaker triggered, stopping execution"
            break
        fi
    done

    echo ""
    log INFO "=========================================="
    log INFO "Execution Summary"
    log INFO "  Total:    $action_count"
    log INFO "  Success:  $success_count"
    log INFO "  Failures: $failure_count"
    log INFO "=========================================="

    # Write digest status
    cat > "$DIGEST_DIR/autonomous-ops.json" <<EOF
{"status": "$([ "$failure_count" -gt 0 ] && echo "failures" || echo "executed")", "actions_taken": $action_count, "success": $success_count, "failures": $failure_count}
EOF

    if (( failure_count > 0 )); then
        exit 1
    fi

    exit 0
}

# Dispatch based on RUN_COMMAND (set during argument parsing)
case "$RUN_COMMAND" in
    status)
        show_status
        exit 0
        ;;
    stop)
        emergency_stop
        exit 0
        ;;
    pause)
        pause_operations
        exit 0
        ;;
    resume)
        resume_operations
        exit 0
        ;;
    *)
        main
        ;;
esac
