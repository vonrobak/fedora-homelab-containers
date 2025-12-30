#!/bin/bash
# Network Topology Generator
# Generates Mermaid diagrams showing network architecture

set -euo pipefail

OUTPUT_FILE="${HOME}/containers/docs/AUTO-NETWORK-TOPOLOGY.md"

log() {
    echo "[$(date +'%H:%M:%S')] $*" >&2
}

# Get network information
get_networks() {
    podman network ls --format '{{.Name}}' | grep '^systemd-' || true
}

# Get containers on a network
get_network_members() {
    local network=$1
    podman network inspect "$network" 2>/dev/null | \
        jq -r '.[0].containers // {} | to_entries[] | .value.name' | sort || true
}

# Get network subnet
get_network_subnet() {
    local network=$1
    podman network inspect "$network" 2>/dev/null | \
        jq -r '.[0].subnets[0].subnet // "unknown"' || echo "unknown"
}

# Generate the topology document
generate_topology() {
    local timestamp=$(date -u '+%Y-%m-%d %H:%M:%S UTC')

    log "Generating network topology..."

    cat > "$OUTPUT_FILE" <<'EOF'
# Network Topology (Auto-Generated)

**Generated:** TIMESTAMP
**System:** fedora-htpc

This document provides visual representations of the homelab network architecture using Mermaid diagrams.

---

## Network Overview

Shows all Podman networks and their member services.

```mermaid
graph TB
    subgraph Internet
        User[User/Browser]
        WAN[Internet<br/>Port 80/443]
    end

    WAN -->|Port Forward| Traefik

EOF

    # Add network subgraphs
    for network in $(get_networks); do
        local network_short=$(echo "$network" | sed 's/systemd-//')
        local subnet=$(get_network_subnet "$network")

        cat >> "$OUTPUT_FILE" <<EOF

    subgraph ${network_short}[${network_short} Network<br/>${subnet}]
EOF

        # Add services in this network
        for container in $(get_network_members "$network"); do
            # Create node-safe name (replace hyphens)
            local node_name=$(echo "$container" | sed 's/-/_/g')
            echo "        ${node_name}[${container}]" >> "$OUTPUT_FILE"
        done

        echo "    end" >> "$OUTPUT_FILE"
    done

    # Add basic connections
    cat >> "$OUTPUT_FILE" <<'EOF'

    Traefik -->|Routes to| jellyfin
    Traefik -->|Routes to| immich_server
    Traefik -->|Routes to| nextcloud
    Traefik -->|Routes to| vaultwarden
    Traefik -->|Routes to| grafana
    Traefik -->|Routes to| prometheus
    Traefik -->|Auth check| authelia
    authelia -->|Session storage| redis_authelia
    Traefik -->|Security check| crowdsec

    style Traefik fill:#f9f,stroke:#333,stroke-width:4px
    style authelia fill:#bbf,stroke:#333,stroke-width:2px
    style crowdsec fill:#fbb,stroke:#333,stroke-width:2px
```

---

## Request Flow

Shows the path of an authenticated request through the system.

```mermaid
sequenceDiagram
    participant User
    participant Traefik
    participant CrowdSec
    participant Authelia
    participant Service

    User->>Traefik: HTTPS Request<br/>jellyfin.patriark.org

    Note over Traefik: Layer 1: Security
    Traefik->>CrowdSec: Check IP reputation
    CrowdSec-->>Traefik: ✓ IP not banned

    Note over Traefik: Layer 2: Rate Limiting
    Traefik->>Traefik: Check rate limit<br/>(200 req/min)

    Note over Traefik: Layer 3: Authentication
    Traefik->>Authelia: Verify session

    alt No valid session
        Authelia-->>User: 302 Redirect to sso.patriark.org
        User->>Authelia: Login (YubiKey + TOTP)
        Authelia-->>User: Set session cookie
        User->>Traefik: Retry with session
    end

    Authelia-->>Traefik: ✓ Valid session

    Note over Traefik: Layer 4: Headers & Proxy
    Traefik->>Service: Forward request<br/>+ security headers
    Service-->>User: Response
```

---

## Network Details

EOF

    # Add network details section
    for network in $(get_networks); do
        local network_short=$(echo "$network" | sed 's/systemd-//')
        local subnet=$(get_network_subnet "$network")
        local member_count=$(get_network_members "$network" | wc -l)

        cat >> "$OUTPUT_FILE" <<EOF

### ${network_short}

- **Full Name:** \`${network}\`
- **Subnet:** ${subnet}
- **Services:** ${member_count}

**Members:**
EOF

        for container in $(get_network_members "$network"); do
            echo "- ${container}" >> "$OUTPUT_FILE"
        done

        echo "" >> "$OUTPUT_FILE"
    done

    # Add architecture principles
    cat >> "$OUTPUT_FILE" <<'EOF'

---

## Architecture Principles

### Network Segmentation

Services are organized into isolated networks based on function and trust level:

1. **reverse_proxy** - Gateway network
   - Contains Traefik and all internet-accessible services
   - First network in quadlets (gets default route for internet access)

2. **auth_services** - Authentication network
   - Authelia SSO and Redis session storage
   - Isolated from direct internet access

3. **monitoring** - Observability network
   - Prometheus, Grafana, Loki, exporters
   - Scrapes metrics from all services

4. **media_services** - Media processing
   - Jellyfin and related media services

5. **photos** - Photo management
   - Immich and its supporting services (PostgreSQL, Redis, ML)

### Network Ordering

**Critical:** First network in quadlet `Network=` lines gets the default route.

```ini
# Correct - can reach internet
Network=systemd-reverse_proxy.network
Network=systemd-monitoring.network

# Wrong - cannot reach internet
Network=systemd-monitoring.network
Network=systemd-reverse_proxy.network
```

### Service Discovery

Services on the same network can communicate using container names as hostnames (Podman DNS):
- `http://authelia:9091` - Traefik can reach Authelia
- `http://redis-authelia:6379` - Authelia can reach Redis

---

## Quick Links

- [Service Catalog](AUTO-SERVICE-CATALOG.md) - What's running
- [Dependency Graph](AUTO-DEPENDENCY-GRAPH.md) - Service relationships (when generated)
- [Homelab Architecture](20-operations/guides/homelab-architecture.md) - Full documentation

---

*Auto-generated by `scripts/generate-network-topology.sh`*
*GitHub renders Mermaid diagrams automatically*
EOF

    # Replace timestamp
    sed -i "s/TIMESTAMP/$timestamp/" "$OUTPUT_FILE"

    log "✓ Network topology generated: $OUTPUT_FILE"
}

# Main
main() {
    log "Starting network topology generation..."

    if ! command -v jq &> /dev/null; then
        echo "Error: jq is required" >&2
        exit 1
    fi

    generate_topology

    log "✓ Complete!"
}

main "$@"
