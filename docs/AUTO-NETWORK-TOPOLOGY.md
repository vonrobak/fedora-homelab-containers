# Network Topology (Auto-Generated)

**Generated:** 2026-02-22 06:02:01 UTC
**System:** fedora-htpc | **Networks:** 8 | **Containers:** 27

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
    Authelia -->|Proxy| gathio[gathio]
    Authelia -->|Proxy| grafana[grafana]
    Authelia -->|Proxy| home_assistant[home-assistant]
    Authelia -->|Proxy| homepage[homepage]
    Authelia -->|Proxy| loki[loki]
    Authelia -->|Proxy| prometheus[prometheus]

    %% Services with native authentication (bypass Authelia)
    CrowdSec -->|Rate Limit| alertmanager[alertmanager]
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
- **Native auth** services handle their own authentication (bypass Authelia)

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

    subgraph gathio["gathio<br/>10.89.0.0/24"]
        direction LR
        gathio_gathio[gathio]
        gathio_gathio_db[gathio-db]
    end

    subgraph home_automation["home_automation<br/>10.89.6.0/24"]
        direction LR
        home_automation_home_assistant[home-assistant]
        home_automation_matter_server[matter-server]
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
        monitoring_gathio[gathio]
        monitoring_grafana[grafana]
        monitoring_home_assistant[home-assistant]
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
        monitoring_unpoller[unpoller]
    end

    subgraph nextcloud["nextcloud<br/>10.89.10.0/24"]
        direction LR
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
        reverse_proxy_crowdsec[crowdsec]
        reverse_proxy_gathio[gathio]
        reverse_proxy_grafana[grafana]
        reverse_proxy_home_assistant[home-assistant]
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
    class auth_services,photos,nextcloud,media_services,gathio,home_automation backendNet
```

---

## Network Membership Matrix

Shows which services belong to which networks. Dynamically generated from running container state.

| Service | auth_services | gathio | home_automation | media_services | monitoring | nextcloud | photos | reverse_proxy |
|---------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **Gateway & Security** |
| authelia | ✅ | - | - | - | - | - | - | ✅ |
| crowdsec | - | - | - | - | - | - | - | ✅ |
| redis-authelia | ✅ | - | - | - | - | - | - | - |
| traefik | ✅ | - | - | - | ✅ | - | - | ✅ |
| **Public Services** |
| gathio | - | ✅ | - | - | ✅ | - | - | ✅ |
| home-assistant | - | - | ✅ | - | ✅ | - | - | ✅ |
| homepage | - | - | - | - | - | - | - | ✅ |
| immich-server | - | - | - | - | ✅ | - | ✅ | ✅ |
| jellyfin | - | - | - | ✅ | ✅ | - | - | ✅ |
| nextcloud | - | - | - | - | ✅ | ✅ | - | ✅ |
| vaultwarden | - | - | - | - | - | - | - | ✅ |
| **Monitoring** |
| alert-discord-relay | - | - | - | - | ✅ | - | - | - |
| alertmanager | - | - | - | - | ✅ | - | - | ✅ |
| cadvisor | - | - | - | - | ✅ | - | - | - |
| grafana | - | - | - | - | ✅ | - | - | ✅ |
| loki | - | - | - | - | ✅ | - | - | ✅ |
| node_exporter | - | - | - | - | ✅ | - | - | - |
| prometheus | - | - | - | - | ✅ | - | - | ✅ |
| promtail | - | - | - | - | ✅ | - | - | - |
| unpoller | - | - | - | - | ✅ | - | - | - |
| **Backend Services** |
| gathio-db | - | ✅ | - | - | - | - | - | - |
| immich-ml | - | - | - | - | - | - | ✅ | - |
| matter-server | - | - | ✅ | - | - | - | - | - |
| nextcloud-db | - | - | - | - | ✅ | ✅ | - | - |
| nextcloud-redis | - | - | - | - | ✅ | ✅ | - | - |
| postgresql-immich | - | - | - | - | - | - | ✅ | - |
| redis-immich | - | - | - | - | - | - | ✅ | - |

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


### gathio

- **Full Name:** `systemd-gathio`
- **Subnet:** 10.89.0.0/24
- **Services:** 2

**Members:**
- gathio
- gathio-db


### home_automation

- **Full Name:** `systemd-home_automation`
- **Subnet:** 10.89.6.0/24
- **Services:** 2

**Members:**
- home-assistant
- matter-server


### media_services

- **Full Name:** `systemd-media_services`
- **Subnet:** 10.89.1.0/24
- **Services:** 1

**Members:**
- jellyfin


### monitoring

- **Full Name:** `systemd-monitoring`
- **Subnet:** 10.89.4.0/24
- **Services:** 17

**Members:**
- alert-discord-relay
- alertmanager
- cadvisor
- gathio
- grafana
- home-assistant
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
- unpoller


### nextcloud

- **Full Name:** `systemd-nextcloud`
- **Subnet:** 10.89.10.0/24
- **Services:** 3

**Members:**
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
- **Services:** 14

**Members:**
- alertmanager
- authelia
- crowdsec
- gathio
- grafana
- home-assistant
- homepage
- immich-server
- jellyfin
- loki
- nextcloud
- prometheus
- traefik
- vaultwarden


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
