#!/bin/bash
# Service Catalog Generator
# Generates comprehensive inventory of all services from running containers and quadlets

set -euo pipefail

# Configuration
QUADLET_DIR="${HOME}/.config/containers/systemd"
TRAEFIK_ROUTERS="${HOME}/containers/config/traefik/dynamic/routers.yml"
OUTPUT_FILE="${HOME}/containers/docs/AUTO-SERVICE-CATALOG.md"

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $*" >&2
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

# Get running container information
get_running_containers() {
    podman ps --format json | jq -r '.[] | "\(.Names)|\(.Image)|\(.State)|\(.Status)|\(.Networks // [])"'
}

# Get container resource usage
get_container_stats() {
    local container=$1
    # Skip stats for now - can be slow/blocking
    echo "N/A"
}

# Get container health status
get_health_status() {
    local container=$1
    local health=$(podman inspect "$container" --format '{{.State.Health.Status}}' 2>/dev/null || echo "none")

    case "$health" in
        healthy) echo "✅ Healthy" ;;
        unhealthy) echo "❌ Unhealthy" ;;
        starting) echo "🔄 Starting" ;;
        none) echo "➖ No healthcheck" ;;
        *) echo "$health" ;;
    esac
}

# Get uptime for container
get_uptime() {
    local container=$1
    local started=$(podman inspect "$container" --format '{{.State.StartedAt}}' 2>/dev/null)

    if [[ -n "$started" ]]; then
        local start_epoch=$(date -d "$started" +%s 2>/dev/null || echo "0")
        local now_epoch=$(date +%s)
        local diff=$((now_epoch - start_epoch))

        local days=$((diff / 86400))
        local hours=$(( (diff % 86400) / 3600 ))
        local minutes=$(( (diff % 3600) / 60 ))

        if [[ $days -gt 0 ]]; then
            echo "${days}d ${hours}h"
        elif [[ $hours -gt 0 ]]; then
            echo "${hours}h ${minutes}m"
        else
            echo "${minutes}m"
        fi
    else
        echo "N/A"
    fi
}

# Get public URL from Traefik config
get_public_url() {
    local service=$1

    if [[ -f "$TRAEFIK_ROUTERS" ]]; then
        # Look for router with matching service name
        grep -A 5 "Host(\`.*${service}.*\`)" "$TRAEFIK_ROUTERS" 2>/dev/null | \
            grep -oP "Host\(\`\K[^\`]+" | head -1 || echo "-"
    else
        echo "-"
    fi
}

# Parse networks from podman inspect
get_networks() {
    local container=$1
    podman inspect "$container" --format '{{range $net, $conf := .NetworkSettings.Networks}}{{$net}} {{end}}' 2>/dev/null | \
        sed 's/systemd-//g' | sed 's/ /, /g' | sed 's/, $//'
}

# Generate markdown catalog
generate_catalog() {
    local timestamp=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
    local total_containers=$(podman ps -a | tail -n +2 | wc -l)
    local running_containers=$(podman ps | tail -n +2 | wc -l)
    local healthy_count=0

    log "Generating service catalog..."

    # Start markdown output
    cat > "$OUTPUT_FILE" <<EOF
# Service Catalog (Auto-Generated)

**Generated:** $timestamp
**Total Services:** $running_containers running / $total_containers defined
**System:** fedora-htpc ($(hostname))

---

## Running Services

EOF

    # Categorize services
    declare -A categories
    categories=(
        ["traefik"]="Gateway & Security"
        ["crowdsec"]="Gateway & Security"
        ["authelia"]="Gateway & Security"
        ["redis-authelia"]="Gateway & Security"
        ["jellyfin"]="Media Services"
        ["immich"]="Photo Management"
        ["immich-server"]="Photo Management"
        ["immich-machine-learning"]="Photo Management"
        ["immich-microservices"]="Photo Management"
        ["immich-postgres"]="Photo Management"
        ["immich-redis"]="Photo Management"
        ["prometheus"]="Monitoring Stack"
        ["grafana"]="Monitoring Stack"
        ["loki"]="Monitoring Stack"
        ["promtail"]="Monitoring Stack"
        ["alertmanager"]="Monitoring Stack"
        ["node-exporter"]="Monitoring Stack"
        ["cadvisor"]="Monitoring Stack"
        ["nextcloud"]="Productivity"
        ["nextcloud-postgres"]="Productivity"
        ["vaultwarden"]="Productivity"
        ["ocis"]="Productivity"
    )

    # Build service data
    declare -A service_data
    declare -A service_categories

    while IFS='|' read -r name image state status networks; do
        # Determine category
        category="${categories[$name]:-Other Services}"
        service_categories["$category"]=1

        # Get additional info
        health=$(get_health_status "$name")
        uptime=$(get_uptime "$name")
        memory=$(get_container_stats "$name")
        url=$(get_public_url "$name")
        net_list=$(get_networks "$name")

        # Track healthy services
        if [[ "$health" == "✅ Healthy" || "$health" == "➖ No healthcheck" ]]; then
            ((healthy_count++))
        fi

        # Store service data
        service_data["$category|$name"]="$image|$health|$uptime|$memory|$url|$net_list"
    done < <(get_running_containers)

    # Generate tables by category
    for category in "Gateway & Security" "Media Services" "Photo Management" "Monitoring Stack" "Productivity" "Other Services"; do
        if [[ -n "${service_categories[$category]:-}" ]]; then
            cat >> "$OUTPUT_FILE" <<EOF

### $category

| Service | Image | Health | Uptime | Memory | Public URL | Networks |
|---------|-------|--------|--------|--------|------------|----------|
EOF

            for key in "${!service_data[@]}"; do
                if [[ "$key" == "$category|"* ]]; then
                    name="${key#*|}"
                    IFS='|' read -r image health uptime memory url net_list <<< "${service_data[$key]}"

                    # Shorten image name
                    short_image=$(echo "$image" | sed 's|docker.io/library/||' | sed 's|docker.io/||' | sed 's|ghcr.io/||')

                    echo "| $name | $short_image | $health | $uptime | $memory | $url | $net_list |" >> "$OUTPUT_FILE"
                fi
            done
        fi
    done

    # Add summary statistics
    local health_pct=$((healthy_count * 100 / running_containers))

    cat >> "$OUTPUT_FILE" <<EOF

---

## Health Summary

- **Total Services:** $running_containers running
- **Health Status:** $healthy_count/$running_containers healthy (${health_pct}%)
- **System Load:** $(uptime | awk -F'load average:' '{print $2}')

---

## Network Overview

EOF

    # List networks and their members
    for network in $(podman network ls --format '{{.Name}}' | grep -E '^systemd-'); do
        network_short=$(echo "$network" | sed 's/systemd-//')
        members=$(podman network inspect "$network" | jq -r '.[0].Containers // {} | keys[]' | tr '\n' ', ' | sed 's/,$//')

        if [[ -n "$members" ]]; then
            echo "**$network_short:** $members" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
        fi
    done

    # Add quick links section
    cat >> "$OUTPUT_FILE" <<EOF

---

## Quick Links

**For detailed service documentation:**
- [Traefik Guide](10-services/guides/traefik.md)
- [Authelia Guide](10-services/guides/authelia.md)
- [Jellyfin Guide](10-services/guides/jellyfin.md)
- [Immich Guide](10-services/guides/immich.md)
- [Prometheus Guide](10-services/guides/prometheus.md)
- [Grafana Guide](10-services/guides/grafana.md)

**Architecture Documentation:**
- [Homelab Architecture](20-operations/guides/homelab-architecture.md)
- [Network Topology](AUTO-NETWORK-TOPOLOGY.md) (auto-generated)
- [Dependency Graph](AUTO-DEPENDENCY-GRAPH.md) (auto-generated)

---

*This catalog is auto-generated by \`scripts/generate-service-catalog.sh\`*
*To regenerate: \`~/containers/scripts/generate-service-catalog.sh\`*
EOF

    log "Service catalog generated: $OUTPUT_FILE"
    log "Services: $running_containers running, $healthy_count healthy (${health_pct}%)"
}

# Main execution
main() {
    log "Starting service catalog generation..."

    # Check dependencies
    for cmd in podman jq; do
        if ! command -v "$cmd" &> /dev/null; then
            error "Required command '$cmd' not found"
            exit 1
        fi
    done

    # Generate catalog
    generate_catalog

    log "✓ Service catalog generation complete!"
}

main "$@"
