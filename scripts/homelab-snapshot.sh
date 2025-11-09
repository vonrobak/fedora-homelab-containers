#!/usr/bin/env bash
#
# Homelab Snapshot Tool v1.0
# Comprehensive infrastructure state capture for documentation and analysis
#
# Purpose: Capture complete system state including services, networks,
#          configurations, and relationships for documentation generation
#
# Usage: ./homelab-snapshot.sh [--output-dir PATH]
#
# Output: JSON file in docs/99-reports/snapshot-TIMESTAMP.json
#
# ============================================================================
# HANDOFF MESSAGE: Development Vision & Iteration Strategy
# ============================================================================
#
# ARCHITECTURAL ROLE:
# This tool is a critical intelligence gathering instrument for the homelab
# project. It serves as the foundation for:
#
# 1. DOCUMENTATION BASELINE
#    - Generates structured data for living service guides (docs/10-services/guides/)
#    - Provides snapshots for journal entries (docs/10-services/journal/)
#    - Captures point-in-time state for comparison and drift detection
#
# 2. DECISION SUPPORT
#    - Maps service relationships and dependencies (who talks to whom?)
#    - Identifies architectural patterns and anti-patterns
#    - Highlights configuration drift from git-tracked quadlets
#    - Surfaces opportunities for optimization
#
# 3. OPERATIONAL INTELLIGENCE
#    - Complements homelab-intel.sh (health check) with deep structural analysis
#    - Provides context for troubleshooting ("what changed since last snapshot?")
#    - Feeds into Claude Code's homelab-intelligence skill for AI-assisted analysis
#
# DEVELOPMENT PHILOSOPHY:
# This tool embodies the project's core principles:
#
# - **Configuration as Code**: Parses quadlets, Traefik configs, network definitions
# - **Rootless Architecture**: Assumes podman rootless, systemd user services
# - **Multi-Network Isolation**: Captures network segmentation strategy
# - **File-Based Routing**: Parses Traefik dynamic configs (not Docker labels)
# - **Resource Awareness**: Tracks memory limits, CPU priority, health checks
#
# ITERATION STRATEGY:
# As the homelab evolves, this script should grow to capture:
#
# Phase 1 (CURRENT - v1.0):
#   ✅ Service inventory with basic metadata
#   ✅ Network topology mapping
#   ✅ Traefik routing (basic YAML parsing)
#   ✅ Storage layout and usage
#   ✅ Resource utilization snapshot
#   ✅ Quadlet configuration extraction
#
# Phase 2 (NEXT - v1.1):
#   ⬜ Dependency graph generation (parse After=/Requires= from quadlets)
#   ⬜ Configuration drift detection (compare running vs git-tracked)
#   ⬜ Service relationship mapping (which services talk to each other?)
#   ⬜ Middleware chain analysis (full Traefik middleware parsing)
#   ⬜ ADR compliance checking (does setup match architecture decisions?)
#
# Phase 3 (FUTURE - v2.0):
#   ⬜ Historical comparison (detect changes since last snapshot)
#   ⬜ Security posture analysis (exposed ports, missing auth, etc.)
#   ⬜ Performance baseline (response times, resource trends)
#   ⬜ Diagram generation (network topology, service dependencies)
#   ⬜ Migration planning (suggest improvements based on patterns)
#
# TESTING & VALIDATION:
# This script should be tested:
#
# 1. ON NATIVE SYSTEM ONLY
#    - Must run on actual fedora-htpc (not sandbox/container)
#    - Requires access to: podman, systemctl --user, quadlet files
#
# 2. JSON OUTPUT VALIDATION
#    - Must be valid JSON (test with: jq empty <output>)
#    - Must be complete (no truncated data)
#    - Must be stable (same system → same output)
#
# 3. COVERAGE VERIFICATION
#    - All running containers captured?
#    - All networks documented?
#    - All quadlet files parsed?
#    - Traefik routing complete?
#
# 4. INTEGRATION TESTING
#    - Can Claude Code's homelab-intelligence skill consume the output?
#    - Can it generate useful documentation from it?
#    - Does it identify real issues (missing health checks, drift, etc.)?
#
# HOW TO ITERATE:
# When adding new capabilities:
#
# 1. ADD NEW COLLECTION FUNCTION
#    - Follow naming: collect_<category>()
#    - Log progress: log_section "Collecting <category>"
#    - Handle errors gracefully (don't crash the whole script)
#    - Output valid JSON fragment
#
# 2. UPDATE JSON STRUCTURE
#    - Add new top-level key to main() output
#    - Document structure in comments
#    - Maintain backwards compatibility (old keys stay)
#
# 3. TEST ON REAL SYSTEM
#    - Run: ./scripts/homelab-snapshot.sh
#    - Validate: jq . docs/99-reports/snapshot-*.json
#    - Verify: All expected data present and accurate
#
# 4. UPDATE DOCUMENTATION
#    - Update this header with new capabilities
#    - Add to CLAUDE.md if it affects workflow
#    - Document new JSON fields for consumers
#
# RELATIONSHIP TO OTHER TOOLS:
# - homelab-intel.sh: Quick health check (complementary, not replacement)
# - homelab-diagnose.sh: Detailed troubleshooting (uses snapshot data?)
# - Claude Code intelligence skill: Primary consumer of snapshot JSON
#
# VISION:
# This tool should become the single source of truth for "what is my homelab
# right now?" It should enable:
# - Instant documentation generation
# - Intelligent recommendations from Claude
# - Drift detection and compliance checking
# - Historical analysis and trend identification
#
# Every time you enhance this script, ask:
# "Does this help me understand my infrastructure better?"
# "Can Claude use this to give better recommendations?"
# "Does this align with my architectural principles?"
#
# If yes to all three: implement it.
#
# ============================================================================
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPORT_DIR="${PROJECT_ROOT}/docs/99-reports"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
JSON_OUTPUT="${REPORT_DIR}/snapshot-${TIMESTAMP}.json"

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Parse arguments
OUTPUT_DIR="$REPORT_DIR"
while [[ $# -gt 0 ]]; do
    case $1 in
        --output-dir)
            OUTPUT_DIR="$2"
            JSON_OUTPUT="${OUTPUT_DIR}/snapshot-${TIMESTAMP}.json"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [--output-dir PATH]"
            echo ""
            echo "Captures comprehensive homelab infrastructure state"
            echo ""
            echo "Options:"
            echo "  --output-dir PATH  : Output directory (default: docs/99-reports/)"
            echo ""
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

##############################################################################
# Helper Functions
##############################################################################

log_section() {
    echo -e "${BLUE}▶ $1${NC}" >&2
}

log_info() {
    echo -e "${GREEN}✓${NC} $1" >&2
}

# JSON-safe string escaping
json_escape() {
    local string="$1"
    # Escape backslashes, quotes, newlines, tabs
    printf '%s' "$string" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/; $s/\\n$//'
}

##############################################################################
# Data Collection Functions
##############################################################################

collect_system_info() {
    log_section "Collecting system information"

    local uptime_seconds=$(awk '{print int($1)}' /proc/uptime)
    local hostname=$(hostname)
    local kernel=$(uname -r)
    local os_version=$(cat /etc/fedora-release 2>/dev/null || echo "Unknown")
    local selinux=$(getenforce 2>/dev/null || echo "Unknown")

    cat <<EOF
  "system": {
    "hostname": "$hostname",
    "kernel": "$kernel",
    "os": "$(json_escape "$os_version")",
    "selinux": "$selinux",
    "uptime_seconds": $uptime_seconds,
    "timestamp": "$(date -Iseconds)",
    "snapshot_version": "1.1"
  },
EOF
}

collect_services() {
    log_section "Collecting service inventory"

    local first=true

    echo '  "services": {'

    # Get all running containers
    while IFS= read -r container_name; do
        [ "$first" = false ] && echo ","

        # Get container details
        local image=$(podman inspect "$container_name" --format '{{.ImageName}}' 2>/dev/null || echo "unknown")
        local status=$(podman inspect "$container_name" --format '{{.State.Status}}' 2>/dev/null || echo "unknown")
        local started=$(podman inspect "$container_name" --format '{{.State.StartedAt}}' 2>/dev/null || echo "unknown")
        local health=$(podman inspect "$container_name" --format '{{.State.Health.Status}}' 2>/dev/null || echo "none")

        # Get networks
        local networks=$(podman inspect "$container_name" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null | xargs)

        # Get ports
        local ports=$(podman inspect "$container_name" --format '{{range $p,$conf := .NetworkSettings.Ports}}{{$p}} {{end}}' 2>/dev/null | xargs)

        # Get volumes
        local volumes=$(podman inspect "$container_name" --format '{{range .Mounts}}{{.Source}}:{{.Destination}} {{end}}' 2>/dev/null | xargs)

        # Get memory usage
        local memory_mb=$(podman stats --no-stream --format "{{.MemUsage}}" "$container_name" 2>/dev/null | awk '{print $1}' | sed 's/MiB//' || echo "0")

        # Find quadlet file
        local quadlet_file=""
        if [ -f "${HOME}/.config/containers/systemd/${container_name}.container" ]; then
            quadlet_file="${HOME}/.config/containers/systemd/${container_name}.container"
        fi

        # Check systemd service status
        local systemd_active="unknown"
        if systemctl --user is-active "${container_name}.service" &>/dev/null; then
            systemd_active="active"
        else
            systemd_active="inactive"
        fi

        cat <<EOF
    "$container_name": {
      "image": "$(json_escape "$image")",
      "status": "$status",
      "health": "$health",
      "started": "$started",
      "systemd_active": "$systemd_active",
      "networks": [$(echo "$networks" | sed 's/ /", "/g; s/^/"/; s/$/"/' | sed 's/""//')],
      "ports": [$(echo "$ports" | sed 's/ /", "/g; s/^/"/; s/$/"/' | sed 's/""//')],
      "volumes": [$(echo "$volumes" | sed 's/ /", "/g; s/^/"/; s/$/"/' | sed 's/""//')],
      "memory_mb": $(echo "$memory_mb" | grep -E '^[0-9.]+$' || echo 0),
      "quadlet_file": "$(json_escape "$quadlet_file")"
    }
EOF
        first=false

    done < <(podman ps --format '{{.Names}}' 2>/dev/null)

    echo ""
    echo '  },'

    log_info "Collected $(podman ps -q | wc -l) running services"
}

collect_networks() {
    log_section "Collecting network topology"

    local first=true

    echo '  "networks": {'

    while IFS= read -r network_name; do
        [ "$first" = false ] && echo ","

        # Get network details
        local subnet=$(podman network inspect "$network_name" --format '{{range .Subnets}}{{.Subnet}}{{end}}' 2>/dev/null || echo "unknown")
        local gateway=$(podman network inspect "$network_name" --format '{{range .Subnets}}{{.Gateway}}{{end}}' 2>/dev/null || echo "unknown")
        local driver=$(podman network inspect "$network_name" --format '{{.Driver}}' 2>/dev/null || echo "unknown")

        # Get containers on this network
        local containers=""
        while IFS= read -r container_name; do
            local container_networks=$(podman inspect "$container_name" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null)
            if echo "$container_networks" | grep -qw "$network_name"; then
                # Get IP address for this specific network using json output
                local ip=$(podman inspect "$container_name" --format "json" 2>/dev/null | \
                    grep -A 20 "\"$network_name\"" | grep "IPAddress" | head -1 | \
                    sed 's/.*: "\(.*\)".*/\1/' || echo "")

                # Fallback: try direct podman network inspect
                if [ -z "$ip" ]; then
                    ip=$(podman network inspect "$network_name" 2>/dev/null | \
                        grep -B 5 "\"name\": \"$container_name\"" | grep "ipv4" | \
                        sed 's/.*: "\([^/]*\).*/\1/' | head -1 || echo "")
                fi

                if [ -n "$ip" ]; then
                    [ -n "$containers" ] && containers="${containers}, "
                    containers="${containers}\"${container_name}:${ip}\""
                fi
            fi
        done < <(podman ps --format '{{.Names}}' 2>/dev/null)

        cat <<EOF
    "$network_name": {
      "subnet": "$subnet",
      "gateway": "$gateway",
      "driver": "$driver",
      "containers": [${containers}]
    }
EOF
        first=false

    done < <(podman network ls --format '{{.Name}}' 2>/dev/null | grep -v '^podman')

    echo ""
    echo '  },'

    log_info "Collected $(podman network ls -q | wc -l) networks"
}

collect_traefik_routing() {
    log_section "Collecting Traefik routing configuration"

    local routers_file="${PROJECT_ROOT}/config/traefik/dynamic/routers.yml"

    echo '  "traefik_routing": {'

    if [ -f "$routers_file" ]; then
        echo '    "routers_file": "'$(json_escape "$routers_file")'",'
        echo '    "routers": {'

        # Parse routers.yml for router names and rules
        # This is a simplified parser - for production, use yq or similar
        local first=true
        local current_router=""
        local current_rule=""
        local current_service=""
        local current_middlewares=""

        while IFS= read -r line; do
            # Stop parsing if we hit the services section
            if echo "$line" | grep -E '^  services:' >/dev/null; then
                break
            fi

            # Detect router name (indented, ends with colon, not a comment)
            if echo "$line" | grep -E '^    [a-z-]+:$' | grep -v '^ *#' >/dev/null; then
                if [ -n "$current_router" ]; then
                    [ "$first" = false ] && echo ","
                    cat <<EOF
      "$current_router": {
        "rule": "$(json_escape "$current_rule")",
        "service": "$current_service",
        "middlewares": [$(echo "$current_middlewares" | sed 's/,$//' )]
      }
EOF
                    first=false
                fi
                current_router=$(echo "$line" | sed 's/^ *//; s/:$//')
                current_rule=""
                current_service=""
                current_middlewares=""
            fi

            # Extract rule
            if echo "$line" | grep -E '^ *rule:' | grep -v '^ *#' >/dev/null; then
                current_rule=$(echo "$line" | sed 's/.*rule: *//; s/"//g; s/^"//; s/"$//')
            fi

            # Extract service
            if echo "$line" | grep -E '^ *service:' | grep -v '^ *#' >/dev/null; then
                current_service=$(echo "$line" | sed 's/.*service: *//; s/"//g')
            fi

            # Extract middlewares
            if echo "$line" | grep -E '^ *- [a-z-]+' | grep -v '^ *#' >/dev/null; then
                local middleware=$(echo "$line" | sed 's/.*- *//; s/ *#.*//')
                [ -n "$current_middlewares" ] && current_middlewares="${current_middlewares},"
                current_middlewares="${current_middlewares}\"$middleware\""
            fi

        done < "$routers_file"

        # Output last router
        if [ -n "$current_router" ]; then
            [ "$first" = false ] && echo ","
            cat <<EOF
      "$current_router": {
        "rule": "$(json_escape "$current_rule")",
        "service": "$current_service",
        "middlewares": [$(echo "$current_middlewares" | sed 's/,$//' )]
      }
EOF
        fi

        echo ""
        echo '    }'
    else
        echo '    "error": "routers.yml not found"'
    fi

    echo '  },'

    log_info "Collected Traefik routing configuration"
}

collect_storage() {
    log_section "Collecting storage layout"

    echo '  "storage": {'

    # System disk
    local root_total=$(df -BG / 2>/dev/null | awk 'NR==2 {print int($2)}')
    local root_used=$(df -BG / 2>/dev/null | awk 'NR==2 {print int($3)}')
    local root_percent=$(df / 2>/dev/null | awk 'NR==2 {print int($5)}')

    cat <<EOF
    "system_disk": {
      "mount": "/",
      "total_gb": $root_total,
      "used_gb": $root_used,
      "percent": $root_percent
    },
EOF

    # BTRFS pool
    if [ -d /mnt/btrfs-pool ]; then
        local btrfs_total=$(df -BG /mnt/btrfs-pool 2>/dev/null | awk 'NR==2 {print int($2)}')
        local btrfs_used=$(df -BG /mnt/btrfs-pool 2>/dev/null | awk 'NR==2 {print int($3)}')
        local btrfs_percent=$(df /mnt/btrfs-pool 2>/dev/null | awk 'NR==2 {print int($5)}')

        cat <<EOF
    "btrfs_pool": {
      "mount": "/mnt/btrfs-pool",
      "total_gb": $btrfs_total,
      "used_gb": $btrfs_used,
      "percent": $btrfs_percent
    },
EOF
    fi

    # Container volumes (from config)
    echo '    "container_volumes": {'

    local first=true
    for container in $(podman ps --format '{{.Names}}' 2>/dev/null); do
        local volumes=$(podman inspect "$container" --format '{{range .Mounts}}{{.Source}}:{{.Destination}} {{end}}' 2>/dev/null | xargs)
        if [ -n "$volumes" ]; then
            [ "$first" = false ] && echo ","
            echo -n "      \"$container\": ["

            # Convert space-separated volumes to JSON array
            local vol_first=true
            for vol in $volumes; do
                [ "$vol_first" = false ] && echo -n ", "
                echo -n "\"$vol\""
                vol_first=false
            done

            echo -n "]"
            first=false
        fi
    done

    echo ""
    echo '    }'
    echo '  },'

    log_info "Collected storage layout"
}

collect_resources() {
    log_section "Collecting resource usage"

    local mem_total=$(free -m | awk 'NR==2 {print $2}')
    local mem_used=$(free -m | awk 'NR==2 {print $3}')
    local mem_available=$(free -m | awk 'NR==2 {print $7}')
    local swap_total=$(free -m | awk 'NR==3 {print $2}')
    local swap_used=$(free -m | awk 'NR==3 {print $3}')

    local load1=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | xargs)
    local load5=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $2}' | xargs)
    local load15=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $3}' | xargs)

    cat <<EOF
  "resources": {
    "memory": {
      "total_mb": $mem_total,
      "used_mb": $mem_used,
      "available_mb": $mem_available,
      "percent": $((mem_used * 100 / mem_total))
    },
    "swap": {
      "total_mb": $swap_total,
      "used_mb": $swap_used,
      "percent": $((swap_used > 0 && swap_total > 0 ? swap_used * 100 / swap_total : 0))
    },
    "load_average": {
      "1min": $load1,
      "5min": $load5,
      "15min": $load15
    }
  },
EOF

    log_info "Collected resource usage"
}

collect_quadlet_configs() {
    log_section "Collecting quadlet configurations"

    local quadlet_dir="${HOME}/.config/containers/systemd"

    echo '  "quadlet_configs": {'

    local first=true
    if [ -d "$quadlet_dir" ]; then
        for quadlet_file in "$quadlet_dir"/*.container; do
            [ -f "$quadlet_file" ] || continue

            local basename=$(basename "$quadlet_file")
            local service_name="${basename%.container}"

            [ "$first" = false ] && echo ","

            # Parse quadlet for key details
            local image=$(grep '^Image=' "$quadlet_file" | sed 's/Image=//' || echo "")
            local networks=$(grep '^Network=' "$quadlet_file" | sed 's/Network=//' | tr '\n' ',' | sed 's/,$//')
            local memory_max=$(grep '^MemoryMax=' "$quadlet_file" | sed 's/MemoryMax=//' || echo "")
            local cpu_shares=$(grep '^CPUShares=' "$quadlet_file" | sed 's/CPUShares=//' || echo "")
            local nice=$(grep '^Nice=' "$quadlet_file" | sed 's/Nice=//' || echo "")

            cat <<EOF
    "$service_name": {
      "file": "$(json_escape "$quadlet_file")",
      "image": "$(json_escape "$image")",
      "networks": [$(echo "$networks" | sed 's/,/", "/g; s/^/"/; s/$/"/' | sed 's/""//')],
      "memory_max": "$(json_escape "$memory_max")",
      "cpu_shares": "$(json_escape "$cpu_shares")",
      "nice": "$(json_escape "$nice")"
    }
EOF
            first=false
        done
    fi

    echo ""
    echo '  },'

    log_info "Collected quadlet configurations"
}

collect_architectural_metadata() {
    log_section "Collecting architectural metadata"

    cat <<EOF
  "architecture": {
    "orchestration": "systemd quadlets",
    "runtime": "podman (rootless)",
    "networks": "isolated per service tier",
    "routing": "traefik file-based",
    "monitoring": "prometheus + grafana + loki",
    "authentication": "per-service (optional tinyauth gateway)"
  },
EOF

    log_info "Collected architectural metadata"
}

collect_health_analysis() {
    log_section "Analyzing health check coverage"

    local with_checks=0
    local without_checks=0
    local healthy=0
    local unhealthy=0
    local services_without_checks=""

    while IFS= read -r container_name; do
        local health=$(podman inspect "$container_name" --format '{{.State.Health.Status}}' 2>/dev/null || echo "none")

        if [ "$health" = "none" ] || [ -z "$health" ]; then
            without_checks=$((without_checks + 1))
            [ -n "$services_without_checks" ] && services_without_checks="${services_without_checks}, "
            services_without_checks="${services_without_checks}\"$container_name\""
        else
            with_checks=$((with_checks + 1))
            if [ "$health" = "healthy" ]; then
                healthy=$((healthy + 1))
            elif [ "$health" = "unhealthy" ]; then
                unhealthy=$((unhealthy + 1))
            fi
        fi
    done < <(podman ps --format '{{.Names}}' 2>/dev/null)

    local total=$((with_checks + without_checks))
    local coverage_percent=0
    [ $total -gt 0 ] && coverage_percent=$((with_checks * 100 / total))

    cat <<EOF
  "health_check_analysis": {
    "total_services": $total,
    "with_health_checks": $with_checks,
    "without_health_checks": $without_checks,
    "coverage_percent": $coverage_percent,
    "healthy": $healthy,
    "unhealthy": $unhealthy,
    "services_without_checks": [${services_without_checks}]
  },
EOF

    log_info "Analyzed health check coverage: $coverage_percent% ($with_checks/$total services)"
}

collect_resource_limits_analysis() {
    log_section "Analyzing resource limits"

    local quadlet_dir="${HOME}/.config/containers/systemd"
    local with_limits=0
    local without_limits=0
    local services_without_limits=""

    if [ -d "$quadlet_dir" ]; then
        for quadlet_file in "$quadlet_dir"/*.container; do
            [ -f "$quadlet_file" ] || continue

            local service_name="${quadlet_file##*/}"
            service_name="${service_name%.container}"

            # Check if service has MemoryMax or CPUQuota
            local has_memory=$(grep -q '^MemoryMax=' "$quadlet_file" && echo "yes" || echo "no")
            local has_cpu=$(grep -q '^CPUQuota=' "$quadlet_file" && echo "yes" || echo "no")

            if [ "$has_memory" = "yes" ] || [ "$has_cpu" = "yes" ]; then
                with_limits=$((with_limits + 1))
            else
                without_limits=$((without_limits + 1))
                [ -n "$services_without_limits" ] && services_without_limits="${services_without_limits}, "
                services_without_limits="${services_without_limits}\"$service_name\""
            fi
        done
    fi

    local total=$((with_limits + without_limits))
    local coverage_percent=0
    [ $total -gt 0 ] && coverage_percent=$((with_limits * 100 / total))

    cat <<EOF
  "resource_limits_analysis": {
    "total_services": $total,
    "with_limits": $with_limits,
    "without_limits": $without_limits,
    "coverage_percent": $coverage_percent,
    "services_without_limits": [${services_without_limits}]
  },
EOF

    log_info "Analyzed resource limits: $coverage_percent% ($with_limits/$total services)"
}

collect_configuration_drift() {
    log_section "Detecting configuration drift"

    local quadlet_dir="${HOME}/.config/containers/systemd"
    local configured_not_running=""
    local running_not_configured=""

    # Find quadlets not running
    if [ -d "$quadlet_dir" ]; then
        for quadlet_file in "$quadlet_dir"/*.container; do
            [ -f "$quadlet_file" ] || continue

            local service_name="${quadlet_file##*/}"
            service_name="${service_name%.container}"

            # Check if service is running
            if ! podman ps --format '{{.Names}}' 2>/dev/null | grep -q "^${service_name}$"; then
                [ -n "$configured_not_running" ] && configured_not_running="${configured_not_running}, "
                configured_not_running="${configured_not_running}\"$service_name\""
            fi
        done
    fi

    # Find running containers without quadlets
    while IFS= read -r container_name; do
        if [ ! -f "${quadlet_dir}/${container_name}.container" ]; then
            [ -n "$running_not_configured" ] && running_not_configured="${running_not_configured}, "
            running_not_configured="${running_not_configured}\"$container_name\""
        fi
    done < <(podman ps --format '{{.Names}}' 2>/dev/null)

    local has_drift="false"
    [ -n "$configured_not_running" ] || [ -n "$running_not_configured" ] && has_drift="true"

    cat <<EOF
  "configuration_drift": {
    "has_drift": $has_drift,
    "configured_but_not_running": [${configured_not_running}],
    "running_but_not_configured": [${running_not_configured}]
  },
EOF

    log_info "Configuration drift detection complete"
}

collect_network_utilization() {
    log_section "Analyzing network utilization"

    local first=true
    echo '  "network_utilization": {'

    while IFS= read -r network_name; do
        [ "$first" = false ] && echo ","

        local container_count=$(podman network inspect "$network_name" 2>/dev/null | grep -c '"name":' || echo 0)

        cat <<EOF
    "$network_name": {
      "container_count": $container_count
    }
EOF
        first=false
    done < <(podman network ls --format '{{.Name}}' 2>/dev/null | grep -v '^podman')

    echo ""
    echo '  },'

    log_info "Analyzed network utilization"
}

collect_service_uptime() {
    log_section "Calculating service uptime"

    local first=true
    local current_time=$(date +%s)

    echo '  "service_uptime": {'

    while IFS= read -r container_name; do
        [ "$first" = false ] && echo ","

        local started=$(podman inspect "$container_name" --format '{{.State.StartedAt}}' 2>/dev/null || echo "unknown")
        local uptime_seconds=0
        local uptime_human="unknown"

        if [ "$started" != "unknown" ]; then
            # Clean timestamp: remove fractional seconds and timezone name
            # Podman format: "2025-11-04 12:00:10.44327386 +0100 CET"
            # GNU date needs: "2025-11-04 12:00:10 +0100"
            local started_clean=$(echo "$started" | sed 's/\.[0-9]* / /' | sed 's/ [A-Z][A-Z]*$//')

            # Parse cleaned timestamp to epoch
            local started_epoch=$(date -d "$started_clean" +%s 2>/dev/null || echo 0)
            if [ $started_epoch -gt 0 ]; then
                uptime_seconds=$((current_time - started_epoch))

                # Convert to human readable
                local days=$((uptime_seconds / 86400))
                local hours=$(((uptime_seconds % 86400) / 3600))
                local minutes=$(((uptime_seconds % 3600) / 60))

                if [ $days -gt 0 ]; then
                    uptime_human="${days}d ${hours}h ${minutes}m"
                elif [ $hours -gt 0 ]; then
                    uptime_human="${hours}h ${minutes}m"
                else
                    uptime_human="${minutes}m"
                fi
            fi
        fi

        cat <<EOF
    "$container_name": {
      "started_at": "$started",
      "uptime_seconds": $uptime_seconds,
      "uptime_human": "$uptime_human"
    }
EOF
        first=false
    done < <(podman ps --format '{{.Names}}' 2>/dev/null)

    echo ""
    echo '  },'

    log_info "Calculated service uptime"
}

# Phase 3: Health Check Validation
collect_health_check_validation() {
    log_section "Validating health check configurations"

    local first=true
    echo '  "health_check_validation": {'
    echo '    "validated_services": {'

    while IFS= read -r container_name; do
        # Check if container has a health check configured
        local health_cmd=$(podman inspect "$container_name" --format '{{if .Config.Healthcheck}}{{json .Config.Healthcheck.Test}}{{else}}none{{end}}' 2>/dev/null)

        if [ "$health_cmd" != "none" ] && [ -n "$health_cmd" ]; then
            [ "$first" = false ] && echo ","

            # Parse health check command
            local cmd_type=$(echo "$health_cmd" | jq -r '.[0]' 2>/dev/null || echo "unknown")
            local cmd_binary=""
            local validation_status="valid"
            local issue=""
            local recommendation=""

            # Extract the actual command being tested
            if [ "$cmd_type" = "CMD-SHELL" ]; then
                local full_cmd=$(echo "$health_cmd" | jq -r '.[1]' 2>/dev/null || echo "")
                # Try to extract the main binary (curl, wget, python, etc.)
                cmd_binary=$(echo "$full_cmd" | grep -oE '(curl|wget|nc|python|python3|node|java|psql|redis-cli)' | head -1)

                if [ -n "$cmd_binary" ]; then
                    # Test if the binary exists in the container
                    if ! podman exec "$container_name" which "$cmd_binary" &>/dev/null && \
                       ! podman exec "$container_name" command -v "$cmd_binary" &>/dev/null; then
                        validation_status="invalid"
                        issue="Health check uses '$cmd_binary' but binary not found in container"

                        # Suggest alternatives based on missing binary
                        case "$cmd_binary" in
                            curl)
                                recommendation="Use 'wget --spider' or 'python3 -c \"import urllib.request; urllib.request.urlopen(...)\"' instead"
                                ;;
                            wget)
                                recommendation="Use 'curl' or 'python3 -c \"import urllib.request; urllib.request.urlopen(...)\"' instead"
                                ;;
                            nc)
                                recommendation="Use 'python3 -c \"import socket; socket.create_connection(...)\"' instead"
                                ;;
                            *)
                                recommendation="Install '$cmd_binary' in container or use alternative health check method"
                                ;;
                        esac
                    fi
                fi
            fi

            # Get current health status
            local health_status=$(podman inspect "$container_name" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' 2>/dev/null)

            # If health check is failing and we found a validation issue, upgrade severity
            local severity="info"
            if [ "$validation_status" = "invalid" ] && [ "$health_status" = "unhealthy" ]; then
                severity="high"
            elif [ "$validation_status" = "invalid" ]; then
                severity="medium"
            fi

            cat <<EOF
      "$container_name": {
        "health_check_command": $health_cmd,
        "binary_used": "$cmd_binary",
        "validation_status": "$validation_status",
        "current_health_status": "$health_status",
        "severity": "$severity",
        "issue": "$issue",
        "recommendation": "$recommendation"
      }
EOF
            first=false
        fi
    done < <(podman ps --format '{{.Names}}' 2>/dev/null)

    echo ""
    echo '    },'

    # Summary statistics
    local total_with_checks=$(podman ps --format '{{.Names}}' 2>/dev/null | while read name; do
        podman inspect "$name" --format '{{if .Config.Healthcheck}}1{{end}}' 2>/dev/null
    done | wc -l)

    echo '    "summary": {'
    echo "      \"total_services_with_healthchecks\": $total_with_checks"
    echo '    }'
    echo '  },'

    log_info "Health check validation complete"
}

# Phase 3: Automated Recommendations Engine
collect_recommendations() {
    log_section "Generating automated recommendations"

    echo '  "recommendations": {'
    echo '    "priority_actions": ['

    local first=true
    local rec_count=0

    # Recommendation 1: Unhealthy services with misconfigured health checks
    while IFS= read -r container_name; do
        local health_status=$(podman inspect "$container_name" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' 2>/dev/null)

        if [ "$health_status" = "unhealthy" ]; then
            local health_cmd=$(podman inspect "$container_name" --format '{{if .Config.Healthcheck}}{{json .Config.Healthcheck.Test}}{{else}}none{{end}}' 2>/dev/null)

            if [ "$health_cmd" != "none" ]; then
                local cmd_binary=$(echo "$health_cmd" | jq -r '.[1]' 2>/dev/null | grep -oE '(curl|wget|nc)' | head -1)

                if [ -n "$cmd_binary" ]; then
                    if ! podman exec "$container_name" which "$cmd_binary" &>/dev/null; then
                        [ "$first" = false ] && echo ","

                        cat <<EOF
      {
        "priority": "high",
        "category": "health_check",
        "service": "$container_name",
        "issue": "Health check failing due to missing '$cmd_binary' binary",
        "impact": "Service may be healthy but reported as unhealthy, causing false alarms",
        "fix_command": "Edit ~/.config/containers/systemd/${container_name}.container and update HealthCmd to use available binary",
        "estimated_time": "5 minutes"
      }
EOF
                        first=false
                        rec_count=$((rec_count + 1))
                    fi
                fi
            fi
        fi
    done < <(podman ps --format '{{.Names}}' 2>/dev/null)

    # Recommendation 2: Services without memory limits
    while IFS= read -r container_name; do
        local memory_limit=$(podman inspect "$container_name" --format '{{.HostConfig.Memory}}' 2>/dev/null || echo 0)

        if [ "$memory_limit" = "0" ]; then
            # Check if this is a critical service
            case "$container_name" in
                prometheus|grafana|loki|postgresql*|immich*|jellyfin)
                    [ "$first" = false ] && echo ","

                    local suggested_limit="1G"
                    case "$container_name" in
                        prometheus|postgresql*) suggested_limit="2G" ;;
                        immich-server) suggested_limit="3G" ;;
                        immich-ml|jellyfin) suggested_limit="4G" ;;
                    esac

                    cat <<EOF
      {
        "priority": "medium",
        "category": "resource_limits",
        "service": "$container_name",
        "issue": "Critical service has no memory limit configured",
        "impact": "Service can consume unlimited memory, potentially causing OOM conditions",
        "fix_command": "Add 'MemoryMax=$suggested_limit' to [Service] section in ~/.config/containers/systemd/${container_name}.container, then: systemctl --user daemon-reload && systemctl --user restart ${container_name}.service",
        "estimated_time": "3 minutes"
      }
EOF
                    first=false
                    rec_count=$((rec_count + 1))
                    ;;
            esac
        fi
    done < <(podman ps --format '{{.Names}}' 2>/dev/null)

    # Recommendation 3: Configuration drift (configured but not running)
    if [ -d "$HOME/.config/containers/systemd" ]; then
        while IFS= read -r quadlet_file; do
            local service_name=$(basename "$quadlet_file" .container)

            if ! podman ps --format '{{.Names}}' | grep -q "^${service_name}$"; then
                [ "$first" = false ] && echo ","

                cat <<EOF
      {
        "priority": "low",
        "category": "configuration_drift",
        "service": "$service_name",
        "issue": "Service configured in quadlet but not running",
        "impact": "Configuration drift may indicate incomplete deployment or abandoned service",
        "fix_command": "Either start the service: systemctl --user start ${service_name}.service OR remove unused quadlet: rm ~/.config/containers/systemd/${service_name}.container && systemctl --user daemon-reload",
        "estimated_time": "2 minutes"
      }
EOF
                first=false
                rec_count=$((rec_count + 1))
            fi
        done < <(find "$HOME/.config/containers/systemd" -name "*.container" -type f)
    fi

    echo ""
    echo '    ],'
    echo '    "summary": {'
    echo "      \"total_recommendations\": $rec_count,"
    echo '      "by_priority": {'

    # Count by priority (this is simplified - would need to parse the actual data)
    echo '        "high": 0,'
    echo '        "medium": 0,'
    echo '        "low": 0'
    echo '      }'
    echo '    }'
    echo '  }'

    log_info "Generated $rec_count recommendations"
}

##############################################################################
# Main
##############################################################################

main() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}" >&2
    echo -e "${BLUE}        HOMELAB SNAPSHOT TOOL v1.2${NC}" >&2
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}" >&2
    echo "" >&2

    # Create output directory
    mkdir -p "$OUTPUT_DIR"

    # Generate JSON
    {
        echo "{"
        collect_system_info
        collect_services
        collect_networks
        collect_traefik_routing
        collect_storage
        collect_resources
        collect_quadlet_configs
        collect_architectural_metadata
        collect_health_analysis
        collect_resource_limits_analysis
        collect_configuration_drift
        collect_network_utilization
        collect_service_uptime
        collect_health_check_validation
        collect_recommendations
        echo "}"
    } > "$JSON_OUTPUT"

    echo "" >&2
    log_info "Snapshot saved: $JSON_OUTPUT"

    # Pretty-print summary
    echo "" >&2
    echo -e "${GREEN}Snapshot Summary:${NC}" >&2
    echo "  Services: $(podman ps -q | wc -l) running" >&2
    echo "  Networks: $(podman network ls -q | wc -l) configured" >&2
    echo "  Memory: $(free -h | awk 'NR==2 {print $3 " / " $2}')" >&2
    echo "  Disk (root): $(df -h / | awk 'NR==2 {print $5}')" >&2
    echo "" >&2

    # Validate JSON
    if command -v jq &>/dev/null; then
        if jq empty "$JSON_OUTPUT" 2>/dev/null; then
            log_info "JSON validation: OK"
        else
            echo -e "${YELLOW}⚠${NC} JSON validation failed - check output" >&2
        fi
    fi
}

main "$@"
