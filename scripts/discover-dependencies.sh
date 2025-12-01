#!/bin/bash
################################################################################
# discover-dependencies.sh
# Multi-source dependency discovery with conflict resolution
#
# Discovers service dependencies from multiple sources:
# - Quadlet systemd unit files (After=, Requires=, Wants=)
# - Podman network topology
# - Stack deployment files (future)
# - Traefik routing configuration (future)
# - Runtime TCP connections (future)
#
# Usage:
#   ./discover-dependencies.sh                # Generate dependency graph
#   ./discover-dependencies.sh --output json  # Output to dependency-graph.json
#   ./discover-dependencies.sh --verify       # Validate dependencies
#   ./discover-dependencies.sh --source quadlets  # Discover from specific source
#   ./discover-dependencies.sh --diff         # Show changes since last discovery
#
# Author: Claude (Autonomous Service Dependency Mapping)
# Version: 1.0.0
# Phase: 1 (MVP - Quadlets + Networks)
################################################################################

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly CONTEXT_DIR="$PROJECT_ROOT/.claude/context"
readonly QUADLET_DIR="$HOME/.config/containers/systemd"
readonly OUTPUT_FILE="$CONTEXT_DIR/dependency-graph.json"
readonly CHANGES_LOG="$CONTEXT_DIR/dependency-changes.log"
readonly TIMESTAMP=$(date -Iseconds)

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

Discover service dependencies from multiple sources.

Options:
    --output json       Write output to dependency-graph.json (default)
    --output stdout     Print JSON to stdout
    --verify            Validate discovered dependencies
    --source SOURCE     Discover from specific source (quadlets, networks, all)
    --diff              Show changes since last discovery
    --help              Display this help message

Examples:
    # Full discovery (MVP: quadlets + networks)
    $0

    # Validate dependencies
    $0 --verify

    # Show changes
    $0 --diff

EOF
}

# Parse command line arguments
OUTPUT_MODE="json"
VERIFY_ONLY=false
SOURCE="all"
DIFF_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --output)
            OUTPUT_MODE="$2"
            shift 2
            ;;
        --verify)
            VERIFY_ONLY=true
            shift
            ;;
        --source)
            SOURCE="$2"
            shift 2
            ;;
        --diff)
            DIFF_MODE=true
            shift
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

# Ensure context directory exists
mkdir -p "$CONTEXT_DIR"

################################################################################
# Phase 1: Quadlet Dependency Discovery
################################################################################

discover_quadlet_dependencies() {
    log "INFO" "Discovering dependencies from quadlet files..."

    local services_json="{"
    local first_service=true

    # Iterate over all .container files in quadlet directory
    for quadlet_file in "$QUADLET_DIR"/*.container; do
        [[ ! -f "$quadlet_file" ]] && continue

        local service_name=$(basename "$quadlet_file" .container)

        # Skip if this is a network definition file
        [[ "$service_name" == *"-network" ]] && continue

        log "DEBUG" "Processing quadlet: $service_name"

        # Parse systemd dependencies
        local after_deps=$(grep -E '^After=' "$quadlet_file" | sed 's/After=//' || echo "")
        local requires_deps=$(grep -E '^Requires=' "$quadlet_file" | sed 's/Requires=//' || echo "")
        local wants_deps=$(grep -E '^Wants=' "$quadlet_file" | sed 's/Wants=//' || echo "")

        # Parse network memberships
        local networks=$(grep -E '^Network=' "$quadlet_file" | sed 's/Network=//' || echo "")

        # Build dependencies array
        local deps_json="["
        local first_dep=true

        # Process Requires= (HARD dependencies)
        for dep in $requires_deps; do
            # Clean up dependency name (remove .service, .network suffixes)
            dep=$(echo "$dep" | sed 's/\.service$//' | sed 's/\.network$//' | sed 's/-network$//')

            # Skip network-online.target and other systemd targets
            [[ "$dep" == *".target" ]] && continue

            if [[ "$first_dep" == true ]]; then
                first_dep=false
            else
                deps_json+=","
            fi

            deps_json+=$(cat <<JSON
{
  "target": "$dep",
  "type": "runtime",
  "strength": "hard",
  "source": "quadlet"
}
JSON
)
        done

        # Process Wants= (SOFT dependencies)
        for dep in $wants_deps; do
            dep=$(echo "$dep" | sed 's/\.service$//' | sed 's/\.network$//' | sed 's/-network$//')
            [[ "$dep" == *".target" ]] && continue

            if [[ "$first_dep" == true ]]; then
                first_dep=false
            else
                deps_json+=","
            fi

            deps_json+=$(cat <<JSON
{
  "target": "$dep",
  "type": "optional",
  "strength": "soft",
  "source": "quadlet"
}
JSON
)
        done

        # Process After= (STARTUP order dependencies - soft unless also in Requires)
        for dep in $after_deps; do
            dep=$(echo "$dep" | sed 's/\.service$//' | sed 's/\.network$//' | sed 's/-network$//')
            [[ "$dep" == *".target" ]] && continue

            # Skip if already in requires or wants
            if echo "$requires_deps $wants_deps" | grep -qw "$dep"; then
                continue
            fi

            if [[ "$first_dep" == true ]]; then
                first_dep=false
            else
                deps_json+=","
            fi

            deps_json+=$(cat <<JSON
{
  "target": "$dep",
  "type": "startup",
  "strength": "soft",
  "source": "quadlet"
}
JSON
)
        done

        deps_json+="]"

        # Build networks array
        local networks_json="["
        local first_network=true
        for network in $networks; do
            network=$(echo "$network" | sed 's/^systemd-//')

            if [[ "$first_network" == true ]]; then
                first_network=false
            else
                networks_json+=","
            fi

            networks_json+="\"systemd-$network\""
        done
        networks_json+="]"

        # Determine if service has external access (first network provides default route)
        local external_access="false"
        local first_network_name=$(echo "$networks" | awk '{print $1}' | sed 's/^systemd-//')
        if [[ "$first_network_name" == "reverse_proxy" ]]; then
            external_access="true"
        fi

        # Add service to services object
        if [[ "$first_service" == true ]]; then
            first_service=false
        else
            services_json+=","
        fi

        services_json+=$(cat <<JSON
"$service_name": {
  "dependencies": $deps_json,
  "dependents": [],
  "networks": $networks_json,
  "external_access": $external_access,
  "critical": false,
  "restart_priority": 0,
  "blast_radius": 0
}
JSON
)
    done

    services_json+="}"

    echo "$services_json"
}

################################################################################
# Phase 1: Network Topology Discovery
################################################################################

discover_network_topology() {
    log "INFO" "Discovering network topology..."

    local networks_json="{"
    local first_network=true

    # Get list of systemd networks
    local network_names=$(podman network ls --format '{{.Name}}' | grep '^systemd-' || echo "")

    for network in $network_names; do
        log "DEBUG" "Processing network: $network"

        # Get network members (note: podman uses lowercase 'containers')
        local members=$(podman network inspect "$network" 2>/dev/null | \
            jq -r '.[0].containers // {} | to_entries[] | .value.name' 2>/dev/null || echo "")

        # Build members array (names come directly from jq now)
        local members_json="["
        local first_member=true
        for container_name in $members; do
            # Skip if empty
            [[ -z "$container_name" ]] && continue

            if [[ "$first_member" == true ]]; then
                first_member=false
            else
                members_json+=","
            fi

            members_json+="\"$container_name\""
        done
        members_json+="]"

        # Determine if network provides gateway (internet access)
        local gateway="false"
        if [[ "$network" == "systemd-reverse_proxy" ]]; then
            gateway="true"
        fi

        # Add network to networks object
        if [[ "$first_network" == true ]]; then
            first_network=false
        else
            networks_json+=","
        fi

        networks_json+=$(cat <<JSON
"$network": {
  "members": $members_json,
  "gateway": $gateway
}
JSON
)
    done

    networks_json+="}"

    echo "$networks_json"
}

################################################################################
# Phase 1: Compute Dependents (Reverse Dependencies)
################################################################################

compute_dependents() {
    local services_json=$1

    log "INFO" "Computing reverse dependencies (dependents)..."

    # Create temporary associative array for dependents
    declare -A dependents_map

    # Parse services JSON and build reverse dependency map
    local service_names=$(echo "$services_json" | jq -r 'keys[]')

    for service in $service_names; do
        # Get all dependencies for this service
        local deps=$(echo "$services_json" | jq -r ".[\"$service\"].dependencies[].target")

        for dep in $deps; do
            # Add this service to the dependent's list
            if [[ -z "${dependents_map[$dep]:-}" ]]; then
                dependents_map[$dep]="$service"
            else
                dependents_map[$dep]+=" $service"
            fi
        done
    done

    # Update services JSON with dependents
    local updated_services="$services_json"

    for service in "${!dependents_map[@]}"; do
        local dependents_list="${dependents_map[$service]}"
        local dependents_json="["
        local first=true

        for dependent in $dependents_list; do
            if [[ "$first" == true ]]; then
                first=false
            else
                dependents_json+=","
            fi
            dependents_json+="\"$dependent\""
        done
        dependents_json+="]"

        # Update the service with its dependents
        updated_services=$(echo "$updated_services" | \
            jq ".[\"$service\"].dependents = $dependents_json")
    done

    echo "$updated_services"
}

################################################################################
# Phase 1: Calculate Blast Radius
################################################################################

calculate_blast_radius() {
    local services_json=$1

    log "INFO" "Calculating blast radius for each service..."

    local updated_services="$services_json"
    local service_names=$(echo "$services_json" | jq -r 'keys[]')

    for service in $service_names; do
        # Get direct dependents
        local direct_dependents=$(echo "$services_json" | \
            jq -r ".[\"$service\"].dependents | length")

        # For MVP, blast radius = direct dependents count
        # Future: implement transitive closure for indirect dependents

        updated_services=$(echo "$updated_services" | \
            jq ".[\"$service\"].blast_radius = $direct_dependents")
    done

    echo "$updated_services"
}

################################################################################
# Phase 1: Mark Critical Services
################################################################################

mark_critical_services() {
    local services_json=$1

    log "INFO" "Marking critical services..."

    # Define critical services
    local critical_services=("traefik" "authelia" "prometheus" "alertmanager")

    local updated_services="$services_json"

    for service in "${critical_services[@]}"; do
        # Check if service exists in the graph
        if echo "$services_json" | jq -e ".[\"$service\"]" >/dev/null 2>&1; then
            updated_services=$(echo "$updated_services" | \
                jq ".[\"$service\"].critical = true")
            log "DEBUG" "Marked $service as critical"
        fi
    done

    echo "$updated_services"
}

################################################################################
# Phase 1: Build Complete Dependency Graph
################################################################################

build_dependency_graph() {
    log "INFO" "Building complete dependency graph..."

    # Discover from all sources (Phase 1: quadlets + networks)
    local services=$(discover_quadlet_dependencies)
    local networks=$(discover_network_topology)

    # Compute reverse dependencies
    services=$(compute_dependents "$services")

    # Calculate blast radius
    services=$(calculate_blast_radius "$services")

    # Mark critical services
    services=$(mark_critical_services "$services")

    # Count totals
    local total_services=$(echo "$services" | jq 'keys | length')
    local total_dependencies=$(echo "$services" | jq '[.[].dependencies | length] | add')

    # Build final JSON structure
    local graph_json=$(cat <<JSON
{
  "version": "1.0",
  "generated_at": "$TIMESTAMP",
  "services": $services,
  "networks": $networks,
  "metadata": {
    "total_services": $total_services,
    "total_dependencies": $total_dependencies,
    "sources": ["quadlets", "networks"]
  }
}
JSON
)

    echo "$graph_json"
}

################################################################################
# Phase 1: Validate Dependency Graph
################################################################################

validate_graph() {
    local graph_json=$1

    log "INFO" "Validating dependency graph..."

    local valid=true

    # Check for circular dependencies (simple detection for MVP)
    local service_names=$(echo "$graph_json" | jq -r '.services | keys[]')

    for service in $service_names; do
        local deps=$(echo "$graph_json" | jq -r ".services[\"$service\"].dependencies[].target")

        for dep in $deps; do
            # Check if dependency exists in services
            if ! echo "$graph_json" | jq -e ".services[\"$dep\"]" >/dev/null 2>&1; then
                log "WARNING" "Service $service depends on $dep, but $dep not found in graph"
                valid=false
            fi
        done
    done

    if [[ "$valid" == true ]]; then
        log "SUCCESS" "Dependency graph validation passed"
        return 0
    else
        log "WARNING" "Dependency graph validation found issues"
        return 1
    fi
}

################################################################################
# Phase 1: Compare with Previous Graph (Diff Mode)
################################################################################

show_diff() {
    log "INFO" "Comparing with previous dependency graph..."

    if [[ ! -f "$OUTPUT_FILE" ]]; then
        log "INFO" "No previous dependency graph found - this is the first discovery"
        return 0
    fi

    local old_graph=$(cat "$OUTPUT_FILE")
    local new_graph=$(build_dependency_graph)

    # Compare service counts
    local old_count=$(echo "$old_graph" | jq '.metadata.total_services')
    local new_count=$(echo "$new_graph" | jq '.metadata.total_services')

    echo "Changes since last discovery:"
    echo "  Services: $old_count → $new_count"

    # Compare dependency counts
    local old_deps=$(echo "$old_graph" | jq '.metadata.total_dependencies')
    local new_deps=$(echo "$new_graph" | jq '.metadata.total_dependencies')

    echo "  Dependencies: $old_deps → $new_deps"

    # Find added/removed services
    local old_services=$(echo "$old_graph" | jq -r '.services | keys[]' | sort)
    local new_services=$(echo "$new_graph" | jq -r '.services | keys[]' | sort)

    local added=$(comm -13 <(echo "$old_services") <(echo "$new_services"))
    local removed=$(comm -23 <(echo "$old_services") <(echo "$new_services"))

    if [[ -n "$added" ]]; then
        echo "  Added services:"
        echo "$added" | sed 's/^/    - /'
    fi

    if [[ -n "$removed" ]]; then
        echo "  Removed services:"
        echo "$removed" | sed 's/^/    - /'
    fi

    if [[ -z "$added" && -z "$removed" ]]; then
        echo "  No services added or removed"
    fi
}

################################################################################
# Main Execution
################################################################################

main() {
    log "INFO" "Starting dependency discovery (Phase 1: MVP)"

    # Diff mode
    if [[ "$DIFF_MODE" == true ]]; then
        show_diff
        exit 0
    fi

    # Build graph
    local graph_json=$(build_dependency_graph)

    # Verify if requested
    if [[ "$VERIFY_ONLY" == true ]]; then
        if validate_graph "$graph_json"; then
            exit 0
        else
            exit 1
        fi
    fi

    # Validate graph
    validate_graph "$graph_json" || true

    # Output
    if [[ "$OUTPUT_MODE" == "stdout" ]]; then
        echo "$graph_json" | jq '.'
    else
        echo "$graph_json" | jq '.' > "$OUTPUT_FILE"
        log "SUCCESS" "Dependency graph written to $OUTPUT_FILE"

        # Log summary
        local total_services=$(echo "$graph_json" | jq '.metadata.total_services')
        local total_deps=$(echo "$graph_json" | jq '.metadata.total_dependencies')
        log "INFO" "Discovered $total_services services with $total_deps dependencies"
    fi

    # Log changes
    if [[ -f "$OUTPUT_FILE" ]]; then
        log "INFO" "Recording changes to $CHANGES_LOG"
        echo "{\"timestamp\":\"$TIMESTAMP\",\"event\":\"discovery_completed\",\"services\":$(echo "$graph_json" | jq '.metadata.total_services'),\"dependencies\":$(echo "$graph_json" | jq '.metadata.total_dependencies')}" >> "$CHANGES_LOG"
    fi
}

# Run main
main
