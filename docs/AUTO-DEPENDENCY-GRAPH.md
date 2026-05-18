# Service Dependency Graph (Auto-Generated)

**Generated:** 2026-05-18 05:02:05 UTC
**System:** fedora-htpc

---

## Dependency Overview

Shows how services depend on each other, organized by tier. Edges are derived from quadlet `Requires=` and `After=` directives.

```mermaid
graph TB
    subgraph Critical[Critical — Tier 1]
        authelia[Authelia<br/>SSO + MFA]
        redis_authelia[Redis<br/>Auth Sessions]
        traefik[Traefik<br/>Gateway]
    end

    subgraph Infrastructure[Infrastructure — Tier 2]
        alertmanager[Alertmanager<br/>Alerts]
        crowdsec[CrowdSec<br/>Security]
        grafana[Grafana<br/>Dashboards]
        loki[Loki<br/>Logs]
        prometheus[Prometheus<br/>Metrics]
    end

    subgraph Applications[Applications — Tier 3]
        gathio[Gathio<br/>Events]
        home_assistant[Home Assistant<br/>Automation]
        homepage[Homepage<br/>Dashboard]
        immich_server[Immich<br/>Photos]
        jellyfin[Jellyfin<br/>Media]
        nextcloud[Nextcloud<br/>Files]
        vaultwarden[Vaultwarden<br/>Passwords]
    end

    subgraph Data[Data — Tier 4]
        gathio_db[MongoDB<br/>Gathio DB]
        nextcloud_db[MariaDB<br/>Nextcloud DB]
        nextcloud_redis[Redis<br/>Nextcloud Cache]
        postgresql_immich[PostgreSQL<br/>Immich DB]
        redis_immich[Redis<br/>Immich Cache]
    end

    subgraph Supporting[Supporting — Tier 5]
        alert_discord_relay[alert-discord-relay]
        audiobookshelf[audiobookshelf]
        cadvisor[cadvisor]
        immich_ml[immich-ml]
        matter_server[matter-server]
        navidrome[navidrome]
        node_exporter[node_exporter]
        postgres_exporter[postgres-exporter]
        promtail[promtail]
        proton_bridge[proton-bridge]
        qbittorrent[qbittorrent]
        redis_authelia_exporter[redis-authelia-exporter]
        redis_immich_exporter[redis-immich-exporter]
        unifi_syslog[unifi-syslog]
        unpoller[unpoller]
    end

    %% Hard dependencies (from Requires= directives)
    authelia --> redis_authelia
    gathio --> gathio_db
    immich_server --> postgresql_immich
    immich_server --> redis_immich
    postgres_exporter --> postgresql_immich
    redis_authelia_exporter --> redis_authelia
    redis_immich_exporter --> redis_immich

    %% Routing dependencies (services in reverse_proxy depend on Traefik)
    traefik -.-> alert_discord_relay
    traefik -.-> alertmanager
    traefik -.-> audiobookshelf
    traefik -.-> authelia
    traefik -.-> gathio
    traefik -.-> grafana
    traefik -.-> home_assistant
    traefik -.-> homepage
    traefik -.-> immich_server
    traefik -.-> jellyfin
    traefik -.-> loki
    traefik -.-> navidrome
    traefik -.-> nextcloud
    traefik -.-> prometheus
    traefik -.-> proton_bridge
    traefik -.-> qbittorrent
    traefik -.-> unpoller
    traefik -.-> vaultwarden

    %% Monitoring (Prometheus scrapes via monitoring network)
    prometheus -.->|scrapes| postgres_exporter
    prometheus -.->|scrapes| redis_authelia_exporter
    prometheus -.->|scrapes| redis_immich_exporter

    %% Styling
    style traefik fill:#f9f,stroke:#333,stroke-width:4px
    style authelia fill:#bbf,stroke:#333,stroke-width:3px
    style prometheus fill:#bfb,stroke:#333,stroke-width:2px
    style grafana fill:#bfb,stroke:#333,stroke-width:2px
```

---

## Critical Path Analysis

### Tier 1: Critical

| Service | Hard Dependencies | Impact if Down |
|---------|-------------------|----------------|
| **authelia** | redis-authelia | 🟡 Cannot access Authelia-protected services (monitoring, dashboard) |
| **redis-authelia** | — | 🟡 All SSO sessions lost, users must re-authenticate |
| **traefik** | http.socket,https.socket | 🔴 Total outage — no external access to any service |

### Tier 2: Infrastructure

| Service | Hard Dependencies | Impact if Down |
|---------|-------------------|----------------|
| **alertmanager** | — | 🟢 Alerts not routed, monitoring continues |
| **crowdsec** | — | 🟡 Reduced security — no IP reputation filtering |
| **grafana** | — | 🟢 Dashboards unavailable, metrics still collected |
| **loki** | — | 🟢 Log queries unavailable, logs still forwarded |
| **prometheus** | — | 🟡 No metrics collection, blind operation |

### Tier 3: Applications

| Service | Hard Dependencies | Impact if Down |
|---------|-------------------|----------------|
| **gathio** | gathio-db | 🟢 Event management unavailable |
| **home-assistant** | — | 🟡 Automations stop, smart home degraded |
| **homepage** | — | 🟢 Dashboard unavailable |
| **immich-server** | postgresql-immich,redis-immich | 🟢 Photo management unavailable |
| **jellyfin** | — | 🟢 Media streaming unavailable |
| **nextcloud** | — | 🟢 File sync unavailable |
| **vaultwarden** | — | 🟡 Password vault inaccessible (keep local cache) |

### Tier 4: Data

| Service | Hard Dependencies | Impact if Down |
|---------|-------------------|----------------|
| **gathio-db** | — | 🔴 Gathio completely non-functional |
| **nextcloud-db** | — | 🔴 Nextcloud completely non-functional |
| **nextcloud-redis** | — | 🟡 Nextcloud degraded performance |
| **postgresql-immich** | — | 🔴 Immich completely non-functional |
| **redis-immich** | — | 🟡 Immich degraded (queue processing affected) |

### Tier 5: Supporting

| Service | Hard Dependencies | Impact if Down |
|---------|-------------------|----------------|
| **alert-discord-relay** | — | 🟢 Service-specific impact |
| **audiobookshelf** | — | 🟢 Service-specific impact |
| **cadvisor** | — | 🟢 Service-specific impact |
| **immich-ml** | — | 🟢 Service-specific impact |
| **matter-server** | — | 🟢 Service-specific impact |
| **navidrome** | — | 🟢 Service-specific impact |
| **node_exporter** | — | 🟢 Service-specific impact |
| **postgres-exporter** | postgresql-immich | 🟢 Service-specific impact |
| **promtail** | — | 🟢 Service-specific impact |
| **proton-bridge** | — | 🟢 Service-specific impact |
| **qbittorrent** | — | 🟢 Service-specific impact |
| **redis-authelia-exporter** | redis-authelia | 🟢 Service-specific impact |
| **redis-immich-exporter** | redis-immich | 🟢 Service-specific impact |
| **unifi-syslog** | — | 🟢 Service-specific impact |
| **unpoller** | — | 🟢 Service-specific impact |

---

## Startup Order

Derived from `After=` directives in quadlet files. systemd handles this automatically.

| Service | Starts After |
|---------|-------------|
| alert-discord-relay | (no ordering constraints) |
| alertmanager | (no ordering constraints) |
| audiobookshelf | traefik |
| authelia | redis-authelia |
| cadvisor | (no ordering constraints) |
| crowdsec | (no ordering constraints) |
| gathio | gathio-db |
| gathio-db | (no ordering constraints) |
| grafana | (no ordering constraints) |
| home-assistant | (no ordering constraints) |
| homepage | (no ordering constraints) |
| immich-ml | (no ordering constraints) |
| immich-server | postgresql-immich,redis-immich |
| jellyfin | (no ordering constraints) |
| loki | (no ordering constraints) |
| matter-server | (no ordering constraints) |
| navidrome | traefik |
| nextcloud | nextcloud-db,nextcloud-redis |
| nextcloud-db | (no ordering constraints) |
| nextcloud-redis | (no ordering constraints) |
| node_exporter | (no ordering constraints) |
| postgres-exporter | postgresql-immich |
| postgresql-immich | (no ordering constraints) |
| prometheus | node_exporter |
| promtail | loki |
| proton-bridge | (no ordering constraints) |
| qbittorrent | (no ordering constraints) |
| redis-authelia | (no ordering constraints) |
| redis-authelia-exporter | redis-authelia |
| redis-immich | (no ordering constraints) |
| redis-immich-exporter | redis-immich |
| traefik | http.socket,https.socket |
| unifi-syslog | (no ordering constraints) |
| unpoller | prometheus |
| vaultwarden | traefik |

---

## Network-Based Dependencies

Services on the same network can communicate:

**auth_services:** authelia,redis-authelia,redis-authelia-exporter

**gathio:** gathio,gathio-db

**home_automation:** home-assistant,matter-server

**mail:** authelia,proton-bridge

**media_services:** jellyfin

**monitoring:** alert-discord-relay,alertmanager,cadvisor,grafana,loki,node_exporter,postgres-exporter,prometheus,promtail,redis-authelia-exporter,redis-immich-exporter,unpoller

**nextcloud:** nextcloud,nextcloud-db,nextcloud-redis

**photos:** immich-ml,immich-server,postgres-exporter,postgresql-immich,redis-immich,redis-immich-exporter

**reverse_proxy:** alert-discord-relay,alertmanager,audiobookshelf,authelia,crowdsec,gathio,grafana,home-assistant,homepage,immich-server,jellyfin,loki,navidrome,nextcloud,prometheus,proton-bridge,qbittorrent,traefik,unpoller,vaultwarden

**syslog:** unifi-syslog

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
