# Fedora Homelab: Self-Hosted Services with Podman

Self-hosted infrastructure built for independence — replacing cloud dependencies with owned hardware, tested backups, and full data sovereignty. A learning-focused project documenting the journey of building production-ready infrastructure using rootless Podman containers managed through systemd quadlets.

## How to Navigate This Repository

New here? The documentation is organized as a progression — start broad, then go deep:

1. **[Homelab Architecture](docs/20-operations/guides/homelab-architecture.md)** — the big picture: how the pieces fit together
2. **[Podman Fundamentals](docs/00-foundation/guides/podman-fundamentals.md)** — rootless containers and quadlets explained
3. **Auto-generated system views** (regenerated daily): [Service Catalog](docs/AUTO-SERVICE-CATALOG.md) · [Network Topology](docs/AUTO-NETWORK-TOPOLOGY.md) · [Dependency Graph](docs/AUTO-DEPENDENCY-GRAPH.md) · [Documentation Index](docs/AUTO-DOCUMENTATION-INDEX.md)
4. **Architecture Decision Records** (in `docs/*/decisions/`) — the *why* behind every significant choice, including the mistakes and reversals

Want to build something similar? The **[Pattern Selection Guide](docs/10-services/guides/pattern-selection-guide.md)** and quadlet templates in `quadlets/` are the practical starting point — each service is a small, readable systemd unit file you can adapt.

## Infrastructure

| Host | Platform | Role | Storage |
|------|----------|------|---------|
| Primary server | Fedora Workstation 43 | Container host (37 containers) | BTRFS (SSD + 14.5TB HDD pool) |
| Control center | Fedora Workstation 43 | Workstation | Encrypted BTRFS |
| DNS server | Debian 12 (PiOS) | Pi-hole (DNS + DoH upstream) | SD card |
| Laptop | macOS | Command center | Time Machine |

## Services (17 groups, 37 containers)

**Core Infrastructure:**
- **Traefik** - Reverse proxy with Let's Encrypt SSL and layered middleware
- **Authelia** - SSO with YubiKey/WebAuthn hardware authentication (+ Redis)
- **CrowdSec** - Threat intelligence and IP reputation filtering

**Applications:**
- **Nextcloud** - File sync and collaboration (with MariaDB, Redis)
- **Jellyfin** - Media streaming server
- **Immich** - Photo and video management (with ML, PostgreSQL, Redis)
- **Vaultwarden** - Password manager
- **Gathio** - Event management (with MongoDB)
- **Forgejo** - Self-hosted git forge (with PostgreSQL) — private mirror and sovereign code ledger

**Audio:**
- **Audiobookshelf** - Audiobooks, ebooks, and podcasts
- **Navidrome** - Music streaming server

**Downloads:**
- **qBittorrent** - Torrent client

**Home Automation:**
- **Home Assistant** - Smart home hub

**Mail:**
- **Proton Bridge** - Locally built bridge for self-hosted mail integration

**Monitoring & Observability:**
- **Prometheus + Grafana + Loki** - Full observability stack
- **Alertmanager + Discord relay** - Alert routing and notification
- **Exporters** - cAdvisor, Node Exporter, UnPoller, Blackbox, Postgres, Redis, Pi-hole, UniFi syslog

**Autonomous Operations:**
- OODA loop for daily automated assessment and remediation
- Predictive analytics for resource exhaustion forecasting
- Natural language system queries
- Drift detection and health scoring

## Architecture

- **Container Runtime:** Podman (rootless, UID 1000, SELinux enforcing)
- **Orchestration:** Systemd quadlets with pattern-based deployment templates
- **Authentication:** Authelia SSO with YubiKey/WebAuthn + TOTP fallback
- **Security:** Defense-in-depth — CrowdSec IP reputation, tiered rate limiting, MFA, security headers, network segmentation, container isolation, firewall
- **Networking:** 12 segmented Podman networks for trust boundaries, including a restricted-egress tier for services with no legitimate internet-egress need (outbound blocked by nftables inside the rootless network namespace)
- **Supply chain:** Every container image digest-pinned; no automatic updates — a deliberate monthly update loop with a cooling-off ("bake") period, wave-ordered adoption, and graduated signature verification
- **Secrets:** Runtime secrets sourced from a self-hosted OpenBao vault on the host substrate; containers consume them as podman secrets without any secret material at rest in this repo
- **Storage:** BTRFS with automated snapshots; backups via [Urd](https://github.com/vonrobak/urd), a purpose-built Rust BTRFS backup tool
- **Monitoring:** SLO tracking with error budgets, burn-rate alerting, monthly compliance reports
- **Automation:** 60+ systemd timers, 85 scripts, daily autonomous operations

### Request Path (fail-fast middleware ordering)

```
Internet → Port Forward (80/443)
  → [1] CrowdSec IP reputation   (cheapest check first)
  → [2] Rate limiting            (tiered per route class)
  → [3] Authelia SSO             (YubiKey/WebAuthn — phishing-resistant)
  → [4] Security headers         (applied on response)
  → Backend service
```

Each layer is more expensive than the last: malicious IPs are rejected before any resources are spent on authentication.

## Key Capabilities

**Self-Managing Infrastructure:**
- Daily OODA loop (Observe, Orient, Decide, Act) with confidence-based decision making
- Predictive analytics forecasting disk/memory exhaustion 7-14 days ahead
- Automated drift detection with Discord alerts
- Circuit breaker safety controls and BTRFS snapshots before destructive actions

**Security & Compliance:**
- 53-check automated security audits across 7 categories
- Digest-pinned supply chain with egress observability (unexpected outbound destinations alert)
- Weekly CVE scanning with severity-based alerting
- Incident response and disaster recovery runbooks, with validated DR (6-minute RTO)

**Operational Excellence:**
- Pattern-based deployment with validation and 7-level health verification
- SLO tracking with error budgets and burn-rate alerting
- Architecture Decision Records documenting every key choice — and the reversals
- Weekly intelligence reports with health scores and predictions

## Documentation Structure

See [CONTRIBUTING.md](docs/CONTRIBUTING.md) for conventions.

- `00-foundation/` - Core concepts, fundamentals, foundational ADRs
- `10-services/` - Service-specific guides and deployment patterns
- `20-operations/` - Operational guides, DR runbooks, automation reference
- `30-security/` - Security guides, IR runbooks, CrowdSec field manuals
- `40-monitoring-and-documentation/` - SLO framework, monitoring stack

Each section carries its own `guides/` and `decisions/` (ADRs). The `AUTO-*.md` files at the docs root are regenerated daily from the live system. Internal working notes (journals, plans, reports) live in a private knowledge vault outside this repository — what you see here is the curated, public-safe layer.

## Learning Goals

1. **Digital sovereignty** — owning infrastructure and data end-to-end
2. Systems design and container orchestration with Podman
3. Security hardening, threat modeling, and incident response
4. Autonomous operations and observability engineering
5. Documentation as a learning accelerator

---

*This is a living documentation project. Each directory contains organized markdown files tracking the evolution of a homelab from first container to autonomous infrastructure.*
