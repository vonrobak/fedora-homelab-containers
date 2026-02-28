# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A learning-focused homelab project building production-ready, self-hosted infrastructure using Podman containers managed through systemd quadlets. Platform: Fedora Workstation 43.

**Current Services (29 containers, 15 service groups):**
- **Core Infrastructure:** Traefik (reverse proxy), CrowdSec (threat intel), Authelia + Redis (SSO + YubiKey MFA)
- **Applications:** Nextcloud + MariaDB + Redis (file sync), Vaultwarden (passwords), Jellyfin (media), Immich + PostgreSQL + Redis + ML (photos), Gathio + MongoDB (events), Homepage (dashboard)
- **Audio:** Audiobookshelf (audiobooks/podcasts), Navidrome (music streaming)
- **Home Automation:** Home Assistant + Matter Server (smart home, Plejd integration planned)
- **Monitoring:** Prometheus, Grafana, Loki, Alertmanager, Promtail, cAdvisor, Node Exporter, UnPoller, Alert Discord Relay

## Architecture

### Container Orchestration

**Core Stack:**
- **Runtime:** Podman (rootless containers)
- **Orchestration:** systemd quadlets (`~/.config/containers/systemd/`)
- **Management:** `systemctl --user` commands
- **Service Discovery:** Traefik Docker provider with Podman socket

### Security Architecture

**Layered Middleware** (fail-fast principle):
```
Internet → Port Forward (80/443)
  ↓
[1] CrowdSec IP Reputation (cache lookup - fastest)
  ↓
[2] Rate Limiting (tiered: 100-200 req/min)
  ↓
[3] Authelia SSO (YubiKey/WebAuthn + TOTP - phishing-resistant)
  ↓
[4] Security Headers (applied on response)
  ↓
Backend Service
```

**Why this order matters:** Each layer is more expensive than the last. Reject malicious IPs immediately before wasting resources on auth checks.

**Network Segmentation:** 8 networks for trust boundaries (see `AUTO-NETWORK-TOPOLOGY.md` for topology diagrams)
- `reverse_proxy` - Internet-facing services + Traefik (default route for internet access)
- `monitoring` - Prometheus, Grafana, Loki, exporters (cross-network scraping)
- `auth_services` - Authelia + Redis (isolated auth backend)
- `media_services` - Jellyfin (media isolation)
- `photos` - Immich stack (photo processing isolation)
- `nextcloud` - Nextcloud + Collabora + MariaDB + Redis
- `home_automation` - Home Assistant + Matter Server
- `gathio` - Gathio + MongoDB

Services join networks based on trust/access requirements. Key principle: **First network gets default route** (see Common Gotchas).

### Traefik Configuration

**Static config:** `/config/traefik/traefik.yml` (entry points, providers, Let's Encrypt)

**Dynamic config:** `/config/traefik/dynamic/` (watched by Traefik):
- `middleware.yml` - CrowdSec, rate limiting, auth, security headers
- `routers.yml` - Service routing rules
- `security-headers-strict.yml` - CSP, HSTS, X-Frame-Options
- `tls.yml` - TLS 1.2+ with modern ciphers
- `rate-limit.yml` - Tiered rate limits (global: 50/min, auth: 10/min, API: 30/min)

## Service Deployment

### Pattern-Based Deployment (Recommended)

Use battle-tested deployment patterns for consistent, validated deployments:

```bash
# Deploy using homelab-deployment skill patterns
cd .claude/skills/homelab-deployment

# Examples
./scripts/deploy-from-pattern.sh \
  --pattern media-server-stack \
  --service-name jellyfin \
  --hostname jellyfin.patriark.org \
  --memory 4G

./scripts/deploy-from-pattern.sh \
  --pattern web-app-with-database \
  --service-name wiki \
  --hostname wiki.patriark.org \
  --memory 2G

# See all patterns
ls -1 patterns/*.yml

# Pattern selection guide
cat docs/10-services/guides/pattern-selection-guide.md
```

**Available Patterns (9 total):**
- `media-server-stack` - Jellyfin, Plex (GPU transcoding, large storage)
- `web-app-with-database` - Wiki.js, Bookstack (standard web apps)
- `document-management` - Paperless-ngx, Nextcloud (OCR, multi-container)
- `authentication-stack` - Authelia + Redis (SSO with YubiKey)
- `password-manager` - Vaultwarden (self-contained password vault)
- `database-service` - PostgreSQL, MySQL (BTRFS NOCOW optimized)
- `cache-service` - Redis, Memcached (session storage, caching)
- `reverse-proxy-backend` - Internal services (strict auth required)
- `monitoring-exporter` - Node exporter, cAdvisor (metrics collection)

### Manual Deployment

**🚨 CRITICAL: Traefik Routing Configuration**

**ALL Traefik routing is defined in dynamic config files, NEVER in container labels.**

**Why?**
- ✅ Separation of concerns (ADR-016: quadlets = deployment, Traefik = routing)
- ✅ Centralized security (all routes auditable in one file: `config/traefik/dynamic/routers.yml`)
- ✅ Fail-fast middleware ordering enforced consistently
- ✅ Single source of truth (no label/config sync issues)
- ✅ Git-friendly (routing changes isolated from service changes)

**See:** ADR-016 (Configuration Design Principles) for complete rationale

---

For services without matching patterns:

```bash
# 1. Create quadlet file (NO Traefik labels)
nano ~/.config/containers/systemd/service.container

[Container]
Image=service:latest
ContainerName=service
Network=systemd-reverse_proxy.network
# NO Traefik labels - routing defined separately

# 2. Add route to Traefik dynamic config
nano ~/containers/config/traefik/dynamic/routers.yml

# Append under http.routers:
    service-secure:
      rule: "Host(`service.patriark.org`)"
      service: "service"
      middlewares:
        - crowdsec-bouncer@file
        - rate-limit@file
        - authelia@file               # Remove if native auth
        - security-headers@file
      tls:
        certResolver: letsencrypt

# And under http.services:
    service:
      loadBalancer:
        servers:
          - url: "http://service:port"

# 3. Deploy
systemctl --user daemon-reload
systemctl --user enable --now service.service

# 4. Verify routing
curl -I https://service.patriark.org
```

**Pattern-based deployment handles this automatically:**
```bash
cd .claude/skills/homelab-deployment

./scripts/deploy-from-pattern.sh \
  --pattern web-app-with-database \
  --service-name wiki \
  --hostname wiki.patriark.org \
  --memory 2G

# ✅ Generates BOTH:
# 1. ~/.config/containers/systemd/wiki.container (deployment)
# 2. ~/containers/config/traefik/dynamic/routers.yml (routing)
```

## Operations

### Service Management

```bash
# Service-specific scripts
./scripts/jellyfin-manage.sh {start|stop|restart|status|logs|follow}

# Generic systemd management
systemctl --user status <service>.service
systemctl --user restart <service>.service
journalctl --user -u <service>.service -f

# Container operations
podman ps                           # List running containers
podman logs -f <service>            # Follow logs
podman healthcheck run <service>    # Check container health
```

### Update Management

**Update Strategy:**
- **Most services:** Use `:latest` tags for automatic security patches
- **Databases:** Pin major versions (PostgreSQL, MariaDB) - manual migration required
- **Immich:** Pin to specific version (tight coupling with ML + postgres)
- **Workflow:** `~/containers/scripts/update-before-reboot.sh` before DNF updates
- **Rollback:** Automated BTRFS snapshots enable instant recovery

**See:** `docs/00-foundation/decisions/2025-12-22-ADR-015-container-update-strategy.md`

### Network Management

```bash
podman network ls                              # List networks
podman network inspect <network>               # Inspect network
podman network connect <network> <container>   # Connect container
```

### Traefik Operations

**Configuration Philosophy:** ALL routing in dynamic config files (see ADR-016)

```bash
# Dynamic config reloads automatically when files change
# Just edit config/traefik/dynamic/*.yml and save

podman logs -f traefik                         # View logs
# Dashboard: traefik.patriark.org (requires auth)

# Check Let's Encrypt certificates
ls -lh ~/containers/data/letsencrypt/acme.json

# Routing configuration files
cat ~/containers/config/traefik/dynamic/routers.yml      # All routes (13 routers, 11 services)
cat ~/containers/config/traefik/dynamic/middleware.yml   # Security policies (13KB)

# Force config reload (optional - auto-reloads after 60s)
podman exec traefik kill -SIGHUP 1

# Verify routing works
curl -I https://service.patriark.org

# Audit all public routes
grep "rule:" ~/containers/config/traefik/dynamic/routers.yml
```

**Add new route:**
```bash
# 1. Edit routers.yml
nano ~/containers/config/traefik/dynamic/routers.yml

# 2. Append under http.routers section:
    newservice-secure:
      rule: "Host(`newservice.patriark.org`)"
      service: "newservice"
      middlewares: [crowdsec-bouncer@file, rate-limit@file, authelia@file, security-headers@file]
      tls:
        certResolver: letsencrypt

# 3. Add service definition:
    newservice:
      loadBalancer:
        servers:
          - url: "http://newservice:8080"

# 4. Save file (Traefik auto-reloads in ~60s or send SIGHUP)
```

### Authelia Operations

```bash
# Logs and health
podman logs -f authelia
journalctl --user -u authelia.service -f
podman healthcheck run authelia
curl http://localhost:9091/api/health

# User management
podman exec -it authelia authelia crypto hash generate argon2 --password 'PASSWORD'
# Edit ~/containers/config/authelia/users_database.yml, then restart

# Session management (Redis)
podman exec -it redis-authelia redis-cli
KEYS authelia:session:*
TTL authelia:session:<session-id>

# Force logout all users (nuclear option)
systemctl --user restart redis-authelia.service

# Service management
systemctl --user status authelia.service redis-authelia.service
systemctl --user restart authelia.service
```

## Diagnostics & Monitoring

**Full reference:** `docs/20-operations/guides/automation-reference.md` - Complete catalog of all scripts, schedules, and skill integrations.

### Key Diagnostic Scripts

**Complete catalog:** `docs/20-operations/guides/automation-reference.md` (65 scripts, schedules, integrations)

```bash
# Most critical operations
./scripts/homelab-intel.sh                     # Health scoring (0-100) + recommendations
./scripts/query-homelab.sh "<natural language>" # Query system state (cached)
./scripts/autonomous-check.sh --verbose        # OODA loop assessment
./scripts/check-drift.sh [service]             # Config drift detection
./scripts/security-audit.sh                    # Security baseline check
./scripts/auto-doc-orchestrator.sh             # Regenerate all docs (~2s)
```

### SLO Monitoring

**9 SLOs across 5 services.** Full targets, queries, and dashboard: `docs/40-monitoring-and-documentation/guides/slo-framework.md`

```bash
# Dashboard: https://grafana.patriark.org/d/slo-dashboard
~/containers/scripts/monthly-slo-report.sh  # Generate SLO report
```

### Loki Log Analysis

**Remediation decisions and Traefik access logs ingested into Loki.** LogQL queries for analysis, correlation, and loop detection: `docs/40-monitoring-and-documentation/guides/loki-remediation-queries.md`

**Explore:** https://grafana.patriark.org/explore

### System Health Reference

**Critical Services (Must Be Running):**
```bash
systemctl --user is-active traefik.service       # Gateway to everything
systemctl --user is-active authelia.service      # Needed to access protected services
systemctl --user is-active prometheus.service    # Metrics collection
systemctl --user is-active alertmanager.service  # Alert routing
systemctl --user is-active grafana.service       # Monitoring dashboard
```

**Expected Resource Usage (29 containers, measured February 2026):**
- **Memory:** Total ~4-5GB | Jellyfin: ~200MB idle / 500MB-1GB transcoding | Prometheus: ~300MB | Loki: ~200MB | Grafana: ~200MB | Traefik: ~80MB | Immich-server: ~350MB | Nextcloud: ~200MB | Audiobookshelf: ~200MB | Navidrome: ~200MB
- **CPU:** Idle: >90% | Normal: 2-5% | Transcoding: 50-80% (normal spike)
- **Disk:** System SSD: <70% normal (⚠️ >75%, 🚨 >85%) | BTRFS pool: ~73% used (4TB free of 14.5TB)
- **Swap:** ~1GB typical (normal for long-running services with 29 containers)

**Health Checks:**
```bash
./scripts/homelab-intel.sh                     # Quick overall health
podman healthcheck run <service>               # Individual service
curl -f http://localhost:9090/-/healthy        # Prometheus
curl -f http://localhost:3000/api/health       # Grafana
curl -f http://localhost:3100/ready            # Loki
```

## Autonomous Operations

**OODA Loop:** Daily automated Observe → Orient → Decide → Act cycle. Full framework details: `docs/20-operations/guides/autonomous-operations.md`

```bash
# Status and control
~/containers/scripts/autonomous-check.sh --verbose   # Assessment only
~/containers/scripts/autonomous-execute.sh --status  # Current state
~/containers/scripts/autonomous-execute.sh --pause   # Emergency stop

# Decision history
~/containers/.claude/context/scripts/query-decisions.sh --last 7d --stats
```

**Key Features:**
- **Predictive maintenance:** Forecasts resource exhaustion 7-14 days ahead (>60% confidence threshold)
- **Alert-driven remediation:** Webhook integration with Alertmanager (conservative, safe operations only)
- **Safety controls:** Circuit breaker, service overrides (traefik/authelia), BTRFS snapshots, confidence-based decisions (>90%)

**Automation:** Daily at 06:00 (predictive) and 06:30 (OODA) via systemd timers

## Skills & Automation

**Available Skills:**
- `homelab-deployment` - Service deployment with validation
- `homelab-intelligence` - System health and diagnostics
- `systematic-debugging` - Root cause investigation framework
- `autonomous-operations` - OODA loop operations
- `git-advanced-workflows` - Advanced Git operations

**Documentation:** `docs/10-services/guides/skill-recommendation.md`

## Slash Commands & Subagents

### Slash Commands

**Available Commands:**
- `/commit-push-pr [prefix]` - Complete git workflow automation
  - Pre-computes git status for speed (~0.5s)
  - Auto-detects change type (deployment, config, docs)
  - Generates structured commit messages with homelab context
  - Stages, commits (GPG-signed), pushes, creates PR with gh CLI
  - Includes deployment logs and verification results in PR
  - Usage: `/commit-push-pr` or `/commit-push-pr feat`

**Benefits:**
- **Fast**: Parallel git operations for speed
- **Context-aware**: References deployment journals and issue history
- **Consistent**: Follows homelab commit conventions
- **Complete**: One command from uncommitted changes to PR

### Subagents

Specialized agents for specific tasks, invoked automatically or on-demand:

**infrastructure-architect** - Design decisions before deployment
- Network topology design (which networks, proper ordering)
- Security architecture selection (middleware chains)
- Deployment pattern selection (9 patterns available)
- Resource allocation (memory, storage strategy)
- Integration design (auth, monitoring, backups)
- ADR compliance checking
- **When to use:** Before deploying new services, when asking "how should I deploy..."

**service-validator** - Deployment verification
- 7-level verification framework (health, network, routing, auth, monitoring, drift, security)
- "Assume failure until proven otherwise" mindset
- Structured verification reports
- **When to use:** Automatically after deployment, manual verification requests

**code-simplifier** - Post-deployment refactoring
- Removes config bloat and maintains pattern compliance
- Consolidates quadlet directives and Traefik routes
- Aligns with homelab patterns and ADRs
- **When to use:** After successful deployment, before git commit

**Integration:** Subagents work together in deployment workflow:
1. `infrastructure-architect` → Design decisions
2. `homelab-deployment` skill → Implementation
3. `service-validator` → Verification
4. `code-simplifier` → Cleanup (optional)
5. `/commit-push-pr` → Git workflow

## Security & Runbooks

**Security operations:**
```bash
~/containers/scripts/security-audit.sh               # Comprehensive audit (40+ checks)
~/containers/scripts/scan-vulnerabilities.sh --severity CRITICAL,HIGH
```

**Automated:** Weekly vulnerability scanning (Sundays 06:00), ADR compliance validation

**Runbooks:** 10 total (4 DR, 5 IR, + procedures). See:
- **Disaster Recovery:** `docs/20-operations/runbooks/` (DR-001 through DR-004)
- **Incident Response:** `docs/30-security/runbooks/` (IR-001 through IR-005)
- **Security Guides:** `docs/30-security/guides/` (7 guides including CrowdSec phases, SSH hardening, secrets management)

## Troubleshooting

### Service Not Accessible Externally

1. **Check service running:** `podman ps | grep <service>` and `systemctl --user status <service>.service`
2. **Check Traefik routing:** Dashboard at http://localhost:8080/dashboard/ - verify router rule
3. **Check DNS:** `dig <subdomain>.patriark.org` (should return public IP)
4. **Check firewall:** `sudo firewall-cmd --list-all` (ports 80/443 must be open)
5. **Check logs:** `journalctl --user -u <service>.service -n 50` and `podman logs <service> --tail 50`

### High Disk Usage

1. **System SSD:** `df -h /` (⚠️ if >80%)
2. **BTRFS pool:** `btrfs fi usage -T /mnt/btrfs-pool`
3. **Container data:** `du -sh ~/containers/data/*` and `du -sh ~/containers/config/*`
4. **Logs:** `journalctl --user --disk-usage` and `du -sh ~/containers/data/backup-logs/`
5. **Cleanup:** `podman system prune -af`, `journalctl --user --vacuum-time=7d`, `find ~/containers/data/backup-logs/ -name "*.log" -mtime +30 -delete`

### Container Won't Start

1. **Quadlet syntax:** `systemctl --user daemon-reload` then `systemctl --user status <service>.service`
2. **Volume permissions:** `ls -lZ ~/containers/config/<service>` (verify SELinux context)
3. **Network exists:** `podman network ls | grep <network>`
4. **Port conflicts:** `ss -tulnp | grep <port>`
5. **Recent changes:** `git log --oneline -10` and `git diff HEAD~1`

### Monitoring Stack Issues

1. **Prometheus not scraping:** Check http://localhost:9090/targets and verify service on `systemd-monitoring` network
2. **Grafana dashboard empty:** Verify datasource at http://localhost:3000/datasources and test in Explore view
3. **Loki logs missing:** `systemctl --user status promtail.service` and `podman logs promtail | grep error`

### Untrusted Proxy Errors

**Symptom:** Home Assistant or other services log "400 Bad Request - untrusted proxy" errors

**Root Cause:** Podman's aardvark-dns returns container IPs in undefined order. When monitoring network IPs resolve first, Traefik routes traffic through the wrong network, violating trusted_proxies configuration.

**Solution:** Static IP assignment + Traefik /etc/hosts override (implemented in ADR-018)
1. **Verify static IPs:** `podman exec <service> ip addr show | grep "inet 10.89.2"`
2. **Check Traefik hosts file:** `podman inspect traefik | jq '.[0].Mounts[] | select(.Destination=="/etc/hosts")'`
3. **Test DNS resolution:** `podman exec traefik getent hosts <service>` (should return 10.89.2.x)
4. **Verify no errors:** `journalctl --user -u home-assistant.service | grep -i untrusted`

**See:** docs/00-foundation/decisions/2026-02-04-ADR-018-static-ip-multi-network-services.md

## Key Design Principles

1. **Rootless containers** - All services run as user processes for enhanced security
2. **Middleware ordering** - Arrange by execution cost (fail-fast: CrowdSec → rate limit → auth)
3. **Configuration as code** - All configs in Git (secrets excluded via .gitignore)
4. **Health-aware deployment** - Scripts verify service readiness before completion
5. **Zero-trust model** - Authentication required for all internet-accessible services
6. **Autonomous operations** - OODA loop with confidence-based decision making and safety controls
7. **Predictive maintenance** - Forecast resource exhaustion 7-14 days in advance
8. **Defense in depth** - Layered security (IP reputation, rate limiting, authentication, headers, vulnerability scanning)
9. **Fail-safe defaults** - Autonomous actions require high confidence; circuit breaker on failures
10. **Observable system** - Natural language queries, comprehensive metrics, audit trails

## Architecture Decision Records (ADRs)

**18 ADRs documenting architectural decisions** (see `docs/*/decisions/` for full details)

**Design-Guiding ADRs (affect future decisions):**
- **ADR-001: Rootless Containers** - All containers run as unprivileged user (UID 1000). Requires `:Z` SELinux labels on all volume mounts.
- **ADR-002: Systemd Quadlets Over Docker Compose** - Native systemd integration for unified logging and dependency management.
- **ADR-003: Monitoring Stack** - Prometheus + Grafana + Loki for observability (~700MB RAM overhead with all exporters).
- **ADR-006: YubiKey-First Authentication** - Phishing-resistant hardware auth via FIDO2/WebAuthn for Authelia SSO.
- **ADR-008: CrowdSec Security Architecture** - IP reputation with fail-fast middleware ordering (cheapest checks first).
- **ADR-009: Config vs Data Directory Strategy** - Storage organization: `/config` (version-controlled), `/data` (ephemeral/large).
- **ADR-010: Pattern-Based Deployment** - Automated service deployment using 9 battle-tested patterns with validation.
- **ADR-016: Configuration Design Principles** - **CRITICAL:** Separation of concerns (quadlets = deployment, Traefik = routing). ALL Traefik routing in dynamic config files, NEVER in labels.
- **ADR-018: Static IP Multi-Network Services** - Static IP assignment + Traefik /etc/hosts override to bypass Podman's undefined DNS ordering. Required for predictable routing.

**Supporting ADRs (implementation details):**
- ADR-004: Immich Deployment (multi-container, GPU/ML)
- ADR-005: Authelia SSO (superseded by ADR-006)
- ADR-007: Vaultwarden (self-hosted password manager)
- ADR-011: Service Dependency Mapping
- ADR-012: Autonomous Operations Alert Quality
- ADR-013: Nextcloud Native Authentication
- ADR-014: Nextcloud Passwordless Auth
- ADR-015: Container Update Strategy (`:latest` tags + strategic pinning)
- ADR-017: Slash Commands & Subagents (automation workflow)

**Using ADRs:**

**Using ADRs:**
1. Check if an ADR exists explaining the current approach before proposing changes
2. Understand the rationale and trade-offs already considered
3. Reference the ADR and explain what changed if suggesting alternatives
4. Document new decisions in a new ADR (don't edit existing ones)

**ADR supersession pattern:**
```markdown
## Status: Superseded by ADR-XXX

This decision has been superseded by [ADR-XXX](path/to/new-adr.md)
due to [reason for change].
```

## Quick Reference

**Architecture & Services:**
- Complete service catalog: `AUTO-SERVICE-CATALOG.md` (updated daily)
- Network topology: `AUTO-NETWORK-TOPOLOGY.md` (diagrams, 8 networks)
- Service dependencies: `AUTO-DEPENDENCY-GRAPH.md` (4-tier graph, critical paths)
- Architecture overview: `docs/20-operations/guides/homelab-architecture.md`

**Operations & Automation:**
- Script catalog: `docs/20-operations/guides/automation-reference.md` (65 scripts)
- Autonomous operations: `docs/20-operations/guides/autonomous-operations.md`
- Drift detection: `docs/20-operations/guides/drift-detection-workflow.md`
- Dependency management: `docs/20-operations/guides/dependency-management.md`

**Monitoring & Security:**
- SLO framework: `docs/40-monitoring-and-documentation/guides/slo-framework.md` (9 SLOs)
- Monitoring stack: `docs/40-monitoring-and-documentation/guides/monitoring-stack.md`
- Loki queries: `docs/40-monitoring-and-documentation/guides/loki-remediation-queries.md`
- Security guides: `docs/30-security/guides/` (7 guides + 5 runbooks)

**Documentation:**
- Complete index: `AUTO-DOCUMENTATION-INDEX.md` (298 files)
- Contributing guide: `CONTRIBUTING.md`

## Common Gotchas & Solutions

### Permission Denied on Volume Mounts

**Symptom:** `Error: OCI runtime error: permission denied`

**Cause:** Rootless containers + SELinux enforcing mode

**Solution:** Add `:Z` SELinux label to all bind mounts:
```bash
# Wrong: -v ~/containers/config/jellyfin:/config
# Correct: -v ~/containers/config/jellyfin:/config:Z
```

### Port Already in Use

**Symptom:** `Error: cannot listen on port 8080: address already in use`

**Solution:** `ss -tulnp | grep 8080` or `podman ps --format "{{.Names}}\t{{.Ports}}" | grep 8080`

**Remember:** Rootless containers can't bind to ports <1024. Use Traefik as reverse proxy.

### Quadlet Changes Not Applying

**Symptom:** Modified `.container` file but service behavior unchanged

**Solution:** Must reload systemd daemon:
```bash
systemctl --user daemon-reload
systemctl --user restart <service>.service
```

### First Network Determines Default Route

**Symptom:** Container can't reach internet despite being on multiple networks

**Cause:** In quadlets with multiple `Network=` lines, **first one gets default route**

**Solution:** Put the network with internet access first:
```ini
# Container CAN reach internet (reverse_proxy first)
Network=systemd-reverse_proxy.network
Network=systemd-monitoring.network

# Container CANNOT reach internet (monitoring is internal-only)
Network=systemd-monitoring.network
Network=systemd-reverse_proxy.network
```

### BTRFS Databases Need NOCOW

**Symptom:** Prometheus/Loki/Grafana database performance is terrible

**Cause:** BTRFS Copy-on-Write (COW) causes fragmentation on database write patterns

**Solution:** Disable COW for database directories (only works on empty directories):
```bash
mkdir -p /mnt/btrfs-pool/subvol7-containers/prometheus
chattr +C /mnt/btrfs-pool/subvol7-containers/prometheus
lsattr -d /mnt/btrfs-pool/subvol7-containers/prometheus  # Verify 'C' flag
```

### Podman Generate vs Quadlets Service Names

**Generated units:** `container-jellyfin.service`
**Quadlet units:** `jellyfin.service`

**Impact:** Scripts/docs may reference old name. Update references when migrating.

### System SSD Space Exhaustion

**Common causes:**
1. Journal logs: `journalctl --user --disk-usage`
2. Container layers: `podman system df`
3. Backup logs: `du -sh ~/containers/data/backup-logs/`

**Quick fixes:**
```bash
journalctl --user --vacuum-time=7d           # Rotate journal
podman system prune -f                       # Prune unused container data
find ~/containers/data/backup-logs/ -name "*.log" -mtime +30 -delete
```

## Documentation & Git Workflow

**Documentation Structure:** Hybrid - topical reference + chronological learning logs. See `CONTRIBUTING.md` for conventions.

**Key directories:**
- `00-40/` - Topical guides, ADRs, runbooks (living reference)
- `97-plans/` - Strategic planning (forward-looking)
- `98-journals/` - Complete project timeline (immutable, append-only)
- `99-reports/` - Automated reports + infrastructure snapshots
- `90-archive/` - Superseded documentation

**Auto-Generated Docs (updated daily 07:00):**
- `AUTO-SERVICE-CATALOG.md` - Service inventory, status, resources
- `AUTO-NETWORK-TOPOLOGY.md` - Network diagrams (Mermaid)
- `AUTO-DEPENDENCY-GRAPH.md` - 4-tier dependency graph, critical paths
- `AUTO-DOCUMENTATION-INDEX.md` - Complete catalog (298 files)

**Regenerate:** `~/containers/scripts/auto-doc-orchestrator.sh` (~2s)

**Git Workflow:**
```bash
git checkout main && git pull
git checkout -b feature/description
git add <files> && git commit -m "message"  # GPG signed
git push -u origin feature/description
```

**Security:** SSH (Ed25519), GPG signing, strict host key checking

## Secrets Management

Secrets are excluded from Git via `.gitignore`:
- `*.key`, `*.pem`, `*.crt`
- `*secret*`, `*password*`, `*.env`
- `acme.json` (Let's Encrypt certificates)
- `*.db`, `*.sqlite*` (databases)
- `*.mmdb` (CrowdSec data)

Store secrets outside the repository or use podman secrets or environment variables.
