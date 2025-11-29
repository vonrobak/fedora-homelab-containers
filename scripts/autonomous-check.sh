#!/usr/bin/env bash
#
# autonomous-check.sh - Autonomous Operations Assessment
#
# Implements OBSERVE, ORIENT, DECIDE phases of the OODA loop.
# Collects system state, applies context, and recommends actions.
#
# Usage:
#   ./autonomous-check.sh              # Run assessment
#   ./autonomous-check.sh --verbose    # Verbose output
#   ./autonomous-check.sh --json       # JSON output only
#   ./autonomous-check.sh --dry-run    # Show what would be checked
#
# Output: JSON assessment with recommended actions
#
# Exit codes:
#   0 - Assessment complete, no critical actions needed
#   1 - Assessment complete, actions recommended
#   2 - Error during assessment
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINERS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONTEXT_DIR="$CONTAINERS_DIR/.claude/context"
STATE_FILE="$CONTEXT_DIR/autonomous-state.json"
DECISION_LOG="$CONTEXT_DIR/decision-log.json"
PREFERENCES="$CONTEXT_DIR/preferences.yml"
ISSUE_HISTORY="$CONTEXT_DIR/issue-history.json"

# Scripts to integrate with
HOMELAB_INTEL="$SCRIPT_DIR/homelab-intel.sh"
PREDICT_RESOURCES="$SCRIPT_DIR/predictive-analytics/predict-resource-exhaustion.sh"
CHECK_DRIFT="$CONTAINERS_DIR/.claude/skills/homelab-deployment/scripts/check-drift.sh"
SECURITY_AUDIT="$SCRIPT_DIR/security-audit.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Flags
VERBOSE=false
JSON_ONLY=false
DRY_RUN=false
OUTPUT_FILE=""

# Timestamp
TIMESTAMP=$(date -Iseconds)

##############################################################################
# Argument Parsing
##############################################################################

while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --json|-j)
            JSON_ONLY=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --output|-o)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --help|-h)
            cat << EOF
Usage: $0 [OPTIONS]

Autonomous operations assessment - OBSERVE, ORIENT, DECIDE phases.

Options:
  --verbose, -v    Show detailed output
  --json, -j       Output JSON only (no human-readable text)
  --dry-run        Show what would be checked without running
  --output, -o     Save JSON output to file
  --help, -h       Show this help

Output:
  JSON structure with observations and recommended actions.

Exit Codes:
  0 - No critical actions needed
  1 - Actions recommended
  2 - Assessment error
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 2
            ;;
    esac
done

##############################################################################
# Logging
##############################################################################

log() {
    local level=$1
    shift
    local message="$*"

    if $JSON_ONLY; then
        return
    fi

    case $level in
        INFO)    echo -e "${BLUE}[INFO]${NC} $message" >&2 ;;
        SUCCESS) echo -e "${GREEN}[SUCCESS]${NC} $message" >&2 ;;
        WARNING) echo -e "${YELLOW}[WARNING]${NC} $message" >&2 ;;
        ERROR)   echo -e "${RED}[ERROR]${NC} $message" >&2 ;;
        DEBUG)   $VERBOSE && echo -e "${CYAN}[DEBUG]${NC} $message" >&2 || true ;;
    esac
}

##############################################################################
# State Management
##############################################################################

load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        cat "$STATE_FILE"
    else
        echo '{"enabled": true, "paused": false, "circuit_breaker": {"triggered": false}}'
    fi
}

is_paused() {
    local state
    state=$(load_state)
    echo "$state" | jq -r '.paused // false'
}

is_circuit_breaker_triggered() {
    local state
    state=$(load_state)
    echo "$state" | jq -r '.circuit_breaker.triggered // false'
}

get_cooldown() {
    local action_type=$1
    local state
    state=$(load_state)

    local cooldown_end
    cooldown_end=$(echo "$state" | jq -r ".cooldowns[\"$action_type\"] // \"\"")

    if [[ -n "$cooldown_end" && "$cooldown_end" != "null" ]]; then
        local cooldown_epoch end_epoch
        cooldown_epoch=$(date -d "$cooldown_end" +%s 2>/dev/null || echo 0)
        end_epoch=$(date +%s)

        if (( cooldown_epoch > end_epoch )); then
            echo "active"
            return
        fi
    fi

    echo "inactive"
}

load_preferences() {
    if [[ -f "$PREFERENCES" ]]; then
        # Extract key settings from YAML (simple parsing)
        local risk_tolerance auto_disk_cleanup auto_service_restart

        risk_tolerance=$(grep "^risk_tolerance:" "$PREFERENCES" 2>/dev/null | awk '{print $2}' || echo "medium")
        auto_disk_cleanup=$(grep "auto_disk_cleanup:" "$PREFERENCES" 2>/dev/null | awk '{print $2}' || echo "true")
        auto_service_restart=$(grep "auto_service_restart:" "$PREFERENCES" 2>/dev/null | awk '{print $2}' || echo "true")

        cat << EOF
{
  "risk_tolerance": "$risk_tolerance",
  "auto_disk_cleanup": $auto_disk_cleanup,
  "auto_service_restart": $auto_service_restart
}
EOF
    else
        echo '{"risk_tolerance": "medium", "auto_disk_cleanup": true, "auto_service_restart": true}'
    fi
}

get_service_override() {
    local service=$1

    if [[ -f "$PREFERENCES" ]]; then
        # Check if service has auto_restart: false
        local in_service=false
        while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]*${service}: ]]; then
                in_service=true
            elif [[ "$in_service" == true && "$line" =~ ^[[:space:]]*auto_restart:[[:space:]]*false ]]; then
                echo "no-auto-restart"
                return
            elif [[ "$in_service" == true && "$line" =~ ^[[:space:]]*[a-zA-Z] && ! "$line" =~ ^[[:space:]]+ ]]; then
                in_service=false
            fi
        done < "$PREFERENCES"
    fi

    echo "default"
}

##############################################################################
# OBSERVE Phase - Collect System State
##############################################################################

observe_health() {
    log DEBUG "Collecting health score..."

    if [[ ! -x "$HOMELAB_INTEL" ]]; then
        log WARNING "homelab-intel.sh not found"
        echo '{"health_score": 100, "critical_issues": [], "warnings": []}'
        return
    fi

    # Run homelab-intel.sh and find latest JSON report
    if ! $DRY_RUN; then
        "$HOMELAB_INTEL" --quiet >/dev/null 2>&1 || true
    fi

    local latest_report
    latest_report=$(ls -t "$HOME/containers/docs/99-reports"/intel-*.json 2>/dev/null | head -1 || echo "")

    if [[ -f "$latest_report" ]]; then
        jq '{
          health_score: .health_score,
          critical_issues: (.critical_issues // []),
          warnings: (.warnings // [])
        }' "$latest_report" 2>/dev/null || echo '{"health_score": 100, "critical_issues": [], "warnings": []}'
    else
        echo '{"health_score": 100, "critical_issues": [], "warnings": []}'
    fi
}

observe_predictions() {
    log DEBUG "Collecting resource predictions..."

    if [[ ! -x "$PREDICT_RESOURCES" ]]; then
        log WARNING "predict-resource-exhaustion.sh not found"
        echo '{"predictions": []}'
        return
    fi

    if $DRY_RUN; then
        echo '{"predictions": []}'
        return
    fi

    # Get predictions in JSON format
    local predictions
    predictions=$("$PREDICT_RESOURCES" --output json 2>/dev/null || echo '{"predictions": []}')

    # Extract key predictions
    echo "$predictions" | jq '{
      predictions: (if type == "array" then . else (.predictions // []) end)
    }' 2>/dev/null || echo '{"predictions": []}'
}

observe_drift() {
    log DEBUG "Checking configuration drift..."

    if [[ ! -x "$CHECK_DRIFT" ]]; then
        log WARNING "check-drift.sh not found"
        echo '{"drift_detected": false, "services": []}'
        return
    fi

    if $DRY_RUN; then
        echo '{"drift_detected": false, "services": []}'
        return
    fi

    # Run drift check and capture output
    local drift_output
    drift_output=$("$CHECK_DRIFT" --json 2>/dev/null || echo '{"total_drift": 0}')

    local drift_count
    drift_count=$(echo "$drift_output" | jq '.total_drift // .services_drift // 0' 2>/dev/null || echo 0)

    if (( drift_count > 0 )); then
        echo "{\"drift_detected\": true, \"drift_count\": $drift_count}"
    else
        echo '{"drift_detected": false, "drift_count": 0}'
    fi
}

observe_services() {
    log DEBUG "Checking service states..."

    if $DRY_RUN; then
        echo '{"unhealthy_services": []}'
        return
    fi

    local unhealthy=()

    # Check critical services
    for service in traefik prometheus grafana alertmanager authelia jellyfin immich-server; do
        if systemctl --user is-active "$service.service" >/dev/null 2>&1; then
            # Service is running, check health if container exists
            if podman container exists "$service" 2>/dev/null; then
                if ! podman healthcheck run "$service" >/dev/null 2>&1; then
                    unhealthy+=("$service")
                fi
            fi
        elif systemctl --user list-unit-files "$service.service" >/dev/null 2>&1; then
            # Service exists but not running
            unhealthy+=("$service")
        fi
    done

    # Output as JSON array
    if (( ${#unhealthy[@]} > 0 )); then
        printf '{"unhealthy_services": ['
        local first=true
        for s in "${unhealthy[@]}"; do
            $first || printf ','
            printf '"%s"' "$s"
            first=false
        done
        printf ']}'
    else
        echo '{"unhealthy_services": []}'
    fi
}

observe_disk() {
    log DEBUG "Checking disk usage..."

    if $DRY_RUN; then
        echo '{"root_usage_pct": 50, "btrfs_usage_pct": 30}'
        return
    fi

    local root_pct btrfs_pct

    root_pct=$(df / | awk 'NR==2 {gsub(/%/,""); print $5}')

    # Check BTRFS pool if exists
    if [[ -d /mnt/btrfs-pool ]]; then
        btrfs_pct=$(df /mnt/btrfs-pool | awk 'NR==2 {gsub(/%/,""); print $5}' 2>/dev/null || echo 0)
    else
        btrfs_pct=0
    fi

    echo "{\"root_usage_pct\": $root_pct, \"btrfs_usage_pct\": $btrfs_pct}"
}

##############################################################################
# ORIENT Phase - Apply Context
##############################################################################

get_historical_success_rate() {
    local action_type=$1

    if [[ ! -f "$DECISION_LOG" ]]; then
        echo "1.0"  # Default to 100% if no history
        return
    fi

    local total success
    total=$(jq "[.decisions[] | select(.action_type == \"$action_type\")] | length" "$DECISION_LOG" 2>/dev/null || echo 0)
    success=$(jq "[.decisions[] | select(.action_type == \"$action_type\" and .outcome == \"success\")] | length" "$DECISION_LOG" 2>/dev/null || echo 0)

    if (( total == 0 )); then
        echo "1.0"  # Default if no history
    else
        awk "BEGIN {printf \"%.2f\", $success / $total}"
    fi
}

##############################################################################
# DECIDE Phase - Calculate Confidence and Recommend Actions
##############################################################################

calculate_confidence() {
    local prediction_confidence=$1
    local historical_success=$2
    local impact_certainty=$3
    local rollback_feasibility=$4

    # Weighted average
    awk "BEGIN {
        conf = ($prediction_confidence * 0.30) + \
               ($historical_success * 0.30) + \
               ($impact_certainty * 0.20) + \
               ($rollback_feasibility * 0.20)
        printf \"%.2f\", conf
    }"
}

get_risk_level() {
    local action_type=$1

    case "$action_type" in
        disk-cleanup)
            echo "low"
            ;;
        service-restart)
            echo "low"
            ;;
        drift-reconciliation)
            echo "medium"
            ;;
        *)
            echo "high"
            ;;
    esac
}

make_decision() {
    local confidence=$1
    local risk=$2
    local preferences=$3

    local risk_tolerance
    risk_tolerance=$(echo "$preferences" | jq -r '.risk_tolerance // "medium"')

    # Decision matrix based on risk tolerance
    case "$risk_tolerance" in
        low|conservative)
            # Only auto-execute if >95% confidence and low risk
            if [[ "$risk" == "low" ]] && (( $(awk "BEGIN {print ($confidence >= 0.95)}") )); then
                echo "auto-execute"
            elif (( $(awk "BEGIN {print ($confidence >= 0.80)}") )); then
                echo "queue"
            else
                echo "alert-only"
            fi
            ;;
        medium|moderate)
            # Auto-execute if >90% confidence and low risk, or >85% and low/medium
            if [[ "$risk" == "low" ]] && (( $(awk "BEGIN {print ($confidence >= 0.90)}") )); then
                echo "auto-execute"
            elif [[ "$risk" != "high" ]] && (( $(awk "BEGIN {print ($confidence >= 0.85)}") )); then
                echo "notify-execute"
            elif (( $(awk "BEGIN {print ($confidence >= 0.70)}") )); then
                echo "queue"
            else
                echo "alert-only"
            fi
            ;;
        high|aggressive)
            # More aggressive automation
            if (( $(awk "BEGIN {print ($confidence >= 0.80)}") )); then
                echo "auto-execute"
            elif (( $(awk "BEGIN {print ($confidence >= 0.60)}") )); then
                echo "queue"
            else
                echo "alert-only"
            fi
            ;;
        *)
            echo "alert-only"
            ;;
    esac
}

generate_action_id() {
    echo "action-$(date +%Y%m%d%H%M%S)-$RANDOM"
}

##############################################################################
# Main Assessment
##############################################################################

run_assessment() {
    log INFO "Starting autonomous operations assessment..."
    log INFO "Timestamp: $TIMESTAMP"

    # Check if paused
    if [[ "$(is_paused)" == "true" ]]; then
        log WARNING "Autonomous operations are PAUSED"
        cat << EOF
{
  "timestamp": "$TIMESTAMP",
  "status": "paused",
  "health_score": 0,
  "observations": {},
  "recommended_actions": [],
  "message": "Autonomous operations are paused"
}
EOF
        return 0
    fi

    # Check circuit breaker
    if [[ "$(is_circuit_breaker_triggered)" == "true" ]]; then
        log WARNING "Circuit breaker is TRIGGERED"
        cat << EOF
{
  "timestamp": "$TIMESTAMP",
  "status": "circuit-breaker",
  "health_score": 0,
  "observations": {},
  "recommended_actions": [],
  "message": "Circuit breaker triggered - manual intervention required"
}
EOF
        return 0
    fi

    log INFO "=== OBSERVE Phase ==="

    # Collect observations
    local health_obs predictions_obs drift_obs services_obs disk_obs
    health_obs=$(observe_health)
    predictions_obs=$(observe_predictions)
    drift_obs=$(observe_drift)
    services_obs=$(observe_services)
    disk_obs=$(observe_disk)

    local health_score
    health_score=$(echo "$health_obs" | jq '.health_score // 100')

    log INFO "Health score: $health_score"
    log DEBUG "Health: $health_obs"
    log DEBUG "Predictions: $predictions_obs"
    log DEBUG "Drift: $drift_obs"
    log DEBUG "Services: $services_obs"
    log DEBUG "Disk: $disk_obs"

    log INFO "=== ORIENT Phase ==="

    # Load context
    local preferences
    preferences=$(load_preferences)
    log DEBUG "Preferences: $preferences"

    log INFO "=== DECIDE Phase ==="

    # Build recommended actions
    local actions=()

    # Check disk usage
    local root_pct
    root_pct=$(echo "$disk_obs" | jq '.root_usage_pct')

    if (( root_pct >= 80 )); then
        log WARNING "Root disk at ${root_pct}% - recommending cleanup"

        local hist_success conf risk decision
        hist_success=$(get_historical_success_rate "disk-cleanup")
        conf=$(calculate_confidence 0.95 "$hist_success" 0.95 1.0)
        risk=$(get_risk_level "disk-cleanup")
        decision=$(make_decision "$conf" "$risk" "$preferences")

        if [[ "$(get_cooldown "disk-cleanup")" == "inactive" ]]; then
            actions+=("{
              \"id\": \"$(generate_action_id)\",
              \"type\": \"disk-cleanup\",
              \"reason\": \"Root disk at ${root_pct}%\",
              \"confidence\": $conf,
              \"risk\": \"$risk\",
              \"decision\": \"$decision\",
              \"priority\": \"high\"
            }")
        else
            log DEBUG "Disk cleanup on cooldown"
        fi
    elif (( root_pct >= 70 )); then
        log INFO "Root disk at ${root_pct}% - monitoring"
    fi

    # Check unhealthy services
    local unhealthy_count
    unhealthy_count=$(echo "$services_obs" | jq '.unhealthy_services | length')

    if (( unhealthy_count > 0 )); then
        local unhealthy_services
        unhealthy_services=$(echo "$services_obs" | jq -r '.unhealthy_services[]')

        while IFS= read -r service; do
            [[ -z "$service" ]] && continue

            log WARNING "Service $service is unhealthy"

            # Check service override
            if [[ "$(get_service_override "$service")" == "no-auto-restart" ]]; then
                log INFO "Service $service has auto_restart: false - skipping"
                continue
            fi

            # Check cooldown
            if [[ "$(get_cooldown "${service}.restart")" == "active" ]]; then
                log DEBUG "Service $service restart on cooldown"
                continue
            fi

            local hist_success conf risk decision
            hist_success=$(get_historical_success_rate "service-restart")
            conf=$(calculate_confidence 0.85 "$hist_success" 0.90 1.0)
            risk=$(get_risk_level "service-restart")
            decision=$(make_decision "$conf" "$risk" "$preferences")

            actions+=("{
              \"id\": \"$(generate_action_id)\",
              \"type\": \"service-restart\",
              \"service\": \"$service\",
              \"reason\": \"Service unhealthy or not running\",
              \"confidence\": $conf,
              \"risk\": \"$risk\",
              \"decision\": \"$decision\",
              \"priority\": \"medium\"
            }")
        done <<< "$unhealthy_services"
    fi

    # Check drift
    local drift_detected
    drift_detected=$(echo "$drift_obs" | jq -r '.drift_detected')

    if [[ "$drift_detected" == "true" ]]; then
        log WARNING "Configuration drift detected"

        local hist_success conf risk decision
        hist_success=$(get_historical_success_rate "drift-reconciliation")
        conf=$(calculate_confidence 0.80 "$hist_success" 0.85 1.0)
        risk=$(get_risk_level "drift-reconciliation")
        decision=$(make_decision "$conf" "$risk" "$preferences")

        actions+=("{
          \"id\": \"$(generate_action_id)\",
          \"type\": \"drift-reconciliation\",
          \"reason\": \"Configuration drift detected\",
          \"confidence\": $conf,
          \"risk\": \"$risk\",
          \"decision\": \"$decision\",
          \"priority\": \"low\"
        }")
    fi

    # Build final JSON output
    local actions_json="[]"
    if (( ${#actions[@]} > 0 )); then
        actions_json=$(printf '%s\n' "${actions[@]}" | jq -s '.')
    fi

    local output
    output=$(cat << EOF
{
  "timestamp": "$TIMESTAMP",
  "status": "complete",
  "health_score": $health_score,
  "observations": {
    "health": $health_obs,
    "predictions": $predictions_obs,
    "drift": $drift_obs,
    "services": $services_obs,
    "disk": $disk_obs
  },
  "preferences": $preferences,
  "recommended_actions": $actions_json,
  "summary": {
    "total_actions": ${#actions[@]},
    "auto_execute": $(echo "$actions_json" | jq '[.[] | select(.decision == "auto-execute")] | length'),
    "notify_execute": $(echo "$actions_json" | jq '[.[] | select(.decision == "notify-execute")] | length'),
    "queued": $(echo "$actions_json" | jq '[.[] | select(.decision == "queue")] | length'),
    "alert_only": $(echo "$actions_json" | jq '[.[] | select(.decision == "alert-only")] | length')
  }
}
EOF
    )

    # Output
    echo "$output" | jq '.'

    # Save to file if requested
    if [[ -n "$OUTPUT_FILE" ]]; then
        echo "$output" | jq '.' > "$OUTPUT_FILE"
        log INFO "Output saved to: $OUTPUT_FILE"
    fi

    # Update state
    local state
    state=$(load_state)
    state=$(echo "$state" | jq --arg ts "$TIMESTAMP" '.last_check = $ts | .statistics.total_checks += 1')
    echo "$state" > "$STATE_FILE"

    # Return code based on actions
    local action_count=${#actions[@]}
    if (( action_count > 0 )); then
        log INFO "Assessment complete: $action_count action(s) recommended"
        return 1
    else
        log SUCCESS "Assessment complete: No actions needed"
        return 0
    fi
}

##############################################################################
# Main
##############################################################################

main() {
    # Ensure context directory exists
    mkdir -p "$CONTEXT_DIR"

    # Initialize state file if needed
    if [[ ! -f "$STATE_FILE" ]]; then
        cat << EOF > "$STATE_FILE"
{
  "enabled": true,
  "mode": "active",
  "paused": false,
  "circuit_breaker": {"triggered": false, "consecutive_failures": 0},
  "last_check": null,
  "pending_actions": [],
  "cooldowns": {},
  "statistics": {"total_checks": 0, "total_actions": 0, "success_rate": 1.0}
}
EOF
    fi

    # Initialize decision log if needed
    if [[ ! -f "$DECISION_LOG" ]]; then
        echo '{"version": "1.0.0", "decisions": []}' > "$DECISION_LOG"
    fi

    run_assessment
}

main "$@"
