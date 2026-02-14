#!/bin/bash
# Network Topology Generator
# Generates Mermaid diagrams showing network architecture
# All sections are dynamically generated from live Podman state

set -euo pipefail

OUTPUT_FILE="${HOME}/containers/docs/AUTO-NETWORK-TOPOLOGY.md"
ROUTERS_FILE="${HOME}/containers/config/traefik/dynamic/routers.yml"

log() {
    echo "[$(date +'%H:%M:%S')] $*" >&2
}

# Get network information
get_networks() {
    podman network ls --format '{{.Name}}' | grep '^systemd-' | sort || true
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

# Check if service uses Authelia middleware (parse routers.yml)
uses_authelia() {
    local service=$1

    [[ ! -f "$ROUTERS_FILE" ]] && return 1

    awk -v service="$service" '
        /^    [a-z][a-z0-9_-]*:$/ {
            if (found_service && found_authelia) exit 0
            found_service = 0; found_authelia = 0; in_router = 1; next
        }
        in_router && $0 ~ "service: \"" service "\"" { found_service = 1 }
        in_router && /authelia@file/ { found_authelia = 1 }
        /^  [a-z]+:/ && !/^    / {
            if (found_service && found_authelia) exit 0
            in_router = 0
        }
        END { if (found_service && found_authelia) exit 0; exit 1 }
    ' "$ROUTERS_FILE" && return 0

    return 1
}

# Determine service role for matrix grouping
get_role() {
    local container=$1
    local networks
    networks=$(get_container_networks "$container")

    case "$container" in
        traefik|crowdsec|authelia|redis-authelia) echo "1-Gateway & Security" ;;
        *)
            if echo "$networks" | grep -q "reverse_proxy"; then
                # Check if it's a monitoring service
                case "$container" in
                    prometheus|grafana|loki|alertmanager) echo "3-Monitoring" ;;
                    *) echo "2-Public Services" ;;
                esac
            else
                case "$container" in
                    prometheus|grafana|loki|alertmanager|node_exporter|cadvisor|promtail|unpoller|alert-discord-relay)
                        echo "3-Monitoring" ;;
                    *) echo "4-Backend Services" ;;
                esac
            fi
            ;;
    esac
}

generate_topology() {
    local timestamp
    timestamp=$(date -u '+%Y-%m-%d %H:%M:%S UTC')

    log "Generating network topology..."

    # Collect all network names (short form) for the matrix header
    local network_names=()
    for network in $(get_networks); do
        network_names+=("$(echo "$network" | sed 's/systemd-//')")
    done

    # Collect all containers and their network memberships
    local all_containers
    all_containers=$(podman ps --format '{{.Names}}' | sort)

    # Start writing output
    cat > "$OUTPUT_FILE" <<EOF
# Network Topology (Auto-Generated)

**Generated:** ${timestamp}
**System:** $(hostname) | **Networks:** ${#network_names[@]} | **Containers:** $(echo "$all_containers" | wc -l)

---

## 1. Traffic Flow & Middleware Routing

Shows how requests flow from Internet through Traefik with middleware routing based on actual configuration in \`config/traefik/dynamic/routers.yml\`.

\`\`\`mermaid
graph TB
    Internet[🌐 Internet<br/>Port 80/443]
    Internet -->|Port Forward| Traefik[Traefik<br/>Reverse Proxy]

    %% All traffic goes through CrowdSec first
    Traefik -->|All Traffic| CrowdSec[CrowdSec<br/>IP Reputation]

    %% Services requiring Authelia SSO
    CrowdSec -->|Rate Limit| Authelia[Authelia<br/>SSO + YubiKey]
EOF

    # Dynamically determine which services use Authelia vs native auth
    local authelia_services=""
    local native_auth_services=""

    for container in $(get_network_members "systemd-reverse_proxy"); do
        if uses_authelia "$container"; then
            authelia_services="$authelia_services $container"
        elif [[ "$container" != "traefik" && "$container" != "crowdsec" && "$container" != "authelia" ]]; then
            native_auth_services="$native_auth_services $container"
        fi
    done

    for service in $authelia_services; do
        local node_name="${service//-/_}"
        echo "    Authelia -->|Proxy| ${node_name}[${service}]" >> "$OUTPUT_FILE"
    done

    cat >> "$OUTPUT_FILE" <<EOF

    %% Services with native authentication (bypass Authelia)
EOF

    for service in $native_auth_services; do
        local node_name="${service//-/_}"
        echo "    CrowdSec -->|Rate Limit| ${node_name}[${service}]" >> "$OUTPUT_FILE"
    done

    cat >> "$OUTPUT_FILE" <<'EOF'

    %% Styling
    style Traefik fill:#1a5490,stroke:#0d2a45,stroke-width:4px,color:#fff
    style CrowdSec fill:#c41e3a,stroke:#8b1528,stroke-width:2px,color:#fff
    style Authelia fill:#2d5016,stroke:#1a3010,stroke-width:2px,color:#fff
```

**Key Insights:**
- **CrowdSec** checks ALL traffic (fail-fast: reject banned IPs immediately)
- **Authelia** protects administrative/monitoring services (SSO with YubiKey)
- **Native auth** services handle their own authentication (bypass Authelia)

---

## 2. Network Topology

Shows actual Podman network membership. Services appear in EVERY network they belong to (accuracy over brevity).

```mermaid
graph TB
EOF

    # Build dynamic network topology diagram
    log "Building network topology..."

    for network in $(get_networks); do
        local network_short="${network#systemd-}"
        local subnet
        subnet=$(get_network_subnet "$network")

        cat >> "$OUTPUT_FILE" <<EOF

    subgraph ${network_short}["${network_short}<br/>${subnet}"]
        direction LR
EOF

        for container in $(get_network_members "$network"); do
            local node_name="${container//-/_}"
            echo "        ${network_short}_${node_name}[${container}]" >> "$OUTPUT_FILE"
        done

        echo "    end" >> "$OUTPUT_FILE"
    done

    # Styling based on network function
    cat >> "$OUTPUT_FILE" <<'EOF'

    %% Network styling
    classDef gatewayNet fill:#e6f3ff,stroke:#1a5490,stroke-width:3px
    classDef observeNet fill:#fff9e6,stroke:#d68910,stroke-width:3px
    classDef backendNet fill:#f0f0f0,stroke:#666,stroke-width:2px

    class reverse_proxy gatewayNet
    class monitoring observeNet
    class auth_services,photos,nextcloud,media_services,gathio,home_automation backendNet
```

---

## Network Membership Matrix

Shows which services belong to which networks. Dynamically generated from running container state.

EOF

    # Build dynamic matrix header
    printf "| Service |" >> "$OUTPUT_FILE"
    for net in "${network_names[@]}"; do
        printf " %s |" "$net" >> "$OUTPUT_FILE"
    done
    echo "" >> "$OUTPUT_FILE"

    printf "|---------|" >> "$OUTPUT_FILE"
    for _ in "${network_names[@]}"; do
        printf ":---:|" >> "$OUTPUT_FILE"
    done
    echo "" >> "$OUTPUT_FILE"

    # Group containers by role, then output matrix rows
    local tmpfile
    tmpfile=$(mktemp)
    trap 'rm -f "$tmpfile"' EXIT

    for container in $all_containers; do
        local role
        role=$(get_role "$container")
        local nets
        nets=$(get_container_networks "$container")
        echo "${role}|${container}|${nets}" >> "$tmpfile"
    done

    local current_role=""
    sort "$tmpfile" | while IFS='|' read -r role container nets; do
        local role_name="${role#*-}"
        if [[ "$role_name" != "$current_role" ]]; then
            echo "| **${role_name}** |" >> "$OUTPUT_FILE"
            current_role="$role_name"
        fi

        printf "| %s |" "$container" >> "$OUTPUT_FILE"
        for net in "${network_names[@]}"; do
            if echo ",$nets," | grep -q ",${net},"; then
                printf " ✅ |" >> "$OUTPUT_FILE"
            else
                printf " - |" >> "$OUTPUT_FILE"
            fi
        done
        echo "" >> "$OUTPUT_FILE"
    done

    rm -f "$tmpfile"
    trap - EXIT

    # Request flow diagram (static but accurate)
    cat >> "$OUTPUT_FILE" <<'EOF'

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

    # Dynamic network details
    for network in $(get_networks); do
        local network_short="${network#systemd-}"
        local subnet
        subnet=$(get_network_subnet "$network")
        local members
        members=$(get_network_members "$network")
        local member_count
        member_count=$(echo "$members" | wc -l)

        cat >> "$OUTPUT_FILE" <<EOF

### ${network_short}

- **Full Name:** \`${network}\`
- **Subnet:** ${subnet}
- **Services:** ${member_count}

**Members:**
EOF

        for container in $members; do
            echo "- ${container}" >> "$OUTPUT_FILE"
        done

        echo "" >> "$OUTPUT_FILE"
    done

    # Links to related documentation (not duplicating content)
    cat >> "$OUTPUT_FILE" <<'EOF'

---

## Related Documentation

For architecture principles, network ordering rules, and troubleshooting:

- [CLAUDE.md](../CLAUDE.md) - Network ordering, gotchas, and deployment patterns
- [Homelab Architecture](20-operations/guides/homelab-architecture.md) - Full architecture overview
- [ADR-018: Static IP Multi-Network Services](00-foundation/decisions/2026-02-04-ADR-018-static-ip-multi-network-services.md) - Static IPs and Traefik /etc/hosts override
- [Service Catalog](AUTO-SERVICE-CATALOG.md) - Complete service inventory
- [Dependency Graph](AUTO-DEPENDENCY-GRAPH.md) - Service dependencies

---

*Auto-generated by `scripts/generate-network-topology.sh`*
*GitHub renders Mermaid diagrams automatically - view this file on GitHub for best experience*
EOF

    log "✓ Network topology generated: $OUTPUT_FILE"
}

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
