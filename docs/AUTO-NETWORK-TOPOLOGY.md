# Network Topology (Auto-Generated)

**Generated:** 2026-01-01 13:19:40 UTC
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

    %% Services requiring Authelia SSO
    CrowdSec -->|Rate Limit| Authelia[Authelia<br/>SSO + YubiKey]
    Authelia -->|Proxy| alertmanager[alertmanager]
    Authelia -->|Proxy| grafana[grafana]
    Authelia -->|Proxy| homepage[homepage]
    Authelia -->|Proxy| loki[loki]
    Authelia -->|Proxy| prometheus[prometheus]

    %% Services with native authentication (bypass Authelia)
    CrowdSec -->|Rate Limit| collabora[collabora]
    CrowdSec -->|Rate Limit| immich_server[immich-server]
    CrowdSec -->|Rate Limit| jellyfin[jellyfin]
    CrowdSec -->|Rate Limit| nextcloud[nextcloud]
    CrowdSec -->|Rate Limit| vaultwarden[vaultwarden]

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

    subgraph auth_services["auth_services<br/>10.89.3.0/24"]
        direction LR
        auth_services_authelia[authelia]
        auth_services_redis_authelia[redis-authelia]
        auth_services_traefik[traefik]
    end

    subgraph media_services["media_services<br/>10.89.1.0/24"]
        direction LR
        media_services_jellyfin[jellyfin]
    end

    subgraph monitoring["monitoring<br/>10.89.4.0/24"]
        direction LR
        monitoring_alert_discord_relay[alert-discord-relay]
        monitoring_alertmanager[alertmanager]
        monitoring_cadvisor[cadvisor]
        monitoring_grafana[grafana]
        monitoring_immich_server[immich-server]
        monitoring_jellyfin[jellyfin]
        monitoring_loki[loki]
        monitoring_nextcloud[nextcloud]
        monitoring_nextcloud_db[nextcloud-db]
        monitoring_nextcloud_redis[nextcloud-redis]
        monitoring_node_exporter[node_exporter]
        monitoring_prometheus[prometheus]
        monitoring_promtail[promtail]
        monitoring_traefik[traefik]
    end

    subgraph nextcloud["nextcloud<br/>10.89.10.0/24"]
        direction LR
        nextcloud_collabora[collabora]
        nextcloud_nextcloud[nextcloud]
        nextcloud_nextcloud_db[nextcloud-db]
        nextcloud_nextcloud_redis[nextcloud-redis]
    end

    subgraph photos["photos<br/>10.89.5.0/24"]
        direction LR
        photos_immich_ml[immich-ml]
        photos_immich_server[immich-server]
        photos_postgresql_immich[postgresql-immich]
        photos_redis_immich[redis-immich]
    end

    subgraph reverse_proxy["reverse_proxy<br/>10.89.2.0/24"]
        direction LR
        reverse_proxy_alertmanager[alertmanager]
        reverse_proxy_authelia[authelia]
        reverse_proxy_collabora[collabora]
        reverse_proxy_crowdsec[crowdsec]
        reverse_proxy_grafana[grafana]
        reverse_proxy_homepage[homepage]
        reverse_proxy_immich_server[immich-server]
        reverse_proxy_jellyfin[jellyfin]
        reverse_proxy_loki[loki]
        reverse_proxy_nextcloud[nextcloud]
        reverse_proxy_prometheus[prometheus]
        reverse_proxy_traefik[traefik]
        reverse_proxy_vaultwarden[vaultwarden]
    end

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


### auth_services

- **Full Name:** `systemd-auth_services`
- **Subnet:** 10.89.3.0/24
- **Services:** 3

**Members:**
- authelia
- redis-authelia
- traefik


### media_services

- **Full Name:** `systemd-media_services`
- **Subnet:** 10.89.1.0/24
- **Services:** 1

**Members:**
- jellyfin


### monitoring

- **Full Name:** `systemd-monitoring`
- **Subnet:** 10.89.4.0/24
- **Services:** 14

**Members:**
- alert-discord-relay
- alertmanager
- cadvisor
- grafana
- immich-server
- jellyfin
- loki
- nextcloud
- nextcloud-db
- nextcloud-redis
- node_exporter
- prometheus
- promtail
- traefik


### nextcloud

- **Full Name:** `systemd-nextcloud`
- **Subnet:** 10.89.10.0/24
- **Services:** 4

**Members:**
- collabora
- nextcloud
- nextcloud-db
- nextcloud-redis


### photos

- **Full Name:** `systemd-photos`
- **Subnet:** 10.89.5.0/24
- **Services:** 4

**Members:**
- immich-ml
- immich-server
- postgresql-immich
- redis-immich


### reverse_proxy

- **Full Name:** `systemd-reverse_proxy`
- **Subnet:** 10.89.2.0/24
- **Services:** 13

**Members:**
- alertmanager
- authelia
- collabora
- crowdsec
- grafana
- homepage
- immich-server
- jellyfin
- loki
- nextcloud
- prometheus
- traefik
- vaultwarden


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
