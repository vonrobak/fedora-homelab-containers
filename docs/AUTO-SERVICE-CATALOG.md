# Service Catalog (Auto-Generated)

**Generated:** 2026-02-28 06:01:30 UTC
**System:** fedora-htpc | **Services:** 27/27 running | **Health:** 25/25 healthy (2 without healthcheck)

---

## Core Infrastructure (4)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| authelia | authelia/authelia:latest | ✅ healthy | 5d | [sso.patriark.org](https://sso.patriark.org) | [guide](10-services/guides/authelia.md) |
| crowdsec | crowdsecurity/crowdsec:latest | ✅ healthy | 5d | — | [guide](10-services/guides/crowdsec.md) |
| redis-authelia | redis:7-alpine | ✅ healthy | 5d | — | — |
| traefik | traefik:latest | ✅ healthy | 5d | [traefik.patriark.org](https://traefik.patriark.org) | [guide](10-services/guides/traefik.md) |

## Nextcloud (3)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| nextcloud-db | mariadb:11 | ✅ healthy | 5d | — | [guide](10-services/guides/nextcloud.md) |
| nextcloud | nextcloud:latest | ✅ healthy | 5d | [nextcloud.patriark.org](https://nextcloud.patriark.org) | [guide](10-services/guides/nextcloud.md) |
| nextcloud-redis | redis:7-alpine | ✅ healthy | 5d | — | [guide](10-services/guides/nextcloud.md) |

## Immich (4)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| immich-ml | immich-app/immich-machine-learning:v2.5.5 | ✅ healthy | 5d | — | [guide](10-services/guides/immich.md) |
| immich-server | immich-app/immich-server:v2.5.5 | ✅ healthy | 5d | [photos.patriark.org](https://photos.patriark.org) | [guide](10-services/guides/immich.md) |
| postgresql-immich | immich-app/postgres:14-vectorchord0.4.3-pgvec | ✅ healthy | 5d | — | — |
| redis-immich | valkey/valkey:latest | ✅ healthy | 5d | — | — |

## Jellyfin (1)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| jellyfin | jellyfin/jellyfin:latest | ✅ healthy | 5d | [jellyfin.patriark.org](https://jellyfin.patriark.org) | [guide](10-services/guides/jellyfin.md) |

## Vaultwarden (1)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| vaultwarden | vaultwarden/server:latest | ✅ healthy | 5d | [vault.patriark.org](https://vault.patriark.org) | — |

## Home Automation (2)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| home-assistant | home-assistant/home-assistant:stable | ✅ healthy | 5d | [ha.patriark.org](https://ha.patriark.org) | [guide](10-services/guides/home-assistant.md) |
| matter-server | home-assistant-libs/python-matter-server:stab | ✅ healthy | 5d | — | [guide](10-services/guides/matter-server.md) |

## Gathio (2)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| gathio-db | mongo:7 | ✅ healthy | 5d | — | — |
| gathio | lowercasename/gathio:latest | ✅ healthy | 5d | [events.patriark.org](https://events.patriark.org) | — |

## Homepage (1)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| homepage | gethomepage/homepage:latest | ✅ healthy | 5d | [patriark.org](https://patriark.org) | — |

## Monitoring (9)

| Service | Image | Health | Uptime | URL | Docs |
|---------|-------|--------|--------|-----|------|
| alert-discord-relay | localhost/alert-discord-relay:latest | ✅ healthy | 5d | — | [guide](10-services/guides/alert-discord-relay.md) |
| alertmanager | quay.io/prometheus/alertmanager:latest | ✅ healthy | 5d | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| cadvisor | gcr.io/cadvisor/cadvisor:latest | ✅ healthy | 5d | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| grafana | grafana/grafana:latest | ✅ healthy | 4d | [grafana.patriark.org](https://grafana.patriark.org) | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| loki | grafana/loki:latest | — no check | 5d | [loki.patriark.org](https://loki.patriark.org) | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| node_exporter | quay.io/prometheus/node-exporter:latest | ✅ healthy | 5d | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| prometheus | quay.io/prometheus/prometheus:latest | ✅ healthy | 5d | [prometheus.patriark.org](https://prometheus.patriark.org) | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| promtail | grafana/promtail:latest | ✅ healthy | 5d | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |
| unpoller | unpoller/unpoller:latest | — no check | 5d | — | [guide](40-monitoring-and-documentation/guides/monitoring-stack.md) |

---

## Statistics

- **Total Running:** 27
- **Total Defined:** 27
- **System Load:** 0,86, 0,69, 0,62

---

## Quick Links

- [Network Topology](AUTO-NETWORK-TOPOLOGY.md)
- [Dependency Graph](AUTO-DEPENDENCY-GRAPH.md)
- [Homelab Architecture](20-operations/guides/homelab-architecture.md)

---

*Auto-generated by `scripts/generate-service-catalog-simple.sh`*
