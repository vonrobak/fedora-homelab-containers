#!/bin/bash
################################################################################
# export-dependency-metrics.sh
# Export dependency graph metrics to Prometheus via text file collector
#
# Writes metrics to the node_exporter textfile collector directory.
# Metrics are automatically scraped by Prometheus.
#
# Metrics exported:
# - homelab_service_dependency_count: Number of dependencies per service
# - homelab_service_dependent_count: Number of services depending on each service
# - homelab_service_blast_radius: Total affected services if this one fails
# - homelab_dependency_health: Health of service dependencies (0/1)
# - homelab_dependency_graph_staleness_seconds: Time since last graph update
# - homelab_dependency_drift_detected: Whether drift was detected (0/1)
# - homelab_network_member_count: Services per network
# - homelab_dependency_chain_depth: Maximum dependency chain depth
# - homelab_critical_service_status: Critical service up/down status
#
# Usage:
#   ./export-dependency-metrics.sh           # Export metrics
#   ./export-dependency-metrics.sh --dry-run # Print metrics without writing
#
# Author: Claude (Autonomous Service Dependency Mapping)
# Version: 1.0.0
# Phase: 2 (Metrics & Monitoring)
################################################################################

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly CONTEXT_DIR="$PROJECT_ROOT/.claude/context"
readonly GRAPH_FILE="$CONTEXT_DIR/dependency-graph.json"
readonly METRICS_DIR="$PROJECT_ROOT/data/backup-metrics"
readonly METRICS_FILE="$METRICS_DIR/dependency_metrics.prom"
readonly TEMP_FILE="$METRICS_FILE.tmp"

# Logging
log() {
    local level=$1
    shift
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $*" >&2
}

# Parse arguments
DRY_RUN=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            echo "Usage: $(basename "$0") [--dry-run]"
            exit 0
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check if dependency graph exists
if [[ ! -f "$GRAPH_FILE" ]]; then
    log "ERROR" "Dependency graph not found at $GRAPH_FILE"
    log "INFO" "Run discover-dependencies.sh first"
    exit 1
fi

# Ensure metrics directory exists
mkdir -p "$METRICS_DIR"

################################################################################
# Metric Generation Functions
################################################################################

# Generate HELP and TYPE headers for a metric
metric_header() {
    local name=$1
    local type=$2
    local help=$3

    echo "# HELP $name $help"
    echo "# TYPE $name $type"
}

# Export dependency count metrics
export_dependency_counts() {
    log "INFO" "Exporting dependency count metrics..."

    metric_header "homelab_service_dependency_count" "gauge" "Number of dependencies for each service"

    # Get all services and their dependency counts by type
    jq -r '
        .services | to_entries[] |
        select(.value.dependencies != null and (.value.dependencies | length) > 0) |
        .key as $service |
        .value.dependencies |
        group_by(.strength) |
        .[] |
        {
            service: $service,
            strength: .[0].strength,
            count: length
        } |
        "homelab_service_dependency_count{service=\"\(.service)\",type=\"\(.strength)\"} \(.count)"
    ' "$GRAPH_FILE"

    echo ""
}

# Export dependent count metrics (reverse dependencies)
export_dependent_counts() {
    log "INFO" "Exporting dependent count metrics..."

    metric_header "homelab_service_dependent_count" "gauge" "Number of services that depend on this service"

    jq -r '
        .services | to_entries[] |
        "homelab_service_dependent_count{service=\"\(.key)\"} \(.value.dependents | length)"
    ' "$GRAPH_FILE"

    echo ""
}

# Export blast radius metrics
export_blast_radius() {
    log "INFO" "Exporting blast radius metrics..."

    metric_header "homelab_service_blast_radius" "gauge" "Number of services affected if this service fails"

    jq -r '
        .services | to_entries[] |
        "homelab_service_blast_radius{service=\"\(.key)\"} \(.value.blast_radius)"
    ' "$GRAPH_FILE"

    echo ""
}

# Export dependency health metrics
export_dependency_health() {
    log "INFO" "Exporting dependency health metrics..."

    metric_header "homelab_dependency_health" "gauge" "Health status of service dependencies (0=unhealthy, 1=healthy)"

    # Check health of each dependency
    local services=$(jq -r '.services | keys[]' "$GRAPH_FILE")

    for service in $services; do
        local deps=$(jq -r ".services[\"$service\"].dependencies[].target" "$GRAPH_FILE" 2>/dev/null || echo "")

        for dep in $deps; do
            # Check if dependency service is running
            local health=1
            if ! systemctl --user is-active "$dep.service" >/dev/null 2>&1; then
                # Try without .service suffix (might be a network)
                if ! podman ps --format '{{.Names}}' | grep -qw "^$dep$"; then
                    health=0
                fi
            fi

            echo "homelab_dependency_health{service=\"$service\",dependency=\"$dep\"} $health"
        done
    done

    echo ""
}

# Export graph staleness metric
export_staleness() {
    log "INFO" "Exporting graph staleness metrics..."

    metric_header "homelab_dependency_graph_staleness_seconds" "gauge" "Time since dependency graph was last updated"

    local generated_at=$(jq -r '.generated_at' "$GRAPH_FILE")
    local generated_epoch=$(date -d "$generated_at" +%s 2>/dev/null || echo "0")
    local now_epoch=$(date +%s)
    local staleness=$((now_epoch - generated_epoch))

    echo "homelab_dependency_graph_staleness_seconds $staleness"
    echo ""
}

# Export drift detection metric (placeholder - will be implemented in Phase 4)
export_drift_detection() {
    log "INFO" "Exporting drift detection metrics..."

    metric_header "homelab_dependency_drift_detected" "gauge" "Whether dependency drift was detected (1=drift, 0=clean)"

    # For now, set all to 0 (no drift detected)
    # Phase 4 will implement actual drift detection
    local services=$(jq -r '.services | keys[]' "$GRAPH_FILE")

    for service in $services; do
        echo "homelab_dependency_drift_detected{service=\"$service\",type=\"systemd\"} 0"
    done

    echo ""
}

# Export network membership counts
export_network_counts() {
    log "INFO" "Exporting network membership metrics..."

    metric_header "homelab_network_member_count" "gauge" "Number of services on each network"

    jq -r '
        .networks | to_entries[] |
        "homelab_network_member_count{network=\"\(.key)\"} \(.value.members | length)"
    ' "$GRAPH_FILE"

    echo ""
}

# Export dependency chain depth metrics
export_chain_depth() {
    log "INFO" "Exporting dependency chain depth metrics..."

    metric_header "homelab_dependency_chain_depth" "gauge" "Maximum dependency chain depth for each service"

    # Calculate chain depth using BFS
    # For MVP, use simple direct dependency count as approximation
    # Full transitive closure would be more accurate but expensive

    jq -r '
        .services | to_entries[] |
        "homelab_dependency_chain_depth{service=\"\(.key)\"} \((.value.dependencies // []) | length)"
    ' "$GRAPH_FILE"

    echo ""
}

# Export critical service status
export_critical_status() {
    log "INFO" "Exporting critical service status metrics..."

    metric_header "homelab_critical_service_status" "gauge" "Status of critical services (1=running, 0=down)"

    # Get critical services
    local critical_services=$(jq -r '.services | to_entries[] | select(.value.critical == true) | .key' "$GRAPH_FILE")

    for service in $critical_services; do
        local status=0
        if systemctl --user is-active "$service.service" >/dev/null 2>&1; then
            status=1
        elif podman ps --format '{{.Names}}' | grep -qw "^$service$"; then
            status=1
        fi

        echo "homelab_critical_service_status{service=\"$service\"} $status"
    done

    echo ""
}

# Export metadata metrics
export_metadata() {
    log "INFO" "Exporting metadata metrics..."

    metric_header "homelab_dependency_graph_info" "gauge" "Dependency graph metadata"

    local total_services=$(jq -r '.metadata.total_services' "$GRAPH_FILE")
    local total_deps=$(jq -r '.metadata.total_dependencies' "$GRAPH_FILE")
    local version=$(jq -r '.version' "$GRAPH_FILE")

    echo "homelab_dependency_graph_info{version=\"$version\"} 1"

    metric_header "homelab_dependency_total_services" "gauge" "Total number of services in dependency graph"
    echo "homelab_dependency_total_services $total_services"

    metric_header "homelab_dependency_total_dependencies" "gauge" "Total number of dependencies in graph"
    echo "homelab_dependency_total_dependencies $total_deps"

    echo ""
}

################################################################################
# Main Execution
################################################################################

generate_all_metrics() {
    # Header
    echo "# Dependency mapping metrics"
    echo "# Generated at: $(date -Iseconds)"
    echo "# Source: $GRAPH_FILE"
    echo ""

    # Export all metric types
    export_metadata
    export_dependency_counts
    export_dependent_counts
    export_blast_radius
    export_staleness
    export_network_counts
    export_chain_depth
    export_critical_status
    export_dependency_health
    export_drift_detection
}

main() {
    log "INFO" "Starting dependency metrics export"

    if [[ "$DRY_RUN" == true ]]; then
        log "INFO" "Dry run mode - printing to stdout"
        generate_all_metrics
        log "SUCCESS" "Dry run complete"
    else
        # Write to temp file first, then atomic rename
        generate_all_metrics > "$TEMP_FILE"

        # Atomic rename to prevent partial reads
        mv "$TEMP_FILE" "$METRICS_FILE"

        log "SUCCESS" "Metrics written to $METRICS_FILE"

        # Show summary
        local metric_count=$(grep -c "^homelab_" "$METRICS_FILE" || echo "0")
        log "INFO" "Exported $metric_count metric data points"
    fi
}

# Run main
main
