# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A learning-focused homelab project building production-ready, self-hosted infrastructure using Podman containers managed through systemd quadlets. Platform: Fedora Workstation 42.

**Current Services:** Traefik (reverse proxy + CrowdSec), Jellyfin (media server), Authelia (SSO + YubiKey MFA), Prometheus/Grafana/Loki (monitoring), Alertmanager (alerting), Immich (photo management)

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

**Network Segmentation:**
- `systemd-reverse_proxy` - Traefik and externally-accessible services
- `systemd-media_services` - Jellyfin and media processing
- `systemd-auth_services` - Authelia, Redis (session storage)
- `systemd-monitoring` - Prometheus, Grafana, Loki, Alertmanager, exporters
- `systemd-photos` - Immich and its underlying services

Services join networks based on trust/access requirements. Services can be on multiple networks.

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

### Manual Deployment (Legacy)

For services without matching patterns:

```bash
# Create container with podman run (Traefik labels excluded as they should be defined in Traefik dynamic files)
# Generate systemd units
podman generate systemd --name <container> --files --new
systemctl --user daemon-reload
systemctl --user enable --now <service>.service
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

### Network Management

```bash
podman network ls                              # List networks
podman network inspect <network>               # Inspect network
podman network connect <network> <container>   # Connect container
```

### Traefik Operations

```bash
# Dynamic config reloads automatically when files change
# Just edit config/traefik/dynamic/*.yml and save

podman logs -f traefik                         # View logs
# Dashboard: traefik.patriark.org (requires auth)

# Check Let's Encrypt certificates
ls -lh /path/to/letsencrypt/acme.json
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

```bash
# System health and intelligence
./scripts/homelab-intel.sh              # Health scoring + recommendations (0-100)
./scripts/homelab-diagnose.sh           # Comprehensive system diagnostics

# Natural language queries (cached for speed)
./scripts/query-homelab.sh "what services are using the most memory?"
./scripts/query-homelab.sh "is jellyfin running?"
./scripts/query-homelab.sh "show me disk usage"

# Autonomous operations
./scripts/autonomous-check.sh --verbose  # Assessment only
./scripts/autonomous-execute.sh --status # Check autonomous status

# Predictive analytics
./scripts/predictive-analytics/predict-resource-exhaustion.sh --all

# Configuration drift detection
cd .claude/skills/homelab-deployment
./scripts/check-drift.sh                 # Check all services
./scripts/check-drift.sh jellyfin       # Check specific service

# Pre-deployment health check
./scripts/check-system-health.sh
./scripts/check-system-health.sh --verbose

# Security
./scripts/security-audit.sh
./scripts/scan-vulnerabilities.sh --severity CRITICAL,HIGH

# Skill usage analytics
./scripts/analyze-skill-usage.sh
./scripts/recommend-skill.sh "jellyfin won't start"

# System inventory
./scripts/survey.sh                      # BTRFS, storage, firewall, versions
./scripts/show-pod-status.sh            # Pod status with network/port info
./scripts/jellyfin-status.sh            # Service-specific status
./scripts/collect-storage-info.sh       # Storage diagnostics
```

**Drift Detection Categories:**
- ✓ MATCH - Configuration matches quadlet definition
- ✗ DRIFT - Mismatch requiring reconciliation (restart service)
- ⚠ WARNING - Minor differences (informational only)

**What is checked:** Image version, memory limits, networks, volumes, Traefik labels

### SLO Monitoring

**Dashboard:** https://grafana.patriark.org/d/slo-dashboard

```bash
# Query SLO metrics
curl 'http://localhost:9090/api/v1/query?query=slo:jellyfin:availability:actual'

# Run monthly SLO report
~/containers/scripts/monthly-slo-report.sh

# Check schedule
systemctl --user list-timers | grep monthly-slo-report
```

**SLO Targets (9 SLOs across 5 services):**
- Jellyfin: 99.5% availability, 95% latency <500ms
- Immich: 99.9% availability, 99.5% upload success
- Authelia: 99.9% availability, 95% latency <200ms
- Traefik: 99.95% availability, 99% latency <100ms
- OCIS: 99.5% availability

**Documentation:** `docs/40-monitoring-and-documentation/guides/slo-framework.md`

### System Health Reference

**Critical Services (Must Be Running):**
```bash
systemctl --user is-active traefik.service       # Gateway to everything
systemctl --user is-active authelia.service      # Needed to access protected services
systemctl --user is-active prometheus.service    # Metrics collection
systemctl --user is-active alertmanager.service  # Alert routing
systemctl --user is-active grafana.service       # Monitoring dashboard
```

**Expected Resource Usage:**
- **Memory:** Total ~2-3GB | Traefik: ~50MB | Jellyfin: ~200MB (idle) / 500MB-1GB (transcoding) | Prometheus: ~80MB | Grafana: ~120MB | Loki: ~60MB
- **CPU:** Idle: >90% | Normal: 2-5% | Transcoding: 50-80% (normal spike)
- **Disk:** System SSD: <60% (⚠️ >70%, 🚨 >80%) | BTRFS pool: Plenty of space

**Health Checks:**
```bash
./scripts/homelab-intel.sh                     # Quick overall health
podman healthcheck run <service>               # Individual service
curl -f http://localhost:9090/-/healthy        # Prometheus
curl -f http://localhost:3000/api/health       # Grafana
curl -f http://localhost:3100/ready            # Loki
```

## Autonomous Operations

**OODA Loop:** Daily automated Observe → Orient → Decide → Act cycle with safety controls.

```bash
# Status and control
~/containers/scripts/autonomous-execute.sh --status
~/containers/scripts/autonomous-check.sh --verbose  # Assessment only
~/containers/scripts/autonomous-execute.sh --from-check --dry-run

# Emergency controls
~/containers/scripts/autonomous-execute.sh --pause   # Stop autonomous actions
~/containers/scripts/autonomous-execute.sh --stop    # Full shutdown
~/containers/scripts/autonomous-execute.sh --resume  # Resume operations

# Decision history
~/containers/.claude/context/scripts/query-decisions.sh --last 7d
~/containers/.claude/context/scripts/query-decisions.sh --outcome failure
~/containers/.claude/context/scripts/query-decisions.sh --stats
```

**Automation:** Runs daily at 06:30 via `autonomous-operations.timer`

**Safety Features:**
- Circuit breaker (pauses after 3 consecutive failures)
- Service overrides (traefik, authelia never auto-restart)
- Pre-action BTRFS snapshots for instant rollback
- Confidence-based decision matrix (>90% + low risk → auto-execute)
- Cooldown periods per action type

**Documentation:** `docs/20-operations/guides/autonomous-operations.md`

## Skills & Automation

**Available Skills:**
- `homelab-deployment` - Service deployment with validation
- `homelab-intelligence` - System health and diagnostics
- `systematic-debugging` - Root cause investigation framework
- `autonomous-operations` - OODA loop operations
- `git-advanced-workflows` - Advanced Git operations
- `claude-code-analyzer` - Claude Code workflow optimization

**Documentation:** `docs/10-services/guides/skill-recommendation.md`

## Security & Runbooks

### Security Framework

```bash
# Security operations
~/containers/scripts/security-audit.sh                          # Comprehensive audit
~/containers/scripts/scan-vulnerabilities.sh --severity CRITICAL,HIGH
ls -lh ~/containers/data/security-reports/
systemctl --user status vulnerability-scan.timer                # Check schedule
```

**Automated Security:**
- Weekly vulnerability scanning (Sundays 06:00)
- ADR compliance validation
- Security baseline enforcement in deployments

### Runbooks

**Disaster Recovery** (`docs/20-operations/runbooks/`):
- **DR-001:** System SSD Failure
- **DR-002:** BTRFS Pool Corruption
- **DR-003:** Accidental Deletion
- **DR-004:** Total Catastrophe (bare metal rebuild)

**Incident Response** (`docs/30-security/runbooks/`):
- **IR-001:** Brute Force Attack
- **IR-002:** Unauthorized Port Exposed
- **IR-003:** Critical CVE in Running Container
- **IR-004:** Compliance Failure

Each runbook includes detection criteria, step-by-step procedures, recovery time estimates, and verification steps.

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

**Key decisions shaping this homelab** (see `docs/*/decisions/` for full details):

- **ADR-001: Rootless Containers** - All containers run as unprivileged user (UID 1000), not root. Requires `:Z` SELinux labels. ✅ Production
- **ADR-002: Systemd Quadlets Over Docker Compose** - Native systemd integration for unified logging and dependency management. ✅ Production
- **ADR-003: Monitoring Stack (Prometheus + Grafana + Loki)** - Industry-standard observability with ~340MB RAM overhead. ✅ Production
- **ADR-005: Authelia SSO with YubiKey-First Authentication** - Phishing-resistant hardware auth via FIDO2/WebAuthn, replacing TinyAuth. ✅ Production

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

### Documentation Structure

The `docs/` directory uses a **hybrid structure** combining topical reference with chronological learning logs.

**Directory Organization:**
- `97-plans/` - Strategic planning documents (forward-looking)
- `98-journals/` - Complete chronological history (flat, all dated entries)
- `99-reports/` - Automated system reports + formal snapshots
- `00-foundation/` - Podman, networking, pods, quadlets fundamentals
- `10-services/` - Service-specific guides
- `20-operations/` - Operational procedures, architecture, backup strategy
- `30-security/` - Security configurations, hardening, runbooks
- `40-monitoring-and-documentation/` - Monitoring stack, SLO framework
- `90-archive/` - Superseded documentation (with archival metadata)

**Three-Tier Documentation:**
1. **Forward-looking** (`97-plans/`) - Strategic plans and roadmaps
2. **Historical** (`98-journals/`) - Chronological project timeline
3. **Current state** (`*/guides/`) - Living reference documentation

**Subdirectory Structure (for 00-40 categories):**
- **`guides/`** - Living reference documentation (updated in place, no date prefix)
- **`decisions/`** - Architecture Decision Records / ADRs (immutable, dated)
- **`runbooks/`** - Disaster recovery and incident response (where applicable)

**Documentation Policies:**
1. **Guides are living** - Update in place when information changes
2. **Journals are immutable** - Never edit after creation (append-only log)
3. **Plans include status** - Updated with progress, archived manually
4. **ADRs are permanent** - Architecture decisions never edited, only superseded
5. **Reports are automated** - JSON reports or formal infrastructure snapshots
6. **Archive with metadata** - Include archival reason and superseding document

**Full guide:** See `docs/CONTRIBUTING.md` for detailed conventions and templates.

### Git Workflow

**Branch naming:**
- Features: `feature/description`
- Bugfixes: `bugfix/description`
- Documentation: `docs/description`
- Hotfixes: `hotfix/description`

**Standard workflow:**
```bash
# Start new work
git checkout main && git pull origin main
git checkout -b feature/your-feature

# Commit changes
git add <files>
git commit -m "Descriptive message"  # GPG signing enabled

# Push and create PR
git push -u origin feature/your-feature
```

**Merging strategy:**
- "Squash and merge" for small changes
- "Create merge commit" for feature branches
- Auto-delete branches after merge

**Security:** SSH authentication (Ed25519), GPG commit signing, strict host key checking enabled.

## Secrets Management

Secrets are excluded from Git via `.gitignore`:
- `*.key`, `*.pem`, `*.crt`
- `*secret*`, `*password*`, `*.env`
- `acme.json` (Let's Encrypt certificates)
- `*.db`, `*.sqlite*` (databases)
- `*.mmdb` (CrowdSec data)

Store secrets outside the repository or use podman secrets or environment variables.
