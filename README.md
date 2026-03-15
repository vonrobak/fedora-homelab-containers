# Fedora Homelab: Self-Hosted Services with Podman

Self-hosted infrastructure built for independence — replacing cloud dependencies with owned hardware, tested backups, and full data sovereignty. A learning-focused project documenting the journey of building production-ready infrastructure using rootless Podman containers managed through systemd quadlets.

## Infrastructure

| Host | Platform | Role | Storage |
|------|----------|------|---------|
| Primary server | Fedora Workstation 43 | Container host (30 containers) | BTRFS (SSD + 14.5TB HDD pool) |
| Control center | Fedora Workstation 43 | Workstation | Encrypted BTRFS |
| DNS server | Debian 12 (PiOS) | Pi-hole | SD card |
| Laptop | macOS | Command center | Time Machine |

## Services (16 groups, 30 containers)

**Core Infrastructure:**
- **Traefik** - Reverse proxy with Let's Encrypt SSL and layered middleware
- **Authelia** - SSO with YubiKey/WebAuthn hardware authentication
- **CrowdSec** - Threat intelligence and IP reputation filtering

**Applications:**
- **Nextcloud** - File sync and collaboration (with MariaDB, Redis)
- **Jellyfin** - Media streaming server
- **Immich** - Photo and video management (with ML, PostgreSQL, Redis)
- **Vaultwarden** - Password manager
- **Gathio** - Event management
- **Homepage** - Dashboard

**Audio:**
- **Audiobookshelf** - Audiobooks, ebooks, and podcasts
- **Navidrome** - Music streaming server

**Downloads:**
- **qBittorrent** - Torrent client

**Home Automation:**
- **Home Assistant** - Smart home hub (with Matter Server)

**Monitoring & Observability:**
- **Prometheus + Grafana + Loki** - Full observability stack
- **Alertmanager** - Alert routing to Discord
- **cAdvisor + Node Exporter + UnPoller** - Metrics exporters

**Autonomous Operations:**
- OODA loop for daily automated assessment and remediation
- Predictive analytics for resource exhaustion forecasting
- Natural language system queries
- Drift detection and health scoring

## Architecture

- **Container Runtime:** Podman (rootless, UID 1000, SELinux enforcing)
- **Orchestration:** Systemd quadlets with 9 pattern-based deployment templates
- **Authentication:** Authelia SSO with YubiKey/WebAuthn + TOTP fallback
- **Security:** 7-layer defense-in-depth (CrowdSec, rate limiting, MFA, headers, network segmentation, container isolation, firewall)
- **Networking:** 8 segmented Podman networks for trust boundaries
- **Storage:** BTRFS with automated daily snapshots and incremental backups
- **Monitoring:** SLO tracking (13 SLOs across 8 services), burn-rate alerting, monthly compliance
- **Automation:** 53 systemd timers, 65+ scripts, daily autonomous operations

## Key Capabilities

**Self-Managing Infrastructure:**
- Daily OODA loop (Observe, Orient, Decide, Act) with confidence-based decision making
- Predictive analytics forecasting disk/memory exhaustion 7-14 days ahead
- Automated drift detection with Discord alerts
- Circuit breaker safety controls and BTRFS snapshots before destructive actions

**Security & Compliance:**
- 53-check automated security audits across 7 categories
- Weekly CVE scanning with severity-based alerting
- 10 runbooks (4 disaster recovery, 5 incident response, + procedures)
- Validated disaster recovery with 6-minute RTO

**Operational Excellence:**
- Pattern-based deployment with validation and health checks
- SLO tracking with error budgets and burn-rate alerting
- 19 Architecture Decision Records documenting key choices
- Weekly intelligence reports with health scores and predictions

## Documentation Structure

See [CONTRIBUTING.md](docs/CONTRIBUTING.md) for conventions.

- `00-foundation/` - Core concepts, fundamentals, ADRs
- `10-services/` - Service-specific guides (22 services documented)
- `20-operations/` - Operational guides, DR runbooks, automation reference
- `30-security/` - Security guides, IR runbooks, CrowdSec field manuals
- `40-monitoring-and-documentation/` - SLO framework, monitoring stack
- `90-archive/` - Historical documentation
- `97-plans/` - Strategic planning
- `98-journals/` - Chronological learning log
- `99-reports/` - Automated reports and snapshots

## Learning Goals

1. **Digital sovereignty** — owning infrastructure and data end-to-end
2. Systems design and container orchestration with Podman
3. Security hardening, threat modeling, and incident response
4. Autonomous operations and observability engineering
5. Documentation as a learning accelerator

---

*This is a living documentation project. Each directory contains organized markdown files tracking the evolution of a homelab from first container to autonomous infrastructure.*
