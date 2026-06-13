# Service Catalog (Auto-Generated)

**Generated:** 2026-06-13 19:01:33 UTC
**System:** fedora-htpc | **Services:** 37/37 running | **Health:** 32/32 healthy (5 without healthcheck)

---

## Other (12)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| audiobookshelf | advplyr/audiobookshelf@sha256:89276ff2e0b3d2f | ✅ healthy | 25h | [audiobookshelf.patriark.org](https://audiobookshelf.patriark.org) | — |
| blackbox-exporter | quay.io/prometheus/blackbox-exporter@sha256:e | ✅ healthy | 4d | — | — |
| forgejo | codeberg.org/forgejo/forgejo@sha256:db04c7114 | ✅ healthy | 25h | [git.patriark.org](https://git.patriark.org) | — |
| forgejo-db | postgres@sha256:16bc17c64a573ef34162af9298258 | ✅ healthy | 25h | — | — |
| navidrome | deluan/navidrome@sha256:9fa40b3d8dec43ceb2213 | ✅ healthy | 25h | [musikk.patriark.org](https://musikk.patriark.org) | — |
| pihole-exporter | ekofr/pihole-exporter@sha256:a890cc731a39da71 | — no check | 4d | — | — |
| postgres-exporter | quay.io/prometheuscommunity/postgres-exporter | ✅ healthy | 25h | — | — |
| proton-bridge | localhost/proton-bridge:3.23.1 | ✅ healthy | 25h | — | — |
| qbittorrent | linuxserver/qbittorrent@sha256:f76c4363cce083 | ✅ healthy | 25h | [torrent.patriark.org](https://torrent.patriark.org) | — |
| redis-authelia-exporter | quay.io/oliver006/redis_exporter@sha256:2e979 | — no check | 25h | — | — |
| redis-immich-exporter | quay.io/oliver006/redis_exporter@sha256:2e979 | — no check | 25h | — | — |
| unifi-syslog | linuxserver/syslog-ng@sha256:b77c32d93b9e9b84 | ✅ healthy | 25h | — | — |

## Core Infrastructure (4)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| authelia | authelia/authelia@sha256:1b363e9279e742397966 | ✅ healthy | 25h | [sso.patriark.org](https://sso.patriark.org) | [guide](10-services/guides/authelia.md) |
| crowdsec | crowdsecurity/crowdsec@sha256:2f527c9bb8b3671 | ✅ healthy | 25h | — | [guide](10-services/guides/crowdsec.md) |
| redis-authelia | redis@sha256:6ab0b6e7381779332f97b8ca76193e45 | ✅ healthy | 25h | — | — |
| traefik | traefik@sha256:6b9cbca6fac42ab0075f5437d8dc16 | ✅ healthy | 25h | [traefik.patriark.org](https://traefik.patriark.org) | [guide](10-services/guides/traefik.md) |

## Nextcloud (3)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| nextcloud-db | mariadb@sha256:be1ef4fe5f14589325c08a41c76334 | ✅ healthy | 25h | — | [guide](10-services/guides/nextcloud.md) |
| nextcloud | nextcloud@sha256:b67959acacd54ed2d110e111c8b2 | ✅ healthy | 25h | [nextcloud.patriark.org](https://nextcloud.patriark.org) | [guide](10-services/guides/nextcloud.md) |
| nextcloud-redis | redis@sha256:6ab0b6e7381779332f97b8ca76193e45 | ✅ healthy | 25h | — | [guide](10-services/guides/nextcloud.md) |

## Immich (4)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| immich-ml | immich-app/immich-machine-learning@sha256:a25 | ✅ healthy | 25h | — | [guide](10-services/guides/immich.md) |
| immich-server | immich-app/immich-server@sha256:c15bff75068ef | ✅ healthy | 25h | [photos.patriark.org](https://photos.patriark.org) | [guide](10-services/guides/immich.md) |
| postgresql-immich | immich-app/postgres@sha256:bcf63357191b76a916 | ✅ healthy | 25h | — | — |
| redis-immich | valkey/valkey@sha256:4963247afc4cd33c7d3b2d28 | ✅ healthy | 25h | — | — |

## Jellyfin (1)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| jellyfin | jellyfin/jellyfin@sha256:1694ff069f0c9dafb283 | ✅ healthy | 25h | [jellyfin.patriark.org](https://jellyfin.patriark.org) | [guide](10-services/guides/jellyfin.md) |

## Vaultwarden (1)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| vaultwarden | vaultwarden/server@sha256:d626d04934cd1192ad8 | ✅ healthy | 25h | [vault.patriark.org](https://vault.patriark.org) | — |

## Home Automation (1)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| home-assistant | home-assistant/home-assistant@sha256:d4fbec16 | ✅ healthy | 25h | [ha.patriark.org](https://ha.patriark.org) | [guide](10-services/guides/home-assistant.md) |

## Gathio (2)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| gathio-db | mongo@sha256:c1a84ab5d0c17deed1e0dba1d24bd7c7 | ✅ healthy | 25h | — | — |
| gathio | lowercasename/gathio@sha256:ff66a8d2cc522568c | ✅ healthy | 25h | [events.patriark.org](https://events.patriark.org) | — |

## Monitoring (9)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| alert-discord-relay | localhost/alert-discord-relay:2026-05-23 | ✅ healthy | 25h | — | [guide](10-services/guides/alert-discord-relay.md) |
| alertmanager | quay.io/prometheus/alertmanager@sha256:51a825 | ✅ healthy | 22h | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| cadvisor | gcr.io/cadvisor/cadvisor@sha256:3de2bd5203120 | ✅ healthy | 25h | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| grafana | grafana/grafana@sha256:5dad0df181cb644a14e136 | ✅ healthy | 25h | [grafana.patriark.org](https://grafana.patriark.org) | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| loki | grafana/loki@sha256:191d4fdfb7264f16989f0a57f | — no check | 25h | [loki.patriark.org](https://loki.patriark.org) | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| node_exporter | quay.io/prometheus/node-exporter@sha256:0f422 | ✅ healthy | 25h | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| prometheus | quay.io/prometheus/prometheus@sha256:69f52414 | ✅ healthy | 25h | [prometheus.patriark.org](https://prometheus.patriark.org) | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| promtail | grafana/promtail@sha256:6cfa64ec432b24a912d64 | ✅ healthy | 25h | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| unpoller | unpoller/unpoller@sha256:bf7bdcc59fcdaa469968 | — no check | 4d | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |

---

## Statistics

- **Total Running:** 37
- **Total Defined:** 37
- **System Load:** 0,84, 0,78, 0,68

---

## Quick Links

- [Network Topology](AUTO-NETWORK-TOPOLOGY.md)
- [Dependency Graph](AUTO-DEPENDENCY-GRAPH.md)
- [Homelab Architecture](20-operations/guides/homelab-architecture.md)

---

*Auto-generated by `scripts/generate-service-catalog-simple.sh`*
