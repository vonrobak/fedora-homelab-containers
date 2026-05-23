# Container Image Pin Index (Auto-Generated)

**Generated:** 2026-05-23 16:06:20 UTC
**Source:** `/home/patriark/containers/quadlets` — ADR-030 (Container Supply-Chain Trust Model)

Pins live in each quadlet's `Image=` line (where Podman reads them); this is
the aggregated audit view. `tag` is the discovery handle; the digest is the
execution contract. Update = resolve a new digest, bake, edit the quadlet, restart.
For local builds the `Digest` column shows the **base image** pin (FROM …@sha256).

## Summary

| Metric | Count |
|--------|-------|
| Total images | 36 |
| 🔒 Digest-pinned | 34 |
| ⚠️ Floating (mutable tag) | 0 |
| 🔨 Local builds | 2 |
| 🔨 Local builds with FLOATING base | 0 |
| Egress-tier still floating | 0 |
| Egress-tier still auto-updating | 0 |

> ✅ **Supply-chain invariant holds:** no reverse_proxy-tier service is floating
> or auto-updating, and every local build pins its base image by digest.

## Images

| Service | Egress | Status | Repository | Tag | Digest | Auto |
|---------|--------|--------|------------|-----|--------|------|
| alert-discord-relay | yes | 🔨 base-pinned | `localhost/alert-discord-relay` | latest | `sha256:a3ab0b966bc4…` | no |
| alertmanager | yes | 🔒 pinned | `quay.io/prometheus/alertmanager` | latest | `sha256:51a825c2a40a…` | no |
| audiobookshelf | yes | 🔒 pinned | `ghcr.io/advplyr/audiobookshelf` | latest | `sha256:4143292c530f…` | no |
| authelia | yes | 🔒 pinned | `docker.io/authelia/authelia` | latest | `sha256:0c824dcab1ae…` | no |
| cadvisor | no | 🔒 pinned | `gcr.io/cadvisor/cadvisor` | latest | `sha256:3de2bd520312…` | no |
| crowdsec | yes | 🔒 pinned | `docker.io/crowdsecurity/crowdsec` | latest | `sha256:2f527c9bb8b3…` | no |
| forgejo-db | no | 🔒 pinned | `docker.io/library/postgres` | 16-alpine | `sha256:16bc17c64a57…` | no |
| forgejo | yes | 🔒 pinned | `codeberg.org/forgejo/forgejo` | 15 | `sha256:db04c7114b65…` | no |
| gathio-db | no | 🔒 pinned | `docker.io/library/mongo` | 7 | `sha256:32979a1189df…` | no |
| gathio | yes | 🔒 pinned | `ghcr.io/lowercasename/gathio` | latest | `sha256:b7e9675d4e22…` | no |
| grafana | yes | 🔒 pinned | `docker.io/grafana/grafana` | latest | `sha256:2d1f9ae67c17…` | no |
| home-assistant | yes | 🔒 pinned | `ghcr.io/home-assistant/home-assistant` | stable | `sha256:d4fbec16196d…` | no |
| homepage | yes | 🔒 pinned | `ghcr.io/gethomepage/homepage` | latest | `sha256:d8d784e50901…` | no |
| immich-ml | no | 🔒 pinned | `ghcr.io/immich-app/immich-machine-learning` | v2.7.5 | `sha256:a2501141440f…` | no |
| immich-server | yes | 🔒 pinned | `ghcr.io/immich-app/immich-server` | v2.7.5 | `sha256:c15bff75068e…` | no |
| jellyfin | yes | 🔒 pinned | `docker.io/jellyfin/jellyfin` | latest | `sha256:1694ff069f0c…` | no |
| loki | yes | 🔒 pinned | `docker.io/grafana/loki` | latest | `sha256:191d4fdfb726…` | no |
| navidrome | yes | 🔒 pinned | `docker.io/deluan/navidrome` | latest | `sha256:9fa40b3d8dec…` | no |
| nextcloud-db | no | 🔒 pinned | `docker.io/library/mariadb` | 11 | `sha256:78a5047d3ba3…` | no |
| nextcloud-redis | no | 🔒 pinned | `docker.io/library/redis` | 7-alpine | `sha256:6ab0b6e73817…` | no |
| nextcloud | yes | 🔒 pinned | `docker.io/library/nextcloud` | 33 | `sha256:b67959acacd5…` | no |
| node_exporter | no | 🔒 pinned | `quay.io/prometheus/node-exporter` | latest | `sha256:0f422f62c15f…` | no |
| postgres-exporter | no | 🔒 pinned | `quay.io/prometheuscommunity/postgres-exporter` | latest | `sha256:e96064f87622…` | no |
| postgresql-immich | no | 🔒 pinned | `ghcr.io/immich-app/postgres` | 14-vectorchord0.4.3-pgvectors0.2.0 | `sha256:bcf63357191b…` | no |
| prometheus | yes | 🔒 pinned | `quay.io/prometheus/prometheus` | latest | `sha256:c0b857aead0d…` | no |
| promtail | no | 🔒 pinned | `docker.io/grafana/promtail` | latest | `sha256:6cfa64ec432b…` | no |
| proton-bridge | yes | 🔨 base-pinned | `localhost/proton-bridge` | 3.23.1 | `sha256:747502f9190e…` | no |
| qbittorrent | yes | 🔒 pinned | `docker.io/linuxserver/qbittorrent` | latest | `sha256:f76c4363cce0…` | no |
| redis-authelia-exporter | no | 🔒 pinned | `quay.io/oliver006/redis_exporter` | latest | `sha256:e8c209894d4c…` | no |
| redis-authelia | no | 🔒 pinned | `docker.io/library/redis` | 7-alpine | `sha256:6ab0b6e73817…` | no |
| redis-immich-exporter | no | 🔒 pinned | `quay.io/oliver006/redis_exporter` | latest | `sha256:e8c209894d4c…` | no |
| redis-immich | no | 🔒 pinned | `docker.io/valkey/valkey` | latest | `sha256:8436e10bc65c…` | no |
| traefik | yes | 🔒 pinned | `docker.io/library/traefik` | latest | `sha256:6b9cbca6fac4…` | no |
| unifi-syslog | no | 🔒 pinned | `docker.io/linuxserver/syslog-ng` | latest | `sha256:0d164e438d1f…` | no |
| unpoller | yes | 🔒 pinned | `ghcr.io/unpoller/unpoller` | latest | `sha256:bf7bdcc59fcd…` | no |
| vaultwarden | yes | 🔒 pinned | `docker.io/vaultwarden/server` | latest | `sha256:d626d04934cd…` | no |

---

*Auto-generated by `scripts/generate-image-pin-index.sh`. Egress-tier ==
reverse_proxy network member (ADR-030 P4). Local builds (`localhost/*`) are
pinned via build inputs under Tier 2 — base image by digest, plus hash-locked
deps (alert-discord-relay) / GPG+SHA-verified RPM (proton-bridge) — not by
registry digest. The `Digest` column shows the base-image pin.*
