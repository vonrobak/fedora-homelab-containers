# Session 5: Multi-Service Orchestration Framework

**Status:** Planning Complete, Ready for CLI Execution
**Priority:** 🚀 HIGH (Deployment Efficiency)
**Dependencies:** Session 3 (homelab-deployment skill) ✅ Complete
**Optional Enhancement:** Session 4 (context framework) - not required
**Estimated Effort:** 6-8 hours (2-3 CLI sessions)
**Target:** Level 2 Automation (Coordinated Multi-Service Deployment)

---

## Executive Summary

Your homelab has **excellent single-service deployment** (9 patterns, drift detection, validation), but deploying complex multi-service stacks is still manual and error-prone.

**Current Reality:**
```bash
# Deploying Immich stack (5 services) - MANUAL
./deploy-from-pattern.sh --pattern database-service --service-name immich-postgres
# Wait... is it healthy?
./deploy-from-pattern.sh --pattern cache-service --service-name immich-redis
# Wait... is it healthy?
./deploy-from-pattern.sh --pattern document-management --service-name immich
# Immich fails because postgres wasn't ready yet
# Start over, add sleep timers, hope it works this time...
```

**After Session 5:**
```bash
# Deploy Immich stack (5 services) - ORCHESTRATED
./deploy-stack.sh --stack immich

# Orchestrator automatically:
# 1. Validates all prerequisites
# 2. Deploys in dependency order (postgres → redis → immich-server → immich-ml → immich-web)
# 3. Waits for each service to be healthy
# 4. Rolls back entire stack if any service fails
# 5. Verifies stack health
# Total time: 5-8 minutes, zero manual intervention
```

**The Problem This Solves:**
- ❌ Manual deployment order = errors (service B starts before service A is ready)
- ❌ No atomic operations = partial failures leave system in broken state
- ❌ No coordination = waste time waiting/retrying manually
- ❌ No validation = discover missing prerequisites mid-deployment
- ❌ No rollback = have to manually clean up failed deployments

---

## Current State Analysis

### What Works Well (Session 3 Achievements)

✅ **Single-Service Deployment:**
- 9 deployment patterns (media, web-app, database, cache, etc.)
- Automated quadlet generation
- Pre-deployment validation (networks, ports, resources)
- Drift detection and reconciliation
- Health check verification

✅ **Pattern Quality:**
- Comprehensive deployment notes
- Common issues documented
- Post-deployment checklists
- Security guidance

### What's Missing (Multi-Service Gaps)

❌ **Stack Definitions:**
- No way to define "Immich stack = these 5 services"
- No declaration of dependencies (service B needs service A)
- No stack-level configuration (shared networks, resources)

❌ **Orchestration:**
- No automatic deployment ordering
- No health check coordination (wait for A before starting B)
- No parallel deployment (services without dependencies could deploy together)

❌ **Atomicity:**
- Partial failures leave system in inconsistent state
- No automatic rollback of related services
- No transaction semantics ("all or nothing")

❌ **Validation:**
- Pre-flight checks are per-service, not per-stack
- Don't verify inter-service compatibility
- No capacity planning (will all services fit in available resources?)

---

## Architecture Overview

### Multi-Service Orchestration System

```
┌─────────────────────────────────────────────────────────────┐
│                    Stack Definition (YAML)                  │
│  - Services list (5 services in Immich stack)              │
│  - Dependencies (immich → postgres, redis)                  │
│  - Shared config (networks, resources, secrets)            │
│  - Deployment order (explicit or computed)                  │
└─────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│              Dependency Resolution Engine                   │
│  - Parse stack definition                                   │
│  - Build dependency graph                                   │
│  - Compute deployment order (topological sort)              │
│  - Detect circular dependencies                             │
│  - Identify parallel deployment opportunities               │
└─────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                 Pre-Flight Validation                       │
│  - Check all prerequisites for ENTIRE stack                 │
│  - Verify capacity (total memory < available)               │
│  - Validate inter-service compatibility                     │
│  - Ensure no port conflicts                                 │
│  - Confirm all networks exist                               │
└─────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│              Orchestration Workflow Engine                  │
│                                                             │
│  Phase 1: Deploy Foundation (postgres, redis)              │
│    ├─ Deploy postgres                                       │
│    ├─ Wait for health check (READY)                         │
│    ├─ Deploy redis (parallel - no dependency)              │
│    └─ Wait for health check (READY)                         │
│                                                             │
│  Phase 2: Deploy Application (immich-server)               │
│    ├─ Deploy immich-server                                  │
│    ├─ Wait for health check (READY)                         │
│    └─ Verify database connection                            │
│                                                             │
│  Phase 3: Deploy Workers (immich-ml, immich-web)           │
│    ├─ Deploy immich-ml                                      │
│    ├─ Deploy immich-web (parallel)                         │
│    └─ Wait for both health checks (READY)                   │
│                                                             │
│  ✅ Stack deployment complete                               │
└─────────────────────────────────────────────────────────────┘
                             │
                  ┌──────────┴──────────┐
                  │                     │
                  ▼                     ▼
         ┌────────────────┐    ┌───────────────┐
         │   Success      │    │   Failure     │
         │   - Verify     │    │   - Rollback  │
         │   - Log        │    │   - Report    │
         └────────────────┘    └───────────────┘
```

---

## Component 1: Stack Definition Format

### Stack YAML Schema

**File Location:** `.claude/skills/homelab-deployment/stacks/*.yml`

**Example: Immich Stack**

```yaml
# .claude/skills/homelab-deployment/stacks/immich.yml
---
stack:
  name: immich
  description: "Photo management platform with AI-powered features"
  version: "1.0"
  author: "homelab-deployment"

metadata:
  criticality: tier-2  # tier-1 (critical), tier-2 (important), tier-3 (standard)
  category: media
  documentation: "docs/10-services/guides/immich.md"
  adr_references:
    - ADR-001  # Rootless containers
    - ADR-002  # Systemd quadlets

# Shared configuration for all services in stack
shared:
  networks:
    - systemd-reverse_proxy
    - systemd-photos

  environment:
    TZ: "Europe/Oslo"
    UPLOAD_LOCATION: "/mnt/btrfs-pool/subvol4-immich-data/upload"

  secrets:
    - immich_db_password  # Podman secret shared by multiple services

  resources:
    total_memory_mb: 8192  # Total memory budget for stack
    total_cpu_shares: 2048

# Service definitions
services:
  # Service 1: PostgreSQL Database
  - name: immich-postgres
    pattern: database-service
    dependencies: []  # Foundation service, no dependencies

    configuration:
      image: docker.io/tensorchord/pgvecto-rs:pg14-v0.2.0
      memory: 2048M
      memory_high: 1792M
      ports: []  # No external ports (internal only)
      volumes:
        - source: /mnt/btrfs-pool/subvol4-immich-data/postgres
          target: /var/lib/postgresql/data
          options: "Z,nocow"  # BTRFS NOCOW for database
      environment:
        POSTGRES_USER: immich
        POSTGRES_DB: immich
        POSTGRES_PASSWORD: "${immich_db_password}"  # From Podman secret

      health_check:
        command: "pg_isready -U immich"
        interval: 10s
        timeout: 5s
        retries: 5
        start_period: 30s

      ready_criteria:
        - type: health_check
          timeout: 60s
        - type: log_pattern
          pattern: "database system is ready to accept connections"
          timeout: 60s

  # Service 2: Redis Cache
  - name: immich-redis
    pattern: cache-service
    dependencies: []  # Foundation service, can deploy in parallel with postgres

    configuration:
      image: docker.io/library/redis:7-alpine
      memory: 512M
      memory_high: 448M
      ports: []
      volumes:
        - source: /mnt/btrfs-pool/subvol4-immich-data/redis
          target: /data
          options: "Z"
      command: ["redis-server", "--save", "60", "1", "--loglevel", "warning"]

      health_check:
        command: "redis-cli ping"
        interval: 10s
        timeout: 3s
        retries: 3

      ready_criteria:
        - type: health_check
          timeout: 30s

  # Service 3: Immich Server (depends on postgres + redis)
  - name: immich-server
    pattern: web-app-with-database
    dependencies:
      - immich-postgres  # Must be READY
      - immich-redis     # Must be READY

    configuration:
      image: ghcr.io/immich-app/immich-server:release
      memory: 4096M
      memory_high: 3584M
      ports:
        - "2283:3001"  # Internal API port
      volumes:
        - source: /mnt/btrfs-pool/subvol4-immich-data/upload
          target: /usr/src/app/upload
          options: "Z"
        - source: /etc/localtime
          target: /etc/localtime
          options: "ro"
      environment:
        DB_HOSTNAME: immich-postgres
        DB_USERNAME: immich
        DB_PASSWORD: "${immich_db_password}"
        DB_DATABASE_NAME: immich
        REDIS_HOSTNAME: immich-redis
        LOG_LEVEL: log

      traefik_labels:
        enabled: true
        router_rule: "Host(`immich.patriark.org`)"
        router_entrypoints: "websecure"
        middlewares:
          - crowdsec-bouncer@file
          - rate-limit@file
        tls: true
        tls_certresolver: "letsencrypt"

      health_check:
        command: "curl -f http://localhost:3001/api/server-info/ping || exit 1"
        interval: 30s
        timeout: 10s
        retries: 3
        start_period: 60s

      ready_criteria:
        - type: health_check
          timeout: 120s
        - type: http_endpoint
          url: "http://localhost:3001/api/server-info/ping"
          expected_status: 200
          timeout: 120s

  # Service 4: Immich ML (depends on server)
  - name: immich-ml
    pattern: reverse-proxy-backend
    dependencies:
      - immich-server  # Needs API access

    configuration:
      image: ghcr.io/immich-app/immich-machine-learning:release
      memory: 2048M
      memory_high: 1792M
      ports: []
      volumes:
        - source: /mnt/btrfs-pool/subvol4-immich-data/model-cache
          target: /cache
          options: "Z"
      environment:
        IMMICH_HOST: "immich-server"
        IMMICH_PORT: "3001"

      # GPU access (if available)
      devices:
        - /dev/dri:/dev/dri  # Intel GPU
      security:
        privileged: false
        capabilities:
          - CAP_SYS_ADMIN  # For GPU access

      health_check:
        command: "curl -f http://localhost:3003/ping || exit 1"
        interval: 30s
        timeout: 10s
        retries: 3

      ready_criteria:
        - type: health_check
          timeout: 90s

  # Service 5: Immich Web (frontend, can deploy parallel with ML)
  - name: immich-web
    pattern: reverse-proxy-backend
    dependencies:
      - immich-server  # Needs API access

    configuration:
      image: ghcr.io/immich-app/immich-web:release
      memory: 512M
      memory_high: 448M
      ports: []
      environment:
        IMMICH_API_URL_EXTERNAL: "https://immich.patriark.org/api"
        IMMICH_SERVER_URL: "http://immich-server:3001"

      health_check:
        command: "curl -f http://localhost:3000 || exit 1"
        interval: 30s
        timeout: 5s
        retries: 3

      ready_criteria:
        - type: health_check
          timeout: 60s

# Deployment strategy
deployment:
  strategy: dependency-ordered  # or: sequential, parallel

  # Computed deployment phases (auto-generated from dependencies)
  phases:
    - phase: 1
      name: "Foundation Services"
      services:
        - immich-postgres
        - immich-redis
      parallel: true  # No inter-dependencies

    - phase: 2
      name: "Application Server"
      services:
        - immich-server
      parallel: false

    - phase: 3
      name: "Worker Services"
      services:
        - immich-ml
        - immich-web
      parallel: true  # Both depend on server, can deploy together

  timeouts:
    per_service_deployment: 300s  # 5 minutes per service
    total_stack_deployment: 900s  # 15 minutes total
    health_check_poll_interval: 5s

  failure_handling:
    strategy: rollback  # or: leave-partial, pause-for-debug
    rollback_order: reverse  # Shutdown in reverse deployment order
    preserve_logs: true
    cleanup_volumes: false  # Keep data on rollback

# Post-deployment validation
validation:
  tests:
    - name: "Database connectivity"
      type: sql_query
      target: immich-postgres
      query: "SELECT 1"
      expected: "1"

    - name: "Redis connectivity"
      type: redis_ping
      target: immich-redis
      expected: "PONG"

    - name: "API reachability"
      type: http_get
      url: "http://immich-server:3001/api/server-info/ping"
      expected_status: 200

    - name: "Web UI reachable"
      type: http_get
      url: "http://immich-web:3000"
      expected_status: 200

    - name: "ML service responsive"
      type: http_get
      url: "http://immich-ml:3003/ping"
      expected_status: 200

# Rollback procedure
rollback:
  steps:
    - name: "Stop services in reverse order"
      services:
        - immich-web
        - immich-ml
        - immich-server
        - immich-redis
        - immich-postgres

    - name: "Remove quadlets"
      action: delete_quadlets

    - name: "Reload systemd"
      action: daemon_reload

    - name: "Verify cleanup"
      action: check_no_containers_running

  preserve:
    - volumes  # Don't delete data
    - networks  # Don't delete networks (might be shared)
    - secrets  # Don't delete secrets

# Documentation
documentation:
  post_deployment:
    - "Access Immich at: https://immich.patriark.org"
    - "Initial setup: Create admin user via web UI"
    - "Configure upload location in settings"
    - "Enable ML features in admin panel"

  troubleshooting:
    - issue: "ML service won't start"
      solution: "Check GPU access: podman exec immich-ml ls /dev/dri"
    - issue: "Database connection failed"
      solution: "Verify postgres is ready: podman exec immich-postgres pg_isready"
```

---

### Additional Stack Examples

**Monitoring Stack (Simple):**
```yaml
# stacks/monitoring-simple.yml
stack:
  name: monitoring-simple
  description: "Basic monitoring stack (Prometheus + Grafana only)"

services:
  - name: prometheus
    pattern: monitoring-exporter
    dependencies: []
    configuration:
      # ... prometheus config

  - name: grafana
    pattern: web-app-with-database
    dependencies:
      - prometheus  # Needs datasource
    configuration:
      # ... grafana config
```

**Web App Stack:**
```yaml
# stacks/wiki-stack.yml
stack:
  name: wiki
  description: "Wiki.js with PostgreSQL backend"

services:
  - name: wiki-db
    pattern: database-service
    dependencies: []

  - name: wiki-app
    pattern: web-app-with-database
    dependencies:
      - wiki-db
```

---

## Component 2: Dependency Resolution Engine

### File: `scripts/resolve-dependencies.sh`

**Purpose:** Compute deployment order from stack definition

**Algorithm: Topological Sort (Kahn's Algorithm)**

```bash
#!/bin/bash
# .claude/skills/homelab-deployment/scripts/resolve-dependencies.sh

set -euo pipefail

STACK_FILE=""
OUTPUT_FORMAT="text"  # text | json | phases

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

usage() {
    cat <<EOF
Usage: $0 --stack <stack-file> [options]

Resolve service dependencies and compute deployment order.

Options:
  --stack <file>       Stack definition YAML file (required)
  --output <format>    Output format: text, json, phases (default: text)
  --visualize          Generate dependency graph (Graphviz DOT format)
  --validate-only      Only validate, don't compute order
  --help               Show this help

Examples:
  $0 --stack stacks/immich.yml
  $0 --stack stacks/immich.yml --output json
  $0 --stack stacks/immich.yml --visualize > immich-deps.dot
EOF
}

# Parse YAML (requires yq)
parse_stack() {
    local stack_file=$1

    if ! command -v yq &>/dev/null; then
        echo "Error: yq is required for parsing YAML" >&2
        echo "Install: sudo dnf install yq" >&2
        exit 1
    fi

    if [[ ! -f "$stack_file" ]]; then
        echo "Error: Stack file not found: $stack_file" >&2
        exit 1
    fi

    # Extract service names
    yq eval '.services[].name' "$stack_file"
}

# Build dependency graph
build_dependency_graph() {
    local stack_file=$1

    # Create adjacency list (service -> dependencies)
    declare -A deps
    declare -A indegree

    local services=$(yq eval '.services[].name' "$stack_file")

    for service in $services; do
        indegree[$service]=0
        deps[$service]=""
    done

    # Parse dependencies
    local i=0
    while true; do
        local service=$(yq eval ".services[$i].name" "$stack_file" 2>/dev/null)
        [[ "$service" == "null" ]] && break

        local service_deps=$(yq eval ".services[$i].dependencies[]" "$stack_file" 2>/dev/null)

        if [[ "$service_deps" != "null" && -n "$service_deps" ]]; then
            for dep in $service_deps; do
                deps[$service]="${deps[$service]} $dep"
                indegree[$service]=$((indegree[$service] + 1))
            done
        fi

        ((i++))
    done

    # Export for other functions
    declare -p deps
    declare -p indegree
}

# Topological sort (Kahn's algorithm)
topological_sort() {
    local stack_file=$1

    # Build graph
    eval "$(build_dependency_graph "$stack_file")"

    # Find all nodes with no incoming edges (indegree = 0)
    local queue=()
    for service in "${!indegree[@]}"; do
        if [[ ${indegree[$service]} -eq 0 ]]; then
            queue+=("$service")
        fi
    done

    # Process queue
    local sorted=()
    local phase=1
    local current_phase=()

    while [[ ${#queue[@]} -gt 0 ]]; do
        # All services in queue can be deployed in parallel (same phase)
        current_phase=("${queue[@]}")

        echo "# Phase $phase (parallel: ${#current_phase[@]} services)"
        for service in "${current_phase[@]}"; do
            echo "$service"
            sorted+=("$service")
        done
        echo ""

        # Clear queue
        queue=()

        # For each service in current phase, reduce indegree of dependents
        for service in "${current_phase[@]}"; do
            # Find all services that depend on this service
            for dependent in "${!deps[@]}"; do
                if [[ " ${deps[$dependent]} " =~ " $service " ]]; then
                    indegree[$dependent]=$((indegree[$dependent] - 1))

                    # If indegree becomes 0, add to queue
                    if [[ ${indegree[$dependent]} -eq 0 ]]; then
                        queue+=("$dependent")
                    fi
                fi
            done
        done

        ((phase++))
    done

    # Check for cycles (if sorted length != total services)
    local total_services=$(yq eval '.services | length' "$stack_file")
    if [[ ${#sorted[@]} -ne $total_services ]]; then
        echo "ERROR: Circular dependency detected!" >&2
        echo "Resolved: ${#sorted[@]} / $total_services services" >&2
        exit 1
    fi
}

# Detect circular dependencies
detect_cycles() {
    local stack_file=$1

    # Use DFS to detect cycles
    # (Simplified: if topological_sort fails, there's a cycle)

    if ! topological_sort "$stack_file" &>/dev/null; then
        echo "Circular dependency detected"

        # Try to identify the cycle
        # (Advanced: implement cycle detection algorithm)

        return 1
    fi

    echo "No circular dependencies found"
    return 0
}

# Generate Graphviz visualization
visualize_graph() {
    local stack_file=$1

    echo "digraph stack_dependencies {"
    echo "  rankdir=LR;"
    echo "  node [shape=box, style=rounded];"
    echo ""

    # Add nodes
    local services=$(yq eval '.services[].name' "$stack_file")
    for service in $services; do
        echo "  \"$service\";"
    done

    echo ""

    # Add edges (dependencies)
    local i=0
    while true; do
        local service=$(yq eval ".services[$i].name" "$stack_file" 2>/dev/null)
        [[ "$service" == "null" ]] && break

        local service_deps=$(yq eval ".services[$i].dependencies[]" "$stack_file" 2>/dev/null)

        if [[ "$service_deps" != "null" && -n "$service_deps" ]]; then
            for dep in $service_deps; do
                echo "  \"$dep\" -> \"$service\";"
            done
        fi

        ((i++))
    done

    echo "}"
}

# Main
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
                visualize_graph "$STACK_FILE"
                exit 0
                ;;
            --validate-only)
                detect_cycles "$STACK_FILE"
                exit $?
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

    # Resolve dependencies
    topological_sort "$STACK_FILE"
}

main "$@"
```

**Example Output:**
```bash
$ ./scripts/resolve-dependencies.sh --stack stacks/immich.yml

# Phase 1 (parallel: 2 services)
immich-postgres
immich-redis

# Phase 2 (parallel: 1 service)
immich-server

# Phase 3 (parallel: 2 services)
immich-ml
immich-web
```

---

## Component 3: Stack Deployment Orchestrator

### File: `scripts/deploy-stack.sh`

**Purpose:** Main orchestration engine - deploys entire stack

```bash
#!/bin/bash
# .claude/skills/homelab-deployment/scripts/deploy-stack.sh

set -euo pipefail

STACK_FILE=""
DRY_RUN=false
SKIP_HEALTH_CHECK=false
ROLLBACK_ON_FAILURE=true
VERBOSE=false

# State tracking
declare -A SERVICE_STATUS  # service -> "pending" | "deploying" | "healthy" | "failed"
declare -A SERVICE_START_TIME
declare -A SERVICE_PIDS  # For parallel deployment
DEPLOYMENT_LOG=""

usage() {
    cat <<EOF
Usage: $0 --stack <stack-name> [options]

Deploy a multi-service stack with dependency orchestration.

Options:
  --stack <name>           Stack name (looks for stacks/<name>.yml)
  --stack-file <path>      Path to stack YAML file
  --dry-run                Show what would be deployed without executing
  --skip-health-check      Don't wait for health checks (faster, risky)
  --no-rollback            Don't rollback on failure (leave partial deployment)
  --verbose                Verbose output
  --help                   Show this help

Examples:
  $0 --stack immich
  $0 --stack-file /path/to/custom-stack.yml --dry-run
  $0 --stack monitoring-simple --verbose
EOF
}

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[$timestamp] [$level] $message" | tee -a "$DEPLOYMENT_LOG"

    case $level in
        ERROR)   echo -e "${RED}[ERROR]${NC} $message" >&2 ;;
        SUCCESS) echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
        WARNING) echo -e "${YELLOW}[WARNING]${NC} $message" ;;
        INFO)    echo -e "${BLUE}[INFO]${NC} $message" ;;
    esac
}

# Phase 1: Pre-flight validation
preflight_validation() {
    local stack_file=$1

    log INFO "Running pre-flight validation..."

    # 1. Validate stack file syntax
    if ! yq eval '.' "$stack_file" &>/dev/null; then
        log ERROR "Invalid YAML syntax in stack file"
        return 1
    fi

    # 2. Check for circular dependencies
    if ! ./scripts/resolve-dependencies.sh --stack "$stack_file" --validate-only; then
        log ERROR "Circular dependency detected in stack"
        return 1
    fi

    # 3. Verify all patterns exist
    local i=0
    while true; do
        local service=$(yq eval ".services[$i].name" "$stack_file" 2>/dev/null)
        [[ "$service" == "null" ]] && break

        local pattern=$(yq eval ".services[$i].pattern" "$stack_file")
        if [[ ! -f ".claude/skills/homelab-deployment/patterns/$pattern.yml" ]]; then
            log ERROR "Pattern not found: $pattern (required by $service)"
            return 1
        fi

        ((i++))
    done

    # 4. Check resource capacity
    local total_memory=$(yq eval '.shared.resources.total_memory_mb' "$stack_file")
    local available_memory=$(free -m | awk '/^Mem:/{print $7}')

    if [[ $total_memory -gt $available_memory ]]; then
        log WARNING "Requested memory ($total_memory MB) > available ($available_memory MB)"
        read -p "Continue anyway? (y/n) " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && return 1
    fi

    # 5. Verify all networks exist
    local networks=$(yq eval '.shared.networks[]' "$stack_file")
    for network in $networks; do
        if ! podman network exists "$network" 2>/dev/null; then
            log ERROR "Network not found: $network"
            return 1
        fi
    done

    # 6. Check for port conflicts
    # ... (check if any services use ports already in use)

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

    # Find service in stack definition
    local service_index=-1
    local i=0
    while true; do
        local name=$(yq eval ".services[$i].name" "$stack_file" 2>/dev/null)
        [[ "$name" == "null" ]] && break

        if [[ "$name" == "$service_name" ]]; then
            service_index=$i
            break
        fi

        ((i++))
    done

    if [[ $service_index -eq -1 ]]; then
        log ERROR "Service not found in stack: $service_name"
        SERVICE_STATUS[$service_name]="failed"
        return 1
    fi

    # Extract service configuration
    local pattern=$(yq eval ".services[$service_index].pattern" "$stack_file")
    local image=$(yq eval ".services[$service_index].configuration.image" "$stack_file")
    local memory=$(yq eval ".services[$service_index].configuration.memory" "$stack_file")

    # Call existing deploy-service.sh with configuration
    # (This integrates with Session 3 deployment skill)

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would deploy: $service_name (pattern: $pattern, image: $image)"
        SERVICE_STATUS[$service_name]="healthy"
        return 0
    fi

    # Actual deployment
    if ! ./.claude/skills/homelab-deployment/scripts/deploy-service.sh \
        --service-name "$service_name" \
        --pattern "$pattern" \
        --image "$image" \
        --memory "$memory" \
        --skip-health-check; then

        log ERROR "Deployment failed: $service_name"
        SERVICE_STATUS[$service_name]="failed"
        return 1
    fi

    log SUCCESS "Service deployed: $service_name"
    SERVICE_STATUS[$service_name]="deployed"
    return 0
}

# Wait for service to be healthy
wait_for_healthy() {
    local stack_file=$1
    local service_name=$2
    local timeout=${3:-300}  # Default 5 minutes

    if [[ "$SKIP_HEALTH_CHECK" == "true" ]]; then
        log WARNING "Skipping health check for $service_name (--skip-health-check)"
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
            # Check container health check
            if podman healthcheck run "$service_name" &>/dev/null; then
                log SUCCESS "$service_name is healthy (took ${elapsed}s)"
                SERVICE_STATUS[$service_name]="healthy"
                return 0
            fi
        fi

        log INFO "$service_name not ready yet (${elapsed}s elapsed)..."
        sleep $poll_interval
    done
}

# Deploy services in a phase (can be parallel)
deploy_phase() {
    local stack_file=$1
    local phase_number=$2
    local services=("${@:3}")  # Remaining args are service names

    log INFO "Deploying Phase $phase_number (${#services[@]} services)"

    # Check if services can be deployed in parallel
    local parallel=$(yq eval ".deployment.phases[$((phase_number - 1))].parallel" "$stack_file")

    if [[ "$parallel" == "true" && ${#services[@]} -gt 1 ]]; then
        log INFO "Deploying services in parallel"

        # Deploy all services in background
        for service in "${services[@]}"; do
            deploy_service "$stack_file" "$service" &
            SERVICE_PIDS[$service]=$!
        done

        # Wait for all deployments to complete
        local all_success=true
        for service in "${services[@]}"; do
            if ! wait ${SERVICE_PIDS[$service]}; then
                log ERROR "Parallel deployment failed: $service"
                all_success=false
            fi
        done

        if [[ "$all_success" == "false" ]]; then
            return 1
        fi

        # Wait for all to be healthy
        for service in "${services[@]}"; do
            if ! wait_for_healthy "$stack_file" "$service"; then
                return 1
            fi
        done
    else
        # Sequential deployment
        for service in "${services[@]}"; do
            if ! deploy_service "$stack_file" "$service"; then
                return 1
            fi

            if ! wait_for_healthy "$stack_file" "$service"; then
                return 1
            fi
        done
    fi

    log SUCCESS "Phase $phase_number complete"
    return 0
}

# Rollback stack
rollback_stack() {
    local stack_file=$1

    log WARNING "Rolling back stack deployment..."

    # Get all deployed services (in reverse order)
    local deployed_services=()
    for service in "${!SERVICE_STATUS[@]}"; do
        if [[ "${SERVICE_STATUS[$service]}" == "deployed" || "${SERVICE_STATUS[$service]}" == "healthy" ]]; then
            deployed_services+=("$service")
        fi
    done

    # Reverse array
    local reversed=()
    for ((i=${#deployed_services[@]}-1; i>=0; i--)); do
        reversed+=("${deployed_services[$i]}")
    done

    # Stop services
    for service in "${reversed[@]}"; do
        log INFO "Stopping: $service"
        systemctl --user stop "${service}.service" || true

        # Optionally remove quadlet
        rm -f "$HOME/.config/containers/systemd/${service}.container"
    done

    # Reload systemd
    systemctl --user daemon-reload

    log WARNING "Rollback complete. Services stopped and removed."
}

# Main orchestration
orchestrate_deployment() {
    local stack_file=$1

    # Step 1: Resolve dependencies and get deployment phases
    log INFO "Resolving dependencies..."
    local phases_output=$(./scripts/resolve-dependencies.sh --stack "$stack_file")

    # Parse phases (simplified - in production, use structured output)
    local current_phase=0
    local phase_services=()

    while IFS= read -r line; do
        if [[ $line =~ ^#\ Phase\ ([0-9]+) ]]; then
            # Start of new phase
            if [[ ${#phase_services[@]} -gt 0 ]]; then
                # Deploy previous phase
                deploy_phase "$stack_file" $current_phase "${phase_services[@]}" || return 1
                phase_services=()
            fi

            current_phase=${BASH_REMATCH[1]}
        elif [[ -n "$line" && ! $line =~ ^# ]]; then
            # Service name
            phase_services+=("$line")
        fi
    done <<< "$phases_output"

    # Deploy final phase
    if [[ ${#phase_services[@]} -gt 0 ]]; then
        deploy_phase "$stack_file" $current_phase "${phase_services[@]}" || return 1
    fi

    log SUCCESS "All phases deployed successfully"
}

# Post-deployment validation
post_deployment_validation() {
    local stack_file=$1

    log INFO "Running post-deployment validation tests..."

    # Run validation tests defined in stack YAML
    local test_count=$(yq eval '.validation.tests | length' "$stack_file")

    if [[ "$test_count" == "null" || $test_count -eq 0 ]]; then
        log INFO "No validation tests defined"
        return 0
    fi

    local i=0
    local failed_tests=0

    while [[ $i -lt $test_count ]]; do
        local test_name=$(yq eval ".validation.tests[$i].name" "$stack_file")
        local test_type=$(yq eval ".validation.tests[$i].type" "$stack_file")

        log INFO "Running test: $test_name"

        case $test_type in
            http_get)
                local url=$(yq eval ".validation.tests[$i].url" "$stack_file")
                local expected_status=$(yq eval ".validation.tests[$i].expected_status" "$stack_file")

                local actual_status=$(curl -s -o /dev/null -w "%{http_code}" "$url")

                if [[ "$actual_status" == "$expected_status" ]]; then
                    log SUCCESS "Test passed: $test_name"
                else
                    log ERROR "Test failed: $test_name (expected $expected_status, got $actual_status)"
                    ((failed_tests++))
                fi
                ;;

            sql_query)
                local target=$(yq eval ".validation.tests[$i].target" "$stack_file")
                local query=$(yq eval ".validation.tests[$i].query" "$stack_file")

                if podman exec "$target" psql -U postgres -c "$query" &>/dev/null; then
                    log SUCCESS "Test passed: $test_name"
                else
                    log ERROR "Test failed: $test_name"
                    ((failed_tests++))
                fi
                ;;

            redis_ping)
                local target=$(yq eval ".validation.tests[$i].target" "$stack_file")

                if [[ "$(podman exec "$target" redis-cli ping)" == "PONG" ]]; then
                    log SUCCESS "Test passed: $test_name"
                else
                    log ERROR "Test failed: $test_name"
                    ((failed_tests++))
                fi
                ;;
        esac

        ((i++))
    done

    if [[ $failed_tests -gt 0 ]]; then
        log ERROR "$failed_tests validation test(s) failed"
        return 1
    fi

    log SUCCESS "All validation tests passed"
    return 0
}

# Main
main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --stack)
                STACK_FILE=".claude/skills/homelab-deployment/stacks/$2.yml"
                shift 2
                ;;
            --stack-file)
                STACK_FILE="$2"
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
    DEPLOYMENT_LOG="$HOME/containers/data/deployment-logs/stack-$(basename "$STACK_FILE" .yml)-$(date +%Y%m%d-%H%M%S).log"
    mkdir -p "$(dirname "$DEPLOYMENT_LOG")"

    log INFO "=========================================="
    log INFO "Stack Deployment: $(basename "$STACK_FILE" .yml)"
    log INFO "=========================================="

    # Phase 1: Pre-flight validation
    if ! preflight_validation "$STACK_FILE"; then
        log ERROR "Pre-flight validation failed. Aborting deployment."
        exit 1
    fi

    # Phase 2: Orchestrate deployment
    if ! orchestrate_deployment "$STACK_FILE"; then
        log ERROR "Deployment failed"

        if [[ "$ROLLBACK_ON_FAILURE" == "true" ]]; then
            rollback_stack "$STACK_FILE"
        else
            log WARNING "Rollback disabled. Partial deployment remains."
        fi

        exit 1
    fi

    # Phase 3: Post-deployment validation
    if ! post_deployment_validation "$STACK_FILE"; then
        log WARNING "Post-deployment validation failed"

        if [[ "$ROLLBACK_ON_FAILURE" == "true" ]]; then
            read -p "Rollback deployment? (y/n) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rollback_stack "$STACK_FILE"
                exit 1
            fi
        fi
    fi

    # Success summary
    log SUCCESS "=========================================="
    log SUCCESS "Stack deployment complete!"
    log SUCCESS "=========================================="
    log INFO "Deployment log: $DEPLOYMENT_LOG"

    # Show post-deployment docs
    local doc_count=$(yq eval '.documentation.post_deployment | length' "$STACK_FILE")
    if [[ "$doc_count" != "null" && $doc_count -gt 0 ]]; then
        echo ""
        log INFO "Post-Deployment Instructions:"
        yq eval '.documentation.post_deployment[]' "$STACK_FILE" | while read -r line; do
            echo "  - $line"
        done
    fi
}

main "$@"
```

---

## Implementation Roadmap

### Phase 1: Foundation (2-3 hours)

**Session 1A: Dependency Resolution (1.5 hours)**
```bash
# 1. Create dependency resolver
cd .claude/skills/homelab-deployment
mkdir -p scripts stacks

# 2. Implement resolve-dependencies.sh
# - Topological sort algorithm
# - Circular dependency detection
# - Graphviz visualization

# 3. Test with simple stack
cat > stacks/test-simple.yml <<EOF
stack:
  name: test-simple
services:
  - name: redis
    pattern: cache-service
    dependencies: []
  - name: app
    pattern: web-app-with-database
    dependencies: [redis]
EOF

./scripts/resolve-dependencies.sh --stack stacks/test-simple.yml
# Expected: Phase 1: redis, Phase 2: app

# 4. Test cycle detection
cat > stacks/test-cycle.yml <<EOF
services:
  - name: a
    dependencies: [b]
  - name: b
    dependencies: [a]
EOF

./scripts/resolve-dependencies.sh --stack stacks/test-cycle.yml --validate-only
# Expected: ERROR - Circular dependency
```

**Session 1B: Stack Definition (1-1.5 hours)**
```bash
# 1. Create Immich stack definition
# - Copy example from Component 1 above
# - Adjust paths, images, config for your setup

# 2. Create monitoring stack
# - Simpler example (Prometheus + Grafana)

# 3. Validate YAML syntax
yq eval '.' stacks/immich.yml
yq eval '.' stacks/monitoring-simple.yml

# 4. Visualize dependencies
./scripts/resolve-dependencies.sh --stack stacks/immich.yml --visualize > immich-deps.dot
dot -Tpng immich-deps.dot -o immich-deps.png
# View: xdg-open immich-deps.png
```

---

### Phase 2: Orchestration Engine (2-3 hours)

**Session 2A: Core Orchestrator (2 hours)**
```bash
# 1. Implement deploy-stack.sh
# - Pre-flight validation
# - Phase-based deployment
# - Health check waiting
# - Basic rollback

# 2. Integrate with existing deploy-service.sh
# - Reuse pattern deployment logic
# - Pass configuration from stack YAML

# 3. Test with simple stack (monitoring)
./scripts/deploy-stack.sh --stack monitoring-simple --dry-run
# Should show: Phase 1: prometheus, Phase 2: grafana

# 4. Test actual deployment (if ready)
./scripts/deploy-stack.sh --stack monitoring-simple --verbose
```

**Session 2B: Rollback & Validation (1 hour)**
```bash
# 1. Implement rollback logic
# - Stop services in reverse order
# - Remove quadlets
# - Preserve data (configurable)

# 2. Implement post-deployment validation
# - HTTP endpoint checks
# - Database connectivity
# - Service-to-service communication

# 3. Test rollback
# - Deploy stack with intentional failure
# - Verify rollback cleans up correctly
```

---

### Phase 3: Testing & Documentation (1-2 hours)

**Session 3: End-to-End Testing (1-2 hours)**
```bash
# 1. Test Immich stack deployment
./scripts/deploy-stack.sh --stack immich --dry-run
# Review deployment plan

./scripts/deploy-stack.sh --stack immich
# Execute actual deployment (~8-10 minutes)

# 2. Verify stack health
podman ps | grep immich
systemctl --user status immich-*.service

# Access Immich web UI
curl https://immich.patriark.org

# 3. Test post-deployment validation
# - Database connectivity
# - Redis connectivity
# - API reachability
# - ML service responsive

# 4. Test rollback
./scripts/deploy-stack.sh --stack test-rollback
# (Intentional failure - verify rollback works)

# 5. Document procedures
# - Update skill-integration-guide.md
# - Create stack deployment guide
# - Add troubleshooting section
```

---

## Deliverables Checklist

### Scripts
- [ ] `.claude/skills/homelab-deployment/scripts/resolve-dependencies.sh` (dependency resolver)
- [ ] `.claude/skills/homelab-deployment/scripts/deploy-stack.sh` (orchestrator)
- [ ] `.claude/skills/homelab-deployment/scripts/rollback-stack.sh` (rollback utility)
- [ ] `.claude/skills/homelab-deployment/scripts/validate-stack.sh` (validation helper)

### Stack Definitions
- [ ] `.claude/skills/homelab-deployment/stacks/immich.yml` (complete Immich stack)
- [ ] `.claude/skills/homelab-deployment/stacks/monitoring-simple.yml` (Prometheus + Grafana)
- [ ] `.claude/skills/homelab-deployment/stacks/monitoring-full.yml` (Full monitoring stack)
- [ ] `.claude/skills/homelab-deployment/stacks/web-app-template.yml` (Generic web app template)

### Documentation
- [ ] `.claude/skills/homelab-deployment/STACK-GUIDE.md` (Stack deployment guide)
- [ ] `.claude/skills/homelab-deployment/STACK-DEFINITION-SPEC.md` (YAML schema docs)
- [ ] Update: `docs/10-services/guides/skill-integration-guide.md`
- [ ] Example: `docs/10-services/journal/YYYY-MM-DD-immich-stack-deployment.md`

### Testing
- [ ] Test: Simple 2-service stack (redis + app)
- [ ] Test: Monitoring stack (Prometheus + Grafana)
- [ ] Test: Immich stack (5 services)
- [ ] Test: Circular dependency detection
- [ ] Test: Rollback on failure
- [ ] Test: Parallel deployment (services without dependencies)

---

## Success Criteria

### Functional Requirements

**Must Have:**
- [ ] Deploy multi-service stack with single command
- [ ] Automatically resolve dependencies and compute order
- [ ] Wait for each service to be healthy before proceeding
- [ ] Detect circular dependencies
- [ ] Rollback entire stack on failure
- [ ] Validate stack health after deployment

**Should Have:**
- [ ] Parallel deployment of independent services
- [ ] Pre-flight validation (capacity, prerequisites)
- [ ] Post-deployment validation tests
- [ ] Dry-run mode (show plan without executing)
- [ ] Detailed deployment logs
- [ ] Visualize dependency graph

**Could Have:**
- [ ] Incremental updates (update single service in deployed stack)
- [ ] Stack status command (show health of all services)
- [ ] Stack logs command (aggregate logs from all services)
- [ ] Blue-green deployment (deploy new version alongside old)

---

### Quality Requirements

**Safety:**
- [ ] No partial deployments left on failure (rollback works)
- [ ] Data preserved during rollback (volumes not deleted)
- [ ] Secrets not leaked in logs
- [ ] Dry-run accurately represents what would happen

**Performance:**
- [ ] Parallel deployment reduces total time (5 services in 3 phases < 5 sequential)
- [ ] Health checks timeout appropriately (not too long, not too short)
- [ ] Large stacks (10+ services) complete in reasonable time (<30 min)

**Usability:**
- [ ] Clear progress output during deployment
- [ ] Helpful error messages when failures occur
- [ ] Easy to create new stack definitions (template available)
- [ ] Integration with existing homelab-deployment skill seamless

---

## Usage Examples

### Example 1: Deploy Immich Stack

```bash
# Review what will be deployed
./deploy-stack.sh --stack immich --dry-run

# Deploy with verbose output
./deploy-stack.sh --stack immich --verbose

# Expected output:
# [2025-11-20 14:00:00] [INFO] Running pre-flight validation...
# [2025-11-20 14:00:05] [SUCCESS] Pre-flight validation passed
# [2025-11-20 14:00:05] [INFO] Deploying Phase 1 (2 services)
# [2025-11-20 14:00:06] [INFO] Deploying service: immich-postgres
# [2025-11-20 14:00:20] [SUCCESS] Service deployed: immich-postgres
# [2025-11-20 14:00:20] [INFO] Waiting for immich-postgres to be healthy
# [2025-11-20 14:00:35] [SUCCESS] immich-postgres is healthy (took 15s)
# [2025-11-20 14:00:35] [INFO] Deploying service: immich-redis
# [2025-11-20 14:00:45] [SUCCESS] Service deployed: immich-redis
# [2025-11-20 14:00:50] [SUCCESS] immich-redis is healthy (took 5s)
# [2025-11-20 14:00:50] [SUCCESS] Phase 1 complete
# ... (continues for Phase 2 and 3)
# [2025-11-20 14:08:30] [SUCCESS] Stack deployment complete!
```

---

### Example 2: Deploy Monitoring Stack

```bash
# Simple Prometheus + Grafana
./deploy-stack.sh --stack monitoring-simple

# Full monitoring stack (Prometheus + Grafana + Loki + Alertmanager + exporters)
./deploy-stack.sh --stack monitoring-full
```

---

### Example 3: Rollback After Failure

```bash
# Deploy stack (will fail at Phase 2)
./deploy-stack.sh --stack test-stack

# Output shows failure and automatic rollback:
# [ERROR] Deployment failed: immich-server (database connection failed)
# [WARNING] Rolling back stack deployment...
# [INFO] Stopping: immich-redis
# [INFO] Stopping: immich-postgres
# [WARNING] Rollback complete. Services stopped and removed.
```

---

### Example 4: Create Custom Stack

```bash
# Create new stack definition
cat > stacks/my-wiki.yml <<EOF
stack:
  name: my-wiki
  description: "Wiki.js with PostgreSQL"

shared:
  networks:
    - systemd-reverse_proxy

services:
  - name: wiki-db
    pattern: database-service
    dependencies: []
    configuration:
      image: docker.io/library/postgres:15
      memory: 1024M
      environment:
        POSTGRES_USER: wiki
        POSTGRES_PASSWORD: "\${wiki_db_password}"
        POSTGRES_DB: wiki

  - name: wiki-app
    pattern: web-app-with-database
    dependencies: [wiki-db]
    configuration:
      image: ghcr.io/requarks/wiki:2
      memory: 2048M
      environment:
        DB_TYPE: postgres
        DB_HOST: wiki-db
        DB_PORT: 5432
        DB_USER: wiki
        DB_PASS: "\${wiki_db_password}"
        DB_NAME: wiki
EOF

# Deploy custom stack
./deploy-stack.sh --stack my-wiki
```

---

## Integration with Existing Skills

### Enhances homelab-deployment Skill

**Before Session 5:**
```
homelab-deployment skill:
- Single-service deployment ✅
- Pattern-based templates ✅
- Pre-deployment validation ✅
- Drift detection ✅
```

**After Session 5:**
```
homelab-deployment skill:
- Single-service deployment ✅
- Multi-service orchestration ✅ NEW
- Pattern-based templates ✅
- Pre-deployment validation (per-stack) ✅ ENHANCED
- Drift detection ✅
- Atomic rollback ✅ NEW
- Dependency resolution ✅ NEW
```

### Integration with homelab-intelligence

**Optional (if Session 4 complete):**
- Check system health before stack deployment
- Use deployment memory (learn from past stack deployments)
- Auto-remediation for failed deployments

**Without Session 4:**
- Standalone operation (no context needed)
- Basic health checks (systemd status, podman health)

---

## Future Enhancements (Beyond Session 5)

### Session 6 Ideas: Advanced Orchestration

1. **Incremental Stack Updates**
   - Update single service without redeploying entire stack
   - Blue-green deployments (zero downtime updates)
   - Canary deployments (gradual rollout)

2. **Stack Composition**
   - Import stacks into other stacks
   - Share common services (one postgres for multiple apps)
   - Stack dependencies (app-stack depends on monitoring-stack)

3. **Advanced Health Checks**
   - Custom readiness probes (beyond systemd health checks)
   - Dependency health (service A healthy only if service B responsive)
   - Business logic validation (not just "container running")

4. **Resource Scaling**
   - Automatic resource adjustment based on load
   - Memory/CPU limits based on actual usage patterns
   - Cost optimization (reduce resources for idle services)

5. **Disaster Recovery Integration**
   - Stack backup/restore procedures
   - Export stack state for migration
   - Import stack from backup

---

## Estimated Timeline

### Session 5A: Foundation (2-3 hours)
- Hour 1: Implement dependency resolver
- Hour 2: Create stack definitions (Immich + monitoring)
- Hour 3: Test dependency resolution, visualization

### Session 5B: Orchestration (2-3 hours)
- Hour 1-2: Implement deploy-stack.sh core logic
- Hour 3: Implement rollback mechanism

### Session 5C: Testing & Polish (1-2 hours)
- Hour 1: End-to-end testing (Immich deployment)
- Hour 2: Documentation, edge cases, troubleshooting guide

**Total:** 6-8 hours across 2-3 CLI sessions

---

## Success Metrics

### Quantitative
- [ ] Stack deployment time: Manual 40-60min → Automated 5-10min (80%+ reduction)
- [ ] Error rate: Manual 30-40% → Automated <5% (90%+ reduction)
- [ ] Services deployed correctly on first attempt: >95%
- [ ] Rollback success rate: 100% (all-or-nothing guarantee)

### Qualitative
- [ ] One command deploys entire stack
- [ ] Clear visibility into deployment progress
- [ ] Automatic recovery from transient failures
- [ ] Confidence in deploying complex stacks

---

## Risk Assessment

| Risk | Impact | Likelihood | Mitigation |
|------|--------|-----------|------------|
| **Partial failure leaves broken state** | High | Medium | Atomic rollback (all-or-nothing) |
| **Health checks timeout too early** | Medium | Medium | Configurable timeouts, sensible defaults |
| **Circular dependencies crash resolver** | High | Low | Cycle detection before deployment |
| **Resource exhaustion mid-deployment** | High | Low | Pre-flight capacity validation |
| **Rollback fails, state unknown** | Critical | Very Low | Rollback is simple (just stop services) |

---

## Troubleshooting Guide

### Issue: Circular Dependency Error

**Symptom:**
```
ERROR: Circular dependency detected!
Resolved: 3 / 5 services
```

**Cause:** Service A depends on B, B depends on A (or longer cycle)

**Solution:**
```bash
# Visualize dependencies to find cycle
./scripts/resolve-dependencies.sh --stack stacks/mystack.yml --visualize > deps.dot
dot -Tpng deps.dot -o deps.png
xdg-open deps.png

# Fix stack definition (remove circular dependency)
```

---

### Issue: Service Won't Become Healthy

**Symptom:**
```
ERROR: Health check timeout for immich-server (300s)
```

**Cause:** Service started but health check failing

**Solution:**
```bash
# Check service logs
podman logs immich-server

# Check health check definition
podman inspect immich-server | jq '.[0].Config.Healthcheck'

# Manually test health check
podman exec immich-server curl -f http://localhost:3001/api/server-info/ping

# Increase timeout if service is slow to start
# Edit stack YAML: ready_criteria.timeout: 600s
```

---

### Issue: Rollback Leaves Containers Running

**Symptom:** After rollback, `podman ps` still shows containers

**Solution:**
```bash
# Manual cleanup
for service in immich-web immich-ml immich-server immich-redis immich-postgres; do
    systemctl --user stop $service.service || true
    podman stop $service || true
    podman rm $service || true
done

# Verify clean state
podman ps -a | grep immich
```

---

## Conclusion

Session 5 transforms your homelab deployment from **single-service manual** to **multi-service orchestrated**. By adding dependency resolution, health check coordination, and atomic rollback, you gain:

✅ **Efficiency** - Deploy 5-service stacks in minutes, not hours
✅ **Reliability** - Automatic health checks and rollback on failure
✅ **Safety** - All-or-nothing deployments, no partial failures
✅ **Simplicity** - One command, complex orchestration happens automatically

**This is the path to Level 2 automation** - where Claude can deploy entire application stacks, not just individual services.

---

**Status:** Ready for CLI execution
**Prerequisites:** Session 3 (homelab-deployment skill) ✅
**Next Steps:** Execute Phase 1 (Foundation) when CLI credits available
**Questions:** Review plan, request clarifications before implementation
