#!/bin/bash
# Auto-Documentation Orchestrator
# Runs all documentation generators in sequence

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCS_DIR="${HOME}/containers/docs"

log() {
    echo "[$(date +'%H:%M:%S')] $*"
}

error() {
    echo "[$(date +'%H:%M:%S')] ERROR: $*" >&2
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."

    if ! command -v podman &> /dev/null; then
        error "podman is required"
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        error "jq is required"
        exit 1
    fi

    log "✓ Prerequisites met"
}

# Run a generator script
run_generator() {
    local script=$1
    local description=$2

    log "Running: $description..."

    if [[ ! -x "$script" ]]; then
        error "Script not executable: $script"
        return 1
    fi

    if "$script"; then
        log "✓ $description complete"
        return 0
    else
        error "$description failed"
        return 1
    fi
}

# Main
main() {
    local start_time=$(date +%s)

    log "========================================="
    log "Auto-Documentation Orchestrator"
    log "========================================="
    log ""

    check_prerequisites
    log ""

    # Track success/failure
    local failures=0

    # Phase 1: Service Catalog
    if ! run_generator "${SCRIPT_DIR}/generate-service-catalog-simple.sh" "Service Catalog"; then
        ((failures++))
    fi
    log ""

    # Phase 2: Network Topology
    if ! run_generator "${SCRIPT_DIR}/generate-network-topology.sh" "Network Topology"; then
        ((failures++))
    fi
    log ""

    # Phase 3: Dependency Graph
    if ! run_generator "${SCRIPT_DIR}/generate-dependency-graph.sh" "Dependency Graph"; then
        ((failures++))
    fi
    log ""

    # Phase 4: Documentation Index
    if ! run_generator "${SCRIPT_DIR}/generate-doc-index.sh" "Documentation Index"; then
        ((failures++))
    fi
    log ""

    # Summary
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    log "========================================="
    log "Summary"
    log "========================================="
    log "Duration: ${duration}s"
    log "Failures: $failures"
    log ""

    if [[ $failures -eq 0 ]]; then
        log "✓ All documentation generated successfully!"
        log ""
        log "Generated files:"
        log "  - ${DOCS_DIR}/AUTO-SERVICE-CATALOG.md"
        log "  - ${DOCS_DIR}/AUTO-NETWORK-TOPOLOGY.md"
        log "  - ${DOCS_DIR}/AUTO-DEPENDENCY-GRAPH.md"
        log "  - ${DOCS_DIR}/AUTO-DOCUMENTATION-INDEX.md"
        log ""
        log "You can view these in GitHub - Mermaid diagrams will render automatically."
        return 0
    else
        error "Some generators failed. Check logs above."
        return 1
    fi
}

main "$@"
