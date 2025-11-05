# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A learning-focused homelab project building production-ready, self-hosted infrastructure using Podman containers managed through systemd quadlets. Platform: Fedora Workstation 42.

**Current Services:** Traefik (reverse proxy + CrowdSec), Jellyfin (media server), TinyAuth (authentication)

## Architecture

### Container Orchestration Model

This project uses **systemd quadlets** rather than docker-compose or Makefiles:

- **Runtime:** Podman (rootless containers)
- **Orchestration:** systemd user services (`~/.config/containers/systemd/`)
- **Management:** `systemctl --user` commands
- **Service Discovery:** Traefik Docker provider with Podman socket

**Deployment Pattern:**
1. Create container with `podman run` (including Traefik labels)
2. Generate systemd units: `podman generate systemd --name <container> --files`
3. Reload systemd: `systemctl --user daemon-reload`
4. Enable/start: `systemctl --user enable --now <service.service>`

### Layered Security Architecture

Requests flow through ordered middleware layers (fail-fast principle):

```
Internet → Port Forward (80/443)
  ↓
[1] CrowdSec IP Reputation (cache lookup - fastest)
  ↓
[2] Rate Limiting (memory check)
  ↓
[3] TinyAuth Authentication (database + bcrypt - most expensive)
  ↓
[4] Security Headers (applied on response)
  ↓
Backend Service
```

**Why this order matters:** Each layer is more expensive than the last. Reject malicious IPs immediately (CrowdSec) before wasting resources on auth checks.

### Network Segmentation

Services are isolated into logical networks:
- `reverse_proxy` - Traefik and externally-accessible services
- `media_services` - Jellyfin and media processing
- `authentication` - TinyAuth
- `database` - Data persistence

Services join networks based on trust/access requirements.

### Traefik Configuration Structure

**Static config:** `/config/traefik/traefik.yml` (entry points, providers, Let's Encrypt)

**Dynamic config:** `/config/traefik/dynamic/` (watched by Traefik):
- `middleware.yml` - CrowdSec, rate limiting, auth, security headers
- `routers.yml` - Service routing rules
- `security-headers-strict.yml` - CSP, HSTS, X-Frame-Options
- `tls.yml` - TLS 1.2+ with modern ciphers
- `rate-limit.yml` - Tiered rate limits (global: 50/min, auth: 10/min, API: 30/min)

**Service autodiscovery:** Containers use labels for Traefik registration:
```bash
--label "traefik.enable=true"
--label "traefik.http.routers.service-name.rule=Host(\`subdomain.domain.com\`)"
--label "traefik.http.services.service-name.loadbalancer.server.port=8096"
```

## Common Commands

### Service Deployment

```bash
# Full Jellyfin + Traefik deployment
./scripts/deploy-jellyfin-with-traefik.sh

# Manual container creation with Traefik integration
podman run -d \
  --name jellyfin \
  --network reverse_proxy \
  --label "traefik.enable=true" \
  --label "traefik.http.routers.jellyfin.rule=Host(\`jellyfin.example.com\`)" \
  --label "traefik.http.routers.jellyfin.middlewares=crowdsec-bouncer@file,rate-limit@file,tinyauth@file" \
  -v ./config/jellyfin/config:/config:Z \
  jellyfin/jellyfin

# Generate systemd units
cd ~/.config/containers/systemd/
podman generate systemd --name jellyfin --files --new
systemctl --user daemon-reload
systemctl --user enable --now container-jellyfin.service
```

### Service Management

```bash
# Jellyfin management
./scripts/jellyfin-manage.sh {start|stop|restart|status|logs|follow}

# Generic systemd management
systemctl --user status container-jellyfin.service
systemctl --user restart container-traefik.service
journalctl --user -u container-jellyfin.service -f

# Container operations
podman ps                           # List running containers
podman logs -f jellyfin             # Follow logs
podman healthcheck run jellyfin     # Check container health
```

### Diagnostics and Auditing

```bash
# Comprehensive system diagnostics (generates timestamped report in docs/99-reports/)
./scripts/homelab-diagnose.sh

# Security compliance audit
./scripts/security-audit.sh

# Pod status with network/port info
./scripts/show-pod-status.sh

# System inventory (BTRFS, storage, firewall, versions)
./scripts/survey.sh

# Service-specific status
./scripts/jellyfin-status.sh

# Storage diagnostics
./scripts/collect-storage-info.sh
```

### Network Management

```bash
# List networks
podman network ls

# Inspect network
podman network inspect reverse_proxy

# Connect container to network
podman network connect media_services jellyfin
```

### Traefik Operations

```bash
# Reload dynamic configuration (Traefik watches for changes automatically)
# Just edit files in config/traefik/dynamic/ and save

# View Traefik logs
podman logs -f traefik

# Access Traefik dashboard
# Navigate to traefik.patriark.org (requires authentication)

# Test certificate renewal
# Let's Encrypt auto-renews. Check acme.json modification time:
ls -lh /path/to/letsencrypt/acme.json
```

## Git Workflow

**Branch naming:**
- Features: `feature/description`
- Bugfixes: `bugfix/description`
- Documentation: `docs/description`
- Hotfixes: `hotfix/description`

**Standard workflow:**
```bash
# Start new work
git checkout main
git pull origin main
git checkout -b feature/your-feature

# Commit changes
git add <files>
git commit -m "Descriptive message"  # GPG signing enabled

# Push and create PR
git push -u origin feature/your-feature
# Then create PR on GitHub
```

**Merging strategy:**
- "Squash and merge" for small changes
- "Create merge commit" for feature branches
- Auto-delete branches after merge

**Security:** SSH authentication (Ed25519), GPG commit signing, strict host key checking enabled.

## Documentation Structure

The `docs/` directory contains 61 markdown files organized chronologically:

- `00-foundation/` - Podman, networking, pods, quadlets fundamentals
- `10-services/` - Service-specific guides (Jellyfin, Traefik)
- `20-operations/` - Architecture decisions, storage, operational procedures
- `30-security/` - TinyAuth implementation, security configurations
- `40-monitoring-and-documentation/` - Monitoring setup, documentation index
- `90-archive/` - Historical documentation
- `99-reports/` - Generated diagnostic reports

Files are date-prefixed (YYYYMMDD) for chronological tracking.

## Key Design Principles

1. **Rootless containers** - All services run as user processes for enhanced security
2. **Middleware ordering** - Arrange by execution cost (fail-fast: CrowdSec → rate limit → auth)
3. **Configuration as code** - All configs in Git (secrets excluded via .gitignore)
4. **Health-aware deployment** - Scripts verify service readiness before completion
5. **Zero-trust model** - Authentication required for all internet-accessible services

## Secrets Management

Secrets are excluded from Git via `.gitignore`:
- `*.key`, `*.pem`, `*.crt`
- `*secret*`, `*password*`, `*.env`
- `acme.json` (Let's Encrypt certificates)
- `*.db`, `*.sqlite*` (databases)
- `*.mmdb` (CrowdSec data)

Store secrets outside the repository or use environment variables.
