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
    "snapshot_version": "1.0"
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
        local volumes=$(podman inspect "$container" --format '{{range .Mounts}}{{.Source}}:{{.Destination}}:{{.Mode}} {{end}}' 2>/dev/null | xargs)
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
  }
EOF

    log_info "Collected architectural metadata"
}

##############################################################################
# Main
##############################################################################

main() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}" >&2
    echo -e "${BLUE}        HOMELAB SNAPSHOT TOOL v1.0${NC}" >&2
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
