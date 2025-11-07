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

# System intelligence report (health scoring + recommendations)
./scripts/homelab-intel.sh

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

## Troubleshooting Workflow

### Service Not Accessible Externally

1. **Check service is running:**
   ```bash
   podman ps | grep <service>
   systemctl --user status <service>.service
   ```

2. **Check Traefik routing:**
   - Dashboard: http://localhost:8080/dashboard/
   - Look for service in HTTP Routers section
   - Verify router rule matches expected hostname

3. **Check DNS resolution:**
   ```bash
   dig <subdomain>.patriark.org
   # Should return your public IP
   ```

4. **Check firewall:**
   ```bash
   sudo firewall-cmd --list-all
   # Ports 80/443 must be open
   ```

5. **Check logs:**
   ```bash
   journalctl --user -u <service>.service -n 50
   podman logs <service> --tail 50
   ```

### High Disk Usage

1. **Check system SSD (128GB limit):**
   ```bash
   df -h /
   # If >80%, investigate immediately
   ```

2. **Check BTRFS pool:**
   ```bash
   btrfs fi usage -T /mnt/btrfs-pool
   ```

3. **Check container data:**
   ```bash
   du -sh ~/containers/data/*
   du -sh ~/containers/config/*
   ```

4. **Check logs:**
   ```bash
   du -sh ~/containers/data/backup-logs/
   journalctl --user --disk-usage
   ```

5. **Cleanup options:**
   ```bash
   # Prune unused containers/images (CAREFUL!)
   podman system prune -af

   # Rotate old journal logs
   journalctl --user --vacuum-time=7d

   # Clean old backup logs
   find ~/containers/data/backup-logs/ -name "*.log" -mtime +30 -delete
   ```

### Container Won't Start

1. **Check quadlet syntax:**
   ```bash
   systemctl --user daemon-reload
   systemctl --user status <service>.service
   # Look for syntax errors in output
   ```

2. **Check volume permissions:**
   ```bash
   ls -lZ ~/containers/config/<service>
   # Verify SELinux context is correct
   ```

3. **Check network exists:**
   ```bash
   podman network ls | grep <network>
   ```

4. **Check for port conflicts:**
   ```bash
   ss -tulnp | grep <port>
   ```

5. **Review recent changes:**
   ```bash
   git log --oneline -10
   git diff HEAD~1
   ```

### Monitoring Stack Issues

1. **Prometheus not scraping:**
   - Check targets: http://localhost:9090/targets
   - Verify network connectivity between Prometheus and targets
   - Check service is on `systemd-monitoring` network

2. **Grafana dashboard empty:**
   - Verify datasource configured: http://localhost:3000/datasources
   - Check Prometheus UID matches in provisioning
   - Test query in Explore view

3. **Loki logs not appearing:**
   - Check Promtail status: `systemctl --user status promtail.service`
   - Verify Promtail can reach Loki: `podman logs promtail | grep error`
   - Check log file paths in promtail-config.yml

## System Health Reference

### Critical Services (Must Be Running)

These services are essential for system operation:

```bash
# Check critical services
systemctl --user is-active traefik.service       # Gateway to everything
systemctl --user is-active prometheus.service    # Metrics collection
systemctl --user is-active alertmanager.service  # Alert routing
systemctl --user is-active grafana.service       # Monitoring dashboard
```

### Expected Resource Usage (Normal Operation)

**Memory:**
- Total containers: ~2-3GB
- Individual services:
  - Traefik: ~50MB
  - Jellyfin: ~200MB (idle), 500MB-1GB (transcoding)
  - Prometheus: ~80MB
  - Grafana: ~120MB
  - Loki: ~60MB

**CPU:**
- Idle: >90% available
- Normal operation: 2-5% usage
- Transcoding: Can spike to 50-80% (normal)

**Disk:**
- System SSD: <60% (⚠️ if >70%, 🚨 if >80%)
- BTRFS pool: Plenty of space for media/data

### Health Check Commands

```bash
# Quick overall health
./scripts/homelab-intel.sh

# Individual service health
podman healthcheck run jellyfin
curl -f http://localhost:9090/-/healthy        # Prometheus
curl -f http://localhost:3000/api/health       # Grafana
curl -f http://localhost:3100/ready            # Loki

# All running containers
podman ps --format "table {{.Names}}\t{{.Status}}\t{{.State}}"

# Service status summary
systemctl --user list-units --type=service --state=running | grep -E '(traefik|jellyfin|prometheus|grafana|loki)'
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

## Architecture Decision Records (ADRs)

**Key decisions shaping this homelab:**

### ADR-001: Rootless Containers
**File:** `docs/00-foundation/decisions/2025-10-20-decision-001-rootless-containers.md`

**Decision:** All containers run as unprivileged user (UID 1000), not root.

**Rationale:**
- Security through principle of least privilege
- Container escape = unprivileged user access (not root)
- Works seamlessly with SELinux enforcing mode

**Impact:**
- ✅ Enhanced security, clear permission model
- ⚠️ Requires `:Z` SELinux labels on all volume mounts
- ⚠️ Can't bind to ports <1024 (solved via Traefik reverse proxy)
- ⚠️ UID mapping can be tricky (use `podman unshare` for debugging)

**Status:** ✅ Production, no regrets. Would choose again.

### ADR-002: Systemd Quadlets Over Docker Compose
**File:** `docs/00-foundation/decisions/2025-10-25-decision-002-systemd-quadlets-over-compose.md`

**Decision:** Use systemd quadlets (`.container` files) instead of docker-compose.

**Rationale:**
- Native systemd integration (no abstraction layer)
- Unified logging via journalctl
- First-class dependency management
- More transferable to enterprise environments
- Better learning value

**Impact:**
- ✅ Service management feels natural (`systemctl --user`)
- ✅ Bulletproof dependency handling
- ⚠️ One file per service vs stack files (preference)
- ⚠️ Initial learning curve (systemd syntax)

**Workflow:**
```bash
# Edit quadlet file
nano ~/.config/containers/systemd/service.container

# Apply changes
systemctl --user daemon-reload
systemctl --user restart service.service
```

**Status:** ✅ Production. Quadlets are the right abstraction level.

### ADR-003: Monitoring Stack (Prometheus + Grafana + Loki)
**File:** `docs/40-monitoring-and-documentation/decisions/2025-11-06-decision-001-monitoring-stack-architecture.md`

**Decision:** Deploy Prometheus + Grafana + Loki + Alertmanager for observability.

**Rationale:**
- Industry-standard, transferable skills
- Open source, self-hosted, no vendor lock-in
- Perfect scale for homelab (lightweight but powerful)
- Single pane of glass (Grafana) for metrics + logs

**Impact:**
- ✅ Complete visibility into system health
- ✅ Historical analysis ("what happened last Tuesday?")
- ✅ Proactive alerting (Discord notifications)
- ⚠️ ~340MB RAM overhead
- ⚠️ Need to manage retention policies

**Key Components:**
- Prometheus: Metrics (15-day retention)
- Grafana: Dashboards and visualization
- Loki: Log aggregation (7-day retention)
- Alertmanager: Alert routing to Discord

**Status:** ✅ Production. Highest-value addition to homelab.

### Using ADRs When Making Changes

**Before proposing architectural changes:**
1. Check if an ADR exists explaining the current approach
2. Understand the rationale and trade-offs already considered
3. If suggesting an alternative, reference the ADR and explain what changed
4. Document new decisions in a new ADR (don't edit existing ones)

**ADR supersession pattern:**
```markdown
## Status: Superseded by ADR-XXX

This decision has been superseded by [ADR-XXX](path/to/new-adr.md)
due to [reason for change].
```

## Common Gotchas & Solutions

### Permission Denied on Volume Mounts

**Symptom:**
```
Error: OCI runtime error: permission denied
```

**Cause:** Rootless containers + SELinux enforcing mode

**Solution:** Add `:Z` SELinux label to all bind mounts:
```bash
# Wrong
-v ~/containers/config/jellyfin:/config

# Correct
-v ~/containers/config/jellyfin:/config:Z
```

**Why:** The `:Z` label tells SELinux to relabel the content for container access.

### Port Already in Use

**Symptom:**
```
Error: cannot listen on port 8080: address already in use
```

**Solution:** Find what's using the port:
```bash
ss -tulnp | grep 8080
podman ps --format "{{.Names}}\t{{.Ports}}" | grep 8080
```

**Remember:** Rootless containers can't bind to ports <1024 without special capabilities. Use Traefik as reverse proxy instead.

### Quadlet Changes Not Applying

**Symptom:** Modified `.container` file but service behavior unchanged.

**Solution:** Must reload systemd daemon:
```bash
systemctl --user daemon-reload
systemctl --user restart <service>.service
```

**Why:** Systemd caches unit files. Daemon-reload forces re-read.

### First Network Determines Default Route

**Symptom:** Container can't reach internet despite being on multiple networks.

**Cause:** In quadlets with multiple `Network=` lines, **first one gets default route**.

**Example:**
```ini
# Container CAN reach internet (reverse_proxy first)
Network=systemd-reverse_proxy.network
Network=systemd-monitoring.network

# Container CANNOT reach internet (monitoring is internal-only)
Network=systemd-monitoring.network
Network=systemd-reverse_proxy.network
```

**Solution:** Put the network with internet access first.

### BTRFS Databases Need NOCOW

**Symptom:** Prometheus/Loki/Grafana database performance is terrible.

**Cause:** BTRFS Copy-on-Write (COW) causes fragmentation on database write patterns.

**Solution:** Disable COW for database directories:
```bash
# Before first use
mkdir -p /mnt/btrfs-pool/subvol7-containers/prometheus
chattr +C /mnt/btrfs-pool/subvol7-containers/prometheus

# Verify
lsattr -d /mnt/btrfs-pool/subvol7-containers/prometheus
# Should show 'C' flag
```

**Note:** Only works on empty directories. Can't retroactively fix existing databases.

### Podman Generate vs Quadlets Service Names

**Issue:** Service names change between generated units and quadlets.

**Generated units:** `container-jellyfin.service`
**Quadlet units:** `jellyfin.service`

**Impact:** Scripts/docs may reference old name. Update references when migrating.

### System SSD Space Exhaustion

**Symptom:** System suddenly fills up despite moving data to BTRFS pool.

**Common causes:**
1. Journal logs growing (check: `journalctl --user --disk-usage`)
2. Old container layers (check: `podman system df`)
3. Backup logs accumulating (check: `du -sh ~/containers/data/backup-logs/`)

**Quick fixes:**
```bash
# Rotate journal
journalctl --user --vacuum-time=7d

# Prune unused container data
podman system prune -f

# Clean old backup logs
find ~/containers/data/backup-logs/ -name "*.log" -mtime +30 -delete
```

## Secrets Management

Secrets are excluded from Git via `.gitignore`:
- `*.key`, `*.pem`, `*.crt`
- `*secret*`, `*password*`, `*.env`
- `acme.json` (Let's Encrypt certificates)
- `*.db`, `*.sqlite*` (databases)
- `*.mmdb` (CrowdSec data)

Store secrets outside the repository or use environment variables.
