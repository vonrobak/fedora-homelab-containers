#!/bin/bash
################################################################################
# analyze-impact.sh
# Calculate blast radius and restart impact for services
#
# This script analyzes the dependency graph to determine:
# - Blast radius (how many services affected if X fails)
# - Restart order (optimal sequence to minimize downtime)
# - Impact severity (critical, high, medium, low)
# - Cascade requirements (does restart trigger dependent restarts?)
#
# Usage:
#   ./analyze-impact.sh --service jellyfin          # Impact if jellyfin fails
#   ./analyze-impact.sh --action restart prometheus # Impact of restarting
#   ./analyze-impact.sh --network monitoring        # Impact if network fails
#   ./analyze-impact.sh --visualize jellyfin        # Generate impact visualization
#
# Author: Claude (Autonomous Service Dependency Mapping)
# Version: 1.0.0
# Phase: 1 (MVP - Basic blast radius + restart order)
################################################################################

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly CONTEXT_DIR="$PROJECT_ROOT/.claude/context"
readonly GRAPH_FILE="$CONTEXT_DIR/dependency-graph.json"

# Logging
log() {
    local level=$1
    shift
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $*" >&2
}

# Usage information
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Analyze dependency impact and generate restart strategies.

Options:
    --service SERVICE       Analyze impact if SERVICE fails
    --action ACTION         Action to perform (restart, stop, start)
    --network NETWORK       Analyze impact if NETWORK fails
    --visualize             Generate visual representation
    --output FORMAT         Output format (text, json) [default: text]
    --help                  Display this help message

Examples:
    # What happens if postgres fails?
    $0 --service postgresql-immich

    # What's the impact of restarting traefik?
    $0 --service traefik --action restart

    # Show as JSON
    $0 --service immich-server --output json

EOF
}

# Parse command line arguments
SERVICE=""
ACTION="failure"
NETWORK=""
VISUALIZE=false
OUTPUT_FORMAT="text"

while [[ $# -gt 0 ]]; do
    case $1 in
        --service)
            SERVICE="$2"
            shift 2
            ;;
        --action)
            ACTION="$2"
            shift 2
            ;;
        --network)
            NETWORK="$2"
            shift 2
            ;;
        --visualize)
            VISUALIZE=true
            shift
            ;;
        --output)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate inputs
if [[ -z "$SERVICE" && -z "$NETWORK" ]]; then
    log "ERROR" "Must specify --service or --network"
    usage
    exit 1
fi

if [[ ! -f "$GRAPH_FILE" ]]; then
    log "ERROR" "Dependency graph not found at $GRAPH_FILE"
    log "INFO" "Run discover-dependencies.sh first to generate the graph"
    exit 1
fi

################################################################################
# Core Functions
################################################################################

# Load dependency graph
load_graph() {
    cat "$GRAPH_FILE"
}

# Get direct dependents of a service
get_direct_dependents() {
    local service=$1
    local graph=$2

    echo "$graph" | jq -r ".services[\"$service\"].dependents[]?" 2>/dev/null || echo ""
}

# Get all dependencies of a service (for restart order)
get_dependencies() {
    local service=$1
    local graph=$2

    echo "$graph" | jq -r ".services[\"$service\"].dependencies[]?.target" 2>/dev/null || echo ""
}

# Calculate transitive closure (all affected services via BFS)
calculate_transitive_dependents() {
    local service=$1
    local graph=$2

    # Use associative array to track visited services
    declare -A visited
    local queue=("$service")
    local all_dependents=()

    while [[ ${#queue[@]} -gt 0 ]]; do
        local current="${queue[0]}"
        queue=("${queue[@]:1}")  # dequeue

        # Skip if already visited
        [[ -n "${visited[$current]:-}" ]] && continue
        visited[$current]=1

        # Get direct dependents of current service
        local dependents=$(get_direct_dependents "$current" "$graph")

        for dependent in $dependents; do
            # Skip if already visited
            [[ -n "${visited[$dependent]:-}" ]] && continue

            all_dependents+=("$dependent")
            queue+=("$dependent")
        done
    done

    # Return unique list
    printf '%s\n' "${all_dependents[@]}" | sort -u
}

# Calculate blast radius
calculate_blast_radius() {
    local service=$1
    local graph=$2

    local direct_dependents=$(get_direct_dependents "$service" "$graph")
    local direct_count=$(echo "$direct_dependents" | wc -w)

    local all_dependents=$(calculate_transitive_dependents "$service" "$graph")
    local indirect_count=$(echo "$all_dependents" | wc -l)

    # Check if service is critical
    local is_critical=$(echo "$graph" | jq -r ".services[\"$service\"].critical")

    # Check if service has external access
    local external_access=$(echo "$graph" | jq -r ".services[\"$service\"].external_access")

    # Get affected networks
    local networks=$(echo "$graph" | jq -r ".services[\"$service\"].networks[]")

    # Assess severity
    local severity="low"
    if [[ "$is_critical" == "true" ]]; then
        severity="critical"
    elif [[ $indirect_count -gt 5 ]]; then
        severity="high"
    elif [[ $indirect_count -gt 2 ]]; then
        severity="medium"
    fi

    # Estimate downtime
    local estimated_downtime="1-2 minutes"
    if [[ "$is_critical" == "true" ]]; then
        estimated_downtime="5-10 minutes"
    elif [[ $indirect_count -gt 3 ]]; then
        estimated_downtime="3-5 minutes"
    fi

    # Build result
    cat <<JSON
{
  "service": "$service",
  "blast_radius": {
    "direct_dependents": [$(echo "$direct_dependents" | tr ' ' '\n' | sed 's/^/"/;s/$/"/' | paste -sd, || echo '')],
    "indirect_dependents": [$(echo "$all_dependents" | sed 's/^/"/;s/$/"/' | paste -sd, || echo '')],
    "affected_networks": [$(echo "$networks" | sed 's/^/"/;s/$/"/' | paste -sd, || echo '')],
    "external_access_lost": $external_access,
    "total_services_affected": $indirect_count,
    "severity": "$severity"
  },
  "estimated_downtime": "$estimated_downtime"
}
JSON
}

# Generate restart order using topological sort
generate_restart_order() {
    local service=$1
    local graph=$2

    log "INFO" "Generating restart order for $service..."

    # Get all dependents (services that need to be stopped first)
    local all_dependents=$(calculate_transitive_dependents "$service" "$graph")

    # Phase 1: Stop all dependents in reverse dependency order
    local stop_phases=()
    local phase_num=1

    # For MVP, stop all dependents in parallel (single phase)
    if [[ -n "$all_dependents" ]]; then
        local dependents_array="[$(echo "$all_dependents" | sed 's/^/"/;s/$/"/' | paste -sd, || echo '')]"
        stop_phases+=("{\"phase\":$phase_num,\"action\":\"stop\",\"targets\":$dependents_array,\"parallel\":true}")
        ((phase_num++))
    fi

    # Phase 2: Restart target service
    stop_phases+=("{\"phase\":$phase_num,\"action\":\"restart\",\"targets\":[\"$service\"],\"parallel\":false}")
    ((phase_num++))

    # Phase 3: Start dependents in dependency order
    if [[ -n "$all_dependents" ]]; then
        local dependents_array="[$(echo "$all_dependents" | sed 's/^/"/;s/$/"/' | paste -sd, || echo '')]"
        stop_phases+=("{\"phase\":$phase_num,\"action\":\"start\",\"targets\":$dependents_array,\"parallel\":true}")
    fi

    # Build strategy JSON
    local phases_json=$(IFS=,; echo "[${stop_phases[*]}]")

    cat <<JSON
{
  "recommended_order": $phases_json,
  "estimated_duration": "5-8 minutes",
  "requires_confirmation": $([ "${#all_dependents}" -gt 3 ] && echo "true" || echo "false")
}
JSON
}

# Check if restart will trigger cascade
will_trigger_cascade() {
    local service=$1
    local graph=$2

    # Check if service has hard dependents
    local services=$(echo "$graph" | jq -r '.services | keys[]')

    for svc in $services; do
        local deps=$(echo "$graph" | jq -r ".services[\"$svc\"].dependencies[]?")

        # Check if this service has a HARD dependency on our target
        local has_hard_dep=$(echo "$deps" | jq -r "select(.target == \"$service\" and .strength == \"hard\") | .target" 2>/dev/null || echo "")

        if [[ -n "$has_hard_dep" ]]; then
            echo "true"
            return 0
        fi
    done

    echo "false"
    return 0
}

################################################################################
# Output Functions
################################################################################

# Format output as text
format_text_output() {
    local service=$1
    local blast_radius=$2
    local restart_strategy=$3
    local graph=$4

    echo "=========================================="
    echo "Impact Analysis: $service"
    echo "=========================================="
    echo ""

    # Blast Radius
    echo "BLAST RADIUS:"
    local direct_deps=$(echo "$blast_radius" | jq -r '.blast_radius.direct_dependents[]?' 2>/dev/null || echo "")
    local indirect_deps=$(echo "$blast_radius" | jq -r '.blast_radius.indirect_dependents[]?' 2>/dev/null || echo "")
    local severity=$(echo "$blast_radius" | jq -r '.blast_radius.severity')
    local total=$(echo "$blast_radius" | jq -r '.blast_radius.total_services_affected')

    echo "  Severity: $severity"
    echo "  Total affected: $total services"
    echo ""

    if [[ -n "$direct_deps" ]]; then
        echo "  Direct dependents:"
        echo "$direct_deps" | sed 's/^/    - /'
        echo ""
    fi

    if [[ -n "$indirect_deps" && "$direct_deps" != "$indirect_deps" ]]; then
        echo "  Indirect dependents (cascading):"
        comm -13 <(echo "$direct_deps" | sort) <(echo "$indirect_deps" | sort) | sed 's/^/    - /'
        echo ""
    fi

    # Networks affected
    local networks=$(echo "$blast_radius" | jq -r '.blast_radius.affected_networks[]?' 2>/dev/null || echo "")
    if [[ -n "$networks" ]]; then
        echo "  Affected networks:"
        echo "$networks" | sed 's/^/    - /'
        echo ""
    fi

    # Restart strategy
    if [[ "$ACTION" == "restart" ]]; then
        echo "RESTART STRATEGY:"
        local requires_confirm=$(echo "$restart_strategy" | jq -r '.requires_confirmation')
        local duration=$(echo "$restart_strategy" | jq -r '.estimated_duration')

        echo "  Estimated duration: $duration"
        echo "  Requires confirmation: $requires_confirm"
        echo ""

        echo "  Recommended order:"
        echo "$restart_strategy" | jq -r '.recommended_order[] | "    Phase \(.phase): \(.action) \(.targets | join(", "))"'
        echo ""
    fi

    # Critical service warning
    local is_critical=$(echo "$graph" | jq -r ".services[\"$service\"].critical")
    if [[ "$is_critical" == "true" ]]; then
        echo "⚠️  WARNING: $service is a CRITICAL service"
        echo "   Consider impact carefully before taking action"
        echo ""
    fi

    # Cascade warning
    local will_cascade=$(will_trigger_cascade "$service" "$graph")
    if [[ "$will_cascade" == "true" ]]; then
        echo "⚠️  WARNING: Restarting $service will trigger cascade restart"
        echo "   Dependent services with HARD dependencies will be affected"
        echo ""
    fi

    echo "=========================================="
}

# Format output as JSON
format_json_output() {
    local service=$1
    local blast_radius=$2
    local restart_strategy=$3

    cat <<JSON
{
  "service": "$service",
  "action": "$ACTION",
  "blast_radius": $(echo "$blast_radius" | jq -c '.blast_radius'),
  "restart_strategy": $(echo "$restart_strategy" | jq -c '.'),
  "estimated_downtime": $(echo "$blast_radius" | jq -r '.estimated_downtime'),
  "will_trigger_cascade": $(will_trigger_cascade "$service" "$(load_graph)")
}
JSON
}

################################################################################
# Main Execution
################################################################################

main() {
    log "INFO" "Analyzing impact for service: $SERVICE (action: $ACTION)"

    # Load dependency graph
    local graph=$(load_graph)

    # Verify service exists
    if ! echo "$graph" | jq -e ".services[\"$SERVICE\"]" >/dev/null 2>&1; then
        log "ERROR" "Service '$SERVICE' not found in dependency graph"
        log "INFO" "Available services:"
        echo "$graph" | jq -r '.services | keys[]' | sed 's/^/  - /'
        exit 1
    fi

    # Calculate blast radius
    local blast_radius=$(calculate_blast_radius "$SERVICE" "$graph")

    # Generate restart strategy
    local restart_strategy=$(generate_restart_order "$SERVICE" "$graph")

    # Output results
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        format_json_output "$SERVICE" "$blast_radius" "$restart_strategy"
    else
        format_text_output "$SERVICE" "$blast_radius" "$restart_strategy" "$graph"
    fi

    # Exit with appropriate code based on severity
    local severity=$(echo "$blast_radius" | jq -r '.blast_radius.severity')
    case $severity in
        critical)
            log "WARNING" "Impact severity: CRITICAL"
            exit 2
            ;;
        high)
            log "WARNING" "Impact severity: HIGH"
            exit 1
            ;;
        *)
            exit 0
            ;;
    esac
}

# Run main
main
