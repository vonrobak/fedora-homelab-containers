# Container Image Pin Index (Auto-Generated)

**Generated:** 2026-07-01 22:04:56 UTC
**Source:** `/home/patriark/containers/quadlets` — ADR-030 (Container Supply-Chain Trust Model)

Pins live in each quadlet's `Image=` line (where Podman reads them); this is
the aggregated audit view. `tag` is the discovery handle; the digest is the
execution contract. Update = resolve a new digest, bake, edit the quadlet, restart.
For local builds the `Digest` column shows the **base image** pin (FROM …@sha256).

## Summary

| Metric | Count |
|--------|-------|
| Total images | 38 |
| 🔒 Digest-pinned | 36 |
| ⚠️ Floating (mutable tag) | 0 |
| 🔨 Local builds | 2 |
| 🔨 Local builds with FLOATING base | 0 |
| Egress-tier still floating | 0 |
| Egress-tier still auto-updating | 0 |
| 🔏 P6 signers (authenticity-verified on adopt) | 2 |
| ✗ P6 signature FAILED | 0 |

> ✅ **Supply-chain invariant holds:** no reverse_proxy-tier service is floating
> or auto-updating, every local build pins its base image by digest, and no
> known signer has a FAILED signature.

## Images

| Service | Egress | Status | Repository | Tag | Digest | Auto | Signed (P6) |
|---------|--------|--------|------------|-----|--------|------|-------------|
| alert-discord-relay | yes | 🔨 base-pinned | `localhost/alert-discord-relay` | 2026-05-23 | `sha256:a3ab0b966bc4…` | no | n/a (Tier 2) |
| alertmanager | yes | 🔒 pinned | `quay.io/prometheus/alertmanager` | latest | `sha256:af26fbe4dd18…` | no | — unsigned |
| audiobookshelf | yes | 🔒 pinned | `ghcr.io/advplyr/audiobookshelf` | 2.35.0 | `sha256:89276ff2e0b3…` | no | — unsigned |
| authelia | yes | 🔒 pinned | `docker.io/authelia/authelia` | latest | `sha256:1b363e9279e7…` | no | — unsigned |
| blackbox-exporter | yes | 🔒 pinned | `quay.io/prometheus/blackbox-exporter` | latest | `sha256:e753ff9f3fc4…` | no | — unsigned |
| cadvisor | no | 🔒 pinned | `gcr.io/cadvisor/cadvisor` | latest | `sha256:3de2bd520312…` | no | — unsigned |
| crowdsec | yes | 🔒 pinned | `docker.io/crowdsecurity/crowdsec` | latest | `sha256:2f527c9bb8b3…` | no | — unsigned |
| forgejo-db | no | 🔒 pinned | `docker.io/library/postgres` | 16-alpine | `sha256:e013e867e712…` | no | — unsigned |
| forgejo | yes | 🔒 pinned | `codeberg.org/forgejo/forgejo` | 15 | `sha256:55bb42bec9ab…` | no | — unsigned |
| gathio-db | no | 🔒 pinned | `docker.io/library/mongo` | 7 | `sha256:8ecb514b00bd…` | no | — unsigned |
| gathio | yes | 🔒 pinned | `ghcr.io/lowercasename/gathio` | latest | `sha256:ff66a8d2cc52…` | no | — unsigned |
| gluetun | yes | 🔒 pinned | `docker.io/qmcgaw/gluetun` | latest | `sha256:b0ee2135e6ba…` | no | — unsigned |
| grafana | yes | 🔒 pinned | `docker.io/grafana/grafana` | latest | `sha256:5dad0df181cb…` | no | — unsigned |
| home-assistant | yes | 🔒 pinned | `ghcr.io/home-assistant/home-assistant` | stable | `sha256:d4fbec16196d…` | no | ✓ verified |
| immich-ml | no | 🔒 pinned | `ghcr.io/immich-app/immich-machine-learning` | v2.7.5 | `sha256:a2501141440f…` | no | — unsigned |
| immich-server | yes | 🔒 pinned | `ghcr.io/immich-app/immich-server` | v2.7.5 | `sha256:c15bff75068e…` | no | — unsigned |
| jellyfin | yes | 🔒 pinned | `docker.io/jellyfin/jellyfin` | latest | `sha256:aefb67e6a7ff…` | no | — unsigned |
| loki | yes | 🔒 pinned | `docker.io/grafana/loki` | latest | `sha256:191d4fdfb726…` | no | — unsigned |
| navidrome | yes | 🔒 pinned | `docker.io/deluan/navidrome` | latest | `sha256:c4b5cb36a790…` | no | — unsigned |
| nextcloud-db | no | 🔒 pinned | `docker.io/library/mariadb` | 11 | `sha256:be1ef4fe5f14…` | no | — unsigned |
| nextcloud-redis | no | 🔒 pinned | `docker.io/library/redis` | 7-alpine | `sha256:6ab0b6e73817…` | no | — unsigned |
| nextcloud | yes | 🔒 pinned | `docker.io/library/nextcloud` | 33 | `sha256:fe5166b04f21…` | no | — unsigned |
| node_exporter | no | 🔒 pinned | `quay.io/prometheus/node-exporter` | latest | `sha256:0f422f62c15f…` | no | — unsigned |
| pihole-exporter | yes | 🔒 pinned | `docker.io/ekofr/pihole-exporter` | latest | `sha256:a890cc731a39…` | no | — unsigned |
| postgres-exporter | no | 🔒 pinned | `quay.io/prometheuscommunity/postgres-exporter` | latest | `sha256:e96064f87622…` | no | — unsigned |
| postgresql-immich | no | 🔒 pinned | `ghcr.io/immich-app/postgres` | 14-vectorchord0.4.3-pgvectors0.2.0 | `sha256:bcf63357191b…` | no | — unsigned |
| prometheus | yes | 🔒 pinned | `quay.io/prometheus/prometheus` | latest | `sha256:69f524141883…` | no | — unsigned |
| promtail | no | 🔒 pinned | `docker.io/grafana/promtail` | latest | `sha256:6cfa64ec432b…` | no | — unsigned |
| proton-bridge | yes | 🔨 base-pinned | `localhost/proton-bridge` | 3.23.1 | `sha256:747502f9190e…` | no | n/a (Tier 2) |
| qbittorrent | yes | 🔒 pinned | `docker.io/linuxserver/qbittorrent` | latest | `sha256:f76c4363cce0…` | no | — unsigned |
| redis-authelia-exporter | no | 🔒 pinned | `quay.io/oliver006/redis_exporter` | latest | `sha256:2e9795be900d…` | no | — unsigned |
| redis-authelia | no | 🔒 pinned | `docker.io/library/redis` | 7-alpine | `sha256:6ab0b6e73817…` | no | — unsigned |
| redis-immich-exporter | no | 🔒 pinned | `quay.io/oliver006/redis_exporter` | latest | `sha256:2e9795be900d…` | no | — unsigned |
| redis-immich | no | 🔒 pinned | `docker.io/valkey/valkey` | latest | `sha256:4963247afc4c…` | no | — unsigned |
| traefik | yes | 🔒 pinned | `docker.io/library/traefik` | latest | `sha256:6b9cbca6fac4…` | no | — unsigned |
| unifi-syslog | no | 🔒 pinned | `docker.io/linuxserver/syslog-ng` | latest | `sha256:53d71945a46f…` | no | — unsigned |
| unpoller | yes | 🔒 pinned | `ghcr.io/unpoller/unpoller` | latest | `sha256:bf7bdcc59fcd…` | no | — unsigned |
| vaultwarden | yes | 🔒 pinned | `docker.io/vaultwarden/server` | latest | `sha256:d626d04934cd…` | no | ✓ verified |

---

*Auto-generated by `scripts/generate-image-pin-index.sh`. Egress-tier ==
reverse_proxy network member (ADR-030 P4). Local builds (`localhost/*`) are
pinned via build inputs under Tier 2 — base image by digest, plus hash-locked
deps (alert-discord-relay) / GPG+SHA-verified RPM (proton-bridge) — not by
registry digest. The `Digest` column shows the base-image pin.*

*`Signed (P6)` (Tier 3): `✓ verified` / `✗ FAILED` reflect the last
deliberate-path cosign check (`signers.yaml` + the textfile metric), NOT a live
verify. `— unsigned` = no publisher signature, tracked in `config/supply-chain/
known-unsigned.md`. Survey 2026-05-24: 1/32 signed (Home Assistant). podman 5.8.2
policy.json cannot enforce its workflow-URI identity, so authenticity is verified
on the deliberate-update path — see the Tier 3 plan.*
