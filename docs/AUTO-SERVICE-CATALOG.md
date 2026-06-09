# Service Catalog (Auto-Generated)

**Generated:** 2026-06-09 00:01:06 UTC
**System:** fedora-htpc | **Services:** 37/37 running | **Health:** 32/32 healthy (5 without healthcheck)

---

## Other (12)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| audiobookshelf | advplyr/audiobookshelf@sha256:89276ff2e0b3d2f | ✅ healthy | ~anh | [audiobookshelf.patriark.org](https://audiobookshelf.patriark.org) | — |
| blackbox-exporter | quay.io/prometheus/blackbox-exporter@sha256:e | ✅ healthy | ~anh | — | — |
| forgejo | codeberg.org/forgejo/forgejo@sha256:db04c7114 | ✅ healthy | ~anh | [git.patriark.org](https://git.patriark.org) | — |
| forgejo-db | postgres@sha256:16bc17c64a573ef34162af9298258 | ✅ healthy | ~anh | — | — |
| navidrome | deluan/navidrome@sha256:9fa40b3d8dec43ceb2213 | ✅ healthy | ~anh | [musikk.patriark.org](https://musikk.patriark.org) | — |
| pihole-exporter | ekofr/pihole-exporter@sha256:a890cc731a39da71 | — no check | ~anh | — | — |
| postgres-exporter | quay.io/prometheuscommunity/postgres-exporter | ✅ healthy | ~anh | — | — |
| proton-bridge | localhost/proton-bridge:3.23.1 | ✅ healthy | ~anh | — | — |
| qbittorrent | linuxserver/qbittorrent@sha256:f76c4363cce083 | ✅ healthy | ~anh | [torrent.patriark.org](https://torrent.patriark.org) | — |
| redis-authelia-exporter | quay.io/oliver006/redis_exporter@sha256:e8c20 | — no check | ~anh | — | — |
| redis-immich-exporter | quay.io/oliver006/redis_exporter@sha256:e8c20 | — no check | ~anh | — | — |
| unifi-syslog | linuxserver/syslog-ng@sha256:0d164e438d1f9ee4 | ✅ healthy | ~anh | — | — |

## Core Infrastructure (4)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| authelia | authelia/authelia@sha256:0c824dcab1ae97c56bf6 | ✅ healthy | ~anh | [sso.patriark.org](https://sso.patriark.org) | [guide](10-services/guides/authelia.md) |
| crowdsec | crowdsecurity/crowdsec@sha256:2f527c9bb8b3671 | ✅ healthy | ~anh | — | [guide](10-services/guides/crowdsec.md) |
| redis-authelia | redis@sha256:6ab0b6e7381779332f97b8ca76193e45 | ✅ healthy | ~anh | — | — |
| traefik | traefik@sha256:6b9cbca6fac42ab0075f5437d8dc16 | ✅ healthy | ~anh | [traefik.patriark.org](https://traefik.patriark.org) | [guide](10-services/guides/traefik.md) |

## Nextcloud (3)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| nextcloud-db | mariadb@sha256:78a5047d3ba33975f183f183c2464c | ✅ healthy | ~anh | — | [guide](10-services/guides/nextcloud.md) |
| nextcloud | nextcloud@sha256:b67959acacd54ed2d110e111c8b2 | ✅ healthy | ~anh | [nextcloud.patriark.org](https://nextcloud.patriark.org) | [guide](10-services/guides/nextcloud.md) |
| nextcloud-redis | redis@sha256:6ab0b6e7381779332f97b8ca76193e45 | ✅ healthy | ~anh | — | [guide](10-services/guides/nextcloud.md) |

## Immich (4)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| immich-ml | immich-app/immich-machine-learning@sha256:a25 | ✅ healthy | ~anh | — | [guide](10-services/guides/immich.md) |
| immich-server | immich-app/immich-server@sha256:c15bff75068ef | ✅ healthy | ~anh | [photos.patriark.org](https://photos.patriark.org) | [guide](10-services/guides/immich.md) |
| postgresql-immich | immich-app/postgres@sha256:bcf63357191b76a916 | ✅ healthy | ~anh | — | — |
| redis-immich | valkey/valkey@sha256:8436e10bc65c94886a91d441 | ✅ healthy | ~anh | — | — |

## Jellyfin (1)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| jellyfin | jellyfin/jellyfin@sha256:1694ff069f0c9dafb283 | ✅ healthy | ~anh | [jellyfin.patriark.org](https://jellyfin.patriark.org) | [guide](10-services/guides/jellyfin.md) |

## Vaultwarden (1)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| vaultwarden | vaultwarden/server@sha256:d626d04934cd1192ad8 | ✅ healthy | ~anh | [vault.patriark.org](https://vault.patriark.org) | — |

## Home Automation (1)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| home-assistant | home-assistant/home-assistant@sha256:d4fbec16 | ✅ healthy | ~anh | [ha.patriark.org](https://ha.patriark.org) | [guide](10-services/guides/home-assistant.md) |

## Gathio (2)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| gathio-db | mongo@sha256:32979a1189dfdc44da3f5ed40d910495 | ✅ healthy | ~anh | — | — |
| gathio | lowercasename/gathio@sha256:b7e9675d4e22b62e4 | ✅ healthy | ~anh | [events.patriark.org](https://events.patriark.org) | — |

## Monitoring (9)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| alert-discord-relay | localhost/alert-discord-relay:2026-05-23 | ✅ healthy | ~anh | — | [guide](10-services/guides/alert-discord-relay.md) |
| alertmanager | quay.io/prometheus/alertmanager@sha256:51a825 | ✅ healthy | ~anh | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| cadvisor | gcr.io/cadvisor/cadvisor@sha256:3de2bd5203120 | ✅ healthy | ~anh | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| grafana | grafana/grafana@sha256:2d1f9ae67c1778d33e291d | ✅ healthy | ~anh | [grafana.patriark.org](https://grafana.patriark.org) | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| loki | grafana/loki@sha256:191d4fdfb7264f16989f0a57f | — no check | ~anh | [loki.patriark.org](https://loki.patriark.org) | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| node_exporter | quay.io/prometheus/node-exporter@sha256:0f422 | ✅ healthy | ~anh | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| prometheus | quay.io/prometheus/prometheus@sha256:c0b857ae | ✅ healthy | ~anh | [prometheus.patriark.org](https://prometheus.patriark.org) | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| promtail | grafana/promtail@sha256:6cfa64ec432b24a912d64 | ✅ healthy | ~anh | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| unpoller | unpoller/unpoller@sha256:bf7bdcc59fcdaa469968 | — no check | ~anh | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |

---

## Statistics

- **Total Running:** 37
- **Total Defined:** 37
- **System Load:** 3,93, 2,44, 1,69

---

## Quick Links

- [Network Topology](AUTO-NETWORK-TOPOLOGY.md)
- [Dependency Graph](AUTO-DEPENDENCY-GRAPH.md)
- [Homelab Architecture](20-operations/guides/homelab-architecture.md)

---

*Auto-generated by `scripts/generate-service-catalog-simple.sh`*
