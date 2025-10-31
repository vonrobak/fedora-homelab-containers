# Fedora Homelab: Self-Hosted Services with Podman

A learning-focused homelab project documenting the journey of building a production-ready, self-hosted infrastructure using Podman containers managed through systemd quadlets.

## Current Services

- **Traefik** - Reverse proxy with CrowdSec integration
- **Jellyfin** - Media server
- **TinyAuth** - Authentication service

## Architecture

- Platform: Fedora Workstation 42
- Container Runtime: Podman
- Service Management: systemd quadlets
- Reverse Proxy: Traefik with Let's Encrypt
- Security: CrowdSec Bouncer, rate limiting

## Documentation Structure

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
