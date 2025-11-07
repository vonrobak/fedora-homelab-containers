# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A learning-focused homelab project building production-ready, self-hosted infrastructure using Podman containers managed through systemd quadlets. Platform: Fedora Workstation 42.

**Current Services:** Traefik (reverse proxy + CrowdSec), Jellyfin (media server), TinyAuth (authentication), Prometheus/Grafana/Loki (monitoring), Alertmanager (alerting)

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
- `systemd-reverse_proxy` - Traefik and externally-accessible services
- `systemd-media_services` - Jellyfin and media processing
- `systemd-auth_services` - TinyAuth, authentication services
- `systemd-monitoring` - Prometheus, Grafana, Loki, Alertmanager, exporters

Services join networks based on trust/access requirements. Services can be on multiple networks.

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

The `docs/` directory uses a **hybrid structure** combining topical reference with chronological learning logs.

### Directory Organization

- `00-foundation/` - Podman, networking, pods, quadlets fundamentals
- `10-services/` - Service-specific guides and deployment logs
- `20-operations/` - Operational procedures, architecture, backup strategy
- `30-security/` - Security configurations, incidents, hardening
- `40-monitoring-and-documentation/` - Monitoring stack, project state
- `90-archive/` - Superseded documentation (with archival metadata)
- `99-reports/` - Point-in-time system state snapshots

### Subdirectory Structure

Each category directory contains:
- **`guides/`** - Living reference documentation (updated in place, no date prefix)
- **`journal/`** - Dated learning logs and progress reports (immutable, dated)
- **`decisions/`** - Architecture Decision Records / ADRs (immutable, dated)

### Document Types & Naming

**Living Documents (guides/):**
```
<topic>.md
Examples: jellyfin.md, backup-strategy.md, middleware-patterns.md
```

**Dated Documents (journal/, decisions/):**
```
YYYY-MM-DD-<description>.md
Examples: 2025-11-07-monitoring-deployment.md
```

**Reports (99-reports/):**
```
YYYY-MM-DD-<type>-<description>.md
Examples: 2025-11-07-system-state.md
```

### Documentation Policies

1. **Guides are living** - Update in place when information changes
2. **Journals are immutable** - Never edit after creation (append-only log)
3. **ADRs are permanent** - Architecture decisions never edited, only superseded
4. **Reports are snapshots** - Point-in-time system state, never updated
5. **Archive with metadata** - Include archival reason and superseding document

**Full guide:** See `docs/CONTRIBUTING.md` for detailed conventions and templates.

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
