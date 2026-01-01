# Network Topology (Auto-Generated)

**Generated:** 2026-01-01 11:08:03 UTC
**System:** fedora-htpc

This document provides visual representations of the homelab network architecture.

---

## Hierarchical Network Architecture

Shows the layered architecture from Internet to services. Each service appears **once** in its primary functional layer.

```mermaid
graph TB
    %% Internet Layer
    Internet[🌐 Internet<br/>Port 80/443]

    %% Gateway Layer - Entry point
    Internet -->|Port Forward| Traefik

    %% Security Middleware
    Traefik -->|1. IP Check| CrowdSec[CrowdSec<br/>IP Reputation]
    Traefik -->|2. Auth| Authelia[Authelia<br/>SSO + YubiKey]

    %% Public Services (Internet-accessible via reverse_proxy network)
    Traefik -->|Routes| Jellyfin[Jellyfin<br/>Media Server]
    Traefik -->|Routes| Immich[Immich<br/>Photo Management]
    Traefik -->|Routes| Nextcloud[Nextcloud<br/>File Sync]
    Traefik -->|Routes| Vaultwarden[Vaultwarden<br/>Passwords]
    Traefik -->|Routes| Collabora[Collabora<br/>Office Suite]
    Traefik -->|Routes| Homepage[Homepage<br/>Dashboard]

    %% Monitoring Services (reverse_proxy + monitoring networks)
    Traefik -->|Routes| Prometheus[Prometheus<br/>Metrics]
    Traefik -->|Routes| Grafana[Grafana<br/>Dashboards]
    Traefik -->|Routes| Loki[Loki<br/>Logs]
    Traefik -->|Routes| Alertmanager[Alertmanager<br/>Alerts]

    %% Backend Services (Internal only - monitoring network)
    Prometheus -.->|Scrapes| NodeExporter[Node Exporter<br/>Host Metrics]
    Prometheus -.->|Scrapes| cAdvisor[cAdvisor<br/>Container Metrics]
    Prometheus -.->|Scrapes| Promtail[Promtail<br/>Log Collection]
    Alertmanager -.->|Webhooks| DiscordRelay[Discord Relay<br/>Notifications]

    %% Support Services
    Authelia -->|Session| RedisAuth[(Redis<br/>Auth Sessions)]
    Jellyfin -.->|Media Storage| MediaLib[/Media Library<br/>BTRFS/]

    Immich -->|ML Processing| ImmichML[Immich ML<br/>Recognition]
    Immich -->|Photos| PostgresImmich[(PostgreSQL<br/>Immich DB)]
    Immich -->|Cache| RedisImmich[(Redis<br/>Immich Cache)]

    Nextcloud -->|Database| NextcloudDB[(PostgreSQL<br/>Nextcloud DB)]
    Nextcloud -->|Cache| NextcloudRedis[(Redis<br/>Nextcloud Cache)]

    %% Styling - Readable colors with good contrast
    style Traefik fill:#1a5490,stroke:#0d2a45,stroke-width:4px,color:#fff
    style CrowdSec fill:#c41e3a,stroke:#8b1528,stroke-width:2px,color:#fff
    style Authelia fill:#2d5016,stroke:#1a3010,stroke-width:2px,color:#fff

    style Jellyfin fill:#e8f4f8,stroke:#4a90a4,stroke-width:2px,color:#000
    style Immich fill:#e8f4f8,stroke:#4a90a4,stroke-width:2px,color:#000
    style Nextcloud fill:#e8f4f8,stroke:#4a90a4,stroke-width:2px,color:#000
    style Vaultwarden fill:#e8f4f8,stroke:#4a90a4,stroke-width:2px,color:#000
    style Collabora fill:#e8f4f8,stroke:#4a90a4,stroke-width:2px,color:#000
    style Homepage fill:#e8f4f8,stroke:#4a90a4,stroke-width:2px,color:#000

    style Prometheus fill:#fff4e6,stroke:#d68910,stroke-width:2px,color:#000
    style Grafana fill:#fff4e6,stroke:#d68910,stroke-width:2px,color:#000
    style Loki fill:#fff4e6,stroke:#d68910,stroke-width:2px,color:#000
    style Alertmanager fill:#fff4e6,stroke:#d68910,stroke-width:2px,color:#000

    style NodeExporter fill:#f5f5f5,stroke:#888,stroke-width:1px,color:#000
    style cAdvisor fill:#f5f5f5,stroke:#888,stroke-width:1px,color:#000
    style Promtail fill:#f5f5f5,stroke:#888,stroke-width:1px,color:#000
    style DiscordRelay fill:#f5f5f5,stroke:#888,stroke-width:1px,color:#000

    style ImmichML fill:#f0f0f0,stroke:#666,stroke-width:1px,color:#000
    style PostgresImmich fill:#d4e6f1,stroke:#5499c7,stroke-width:2px,color:#000
    style RedisImmich fill:#fadbd8,stroke:#e74c3c,stroke-width:2px,color:#000
    style NextcloudDB fill:#d4e6f1,stroke:#5499c7,stroke-width:2px,color:#000
    style NextcloudRedis fill:#fadbd8,stroke:#e74c3c,stroke-width:2px,color:#000
    style RedisAuth fill:#fadbd8,stroke:#e74c3c,stroke-width:2px,color:#000
```

**Legend:**
- 🔵 **Blue** = Gateway (Traefik)
- 🔴 **Red** = Security (CrowdSec)
- 🟢 **Green** = Authentication (Authelia)
- ⚪ **Light Blue** = Public Services
- 🟡 **Cream** = Monitoring Services
- ⚫ **Gray** = Internal Services
- 🗄️ **Databases** = Cylinder shape
- **Solid arrows** = Primary traffic flow
- **Dotted arrows** = Backend/scraping connections

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
   - Nextcloud application with PostgreSQL, Redis, and Collabora
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
