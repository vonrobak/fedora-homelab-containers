# Fedora Homelab: Self-Hosted Services with Podman

A learning-focused homelab project documenting the journey of building a production-ready, self-hosted infrastructure using Podman containers managed through systemd quadlets.

**Milestone:** SSH infrastructure complete - Hardware-secured authentication operational (2025-11-05)

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
- **Traefik** - Reverse proxy with Let's Encrypt SSL
- **CrowdSec** - Threat intelligence and IP blocking
- **Jellyfin** - Media streaming server
- **Grafana** - Monitoring graphical dashboards
- **Prometheus** - Monitoring and alert toolkit
- **Loki** - Log aggregation
- **AlertManager** - Alerting service linked to Discord webook
- **cAdvisor** - System metrics
- **Immich** - Image and video service
- **TinyAuth** - Forward authentication service

## Architecture

- **Container Runtime:** Podman (rootless)
- **Orchestration:** systemd quadlets
- **Authentication:** YubiKey FIDO2 (3 keys, triple redundancy)
- **Security:** Hardware-backed SSH, forward authentication, layered middleware
- **Storage:** BTRFS with snapshots.  and RAID1 (planned)
- **Networking:** Segmented Podman networks (reverse_proxy, media_services, database, auth_services)

## Documentation Structure (well defined documentation logic in ~/containers/docs/CONTRIBUTING.md and ~/containers/docs/README.md)

- `00-foundation/` - Core concepts and fundamentals
- `10-services/` - Service-specific documentation
- `20-operations/` - Operational guides and procedures
- `30-security/` - Security configurations and guides
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
