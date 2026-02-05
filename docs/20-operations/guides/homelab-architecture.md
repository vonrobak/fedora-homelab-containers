# Homelab Architecture Documentation

**Last Updated:** February 5, 2026
**Status:** Production Ready
**Health Score:** 100/100 (as of 2026-02-05)

---

## Table of Contents

1. [Overview](#overview)
2. [Network Architecture](#network-architecture)
3. [Service Stack](#service-stack)
4. [Deployment Ecosystem](#deployment-ecosystem)
5. [Security Layers](#security-layers)
6. [DNS Configuration](#dns-configuration)
7. [Storage & Data](#storage--data)
8. [Backup Strategy](#backup-strategy)
9. [Monitoring & Observability](#monitoring--observability)
10. [Autonomous Operations](#autonomous-operations)
11. [Expansion Guide](#expansion-guide)
12. [Maintenance](#maintenance)

---

## Overview

### Current State

**Infrastructure:** 28 rootless Podman containers across 14 service groups on Fedora Linux
**Orchestration:** Systemd quadlets with pattern-based deployment
**Accessibility:** Internet-accessible with 7-layer defense-in-depth security
**Autonomous:** Daily OODA loop, predictive maintenance, drift detection

### Technology Stack

```
Operating System:  Fedora Workstation 43
Container Runtime: Podman (rootless, UID 1000)
Orchestration:     Systemd Quadlets (~/.config/containers/systemd/)
Reverse Proxy:     Traefik v3 (dynamic config, no container labels)
Authentication:    Authelia SSO (YubiKey/WebAuthn + TOTP)
Security:          CrowdSec IP reputation + layered middleware
DNS:               Cloudflare (external) + Pi-hole (internal)
SSL:               Let's Encrypt (automated, TLS 1.2+)
Network:           UniFi Dream Machine Pro
Storage:           BTRFS (SSD + 14.5TB HDD pool, 4 drives)
Monitoring:        Prometheus + Grafana + Loki + Alertmanager
```

---

## Network Architecture

### Physical Network

```
Internet (ISP) → Public IP (dynamic, DDNS every 30min)
    ↓
UDM Pro (gateway/firewall)
    ├── Port Forward: 80/443 → fedora-htpc
    ├── DHCP / Firewall / IDS
    └── Local Network (192.168.1.0/24)
        ├── fedora-htpc - Container host
        ├── raspberrypi - Pi-hole DNS
        └── Other devices
```

### Container Networks (8 custom networks)

Services are segmented across 8 Podman bridge networks based on trust boundaries.
Key principle: **First `Network=` line in a quadlet gets the default route** (determines internet access).

```
┌─────────────────────────────────────────────────────────────┐
│  reverse_proxy (10.89.2.0/24) — 15 containers              │
│  Internet-facing services. Traefik routes to all backends.  │
│  Has default route (internet access).                       │
│  Members: traefik, crowdsec, authelia, homepage, jellyfin,  │
│           immich-server, nextcloud, vaultwarden, grafana,   │
│           prometheus, loki, alertmanager, gathio,           │
│           home-assistant, alert-discord-relay                │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  monitoring (10.89.1.0/24) — 17 containers                 │
│  Observability stack. Cross-network scraping.               │
│  Members: prometheus, grafana, loki, promtail, alertmanager,│
│           cadvisor, node_exporter, unpoller,                │
│           alert-discord-relay, + most services for scraping │
└─────────────────────────────────────────────────────────────┘

┌───────────────────────────┐  ┌──────────────────────────────┐
│  auth_services            │  │  media_services              │
│  (10.89.3.0/24) — 3      │  │  Jellyfin media isolation    │
│  authelia, traefik,       │  │  Members: jellyfin           │
│  redis-authelia           │  │                              │
└───────────────────────────┘  └──────────────────────────────┘

┌───────────────────────────┐  ┌──────────────────────────────┐
│  photos                   │  │  nextcloud                   │
│  Immich stack isolation   │  │  Nextcloud ecosystem         │
│  Members: immich-server,  │  │  Members: nextcloud,         │
│  immich-ml, postgresql-   │  │  collabora, nextcloud-db,    │
│  immich, redis-immich     │  │  nextcloud-redis             │
└───────────────────────────┘  └──────────────────────────────┘

┌───────────────────────────┐  ┌──────────────────────────────┐
│  home_automation          │  │  gathio                      │
│  Smart home stack         │  │  Event management            │
│  Members: home-assistant, │  │  Members: gathio, gathio-db  │
│  matter-server            │  │                              │
└───────────────────────────┘  └──────────────────────────────┘
```

### Logical Request Flow

```
Internet Request → DNS (Cloudflare) → Port Forward (UDM Pro :80/:443)
    ↓
[1] CrowdSec IP Reputation (cache lookup — fastest, fail-fast)
    ↓
[2] Rate Limiting (tiered: 50-400 req/min depending on service)
    ↓
[3] Authentication
    ├── Authelia SSO (YubiKey/WebAuthn + TOTP) for admin services
    └── Native auth for Jellyfin, Immich, Nextcloud, Vaultwarden, HA
    ↓
[4] Security Headers (HSTS, CSP, X-Frame-Options)
    ↓
Backend Service
```

### Multi-Network DNS (ADR-018)

Services on multiple networks use static IP assignment + Traefik /etc/hosts override to ensure predictable routing. Without this, Podman's aardvark-dns returns IPs in undefined order, causing untrusted-proxy errors.

**See:** `docs/00-foundation/decisions/2026-02-04-ADR-018-static-ip-multi-network-services.md`

---

## Service Stack

### Production Services (14 service groups, 28 containers)

#### Core Infrastructure

| Service | Container(s) | Network(s) | Purpose |
|---------|-------------|------------|---------|
| **Traefik** | traefik | reverse_proxy, auth_services, monitoring | Reverse proxy, SSL termination, routing |
| **CrowdSec** | crowdsec | reverse_proxy, monitoring | IP reputation, threat intelligence |
| **Authelia** | authelia, redis-authelia | reverse_proxy, auth_services, monitoring | SSO + YubiKey MFA |

#### User Applications

| Service | Container(s) | Network(s) | Auth Method | URL Pattern |
|---------|-------------|------------|-------------|-------------|
| **Homepage** | homepage | reverse_proxy, monitoring | Authelia | home.* |
| **Jellyfin** | jellyfin | reverse_proxy, media_services, monitoring | Native | jellyfin.* |
| **Immich** | immich-server, immich-ml, postgresql-immich, redis-immich | reverse_proxy, photos, monitoring | Native | photos.* |
| **Nextcloud** | nextcloud, collabora, nextcloud-db, nextcloud-redis | reverse_proxy, nextcloud, monitoring | Native | nextcloud.* |
| **Vaultwarden** | vaultwarden | reverse_proxy, monitoring | Native | vault.* |
| **Gathio** | gathio, gathio-db | reverse_proxy, gathio, monitoring | Authelia | events.* |
| **Home Assistant** | home-assistant, matter-server | reverse_proxy, home_automation, monitoring | Native | ha.* |

#### Monitoring & Observability

| Service | Container(s) | Network(s) | Purpose |
|---------|-------------|------------|---------|
| **Prometheus** | prometheus | reverse_proxy, monitoring | Metrics collection |
| **Grafana** | grafana | reverse_proxy, monitoring | Dashboards & visualization |
| **Loki** | loki | reverse_proxy, monitoring | Log aggregation |
| **Alertmanager** | alertmanager | monitoring | Alert routing (Discord) |
| **Promtail** | promtail | monitoring | Log shipping to Loki |
| **cAdvisor** | cadvisor | monitoring | Container metrics |
| **Node Exporter** | node_exporter | monitoring | Host system metrics |
| **UnPoller** | unpoller | monitoring | UniFi network metrics |
| **Alert Discord Relay** | alert-discord-relay | reverse_proxy, monitoring | Alertmanager → Discord |

### Internal-Only Services (no public route)

- **Collabora** - Document editing server (accessed by Nextcloud internally)
- **Alertmanager** - Alert routing (access via Grafana or direct container exec)
- **All databases/Redis instances** - Backend-only, no Traefik routing

### Authentication Model

| Auth Method | Services | Rationale |
|-------------|----------|-----------|
| **Authelia SSO** | Homepage, Traefik Dashboard, Grafana, Prometheus, Loki, Gathio | Admin/monitoring tools — centralized auth |
| **Native auth** | Jellyfin, Immich, Nextcloud, Vaultwarden, Home Assistant | Mobile apps, WebDAV clients need direct auth |

---

## Deployment Ecosystem

### Configuration Philosophy (ADR-016)

**ALL Traefik routing in dynamic config files. NEVER in container labels.**

- **Quadlet files** (`~/.config/containers/systemd/`) = deployment: image, volumes, networks, resources
- **Traefik dynamic config** (`config/traefik/dynamic/`) = routing: rules, middleware chains, TLS
- **Never mix** — single source of truth for each concern

### Pattern-Based Deployment

9 battle-tested patterns for consistent deployments:

| Pattern | Examples | Resource Tier |
|---------|----------|---------------|
| `media-server-stack` | Jellyfin, Plex | High (4GB+, GPU) |
| `web-app-with-database` | Wiki.js, Bookstack | Medium (2GB) |
| `document-management` | Paperless-ngx, Nextcloud | High (3GB+, OCR) |
| `authentication-stack` | Authelia + Redis | Low (512MB) |
| `password-manager` | Vaultwarden | Low (512MB) |
| `database-service` | PostgreSQL, MySQL | Medium (2GB, NOCOW) |
| `cache-service` | Redis, Memcached | Low (256-512MB) |
| `reverse-proxy-backend` | Internal services | Low (512MB) |
| `monitoring-exporter` | node_exporter, cAdvisor | Minimal (128MB) |

**Deploy:**
```bash
cd .claude/skills/homelab-deployment
./scripts/deploy-from-pattern.sh \
  --pattern web-app-with-database \
  --service-name wiki \
  --hostname wiki.example.org \
  --memory 2G
```

**See:** `docs/10-services/guides/pattern-selection-guide.md`

---

## Security Layers

### Defense in Depth (7 layers, fail-fast ordering)

```
Layer 7: Container Isolation (rootless, SELinux enforcing, UID 1000)
Layer 6: Network Segmentation (8 isolated Podman networks)
Layer 5: Security Headers (HSTS, CSP, X-Frame-Options)
Layer 4: Authentication (Authelia YubiKey/WebAuthn + TOTP, or native)
Layer 3: Rate Limiting (tiered: 50-400 req/min by service type)
Layer 2: Threat Intelligence (CrowdSec IP reputation, behavioral analysis)
Layer 1: Port Filtering (UDM Pro firewall, only 80/443 exposed)
```

### Middleware Chains (per-service in routers.yml)

**Authelia-protected services:**
`crowdsec-bouncer → rate-limit → authelia → security-headers`

**Native-auth services (Jellyfin, Immich, Nextcloud, Vaultwarden, HA):**
`crowdsec-bouncer → rate-limit-{service} → [circuit-breaker] → [retry] → security-headers`

### Vulnerability Management

- **Weekly:** Automated CVE scanning (Sundays 06:00)
- **Monthly:** Security audit (`scripts/security-audit.sh`, 40+ checks)
- **Continuous:** CrowdSec behavioral analysis + global threat intelligence

---

## DNS Configuration

### External DNS (Cloudflare)

- Wildcard A record: `*.example.org` → public IP (dynamic)
- DDNS updates: Every 30 minutes via `scripts/cloudflare-ddns.sh` + systemd timer
- Cloudflare API token stored in `secrets/cloudflare_token`

### Internal DNS (Pi-hole)

- Local resolution: `*.example.org` → server LAN IP
- Benefit: LAN traffic stays local (no hairpin NAT)

---

## Storage & Data

### Directory Structure

```
~/containers/
├── config/                 # Service configurations (git-tracked)
│   ├── traefik/           # Static + dynamic config
│   │   ├── traefik.yml    # Static config (entry points, providers)
│   │   └── dynamic/       # Watched by Traefik (auto-reload)
│   │       ├── routers.yml      # All routes + services
│   │       ├── middleware.yml   # Security middleware chains
│   │       ├── tls.yml          # TLS 1.2+ config
│   │       └── rate-limit.yml   # Tiered rate limits
│   ├── authelia/          # SSO config
│   ├── crowdsec/          # Threat detection config
│   ├── prometheus/        # Scrape targets, recording rules, alerts
│   ├── grafana/           # Provisioned dashboards & datasources
│   ├── loki/              # Log aggregation config
│   └── homepage/          # Dashboard widget config
│
├── data/                   # Runtime data (gitignored, on BTRFS pool)
│   ├── crowdsec/          # Threat database
│   └── backup-logs/       # Backup operation logs
│
├── quadlets/              # Symlink → ~/.config/containers/systemd/
│                           # All 28 .container files + .network files
│
├── scripts/               # 65+ automation scripts (git-tracked)
├── secrets/               # API tokens, passwords (gitignored, chmod 600)
├── docs/                  # Documentation (373 files, git-tracked)
└── .claude/               # Claude Code skills, agents, hooks
```

### BTRFS Storage Pool

- **Capacity:** 14.55 TiB (4 drives, single data / RAID1 metadata)
- **Usage:** ~73% (10.54 TiB used, 4.01 TiB free)
- **Snapshots:** Daily automated at `/mnt/btrfs-pool/.snapshots/`
- **NOCOW:** Applied to database directories (Prometheus, Loki, PostgreSQL) to avoid CoW fragmentation

### System SSD

- **Capacity:** 118GB
- **Usage:** ~64% (normal range)
- **Thresholds:** Normal <70% | Warning >75% | Critical >85%

---

## Backup Strategy

### Three Pillars

1. **Local BTRFS Snapshots**
   - Daily automated, 14+ day retention
   - RTO: <10 minutes (validated)
   - RPO: 24 hours

2. **Git Version Control**
   - Configs, quadlets, docs, scripts tracked on GitHub
   - Full history, instant config recovery

3. **External Backup**
   - WD-18TB drive, validated restore (81,716 files)
   - Off-site capability for catastrophic recovery

### Disaster Recovery Runbooks

| Runbook | Scenario | RTO | Status |
|---------|----------|-----|--------|
| DR-001 | System SSD Failure | ~6 min | Validated |
| DR-002 | BTRFS Pool Corruption | Hours | Tested |
| DR-003 | Accidental Deletion | ~6 min | Validated 2025-12-31 |
| DR-004 | Total Catastrophe | Days | Validated 2026-01-03 |

---

## Monitoring & Observability

### Stack

```
Prometheus (metrics) → Grafana (dashboards) → Alertmanager (Discord)
                  ↗                                    ↗
Node Exporter (host)     Loki (logs) ← Promtail (shipping)
cAdvisor (containers)    UnPoller (UniFi network)
```

### SLO Framework

9 SLOs across 5 services (Traefik, Authelia, Jellyfin, Immich, Nextcloud):
- Burn-rate alerting (Tier 1: critical, Tier 2: high)
- Error budget tracking via Prometheus recording rules
- Monthly compliance reporting

**Dashboard:** Grafana SLO dashboard
**Reference:** `docs/40-monitoring-and-documentation/guides/slo-framework.md`

### Alerting

- **Route:** Alertmanager → Alert Discord Relay → Discord webhook
- **Tiers:** Critical (page immediately), High (within 1h), Warning (daily digest)
- **Daily error digest:** Automated aggregation at 07:00

---

## Autonomous Operations

### OODA Loop

Daily automated cycle: **Observe → Orient → Decide → Act**

- **Schedule:** 06:00 (predictive maintenance) + 06:30 (OODA assessment)
- **Safety:** Circuit breaker on failures, BTRFS snapshots before actions
- **Protected services:** Traefik and Authelia exempt from auto-restart
- **Decision confidence:** >90% required for execution

### Capabilities

| Capability | Schedule | Status |
|-----------|----------|--------|
| Health scoring (0-100) | On-demand | Operational |
| Predictive maintenance | Daily 06:00 | Operational |
| OODA assessment | Daily 06:30 | Operational |
| Drift detection | Daily | Operational |
| Resource forecasting | Daily | Operational |
| Natural language queries | On-demand (cached) | Operational |
| Alert-driven remediation | Real-time (webhook) | Operational |

### Systemd Timers (53 active)

Key scheduled operations:
- Every 5 min: Nextcloud cron, dependency metrics
- Every 30 min: Cloudflare DDNS
- Hourly: Journal log rotation
- Daily: BTRFS backup, SLO snapshot, drift check, resource forecast, error digest, auto-doc
- Weekly: Intelligence report, vulnerability scan, podman auto-update, database maintenance
- Monthly: SLO report, remediation report, skill usage report
- Biweekly: Backup restore test

---

## Expansion Guide

### Adding a New Service

1. **Design:** Consult `infrastructure-architect` subagent for network topology and pattern selection
2. **Deploy:** Use pattern-based deployment or manual quadlet creation
3. **Route:** Add to `config/traefik/dynamic/routers.yml` (never use container labels)
4. **Verify:** Run `service-validator` subagent for 7-level verification
5. **Clean:** Use `code-simplifier` subagent for post-deployment refactoring
6. **Commit:** Use `/commit-push-pr` for git workflow

### Network Ordering Rule

When a container needs multiple networks, **the first `Network=` line gets the default route**:

```ini
# Correct: reverse_proxy first (has internet access)
Network=systemd-reverse_proxy.network
Network=systemd-monitoring.network

# Wrong: monitoring first (no internet, breaks outbound connectivity)
Network=systemd-monitoring.network
Network=systemd-reverse_proxy.network
```

---

## Maintenance

### Automated (no manual action needed)

- DDNS updates (every 30 min)
- CrowdSec threat updates (continuous)
- Container health checks (every 10-30s)
- SSL certificate renewal (Let's Encrypt)
- BTRFS snapshots (daily)
- Log rotation (hourly)
- Documentation regeneration (daily 07:00)

### Weekly Review

```bash
./scripts/homelab-intel.sh              # Health score + recommendations
./scripts/check-drift.sh                # Config drift detection
./scripts/security-audit.sh             # Security baseline
```

### Update Workflow

```bash
~/containers/scripts/update-before-reboot.sh  # Before DNF updates
# Uses :latest tags for most services
# Databases pinned to major version
# Immich pinned to specific version
# Rollback via BTRFS snapshots
```

---

**Document Version:** 3.0
**Previous versions:** [v1.0 archived from Nov 2025](../../90-archive/)
