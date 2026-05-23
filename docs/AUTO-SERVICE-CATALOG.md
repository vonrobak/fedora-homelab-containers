# Service Catalog (Auto-Generated)

**Generated:** 2026-05-23 15:02:07 UTC
**System:** fedora-htpc | **Services:** 36/36 running | **Health:** 32/32 healthy (4 without healthcheck)

---

## Other (10)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| audiobookshelf | advplyr/audiobookshelf@sha256:4143292c530f6ac | ✅ healthy | 6m | [audiobookshelf.patriark.org](https://audiobookshelf.patriark.org) | — |
| forgejo | codeberg.org/forgejo/forgejo:15 | ✅ healthy | 42h | [git.patriark.org](https://git.patriark.org) | — |
| forgejo-db | postgres:16-alpine | ✅ healthy | 42h | — | — |
| navidrome | deluan/navidrome@sha256:9fa40b3d8dec43ceb2213 | ✅ healthy | 7m | [musikk.patriark.org](https://musikk.patriark.org) | — |
| postgres-exporter | quay.io/prometheuscommunity/postgres-exporter | ✅ healthy | 11m | — | — |
| proton-bridge | localhost/proton-bridge:3.23.1 | ✅ healthy | 9d | — | — |
| qbittorrent | linuxserver/qbittorrent@sha256:f76c4363cce083 | ✅ healthy | 5m | [torrent.patriark.org](https://torrent.patriark.org) | — |
| redis-authelia-exporter | quay.io/oliver006/redis_exporter@sha256:e8c20 | — no check | 10m | — | — |
| redis-immich-exporter | quay.io/oliver006/redis_exporter@sha256:e8c20 | — no check | 10m | — | — |
| unifi-syslog | linuxserver/syslog-ng@sha256:0d164e438d1f9ee4 | ✅ healthy | 10m | — | — |

## Core Infrastructure (4)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| authelia | authelia/authelia@sha256:0c824dcab1ae97c56bf6 | ✅ healthy | 41m | [sso.patriark.org](https://sso.patriark.org) | [guide](10-services/guides/authelia.md) |
| crowdsec | crowdsecurity/crowdsec@sha256:2f527c9bb8b3671 | ✅ healthy | 41m | — | [guide](10-services/guides/crowdsec.md) |
| redis-authelia | redis:7-alpine | ✅ healthy | 9d | — | — |
| traefik | traefik@sha256:6b9cbca6fac42ab0075f5437d8dc16 | ✅ healthy | 40m | [traefik.patriark.org](https://traefik.patriark.org) | [guide](10-services/guides/traefik.md) |

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
| jellyfin | jellyfin/jellyfin@sha256:1694ff069f0c9dafb283 | ✅ healthy | 5m | [jellyfin.patriark.org](https://jellyfin.patriark.org) | [guide](10-services/guides/jellyfin.md) |

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
| homepage | gethomepage/homepage@sha256:d8d784e5090111b6e | ✅ healthy | 9m | [patriark.org](https://patriark.org) | — |

## Monitoring (9)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| alert-discord-relay | localhost/alert-discord-relay:latest | ✅ healthy | 9d | — | [guide](10-services/guides/alert-discord-relay.md) |
| alertmanager | quay.io/prometheus/alertmanager@sha256:51a825 | ✅ healthy | 9m | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| cadvisor | gcr.io/cadvisor/cadvisor@sha256:3de2bd5203120 | ✅ healthy | 13m | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| grafana | grafana/grafana@sha256:2d1f9ae67c1778d33e291d | ✅ healthy | 8m | [grafana.patriark.org](https://grafana.patriark.org) | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| loki | grafana/loki:latest | — no check | 25h | [loki.patriark.org](https://loki.patriark.org) | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| node_exporter | quay.io/prometheus/node-exporter@sha256:0f422 | ✅ healthy | 12m | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| prometheus | quay.io/prometheus/prometheus:latest | ✅ healthy | 26h | [prometheus.patriark.org](https://prometheus.patriark.org) | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| promtail | grafana/promtail@sha256:6cfa64ec432b24a912d64 | ✅ healthy | 10m | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| unpoller | unpoller/unpoller@sha256:bf7bdcc59fcdaa469968 | — no check | 9m | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |

---

## Statistics

- **Total Running:** 36
- **Total Defined:** 36
- **System Load:** 3,29, 2,31, 1,69

---

## Quick Links

- [Network Topology](AUTO-NETWORK-TOPOLOGY.md)
- [Dependency Graph](AUTO-DEPENDENCY-GRAPH.md)
- [Homelab Architecture](20-operations/guides/homelab-architecture.md)

---

*Auto-generated by `scripts/generate-service-catalog-simple.sh`*
