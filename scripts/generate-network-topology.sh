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

# Get all networks a container belongs to
get_container_networks() {
    local container=$1
    podman inspect "$container" 2>/dev/null | \
        jq -r '.[0].NetworkSettings.Networks // {} | keys[]' | \
        sed 's/systemd-//' | sort | tr '\n' ',' | sed 's/,$//'
}

# Get all running containers
get_all_containers() {
    podman ps --format '{{.Names}}' | sort
}

# Check if service uses Authelia middleware (parse routers.yml)
uses_authelia() {
    local service=$1
    local routers_file="${HOME}/containers/config/traefik/dynamic/routers.yml"

    if [[ ! -f "$routers_file" ]]; then
        return 1
    fi

    # Strategy: Extract router blocks that have "service: \"$service\""
    # Then check if that block contains "authelia@file"
    # Router blocks start with 4-space indent + name + colon (e.g., "    router-name:")
    # and continue until the next router or section

    awk -v service="$service" '
        # Start of a new router (4 spaces + word + colon, not a list item)
        /^    [a-z][a-z0-9_-]*:$/ {
            # Process previous router if it matched
            if (found_service && found_authelia) {
                exit 0
            }
            # Reset for new router
            found_service = 0
            found_authelia = 0
            in_router = 1
            next
        }

        # Check if this line has our service
        in_router && $0 ~ "service: \"" service "\"" {
            found_service = 1
        }

        # Check if this line has authelia middleware
        in_router && /authelia@file/ {
            found_authelia = 1
        }

        # End of routers section or file
        /^  [a-z]+:/ && !/^    / {
            if (found_service && found_authelia) {
                exit 0
            }
            in_router = 0
        }

        END {
            if (found_service && found_authelia) {
                exit 0
            }
            exit 1
        }
    ' "$routers_file" && return 0

    return 1
}

# Determine if container is internet-accessible (in reverse_proxy network)
is_public_service() {
    local container=$1
    get_container_networks "$container" | grep -q "reverse_proxy"
}

# Get primary network for a container (first network = default route)
get_primary_network() {
    local container=$1
    podman inspect "$container" 2>/dev/null | \
        jq -r '.[0].NetworkSettings.Networks // {} | keys[0]' | \
        sed 's/systemd-//'
}

# Generate the topology document
generate_topology() {
    local timestamp=$(date -u '+%Y-%m-%d %H:%M:%S UTC')

    log "Generating network topology..."

    cat > "$OUTPUT_FILE" <<'EOF'
# Network Topology (Auto-Generated)

**Generated:** TIMESTAMP
**System:** fedora-htpc

This document provides comprehensive visualizations of the homelab network architecture, combining traffic flow analysis with network-centric topology views.

---

## 1. Traffic Flow & Middleware Routing

Shows how requests flow from Internet through Traefik with middleware routing based on actual configuration in `config/traefik/dynamic/routers.yml`.

```mermaid
graph TB
    Internet[🌐 Internet<br/>Port 80/443]
    Internet -->|Port Forward| Traefik[Traefik<br/>Reverse Proxy]

    %% All traffic goes through CrowdSec first
    Traefik -->|All Traffic| CrowdSec[CrowdSec<br/>IP Reputation]

EOF

    # Parse routers.yml to determine routing (data-driven)
    log "Parsing routing configuration..."

    # Services with Authelia
    cat >> "$OUTPUT_FILE" <<'EOF'
    %% Services requiring Authelia SSO
    CrowdSec -->|Rate Limit| Authelia[Authelia<br/>SSO + YubiKey]
EOF

    local authelia_services=""
    local native_auth_services=""

    for container in $(get_network_members "systemd-reverse_proxy"); do
        if uses_authelia "$container"; then
            authelia_services="$authelia_services $container"
        elif [[ "$container" != "traefik" && "$container" != "crowdsec" && "$container" != "authelia" ]]; then
            native_auth_services="$native_auth_services $container"
        fi
    done

    # Add Authelia-protected services
    for service in $authelia_services; do
        local node_name=$(echo "$service" | sed 's/-/_/g')
        echo "    Authelia -->|Proxy| ${node_name}[${service}]" >> "$OUTPUT_FILE"
    done

    # Add services with native auth (bypass Authelia)
    cat >> "$OUTPUT_FILE" <<EOF

    %% Services with native authentication (bypass Authelia)
EOF

    for service in $native_auth_services; do
        local node_name=$(echo "$service" | sed 's/-/_/g')
        echo "    CrowdSec -->|Rate Limit| ${node_name}[${service}]" >> "$OUTPUT_FILE"
    done

    # Styling
    cat >> "$OUTPUT_FILE" <<'EOF'

    %% Styling
    style Traefik fill:#1a5490,stroke:#0d2a45,stroke-width:4px,color:#fff
    style CrowdSec fill:#c41e3a,stroke:#8b1528,stroke-width:2px,color:#fff
    style Authelia fill:#2d5016,stroke:#1a3010,stroke-width:2px,color:#fff
```

**Key Insights:**
- **CrowdSec** checks ALL traffic (fail-fast: reject banned IPs immediately)
- **Authelia** protects administrative/monitoring services (SSO with YubiKey)
- **Native auth** services handle their own authentication (Jellyfin, Immich, Nextcloud, Vaultwarden)

---

## 2. Network Topology

Shows actual Podman network membership. Services appear in EVERY network they belong to (accuracy over brevity).

```mermaid
graph TB
EOF

    # Build accurate network topology - services appear in ALL networks they're in
    log "Building network topology..."

    # Process each network and show ALL its members
    for network in $(get_networks); do
        local network_short=$(echo "$network" | sed 's/systemd-//')
        local subnet=$(get_network_subnet "$network")

        cat >> "$OUTPUT_FILE" <<EOF

    subgraph ${network_short}["${network_short}<br/>${subnet}"]
        direction LR
EOF

        # Add ALL services in this network
        for container in $(get_network_members "$network"); do
            local node_name=$(echo "$container" | sed 's/-/_/g')
            # Unique node ID per network to avoid conflicts
            echo "        ${network_short}_${node_name}[${container}]" >> "$OUTPUT_FILE"
        done

        echo "    end" >> "$OUTPUT_FILE"
    done

    # Network styling based on function
    cat >> "$OUTPUT_FILE" <<'EOF'

    %% Network styling
    classDef gatewayNet fill:#e6f3ff,stroke:#1a5490,stroke-width:3px
    classDef observeNet fill:#fff9e6,stroke:#d68910,stroke-width:3px
    classDef backendNet fill:#f0f0f0,stroke:#666,stroke-width:2px

    class reverse_proxy gatewayNet
    class monitoring observeNet
    class auth_services,photos,nextcloud,media_services backendNet
```

**Network Functions:**
- **reverse_proxy** (10.89.2.0/24) - Gateway for Internet-accessible services
- **monitoring** (10.89.4.0/24) - Observability network (scrapes metrics from all services)
- **auth_services** (10.89.3.0/24) - Authentication and session management
- **photos** (10.89.5.0/24) - Immich stack isolation
- **nextcloud** (10.89.10.0/24) - Nextcloud stack isolation
- **media_services** (10.89.1.0/24) - Jellyfin media processing

**Note:** Services appear in multiple network boxes if they belong to multiple networks. This accurately represents Podman network membership.

---

## Network Membership Matrix

Shows which services belong to which networks. Many services are members of multiple networks.

| Service | reverse_proxy | monitoring | auth_services | photos | nextcloud | media_services |
|---------|:-------------:|:----------:|:-------------:|:------:|:---------:|:--------------:|
| **Gateway & Security** |
| traefik | ✅ | ✅ | ✅ | - | - | - |
| crowdsec | ✅ | - | - | - | - | - |
| authelia | ✅ | - | ✅ | - | - | - |
| redis-authelia | - | - | ✅ | - | - | - |
| **Public Services** |
| jellyfin | ✅ | ✅ | - | - | - | ✅ |
| immich-server | ✅ | ✅ | - | ✅ | - | - |
| nextcloud | ✅ | ✅ | - | - | ✅ | - |
| vaultwarden | ✅ | - | - | - | - | - |
| collabora | ✅ | - | - | - | ✅ | - |
| homepage | ✅ | - | - | - | - | - |
| **Monitoring** |
| prometheus | ✅ | ✅ | - | - | - | - |
| grafana | ✅ | ✅ | - | - | - | - |
| loki | ✅ | ✅ | - | - | - | - |
| alertmanager | ✅ | ✅ | - | - | - | - |
| node_exporter | - | ✅ | - | - | - | - |
| cadvisor | - | ✅ | - | - | - | - |
| promtail | - | ✅ | - | - | - | - |
| alert-discord-relay | - | ✅ | - | - | - | - |
| **Backend Services** |
| postgresql-immich | - | - | - | ✅ | - | - |
| redis-immich | - | - | - | ✅ | - | - |
| immich-ml | - | - | - | ✅ | - | - |
| nextcloud-db | - | ✅ | - | - | ✅ | - |
| nextcloud-redis | - | ✅ | - | - | ✅ | - |

**Key Insights:**
- **Traefik** is in 3 networks (gateway, monitoring, auth) to route traffic and be monitored
- **Internet-facing services** are all in `reverse_proxy` (primary) + their functional network
- **Monitoring network** has the most members (14 services) - observability across all tiers
- **Backend databases/caches** are isolated to their functional networks only

---

## Request Flow

Shows the path of an authenticated request through the middleware layers.

```mermaid
sequenceDiagram
    participant User
    participant Traefik
    participant CrowdSec
    participant Authelia
    participant Service

    User->>Traefik: HTTPS Request<br/>jellyfin.patriark.org

    Note over Traefik: Layer 1: IP Reputation
    Traefik->>CrowdSec: Check IP reputation
    CrowdSec-->>Traefik: ✓ IP not banned

    Note over Traefik: Layer 2: Rate Limiting
    Traefik->>Traefik: Check rate limit<br/>(100-200 req/min)

    Note over Traefik: Layer 3: Authentication
    Traefik->>Authelia: Verify session

    alt No valid session
        Authelia-->>User: 302 Redirect to sso.patriark.org
        User->>Authelia: Login (YubiKey + TOTP)
        Authelia-->>User: Set session cookie
        User->>Traefik: Retry with session
    end

    Authelia-->>Traefik: ✓ Valid session

    Note over Traefik: Layer 4: Security Headers
    Traefik->>Service: Forward request<br/>+ HSTS, CSP, etc.
    Service-->>User: Response
```

**Middleware Ordering (fail-fast principle):**
1. **CrowdSec** - Fastest (cache lookup) - reject banned IPs immediately
2. **Rate Limiting** - Fast (counter check) - prevent DoS
3. **Authelia** - Expensive (session validation + SSO) - only for legitimate traffic
4. **Security Headers** - Applied on response

---

## Network Details

EOF

    # Add network details section with dynamic data
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

### Network Segmentation Strategy

Services are organized into isolated networks based on function and trust level:

1. **reverse_proxy** (10.89.2.0/24) - **Gateway Network**
   - Contains Traefik and all internet-accessible services
   - **Critical:** First network in quadlets (gets default route for internet access)
   - 13 members including all public-facing services

2. **monitoring** (10.89.4.0/24) - **Observability Network**
   - Prometheus, Grafana, Loki, exporters, and relay services
   - Scrapes metrics from services across all other networks
   - 14 members (most connected network)

3. **auth_services** (10.89.3.0/24) - **Authentication Network**
   - Authelia SSO, Redis session storage, and Traefik
   - Isolated from direct internet except through reverse proxy
   - 3 members (tightly controlled)

4. **photos** (10.89.5.0/24) - **Photo Management Network**
   - Immich application stack with PostgreSQL, Redis, and ML
   - Backend services isolated from internet
   - 4 members

5. **nextcloud** (10.89.10.0/24) - **File Sync Network**
   - Nextcloud application with MariaDB, Redis, and Collabora
   - Backend databases accessible only within this network
   - 4 members

6. **media_services** (10.89.1.0/24) - **Media Processing Network**
   - Jellyfin and media-related services
   - 1 member (Jellyfin also in reverse_proxy and monitoring)

### Multi-Network Services

**Why multiple networks?**
- **reverse_proxy** = Internet accessibility
- **monitoring** = Metrics scraping
- **Functional network** = Backend communication (databases, caches)

**Examples:**
- **Traefik (3 networks):** reverse_proxy (gateway), auth_services (Authelia access), monitoring (metrics)
- **Jellyfin (3 networks):** reverse_proxy (internet), monitoring (metrics), media_services (function)
- **Immich (3 networks):** reverse_proxy (internet), monitoring (metrics), photos (backend DB/cache)
- **Nextcloud (3 networks):** reverse_proxy (internet), monitoring (metrics), nextcloud (backend DB/cache)

### Network Ordering in Quadlets

**Critical:** First `Network=` line in quadlet gets the default route (internet access).

```ini
# ✅ Correct - can reach internet AND internal services
Network=systemd-reverse_proxy.network
Network=systemd-monitoring.network
Network=systemd-photos.network

# ❌ Wrong - cannot reach internet (monitoring is internal-only)
Network=systemd-monitoring.network
Network=systemd-reverse_proxy.network
```

**Rule of thumb:**
- Internet-facing services: `reverse_proxy` first
- Internal services: Functional network first (photos, nextcloud, etc.)
- Monitoring-only: `monitoring` network only (no internet needed)

### Service Discovery (Podman DNS)

Services on the same network can communicate using container names as hostnames:
- `http://authelia:9091` - Traefik reaches Authelia (both in auth_services)
- `http://redis-authelia:6379` - Authelia reaches Redis (both in auth_services)
- `http://postgresql-immich:5432` - Immich reaches database (both in photos)
- `http://prometheus:9090` - Grafana reaches Prometheus (both in monitoring)

---

## Quick Links

- [Service Catalog](AUTO-SERVICE-CATALOG.md) - Complete service inventory
- [Dependency Graph](AUTO-DEPENDENCY-GRAPH.md) - Service dependencies
- [Homelab Architecture](20-operations/guides/homelab-architecture.md) - Full documentation

---

*Auto-generated by `scripts/generate-network-topology.sh`*
*GitHub renders Mermaid diagrams automatically - view this file on GitHub for best experience*
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
