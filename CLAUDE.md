# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Philosophy

This is a digital sovereignty project — self-hosted infrastructure built for independence, not convenience. Every service replaces a cloud dependency. Every decision should:
- **Increase owner understanding** — prefer learning over turnkey solutions
- **Minimize external dependencies** — self-host when the trade-off is reasonable
- **Preserve data ownership** — all data lives on owned hardware with tested backups
- **Build layered resilience** — no single failure should take down the system

## Project Overview

A learning-focused homelab building production-ready, self-hosted infrastructure using Podman containers managed through systemd quadlets. Platform: Fedora Workstation 43.

**Current Services (29 containers, 16 service groups):**
- **Core Infrastructure:** Traefik (reverse proxy), CrowdSec (threat intel), Authelia + Redis (SSO + YubiKey MFA)
- **Applications:** Nextcloud + MariaDB + Redis (file sync), Vaultwarden (passwords), Jellyfin (media), Immich + PostgreSQL + Redis + ML (photos), Gathio + MongoDB (events), Homepage (dashboard)
- **Audio:** Audiobookshelf (audiobooks/podcasts), Navidrome (music streaming)
- **Downloads:** qBittorrent (torrent client)
- **Home Automation:** Home Assistant (smart home; Matter Server decommissioned 2026-05-18 pending matter.js successor, Plejd integration planned)
- **Monitoring:** Prometheus, Grafana, Loki, Alertmanager, Promtail, cAdvisor, Node Exporter, UnPoller, Alert Discord Relay

## Architecture

### Container Orchestration

- **Runtime:** Podman (rootless containers, UID 1000, SELinux enforcing)
- **Orchestration:** systemd quadlets (`~/containers/quadlets/` symlinked to `~/.config/containers/systemd/`)
- **Management:** `systemctl --user` commands
- **Service Discovery:** Traefik Docker provider with Podman socket

### Security Architecture

**Layered Middleware** (fail-fast principle):
```
Internet → Port Forward (80/443)
  → [1] CrowdSec IP Reputation (cache lookup - fastest)
  → [2] Rate Limiting (tiered: 100-200 req/min)
  → [3] Authelia SSO (YubiKey/WebAuthn + TOTP - phishing-resistant)
  → [4] Security Headers (applied on response)
  → Backend Service
```

Each layer is more expensive than the last. Reject malicious IPs before wasting resources on auth checks.

### Network Segmentation

8 networks for trust boundaries (see `AUTO-NETWORK-TOPOLOGY.md`):
- `reverse_proxy` - Internet-facing services + Traefik (default route for internet access)
- `monitoring` - Prometheus, Grafana, Loki, exporters (Internal=true, no internet)
- `auth_services` - Authelia + Redis (isolated auth backend)
- `media_services` - Jellyfin | `photos` - Immich stack
- `nextcloud` - Nextcloud + MariaDB + Redis
- `home_automation` - Home Assistant + Matter Server | `gathio` - Gathio + MongoDB

### Traefik Configuration

**Static config:** `config/traefik/traefik.yml` | **Dynamic config:** `config/traefik/dynamic/` (auto-reloads):
- `routers.yml` - All service routing rules
- `middleware.yml` - CrowdSec, rate limiting, auth, security headers
- `tls.yml` - TLS 1.2+
- `rate-limit.yml` - Tiered (global: 50/min, auth: 10/min, API: 30/min, public: 200/min)
- `security-headers-strict.yml` - CSP/HSTS

## Critical Conventions

### Traefik Routing (ADR-016)

**ALL Traefik routing is defined in `config/traefik/dynamic/routers.yml`, NEVER in container labels.**

Why: Separation of concerns (quadlets = deployment, Traefik = routing), centralized security auditing, fail-fast middleware ordering enforced consistently, single source of truth.

**To add a new route:** Edit `config/traefik/dynamic/routers.yml` — add router under `http.routers` and service under `http.services`. Traefik auto-reloads within 60s.

### Deployment Procedure

1. Create quadlet file in `~/containers/quadlets/` (NO Traefik labels)
2. Add route to `config/traefik/dynamic/routers.yml` with standard middleware chain:
   - **Default (Authelia):** `crowdsec-bouncer@file, rate-limit@file, authelia@file, security-headers@file` — used by qBittorrent, Homepage, Grafana, etc.
   - **Native auth** (Jellyfin, Nextcloud, Immich, Vaultwarden, HA, Navidrome, Audiobookshelf): `crowdsec-bouncer@file, rate-limit-public@file, compression@file, security-headers@file` — NO authelia
3. `systemctl --user daemon-reload && systemctl --user enable --now <service>.service`
4. Verify: `curl -I https://service.patriark.org`

Pattern-based deployment available via `homelab-deployment` skill (see `.claude/skills/homelab-deployment/`).

### Update Strategy

Governed by **ADR-030 (Container Supply-Chain Trust Model):** **fully implemented (Tier 1 + Tier 2)** — every registry image is digest-pinned (`tag@sha256:…`, tag = discovery handle, digest = execution contract), all `AutoUpdate=registry` lines are stripped, and the 2 local builds pin their `FROM` bases by digest. Nothing updates automatically; superseded ADR-015's `:latest`/auto-update trust model. A pre-commit hook enforces the invariants (egress tier pinned + de-automated, local bases pinned, no signature failures); `docs/AUTO-IMAGE-PIN-INDEX.md` is the daily audit view.

**Deliberate update loop (ADR-036)** — single entry point: `scripts/monthly-update.sh` (chains all steps below interactively; Discord nudges via `ImageUpdatesBaked*` alerts when ≥5 updates are baked):
1. **Discover:** `scripts/check-image-updates.sh` — skopeo digest-diff, notify-only; annotates each candidate BAKED/TOO-YOUNG against the P3 bake policy (`config/supply-chain/bake-policy.yml`: egress 7d, internal 3d) and writes machine-readable JSON
2. **Adopt:** `scripts/adopt-baked.sh [--dry-run]` — wave-ordered batch (plumbing → apps → core → DBs + dependent restarts), per-service health + HTTP verification, halt-on-failure; P6 signature gate applies via `pin-container-image.sh`
3. **Exception lane:** a release fixing a known-exploited CVE in an egress-tier service may skip the bake via `--allow-young <svc>` — commit message must name the CVE
4. **Single-service path:** `scripts/pin-container-image.sh <svc> --adopt <digest> --apply` + daemon-reload + restart

**Class-specific rules:**
- **Databases:** PostgreSQL, MariaDB, MongoDB pinned to major-version tags; major upgrades are explicit migration projects (ADR-029 dump backbone), never casual bumps
- **Immich:** server + ML + postgres version-locked as a set (tight coupling)
- **Local builds** (proton-bridge, alert-discord-relay): Tier 2 — built locally from digest-pinned bases, no registry trust

Rollback: `git revert` of the digest line + restart; BTRFS snapshots as second path. Remaining ADR-030 work: Tier 3/4 (broader signature coverage). Workflow: `scripts/update-before-reboot.sh` before DNF updates (ensures pinned digests present, never re-floats them).

### Architecture Decision Records

**Architectural decisions recorded as ADRs — latest is ADR-036** (see `docs/*/decisions/` for full details; number new ADRs sequentially from the latest)

**Design-Guiding ADRs (affect future decisions):**
- **ADR-001:** Rootless Containers — UID 1000, `:Z` SELinux labels on all mounts
- **ADR-002:** Systemd Quadlets Over Docker Compose
- **ADR-003:** Monitoring Stack — Prometheus + Grafana + Loki
- **ADR-006:** YubiKey-First Authentication — FIDO2/WebAuthn for Authelia SSO
- **ADR-008:** CrowdSec Security Architecture — fail-fast middleware ordering
- **ADR-009:** Config vs Data Directory Strategy
- **ADR-010:** Pattern-Based Deployment — 9 templates with validation
- **ADR-016:** Configuration Design Principles — **CRITICAL:** ALL routing in dynamic config, NEVER in labels
- **ADR-018:** Static IP Multi-Network Services — /etc/hosts override for predictable routing
- **ADR-019:** Filesystem Permission Model — POSIX ACLs for container access
- **ADR-021:** Urd Backup Tool — Rust-based BTRFS Time Machine replaces shell script (supersedes ADR-020 implementation)
- **ADR-030:** Container Supply-Chain Trust Model — digest pinning, deliberate (de-automated) updates, cooling-off interval, graduated signature verification (supersedes ADR-015 trust model)
- **ADR-031:** DNS Resolver First-Class & HA — redundancy-before-monitoring, active/passive keepalived VIP, alert-path resolver must be independent of the monitored resolver, resolver managed-as-code + SSO admin (status: Accepted, implementation phased)
- **ADR-036:** Bake Policy & Exception Lane (amends ADR-030) — P3 cooling-off codified (egress 7d / internal 3d in `bake-policy.yml`), wave-ordered batch adoption via `adopt-baked.sh`, security-release CVE override with `--allow-young`

Check if an ADR exists before proposing changes. Reference the ADR and explain what changed if suggesting alternatives. New decisions get new ADRs (don't edit existing ones).

## Key Design Principles

1. **Rootless containers** — all services run as user processes
2. **Middleware ordering** — fail-fast: CrowdSec → rate limit → auth → headers
3. **Configuration as code** — all configs in Git (secrets excluded via .gitignore)
4. **Health-aware deployment** — scripts verify service readiness
5. **Zero-trust model** — authentication required for all internet-accessible services
6. **Autonomous operations** — OODA loop with confidence-based decisions and safety controls
7. **Defense in depth** — IP reputation, rate limiting, authentication, headers, scanning
8. **Observable system** — natural language queries, comprehensive metrics, audit trails

**Lesson capture:** When a session produces a durable, generalizable lesson (incident, postmortem, surprising root cause), append it to `docs/96-project-supervisor/lessons.md` following its "How to add a lesson" protocol. Consult that file before redesigning alerting, storage, security layers, or debugging strategy — it includes superseded approaches not to repeat.

## Common Gotchas

**SELinux `:Z` label required** on all bind mounts in quadlets (rootless + SELinux enforcing). Without it: `permission denied`.

**First `Network=` line gets default route.** Put `reverse_proxy` first if the container needs internet access. Wrong order = container can't reach external services.

**BTRFS NOCOW for databases.** Database directories (Prometheus, Loki, PostgreSQL) need `chattr +C` before first use. COW causes severe fragmentation on DB write patterns.

**Quadlet changes need daemon-reload.** After editing `.container` files: `systemctl --user daemon-reload && systemctl --user restart <service>.service`.

**Multi-network services get untrusted proxy errors** if Podman's DNS returns the wrong network IP. Solution: static IPs + Traefik `/etc/hosts` override (ADR-018). Already implemented for HA and other multi-network containers.

## Operations

### Key Scripts

```bash
./scripts/homelab-intel.sh                     # Health scoring (0-100) + recommendations
./scripts/query-homelab.sh "<natural language>" # Query system state (cached)
./scripts/autonomous-check.sh --verbose        # OODA loop assessment
./scripts/check-drift.sh [service]             # Config drift detection
./scripts/security-audit.sh                    # Security audit (53 checks, --level 1/2/3)
./scripts/auto-doc-orchestrator.sh             # Regenerate all docs (~2s)
```

Full script catalog: `docs/20-operations/guides/automation-reference.md`

### Troubleshooting: Service Not Accessible

1. Check service running: `systemctl --user status <service>.service`
2. Check Traefik routing: Dashboard at `traefik.patriark.org` — verify router rule exists
3. Check DNS: `dig <subdomain>.patriark.org` (should return public IP)
4. Check firewall: `sudo firewall-cmd --list-all` (ports 80/443 must be open)
5. Check logs: `journalctl --user -u <service>.service -n 50`

## Skills & Subagents

**Skills:** `homelab-deployment` (deploy), `homelab-intelligence` (health), `security-auditor` (53-check audit), `systematic-debugging` (root cause), `autonomous-operations` (OODA), `git-advanced-workflows` (git ops)

**Subagents:**
- `infrastructure-architect` — consult before deploying new services or changing architecture
- `service-validator` — run after deployment for 7-level verification
- `code-simplifier` — refactor after deployment to prevent config bloat

**Slash command:** `/commit-push-pr` — stages, commits (GPG), pushes, creates PR

## Quick Reference

| Category | Location |
|----------|----------|
| Lessons learned | `docs/96-project-supervisor/lessons.md` (L-NNN, incl. superseded) |
| Service catalog | `AUTO-SERVICE-CATALOG.md` (updated daily) |
| Network topology | `AUTO-NETWORK-TOPOLOGY.md` (diagrams, 8 networks) |
| Dependency graph | `AUTO-DEPENDENCY-GRAPH.md` (4-tier, critical paths) |
| Architecture overview | `docs/20-operations/guides/homelab-architecture.md` |
| Script catalog | `docs/20-operations/guides/automation-reference.md` |
| Autonomous ops | `docs/20-operations/guides/autonomous-operations.md` |
| Drift detection | `docs/20-operations/guides/drift-detection-workflow.md` |
| SLO framework | `docs/40-monitoring-and-documentation/guides/slo-framework.md` |
| Monitoring stack | `docs/40-monitoring-and-documentation/guides/monitoring-stack.md` |
| Security guides | `docs/30-security/guides/` (7 guides + 5 IR runbooks) |
| DR runbooks | `docs/20-operations/runbooks/` (4 DR runbooks) |
| Documentation index | `AUTO-DOCUMENTATION-INDEX.md` |
| Contributing guide | `CONTRIBUTING.md` |
