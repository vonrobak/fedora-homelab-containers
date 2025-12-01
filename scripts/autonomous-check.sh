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
CONTEXT_DIR="$HOME/containers/.claude/context"  # Unified context location
STATE_FILE="$CONTEXT_DIR/autonomous-state.json"
DECISION_LOG="$CONTEXT_DIR/decision-log.json"
PREFERENCES="$CONTEXT_DIR/preferences.yml"
ISSUE_HISTORY="$CONTEXT_DIR/issue-history.json"

# Scripts to integrate with
HOMELAB_INTEL="$SCRIPT_DIR/homelab-intel.sh"
PREDICT_RESOURCES="$SCRIPT_DIR/predictive-analytics/predict-resource-exhaustion.sh"
CHECK_DRIFT="$CONTAINERS_DIR/.claude/skills/homelab-deployment/scripts/check-drift.sh"
SECURITY_AUDIT="$SCRIPT_DIR/security-audit.sh"
QUERY_HOMELAB="$SCRIPT_DIR/query-homelab.sh"
RECOMMEND_SKILL="$SCRIPT_DIR/recommend-skill.sh"

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
        # Extract key settings from YAML (simple parsing, exclude comments)
        local risk_tolerance auto_disk_cleanup auto_service_restart

        risk_tolerance=$(grep "^risk_tolerance:" "$PREFERENCES" 2>/dev/null | awk '{print $2}' || echo "medium")
        auto_disk_cleanup=$(grep "^[[:space:]]*auto_disk_cleanup:" "$PREFERENCES" 2>/dev/null | grep -v "^#" | awk '{print $2}' | head -1 || echo "true")
        auto_service_restart=$(grep "^[[:space:]]*auto_service_restart:" "$PREFERENCES" 2>/dev/null | grep -v "^#" | awk '{print $2}' | head -1 || echo "true")

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

    # Try query cache for service health (Session 5C integration)
    local CACHE_FILE="$CONTEXT_DIR/query-cache.json"
    if [[ -f "$CACHE_FILE" ]]; then
        local cached_entry
        cached_entry=$(jq '.unhealthy_services // null' "$CACHE_FILE" 2>/dev/null)

        if [[ -n "$cached_entry" && "$cached_entry" != "null" ]]; then
            # Check if cache is fresh (TTL from cache)
            local cache_time ttl
            cache_time=$(echo "$cached_entry" | jq -r '.timestamp // null' 2>/dev/null)
            ttl=$(echo "$cached_entry" | jq -r '.ttl // 60' 2>/dev/null)

            if [[ -n "$cache_time" && "$cache_time" != "null" ]]; then
                local current_time=$(date +%s)
                local cached_epoch=$(date -d "$cache_time" +%s 2>/dev/null || echo "0")
                local age=$((current_time - cached_epoch))

                if (( age < ttl )); then
                    log DEBUG "Using cached service health data (age: ${age}s, ttl: ${ttl}s)"
                    # Extract result - it's already in the format we need
                    local cache_result
                    cache_result=$(echo "$cached_entry" | jq '.result' 2>/dev/null)
                    if [[ -n "$cache_result" && "$cache_result" != "null" ]]; then
                        echo "$cache_result"
                        return
                    fi
                fi
            fi
        fi
    fi

    # Fallback to direct checks
    log DEBUG "Cache miss or stale, using direct service checks"
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

    # Try query-homelab.sh for cached disk info (Session 5C integration)
    if [[ -x "$QUERY_HOMELAB" ]]; then
        local disk_result
        disk_result=$("$QUERY_HOMELAB" "show me disk usage" --json 2>/dev/null || echo "")

        if [[ -n "$disk_result" ]]; then
            # Parse query result and convert to expected format
            local root_pct btrfs_pct
            root_pct=$(echo "$disk_result" | jq -r '.filesystems[] | select(.mount == "/") | .usage_pct' | tr -d '%')
            btrfs_pct=$(echo "$disk_result" | jq -r '.filesystems[] | select(.mount == "/mnt/btrfs-pool") | .usage_pct' | tr -d '%' 2>/dev/null || echo 0)

            if [[ -n "$root_pct" && "$root_pct" != "null" ]]; then
                log DEBUG "Using cached disk usage data"
                echo "{\"root_usage_pct\": $root_pct, \"btrfs_usage_pct\": $btrfs_pct}"
                return
            fi
        fi
    fi

    # Fallback to direct calls if query system unavailable
    log DEBUG "Query system unavailable, using direct disk checks"
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

observe_dependencies() {
    log DEBUG "Analyzing service dependencies..."

    local dep_graph="$CONTEXT_DIR/dependency-graph.json"
    local analyze_impact="$SCRIPT_DIR/analyze-impact.sh"

    if $DRY_RUN; then
        echo '{"graph_exists": false, "critical_services": [], "unhealthy_dependencies": [], "high_risk_services": []}'
        return
    fi

    # Check if dependency graph exists
    if [[ ! -f "$dep_graph" ]]; then
        log WARNING "Dependency graph not found at $dep_graph"
        echo '{"graph_exists": false, "critical_services": [], "unhealthy_dependencies": [], "high_risk_services": []}'
        return
    fi

    # Check graph staleness
    local generated_at staleness_seconds
    generated_at=$(jq -r '.generated_at' "$dep_graph" 2>/dev/null || echo "")

    if [[ -n "$generated_at" ]]; then
        local generated_epoch now_epoch
        generated_epoch=$(date -d "$generated_at" +%s 2>/dev/null || echo "0")
        now_epoch=$(date +%s)
        staleness_seconds=$((now_epoch - generated_epoch))
    else
        staleness_seconds=999999
    fi

    # Get critical services
    local critical_services
    critical_services=$(jq -c '[.services | to_entries[] | select(.value.critical == true) | {
        service: .key,
        blast_radius: .value.blast_radius,
        running: false
    }]' "$dep_graph" 2>/dev/null || echo "[]")

    # Check which critical services are running
    local critical_array=()
    while IFS= read -r svc_obj; do
        local svc_name
        svc_name=$(echo "$svc_obj" | jq -r '.service')

        local running=false
        if systemctl --user is-active "$svc_name.service" >/dev/null 2>&1 || \
           podman ps --format '{{.Names}}' 2>/dev/null | grep -qw "^$svc_name$"; then
            running=true
        fi

        svc_obj=$(echo "$svc_obj" | jq --argjson running "$running" '.running = $running')
        critical_array+=("$svc_obj")
    done < <(echo "$critical_services" | jq -c '.[]')

    # Rebuild critical services array
    critical_services="["
    local first=true
    for item in "${critical_array[@]}"; do
        if [[ "$first" == true ]]; then
            first=false
        else
            critical_services+=","
        fi
        critical_services+="$item"
    done
    critical_services+="]"

    # Find services with high blast radius (>3) that could cause cascading failures
    local high_risk_services
    high_risk_services=$(jq -c '[.services | to_entries[] | select(.value.blast_radius > 3) | {
        service: .key,
        blast_radius: .value.blast_radius,
        dependents: (.value.dependents | length)
    }]' "$dep_graph" 2>/dev/null || echo "[]")

    # Use query-homelab.sh to check for unhealthy dependencies
    local unhealthy_deps="[]"
    if [[ -x "$QUERY_HOMELAB" ]]; then
        unhealthy_deps=$("$QUERY_HOMELAB" "unhealthy dependencies" --json 2>/dev/null | \
            jq -c '.unhealthy_dependencies // []' || echo "[]")
    fi

    # Output dependency observations
    jq -n \
        --argjson graph_exists true \
        --argjson staleness "$staleness_seconds" \
        --argjson critical "$critical_services" \
        --argjson high_risk "$high_risk_services" \
        --argjson unhealthy "$unhealthy_deps" \
        '{
            graph_exists: $graph_exists,
            staleness_seconds: $staleness,
            critical_services: $critical,
            high_risk_services: $high_risk,
            unhealthy_dependencies: $unhealthy
        }'
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

calculate_dependency_safety() {
    local service=$1
    local dependencies_obs=$2

    # Parse dependency observation data
    local blast_radius unhealthy_count critical_down

    blast_radius=$(echo "$dependencies_obs" | jq -r ".high_risk_services[] | select(.service == \"$service\") | .blast_radius" 2>/dev/null || echo "0")
    unhealthy_count=$(echo "$dependencies_obs" | jq '[.unhealthy_dependencies[] | select(.service == "'"$service"'")] | length' 2>/dev/null || echo "0")
    critical_down=$(echo "$dependencies_obs" | jq '[.critical_services[] | select(.service == "'"$service"'" and .running == false)] | length' 2>/dev/null || echo "0")

    # Calculate safety score (0.0 - 1.0)
    # - Start at 1.0 (perfect safety)
    # - Subtract 0.05 per blast radius point
    # - Subtract 0.20 per unhealthy dependency
    # - Subtract 0.40 if service is critical and down

    awk "BEGIN {
        score = 1.0
        score -= ($blast_radius * 0.05)
        score -= ($unhealthy_count * 0.20)
        score -= ($critical_down * 0.40)
        if (score < 0) score = 0
        printf \"%.2f\", score
    }"
}

calculate_confidence() {
    local prediction_confidence=$1
    local historical_success=$2
    local impact_certainty=$3
    local rollback_feasibility=$4
    local dep_safety_score=${5:-1.0}  # Default to 1.0 if not provided

    # Weighted average with dependency safety (Phase 3 integration)
    # - prediction_confidence: 25% (reduced from 30%)
    # - historical_success: 25% (reduced from 30%)
    # - impact_certainty: 15% (reduced from 20%)
    # - rollback_feasibility: 15% (reduced from 20%)
    # - dep_safety_score: 20% (NEW - dependency safety)
    awk "BEGIN {
        conf = ($prediction_confidence * 0.25) + \
               ($historical_success * 0.25) + \
               ($impact_certainty * 0.15) + \
               ($rollback_feasibility * 0.15) + \
               ($dep_safety_score * 0.20)
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
    local health_obs predictions_obs drift_obs services_obs disk_obs dependencies_obs
    health_obs=$(observe_health)
    predictions_obs=$(observe_predictions)
    drift_obs=$(observe_drift)
    services_obs=$(observe_services)
    disk_obs=$(observe_disk)
    dependencies_obs=$(observe_dependencies)

    local health_score
    health_score=$(echo "$health_obs" | jq '.health_score // 100')

    log INFO "Health score: $health_score"
    log DEBUG "Health: $health_obs"
    log DEBUG "Predictions: $predictions_obs"
    log DEBUG "Drift: $drift_obs"
    log DEBUG "Services: $services_obs"
    log DEBUG "Disk: $disk_obs"
    log DEBUG "Dependencies: $dependencies_obs"

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

            # Calculate dependency safety score (Phase 3)
            local dep_safety_score
            dep_safety_score=$(calculate_dependency_safety "$service" "$dependencies_obs")

            local hist_success conf risk decision
            hist_success=$(get_historical_success_rate "service-restart")
            conf=$(calculate_confidence 0.85 "$hist_success" 0.90 1.0 "$dep_safety_score")
            risk=$(get_risk_level "service-restart")
            decision=$(make_decision "$conf" "$risk" "$preferences")

            actions+=("{
              \"id\": \"$(generate_action_id)\",
              \"type\": \"service-restart\",
              \"service\": \"$service\",
              \"reason\": \"Service unhealthy or not running\",
              \"confidence\": $conf,
              \"dep_safety_score\": $dep_safety_score,
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

    # Get skill recommendations based on observations
    local skill_recommendations="null"
    if [[ -x "$RECOMMEND_SKILL" ]]; then
        log DEBUG "Getting skill recommendations..."

        # Build a natural language summary of the situation for skill matching
        local situation_summary=""

        if (( unhealthy_count > 0 )); then
            situation_summary+="unhealthy service error troubleshoot "
        fi

        if [[ "$drift_detected" == "true" ]]; then
            situation_summary+="configuration drift deploy reconfigure "
        fi

        if (( root_pct >= 70 )); then
            situation_summary+="disk usage space cleanup "
        fi

        # Only recommend skills if there are issues
        if [[ -n "$situation_summary" ]]; then
            local skill_result
            skill_result=$("$RECOMMEND_SKILL" --json "$situation_summary" 2>/dev/null || echo "{}")

            if [[ -n "$skill_result" && "$skill_result" != "{}" ]]; then
                skill_recommendations="$skill_result"
                log DEBUG "Skill recommendation: $(echo "$skill_result" | jq -r '.top_recommendation.skill // "none"')"
            fi
        fi
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
  "skill_recommendations": $skill_recommendations,
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

    # Output (save raw for debugging if needed)
    if $VERBOSE; then
        echo "$output" > /tmp/autonomous-check-raw.json 2>/dev/null || true
    fi
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
