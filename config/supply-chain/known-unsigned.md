# Known-Unsigned Images (ADR-030 P6 — tracked, not silently trusted)

**Survey date:** 2026-06-13 (re-survey; original 2026-05-24) · **Tool:** containerized
cosign v3.0.6 (`cosign tree`) + skopeo tag-scheme probe + `gh attestation verify`.

ADR-030 P6 enforces authenticity *where publishers support it* and **tracks** the
publishers who do not — rather than silently trusting them. This is that record. Of
33 unique external repositories, **2 are signed** (`ghcr.io/home-assistant/home-assistant`,
`docker.io/vaultwarden/server` — both verified on the deliberate-update path via
`signers.yaml`); the rest are listed below.

This is a point-in-time snapshot. Re-run the survey when adding a service or when a
publisher may have started signing; promote any new signer into `signers.yaml`.
The 2026-06-13 re-survey proves coverage *does* grow: vaultwarden gained GitHub
Artifact Attestations between the two surveys.

## Signed (enforced via deliberate-path cosign gate)

| Repository | Mechanism |
|---|---|
| `ghcr.io/home-assistant/home-assistant` | keyless GitHub-Actions cosign signature (Rekor-logged) — see `signers.yaml` |
| `docker.io/vaultwarden/server` | GitHub Artifact Attestation — SLSA provenance v1, referrer-attached sigstore bundle (first seen on release 1.36.0) — see `signers.yaml` |

## Unsigned — no registry-attached sigstore signature (31 refs)

No `cosign tree` artifacts and no tag-scheme `.sig`/`.att`. Trusted by **digest pin
(P2) + bake (P3) + containment (P7)** only; authenticity not verifiable today.

### docker.io
- `docker.io/authelia/authelia`
- `docker.io/crowdsecurity/crowdsec`
- `docker.io/ekofr/pihole-exporter` *(added post-survey; confirmed unsigned 2026-06-13)*
- `docker.io/library/postgres`
- `docker.io/library/mongo`
- `docker.io/library/mariadb`
- `docker.io/library/redis`
- `docker.io/library/nextcloud`
- `docker.io/library/traefik`
- `docker.io/grafana/grafana`
- `docker.io/grafana/loki`
- `docker.io/grafana/promtail`
- `docker.io/jellyfin/jellyfin`
- `docker.io/deluan/navidrome`
- `docker.io/valkey/valkey`
- `docker.io/linuxserver/qbittorrent`
- `docker.io/linuxserver/syslog-ng`

### ghcr.io
- `ghcr.io/advplyr/audiobookshelf`
- `ghcr.io/lowercasename/gathio`
- `ghcr.io/immich-app/immich-server`
- `ghcr.io/immich-app/immich-machine-learning`
- `ghcr.io/immich-app/postgres`
- `ghcr.io/unpoller/unpoller`

### quay.io
- `quay.io/prometheus/alertmanager`
- `quay.io/prometheus/blackbox-exporter` *(added post-survey; confirmed unsigned 2026-06-13)*
- `quay.io/prometheus/node-exporter`
- `quay.io/prometheus/prometheus`
- `quay.io/prometheuscommunity/postgres-exporter`
- `quay.io/oliver006/redis_exporter`

### gcr.io
- `gcr.io/cadvisor/cadvisor`

### codeberg.org
- `codeberg.org/forgejo/forgejo`

## GHCR build-provenance probe (separate finding)

`gh attestation verify` against the GHCR application images returned **no GitHub
build-provenance attestations** for any of: `immich-server`, `immich-machine-learning`,
`immich/postgres`, `lowercasename/gathio`, `advplyr/audiobookshelf`,
`unpoller/unpoller` (re-confirmed 2026-06-13; `gethomepage/homepage` dropped —
service decommissioned). The outline expected "GHCR OIDC-built images" to be the most
likely first signers; that assumption is **falsified** for this fleet's GHCR
publishers — the first attestation adopter was a docker.io publisher (vaultwarden).

## Local builds (Tier 2, not registry-signed)

`localhost/alert-discord-relay`, `localhost/proton-bridge` — accountability is via
Tier 2 build-input pinning (base digest + hash-locked deps / GPG+SHA-verified RPM),
not a registry signature. Signing our own builds is noted as a future, out of Tier 3 scope.
