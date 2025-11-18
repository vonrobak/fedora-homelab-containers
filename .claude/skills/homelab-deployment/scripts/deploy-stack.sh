#!/bin/bash
# deploy-stack.sh
# Multi-service stack deployment orchestrator
#
# Purpose:
#   - Deploy entire application stacks with dependency resolution
#   - Coordinate health checks across services
#   - Provide atomic rollback on failure
#   - Integrate with existing homelab-deployment patterns
#
# Usage:
#   ./deploy-stack.sh --stack <name>           # Deploy stack from stacks/<name>.yml
#   ./deploy-stack.sh --stack <name> --dry-run # Show deployment plan without executing
#   ./deploy-stack.sh --help                   # Show usage

set -euo pipefail

STACK_NAME=""
STACK_FILE=""
DRY_RUN=false
SKIP_HEALTH_CHECK=false
ROLLBACK_ON_FAILURE=true
VERBOSE=false

# State tracking
declare -A SERVICE_STATUS  # service -> "pending" | "deploying" | "healthy" | "failed"
declare -A SERVICE_START_TIME
DEPLOYMENT_LOG=""
DEPLOYED_SERVICES=()

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

usage() {
    cat <<EOF
Usage: $0 --stack <name> [options]

Deploy a multi-service stack with dependency orchestration.

Options:
  --stack <name>           Stack name (looks for stacks/<name>.yml)
  --stack-file <path>      Path to stack YAML file (alternative to --stack)
  --dry-run                Show what would be deployed without executing
  --skip-health-check      Don't wait for health checks (faster, risky)
  --no-rollback            Don't rollback on failure (leave partial deployment)
  --verbose                Verbose output
  --help                   Show this help

Examples:
  # Deploy Immich stack
  $0 --stack immich

  # Dry-run (show plan without deploying)
  $0 --stack monitoring-simple --dry-run

  # Deploy without health checks (fast, for testing)
  $0 --stack immich --skip-health-check --no-rollback

  # Verbose output for debugging
  $0 --stack immich --verbose
EOF
}

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Log to file
    if [[ -n "$DEPLOYMENT_LOG" ]]; then
        echo "[$timestamp] [$level] $message" >> "$DEPLOYMENT_LOG"
    fi

    # Log to console with colors
    case $level in
        ERROR)   echo -e "${RED}[ERROR]${NC} $message" >&2 ;;
        SUCCESS) echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
        WARNING) echo -e "${YELLOW}[WARNING]${NC} $message" ;;
        INFO)    echo -e "${BLUE}[INFO]${NC} $message" ;;
        DEBUG)   [[ "$VERBOSE" == "true" ]] && echo -e "${CYAN}[DEBUG]${NC} $message" ;;
        *)       echo "$message" ;;
    esac
}

# Parse stack metadata using Python + PyYAML
get_stack_value() {
    local stack_file=$1
    local path=$2  # e.g., "stack.name" or "shared.domain"

    python3 <<EOF
import yaml
import sys

try:
    with open('$stack_file', 'r') as f:
        stack = yaml.safe_load(f)

    # Navigate nested path
    keys = '$path'.split('.')
    value = stack
    for key in keys:
        value = value.get(key, None)
        if value is None:
            break

    if value is not None:
        print(value)
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
EOF
}

# Pre-flight validation
preflight_validation() {
    local stack_file=$1

    log INFO "Running pre-flight validation..."

    # 1. Validate stack file exists and is valid YAML
    if [[ ! -f "$stack_file" ]]; then
        log ERROR "Stack file not found: $stack_file"
        return 1
    fi

    if ! python3 -c "import yaml; yaml.safe_load(open('$stack_file'))" 2>/dev/null; then
        log ERROR "Invalid YAML syntax in stack file"
        return 1
    fi

    # 2. Check for circular dependencies
    log DEBUG "Checking for circular dependencies..."
    if ! "$SCRIPT_DIR/resolve-dependencies.sh" --stack "$stack_file" --validate-only 2>&1 | grep -q "SUCCESS"; then
        log ERROR "Circular dependency detected in stack"
        return 1
    fi

    # 3. Verify networks exist
    log DEBUG "Verifying networks..."
    local network_count=$(python3 -c "import yaml; s = yaml.safe_load(open('$stack_file')); print(len(s.get('shared', {}).get('networks', [])))")

    if [[ "$network_count" -gt 0 ]]; then
        local i=0
        while [[ $i -lt $network_count ]]; do
            local network=$(python3 -c "import yaml; s = yaml.safe_load(open('$stack_file')); print(s['shared']['networks'][$i])")

            if ! podman network exists "$network" 2>/dev/null; then
                log ERROR "Network not found: $network"
                log INFO "Create network with: podman network create $network"
                return 1
            fi

            ((i++))
        done
        log DEBUG "All networks exist"
    fi

    # 4. Check available memory
    local total_memory=$(get_stack_value "$stack_file" "shared.resources.total_memory_mb" 2>/dev/null || echo "0")
    if [[ "$total_memory" -gt 0 ]]; then
        local available_memory=$(free -m | awk '/^Mem:/{print $7}')

        if [[ $total_memory -gt $available_memory ]]; then
            log WARNING "Requested memory ($total_memory MB) > available ($available_memory MB)"

            if [[ "$DRY_RUN" == "false" ]]; then
                read -p "Continue anyway? (y/n) " -n 1 -r
                echo
                [[ ! $REPLY =~ ^[Yy]$ ]] && return 1
            fi
        fi
        log DEBUG "Memory capacity OK ($available_memory MB available, $total_memory MB requested)"
    fi

    log SUCCESS "Pre-flight validation passed"
    return 0
}

# Deploy a single service
deploy_service() {
    local stack_file=$1
    local service_name=$2

    log INFO "Deploying service: $service_name"
    SERVICE_STATUS[$service_name]="deploying"
    SERVICE_START_TIME[$service_name]=$(date +%s)

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would deploy: $service_name"
        SERVICE_STATUS[$service_name]="healthy"
        DEPLOYED_SERVICES+=("$service_name")
        return 0
    fi

    # Extract service configuration using Python
    local config_json=$(python3 <<EOF
import yaml
import json

with open('$stack_file', 'r') as f:
    stack = yaml.safe_load(f)

services = stack.get('services', [])
for svc in services:
    if svc['name'] == '$service_name':
        print(json.dumps(svc))
        break
EOF
)

    if [[ -z "$config_json" ]]; then
        log ERROR "Service not found in stack: $service_name"
        SERVICE_STATUS[$service_name]="failed"
        return 1
    fi

    log DEBUG "Service config: $config_json"

    # Generate quadlet file for this service
    if ! generate_quadlet_from_stack "$service_name" "$config_json" "$stack_file"; then
        log ERROR "Failed to generate quadlet for $service_name"
        SERVICE_STATUS[$service_name]="failed"
        return 1
    fi

    # Deploy using existing deploy-service.sh infrastructure
    log INFO "Deploying $service_name via systemd..."
    if "$SCRIPT_DIR/deploy-service.sh" --service "$service_name" --wait-for-healthy --timeout 300 >> "$DEPLOYMENT_LOG" 2>&1; then
        SERVICE_STATUS[$service_name]="deployed"
        DEPLOYED_SERVICES+=("$service_name")
        log SUCCESS "Service deployed: $service_name"
        return 0
    else
        log ERROR "Deployment failed: $service_name"
        log ERROR "Check logs: journalctl --user -u ${service_name}.service"
        SERVICE_STATUS[$service_name]="failed"
        return 1
    fi
}

# Generate quadlet file from stack configuration
generate_quadlet_from_stack() {
    local service_name=$1
    local config_json=$2
    local stack_file=$3

    local quadlet_dir="$HOME/.config/containers/systemd"
    local quadlet_file="$quadlet_dir/${service_name}.container"

    mkdir -p "$quadlet_dir"

    log DEBUG "Generating quadlet: $quadlet_file"

    # Extract configuration fields using Python
    python3 <<EOF > "$quadlet_file"
import yaml
import json

# Load stack and service config
with open('$stack_file', 'r') as f:
    stack = yaml.safe_load(f)

config = json.loads('$config_json')
service_config = config.get('configuration', {})

# Get shared config
shared = stack.get('shared', {})

# Print quadlet file
print("[Unit]")
print(f"Description={service_name} container (deployed via stack)")
print("After=network-online.target")
print("Wants=network-online.target")
print("")

print("[Container]")
print(f"ContainerName={service_name}")

# Image
image = service_config.get('image', 'docker.io/library/alpine:latest')
print(f"Image={image}")

# Memory limits
memory = service_config.get('memory', '512M')
print(f"Memory={memory}")

# Environment variables
env_vars = service_config.get('environment', {})
if isinstance(env_vars, dict):
    for key, value in env_vars.items():
        # Handle environment variable substitution
        if value.startswith('\${') and value.endswith('}'):
            var_name = value[2:-1]
            print(f"Environment={key}=%{var_name}")
        else:
            print(f"Environment={key}={value}")

# Volumes
volumes = service_config.get('volumes', [])
for volume in volumes:
    # Expand variables like \${storage_base}
    volume_expanded = volume
    if '\${storage_base}' in volume:
        storage_base = shared.get('storage_base', '/mnt/btrfs-pool/subvol7-containers')
        volume_expanded = volume.replace('\${storage_base}', storage_base)

    print(f"Volume={volume_expanded}")

# Networks
networks = service_config.get('networks', shared.get('networks', []))
for network in networks:
    print(f"Network={network}")

# Labels (Traefik, Prometheus)
labels = service_config.get('labels', [])
for label in labels:
    # Expand \${domain} variable
    label_expanded = label
    if '\${domain}' in label:
        domain = shared.get('domain', 'example.patriark.org')
        label_expanded = label.replace('\${domain}', domain)

    print(f"Label={label_expanded}")

# Health check
healthcheck = service_config.get('healthcheck', {})
if healthcheck:
    test = healthcheck.get('test', [])
    if test:
        test_cmd = ' '.join(test) if isinstance(test, list) else test
        print(f"HealthCmd={test_cmd}")

    interval = healthcheck.get('interval', '30s')
    print(f"HealthInterval={interval}")

    timeout = healthcheck.get('timeout', '10s')
    print(f"HealthTimeout={timeout}")

    retries = healthcheck.get('retries', 3)
    print(f"HealthRetries={retries}")

# Auto-update (disabled for stack-managed services)
print("AutoUpdate=disabled")

print("")
print("[Service]")
print("Restart=always")
print("TimeoutStartSec=300")
print("")

print("[Install]")
print("WantedBy=multi-user.target default.target")
EOF

    if [[ ! -f "$quadlet_file" ]]; then
        log ERROR "Failed to create quadlet file: $quadlet_file"
        return 1
    fi

    log SUCCESS "Quadlet generated: $quadlet_file"
    return 0
}

# Wait for service to be healthy
wait_for_healthy() {
    local service_name=$1
    local timeout=${2:-300}

    if [[ "$SKIP_HEALTH_CHECK" == "true" ]]; then
        log WARNING "Skipping health check for $service_name"
        SERVICE_STATUS[$service_name]="healthy"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        SERVICE_STATUS[$service_name]="healthy"
        return 0
    fi

    log INFO "Waiting for $service_name to be healthy (timeout: ${timeout}s)"

    local start_time=$(date +%s)
    local poll_interval=5

    while true; do
        local elapsed=$(($(date +%s) - start_time))

        if [[ $elapsed -ge $timeout ]]; then
            log ERROR "Health check timeout for $service_name (${timeout}s)"
            SERVICE_STATUS[$service_name]="failed"
            return 1
        fi

        # Check systemd service status
        if systemctl --user is-active "${service_name}.service" &>/dev/null; then
            # Check container health check (if available)
            if podman healthcheck run "$service_name" &>/dev/null; then
                local total_time=$(($(date +%s) - ${SERVICE_START_TIME[$service_name]}))
                log SUCCESS "$service_name is healthy (took ${total_time}s)"
                SERVICE_STATUS[$service_name]="healthy"
                return 0
            fi
        fi

        log DEBUG "$service_name not ready yet (${elapsed}s elapsed)..."
        sleep $poll_interval
    done
}

# Deploy services in a phase
deploy_phase() {
    local stack_file=$1
    local phase_number=$2
    shift 2
    local services=("$@")

    log INFO "=========================================="
    log INFO "Phase $phase_number: Deploying ${#services[@]} service(s)"
    log INFO "=========================================="

    # Check if parallel deployment is beneficial (multiple services)
    if [[ ${#services[@]} -gt 1 ]]; then
        log INFO "Deploying services in parallel..."

        # Deploy all services in background
        declare -A service_pids
        for service in "${services[@]}"; do
            (
                if ! deploy_service "$stack_file" "$service"; then
                    exit 1
                fi
            ) &
            service_pids[$service]=$!
            log DEBUG "Started deployment of $service (PID: ${service_pids[$service]})"
        done

        # Wait for all deployments to complete
        local all_success=true
        for service in "${services[@]}"; do
            if wait ${service_pids[$service]}; then
                log SUCCESS "Parallel deployment succeeded: $service"
            else
                log ERROR "Parallel deployment failed: $service"
                all_success=false
            fi
        done

        if [[ "$all_success" == "false" ]]; then
            log ERROR "One or more services failed in parallel deployment"
            return 1
        fi
    else
        # Single service - deploy sequentially
        for service in "${services[@]}"; do
            if ! deploy_service "$stack_file" "$service"; then
                log ERROR "Deployment failed: $service"
                return 1
            fi
        done
    fi

    log SUCCESS "Phase $phase_number complete"
    return 0
}

# Rollback deployed services
rollback_stack() {
    log WARNING "=========================================="
    log WARNING "Rolling back stack deployment..."
    log WARNING "=========================================="

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would rollback: ${DEPLOYED_SERVICES[*]}"
        return 0
    fi

    # Stop services in reverse order
    for ((i=${#DEPLOYED_SERVICES[@]}-1; i>=0; i--)); do
        local service="${DEPLOYED_SERVICES[$i]}"
        log INFO "Stopping: $service"

        systemctl --user stop "${service}.service" 2>/dev/null || true

        # Optionally remove quadlet
        if [[ -f "$HOME/.config/containers/systemd/${service}.container" ]]; then
            log DEBUG "Removing quadlet: ${service}.container"
            rm -f "$HOME/.config/containers/systemd/${service}.container"
        fi
    done

    # Reload systemd
    log INFO "Reloading systemd..."
    systemctl --user daemon-reload

    log WARNING "Rollback complete. ${#DEPLOYED_SERVICES[@]} service(s) stopped and removed."
}

# Main orchestration
orchestrate_deployment() {
    local stack_file=$1

    log INFO "Resolving dependencies..."

    # Get deployment phases from dependency resolver
    local phases_json=$("$SCRIPT_DIR/resolve-dependencies.sh" --stack "$stack_file" --output json)

    if [[ -z "$phases_json" ]]; then
        log ERROR "Failed to resolve dependencies"
        return 1
    fi

    # Parse phases and deploy
    local phase_count=$(echo "$phases_json" | python3 -c "import json, sys; print(len(json.load(sys.stdin)['phases']))")

    log INFO "Deployment plan: $phase_count phases"
    echo ""

    local phase_num=1
    while [[ $phase_num -le $phase_count ]]; do
        # Get services for this phase
        local services=$(echo "$phases_json" | python3 -c "import json, sys; print(' '.join(json.load(sys.stdin)['phases'][$((phase_num - 1))]['services']))")

        # Deploy this phase
        if ! deploy_phase "$stack_file" "$phase_num" $services; then
            log ERROR "Phase $phase_num failed"
            return 1
        fi

        ((phase_num++))
        echo ""
    done

    log SUCCESS "All phases deployed successfully"
    return 0
}

# Post-deployment validation
post_deployment_validation() {
    local stack_file=$1

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would run post-deployment validation"
        return 0
    fi

    log INFO "Running post-deployment validation..."

    # Check if validation tests are defined
    local has_validation=$(python3 -c "import yaml; s = yaml.safe_load(open('$stack_file')); print('validation' in s and 'tests' in s['validation'])" 2>/dev/null || echo "False")

    if [[ "$has_validation" != "True" ]]; then
        log INFO "No validation tests defined"
        return 0
    fi

    # Get test count
    local test_count=$(python3 -c "import yaml; s = yaml.safe_load(open('$stack_file')); print(len(s.get('validation', {}).get('tests', [])))")

    if [[ "$test_count" == "0" ]]; then
        log INFO "No validation tests defined"
        return 0
    fi

    log INFO "Running $test_count validation test(s)..."

    local i=0
    local failed_tests=0

    while [[ $i -lt $test_count ]]; do
        # Extract test details
        local test_info=$(python3 <<EOF
import yaml
import json

with open('$stack_file', 'r') as f:
    stack = yaml.safe_load(f)

test = stack.get('validation', {}).get('tests', [])[$i]
print(json.dumps(test))
EOF
)

        local test_name=$(echo "$test_info" | python3 -c "import json, sys; print(json.load(sys.stdin)['name'])")
        local test_type=$(echo "$test_info" | python3 -c "import json, sys; print(json.load(sys.stdin)['type'])")

        log INFO "Test $((i+1))/$test_count: $test_name"

        # Run test based on type
        case $test_type in
            http_get)
                local url=$(echo "$test_info" | python3 -c "import json, sys; print(json.load(sys.stdin)['url'])")
                local expected_status=$(echo "$test_info" | python3 -c "import json, sys; print(json.load(sys.stdin)['expected_status'])")

                local actual_status=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "0")

                if [[ "$actual_status" == "$expected_status" ]]; then
                    log SUCCESS "✓ $test_name (HTTP $actual_status)"
                else
                    log ERROR "✗ $test_name (expected $expected_status, got $actual_status)"
                    ((failed_tests++))
                fi
                ;;

            sql_query)
                local target=$(echo "$test_info" | python3 -c "import json, sys; print(json.load(sys.stdin)['target'])")
                local query=$(echo "$test_info" | python3 -c "import json, sys; print(json.load(sys.stdin)['query'])")

                if podman exec "$target" psql -U postgres -c "$query" &>/dev/null; then
                    log SUCCESS "✓ $test_name"
                else
                    log ERROR "✗ $test_name (SQL query failed)"
                    ((failed_tests++))
                fi
                ;;

            redis_ping)
                local target=$(echo "$test_info" | python3 -c "import json, sys; print(json.load(sys.stdin)['target'])")

                local response=$(podman exec "$target" redis-cli ping 2>/dev/null || echo "ERROR")

                if [[ "$response" == "PONG" ]]; then
                    log SUCCESS "✓ $test_name"
                else
                    log ERROR "✗ $test_name (Redis did not respond with PONG)"
                    ((failed_tests++))
                fi
                ;;

            *)
                log WARNING "Unknown test type: $test_type (skipping)"
                ;;
        esac

        ((i++))
    done

    if [[ $failed_tests -gt 0 ]]; then
        log WARNING "$failed_tests validation test(s) failed"
        return 1
    fi

    log SUCCESS "All validation tests passed"
    return 0
}

# Post-deployment summary
show_summary() {
    local stack_file=$1
    local stack_name=$(get_stack_value "$stack_file" "stack.name")

    echo ""
    log SUCCESS "=========================================="
    log SUCCESS "Stack deployment complete: $stack_name"
    log SUCCESS "=========================================="
    echo ""

    log INFO "Deployed services:"
    for service in "${DEPLOYED_SERVICES[@]}"; do
        echo "  ✓ $service"
    done

    echo ""
    log INFO "Deployment log: $DEPLOYMENT_LOG"

    # Show post-deployment docs if available
    local has_docs=$(python3 -c "import yaml; s = yaml.safe_load(open('$stack_file')); print('documentation' in s and 'post_deployment' in s['documentation'])" 2>/dev/null || echo "False")

    if [[ "$has_docs" == "True" ]]; then
        echo ""
        log INFO "Post-Deployment Instructions:"
        python3 <<EOF
import yaml
with open('$stack_file', 'r') as f:
    stack = yaml.safe_load(f)
    for item in stack.get('documentation', {}).get('post_deployment', []):
        print(f"  - {item}")
EOF
    fi

    echo ""
}

main() {
    # Get script directory
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --stack)
                STACK_NAME="$2"
                STACK_FILE="$SCRIPT_DIR/../stacks/$2.yml"
                shift 2
                ;;
            --stack-file)
                STACK_FILE="$2"
                STACK_NAME=$(basename "$2" .yml)
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-health-check)
                SKIP_HEALTH_CHECK=true
                shift
                ;;
            --no-rollback)
                ROLLBACK_ON_FAILURE=false
                shift
                ;;
            --verbose)
                VERBOSE=true
                set -x
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
        echo "Error: --stack or --stack-file is required"
        usage
        exit 1
    fi

    # Setup logging
    mkdir -p "$HOME/containers/data/deployment-logs"
    DEPLOYMENT_LOG="$HOME/containers/data/deployment-logs/stack-${STACK_NAME}-$(date +%Y%m%d-%H%M%S).log"

    log INFO "=========================================="
    log INFO "Stack Deployment: $STACK_NAME"
    log INFO "=========================================="
    [[ "$DRY_RUN" == "true" ]] && log WARNING "DRY-RUN MODE - No changes will be made"
    echo ""

    # Phase 1: Pre-flight validation
    if ! preflight_validation "$STACK_FILE"; then
        log ERROR "Pre-flight validation failed. Aborting deployment."
        exit 1
    fi

    echo ""

    # Phase 2: Orchestrate deployment
    if ! orchestrate_deployment "$STACK_FILE"; then
        log ERROR "Deployment failed"

        if [[ "$ROLLBACK_ON_FAILURE" == "true" ]]; then
            echo ""
            rollback_stack
        else
            log WARNING "Rollback disabled. Partial deployment remains."
        fi

        exit 1
    fi

    echo ""

    # Phase 3: Post-deployment validation
    if ! post_deployment_validation "$STACK_FILE"; then
        log WARNING "Post-deployment validation failed"

        if [[ "$ROLLBACK_ON_FAILURE" == "true" && "$DRY_RUN" == "false" ]]; then
            read -p "Rollback deployment? (y/n) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo ""
                rollback_stack
                exit 1
            fi
        fi
    fi

    # Success summary
    show_summary "$STACK_FILE"
}

main "$@"
