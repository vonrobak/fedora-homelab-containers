# Service Catalog (Auto-Generated)

**Generated:** 2026-05-23 13:52:17 UTC
**System:** fedora-htpc | **Services:** 36/36 running | **Health:** 32/32 healthy (4 without healthcheck)

---

## Other (10)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| audiobookshelf | advplyr/audiobookshelf:latest | ✅ healthy | 9d | [audiobookshelf.patriark.org](https://audiobookshelf.patriark.org) | — |
| forgejo | codeberg.org/forgejo/forgejo:15 | ✅ healthy | 41h | [git.patriark.org](https://git.patriark.org) | — |
| forgejo-db | postgres:16-alpine | ✅ healthy | 41h | — | — |
| navidrome | deluan/navidrome:latest | ✅ healthy | 9d | [musikk.patriark.org](https://musikk.patriark.org) | — |
| postgres-exporter | quay.io/prometheuscommunity/postgres-exporter | ✅ healthy | 8d | — | — |
| proton-bridge | localhost/proton-bridge:3.23.1 | ✅ healthy | 9d | — | — |
| qbittorrent | linuxserver/qbittorrent:latest | ✅ healthy | 9d | [torrent.patriark.org](https://torrent.patriark.org) | — |
| redis-authelia-exporter | quay.io/oliver006/redis_exporter:latest | — no check | 8d | — | — |
| redis-immich-exporter | quay.io/oliver006/redis_exporter:latest | — no check | 8d | — | — |
| unifi-syslog | linuxserver/syslog-ng:latest | ✅ healthy | 18h | — | — |

## Core Infrastructure (4)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| authelia | authelia/authelia:latest | ✅ healthy | 8d | [sso.patriark.org](https://sso.patriark.org) | [guide](10-services/guides/authelia.md) |
| crowdsec | crowdsecurity/crowdsec:latest | ✅ healthy | 9d | — | [guide](10-services/guides/crowdsec.md) |
| redis-authelia | redis:7-alpine | ✅ healthy | 9d | — | — |
| traefik | traefik:latest | ✅ healthy | 41h | [traefik.patriark.org](https://traefik.patriark.org) | [guide](10-services/guides/traefik.md) |

## Nextcloud (3)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| nextcloud-db | mariadb:11 | ✅ healthy | 9d | — | [guide](10-services/guides/nextcloud.md) |
| nextcloud | nextcloud:33 | ✅ healthy | 9d | [nextcloud.patriark.org](https://nextcloud.patriark.org) | [guide](10-services/guides/nextcloud.md) |
| nextcloud-redis | redis:7-alpine | ✅ healthy | 8d | — | [guide](10-services/guides/nextcloud.md) |

## Immich (4)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| immich-ml | immich-app/immich-machine-learning:v2.7.5 | ✅ healthy | 9d | — | [guide](10-services/guides/immich.md) |
| immich-server | immich-app/immich-server:v2.7.5 | ✅ healthy | 9d | [photos.patriark.org](https://photos.patriark.org) | [guide](10-services/guides/immich.md) |
| postgresql-immich | immich-app/postgres:14-vectorchord0.4.3-pgvec | ✅ healthy | 9d | — | — |
| redis-immich | valkey/valkey:latest | ✅ healthy | 9d | — | — |

## Jellyfin (1)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| jellyfin | jellyfin/jellyfin:latest | ✅ healthy | 9d | [jellyfin.patriark.org](https://jellyfin.patriark.org) | [guide](10-services/guides/jellyfin.md) |

## Vaultwarden (1)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| vaultwarden | vaultwarden/server:latest | ✅ healthy | 9d | [vault.patriark.org](https://vault.patriark.org) | — |

## Home Automation (1)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| home-assistant | home-assistant/home-assistant:stable | ✅ healthy | 9d | [ha.patriark.org](https://ha.patriark.org) | [guide](10-services/guides/home-assistant.md) |

## Gathio (2)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| gathio-db | mongo:7 | ✅ healthy | 9d | — | — |
| gathio | lowercasename/gathio:latest | ✅ healthy | 9d | [events.patriark.org](https://events.patriark.org) | — |

## Homepage (1)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| homepage | gethomepage/homepage:latest | ✅ healthy | 9d | [patriark.org](https://patriark.org) | — |

## Monitoring (9)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| alert-discord-relay | localhost/alert-discord-relay:latest | ✅ healthy | 9d | — | [guide](10-services/guides/alert-discord-relay.md) |
| alertmanager | quay.io/prometheus/alertmanager:latest | ✅ healthy | 9d | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| cadvisor | gcr.io/cadvisor/cadvisor:latest | ✅ healthy | 9d | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| grafana | grafana/grafana:latest | ✅ healthy | 9d | [grafana.patriark.org](https://grafana.patriark.org) | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| loki | grafana/loki:latest | — no check | 24h | [loki.patriark.org](https://loki.patriark.org) | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| node_exporter | quay.io/prometheus/node-exporter:latest | ✅ healthy | 9d | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| prometheus | quay.io/prometheus/prometheus:latest | ✅ healthy | 25h | [prometheus.patriark.org](https://prometheus.patriark.org) | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| promtail | grafana/promtail:latest | ✅ healthy | 18h | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| unpoller | unpoller/unpoller:latest | — no check | 9d | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |

---

## Statistics

- **Total Running:** 36
- **Total Defined:** 36
- **System Load:** 2,93, 2,05, 1,48

---

## Quick Links

- [Network Topology](AUTO-NETWORK-TOPOLOGY.md)
- [Dependency Graph](AUTO-DEPENDENCY-GRAPH.md)
- [Homelab Architecture](20-operations/guides/homelab-architecture.md)

---

*Auto-generated by `scripts/generate-service-catalog-simple.sh`*
