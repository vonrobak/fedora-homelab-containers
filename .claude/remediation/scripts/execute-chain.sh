#!/usr/bin/env bash
#
# execute-chain.sh - Multi-Playbook Chain Orchestration Engine
# Part of Phase 5: Advanced Orchestration
#
# Executes sequences of remediation playbooks with:
# - Sequential execution with timeouts
# - Conditional playbook execution
# - Failure strategy handling (continue-on-error, stop-on-failure, rollback, skip)
# - State management for resume capability
# - Chain-level metrics and reporting
#
# Usage:
#   execute-chain.sh --chain <chain-name> [options]
#   execute-chain.sh --list-chains
#   execute-chain.sh --resume <chain-execution-id>
#
# Options:
#   --chain <name>           Chain to execute (from .claude/remediation/chains/*.yml)
#   --dry-run                Show execution plan without running
#   --force                  Skip confirmation prompts
#   --resume <id>            Resume failed/interrupted chain execution
#   --list-chains            List available chains
#   --validate <chain>       Validate chain configuration
#   --verbose                Enable verbose logging
#   --help                   Show this help message

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMEDIATION_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CHAINS_DIR="$REMEDIATION_DIR/chains"
STATE_DIR="$REMEDIATION_DIR/state"
PLAYBOOK_SCRIPT="$SCRIPT_DIR/apply-remediation.sh"

# Ensure state directory exists
mkdir -p "$STATE_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Logging
VERBOSE=false
DRY_RUN=false
FORCE=false

# ==============================================================================
# LOGGING FUNCTIONS
# ==============================================================================

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_verbose() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${CYAN}[VERBOSE]${NC} $*"
    fi
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
    echo -e "${RED}✗${NC} $*" >&2
}

log_step() {
    echo -e "${MAGENTA}▸${NC} $*"
}

# ==============================================================================
# CHAIN LOADING AND PARSING
# ==============================================================================

# Load chain YAML configuration
load_chain() {
    local chain_name="$1"
    local chain_file="$CHAINS_DIR/${chain_name}.yml"

    if [ ! -f "$chain_file" ]; then
        log_error "Chain not found: $chain_name"
        log_error "Available chains:"
        list_chains
        exit 1
    fi

    log_verbose "Loading chain from: $chain_file"

    # Export chain file path for yq queries
    export CHAIN_FILE="$chain_file"

    # Validate chain has required fields
    if ! yq eval '.name' "$chain_file" >/dev/null 2>&1; then
        log_error "Invalid chain file: missing 'name' field"
        exit 1
    fi
}

# Get chain metadata
get_chain_field() {
    local field="$1"
    local default="${2:-}"

    local value
    value=$(yq eval ".$field" "$CHAIN_FILE" 2>/dev/null)

    if [ "$value" = "null" ] || [ -z "$value" ]; then
        echo "$default"
    else
        echo "$value"
    fi
}

# Get number of playbooks in chain
get_playbook_count() {
    yq eval '.playbooks | length' "$CHAIN_FILE"
}

# Get playbook field by index
get_playbook_field() {
    local index="$1"
    local field="$2"
    local default="${3:-}"

    local value
    value=$(yq eval ".playbooks[$index].$field" "$CHAIN_FILE" 2>/dev/null)

    if [ "$value" = "null" ] || [ -z "$value" ]; then
        echo "$default"
    else
        echo "$value"
    fi
}

# ==============================================================================
# CHAIN VALIDATION
# ==============================================================================

validate_chain() {
    local chain_name="$1"

    log "Validating chain: $chain_name"

    load_chain "$chain_name"

    local errors=0

    # Check required fields
    local name description risk_level
    name=$(get_chain_field "name")
    description=$(get_chain_field "description")
    risk_level=$(get_chain_field "risk_level")

    if [ -z "$name" ]; then
        log_error "Missing required field: name"
        ((errors++))
    fi

    if [ -z "$description" ]; then
        log_error "Missing required field: description"
        ((errors++))
    fi

    if [ -z "$risk_level" ]; then
        log_error "Missing required field: risk_level"
        ((errors++))
    fi

    # Validate playbooks
    local playbook_count
    playbook_count=$(get_playbook_count)

    if [ "$playbook_count" -eq 0 ]; then
        log_error "Chain has no playbooks defined"
        ((errors++))
    fi

    log "Chain has $playbook_count playbook(s)"

    # Validate each playbook
    for ((i=0; i<playbook_count; i++)); do
        local pb_name timeout on_failure
        pb_name=$(get_playbook_field "$i" "name")
        timeout=$(get_playbook_field "$i" "timeout" "300")
        on_failure=$(get_playbook_field "$i" "on_failure" "stop")

        if [ -z "$pb_name" ]; then
            log_error "Playbook $i: missing 'name' field"
            ((errors++))
            continue
        fi

        # Check if playbook exists in apply-remediation.sh
        # Output format: "1. disk-cleanup - Description"
        if ! "$PLAYBOOK_SCRIPT" --list-playbooks 2>/dev/null | grep -oP '^\d+\.\s+\K[a-z-]+' | grep -q "^$pb_name$"; then
            log_error "Playbook $i: unknown playbook '$pb_name'"
            ((errors++))
        else
            log_success "Playbook $((i+1)): $pb_name (timeout: ${timeout}s, on_failure: $on_failure)"
        fi
    done

    if [ $errors -eq 0 ]; then
        log_success "Chain validation passed"
        return 0
    else
        log_error "Chain validation failed with $errors error(s)"
        return 1
    fi
}

# ==============================================================================
# CONDITION EVALUATION
# ==============================================================================

# Check if memory pressure exists
check_memory_pressure() {
    # Check if available memory < 20% OR swap usage > 80%
    local mem_available swap_total swap_used

    mem_available=$(free | awk '/^Mem:/ {print ($7/$2)*100}')
    swap_total=$(free | awk '/^Swap:/ {print $2}')
    swap_used=$(free | awk '/^Swap:/ {print $3}')

    if (( $(echo "$mem_available < 20" | bc -l) )); then
        log_verbose "Memory pressure detected: ${mem_available}% available"
        return 0
    fi

    if [ "$swap_total" -gt 0 ]; then
        local swap_pct=$((swap_used * 100 / swap_total))
        if [ "$swap_pct" -gt 80 ]; then
            log_verbose "Memory pressure detected: ${swap_pct}% swap used"
            return 0
        fi
    fi

    log_verbose "No memory pressure detected (${mem_available}% memory available)"
    return 1
}

# Check if disk exhaustion predicted
check_disk_prediction() {
    # Check if predictive-maintenance found critical disk prediction
    # This would be set by previous playbook in chain
    if [ -f "$STATE_DIR/disk_prediction_critical" ]; then
        log_verbose "Disk exhaustion prediction: CRITICAL"
        return 0
    fi

    log_verbose "Disk exhaustion prediction: OK"
    return 1
}

# Check if memory exhaustion predicted
check_memory_prediction() {
    if [ -f "$STATE_DIR/memory_prediction_critical" ]; then
        log_verbose "Memory exhaustion prediction: CRITICAL"
        return 0
    fi

    log_verbose "Memory exhaustion prediction: OK"
    return 1
}

# Evaluate condition (returns 0 if condition passes, 1 if fails)
evaluate_condition() {
    local condition="$1"

    if [ -z "$condition" ]; then
        return 0  # No condition = always pass
    fi

    log_verbose "Evaluating condition: $condition"

    # Map condition string to function call
    case "$condition" in
        "memory_pressure_detected")
            check_memory_pressure
            ;;
        "disk_exhaustion_predicted")
            check_disk_prediction
            ;;
        "memory_exhaustion_predicted")
            check_memory_prediction
            ;;
        *)
            log_warning "Unknown condition: $condition (assuming false)"
            return 1
            ;;
    esac
}

# ==============================================================================
# STATE MANAGEMENT
# ==============================================================================

# Create new chain execution state
create_execution_state() {
    local chain_name="$1"

    # Generate unique execution ID
    local exec_id="${chain_name}_$(date +%s)"
    local state_file="$STATE_DIR/${exec_id}.json"

    # Initialize state
    jq -n \
        --arg chain "$chain_name" \
        --arg exec_id "$exec_id" \
        --argjson start_time "$(date +%s)" \
        '{
            chain: $chain,
            execution_id: $exec_id,
            start_time: $start_time,
            status: "running",
            playbooks_completed: [],
            playbooks_failed: [],
            playbooks_skipped: [],
            current_playbook_index: 0,
            total_playbooks: 0,
            metadata: {}
        }' > "$state_file"

    echo "$exec_id"
}

# Update execution state
update_execution_state() {
    local exec_id="$1"
    local field="$2"
    local value="$3"

    local state_file="$STATE_DIR/${exec_id}.json"

    if [ ! -f "$state_file" ]; then
        log_error "State file not found: $state_file"
        return 1
    fi

    # Update field
    jq --arg field "$field" --arg value "$value" \
        '.[$field] = $value' \
        "$state_file" > "${state_file}.tmp" && mv "${state_file}.tmp" "$state_file"
}

# Add playbook result to state
add_playbook_result() {
    local exec_id="$1"
    local playbook_name="$2"
    local status="$3"  # completed, failed, skipped

    local state_file="$STATE_DIR/${exec_id}.json"

    local field
    case "$status" in
        "completed") field="playbooks_completed" ;;
        "failed") field="playbooks_failed" ;;
        "skipped") field="playbooks_skipped" ;;
        *) log_error "Unknown status: $status"; return 1 ;;
    esac

    jq --arg field "$field" --arg playbook "$playbook_name" \
        '.[$field] += [$playbook]' \
        "$state_file" > "${state_file}.tmp" && mv "${state_file}.tmp" "$state_file"
}

# Mark chain execution complete
mark_execution_complete() {
    local exec_id="$1"
    local final_status="$2"  # success, failed, aborted

    local state_file="$STATE_DIR/${exec_id}.json"
    local end_time
    end_time=$(date +%s)

    jq --arg status "$final_status" --argjson end_time "$end_time" \
        '.status = $status | .end_time = $end_time' \
        "$state_file" > "${state_file}.tmp" && mv "${state_file}.tmp" "$state_file"
}

# ==============================================================================
# PLAYBOOK EXECUTION
# ==============================================================================

# Execute a single playbook with timeout
execute_playbook() {
    local playbook_name="$1"
    local timeout="$2"
    local parameters="$3"

    log_step "Executing playbook: $playbook_name (timeout: ${timeout}s)"

    if [ "$DRY_RUN" = true ]; then
        log "DRY RUN: Would execute: $PLAYBOOK_SCRIPT --playbook $playbook_name $parameters"
        return 0
    fi

    # Build command
    local cmd="$PLAYBOOK_SCRIPT --playbook $playbook_name"
    if [ -n "$parameters" ]; then
        cmd="$cmd $parameters"
    fi

    # Execute with timeout
    local start_time end_time duration
    start_time=$(date +%s)

    if timeout "$timeout" bash -c "$cmd"; then
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        log_success "Playbook completed in ${duration}s"
        return 0
    else
        local exit_code=$?
        end_time=$(date +%s)
        duration=$((end_time - start_time))

        if [ $exit_code -eq 124 ]; then
            log_error "Playbook timed out after ${timeout}s"
        else
            log_error "Playbook failed with exit code $exit_code (duration: ${duration}s)"
        fi
        return $exit_code
    fi
}

# ==============================================================================
# CHAIN EXECUTION
# ==============================================================================

execute_chain() {
    local chain_name="$1"

    log ""
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "  Chain Execution: $chain_name"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log ""

    # Load chain configuration
    load_chain "$chain_name"

    # Extract metadata
    local description risk_level requires_confirmation max_duration
    description=$(get_chain_field "description")
    risk_level=$(get_chain_field "risk_level" "medium")
    requires_confirmation=$(get_chain_field "requires_confirmation" "no")
    max_duration=$(get_chain_field "max_duration" "3600")

    log "Description: $description"
    log "Risk Level: $risk_level"
    log "Max Duration: ${max_duration}s"
    log ""

    # Confirmation check
    if [ "$requires_confirmation" = "yes" ] && [ "$FORCE" = false ]; then
        echo -e "${YELLOW}⚠ This chain requires confirmation (risk level: $risk_level)${NC}"
        read -rp "Proceed with execution? [y/N] " -n 1
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Chain execution cancelled by user"
            exit 0
        fi
    fi

    # Create execution state
    local exec_id
    exec_id=$(create_execution_state "$chain_name")
    log "Execution ID: $exec_id"
    log ""

    # Get playbook count
    local playbook_count
    playbook_count=$(get_playbook_count)

    # Update state with total playbooks
    update_execution_state "$exec_id" "total_playbooks" "$playbook_count"

    # Chain start time
    local chain_start_time
    chain_start_time=$(date +%s)

    # Execute playbooks sequentially
    local success=0
    local failures=0
    local skipped=0

    for ((i=0; i<playbook_count; i++)); do
        local pb_name timeout on_failure condition parameters priority description

        pb_name=$(get_playbook_field "$i" "name")
        timeout=$(get_playbook_field "$i" "timeout" "300")
        on_failure=$(get_playbook_field "$i" "on_failure" "stop")
        condition=$(get_playbook_field "$i" "condition" "")
        priority=$(get_playbook_field "$i" "priority" "$((i+1))")
        description=$(get_playbook_field "$i" "description" "")

        # Build parameters from playbook.parameters (if exists)
        parameters=""
        local param_count
        param_count=$(yq eval ".playbooks[$i].parameters | length" "$CHAIN_FILE" 2>/dev/null || echo 0)

        if [ "$param_count" -gt 0 ]; then
            # Extract parameters as key=value pairs
            while IFS= read -r line; do
                if [ -n "$line" ]; then
                    parameters="$parameters --$line"
                fi
            done < <(yq eval ".playbooks[$i].parameters | to_entries | .[] | .key + \" \" + .value" "$CHAIN_FILE" 2>/dev/null)
        fi

        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log "Playbook $((i+1))/$playbook_count: $pb_name"
        if [ -n "$description" ]; then
            log "Description: $description"
        fi
        log "Priority: $priority | Timeout: ${timeout}s | On Failure: $on_failure"
        if [ -n "$condition" ]; then
            log "Condition: $condition"
        fi
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log ""

        # Update current playbook index
        update_execution_state "$exec_id" "current_playbook_index" "$i"

        # Evaluate condition
        if [ -n "$condition" ]; then
            if ! evaluate_condition "$condition"; then
                log_warning "Condition not met: $condition"
                log "Skipping playbook: $pb_name"
                log ""
                add_playbook_result "$exec_id" "$pb_name" "skipped"
                skipped=$((skipped + 1))
                continue
            else
                log_success "Condition met: $condition"
            fi
        fi

        # Check max chain duration
        local elapsed=$(($(date +%s) - chain_start_time))
        if [ $elapsed -ge "$max_duration" ]; then
            log_error "Chain max duration exceeded (${max_duration}s)"
            log "Aborting remaining playbooks"
            mark_execution_complete "$exec_id" "aborted"
            exit 1
        fi

        # Execute playbook
        if execute_playbook "$pb_name" "$timeout" "$parameters"; then
            log_success "Playbook succeeded: $pb_name"
            add_playbook_result "$exec_id" "$pb_name" "completed"
            success=$((success + 1))
            log_verbose "DEBUG: After success increment, continuing to next playbook"
        else
            log_error "Playbook failed: $pb_name"
            add_playbook_result "$exec_id" "$pb_name" "failed"
            failures=$((failures + 1))

            # Handle failure strategy
            case "$on_failure" in
                "continue")
                    log_warning "Failure strategy: continue-on-error"
                    log "Continuing to next playbook..."
                    ;;
                "skip")
                    log_warning "Failure strategy: skip"
                    log "Skipping to next playbook..."
                    ;;
                "abort")
                    log_error "Failure strategy: abort"
                    log "Aborting chain execution"
                    mark_execution_complete "$exec_id" "aborted"
                    exit 1
                    ;;
                "rollback")
                    log_error "Failure strategy: rollback"
                    log "Rollback not yet implemented (would restore BTRFS snapshot)"
                    mark_execution_complete "$exec_id" "failed"
                    exit 1
                    ;;
                "stop")
                    log_error "Failure strategy: stop-on-failure"
                    log "Stopping chain execution"
                    mark_execution_complete "$exec_id" "failed"
                    exit 1
                    ;;
                *)
                    log_error "Unknown failure strategy: $on_failure"
                    log "Stopping chain execution"
                    mark_execution_complete "$exec_id" "failed"
                    exit 1
                    ;;
            esac
        fi

        log ""
        log_verbose "DEBUG: End of playbook $((i+1)), proceeding to next iteration"
    done

    log_verbose "DEBUG: Loop completed, all playbooks processed"

    # Chain execution complete
    local chain_end_time
    chain_end_time=$(date +%s)
    local total_duration=$((chain_end_time - chain_start_time))

    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "  Chain Execution Complete"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log ""
    log "Total Duration: ${total_duration}s"
    log "Playbooks Completed: $success"
    log "Playbooks Failed: $failures"
    log "Playbooks Skipped: $skipped"
    log ""

    # Determine final status
    local final_status
    if [ $failures -eq 0 ]; then
        final_status="success"
        log_success "Chain completed successfully"
    else
        final_status="failed"
        log_error "Chain completed with failures"
    fi

    mark_execution_complete "$exec_id" "$final_status"

    # Write chain-level metrics
    write_chain_metrics "$exec_id" "$chain_name" "$final_status" "$total_duration" "$success" "$failures" "$skipped"

    log ""
    log "Execution state saved: $STATE_DIR/${exec_id}.json"

    # Return exit code based on failures
    if [ $failures -gt 0 ]; then
        return 1
    else
        return 0
    fi
}

# ==============================================================================
# METRICS
# ==============================================================================

write_chain_metrics() {
    local exec_id="$1"
    local chain_name="$2"
    local status="$3"
    local duration="$4"
    local success_count="$5"
    local failure_count="$6"
    local skipped_count="$7"

    # Append to chain metrics history
    local metrics_history="$REMEDIATION_DIR/chain-metrics-history.jsonl"

    local metric_record
    metric_record=$(jq -n \
        --arg exec_id "$exec_id" \
        --arg chain "$chain_name" \
        --arg status "$status" \
        --argjson timestamp "$(date +%s)" \
        --argjson duration "$duration" \
        --argjson success "$success_count" \
        --argjson failures "$failure_count" \
        --argjson skipped "$skipped_count" \
        '{
            execution_id: $exec_id,
            chain: $chain,
            status: $status,
            timestamp: $timestamp,
            duration: $duration,
            playbooks_succeeded: $success,
            playbooks_failed: $failures,
            playbooks_skipped: $skipped
        }')

    echo "$metric_record" >> "$metrics_history"

    log_verbose "Chain metrics written to $metrics_history"
}

# ==============================================================================
# UTILITY FUNCTIONS
# ==============================================================================

list_chains() {
    if [ ! -d "$CHAINS_DIR" ]; then
        log_error "Chains directory not found: $CHAINS_DIR"
        return 1
    fi

    echo "Available chains:"
    echo ""

    for chain_file in "$CHAINS_DIR"/*.yml; do
        if [ -f "$chain_file" ]; then
            local chain_name
            chain_name=$(basename "$chain_file" .yml)

            # Load chain to get description
            export CHAIN_FILE="$chain_file"
            local description risk_level
            description=$(yq eval '.description' "$chain_file" 2>/dev/null || echo "No description")
            risk_level=$(yq eval '.risk_level' "$chain_file" 2>/dev/null || echo "unknown")

            echo "  $chain_name"
            echo "    Description: $description"
            echo "    Risk Level: $risk_level"
            echo ""
        fi
    done
}

show_help() {
    cat << EOF
execute-chain.sh - Multi-Playbook Chain Orchestration Engine

USAGE:
    execute-chain.sh --chain <chain-name> [options]
    execute-chain.sh --list-chains
    execute-chain.sh --validate <chain-name>
    execute-chain.sh --resume <execution-id>

OPTIONS:
    --chain <name>           Execute specified chain
    --dry-run                Show execution plan without running
    --force                  Skip confirmation prompts
    --resume <id>            Resume failed/interrupted chain
    --list-chains            List available chains
    --validate <chain>       Validate chain configuration
    --verbose                Enable verbose logging
    --help                   Show this help message

EXAMPLES:
    # List available chains
    execute-chain.sh --list-chains

    # Validate chain configuration
    execute-chain.sh --validate full-recovery

    # Execute chain (dry run)
    execute-chain.sh --chain full-recovery --dry-run

    # Execute chain (real execution)
    execute-chain.sh --chain full-recovery

    # Execute chain without confirmation
    execute-chain.sh --chain predictive-preemption --force

    # Resume interrupted chain
    execute-chain.sh --resume full-recovery_1735027200

AVAILABLE CHAINS:
$(list_chains 2>&1 | sed 's/^/    /')

EOF
}

# ==============================================================================
# MAIN
# ==============================================================================

main() {
    # Parse arguments
    local chain_name=""
    local mode="execute"
    local resume_id=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --chain)
                chain_name="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --list-chains)
                mode="list"
                shift
                ;;
            --validate)
                mode="validate"
                chain_name="$2"
                shift 2
                ;;
            --resume)
                mode="resume"
                resume_id="$2"
                shift 2
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Execute based on mode
    case "$mode" in
        "list")
            list_chains
            ;;
        "validate")
            if [ -z "$chain_name" ]; then
                log_error "Chain name required for validation"
                exit 1
            fi
            validate_chain "$chain_name"
            ;;
        "resume")
            if [ -z "$resume_id" ]; then
                log_error "Execution ID required for resume"
                exit 1
            fi
            log_error "Resume not yet implemented"
            exit 1
            ;;
        "execute")
            if [ -z "$chain_name" ]; then
                log_error "Chain name required"
                show_help
                exit 1
            fi
            execute_chain "$chain_name"
            ;;
        *)
            log_error "Unknown mode: $mode"
            exit 1
            ;;
    esac
}

# Run main if not sourced
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
