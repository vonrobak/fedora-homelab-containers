# Deploy Audiobookshelf + Navidrome

**Date:** 2026-02-28
**Scope:** Two new self-hosted audio services — audiobooks/podcasts + music streaming
**Result:** 27 → 29 containers, both healthy, libraries scanning

---

## Motivation

Three audio use cases had no self-hosted solution:
- **Audiobooks** — large Norwegian audiobook collection sitting unused on disk
- **Podcasts** — existing archive (Podder) plus new downloads
- **Music streaming** — 1.1TB music library only accessible via Jellyfin (wrong tool for the job)

After evaluating alternatives, selected **Audiobookshelf** (audiobooks + podcasts, single container, excellent iOS app) and **Navidrome** (music, Subsonic-compatible, native Prometheus metrics).

Secondary goal: **test the deploy-from-pattern skill** in dry-run mode to document gaps.

---

## Architecture Decisions

### Network topology
- **Audiobookshelf:** `reverse_proxy` only — standalone SQLite service, no inter-service communication, no metrics endpoint. Matches Vaultwarden pattern.
- **Navidrome:** `reverse_proxy` + `monitoring` — has native Prometheus metrics (`ND_PROMETHEUS_ENABLED`), needs scraping from monitoring network.

### Static IPs
| Service | reverse_proxy | monitoring |
|---|---|---|
| Audiobookshelf | 10.89.2.74 | — |
| Navidrome | 10.89.2.75 | 10.89.4.75 |

### Authentication
Both use native auth (no Authelia) — same pattern as Jellyfin, Immich, Nextcloud. Mobile apps (Subsonic clients, ABS iOS app) need direct auth without SSO redirect.

### Middleware chain
```
crowdsec-bouncer → rate-limit-public → compression → security-headers
```
Matches Jellyfin pattern.

### SELinux labels
- `:Z` for exclusive container data (config, metadata, database)
- `:ro,z` for shared read-only media libraries
- `:z` for writable shared directories (podcast downloads)

---

## Implementation

### Files created
- `quadlets/audiobookshelf.container` — symlinked to `~/.config/containers/systemd/`
- `quadlets/navidrome.container` — symlinked to `~/.config/containers/systemd/`

### Files modified
- `config/traefik/hosts` — added 2 host entries (audiobookshelf, navidrome)
- `config/traefik/dynamic/routers.yml` — added 2 routers + 2 services
- `config/prometheus/prometheus.yml` — added navidrome scrape job

### Directories created (BTRFS)
```
/mnt/btrfs-pool/subvol7-containers/audiobookshelf/config    (NOCOW)
/mnt/btrfs-pool/subvol7-containers/audiobookshelf/metadata   (NOCOW)
/mnt/btrfs-pool/subvol7-containers/navidrome                 (NOCOW)
/mnt/btrfs-pool/subvol4-multimedia/audiobookshelf            (podcast downloads)
```

---

## Issues Found and Fixed

### 1. Audiobookshelf listens on port 80, not 13378

The ABS documentation says default port is 13378, but the Docker image sets `PORT=80` internally. Logs confirmed: `Listening on port :80`. Fixed Traefik service URL and healthcheck accordingly.

### 2. No curl in official ABS image

Healthcheck `curl -f ... || exit 1` would fail silently. Switched to `wget --no-verbose --tries=1 --spider` which is available in the image.

### 3. Navidrome has no `/api/ping` endpoint

The plan assumed `/api/ping` existed — it returns 404. The Subsonic API at `/rest/ping` requires auth parameters. Root `/` returns 200 (or 302 for unauthenticated). Used `wget --spider http://127.0.0.1:4533/` for healthcheck.

### 4. wget resolves localhost to IPv6 first

Initial healthchecks connected to `[::1]` which returned connection refused (services bind to IPv4 only inside containers). Fixed by using `127.0.0.1` explicitly in all healthcheck URLs.

### 5. Library paths are container paths, not host paths

User initially added host paths (`/mnt/btrfs-pool/subvol4-multimedia/Lydbøker`) in ABS UI. Libraries showed empty because those paths don't exist inside the container. Correct paths are the mount destinations from the quadlet: `/audiobooks`, `/ebooks`, `/podcasts-archive`, `/podcasts`.

---

## Deploy-from-Pattern Skill Gap Analysis

Ran `deploy-from-pattern.sh --dry-run` for both services using `media-server-stack` pattern. The test revealed significant gaps between the pattern system and real deployment needs.

### What the pattern got right
- Traefik route template structure (router + service, native auth comment)
- Service naming convention (`{service}-secure`)
- TLS with letsencrypt certResolver
- General quadlet structure (Unit, Container, Service, Install sections)

### What the pattern got wrong

| Gap | Pattern output | Actual need |
|---|---|---|
| **Image** | `docker.io/jellyfin/jellyfin:latest` (hardcoded) | Service-specific image |
| **Port** | 8080 (template default) | 80 (ABS), 4533 (Navidrome) |
| **Networks** | Always 3 (reverse_proxy, media_services, monitoring) | 1 for ABS, 2 for Navidrome |
| **Volumes** | 2 generic mounts, hardcoded `:Z` | 6 mounts for ABS with mixed labels |
| **Middleware** | `rate-limit@file` | `rate-limit-public@file` + `compression@file` |
| **Health endpoint** | `/health` (Jellyfin) | `/healthcheck` (ABS), `/` (Navidrome) |
| **Template vars** | `{{SERVICE_DESCRIPTION}}`, `{{DOCS_URL}}` unresolved | Should have defaults or be required |
| **Quadlet location** | Copies directly to `~/.config/containers/systemd/` | Should use `quadlets/` + symlink |
| **Env vars** | Only `TZ` + Jellyfin-specific | Each service needs unique env vars |

### Root cause

The pattern system is **Jellyfin-shaped** — designed around one specific deployment and insufficiently parameterized. The `media-server-stack` pattern is really a "Jellyfin deployment template" rather than a generic media server pattern.

### Recommendations for improvement
1. **Separate image from pattern** — `--image` flag exists but the template still contains Jellyfin's image
2. **Make port a required variable** — no sensible default across services
3. **Network count should be configurable** — pattern should specify minimum required networks, not fixed list
4. **Volume specification needs a DSL** — `--var volume.1=/host:/container:label` or a YAML override file
5. **Health endpoint must be per-service** — add `--health-path` and `--health-port` flags
6. **Template variable validation** — fail on unresolved `{{variables}}` instead of leaving them in output
7. **Respect quadlet symlink convention** — generate in `quadlets/`, symlink to systemd dir

---

## Verification Results

| Check | Result |
|---|---|
| Container health | Both healthy |
| Static IPs | 10.89.2.74 (ABS), 10.89.2.75 + 10.89.4.75 (Navidrome) |
| Traefik DNS | Both resolve to reverse_proxy IPs |
| Routing | ABS: 200, Navidrome: 302 (redirect to login) |
| TLS | Default cert (ACME port forwarding issue — pre-existing, all services) |
| Logs | No errors |
| Prometheus | Navidrome target UP |
| Traefik routers | Both loaded (`@file`) |
| SELinux | No denials, existing services unaffected |
| Existing services | Jellyfin + Nextcloud still healthy (shared `:ro,z` mounts) |

---

## Post-Deployment State

- **Container count:** 29 (was 27)
- **Service groups:** 15 (was 13)
- **Audiobookshelf:** v2.32.1, scanning audiobooks/ebooks/podcasts
- **Navidrome:** v0.60.3, scanning 1.1TB music library
- **Estimated additional RAM:** ~200MB per service at idle
- **Next available static IP:** .76

---

## Pre-Existing Issue Noted

Traefik ACME certificate renewal is failing for **all** domains with "Timeout during connect (likely firewall problem)". Port forwarding to port 80 appears to be blocked upstream. This is not related to this deployment but should be investigated.
