# Service Catalog (Auto-Generated)

**Generated:** 2026-07-25 10:12:55 UTC
**System:** fedora-htpc | **Services:** 37/37 running | **Health:** 32/32 healthy (5 without healthcheck)

---

## Other (12)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| audiobookshelf | advplyr/audiobookshelf@sha256:89276ff2e0b3d2f | ✅ healthy | 7d | [audiobookshelf.patriark.org](https://audiobookshelf.patriark.org) | — |
| blackbox-exporter | quay.io/prometheus/blackbox-exporter@sha256:e | ✅ healthy | 7d | — | — |
| forgejo | codeberg.org/forgejo/forgejo@sha256:eda2e3784 | ✅ healthy | 54m | [git.patriark.org](https://git.patriark.org) | — |
| forgejo-db | postgres@sha256:57c72fd2a128e416c7fcc49995886 | ✅ healthy | 11d | — | — |
| navidrome | deluan/navidrome@sha256:9012939114fbb1bb641b8 | ✅ healthy | 52m | [musikk.patriark.org](https://musikk.patriark.org) | — |
| pihole-exporter | ekofr/pihole-exporter@sha256:a890cc731a39da71 | — no check | 8d | — | — |
| postgres-exporter | quay.io/prometheuscommunity/postgres-exporter | ✅ healthy | 11d | — | — |
| proton-bridge | localhost/proton-bridge:3.23.1 | ✅ healthy | 11d | — | — |
| qbittorrent | linuxserver/qbittorrent@sha256:b024436f8ca665 | ✅ healthy | 32m | [torrent.patriark.org](https://torrent.patriark.org) | — |
| redis-authelia-exporter | quay.io/oliver006/redis_exporter@sha256:2c8c5 | — no check | 40m | — | — |
| redis-immich-exporter | quay.io/oliver006/redis_exporter@sha256:2c8c5 | — no check | 40m | — | — |
| unifi-syslog | linuxserver/syslog-ng@sha256:f2eeb181908b3068 | ✅ healthy | 55m | — | — |

## Core Infrastructure (4)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| authelia | authelia/authelia@sha256:1b363e9279e742397966 | ✅ healthy | 7d | [sso.patriark.org](https://sso.patriark.org) | [guide](10-services/guides/authelia.md) |
| crowdsec | crowdsecurity/crowdsec@sha256:2f527c9bb8b3671 | ✅ healthy | 11d | — | — |
| redis-authelia | redis@sha256:6ab0b6e7381779332f97b8ca76193e45 | ✅ healthy | 11d | — | — |
| traefik | traefik@sha256:652929a140a32d7cafafb13c6cdfab | ✅ healthy | 12m | [traefik.patriark.org](https://traefik.patriark.org) | [guide](10-services/guides/traefik.md) |

## Nextcloud (3)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| nextcloud-db | mariadb@sha256:efb4959ef2c835cd735dbc388eb9ad | ✅ healthy | 11d | — | — |
| nextcloud | nextcloud@sha256:2e0ba719164b092fe0629c6e36d1 | ✅ healthy | 35m | [nextcloud.patriark.org](https://nextcloud.patriark.org) | — |
| nextcloud-redis | redis@sha256:6ab0b6e7381779332f97b8ca76193e45 | ✅ healthy | 15h | — | — |

## Immich (4)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| immich-ml | immich-app/immich-machine-learning@sha256:a25 | ✅ healthy | 11d | — | — |
| immich-server | immich-app/immich-server@sha256:c15bff75068ef | ✅ healthy | 42m | [photos.patriark.org](https://photos.patriark.org) | — |
| postgresql-immich | immich-app/postgres@sha256:bcf63357191b76a916 | ✅ healthy | 11d | — | — |
| redis-immich | valkey/valkey@sha256:3acc0687f2a2e1091fae6450 | ✅ healthy | 43m | — | — |

## Jellyfin (1)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| jellyfin | jellyfin/jellyfin@sha256:aefb67e6a7ff1debdd15 | ✅ healthy | 11d | [jellyfin.patriark.org](https://jellyfin.patriark.org) | — |

## Vaultwarden (1)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| vaultwarden | vaultwarden/server@sha256:e6443e3d5ed8fcee220 | ✅ healthy | ~anh | [vault.patriark.org](https://vault.patriark.org) | — |

## Home Automation (1)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| home-assistant | home-assistant/home-assistant@sha256:5a531753 | ✅ healthy | 38m | [ha.patriark.org](https://ha.patriark.org) | — |

## Gathio (2)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| gathio-db | mongo@sha256:9bdaeb6dac6e7e762e84e2f84103d1f9 | ✅ healthy | 15m | — | — |
| gathio | lowercasename/gathio@sha256:40ac5ab0b49cb58b0 | ✅ healthy | 14m | [events.patriark.org](https://events.patriark.org) | — |

## Monitoring (9)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| alert-discord-relay | localhost/alert-discord-relay:2026-05-23 | ✅ healthy | 11d | — | — |
| alertmanager | quay.io/prometheus/alertmanager@sha256:9e0829 | ✅ healthy | 7d | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| cadvisor | gcr.io/cadvisor/cadvisor@sha256:3de2bd5203120 | ✅ healthy | 11d | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| grafana | grafana/grafana@sha256:1c1bd67c54c5fcf6e75989 | ✅ healthy | 31m | [grafana.patriark.org](https://grafana.patriark.org) | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| loki | grafana/loki@sha256:87f0a067673756a3cede1bcbf | — no check | 20m | [loki.patriark.org](https://loki.patriark.org) | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| node_exporter | quay.io/prometheus/node-exporter@sha256:1b4e4 | ✅ healthy | 56m | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| prometheus | quay.io/prometheus/prometheus@sha256:3c42b892 | ✅ healthy | 43m | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| promtail | grafana/promtail@sha256:6cfa64ec432b24a912d64 | ✅ healthy | 55m | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| unpoller | unpoller/unpoller@sha256:e84e0fa3427548df4cc1 | — no check | 54m | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |

---

## Statistics

- **Total Running:** 37
- **Total Defined:** 37
- **System Load:** 0,27, 0,74, 1,63

---

## Quick Links

- [Network Topology](AUTO-NETWORK-TOPOLOGY.md)
- [Dependency Graph](AUTO-DEPENDENCY-GRAPH.md)
- [Homelab Architecture](20-operations/guides/homelab-architecture.md)

---

*Auto-generated by `scripts/generate-service-catalog-simple.sh`*
