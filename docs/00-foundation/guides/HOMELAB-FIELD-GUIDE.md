# Homelab Field Guide

**Purpose:** Operational manual for independently maintaining a healthy, secure homelab
**Audience:** The human operator -- you, without LLM assistance
**Last Updated:** 2026-02-13
**Philosophy:** Understand the system, follow the patterns, verify your work

---

## Table of Contents

### Orientation
- [Mission & Philosophy](#mission--philosophy)
- [System Overview](#system-overview)
- [Quick Start for New Operators](#quick-start-for-new-operators)

### Operations
- [Daily Operations](#daily-operations)
- [Deployment Workflow](#deployment-workflow)
- [Weekly & Monthly Maintenance](#weekly--monthly-maintenance)
- [Update Management](#update-management)

### Troubleshooting
- [Troubleshooting Decision Tree](#troubleshooting-decision-tree)
- [Common Gotchas & Hard-Won Lessons](#common-gotchas--hard-won-lessons)
- [Emergency Procedures](#emergency-procedures)
- [Disaster Recovery](#disaster-recovery)

### Security
- [Security Architecture](#security-architecture)
- [Incident Response](#incident-response)
- [CrowdSec Management](#crowdsec-management)
- [Secrets Management](#secrets-management)

### Monitoring
- [Alert Architecture](#alert-architecture)
- [SLO Framework](#slo-framework)
- [Grafana & Loki](#grafana--loki)

### Home Automation
- [Home Assistant Operations](#home-assistant-operations)

### System Administration
- [Fedora & BTRFS Essentials](#fedora--btrfs-essentials)

### Reference
- [Essential Commands](#essential-commands)
- [Documentation Map](#documentation-map)
- [Best Practices](#best-practices)

---

## Quick Jump to Common Scenarios

| I need to... | Section | Time |
|---|---|---|
| **Check system health** | [Daily Operations](#morning-health-check) | 5 min |
| **Deploy a new service** | [Deployment Workflow](#deployment-workflow) | 10-20 min |
| **Restore a deleted file** | [Disaster Recovery](#disaster-recovery) | 6 min |
| **Respond to a brute force attack** | [Incident Response](#incident-response) | 10 min |
| **Fix a critical CVE** | [Incident Response](#incident-response) | Hours |
| **Service won't start** | [Troubleshooting](#step-2-service-specific) | 15 min |
| **Disk is >90% full** | [Emergency Procedures](#disk-full-emergency) | 5 min |
| **Update Fedora packages** | [Update Management](#update-management) | 30 min |
| **Container has wrong network route** | [Common Gotchas](#dns-resolution-ordering) | 10 min |
| **Run security audit** | [Security Architecture](#monthly-security-audit) | 20 min |
| **Check SLO compliance** | [SLO Framework](#slo-framework) | 5 min |
| **Find any command** | [Essential Commands](#essential-commands) | 2 min |
| **Understand a Home Assistant automation** | [Home Assistant Operations](#home-assistant-operations) | 10 min |

---

## Mission & Philosophy

**Keep the homelab healthy, secure, and reliable** through disciplined operational habits.

**Core Principles:**
1. **Health before action** -- check `homelab-intel.sh` before deployments
2. **Pattern-first** -- use proven templates, customize after
3. **Verify always** -- confirm changes applied, check drift
4. **Document intent** -- commit messages explain WHY, not WHAT
5. **Fail gracefully** -- understand before fixing, never brute force

*"A healthy homelab is a boring homelab. Boring is good."*

---

## System Overview

### Hardware

| Host | Hardware | Role | IP |
|---|---|---|---|
| **fedora-htpc** | Ryzen 5 5600G, 32GB RAM, 128GB NVMe + 14.5TB BTRFS pool | Container host (27 containers) | .70 |
| **fedora-jern** | Ryzen 7 3800XT, 16GB RAM, RX 6700 XT 12GB | Gaming PC (untapped GPU resource) | .71 |
| **raspberrypi** | Raspberry Pi 4 | Pi-hole DNS | .69 |
| **MacBook Air** | M2 | Command center | .11 |

### Platform

| Component | Value |
|---|---|
| OS | Fedora Workstation 43 |
| Kernel | 6.18.7-200.fc43.x86_64 |
| Runtime | Podman (rootless, UID 1000, SELinux enforcing) |
| Orchestration | systemd quadlets symlinked from `~/containers/quadlets/` |
| Networks | 8 segmented Podman networks |
| Containers | 27 running, 13 service groups |

### Services (13 groups, 27 containers)

**Core Infrastructure:**
- **Traefik** -- reverse proxy, Let's Encrypt SSL, layered middleware
- **CrowdSec** -- IP reputation, automatic banning
- **Authelia + Redis** -- SSO with YubiKey/WebAuthn MFA

**Applications:**
- **Nextcloud + MariaDB + Redis** -- file sync (v32.0.5, Hub 11)
- **Immich + PostgreSQL + Redis + ML** -- photo management (v2.5.5, 10,608 assets)
- **Jellyfin** -- media streaming
- **Vaultwarden** -- password manager
- **Gathio + MongoDB** -- event management
- **Homepage** -- dashboard

**Home Automation:**
- **Home Assistant** -- smart home hub (40 automations, 20+ devices)
- **Matter Server** -- Matter protocol support

**Monitoring:**
- Prometheus, Grafana, Loki, Alertmanager, Promtail, cAdvisor, Node Exporter, UnPoller, Alert Discord Relay

### Network Architecture (8 networks)

| Network | Subnet | Purpose | Services |
|---|---|---|---|
| `reverse_proxy` | 10.89.2.0/24 | Internet-facing, default route | Traefik + all web services |
| `monitoring` | 10.89.4.0/24 | Metrics collection | Prometheus, Grafana, Loki, exporters |
| `auth_services` | 10.89.3.0/24 | Auth backend | Authelia, Redis |
| `nextcloud` | 10.89.5.0/24 | File sync | Nextcloud, MariaDB, Redis |
| `photos` | 10.89.7.0/24 | Photo processing | Immich stack |
| `media_services` | 10.89.1.0/24 | Media isolation | Jellyfin |
| `home_automation` | 10.89.6.0/24 | Smart home | Home Assistant, Matter Server |
| `gathio` | 10.89.0.0/24 | Events | Gathio, MongoDB |

Multi-network services use **static IPs** on the `reverse_proxy` network (see [ADR-018](#dns-resolution-ordering) and [Common Gotchas](#dns-resolution-ordering)).

Full topology diagrams: [AUTO-NETWORK-TOPOLOGY.md](../../AUTO-NETWORK-TOPOLOGY.md)

### Storage Layout

| Location | Size | Use | Notes |
|---|---|---|---|
| `/` (NVMe SSD) | 118GB (64% used) | OS, configs, quadlets | Keep <75% |
| `/mnt/btrfs-pool` | 14.5TB (74% used) | Media, photos, databases | NOCOW for DBs |
| WD-18TB external | 17TB | Weekly backups | LUKS encrypted |

---

## Quick Start for New Operators

**Day 1:** Read this guide (focus on Mission, Daily Operations, Troubleshooting). Run `./scripts/homelab-intel.sh`. Browse [homelab-architecture.md](../../20-operations/guides/homelab-architecture.md).

**Week 1:** Daily health checks, no changes. Observe baseline behavior. Explore Grafana dashboards at `grafana.patriark.org`.

**Week 2:** Deploy a test service using pattern-based deployment. Follow the [Deployment Workflow](#deployment-workflow) exactly. Remove it afterward.

**Month 1:** Build daily/weekly habits. Respond to your first incident. Get comfortable with `systemctl --user`, `podman logs`, and `journalctl --user`.

---

## Daily Operations

### Morning Health Check

**When:** Start of day | **Time:** 5 minutes | **Skip if:** Health 100/100 for 3+ consecutive days

```bash
# Primary health check
./scripts/homelab-intel.sh

# Quick natural language queries
./scripts/query-homelab.sh "What services are using the most memory?"
./scripts/query-homelab.sh "Show me disk usage"
```

**Decision Matrix:**

| Health Score | Action |
|---|---|
| **90-100** | Normal operations |
| **75-89** | Address warnings when convenient |
| **50-74** | Fix warnings before new deployments |
| **0-49** | Stop everything, fix critical issues |

**Quick manual checks:**
```bash
# All critical services running?
systemctl --user is-active traefik prometheus grafana authelia

# Any failed containers?
podman ps -a --filter "status=exited" --filter "status=dead"

# Disk space OK?
df -h / /mnt/btrfs-pool

# Resource usage
podman stats --no-stream | head -10
```

---

## Deployment Workflow

### The Golden Rule

> ALL Traefik routing is defined in `config/traefik/dynamic/routers.yml`, NEVER in container labels.
> See [ADR-016](../../00-foundation/decisions/2025-12-31-ADR-016-configuration-design-principles.md).

### Quadlet File Management

Quadlet files live in `~/containers/quadlets/` and are **symlinked** to `~/.config/containers/systemd/`. Always edit the source files in the git-tracked directory:

```bash
# Edit a quadlet (always edit the source)
nano ~/containers/quadlets/jellyfin.container

# Changes are instantly reflected via symlink
# Then reload systemd
systemctl --user daemon-reload
systemctl --user restart jellyfin.service
```

### Pattern-Based Deployment (Recommended)

```bash
cd .claude/skills/homelab-deployment

# See available patterns (9 total)
ls -1 patterns/*.yml

# Deploy
./scripts/deploy-from-pattern.sh \
  --pattern <pattern-name> \
  --service-name <name> \
  --hostname <name>.patriark.org \
  --memory <size>
```

**Pattern selection:**
- Media streaming? `media-server-stack`
- Web app + DB? `web-app-with-database`
- Database? `database-service`
- Cache? `cache-service`
- Auth service? `authentication-stack`
- Metrics exporter? `monitoring-exporter`

Full guide: [pattern-selection-guide.md](../../10-services/guides/pattern-selection-guide.md)

### Manual Deployment

For services without a matching pattern:

```bash
# 1. Create quadlet (NO Traefik labels)
nano ~/containers/quadlets/service.container

# 2. Symlink to systemd directory
ln -s ~/containers/quadlets/service.container ~/.config/containers/systemd/

# 3. Add route to Traefik dynamic config
nano ~/containers/config/traefik/dynamic/routers.yml
# Add under http.routers:
#     service-secure:
#       rule: "Host(`service.patriark.org`)"
#       service: "service"
#       middlewares:
#         - crowdsec-bouncer@file
#         - rate-limit@file
#         - authelia@file        # Remove if service has native auth
#         - security-headers@file
#       tls:
#         certResolver: letsencrypt
# Add under http.services:
#     service:
#       loadBalancer:
#         servers:
#           - url: "http://service:port"

# 4. Deploy
systemctl --user daemon-reload
systemctl --user enable --now service.service

# 5. Verify
curl -I https://service.patriark.org
```

### Post-Deployment Verification

**Always verify after deployment:**

```bash
# 1. Service running?
systemctl --user status <service>.service

# 2. Health check passing?
podman healthcheck run <service>

# 3. Traefik routing working?
curl -I https://<service>.patriark.org

# 4. No configuration drift?
./scripts/check-drift.sh <service>

# 5. Logs clean?
podman logs <service> --tail 20
```

---

## Weekly & Monthly Maintenance

### Weekly Routine (20 minutes, Sunday)

```bash
# 1. Full health report
./scripts/homelab-intel.sh

# 2. Drift detection
./scripts/check-drift.sh

# 3. Check for unexpected container restarts
podman ps -a --filter "status=exited"

# 4. Review error logs from the week
journalctl --user --since "1 week ago" --priority=err -n 50

# 5. SLO status
./scripts/slo-status.sh
```

### Monthly Cleanup (30 minutes, first Sunday)

```bash
# 1. Disk usage audit
df -h / /mnt/btrfs-pool
du -sh ~/containers/data/* | sort -h | tail -10

# 2. Clean journal logs (keep 30 days)
journalctl --user --vacuum-time=30d
journalctl --system --vacuum-time=30d

# 3. Prune unused container images
podman system prune -f
# WARNING: Add --volumes only if no containers are intentionally stopped

# 4. Clean old backup logs
find ~/containers/data/backup-logs/ -name "*.log" -mtime +30 -delete

# 5. BTRFS maintenance
sudo btrfs scrub start /mnt/btrfs-pool
sudo btrfs scrub status /mnt/btrfs-pool  # Check for errors

# 6. Security audit
~/containers/scripts/security-audit.sh

# 7. Backup restore test
~/containers/scripts/test-backup-restore.sh
```

**Target baselines:** System disk <70%, BTRFS pool <80%, no scrub errors, security audit PASS

---

## Update Management

### Container Updates

**Strategy:** Most services use `:latest` tags. Databases and Immich are pinned.

```bash
# Pre-update: run the update script (pulls new images, manages restarts)
~/containers/scripts/update-before-reboot.sh

# Manual single-service update
podman pull <image>:<tag>
systemctl --user restart <service>.service

# Verify after update
podman logs <service> --tail 20
podman healthcheck run <service>
```

**Pinned services (require manual version bumps):**
- PostgreSQL (Immich) -- major version needs migration
- MariaDB (Nextcloud) -- major version needs migration
- Immich -- tight coupling between server, ML, and DB

Full strategy: [ADR-015](../../00-foundation/decisions/2025-12-22-ADR-015-container-update-strategy.md)

### Fedora System Updates

```bash
# Check available updates
sudo dnf check-update

# Run pre-update container script first
~/containers/scripts/update-before-reboot.sh

# Apply system updates
sudo dnf upgrade --refresh

# Check if reboot required
sudo dnf needs-restarting -r
# Exit code 1 = reboot needed (kernel update)
# Exit code 0 = no reboot needed

# If reboot needed, verify DNS fix persists afterward:
~/containers/scripts/verify-dns-fix-post-reboot.sh
```

---

## Troubleshooting Decision Tree

### Step 1: System or Service?

```bash
./scripts/homelab-intel.sh
```

- Health >70? Issue is **service-specific** -- go to [Step 2](#step-2-service-specific)
- Health <70? **System-wide** problem -- go to [Step 3](#step-3-system-wide)

### Step 2: Service-Specific

```bash
# A. Status
systemctl --user status <service>.service

# B. Recent logs
journalctl --user -u <service>.service -n 100

# C. Container logs
podman logs <service> --tail 100

# D. Health check
podman healthcheck run <service>

# E. Configuration drift
./scripts/check-drift.sh <service>

# F. Traefik routing (if web service)
# Check dashboard: http://localhost:8080/dashboard/
curl -I https://<service>.patriark.org
```

**Common issues:**
| Symptom | Likely Cause | Fix |
|---|---|---|
| Won't start | Quadlet syntax, missing network, volume path | `systemctl --user daemon-reload`, check paths |
| Keeps restarting | OOM, config error | `podman logs`, check memory limits |
| Not accessible via web | Traefik route missing, DNS | Check `routers.yml`, `dig <subdomain>` |
| Slow performance | Resource exhaustion | `podman stats`, check CPU/memory |
| Permission denied | SELinux, wrong ownership | Add `:Z` to mounts, check `ls -lZ` |

Service-specific guides: [docs/10-services/guides/](../../10-services/guides/)

### Step 3: System-Wide

```bash
# A. Critical services
systemctl --user is-active traefik prometheus grafana authelia

# B. Disk space
df -h / /mnt/btrfs-pool

# C. Memory pressure
free -h
podman stats --no-stream | head -15

# D. System load
uptime

# E. Recent changes
git log --oneline -10
journalctl --system --since "1 day ago" -p warning -n 50
```

**Emergency quick fixes:**
- **Disk >95%:** `podman system prune -af && journalctl --vacuum-time=3d`
- **Memory >95%:** Restart heavy services (Jellyfin, Grafana, Immich)
- **All services down:** Check Traefik first, then cascade restart
- **Can't access anything:** Check UDM Pro port forwarding, Pi-hole DNS

---

## Common Gotchas & Hard-Won Lessons

These are lessons learned the hard way. Each one cost hours of debugging.

### DNS Resolution Ordering (ADR-018) {#dns-resolution-ordering}

**The problem:** Podman's aardvark-dns returns container IPs in **undefined order**. When a multi-network container's monitoring IP resolves before its reverse_proxy IP, Traefik routes through the wrong network. This caused a P0 outage in February 2026.

**The solution:** Static IP assignment + Traefik `/etc/hosts` override.

```ini
# In quadlet: specify IP on reverse_proxy network
Network=systemd-reverse_proxy.network:ip=10.89.2.10
Network=systemd-monitoring.network
```

```
# In config/traefik/hosts: hostname -> reverse_proxy IP
10.89.2.10 service-name
```

**After kernel upgrades/reboots**, verify DNS fix persists:
```bash
~/containers/scripts/verify-dns-fix-post-reboot.sh
```

Full details: [ADR-018](../../00-foundation/decisions/2026-02-04-ADR-018-static-ip-multi-network-services.md)

### First Network Gets Default Route

```ini
# Container CAN reach internet (reverse_proxy first)
Network=systemd-reverse_proxy.network
Network=systemd-monitoring.network

# Container CANNOT reach internet (monitoring first = wrong!)
Network=systemd-monitoring.network
Network=systemd-reverse_proxy.network
```

### SELinux Volume Mounts

All bind mounts need `:Z` for rootless + SELinux enforcing:
```ini
Volume=/path/to/config:/config:Z
# Read-only: Volume=/path/to/data:/data:ro,Z
```

### BTRFS NOCOW for Databases

Database directories need Copy-on-Write disabled (must be set on empty directory):
```bash
mkdir -p /mnt/btrfs-pool/subvol7-containers/newdb
chattr +C /mnt/btrfs-pool/subvol7-containers/newdb
lsattr -d /mnt/btrfs-pool/subvol7-containers/newdb  # Verify 'C' flag
```

Applies to: Prometheus, Loki, Grafana, PostgreSQL (Immich), MariaDB (Nextcloud).

### Traefik Upload Timeouts

Default `readTimeout` (60s) blocks large file uploads. Currently set to **600s** on the websecure entrypoint. If adding a new upload-heavy service, verify this is sufficient.

Config location: `config/traefik/traefik.yml` under `entryPoints.websecure.transport.respondingTimeouts`

### Circuit Breaker vs Upload Services

Circuit breakers trip on client `ECONNRESET` during large uploads (the client disconnects, not a server error). **Do not use circuit breaker middleware on upload-heavy services** like Immich.

Similarly, **retry middleware cannot replay streamed uploads** -- the request body is consumed on first attempt. Don't attach retry middleware to upload routes.

### Quadlet Service Names

Quadlet units are `<name>.service` (e.g., `jellyfin.service`).
Old `podman generate` units were `container-<name>.service`.
If you find old references to `container-` prefixed names, update them.

---

## Emergency Procedures

### Traefik Down (Nothing Accessible)

```bash
systemctl --user status traefik.service
journalctl --user -u traefik.service -n 50
systemctl --user restart traefik.service
curl http://localhost:8080/api/overview  # Verify API
curl -I https://grafana.patriark.org     # Verify routing
```

### Authentication Down

```bash
# Restart Redis first, then Authelia
systemctl --user restart redis-authelia.service
sleep 5
systemctl --user restart authelia.service
curl http://localhost:9091/api/health

# Emergency bypass (TEMPORARY -- service becomes publicly accessible):
# Edit config/traefik/dynamic/routers.yml
# Remove authelia@file from the service's middleware list
# Traefik auto-reloads in ~60s
# RESTORE AUTH after fixing Authelia
```

### Disk Full Emergency {#disk-full-emergency}

```bash
# Immediate relief (5 minutes)
journalctl --user --vacuum-time=1d
journalctl --system --vacuum-time=1d
podman system prune -af --volumes

# Find space consumers
du -sh ~/containers/data/* | sort -h | tail -20

# If system SSD: consider moving data to BTRFS pool
# If BTRFS pool: check snapshot usage with btrfs fi usage /mnt/btrfs-pool
```

### All Containers Restarting After Reboot

This usually means the DNS resolution ordering issue has recurred. Run:
```bash
~/containers/scripts/verify-dns-fix-post-reboot.sh
```

If the fix has been lost, re-apply static IPs per [ADR-018](../../00-foundation/decisions/2026-02-04-ADR-018-static-ip-multi-network-services.md).

---

## Disaster Recovery

### Quick Reference

| Scenario | RTO | Runbook |
|---|---|---|
| **Accidental file deletion** | 6 minutes | [DR-003](../../20-operations/runbooks/DR-003-accidental-deletion.md) |
| **Service config corruption** | 10-20 min | [DR-003](../../20-operations/runbooks/DR-003-accidental-deletion.md) |
| **System SSD failure** | 4-6 hours | [DR-001](../../20-operations/runbooks/DR-001-system-ssd-failure.md) |
| **BTRFS pool corruption** | 6-12 hours | [DR-002](../../20-operations/runbooks/DR-002-btrfs-pool-corruption.md) |
| **Total catastrophe** | 1-2 weeks | [DR-004](../../20-operations/runbooks/DR-004-total-catastrophe.md) |

### Most Common: Restore a Deleted File

```bash
# 1. Find the file in local snapshots (last 7 days)
ls ~/.snapshots/htpc-home/
find ~/.snapshots/htpc-home/YYYYMMDD-htpc-home -name "filename"

# 2. Preview and restore
less ~/.snapshots/htpc-home/YYYYMMDD-htpc-home/path/to/file
cp -a ~/.snapshots/htpc-home/YYYYMMDD-htpc-home/path/to/file ~/path/to/file

# 3. For older files, use external backup
ls /run/media/patriark/WD-18TB/.snapshots/htpc-home/
```

### Pre-Change Safety Net

Before any risky change, take a manual snapshot:
```bash
sudo btrfs subvolume snapshot -r /home \
     ~/.snapshots/htpc-home/$(date +%Y%m%d-%H%M)-pre-change
```

### Backup Verification

Backups run automatically via systemd timers. **Trust but verify monthly:**
```bash
# Check backup status
systemctl --user list-timers | grep backup

# Run restore test
~/containers/scripts/test-backup-restore.sh

# Manual spot check: compare a file between live and backup
diff ~/containers/config/traefik/traefik.yml \
     /run/media/patriark/WD-18TB/.snapshots/htpc-home/LATEST/containers/config/traefik/traefik.yml
```

Full backup strategy: [backup-strategy.md](../../20-operations/guides/backup-strategy.md)

---

## Security Architecture

### Defense-in-Depth Layers

```
Internet -> Port Forward (80/443)
  |
[1] CrowdSec IP Reputation  (cache lookup -- fastest, cheapest)
  |
[2] Rate Limiting            (tiered: 100-600 req/min per service)
  |
[3] Authelia SSO             (YubiKey/WebAuthn + TOTP -- most expensive)
  |
[4] Security Headers         (HSTS, CSP, X-Frame-Options)
  |
Backend Service
```

**Why this order:** Each layer is more expensive than the last. Reject malicious IPs immediately before wasting resources on auth checks.

**Services with native auth** (bypass Authelia): Jellyfin, Immich, Nextcloud, Vaultwarden, Alertmanager

### Monthly Security Audit

```bash
~/containers/scripts/security-audit.sh
# 40+ checks: SELinux, rootless, CrowdSec, Authelia, secrets, TLS, headers, firewall
# Target: all PASS
```

Full security guides: [docs/30-security/guides/](../../30-security/guides/)

---

## Incident Response

### Quick Reference

| Event | Severity | Procedure |
|---|---|---|
| Brute force detected | HIGH | [IR-001](../../30-security/runbooks/IR-001-brute-force-attack.md) |
| Critical CVE found | CRITICAL | [IR-003](../../30-security/runbooks/IR-003-critical-cve.md) |
| Unauthorized port open | MEDIUM | [IR-002](../../30-security/runbooks/IR-002-unauthorized-port.md) |
| Compliance failure | MEDIUM | [IR-004](../../30-security/runbooks/IR-004-compliance-failure.md) |

### Brute Force Response (10 minutes)

```bash
# 1. Check active bans
podman exec crowdsec cscli decisions list

# 2. Check for breach
podman logs authelia --since 1h 2>&1 | grep -i "failed\|unsuccessful" | tail -30

# 3. Verify no successful breach from attacker IP
podman logs authelia --since 24h 2>&1 | grep "<ATTACKER_IP>" | grep -i "success"
# MUST be empty. If not: escalate to IR-005 immediately.

# 4. Extend ban if needed
podman exec crowdsec cscli decisions add --ip <IP> --duration 168h --reason "Persistent brute force"
```

### Critical CVE Response

```bash
# 1. Check which services are affected
~/containers/scripts/scan-vulnerabilities.sh --severity CRITICAL,HIGH

# 2. Pull updated image
podman pull <image>:<tag>

# 3. Restart service
systemctl --user daemon-reload
systemctl --user restart <service>.service

# 4. Verify CVE fixed
~/containers/scripts/scan-vulnerabilities.sh --image <image>
```

If no patch available: add Authelia protection, move to internal network, or disable service. See [IR-003](../../30-security/runbooks/IR-003-critical-cve.md) for full decision tree.

---

## CrowdSec Management

```bash
# Status
podman exec crowdsec cscli bouncers list    # Traefik bouncer connected?
podman exec crowdsec cscli decisions list    # Active bans
podman exec crowdsec cscli alerts list --since 24h
podman exec crowdsec cscli metrics           # Attack pattern stats

# Manual ban
podman exec crowdsec cscli decisions add --ip <IP> --duration 24h --reason "Manual"

# Unban (false positive)
podman exec crowdsec cscli decisions delete --ip <IP>
```

---

## Secrets Management

**Rotation schedule:** Every 90 days (quarterly) or after suspected exposure.

```bash
# List Podman secrets
podman secret ls

# Rotate a secret
podman secret rm service_password
echo -n "new-value" | podman secret create service_password -
systemctl --user restart <service>.service

# Verify no secrets in git before committing
git diff --cached | grep -iE "password|token|secret|key"
```

Full guide: [secrets-management.md](../../30-security/guides/secrets-management.md)

---

## Alert Architecture

### Current State: 65 alerts across 9 files

The alerting system was completely redesigned in January 2026 (5-phase overhaul). Alerts are organized by category:

| File | Alerts | Purpose |
|---|---|---|
| `infrastructure-critical.yml` | Critical infrastructure failures | Traefik, Authelia, CrowdSec down |
| `infrastructure-warnings.yml` | Resource warnings | Disk, memory, CPU thresholds |
| `security-alerts.yml` | Security events | Auth failures, port exposure |
| `service-health.yml` | Application health | Container restarts, health check failures |
| `network-security-alerts.yml` | Network threats | Actionable UDM Pro events |
| `backup-alerts.yml` | Backup failures | Missed backups, stale snapshots |
| `dependency-alerts.yml` | Dependency issues | Service dependency failures |
| `slo-multiwindow-alerts.yml` | SLO burn rate alerts | Fast/slow burn detection |
| `log-based-alerts.yml` | Promtail-extracted metrics | Nextcloud cron, Immich thumbnails |

**Design principle:** Prefer native infrastructure metrics over log parsing. Log-based metrics are fragile (Counter accumulation during rotation causes false positives).

**Meta-monitoring:** 5 alerts watching the monitoring stack itself ("who watches the watchers"). If Prometheus, Loki, or Promtail fail, you get alerted.

Alert config location: `config/prometheus/alerts/`

---

## SLO Framework

### Overview

9 SLOs across 5 services, using Google SRE-style multi-window burn rate alerting.

```bash
# Quick SLO status
./scripts/slo-status.sh

# Full monthly report
./scripts/monthly-slo-report.sh

# Grafana dashboard
# https://grafana.patriark.org/d/slo-dashboard
```

### Key Concepts

- **SLI** = measured metric (e.g., % of successful requests)
- **SLO** = target (e.g., 99.5% over 30 days)
- **Error budget** = allowed failure (0.5% = 216 min/month)
- **Burn rate** = how fast you're consuming budget (>1x = trouble)

### Important Technical Details

**WebSocket connections** use HTTP status `code=0` in Traefik metrics (not an error). SLO queries include `code=~"0|2..|3.."` to correctly count WebSocket traffic as successful. This matters most for Home Assistant (heavy WebSocket use).

**Division by zero** in upload SLOs: when no uploads occur in a 5-minute window, the SLI produces `NaN` (not "no data"). Use `(... or vector(0)) / (... or vector(1))` pattern to handle this safely.

Full framework: [slo-framework.md](../../40-monitoring-and-documentation/guides/slo-framework.md)

---

## Grafana & Loki

### Dashboards

Access: `grafana.patriark.org` (requires Authelia auth)

Key dashboards:
- **SLO Dashboard** -- error budgets and burn rates
- **Security Overview** -- CrowdSec, auth failures, UniFi network monitoring
- **Container Resources** -- CPU, memory, network per container
- **Node Exporter** -- host-level metrics

### Loki Log Analysis

Loki ingests all container logs via Promtail plus Traefik access logs and remediation decision logs.

```bash
# Explore logs in Grafana:
# https://grafana.patriark.org/explore

# Example LogQL queries:
# All errors in last hour:      {job="containers"} |~ "error|ERROR" | line_format "{{.container_name}}: {{.msg}}"
# Traefik 5xx responses:        {job="traefik-access"} | json | status >= 500
# Authelia failed logins:       {container_name="authelia"} |~ "unsuccessful"
```

Full LogQL reference: [loki-remediation-queries.md](../../40-monitoring-and-documentation/guides/loki-remediation-queries.md)

---

## Home Assistant Operations

### Overview

Home Assistant runs as a container on the `home_automation` network with 40 automations across 20+ integrated devices.

**Access:** `ha.patriark.org` | **Config:** `~/containers/config/home-assistant/`

### Integrated Devices

- **Philips Hue** -- 8 bulbs, 1 bridge, 1 remote (local hub control preserved)
- **Roborock Saros S10** -- vacuum + 14 sensors, room-specific cleaning
- **Mill** -- 3 heaters, 1 air sensor (air purifier integration blocked upstream)
- **iOS** -- iPhone 16, iPad Pro, Apple Watch (presence, Siri webhooks, Focus modes)
- **UniFi** -- WiFi presence detection via Prometheus/UnPoller

### Automation Patterns

| Pattern | Count | Example |
|---|---|---|
| Time-based | 10 | Hue lighting schedules |
| Presence-based | 10 | Welcome home, goodbye routines |
| Roborock | 16 | Context-aware room cleaning |
| iOS integration | 4 | Siri webhooks, Focus mode detection |

### Key Operational Knowledge

**Presence detection uses iPhone only for arrival/departure triggers** (iPad's periodic location updates cause false positives). A 2-minute debounce prevents flapping.

**Roborock automations use `mode: single`** to prevent race conditions when multiple state triggers fire simultaneously.

**Entity naming:** Always verify entity IDs match actual HA entities. Silent failures occur when entity names change (e.g., `light.gang` renamed to `light.hallway`).

### Service Management

```bash
systemctl --user status home-assistant.service matter-server.service
systemctl --user restart home-assistant.service
podman logs home-assistant --tail 50
```

Full guide: [home-assistant.md](../../10-services/guides/home-assistant.md)

Apple ecosystem: [apple-ecosystem-quick-reference.md](../../10-services/guides/apple-ecosystem-quick-reference.md)

---

## Fedora & BTRFS Essentials

### Quick System Check

```bash
cat /etc/fedora-release          # OS version
uname -r                         # Kernel version
getenforce                       # SELinux mode (must be Enforcing)
loginctl show-user $USER | grep Linger  # Must be Linger=yes
```

### SELinux for Containers

SELinux must stay **Enforcing**. All container volume mounts use `:Z` labels.

```bash
# Check for recent denials
sudo ausearch -m avc -ts recent | audit2why

# Fix volume label if needed
chcon -R -t container_file_t ~/containers/config/<service>

# NEVER disable SELinux. If something is denied, investigate first.
# Temporary permissive (troubleshooting ONLY):
sudo setenforce 0   # Troubleshoot...
sudo setenforce 1   # Re-enable immediately
```

### BTRFS Maintenance

```bash
# Monthly: run scrub to verify checksums
sudo btrfs scrub start /mnt/btrfs-pool
sudo btrfs scrub status /mnt/btrfs-pool  # Check for errors

# Check filesystem usage
sudo btrfs filesystem usage /mnt/btrfs-pool

# Balance (redistribute data across devices)
sudo btrfs balance start -dusage=10 /mnt/btrfs-pool
```

### Swap Management

The system uses zram (compressed in-memory swap), not disk swap. 2-3GB swap usage is normal with 27 containers. Only investigate if swap grows above 5GB consistently.

```bash
free -h
swapon --show
```

### systemd Timers

```bash
# List all user timers
systemctl --user list-timers

# Key timers to verify are active:
# - nextcloud-cron.timer (every 5 min)
# - cloudflare-ddns.timer (every 30 min)
# - journal-logrotate.timer (hourly)
# - dependency-metrics-export.timer (every 5 min)
# - btrfs-backup-*.timer (daily/weekly)
```

### Failed Services

```bash
# Check for failures
systemctl --user --failed

# Common: timer-triggered services fail on first run after boot
# Usually safe to reset:
systemctl --user reset-failed <service>.service

# Or restart:
systemctl --user restart <service>.service
```

---

## Essential Commands

### System Health
```bash
./scripts/homelab-intel.sh                     # Health score (0-100)
./scripts/query-homelab.sh "your question"     # Natural language query
./scripts/autonomous-check.sh --verbose        # OODA loop assessment
./scripts/check-drift.sh [service]             # Config drift detection
./scripts/security-audit.sh                    # Security audit (40+ checks)
./scripts/slo-status.sh                        # SLO compliance
```

### Service Management
```bash
systemctl --user status <service>.service      # Status
systemctl --user restart <service>.service     # Restart
systemctl --user daemon-reload                 # After quadlet changes
podman logs <service> --tail 50                # Container logs
podman healthcheck run <service>               # Health check
podman stats --no-stream                       # Resource usage
```

### Traefik
```bash
# Dashboard: http://localhost:8080/dashboard/
# All routes: config/traefik/dynamic/routers.yml
# Middleware: config/traefik/dynamic/middleware.yml
# Force reload: podman exec traefik kill -SIGHUP 1
curl -I https://<service>.patriark.org         # Test routing
```

### Monitoring
```bash
curl -f http://localhost:9090/-/healthy        # Prometheus
curl -f http://localhost:3000/api/health       # Grafana
curl -f http://localhost:3100/ready            # Loki
```

### Backups
```bash
~/containers/scripts/btrfs-snapshot-backup.sh --local-only  # Quick local snapshot
~/containers/scripts/btrfs-snapshot-backup.sh --verbose      # Full backup
~/containers/scripts/test-backup-restore.sh                  # Restore test
```

### Documentation
```bash
~/containers/scripts/auto-doc-orchestrator.sh  # Regenerate all auto-docs (~2s)
```

Full script catalog: [automation-reference.md](../../20-operations/guides/automation-reference.md)

---

## Documentation Map

### Where to Find Answers

| Question | Location |
|---|---|
| Architecture overview | [homelab-architecture.md](../../20-operations/guides/homelab-architecture.md) |
| Service-specific help | [docs/10-services/guides/](../../10-services/guides/) |
| How to deploy a service | [pattern-selection-guide.md](../../10-services/guides/pattern-selection-guide.md) |
| Network topology (diagrams) | [AUTO-NETWORK-TOPOLOGY.md](../../AUTO-NETWORK-TOPOLOGY.md) |
| Service catalog (inventory) | [AUTO-SERVICE-CATALOG.md](../../AUTO-SERVICE-CATALOG.md) |
| Dependency graph | [AUTO-DEPENDENCY-GRAPH.md](../../AUTO-DEPENDENCY-GRAPH.md) |
| All scripts reference | [automation-reference.md](../../20-operations/guides/automation-reference.md) |
| SLO targets and queries | [slo-framework.md](../../40-monitoring-and-documentation/guides/slo-framework.md) |
| Monitoring stack | [monitoring-stack.md](../../40-monitoring-and-documentation/guides/monitoring-stack.md) |
| Loki queries | [loki-remediation-queries.md](../../40-monitoring-and-documentation/guides/loki-remediation-queries.md) |
| Security guides | [docs/30-security/guides/](../../30-security/guides/) |
| Disaster recovery runbooks | [docs/20-operations/runbooks/](../../20-operations/runbooks/) |
| Incident response runbooks | [docs/30-security/runbooks/](../../30-security/runbooks/) |
| Autonomous operations | [autonomous-operations.md](../../20-operations/guides/autonomous-operations.md) |
| Drift detection | [drift-detection-workflow.md](../../20-operations/guides/drift-detection-workflow.md) |
| ADRs (design decisions) | [docs/00-foundation/decisions/](../../00-foundation/decisions/) |

### Auto-Generated Docs (refreshed daily at 07:00)

- `AUTO-SERVICE-CATALOG.md` -- service inventory, status, resources
- `AUTO-NETWORK-TOPOLOGY.md` -- network diagrams (Mermaid)
- `AUTO-DEPENDENCY-GRAPH.md` -- 4-tier dependency graph, critical paths
- `AUTO-DOCUMENTATION-INDEX.md` -- complete file catalog

Regenerate manually: `~/containers/scripts/auto-doc-orchestrator.sh`

### Key ADRs to Know

These ADRs affect how you operate the system:

| ADR | Title | Impact |
|---|---|---|
| [001](../../00-foundation/decisions/2025-10-20-decision-001-rootless-containers.md) | Rootless Containers | All containers as UID 1000, `:Z` labels required |
| [002](../../00-foundation/decisions/2025-10-25-decision-002-systemd-quadlets-over-compose.md) | Systemd Quadlets | `systemctl --user` for all container management |
| [015](../../00-foundation/decisions/2025-12-22-ADR-015-container-update-strategy.md) | Update Strategy | `:latest` for most, pin databases and Immich |
| [016](../../00-foundation/decisions/2025-12-31-ADR-016-configuration-design-principles.md) | Config Design | ALL routing in `routers.yml`, never in labels |
| [018](../../00-foundation/decisions/2026-02-04-ADR-018-static-ip-multi-network-services.md) | Static IPs | Multi-network DNS fix, `/etc/hosts` override |

---

## Best Practices

### Before Making Changes

```bash
./scripts/homelab-intel.sh    # Health check
git status                    # Clean working tree?
# Take snapshot if risky:
sudo btrfs subvolume snapshot -r /home \
     ~/.snapshots/htpc-home/$(date +%Y%m%d-%H%M)-pre-change
```

### After Making Changes

```bash
systemctl --user status <service>.service   # Running?
./scripts/check-drift.sh <service>          # No drift?
curl https://<service>.patriark.org         # Accessible?
podman logs <service> --tail 20             # Clean logs?
git add <files> && git commit -m "why"      # Committed?
```

### Habits That Prevent Incidents

1. **Check health before deploying** -- don't pile changes onto a sick system
2. **One change at a time** -- if something breaks, you know what caused it
3. **Read logs before restarting** -- understand the failure, don't just cycle the service
4. **Keep the git repo clean** -- uncommitted changes are invisible changes
5. **Test backups monthly** -- backups you don't test are backups that don't work
6. **Run `daemon-reload` after quadlet edits** -- without it, systemd uses stale config
7. **Verify DNS fix after reboots** -- the ADR-018 static IPs should persist, but verify

### Operational Maturity Levels

| Level | Name | Characteristics |
|---|---|---|
| 1 | Reactive | Fix when broken, no monitoring, manual deploys |
| 2 | Aware | Daily health checks, pattern-based deploys, weekly drift detection |
| 3 | Disciplined | Automated monitoring, proactive maintenance, systematic troubleshooting |
| 4 | Optimized | Predictive capacity planning, automated remediation, continuous improvement |

**Current state: Level 3** -- automated monitoring, 100/100 health, autonomous OODA loop, but some manual maintenance remains.

---

**Document Version:** 3.0 (2026-02-13)
**Maintained By:** patriark + Claude Code
**Review Frequency:** Quarterly or after major system changes
**Next Review:** 2026-05-13

---

*"A healthy homelab is a boring homelab. Boring is good."*
