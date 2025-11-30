# Fedora Homelab: Self-Hosted Services with Podman

A learning-focused homelab project documenting the journey of building a production-ready, self-hosted infrastructure using Podman containers managed through systemd quadlets.

**Latest Milestone:** Autonomous Operations Framework Complete - Self-managing infrastructure with predictive analytics, natural language queries, and automated security hardening (2025-11-30)

## Systems

| Host | Platform | Role | Storage |
|------|----------|------|---------|
| **fedora-htpc** | Fedora Workstation 42 | Services host | BTRFS (SSD + HDD pool) |
| **fedora-jern** | Fedora Workstation 43 | Control center | Encrypted BTRFS with snapshots |
| **raspberrypi** | Debian 12 (PiOS) | DNS / Pi-hole | SD card |
| **MacBook Air** | macOS | Command center | Time Machine backups |

## Services

### Operational
- **SSH** - Hardware-secured ssh with YubiKey FIDO2 across all systems
- **Pi-hole** - DNS and ad-blocking (raspberrypi)

### Configured (fedora-htpc) - all services reachable through *.patriark.org domains registered with hostinger.com and external DNS from Cloudflare.

**Core Infrastructure:**
- **Traefik** - Reverse proxy with Let's Encrypt SSL and layered middleware
- **Authelia** - SSO server with YubiKey/WebAuthn authentication
- **CrowdSec** - Threat intelligence and IP reputation filtering

**Media & Applications:**
- **Jellyfin** - Media streaming server
- **Immich** - Photo and video management

**Monitoring & Observability:**
- **Prometheus** - Metrics collection and alerting
- **Grafana** - Visualization dashboards
- **Loki** - Log aggregation
- **Alertmanager** - Alert routing to Discord
- **cAdvisor** - Container metrics exporter
- **Trivy** - Vulnerability scanning (weekly automated scans)

**Intelligence & Automation:**
- **Autonomous Operations** - OODA loop for self-healing infrastructure
- **Predictive Analytics** - Resource exhaustion forecasting
- **Natural Language Queries** - Cached system interrogation
- **Skill Recommendation** - Context-aware automation suggestions

## Architecture

- **Container Runtime:** Podman (rootless)
- **Orchestration:** systemd quadlets with pattern-based deployment
- **Authentication:** Authelia SSO with YubiKey/WebAuthn + TOTP fallback
- **Security:** Layered middleware (CrowdSec → Rate Limiting → Authelia → Security Headers), vulnerability scanning, compliance framework
- **Storage:** BTRFS with automated snapshots and incremental backups
- **Networking:** Segmented Podman networks (reverse_proxy, media_services, auth_services, monitoring, photos)
- **Intelligence:** Autonomous OODA loop, predictive analytics, natural language query system
- **Automation:** Daily drift detection, resource forecasting, autonomous remediation with safety controls

## Key Capabilities

**Self-Managing Infrastructure:**
- **Autonomous Operations** - Daily OODA loop (Observe, Orient, Decide, Act) with confidence-based decision making and circuit breaker safety controls
- **Predictive Analytics** - Forecasts disk/memory exhaustion 7-14 days in advance with automated capacity planning
- **Natural Language Queries** - Answer system questions instantly using cached query results (e.g., "what services use the most memory?")
- **Drift Detection** - Automated daily comparison of running vs. declared state with Discord alerts

**Security & Compliance:**
- **Security Framework** - Automated security audits, ADR compliance checking, and incident response runbooks
- **Vulnerability Scanning** - Weekly CVE scanning with Trivy, Discord notifications for critical issues
- **Layered Defense** - CrowdSec IP reputation → Rate limiting → Authelia YubiKey auth → Security headers
- **Disaster Recovery** - 4 runbooks covering system SSD failure, BTRFS corruption, accidental deletion, and total catastrophe

**Operational Excellence:**
- **Pattern-Based Deployment** - 9 battle-tested deployment patterns with validation and health checks
- **Comprehensive Monitoring** - SLO tracking, burn rate alerting, monthly compliance reports
- **Weekly Intelligence Reports** - Automated Friday summaries with health scores, predictions, and recommendations
- **Skill-Based Automation** - Context-aware skill recommendations with usage analytics

## Documentation Structure (well defined documentation logic in ~/containers/docs/CONTRIBUTING.md and ~/containers/docs/README.md)

- `00-foundation/` - Core concepts and fundamentals
- `10-services/` - Service-specific documentation
- `20-operations/` - Operational guides and procedures (includes DR runbooks)
- `30-security/` - Security configurations and guides (includes incident response runbooks)
- `40-monitoring-and-documentation/` - System monitoring and docs
- `90-archive/` - Historical documentation
- `99-reports/` - System state reports and diagnostics

## Learning Goals

1. Systems design and architecture
2. Container orchestration with Podman
3. Security hardening and best practices
4. Documentation as a learning tool

---

*This is a living documentation project. Each directory contains chronologically-organized markdown files tracking the evolution of the system.*
