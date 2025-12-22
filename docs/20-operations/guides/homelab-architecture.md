# Homelab Architecture Documentation

**Last Updated:** November 14, 2025 (Pattern-based deployment adoption)
**Status:** Production Ready ✅
**Owner:** patriark
**Domain:** patriark.org

---

## 📋 Table of Contents

1. [Overview](#overview)
2. [Network Architecture](#network-architecture)
3. [Service Stack](#service-stack)
4. [Deployment Ecosystem](#deployment-ecosystem)
5. [Security Layers](#security-layers)
6. [DNS Configuration](#dns-configuration)
7. [Storage & Data](#storage--data)
8. [Backup Strategy](#backup-strategy)
9. [Service Details](#service-details)
10. [Expansion Guide](#expansion-guide)
11. [Maintenance](#maintenance)
12. [Troubleshooting](#troubleshooting)

---

## 🏗️ Overview

### Current State

**Homelab Type:** Self-hosted infrastructure
**Primary Use:** Media streaming, secure services, learning platform
**Accessibility:** Internet-accessible with multi-layer security
**Infrastructure:** Containerized microservices on Fedora Linux

### Technology Stack

```
Operating System:  Fedora Workstation
Container Runtime: Podman (rootless)
Orchestration:     Systemd Quadlets
Reverse Proxy:     Traefik v3.2
Authentication:    Authelia (SSO + YubiKey MFA)
Security:          CrowdSec + WebAuthn/FIDO2
DNS:               Cloudflare (external) + Pi-hole (internal)
SSL:               Let's Encrypt (automated)
Network:           UniFi Dream Machine Pro
```

### Key Features

- ✅ **Phishing-resistant authentication** - YubiKey/WebAuthn hardware 2FA
- ✅ **Single Sign-On (SSO)** - Authelia provides unified authentication
- ✅ **Zero-trust security** - Multi-factor authentication required for all admin services
- ✅ **Automatic SSL** - Let's Encrypt certificates with auto-renewal
- ✅ **Threat protection** - CrowdSec with global threat intelligence
- ✅ **Dynamic DNS** - Automatic IP updates every 30 minutes
- ✅ **Rootless containers** - Enhanced security with user-space isolation
- ✅ **High availability** - Automatic container restarts on failure
- ✅ **Monitoring ready** - Prometheus + Grafana + Loki stack

---

## 🌐 Network Architecture

### Physical Network

```
Internet (ISP)
    ↓
[62.249.184.112] Public IP (dynamic)
    ↓
UDM Pro (192.168.1.1)
    ├── Port Forwarding
    │   ├── 80 → fedora-htpc:80 (HTTP)
    │   └── 443 → fedora-htpc:443 (HTTPS)
    ├── DHCP Server
    ├── Firewall
    └── Local Network (192.168.1.0/24)
        ├── fedora-htpc (192.168.1.70) - Main server
        ├── pi-hole (192.168.1.69) - DNS server
        └── Other devices
```

### Logical Service Flow

```
Internet Request
    ↓
[1] DNS Resolution (Cloudflare)
    patriark.org → 62.249.184.112
    ↓
[2] Port Forwarding (UDM Pro)
    :80/:443 → 192.168.1.70
    ↓
[3] CrowdSec Check
    ✓ IP not banned → Continue
    ✗ IP banned → 403 Forbidden
    ↓
[4] Traefik (Reverse Proxy)
    ├── SSL Termination (Let's Encrypt)
    ├── Rate Limiting
    ├── Authelia SSO (YubiKey + TOTP)
    ├── Security Headers
    └── Route to service or SSO portal
    ↓
[5] Authelia (SSO + Multi-Factor Authentication)
    ✓ Valid session → Service access
    ✗ No session → SSO portal (sso.patriark.org)
        ├── Username + Password (Argon2id)
        ├── YubiKey touch (WebAuthn/FIDO2)
        └── Session created (Redis-backed, 1h expiration)
    ↓
[6] Service (Jellyfin, Grafana, etc.)
    Render response
    ↓
[7] Return to User
```

### Container Network

```
Host: fedora-htpc (192.168.1.70)
    │
    ├── Podman Network: systemd-reverse_proxy (10.89.2.0/24)
    │   ├── traefik (10.89.2.x) - Reverse proxy & SSL
    │   ├── crowdsec (10.89.2.x) - Threat protection
    │   ├── authelia (10.89.2.x) - SSO portal
    │   └── jellyfin (10.89.2.x) - Media service
    │
    └── Podman Network: systemd-auth_services (10.89.3.0/24)
        ├── authelia (10.89.3.x) - SSO server
        └── redis-authelia (10.89.3.x) - Session storage
```

**Network Type:** Podman bridge network
**DNS:** Internal DNS resolution between containers
**Isolation:** Containers can only talk to each other on this network

---

## 🔧 Service Stack

### Core Infrastructure

| Service | Purpose | Technology | Port(s) | Status |
|---------|---------|------------|---------|--------|
| **Traefik** | Reverse proxy & SSL | Traefik v3.2 | 80, 443, 8080 | Running ✅ |
| **CrowdSec** | Threat protection | CrowdSec latest | 8080 (internal) | Running ✅ |
| **Authelia** | SSO + YubiKey MFA | Authelia 4.38 | 9091 (internal) | Running ✅ |
| **Redis** | Session storage | Redis 7 Alpine | 6379 (internal) | Running ✅ |
| **~~TinyAuth~~** | ~~SSO Authentication~~ | ~~Tinyauth v4~~ | ~~3000 (internal)~~ | **Replaced by Authelia** ⚠️ |

### Application Services

| Service | Purpose | Technology | Port | Status |
|---------|---------|------------|------|--------|
| **Jellyfin** | Media server | Jellyfin latest | 8096 (internal) | Running ✅ |

### External Dependencies

| Service | Purpose | Provider | Configuration |
|---------|---------|----------|---------------|
| **Cloudflare DNS** | Public DNS | Cloudflare | Auto-update via API |
| **Pi-hole** | Local DNS | Self-hosted | 192.168.1.69 |
| **Let's Encrypt** | SSL Certificates | ACME | Auto-renew every 90 days |

---

## 📦 Deployment Ecosystem

**Since:** November 14, 2025 (Session 3)
**Method:** Pattern-based deployment automation
**Status:** Production ✅

### Pattern Library

The homelab uses **deployment patterns** to standardize service deployment. Patterns are reusable YAML templates that encode best practices, network configuration, resource limits, and security settings.

**Available Patterns (9 total):**

| Pattern | Service Type | Resource Tier | Examples | Use Case |
|---------|--------------|---------------|----------|----------|
| **media-server-stack** | Media streaming | High (4GB+) | Jellyfin, Plex, Emby | GPU transcoding, large storage |
| **web-app-with-database** | Web applications | Medium (2GB) | Wiki.js, Bookstack, Nextcloud | Standard 2-container stacks |
| **document-management** | Document systems | High (3GB+) | Paperless-ngx | OCR, indexing, multi-service |
| **authentication-stack** | SSO/Authentication | Low (512MB) | Authelia + Redis | Hardware 2FA, session management |
| **password-manager** | Password vaults | Low (512MB) | Vaultwarden | Self-contained, own auth |
| **database-service** | Databases | Medium (2GB) | PostgreSQL, MySQL | BTRFS NOCOW optimized |
| **cache-service** | Caching | Low (256-512MB) | Redis, Memcached | Sessions, temporary data |
| **reverse-proxy-backend** | Internal APIs | Low (512MB) | Admin panels, tools | Strict auth required |
| **monitoring-exporter** | Metrics exporters | Minimal (128MB) | node_exporter, cAdvisor | Prometheus scraping |

### Deployment Workflow

**Standard deployment process:**

1. **Health Check:** System health scoring (0-100) determines deployment readiness
2. **Pattern Selection:** Choose appropriate pattern based on service type
3. **Validation:** Prerequisite checks (image exists, networks exist, ports available)
4. **Deployment:** Generate systemd quadlet from pattern template
5. **Verification:** Drift detection confirms quadlet matches running container

**Command example:**
```bash
cd .claude/skills/homelab-deployment

# Deploy with pattern
./scripts/deploy-from-pattern.sh \
  --pattern media-server-stack \
  --service-name jellyfin \
  --hostname jellyfin.patriark.org \
  --memory 4G

# Verify deployment
./scripts/check-drift.sh jellyfin
```

### Intelligence Integration

**Health-aware deployment:**
- Health scores 90-100: Excellent - deploy anything
- Health scores 75-89: Good - proceed with monitoring
- Health scores 50-74: Degraded - address warnings first
- Health scores 0-49: Critical - block deployment

**Drift detection:**
- **MATCH:** Configuration correct (no action needed)
- **DRIFT:** Mismatch detected (restart service to reconcile)
- **WARNING:** Minor differences (informational only)

**Checked categories:** Image version, memory limits, networks, volumes, Traefik labels

### Pattern Benefits

**Consistency:** All services follow the same configuration standards

**Best Practices Built-In:**
- Network ordering (reverse_proxy first for internet access)
- SELinux labels (`:Z` on volume mounts)
- BTRFS NOCOW for databases
- Traefik middleware chains (CrowdSec → rate limit → auth → headers)
- Resource limits and systemd dependencies

**Validation:** Pre-deployment checks prevent common mistakes

**Documentation:** Patterns are self-documenting with deployment notes and checklists

**Documentation References:**
- **Pattern Selection Guide:** `docs/10-services/guides/pattern-selection-guide.md`
- **Deployment Cookbook:** `.claude/skills/homelab-deployment/COOKBOOK.md`
- **Skill Integration:** `docs/10-services/guides/skill-integration-guide.md`
- **ADR-007:** `docs/20-operations/decisions/2025-11-14-decision-007-pattern-based-deployment.md`

---

## 🛡️ Security Layers

### Defense in Depth Strategy

```
Layer 7: Multi-Factor Authentication (Authelia: YubiKey + TOTP)
    ↓
Layer 6: SSO Session Management (Redis: 1h expiration)
    ↓
Layer 5: Rate Limiting (Traefik Middleware: Tiered 100-200 req/min)
    ↓
Layer 4: Threat Intelligence (CrowdSec Bouncer: IP reputation)
    ↓
Layer 3: TLS Encryption (Let's Encrypt: TLS 1.2+ with modern ciphers)
    ↓
Layer 2: Security Headers (Traefik: HSTS, CSP, X-Frame-Options)
    ↓
Layer 1: Port Filtering (UDM Pro Firewall: Only 80/443 exposed)
```

### Security Features Implemented

#### 1. **CrowdSec Threat Protection**
- **Type:** Collaborative security
- **Coverage:** Global threat intelligence
- **Detection:** Behavioral analysis + community blocklists
- **Response:** Automatic IP banning
- **Scope:** All HTTP/HTTPS traffic through Traefik

**Active Scenarios:**
- Brute force detection
- Web scanner detection
- HTTP exploit attempts
- Rate abuse detection

#### 2. **Multi-Factor Authentication (Authelia)**
- **Primary:** YubiKey/WebAuthn (FIDO2 phishing-resistant)
- **Fallback:** TOTP (Microsoft Authenticator)
- **Base:** Username + password (Argon2id hashed)
- **Session:** Redis-backed (1h expiration, 15min inactivity)
- **SSO:** Single sign-on across all protected services
- **Scope:** Admin services (Grafana, Prometheus, Traefik), Jellyfin web UI

**Protected services:**
- ✅ Grafana (grafana.patriark.org)
- ✅ Prometheus (prometheus.patriark.org)
- ✅ Loki (loki.patriark.org)
- ✅ Traefik Dashboard (traefik.patriark.org)
- ✅ Jellyfin Web UI (jellyfin.patriark.org)

**Bypass patterns:**
- Health check endpoints (all services)
- Jellyfin API endpoints (mobile app compatibility)
- Immich (uses native authentication)

#### 3. **Rate Limiting (Tiered)**
- **Public services:** 200 requests/minute (media, asset-heavy)
- **Standard services:** 100 requests/minute (admin interfaces)
- **Auth endpoints:** 10 requests/minute (SSO portal was 10, increased to 100 for SPA assets)
- **Applied to:** All routes via Traefik middleware
- **Purpose:** Prevent abuse and DoS

#### 4. **SSL/TLS**
- **Provider:** Let's Encrypt
- **Certificates:** Wildcard + domain-specific
- **Renewal:** Automatic every 90 days
- **Protocols:** TLS 1.2+ only
- **Ciphers:** Modern secure ciphers only

#### 5. **Security Headers**
```yaml
X-Frame-Options: SAMEORIGIN
X-Content-Type-Options: nosniff
X-XSS-Protection: 1; mode=block
Strict-Transport-Security: max-age=31536000
```

#### 6. **Container Security**
- **Rootless:** All containers run as user (UID 1000)
- **SELinux:** Enforcing mode
- **Isolation:** Each service in separate container
- **Networks:** Isolated bridge networks

---

## 🌐 DNS Configuration

### Public DNS (Cloudflare)

**Zone:** patriark.org
**Nameservers:** Cloudflare (cam.ns.cloudflare.com, drew.ns.cloudflare.com)

**DNS Records:**

| Type | Name | Value | TTL | Proxy |
|------|------|-------|-----|-------|
| A | @ | 62.249.184.112 | Auto | DNS only |
| A | * | 62.249.184.112 | Auto | DNS only |

**Dynamic Updates:**
- **Script:** `~/containers/scripts/cloudflare-ddns.sh`
- **Frequency:** Every 30 minutes (systemd timer)
- **Method:** Cloudflare API in ~/containers/secrets

### Local DNS (Pi-hole)

**Server:** 192.168.1.69
**Purpose:** Local resolution for LAN clients

**Custom Records:**

| Domain | IP | Purpose |
|--------|----|---------| 
| patriark.org | 192.168.1.70 | Local routing |
| auth.patriark.org | 192.168.1.70 | Auth portal |
| jellyfin.patriark.org | 192.168.1.70 | Media server |
| traefik.patriark.org | 192.168.1.70 | Dashboard |

**Benefit:** LAN traffic stays local, doesn't hairpin through WAN

---

## 💾 Storage & Data

### Directory Structure

```
/home/patriark/containers/
├── config/                      # Service configurations
│   ├── traefik/
│   │   ├── traefik.yml         # Static config
│   │   ├── dynamic/            # Dynamic configs
│   │   │   ├── routers.yml     # Route definitions
│   │   │   ├── middleware.yml  # Middleware configs
│   │   │   └── tls.yml         # TLS settings
│   │   └── letsencrypt/        # SSL certificates
│   │       └── acme.json       # Let's Encrypt data
│   ├── jellyfin/               # Jellyfin config
│   └── crowdsec/               # CrowdSec config
│
├── data/                        # Service data
│   ├── crowdsec/
│   │   ├── db/                 # CrowdSec database
│   │   └── config/             # Runtime config
│   └── jellyfin/               # Media library metadata
│
├── scripts/                     # Automation scripts
│   ├── cloudflare-ddns.sh     # DNS updater
│   └── security-audit.sh       # Security checker
│
├── secrets/                     # Sensitive data (chmod 600)
│   ├── cloudflare_token        # API token
│   └── cloudflare_zone_id      # Zone ID
│
├── backups/                     # Configuration backups
│   └── phase1-TIMESTAMP/       # Timestamped backups
│
└── documentation/               # Documentation
    └── (this file)
```

### Systemd Service Files

```
/home/patriark/.config/containers/systemd/
├── traefik.container           # Traefik quadlet
├── authelia.container          # Authelia SSO quadlet
├── redis-authelia.container    # Redis for Authelia sessions
├── jellyfin.container          # Jellyfin quadlet
├── crowdsec.container          # CrowdSec quadlet
├── cloudflare-ddns.service     # DDNS service - This seems like an error entry as cloudflare-ddns is run as a script in ~/containers/scripts with automations to run at timely intervals
└── cloudflare-ddns.timer       # DDNS timer - See previous comment
```

### BTRFS Snapshots

**Filesystem:** BTRFS on /home
**Snapshots:** Manual before major changes

```bash
# List snapshots in / and limit shown results to include text home - should be revised
sudo btrfs subvolume list / | grep home

# Current snapshots - this list is NOT complete and should be updated
/home-before-authelia-20251111   # Before Authelia SSO migration
/home-working-tinyauth-20251023  # Historical - After Tinyauth setup (now deprecated)
/home-before-letsencrypt-*       # Before SSL setup
```

---

## 💾 Backup Strategy

### What Gets Backed Up

#### Critical (Daily)
- Service configurations (`~/containers/config/`)
- Systemd quadlets (`~/.config/containers/systemd/`)
- Scripts (`~/containers/scripts/`)
- Secrets (`~/containers/secrets/`)

#### Important (Weekly)
- CrowdSec database
- Jellyfin metadata
- Documentation

#### Optional (Monthly)
- Container images (can be re-pulled)
- Logs (if needed for forensics)

### Backup Methods

#### 1. **BTRFS Snapshots**
```bash
# Before major changes
sudo btrfs subvolume snapshot /home ~/snapshots/YYYYMMDD-htpc-home
```

**Pros:** Instant, space-efficient, easy rollback
**Cons:** Same filesystem (not off-site)

#### 2. **Configuration Tarball**
```bash
# Weekly backup
tar -czf ~/backups/config-$(date +%Y%m%d).tar.gz \
    ~/containers/config \
    ~/.config/containers/systemd \
    ~/containers/scripts
```

**Pros:** Portable, easy to restore  
**Cons:** Manual process

#### 3. **Git Repository** (Recommended for configs)
```bash
cd ~/containers
git init
git add config/ scripts/ .config/containers/systemd/
git commit -m "Backup $(date)"
git push # to private repo
```

**Pros:** Version history, off-site, easy to track changes  
**Cons:** Secrets need to be gitignored

---

## 🔧 Service Details

### Traefik (Reverse Proxy)

**Container:** `traefik`  
**Image:** `docker.io/library/traefik:v3.2`  
**Network:** systemd-reverse_proxy  
**Ports:** 80 (HTTP), 443 (HTTPS), 8080 (Dashboard)

**Key Features:**
- Automatic service discovery via Docker provider
- Let's Encrypt integration with HTTP challenge
- Dynamic configuration from files
- Built-in dashboard

**Configuration Files:**
- Static: `~/containers/config/traefik/traefik.yml`
- Dynamic: `~/containers/config/traefik/dynamic/*.yml`

**Access:**
- Dashboard: https://traefik.patriark.org (requires login)
- API: http://localhost:8080/api (local only)

**Plugins:**
- crowdsec-bouncer-traefik-plugin v1.4.5

---

### CrowdSec (Security)

**Container:** `crowdsec`
**Image:** `ghcr.io/crowdsecurity/crowdsec:latest`
**Network:** systemd-reverse_proxy
**Port:** 8080 (LAPI - internal only)

**Installed Collections:**
- crowdsecurity/traefik
- crowdsecurity/http-cve

**Bouncers:**
- traefik-bouncer (Traefik middleware)

**Key Features:**
- Real-time threat detection
- Global IP reputation
- Behavioral analysis
- Automatic banning

**Management:**
```bash
# View metrics
podman exec crowdsec cscli metrics

# List active bans
podman exec crowdsec cscli decisions list

# View alerts
podman exec crowdsec cscli alerts list

# List bouncers
podman exec crowdsec cscli bouncers list
```

---

### Authelia (SSO + Multi-Factor Authentication)

**Container:** `authelia`
**Image:** `docker.io/authelia/authelia:4.38`
**Networks:** systemd-reverse_proxy, systemd-auth_services
**Port:** 9091 (internal only)

**Configuration:**
- SSO Portal: https://sso.patriark.org
- Authentication methods:
  - Primary: YubiKey/WebAuthn (FIDO2)
  - Fallback: TOTP (Microsoft Authenticator)
  - Base: Username + password (Argon2id)
- Session storage: Redis (redis-authelia)
- Session expiration: 1 hour (15min inactivity)
- Database: SQLite (`/data/db.sqlite3`)

**Users:**
- patriark (groups: admins, users)

**Enrolled devices:**
- YubiKey 5 NFC
- YubiKey 5C Nano
- Microsoft Authenticator (TOTP)

**Integration:**
- Traefik ForwardAuth middleware (`authelia@file`)
- Protects: Admin services, Jellyfin web UI
- Bypasses: Health checks, Jellyfin API (mobile apps)

**Access:**
- SSO Portal: https://sso.patriark.org
- Settings: https://sso.patriark.org/settings

**Management:**
```bash
# Service status
systemctl --user status authelia.service

# View logs
podman logs -f authelia

# Health check
curl http://localhost:9091/api/health

# Generate password hash
podman exec -it authelia authelia crypto hash generate argon2 --random
```

---

### Redis (Session Storage)

**Container:** `redis-authelia`
**Image:** `docker.io/library/redis:7-alpine`
**Network:** systemd-auth_services
**Port:** 6379 (internal only)

**Configuration:**
- Persistence: AOF (append-only file)
- Max memory: 128MB
- Eviction policy: allkeys-lru

**Purpose:**
- Store Authelia SSO sessions
- Session data encrypted by Authelia

**Management:**
```bash
# Check health
podman exec redis-authelia redis-cli ping

# View stats
podman exec redis-authelia redis-cli INFO stats

# Session count
podman exec redis-authelia redis-cli DBSIZE
```

---

### ~~TinyAuth~~ (DEPRECATED - Replaced by Authelia)

**Status:** Decommissioned (replaced 2025-11-11)
**Superseded by:** Authelia SSO with YubiKey MFA
**Migration Date:** 2025-11-11
**Rationale:** Authelia provides superior security with hardware 2FA (YubiKey/WebAuthn), TOTP fallback, and better SSO capabilities

**See:**
- [Authelia Guide](../../10-services/guides/authelia.md) - Current SSO documentation
- [ADR-006](../../30-security/decisions/2025-11-11-ADR-006-authelia-sso-yubikey-deployment.md) - Migration decision rationale

---

### Jellyfin (Media Server)

**Container:** `jellyfin`
**Image:** `docker.io/jellyfin/jellyfin:latest`
**Network:** systemd-reverse_proxy
**Port:** 8096 (internal only)

**Features:**
- Media streaming (movies, TV, music)
- Hardware transcoding
- User management
- Mobile apps available

**Access:**
- Web: https://jellyfin.patriark.org (requires Authelia SSO login first)
- SSO Portal: https://sso.patriark.org (YubiKey + TOTP authentication)
- Internal login: Separate Jellyfin user account (after SSO)

**Storage:**
- Config: `~/containers/config/jellyfin/`
- Media: (configure media library paths)

---

## 🚀 Expansion Guide

### How to Add New Services

#### Standard Service Addition Process

**Step 1: Plan the Service**
- Choose service (e.g., Nextcloud, Vaultwarden)
- Check Docker image availability
- Identify required ports
- Review dependencies

**Step 2: Create Quadlet**
```bash
nano ~/.config/containers/systemd/SERVICE_NAME.container
```

**Template:**
```ini
[Unit]
Description=SERVICE_NAME
After=network-online.target traefik.service
Wants=network-online.target

[Container]
Image=docker.io/SERVICE_IMAGE:TAG
ContainerName=SERVICE_NAME
AutoUpdate=registry
Network=systemd-reverse_proxy

# Volumes
Volume=%h/containers/config/SERVICE_NAME:/config:Z
Volume=%h/containers/data/SERVICE_NAME:/data:Z

# Environment variables
Environment=KEY=VALUE

[Service]
Restart=always
TimeoutStartSec=900

[Install]
WantedBy=default.target
```

**Step 3: Add Traefik Route**
```bash
nano ~/containers/config/traefik/dynamic/routers.yml
```

**Add:**
```yaml
http:
  routers:
    SERVICE_NAME:
      rule: "Host(`SERVICE_NAME.patriark.org`)"
      service: "SERVICE_NAME"
      entryPoints:
        - websecure
      middlewares:
        - crowdsec-bouncer
        - rate-limit
        - authelia@file  # SSO authentication
      tls:
        certResolver: letsencrypt
  
  services:
    SERVICE_NAME:
      loadBalancer:
        servers:
          - url: "http://SERVICE_NAME:PORT"
```

**Step 4: Start Service**
```bash
systemctl --user daemon-reload
systemctl --user start SERVICE_NAME.service
systemctl --user enable SERVICE_NAME.service
```

**Step 5: Test**
```bash
# Check running
podman ps | grep SERVICE_NAME

# Check logs
podman logs SERVICE_NAME --tail 20

# Test access
curl -I https://SERVICE_NAME.patriark.org
```

---

### Service Categories

#### **Media Services**
- **Sonarr** - TV show management
- **Radarr** - Movie management
- **Prowlarr** - Indexer management
- **Bazarr** - Subtitle management
- **Overseerr** - Media requests

#### **Productivity**
- **Nextcloud** - File sync & collaboration
- **Vaultwarden** - Password manager
- **Paperless-ngx** - Document management
- **Bookstack** - Documentation wiki

#### **Monitoring**
- **Uptime Kuma** - Service monitoring
- **Grafana** - Metrics visualization
- **Prometheus** - Metrics collection
- **Loki** - Log aggregation

#### **Smart Home**
- **Home Assistant** - Smart home hub
- **Node-RED** - Automation flows
- **Zigbee2MQTT** - Zigbee device bridge

#### **Development**
- **Gitea** - Git hosting
- **Drone CI** - CI/CD pipeline
- **Code Server** - VS Code in browser

---

### Network Expansion Options

#### **Option 1: Add More Services (Current Setup)**
```
systemd-reverse_proxy network
├── traefik
├── crowdsec
├── authelia
├── jellyfin
├── nextcloud      ← Add here
├── vaultwarden    ← Add here
└── uptime-kuma    ← Add here
```

**Pros:** Simple, everything on one network
**Cons:** All services can talk to each other

---

#### **Option 2: Multiple Networks (Better Isolation)**
```
systemd-reverse_proxy (frontend)
├── traefik
├── crowdsec
└── authelia

systemd-services (backend)
├── jellyfin
├── nextcloud
└── vaultwarden

systemd-databases (data)
├── postgres
├── redis
└── mariadb
```

**Pros:** Better security isolation  
**Cons:** More complex configuration

---

#### **Option 3: Service-Specific Networks**
```
Each service gets its own network + reverse_proxy

traefik → reverse_proxy + jellyfin_net + nextcloud_net
jellyfin → jellyfin_net only
nextcloud → nextcloud_net only
```

**Pros:** Maximum isolation
**Cons:** Most complex

---

### Recommended Expansion Path

**Phase 1: Core Services** (Current)
- ✅ Traefik
- ✅ CrowdSec
- ✅ Authelia (SSO + YubiKey MFA)
- ✅ Jellyfin

**Phase 2: Add Utilities**
- Nextcloud (file storage)
- Vaultwarden (passwords)
- Homepage (dashboard)

**Phase 3: Add Monitoring**
- Uptime Kuma (service monitoring)
- Grafana + Prometheus (metrics)
- Loki (Logs aggregation)

**Phase 4: Advanced**
- WireGuard VPN
- Home Assistant
- Media *arr stack

---

## 🔧 Maintenance

### Daily

**Automatic:**
- DDNS updates (every 30 minutes)
- CrowdSec threat updates
- Container health checks
- SSL certificate renewal checks

**Manual:**
None required! Everything is automated.

---

### Weekly

```bash
# Check service health
podman ps -a

# Review CrowdSec alerts
podman exec crowdsec cscli alerts list

# Check for container updates
podman auto-update --dry-run

# Review logs for errors
journalctl --user -u traefik.service --since "1 week ago" | grep -i error
```

---

### Monthly

```bash
# Update containers
podman auto-update

# Restart services after updates
systemctl --user restart traefik.service
systemctl --user restart crowdsec.service
systemctl --user restart authelia.service redis-authelia.service
systemctl --user restart jellyfin.service

# Create config backup
tar -czf ~/backups/config-$(date +%Y%m%d).tar.gz \
    ~/containers/config \
    ~/.config/containers/systemd

# Create BTRFS snapshot
sudo btrfs subvolume snapshot /home /home-monthly-$(date +%Y%m%d)

# Clean old snapshots (keep 3 months)
sudo btrfs subvolume list / | grep home-monthly | head -n -3 | \
    awk '{print $NF}' | xargs -I {} sudo btrfs subvolume delete {}

# Review CrowdSec statistics
podman exec crowdsec cscli metrics
```

---

### Quarterly

```bash
# Full security audit
~/containers/scripts/security-audit.sh

# Review and update documentation
nano ~/containers/documentation/HOMELAB-ARCHITECTURE-DOCUMENTATION.md

# Test disaster recovery
# (restore from backup to test machine)

# Review SSL certificate health
ls -la ~/containers/config/traefik/letsencrypt/

# Update passwords/secrets
# (rotate API keys, update passwords)
```

---

## 🔍 Troubleshooting

### Common Issues

#### Service Won't Start

```bash
# Check service status
systemctl --user status SERVICE.service

# Check logs
journalctl --user -u SERVICE.service -n 50

# Check container logs
podman logs SERVICE --tail 50

# Common fixes:
systemctl --user daemon-reload
systemctl --user restart SERVICE.service
```

---

#### Can't Access Service from Internet

```bash
# Check DNS
dig SERVICE.patriark.org +short
# Should show your public IP

# Check port forwarding
# UDM Pro → Settings → Port Forwarding
# Verify 80 and 443 → 192.168.1.70

# Check Traefik routing
podman logs traefik | grep SERVICE

# Check if service is running
podman ps | grep SERVICE
```

---

#### SSL Certificate Issues

```bash
# Check certificate file
ls -la ~/containers/config/traefik/letsencrypt/acme.json

# Force renewal
# Delete cert from acme.json, restart Traefik

# Check Let's Encrypt logs
podman logs traefik | grep -i acme
podman logs traefik | grep -i certificate
```

---

#### CrowdSec Not Blocking

```bash
# Check CrowdSec is running
podman ps | grep crowdsec

# Check bouncer is connected
podman exec crowdsec cscli bouncers list

# Check decisions
podman exec crowdsec cscli decisions list

# Test blocking manually
MY_IP=$(curl -s ifconfig.me)
podman exec crowdsec cscli decisions add --ip $MY_IP --duration 5m
curl -I https://jellyfin.patriark.org
# Should return 403
```

---

#### Authentication Loop

```bash
# Check Authelia is running
podman ps | grep authelia

# Check Authelia logs
podman logs authelia --tail 50

# Check Redis (session storage)
podman logs redis-authelia --tail 50

# Check Authelia health endpoint
curl http://localhost:9091/api/health

# Clear browser cookies and try again
```

---

### Emergency Procedures

#### Complete System Restore

```bash
# 1. Stop all services
systemctl --user stop traefik.service
systemctl --user stop crowdsec.service
systemctl --user stop authelia.service redis-authelia.service
systemctl --user stop jellyfin.service

# 2. Restore from BTRFS snapshot
sudo btrfs subvolume snapshot /home-backup-DATE /home

# 3. Reboot
sudo reboot

# 4. Verify services start
podman ps
```

---

#### Remove All Containers (Nuclear Option)

```bash
# Stop all user services
systemctl --user stop traefik.service crowdsec.service authelia.service redis-authelia.service jellyfin.service

# Remove all containers
podman rm -af

# Remove all images
podman rmi -af

# Reload and restart
systemctl --user daemon-reload
systemctl --user start traefik.service
systemctl --user start crowdsec.service
systemctl --user start authelia.service redis-authelia.service
systemctl --user start jellyfin.service

# Containers will be re-pulled
```

---

### Health Check Script

```bash
#!/bin/bash
# ~/containers/scripts/health-check.sh

echo "=== Homelab Health Check ==="
echo ""

echo "Services:"
systemctl --user is-active traefik.service crowdsec.service authelia.service redis-authelia.service jellyfin.service

echo ""
echo "Containers:"
podman ps --format "table {{.Names}}\t{{.Status}}"

echo ""
echo "Public IP:"
curl -s ifconfig.me

echo ""
echo "DNS:"
dig +short patriark.org

echo ""
echo "SSL Expiry:"
echo | openssl s_client -servername jellyfin.patriark.org -connect jellyfin.patriark.org:443 2>/dev/null | \
    openssl x509 -noout -dates | grep notAfter

echo ""
echo "CrowdSec Status:"
podman exec crowdsec cscli bouncers list 2>/dev/null || echo "CrowdSec not responding"

echo ""
echo "=== Health Check Complete ==="
```

---

## 📊 Monitoring & Observability

### Current Monitoring Capabilities

**Service Health:**
- Systemd status (`systemctl --user status`)
- Container health checks (Podman)
- Process monitoring (automatic restarts)

**Logs:**
- Systemd journal (`journalctl`)
- Container logs (`podman logs`)
- Traefik access logs (to be configured)

**Security:**
- CrowdSec alerts and decisions
- Traefik error logs
- Failed authentication attempts (Authelia logs)

**Metrics:**
- CrowdSec metrics (`cscli metrics`)
- Traefik internal metrics (API)
- System resources (htop, podman stats)

---

### Future Monitoring Stack (Recommended)

```
Grafana (Visualization)
    ↓
Prometheus (Metrics)
    ↓
├── Node Exporter (System metrics)
├── cAdvisor (Container metrics)
└── Traefik metrics (HTTP metrics)
    ↓
Loki (Log aggregation)
    ↓
├── Traefik logs
├── CrowdSec logs
└── Application logs
```

---

## 🎓 Learning Resources

### Understanding the Stack

**Traefik:**
- Official docs: https://doc.traefik.io/traefik/
- Getting started: https://doc.traefik.io/traefik/getting-started/quick-start/

**Podman:**
- Official docs: https://docs.podman.io/
- Quadlets guide: https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html

**CrowdSec:**
- Official docs: https://docs.crowdsec.net/
- Traefik bouncer: https://github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin

**Let's Encrypt:**
- How it works: https://letsencrypt.org/how-it-works/
- ACME protocol: https://letsencrypt.org/docs/client-options/

---

## 📝 Change Log

### 2025-11-11 - Authelia SSO Migration
- Migrated from TinyAuth to Authelia
- Implemented YubiKey/WebAuthn hardware 2FA
- Added TOTP fallback (Microsoft Authenticator)
- Deployed Redis for session storage

### 2025-10-23 - Initial Production Setup
- Initial SSO deployment (TinyAuth - later replaced)
- Configured Cloudflare DDNS
- Implemented Let's Encrypt SSL
- Added CrowdSec security
- Documented complete architecture

### Future Changes
- [Date] - [Change description]

---

## 🎯 Success Metrics

**Security:**
- ✅ Zero unauthorized access attempts succeeded
- ✅ All traffic encrypted (SSL/TLS)
- ✅ Rate limiting active on all endpoints
- ✅ CrowdSec blocking malicious IPs
- ✅ Multi-factor authentication ready (can add)

**Reliability:**
- ✅ 99%+ uptime (container auto-restart)
- ✅ Automatic SSL renewal
- ✅ Automatic DNS updates
- ✅ Self-healing infrastructure

**Maintainability:**
- ✅ Declarative configuration (Infrastructure as Code)
- ✅ Version controlled (can be)
- ✅ Well documented
- ✅ Easy to restore from backup
- ✅ Systemd integration (starts on boot)

---

## 🏆 Best Practices Implemented

1. ✅ **Least Privilege** - Rootless containers, minimal permissions
2. ✅ **Defense in Depth** - Multiple security layers
3. ✅ **Automation** - DDNS, SSL renewal, restarts
4. ✅ **Declarative Config** - Quadlets, YAML files
5. ✅ **Immutable Infrastructure** - Containers, not processes
6. ✅ **Observability** - Structured logs, metrics available
7. ✅ **Documentation** - Architecture documented
8. ✅ **Backups** - BTRFS snapshots, config backups
9. ✅ **Secrets Management** - Separated, protected files
10. ✅ **Network Segmentation** - Isolated container networks

---

## 📞 Quick Reference

### Important URLs

| Service | URL | Authentication |
|---------|-----|----------------|
| Jellyfin | https://jellyfin.patriark.org | Authelia SSO → Jellyfin |
| Traefik Dashboard | https://traefik.patriark.org | Authelia SSO |
| Authelia SSO Portal | https://sso.patriark.org | YubiKey + TOTP |

### Important Commands

```bash
# Restart all services
systemctl --user restart traefik.service crowdsec.service authelia.service redis-authelia.service jellyfin.service

# View all logs
journalctl --user -u traefik.service -f

# Update containers
podman auto-update

# Create backup
tar -czf ~/backup-$(date +%Y%m%d).tar.gz ~/containers/config ~/.config/containers/systemd

# Check CrowdSec status
podman exec crowdsec cscli metrics

# Manual DDNS update
~/containers/scripts/cloudflare-ddns.sh

# Health check
~/containers/scripts/health-check.sh
```

### Important Files

```bash
# Traefik
~/containers/config/traefik/traefik.yml
~/containers/config/traefik/dynamic/routers.yml
~/containers/config/traefik/dynamic/middleware.yml

# Systemd
~/.config/containers/systemd/*.container

# Secrets
~/containers/secrets/cloudflare_token
~/containers/secrets/cloudflare_zone_id

# Scripts
~/containers/scripts/cloudflare-ddns.sh
~/containers/scripts/security-audit.sh
```

---

## 🎊 Conclusion

This homelab represents a **production-grade, secure, self-hosted infrastructure** using modern DevOps practices and enterprise-grade tools. The architecture is:

- **Secure** - Multiple layers of protection
- **Reliable** - Self-healing, automatic recovery
- **Maintainable** - Well-documented, easy to understand
- **Scalable** - Easy to add new services
- **Professional** - Industry-standard tools and practices

**You've built something impressive!** 🌟

---

**Document Version:** 1.0
**Last Review:** October 23, 2025
**Next Review:** January 23, 2026
