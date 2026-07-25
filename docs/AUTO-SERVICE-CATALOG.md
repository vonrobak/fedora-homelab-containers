# Service Catalog (Auto-Generated)

**Generated:** 2026-07-25 00:28:48 UTC
**System:** fedora-htpc | **Services:** 37/37 running | **Health:** 32/32 healthy (5 without healthcheck)

---

## Other (12)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| audiobookshelf | advplyr/audiobookshelf@sha256:89276ff2e0b3d2f | ✅ healthy | 7d | [audiobookshelf.patriark.org](https://audiobookshelf.patriark.org) | — |
| blackbox-exporter | quay.io/prometheus/blackbox-exporter@sha256:e | ✅ healthy | 7d | — | — |
| forgejo | codeberg.org/forgejo/forgejo@sha256:55bb42bec | ✅ healthy | 7d | [git.patriark.org](https://git.patriark.org) | — |
| forgejo-db | postgres@sha256:57c72fd2a128e416c7fcc49995886 | ✅ healthy | 11d | — | — |
| navidrome | deluan/navidrome@sha256:c4b5cb36a790b3eb63ca6 | ✅ healthy | 11d | [musikk.patriark.org](https://musikk.patriark.org) | — |
| pihole-exporter | ekofr/pihole-exporter@sha256:a890cc731a39da71 | — no check | 7d | — | — |
| postgres-exporter | quay.io/prometheuscommunity/postgres-exporter | ✅ healthy | 11d | — | — |
| proton-bridge | localhost/proton-bridge:3.23.1 | ✅ healthy | 11d | — | — |
| qbittorrent | linuxserver/qbittorrent@sha256:f76c4363cce083 | ✅ healthy | 11d | [torrent.patriark.org](https://torrent.patriark.org) | — |
| redis-authelia-exporter | quay.io/oliver006/redis_exporter@sha256:2e979 | — no check | 11d | — | — |
| redis-immich-exporter | quay.io/oliver006/redis_exporter@sha256:2e979 | — no check | 11d | — | — |
| unifi-syslog | linuxserver/syslog-ng@sha256:b4ab00e399207db8 | ✅ healthy | 11d | — | — |

## Core Infrastructure (4)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| authelia | authelia/authelia@sha256:1b363e9279e742397966 | ✅ healthy | 7d | [sso.patriark.org](https://sso.patriark.org) | [guide](10-services/guides/authelia.md) |
| crowdsec | crowdsecurity/crowdsec@sha256:2f527c9bb8b3671 | ✅ healthy | 11d | — | — |
| redis-authelia | redis@sha256:6ab0b6e7381779332f97b8ca76193e45 | ✅ healthy | 11d | — | — |
| traefik | traefik@sha256:6b9cbca6fac42ab0075f5437d8dc16 | ✅ healthy | 7d | [traefik.patriark.org](https://traefik.patriark.org) | [guide](10-services/guides/traefik.md) |

## Nextcloud (3)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| nextcloud-db | mariadb@sha256:efb4959ef2c835cd735dbc388eb9ad | ✅ healthy | 11d | — | — |
| nextcloud | nextcloud@sha256:35170a1c67e759ef874eaa0fde74 | ✅ healthy | 7d | [nextcloud.patriark.org](https://nextcloud.patriark.org) | — |
| nextcloud-redis | redis@sha256:6ab0b6e7381779332f97b8ca76193e45 | ✅ healthy | 6h | — | — |

## Immich (4)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| immich-ml | immich-app/immich-machine-learning@sha256:a25 | ✅ healthy | 11d | — | — |
| immich-server | immich-app/immich-server@sha256:c15bff75068ef | ✅ healthy | 11d | [photos.patriark.org](https://photos.patriark.org) | — |
| postgresql-immich | immich-app/postgres@sha256:bcf63357191b76a916 | ✅ healthy | 11d | — | — |
| redis-immich | valkey/valkey@sha256:4963247afc4cd33c7d3b2d28 | ✅ healthy | 11d | — | — |

## Jellyfin (1)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| jellyfin | jellyfin/jellyfin@sha256:aefb67e6a7ff1debdd15 | ✅ healthy | 11d | [jellyfin.patriark.org](https://jellyfin.patriark.org) | — |

## Vaultwarden (1)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| vaultwarden | vaultwarden/server@sha256:d626d04934cd1192ad8 | ✅ healthy | 11d | [vault.patriark.org](https://vault.patriark.org) | — |

## Home Automation (1)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| home-assistant | home-assistant/home-assistant@sha256:d4fbec16 | ✅ healthy | 11d | [ha.patriark.org](https://ha.patriark.org) | — |

## Gathio (2)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| gathio-db | mongo@sha256:d5b3ca8c3f3cdce78d44870dc0871b76 | ✅ healthy | 11d | — | — |
| gathio | lowercasename/gathio@sha256:ff66a8d2cc522568c | ✅ healthy | 11d | [events.patriark.org](https://events.patriark.org) | — |

## Monitoring (9)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| alert-discord-relay | localhost/alert-discord-relay:2026-05-23 | ✅ healthy | 11d | — | — |
| alertmanager | quay.io/prometheus/alertmanager@sha256:9e0829 | ✅ healthy | 7d | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| cadvisor | gcr.io/cadvisor/cadvisor@sha256:3de2bd5203120 | ✅ healthy | 11d | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| grafana | grafana/grafana@sha256:121a7a9ece6dc10b969f1f | ✅ healthy | ~anh | [grafana.patriark.org](https://grafana.patriark.org) | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| loki | grafana/loki@sha256:70b9f699fc9bb868b62f1cfd4 | — no check | 11d | [loki.patriark.org](https://loki.patriark.org) | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| node_exporter | quay.io/prometheus/node-exporter@sha256:0f422 | ✅ healthy | 11d | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| prometheus | quay.io/prometheus/prometheus@sha256:69f52414 | ✅ healthy | 7d | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| promtail | grafana/promtail@sha256:6cfa64ec432b24a912d64 | ✅ healthy | 12m | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| unpoller | unpoller/unpoller@sha256:9dcccdc931a6830735f6 | — no check | 7d | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |

---

## Statistics

- **Total Running:** 37
- **Total Defined:** 37
- **System Load:** 0,58, 1,24, 1,47

---

## Quick Links

- [Network Topology](AUTO-NETWORK-TOPOLOGY.md)
- [Dependency Graph](AUTO-DEPENDENCY-GRAPH.md)
- [Homelab Architecture](20-operations/guides/homelab-architecture.md)

---

*Auto-generated by `scripts/generate-service-catalog-simple.sh`*
