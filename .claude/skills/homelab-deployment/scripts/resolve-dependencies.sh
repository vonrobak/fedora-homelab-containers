#!/bin/bash
# resolve-dependencies.sh
# Dependency resolver for multi-service stacks using topological sort (Kahn's algorithm)
#
# Purpose:
#   - Parse stack YAML to extract service dependencies
#   - Detect circular dependencies
#   - Compute deployment order using topological sort
#   - Output deployment phases (services that can be deployed in parallel)
#
# Usage:
#   ./resolve-dependencies.sh --stack <stack-file>                    # Output deployment order
#   ./resolve-dependencies.sh --stack <stack-file> --validate-only    # Check for cycles
#   ./resolve-dependencies.sh --stack <stack-file> --visualize        # Generate Graphviz DOT
#   ./resolve-dependencies.sh --stack <stack-file> --output json      # JSON output

set -euo pipefail

STACK_FILE=""
OUTPUT_FORMAT="text"  # text | json | graphviz
VALIDATE_ONLY=false
VISUALIZE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
    cat <<EOF
Usage: $0 --stack <stack-file> [options]

Resolve service dependencies and compute deployment order.

Options:
  --stack <file>         Path to stack YAML file (required)
  --output <format>      Output format: text (default), json, graphviz
  --validate-only        Only check for circular dependencies, don't output order
  --visualize            Generate Graphviz DOT output for visualization
  --help                 Show this help

Examples:
  # Show deployment order
  $0 --stack stacks/immich.yml

  # Check for circular dependencies
  $0 --stack stacks/immich.yml --validate-only

  # Generate dependency graph visualization
  $0 --stack stacks/immich.yml --visualize > deps.dot
  dot -Tpng deps.dot -o deps.png

  # JSON output for programmatic use
  $0 --stack stacks/immich.yml --output json
EOF
}

log() {
    local level=$1
    shift
    local message="$*"

    case $level in
        ERROR)   echo -e "${RED}[ERROR]${NC} $message" >&2 ;;
        SUCCESS) echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
        WARNING) echo -e "${YELLOW}[WARNING]${NC} $message" ;;
        INFO)    echo -e "${BLUE}[INFO]${NC} $message" ;;
        *)       echo "$message" ;;
    esac
}

# Python script for dependency resolution
resolve_dependencies_python() {
    local stack_file=$1
    local output_format=$2
    local mode=$3  # resolve | validate | visualize

    python3 <<EOF
import sys
import yaml
import json
from collections import defaultdict, deque

def load_stack(stack_file):
    """Load and parse stack YAML file."""
    try:
        with open(stack_file, 'r') as f:
            return yaml.safe_load(f)
    except FileNotFoundError:
        print(f"ERROR: Stack file not found: {stack_file}", file=sys.stderr)
        sys.exit(1)
    except yaml.YAMLError as e:
        print(f"ERROR: Invalid YAML syntax: {e}", file=sys.stderr)
        sys.exit(1)

def build_dependency_graph(services):
    """
    Build adjacency list and in-degree map from services.

    Returns:
        adjacency_list: dict[service] -> list of services that depend on it
        in_degree: dict[service] -> number of dependencies
        all_services: list of all service names
    """
    adjacency_list = defaultdict(list)
    in_degree = {}
    all_services = []

    # Initialize all services
    for service in services:
        name = service['name']
        all_services.append(name)
        in_degree[name] = 0

    # Build graph edges
    for service in services:
        name = service['name']
        dependencies = service.get('dependencies', [])

        if dependencies is None:
            dependencies = []

        # Set in-degree (number of dependencies)
        in_degree[name] = len(dependencies)

        # For each dependency, add this service to its adjacency list
        for dep in dependencies:
            if dep not in in_degree:
                print(f"ERROR: Service '{name}' depends on undefined service '{dep}'", file=sys.stderr)
                sys.exit(1)

            adjacency_list[dep].append(name)

    return adjacency_list, in_degree, all_services

def topological_sort(adjacency_list, in_degree, all_services):
    """
    Perform topological sort using Kahn's algorithm.

    Returns:
        phases: list of lists (each inner list is services that can be deployed in parallel)
        success: True if no cycles, False if circular dependency detected
    """
    # Queue for services with no dependencies
    queue = deque([svc for svc in all_services if in_degree[svc] == 0])

    phases = []
    resolved_count = 0

    while queue:
        # All services in queue can be deployed in parallel (same phase)
        phase_services = list(queue)
        queue.clear()

        phases.append(phase_services)
        resolved_count += len(phase_services)

        # Process each service in this phase
        for service in phase_services:
            # Reduce in-degree for all dependents
            for dependent in adjacency_list[service]:
                in_degree[dependent] -= 1

                # If in-degree becomes 0, add to next phase
                if in_degree[dependent] == 0:
                    queue.append(dependent)

    # Check for circular dependencies
    success = resolved_count == len(all_services)

    if not success:
        print(f"ERROR: Circular dependency detected!", file=sys.stderr)
        print(f"ERROR: Resolved: {resolved_count} / {len(all_services)} services", file=sys.stderr)
        print(f"ERROR: Services involved in cycle:", file=sys.stderr)
        for service in all_services:
            if in_degree[service] > 0:
                print(f"ERROR:   - {service} (in-degree: {in_degree[service]})", file=sys.stderr)

    return phases, success

def output_text(phases):
    """Output deployment order in text format."""
    for i, phase_services in enumerate(phases, 1):
        print(f"# Phase {i} (parallel: {len(phase_services)} services)")
        for service in phase_services:
            print(service)
        print()

def output_json(phases):
    """Output deployment order in JSON format."""
    result = {
        "phases": [
            {
                "phase": i,
                "parallel": True,
                "services": phase_services
            }
            for i, phase_services in enumerate(phases, 1)
        ]
    }
    print(json.dumps(result, indent=2))

def output_graphviz(adjacency_list, all_services):
    """Output dependency graph in Graphviz DOT format."""
    print("digraph ServiceDependencies {")
    print("  rankdir=LR;")
    print("  node [shape=box, style=rounded];")
    print()

    # Add nodes
    for service in all_services:
        print(f'  "{service}";')

    print()

    # Add edges
    for service, dependents in adjacency_list.items():
        for dependent in dependents:
            print(f'  "{service}" -> "{dependent}" [label="depends"];')

    print("}")

def main():
    stack_file = "${stack_file}"
    output_format = "${output_format}"
    mode = "${mode}"

    # Load stack
    stack = load_stack(stack_file)

    if 'services' not in stack or not stack['services']:
        print("ERROR: No services defined in stack file", file=sys.stderr)
        sys.exit(1)

    services = stack['services']

    # Build dependency graph
    adjacency_list, in_degree, all_services = build_dependency_graph(services)

    if mode == "visualize":
        output_graphviz(adjacency_list, all_services)
        sys.exit(0)

    # Perform topological sort
    phases, success = topological_sort(adjacency_list, in_degree, all_services)

    if not success:
        sys.exit(1)

    if mode == "validate":
        print("SUCCESS: No circular dependencies detected", file=sys.stderr)
        sys.exit(0)

    # Output deployment order
    if output_format == "json":
        output_json(phases)
    else:
        output_text(phases)

if __name__ == "__main__":
    main()
EOF
}

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --stack)
                STACK_FILE="$2"
                shift 2
                ;;
            --output)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --visualize)
                VISUALIZE=true
                shift
                ;;
            --validate-only)
                VALIDATE_ONLY=true
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    if [[ -z "$STACK_FILE" ]]; then
        echo "Error: --stack is required"
        usage
        exit 1
    fi

    # Determine mode
    local mode="resolve"
    if [[ "$VISUALIZE" == "true" ]]; then
        mode="visualize"
    elif [[ "$VALIDATE_ONLY" == "true" ]]; then
        mode="validate"
    fi

    # Run Python script
    resolve_dependencies_python "$STACK_FILE" "$OUTPUT_FORMAT" "$mode"
}

main "$@"
