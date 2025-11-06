# System State Report - November 6, 2025

**Last Updated**: 2025-11-06
**Infrastructure**: Rootless Podman + Quadlets on Fedora Linux
**Domain**: patriark.org (Cloudflare DNS with automated DDNS)

## Executive Summary

Production-grade homelab running 10+ containerized services with comprehensive monitoring, security hardening, and automated operations. Recent focus on observability stack deployment (Prometheus, Grafana, Loki) and secret management improvements.

---

## Core Infrastructure

### Container Platform
- **Runtime**: Podman 5.x (rootless, SELinux enforcing)
- **Orchestration**: systemd Quadlets
- **Networking**: Netavark with bridge networks (network segmentation by service class)
- **Storage**: BTRFS with subvolumes for isolation and snapshot capability

### Reverse Proxy & Security
- **Traefik v3.2**: Automatic HTTPS via Let's Encrypt, Prometheus metrics enabled
- **CrowdSec**: Planned deployment (bouncer plugin configured, API key externalized to Podman secrets)
- **Authentication**: Tinyauth (lightweight) for service protection
- **Authelia**: SSO platform (partially deployed, testing phase)

### Monitoring Stack (Production)
- **Prometheus**: 15-day retention, scraping 5 targets (self, node_exporter, Grafana, Traefik, Loki planned)
- **Grafana 11.3.0**: 3 dashboards (Node Exporter Full, Traefik Overview, system dashboards)
- **Loki**: Centralized log aggregation (Promtail deployed across services)
- **Node Exporter**: Host metrics collection
- **Journal Export**: System journal → Loki pipeline with automated rotation (100MB threshold, keep 3 compressed)

### Network Architecture
```
systemd-reverse_proxy    (10.89.2.0/24)  - Public-facing services + Traefik
systemd-auth_services    (10.89.3.0/24)  - Tinyauth, Authelia, Redis
systemd-media_services   (10.89.1.0/24)  - Jellyfin
systemd-monitoring       (10.89.4.0/24)  - Prometheus, Grafana, Loki, Node Exporter
```

**Design Principle**: Services attach to multiple networks as needed. First network listed becomes default route.

---

## Running Services

### Production Services
| Service | URL | Network(s) | Authentication | Status |
|---------|-----|------------|----------------|--------|
| Traefik Dashboard | localhost:8080 | reverse_proxy, auth_services, monitoring | None (internal only) | ✅ Healthy |
| Jellyfin | https://jellyfin.patriark.org | reverse_proxy, media_services | Tinyauth | ✅ Healthy |
| Grafana | https://grafana.patriark.org | reverse_proxy, monitoring | Tinyauth + built-in | ✅ Healthy |
| Prometheus | https://prometheus.patriark.org | monitoring | Tinyauth + IP whitelist | ✅ Healthy |
| Loki | https://loki.patriark.org | monitoring | Tinyauth + IP whitelist | ✅ Healthy |
| Tinyauth | https://tinyauth.patriark.org | reverse_proxy, auth_services | N/A (auth provider) | ✅ Healthy |

### Supporting Services
- **Redis**: Session storage for Authelia (auth_services network)
- **Node Exporter**: System metrics (monitoring network)
- **Promtail**: Log shipper (all networks, sends to Loki)
- **Journal Export**: Systemd journal → file for Promtail ingestion

### Planned/Testing
- **Authelia**: Full SSO deployment with hardware 2FA
- **CrowdSec**: Active threat detection and IP blocking
- **Alertmanager**: Alert routing and notification

---

## Security Posture

### Current Implementations
✅ **Network Segmentation**: 4 isolated bridge networks
✅ **Defense in Depth**: Multi-layer middleware (CrowdSec → rate limiting → auth → headers)
✅ **Secret Management**: Podman secrets for sensitive credentials (CrowdSec API key externalized)
✅ **TLS Everywhere**: Automatic Let's Encrypt certificates via Traefik
✅ **IP Whitelisting**: Monitoring APIs restricted to LAN + VPN (192.168.1.0/24, 192.168.100.0/24)
✅ **Security Headers**: HSTS, CSP, X-Frame-Options on all routes
✅ **SELinux Enforcing**: Full mandatory access control
✅ **Rootless Containers**: All services run as unprivileged user

### Authentication Layers
1. **Public Services**: CrowdSec bouncer → rate limiting → Tinyauth → security headers
2. **Admin Interfaces**: Additional IP whitelisting before auth
3. **Internal APIs**: IP whitelist only (monitoring endpoints)

### Middleware Ordering (Critical)
All routes follow this order:
1. `crowdsec-bouncer` - Block malicious IPs (fastest check)
2. `rate-limit-*` - Prevent abuse by request rate
3. `tinyauth@file` or `monitoring-api-whitelist` - Authentication/authorization
4. `security-headers` - Response header injection (always last)

---

## Storage Architecture

### Container Configuration & Data
```
/home/patriark/containers/
├── config/          - Service configurations (git tracked)
├── data/            - Small persistent data (git ignored)
├── secrets/         - Sensitive credentials (chmod 600, git ignored)
├── scripts/         - Management automation (git tracked)
├── docs/            - Comprehensive documentation (git tracked)
├── backups/         - Config backups (git ignored)
├── cache/           - Symlink to /mnt/btrfs-pool/subvol6-tmp/container-cache
└── quadlets/        - Symlink to ~/.config/containers/systemd (Quadlet definitions)
```

### Large Data Storage (BTRFS Pool)
```
/mnt/btrfs-pool/
├── subvol1-docs/              - Document archives
├── subvol4-multimedia/        - Video library (Jellyfin media)
├── subvol5-music/             - Audio library
├── subvol6-tmp/               - Cache and temporary files (NOCOW for databases)
└── subvol7-containers/        - Large container data
```

**Database Best Practice**: All database directories use `chattr +C` (NOCOW) to avoid BTRFS COW performance penalties.

---

## Operational Capabilities

### Automated Operations
- **DDNS Updates**: Cloudflare DNS updated via cron (every 5 minutes)
- **SSL Certificate Renewal**: Automatic via Traefik + Let's Encrypt
- **Log Rotation**: Journal export logs rotated at 100MB (keep last 3 compressed)
- **Container Updates**: AutoUpdate=registry on Traefik and Grafana
- **Health Checks**: All services have health probes with restart policies

### Monitoring & Alerting
- **Metrics Collection**: 15-second scrape interval across all targets
- **Dashboard Coverage**: Node exporter full dashboard, Traefik performance dashboard
- **Log Aggregation**: All container logs → Loki (via Promtail)
- **Retention**: Prometheus 15 days, Loki TBD
- **Alerting**: Alertmanager deployment planned (next phase)

### Management Scripts
```bash
~/containers/scripts/
├── jellyfin-manage.sh           - Service control (start/stop/restart/logs)
├── jellyfin-status.sh           - Detailed status report
├── homelab-diagnose.sh          - Full system diagnostic
├── cloudflare-ddns.sh           - DNS update automation
├── rotate-journal-export.sh     - Log rotation (hourly via timer)
└── traefik-entrypoint.sh        - Secret loading wrapper for Traefik
```

### Systemd Service Management
```bash
# Service control
systemctl --user status <service>.service
systemctl --user restart <service>.service
journalctl --user -u <service>.service -f

# Quadlet workflow (after modifying .container files)
systemctl --user daemon-reload
systemctl --user restart <service>.service
```

---

## Recent Developments (Oct 25 - Nov 6, 2025)

### Phase 1: Monitoring Stack Deployment ✅
- Deployed Prometheus with 5 scrape targets
- Deployed Grafana with datasource provisioning
- Deployed Loki + Promtail for log aggregation
- Created journal export pipeline with rotation
- Enabled Traefik Prometheus metrics endpoint

### Phase 2: Enrichment & Observability ✅
- **Traefik Metrics**: Enabled comprehensive metrics (entrypoints, routers, services, response times)
- **Grafana Dashboards**: Created Traefik Overview dashboard (8 panels covering request rates, errors, latencies, status codes)
- **cAdvisor**: Attempted deployment, blocked by rootless Podman + SELinux incompatibility (skipped)
- **Network Fixes**: Added Traefik to monitoring network for Prometheus scraping
- **Datasource UIDs**: Fixed Grafana datasource provisioning (Prometheus uid=prometheus, Loki uid=loki)

### Critical Actions Completed ✅
- **Log Rotation**: Implemented systemd timer-based rotation (hourly check, 100MB threshold, keep 3 compressed)
- **IP Whitelisting**: Applied monitoring-api-whitelist to Prometheus and Loki routes
- **Secret Management**: Externalized CrowdSec API key to Podman secrets (improved git repository safety)

### Security Improvements ✅
- Implemented Traefik entrypoint wrapper for secret injection
- Applied IP whitelisting to monitoring APIs (LAN + VPN only)
- Configured proper middleware ordering on all routes

---

## Current System Metrics

### Resource Usage (Approximate)
- **CPU**: ~2-3% baseline (monitoring stack), spikes during transcoding
- **Memory**: ~1.5GB total across all containers
- **Disk**:
  - System SSD: 94% full (39GB used, 3GB free) ⚠️ **Monitor closely**
  - BTRFS pool: Plenty of space for media/data

### Service Health
- All production services: **Healthy** ✅
- Certificate validity: Valid until next auto-renewal
- Monitoring targets: 5/5 up
- Log pipeline: Operational

---

## Known Issues & Technical Debt

### Active Issues
1. **System SSD at 94% capacity** ⚠️
   - Root cause: No automated cleanup of old journal exports (now resolved with rotation)
   - Mitigation: Log rotation implemented, monitor growth

2. **cAdvisor incompatibility**
   - Cannot deploy due to rootless Podman + SELinux restrictions
   - Workaround: Using Traefik metrics for service-level observability

### Deprecation Warnings
- `IPWhiteList` middleware deprecated (should migrate to `IPAllowList`)
- Affects: `monitoring-api-whitelist` middleware

### Planned Improvements
- Complete Authelia production deployment with YubiKey 2FA
- Deploy Alertmanager with notification channels
- Implement BTRFS snapshot automation
- Create backup verification system
- Document runbooks for common failure scenarios
- Deploy CrowdSec local API + bouncer activation

---

## Next Steps (Recommended Priority Order)

### Immediate (Trajectory 3: Operational Resilience)
1. ✅ ~~Deploy Alertmanager~~ (1 day)
2. ✅ ~~Create critical alert rules~~ (disk space, service down, cert expiry)
3. ✅ ~~Implement BTRFS snapshot automation~~ (1-2 days)
4. ✅ ~~Document backup/restore procedures~~ (1 day)
5. ✅ ~~Test restore procedure~~ (half day)

**Rationale**: Build operational resilience before expanding services. Alerting closes the observability loop, automated backups protect against data loss.

### Short-term (1-2 weeks)
- Complete CrowdSec deployment (local API + active blocking)
- Migrate from IPWhiteList to IPAllowList middleware
- Add uptime tracking dashboard (SLO/SLI monitoring)
- Implement off-site config backup (rclone to cloud)

### Medium-term (1 month)
- Complete Authelia SSO with hardware 2FA
- Deploy additional self-hosted services (Nextcloud, Vaultwarden, Paperless-NGX)
- Implement quarterly backup restore drills
- Create comprehensive runbook documentation

---

## Repository Structure

```
~/containers/
├── .gitignore               - Comprehensive ignore rules (secrets, databases, logs)
├── CLAUDE.md                - AI assistant context (architecture principles, common tasks)
├── README.md                - Repository overview and quick start
├── config/                  - Service configurations (git tracked)
│   ├── traefik/
│   │   ├── traefik.yml      - Static config (entrypoints, providers, ACME)
│   │   └── dynamic/         - Dynamic configs (routers, middleware, TLS)
│   ├── grafana/
│   │   └── provisioning/    - Datasources and dashboards
│   ├── prometheus/
│   │   └── prometheus.yml   - Scrape targets and retention
│   └── loki/
│       └── loki-config.yml  - Log retention and storage
├── scripts/                 - Management automation (git tracked)
├── docs/                    - Comprehensive documentation (git tracked)
│   ├── 00-foundation/       - Design patterns and architecture
│   ├── 30-security/         - Security configurations and guides
│   ├── 40-monitoring-and-documentation/
│   └── 99-reports/          - System state reports and diagnostics
├── quadlets/                - Symlink to ~/.config/containers/systemd (Quadlet definitions)
└── secrets/                 - Sensitive credentials (git ignored, chmod 600)
```

---

## Additional Repository Use Cases

Beyond configuration backup and documentation, consider:

### 1. **Disaster Recovery**
- **Use Case**: Bare-metal restore after system failure
- **Implementation**: Document complete rebuild procedure (OS install → Quadlet deployment)
- **Files Needed**: `docs/00-foundation/DISASTER-RECOVERY.md` with step-by-step rebuild guide

### 2. **Change Management & Audit Trail**
- **Use Case**: Track configuration changes over time, identify when issues were introduced
- **Implementation**: Detailed commit messages with context (what changed, why, expected impact)
- **Benefit**: `git log` and `git blame` become troubleshooting tools

### 3. **Environment Replication**
- **Use Case**: Deploy identical homelab setup on second machine (dev/test environment)
- **Implementation**: Document environment-specific variables (IP addresses, paths)
- **Benefit**: Test changes before applying to production

### 4. **Knowledge Sharing**
- **Use Case**: Share homelab architecture with community, contribute to open-source homelab resources
- **Implementation**: Public repository (after scrubbing any remaining sensitive data)
- **Benefit**: Help others learn from your architecture decisions

### 5. **Automated Testing (Future)**
- **Use Case**: CI/CD pipeline to validate configuration changes
- **Implementation**: GitHub Actions to lint YAML, check for common misconfigurations
- **Benefit**: Catch errors before deployment

### 6. **Multi-Site Deployment**
- **Use Case**: Deploy similar services at multiple locations (home + vacation property)
- **Implementation**: Branch-per-location or environment variable templating
- **Benefit**: Centralized maintenance, consistent security posture

---

## System Access

### Web Interfaces
- **Traefik Dashboard**: http://localhost:8080/dashboard/ (host access only)
- **Grafana**: https://grafana.patriark.org (credentials: patriark / [password in secrets])
- **Prometheus**: https://prometheus.patriark.org (Tinyauth + IP whitelist)
- **Jellyfin**: https://jellyfin.patriark.org (Tinyauth required)

### SSH Access
- Host: fedora-htpc.lokal (LAN) or via WireGuard VPN
- Authentication: YubiKey-based SSH keys (ed25519)

---

## Support & Troubleshooting

### Quick Diagnostics
```bash
# System overview
~/containers/scripts/homelab-diagnose.sh

# Service-specific status
~/containers/scripts/jellyfin-status.sh

# Check all container health
podman ps --all --format "table {{.Names}}\t{{.Status}}\t{{.State}}"

# View service logs
journalctl --user -u <service>.service -n 100
```

### Common Issues
See `docs/00-foundation/20251025-configuration-design-quick-reference.md` for troubleshooting procedures.

---

## Change Log (Recent)

**2025-11-06**:
- Deployed Traefik metrics and Grafana dashboard
- Fixed Grafana datasource UID provisioning issue
- Implemented journal log rotation (systemd timer-based)
- Externalized CrowdSec API key to Podman secrets
- Added IP whitelisting to monitoring APIs
- Updated Traefik to monitoring network for Prometheus scraping

**2025-11-05**:
- Deployed Prometheus, Grafana, and Loki monitoring stack
- Created journal export pipeline with Promtail
- Added Node Exporter for host metrics
- Configured Prometheus scrape targets

**2025-10-25**:
- Deployed Jellyfin media server
- Configured Traefik with Let's Encrypt
- Implemented network segmentation
- Created comprehensive documentation structure

---

**Document Maintained By**: Claude Code (AI Assistant)
**Human Administrator**: patriark
**Review Frequency**: After major changes or monthly
