# Service Catalog (Auto-Generated)

**Generated:** 2026-07-01 22:04:47 UTC
**System:** fedora-htpc | **Services:** 37/37 running | **Health:** 32/32 healthy (5 without healthcheck)

---

## Other (12)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| audiobookshelf | advplyr/audiobookshelf@sha256:89276ff2e0b3d2f | ✅ healthy | 8d | [audiobookshelf.patriark.org](https://audiobookshelf.patriark.org) | — |
| blackbox-exporter | quay.io/prometheus/blackbox-exporter@sha256:e | ✅ healthy | 8d | — | — |
| forgejo | codeberg.org/forgejo/forgejo@sha256:55bb42bec | ✅ healthy | 8d | [git.patriark.org](https://git.patriark.org) | — |
| forgejo-db | postgres@sha256:e013e867e712fec275706a6c51c96 | ✅ healthy | 8d | — | — |
| navidrome | deluan/navidrome@sha256:c4b5cb36a790b3eb63ca6 | ✅ healthy | 8d | [musikk.patriark.org](https://musikk.patriark.org) | — |
| pihole-exporter | ekofr/pihole-exporter@sha256:a890cc731a39da71 | — no check | 8d | — | — |
| postgres-exporter | quay.io/prometheuscommunity/postgres-exporter | ✅ healthy | 8d | — | — |
| proton-bridge | localhost/proton-bridge:3.23.1 | ✅ healthy | 8d | — | — |
| qbittorrent | linuxserver/qbittorrent@sha256:f76c4363cce083 | ✅ healthy | 8d | [torrent.patriark.org](https://torrent.patriark.org) | — |
| redis-authelia-exporter | quay.io/oliver006/redis_exporter@sha256:2e979 | — no check | 8d | — | — |
| redis-immich-exporter | quay.io/oliver006/redis_exporter@sha256:2e979 | — no check | 8d | — | — |
| unifi-syslog | linuxserver/syslog-ng@sha256:53d71945a46f2fa0 | ✅ healthy | 8d | — | — |

## Core Infrastructure (4)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| authelia | authelia/authelia@sha256:1b363e9279e742397966 | ✅ healthy | 8d | [sso.patriark.org](https://sso.patriark.org) | [guide](10-services/guides/authelia.md) |
| crowdsec | crowdsecurity/crowdsec@sha256:2f527c9bb8b3671 | ✅ healthy | 8d | — | [guide](10-services/guides/crowdsec.md) |
| redis-authelia | redis@sha256:6ab0b6e7381779332f97b8ca76193e45 | ✅ healthy | 8d | — | — |
| traefik | traefik@sha256:6b9cbca6fac42ab0075f5437d8dc16 | ✅ healthy | 8d | [traefik.patriark.org](https://traefik.patriark.org) | [guide](10-services/guides/traefik.md) |

## Nextcloud (3)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| nextcloud-db | mariadb@sha256:be1ef4fe5f14589325c08a41c76334 | ✅ healthy | 8d | — | [guide](10-services/guides/nextcloud.md) |
| nextcloud | nextcloud@sha256:fe5166b04f217c9e3a263bfe76ee | ✅ healthy | 5d | [nextcloud.patriark.org](https://nextcloud.patriark.org) | [guide](10-services/guides/nextcloud.md) |
| nextcloud-redis | redis@sha256:6ab0b6e7381779332f97b8ca76193e45 | ✅ healthy | 8d | — | [guide](10-services/guides/nextcloud.md) |

## Immich (4)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| immich-ml | immich-app/immich-machine-learning@sha256:a25 | ✅ healthy | 8d | — | [guide](10-services/guides/immich.md) |
| immich-server | immich-app/immich-server@sha256:c15bff75068ef | ✅ healthy | 8d | [photos.patriark.org](https://photos.patriark.org) | [guide](10-services/guides/immich.md) |
| postgresql-immich | immich-app/postgres@sha256:bcf63357191b76a916 | ✅ healthy | 8d | — | — |
| redis-immich | valkey/valkey@sha256:4963247afc4cd33c7d3b2d28 | ✅ healthy | 8d | — | — |

## Jellyfin (1)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| jellyfin | jellyfin/jellyfin@sha256:aefb67e6a7ff1debdd15 | ✅ healthy | 8d | [jellyfin.patriark.org](https://jellyfin.patriark.org) | [guide](10-services/guides/jellyfin.md) |

## Vaultwarden (1)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| vaultwarden | vaultwarden/server@sha256:d626d04934cd1192ad8 | ✅ healthy | 8d | [vault.patriark.org](https://vault.patriark.org) | — |

## Home Automation (1)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| home-assistant | home-assistant/home-assistant@sha256:d4fbec16 | ✅ healthy | 8d | [ha.patriark.org](https://ha.patriark.org) | [guide](10-services/guides/home-assistant.md) |

## Gathio (2)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| gathio-db | mongo@sha256:8ecb514b00bdcc0bde67ef4e6c330385 | ✅ healthy | 8d | — | — |
| gathio | lowercasename/gathio@sha256:ff66a8d2cc522568c | ✅ healthy | 8d | [events.patriark.org](https://events.patriark.org) | — |

## Monitoring (9)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| alert-discord-relay | localhost/alert-discord-relay:2026-05-23 | ✅ healthy | 8d | — | [guide](10-services/guides/alert-discord-relay.md) |
| alertmanager | quay.io/prometheus/alertmanager@sha256:af26fb | ✅ healthy | 8d | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| cadvisor | gcr.io/cadvisor/cadvisor@sha256:3de2bd5203120 | ✅ healthy | 8d | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| grafana | grafana/grafana@sha256:5dad0df181cb644a14e136 | ✅ healthy | 8d | [grafana.patriark.org](https://grafana.patriark.org) | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| loki | grafana/loki@sha256:191d4fdfb7264f16989f0a57f | — no check | 8d | [loki.patriark.org](https://loki.patriark.org) | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| node_exporter | quay.io/prometheus/node-exporter@sha256:0f422 | ✅ healthy | 8d | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| prometheus | quay.io/prometheus/prometheus@sha256:69f52414 | ✅ healthy | 8d | [prometheus.patriark.org](https://prometheus.patriark.org) | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| promtail | grafana/promtail@sha256:6cfa64ec432b24a912d64 | ✅ healthy | 8d | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| unpoller | unpoller/unpoller@sha256:bf7bdcc59fcdaa469968 | — no check | 8d | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |

---

## Statistics

- **Total Running:** 37
- **Total Defined:** 37
- **System Load:** 3,11, 3,41, 2,77

---

## Quick Links

- [Network Topology](AUTO-NETWORK-TOPOLOGY.md)
- [Dependency Graph](AUTO-DEPENDENCY-GRAPH.md)
- [Homelab Architecture](20-operations/guides/homelab-architecture.md)

---

*Auto-generated by `scripts/generate-service-catalog-simple.sh`*
