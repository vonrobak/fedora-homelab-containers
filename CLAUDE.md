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

**Current Services (30 containers, 16 service groups):**
- **Core Infrastructure:** Traefik (reverse proxy), CrowdSec (threat intel), Authelia + Redis (SSO + YubiKey MFA)
- **Applications:** Nextcloud + MariaDB + Redis (file sync), Vaultwarden (passwords), Jellyfin (media), Immich + PostgreSQL + Redis + ML (photos), Gathio + MongoDB (events), Homepage (dashboard)
- **Audio:** Audiobookshelf (audiobooks/podcasts), Navidrome (music streaming)
- **Downloads:** qBittorrent (torrent client)
- **Home Automation:** Home Assistant + Matter Server (smart home, Plejd integration planned)
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
- `tls.yml` - TLS 1.2+ | `rate-limit.yml` - Tiered (global: 50/min, auth: 10/min, API: 30/min, public: 200/min) | `security-headers-strict.yml` - CSP/HSTS

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

Most services use `:latest` tags. **Exceptions (pinned, manual upgrade only):**
- **Databases:** PostgreSQL, MariaDB (major version migrations required)
- **Immich:** Pinned to specific version (tight ML + postgres coupling)

See ADR-015 for full rationale. Workflow: `scripts/update-before-reboot.sh` before DNF updates.

### Architecture Decision Records

**19 ADRs documenting architectural decisions** (see `docs/*/decisions/` for full details)

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
