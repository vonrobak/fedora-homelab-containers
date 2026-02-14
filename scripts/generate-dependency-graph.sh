#!/bin/bash
# Dependency Graph Generator
# Dynamically analyzes service dependencies from quadlet files and network membership

set -euo pipefail

OUTPUT_FILE="${HOME}/containers/docs/AUTO-DEPENDENCY-GRAPH.md"
QUADLET_DIR="${HOME}/containers/quadlets"

log() {
    echo "[$(date +'%H:%M:%S')] $*" >&2
}

# Parse hard dependencies (Requires=) from quadlet files, filtering networks/targets
get_hard_deps() {
    local service=$1
    local quadlet="${QUADLET_DIR}/${service}.container"

    [[ -f "$quadlet" ]] || return
    grep -E "^Requires=" "$quadlet" 2>/dev/null | \
        sed 's/Requires=//' | tr ' ' '\n' | \
        grep -v "network" | grep -v "target" | \
        sed 's/\.service$//; s/\.container$//' | sort -u || true
}

# Parse ordering dependencies (After=) excluding networks/targets
get_after_deps() {
    local service=$1
    local quadlet="${QUADLET_DIR}/${service}.container"

    [[ -f "$quadlet" ]] || return
    grep -E "^After=" "$quadlet" 2>/dev/null | \
        sed 's/After=//' | tr ' ' '\n' | \
        grep -v "network" | grep -v "target" | \
        sed 's/\.service$//; s/\.container$//' | sort -u || true
}

# Determine service tier
get_tier() {
    case "$1" in
        traefik|authelia|redis-authelia)                         echo "1:Critical" ;;
        prometheus|grafana|loki|alertmanager|crowdsec)           echo "2:Infrastructure" ;;
        jellyfin|immich-server|nextcloud|vaultwarden|home-assistant|homepage|gathio)
                                                                 echo "3:Applications" ;;
        nextcloud-db|nextcloud-redis|postgresql-immich|redis-immich|gathio-db)
                                                                 echo "4:Data" ;;
        *)                                                       echo "5:Supporting" ;;
    esac
}

# Get display label for Mermaid node
get_label() {
    case "$1" in
        traefik)           echo "Traefik<br/>Gateway" ;;
        authelia)          echo "Authelia<br/>SSO + MFA" ;;
        redis-authelia)    echo "Redis<br/>Auth Sessions" ;;
        crowdsec)          echo "CrowdSec<br/>Security" ;;
        prometheus)        echo "Prometheus<br/>Metrics" ;;
        grafana)           echo "Grafana<br/>Dashboards" ;;
        loki)              echo "Loki<br/>Logs" ;;
        alertmanager)      echo "Alertmanager<br/>Alerts" ;;
        jellyfin)          echo "Jellyfin<br/>Media" ;;
        immich-server)     echo "Immich<br/>Photos" ;;
        nextcloud)         echo "Nextcloud<br/>Files" ;;
        vaultwarden)       echo "Vaultwarden<br/>Passwords" ;;
        home-assistant)    echo "Home Assistant<br/>Automation" ;;
        homepage)          echo "Homepage<br/>Dashboard" ;;
        gathio)            echo "Gathio<br/>Events" ;;
        nextcloud-db)      echo "MariaDB<br/>Nextcloud DB" ;;
        nextcloud-redis)   echo "Redis<br/>Nextcloud Cache" ;;
        postgresql-immich) echo "PostgreSQL<br/>Immich DB" ;;
        redis-immich)      echo "Redis<br/>Immich Cache" ;;
        gathio-db)         echo "MongoDB<br/>Gathio DB" ;;
        *)                 echo "$1" ;;
    esac
}

# Get impact severity for a service going down
get_impact() {
    case "$1" in
        traefik)           echo "🔴 Total outage — no external access to any service" ;;
        authelia)          echo "🟡 Cannot access Authelia-protected services (monitoring, dashboard)" ;;
        redis-authelia)    echo "🟡 All SSO sessions lost, users must re-authenticate" ;;
        crowdsec)          echo "🟡 Reduced security — no IP reputation filtering" ;;
        prometheus)        echo "🟡 No metrics collection, blind operation" ;;
        grafana)           echo "🟢 Dashboards unavailable, metrics still collected" ;;
        loki)              echo "🟢 Log queries unavailable, logs still forwarded" ;;
        alertmanager)      echo "🟢 Alerts not routed, monitoring continues" ;;
        jellyfin)          echo "🟢 Media streaming unavailable" ;;
        immich-server)     echo "🟢 Photo management unavailable" ;;
        nextcloud)         echo "🟢 File sync unavailable" ;;
        vaultwarden)       echo "🟡 Password vault inaccessible (keep local cache)" ;;
        home-assistant)    echo "🟡 Automations stop, smart home degraded" ;;
        homepage)          echo "🟢 Dashboard unavailable" ;;
        gathio)            echo "🟢 Event management unavailable" ;;
        postgresql-immich) echo "🔴 Immich completely non-functional" ;;
        nextcloud-db)      echo "🔴 Nextcloud completely non-functional" ;;
        redis-immich)      echo "🟡 Immich degraded (queue processing affected)" ;;
        nextcloud-redis)   echo "🟡 Nextcloud degraded performance" ;;
        gathio-db)         echo "🔴 Gathio completely non-functional" ;;
        *)                 echo "🟢 Service-specific impact" ;;
    esac
}

generate_graph() {
    local timestamp
    timestamp=$(date -u '+%Y-%m-%d %H:%M:%S UTC')

    log "Generating dependency graph..."

    # Collect all containers and their tiers
    local all_containers
    all_containers=$(podman ps --format '{{.Names}}' | sort)

    # Build tier lists
    local -A tier_members
    for container in $all_containers; do
        local tier
        tier=$(get_tier "$container")
        local tier_key="${tier%%:*}"
        tier_members[$tier_key]="${tier_members[$tier_key]:-} $container"
    done

    # Start output
    cat > "$OUTPUT_FILE" <<EOF
# Service Dependency Graph (Auto-Generated)

**Generated:** ${timestamp}
**System:** $(hostname)

---

## Dependency Overview

Shows how services depend on each other, organized by tier. Edges are derived from quadlet \`Requires=\` and \`After=\` directives.

\`\`\`mermaid
graph TB
EOF

    # Generate tier subgraphs dynamically
    local tier_names=("Critical" "Infrastructure" "Applications" "Data" "Supporting")
    local tier_nums=(1 2 3 4 5)

    for i in "${!tier_nums[@]}"; do
        local tier_num="${tier_nums[$i]}"
        local tier_name="${tier_names[$i]}"
        local members="${tier_members[$tier_num]:-}"

        [[ -z "$members" ]] && continue

        echo "    subgraph ${tier_name}[${tier_name} — Tier ${tier_num}]" >> "$OUTPUT_FILE"

        for container in $members; do
            local node_id="${container//-/_}"
            local label
            label=$(get_label "$container")
            echo "        ${node_id}[${label}]" >> "$OUTPUT_FILE"
        done

        echo "    end" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    done

    # Generate edges from quadlet dependencies
    echo "    %% Hard dependencies (from Requires= directives)" >> "$OUTPUT_FILE"
    for container in $all_containers; do
        local node_id="${container//-/_}"
        for dep in $(get_hard_deps "$container"); do
            local dep_id="${dep//-/_}"
            # Verify the dependency is a running container
            if echo "$all_containers" | grep -qx "$dep"; then
                echo "    ${node_id} --> ${dep_id}" >> "$OUTPUT_FILE"
            fi
        done
    done

    echo "" >> "$OUTPUT_FILE"
    echo "    %% Routing dependencies (services in reverse_proxy depend on Traefik)" >> "$OUTPUT_FILE"

    # Add Traefik routing edges for services in reverse_proxy network
    local rp_members
    rp_members=$(podman network inspect systemd-reverse_proxy 2>/dev/null | \
        jq -r '.[0].containers // {} | to_entries[] | .value.name' | sort || true)

    for container in $rp_members; do
        [[ "$container" == "traefik" || "$container" == "crowdsec" ]] && continue
        local node_id="${container//-/_}"
        # Only add if not already covered by a hard dep
        if ! get_hard_deps "$container" | grep -qx "traefik"; then
            echo "    traefik -.-> ${node_id}" >> "$OUTPUT_FILE"
        fi
    done

    echo "" >> "$OUTPUT_FILE"
    echo "    %% Monitoring (Prometheus scrapes via monitoring network)" >> "$OUTPUT_FILE"

    # Add Prometheus scraping edges for key services
    local mon_members
    mon_members=$(podman network inspect systemd-monitoring 2>/dev/null | \
        jq -r '.[0].containers // {} | to_entries[] | .value.name' | sort || true)

    for container in $mon_members; do
        case "$container" in
            prometheus|promtail|cadvisor|node_exporter|alert-discord-relay|loki|alertmanager|grafana|unpoller) continue ;;
        esac
        local node_id="${container//-/_}"
        echo "    prometheus -.->|scrapes| ${node_id}" >> "$OUTPUT_FILE"
    done

    # Styling
    cat >> "$OUTPUT_FILE" <<'EOF'

    %% Styling
    style traefik fill:#f9f,stroke:#333,stroke-width:4px
    style authelia fill:#bbf,stroke:#333,stroke-width:3px
    style prometheus fill:#bfb,stroke:#333,stroke-width:2px
    style grafana fill:#bfb,stroke:#333,stroke-width:2px
```

---

## Critical Path Analysis

EOF

    # Generate tier tables dynamically
    for i in "${!tier_nums[@]}"; do
        local tier_num="${tier_nums[$i]}"
        local tier_name="${tier_names[$i]}"
        local members="${tier_members[$tier_num]:-}"

        [[ -z "$members" ]] && continue

        echo "### Tier ${tier_num}: ${tier_name}" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"

        echo "| Service | Hard Dependencies | Impact if Down |" >> "$OUTPUT_FILE"
        echo "|---------|-------------------|----------------|" >> "$OUTPUT_FILE"

        for container in $members; do
            local deps
            deps=$(get_hard_deps "$container" | tr '\n' ', ' | sed 's/,$//')
            [[ -z "$deps" ]] && deps="—"
            local impact
            impact=$(get_impact "$container")
            echo "| **${container}** | ${deps} | ${impact} |" >> "$OUTPUT_FILE"
        done

        echo "" >> "$OUTPUT_FILE"
    done

    # Startup order from After= directives
    cat >> "$OUTPUT_FILE" <<'EOF'
---

## Startup Order

Derived from `After=` directives in quadlet files. systemd handles this automatically.

EOF

    echo "| Service | Starts After |" >> "$OUTPUT_FILE"
    echo "|---------|-------------|" >> "$OUTPUT_FILE"

    for container in $all_containers; do
        local after_deps
        after_deps=$(get_after_deps "$container" | tr '\n' ', ' | sed 's/,$//')
        [[ -z "$after_deps" ]] && after_deps="(no ordering constraints)"
        echo "| ${container} | ${after_deps} |" >> "$OUTPUT_FILE"
    done

    # Network-based dependencies
    cat >> "$OUTPUT_FILE" <<'EOF'

---

## Network-Based Dependencies

Services on the same network can communicate:

EOF

    for network in $(podman network ls --format '{{.Name}}' | grep '^systemd-' | sort); do
        local network_short="${network#systemd-}"
        local members
        members=$(podman network inspect "$network" 2>/dev/null | \
            jq -r '.[0].containers // {} | to_entries[] | .value.name' | sort | tr '\n' ', ' | sed 's/,$//')

        [[ -n "$members" ]] && echo "**${network_short}:** ${members}" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    done

    # Service overrides and links
    cat >> "$OUTPUT_FILE" <<'EOF'
---

## Service Overrides

Services with restricted auto-restart in autonomous operations:

| Service | Auto-Restart | Rationale |
|---------|--------------|-----------|
| traefik | ❌ No | Gateway — manual intervention required |
| authelia | ❌ No | Authentication — manual intervention required |
| Others | ✅ Yes | Can be automatically restarted if unhealthy |

---

## Related Documentation

- [Service Catalog](AUTO-SERVICE-CATALOG.md) - What's running
- [Network Topology](AUTO-NETWORK-TOPOLOGY.md) - Network architecture
- [Homelab Architecture](20-operations/guides/homelab-architecture.md) - Full documentation
- [Autonomous Operations](20-operations/guides/autonomous-operations.md) - OODA loop
- [ADR-011: Service Dependency Mapping](10-services/decisions/2025-11-15-ADR-011-service-dependency-mapping.md) - Dependency design decisions

---

*Auto-generated by `scripts/generate-dependency-graph.sh`*
EOF

    log "✓ Dependency graph generated: $OUTPUT_FILE"
}

main() {
    log "Starting dependency graph generation..."

    if ! command -v jq &> /dev/null; then
        echo "Error: jq is required" >&2
        exit 1
    fi

    generate_graph

    log "✓ Complete!"
}

main "$@"
