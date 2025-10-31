# Homelab Architecture Documentation

**Last Updated:** October 25, 2025 (Rev 2)
**Status:** Production Ready ✅
**Owner:** patriark
**Domain:** patriark.org
**Authoritative Source:** This document integrates storage architecture from 20251025-storage-architecture-authoritative-rev2.md

---

## 📋 Table of Contents

1. [Overview](#overview)
2. [Network Architecture](#network-architecture)
3. [Service Stack](#service-stack)
4. [Security Layers](#security-layers)
5. [DNS Configuration](#dns-configuration)
6. [Storage & Data](#storage--data)
7. [Backup Strategy](#backup-strategy)
8. [Service Details](#service-details)
9. [Expansion Guide](#expansion-guide)
10. [Maintenance](#maintenance)
11. [Troubleshooting](#troubleshooting)

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
Authentication:    Tinyauth v4
Security:          CrowdSec
DNS:               Cloudflare (external) + Pi-hole (internal)
SSL:               Let's Encrypt (automated)
Network:           UniFi Dream Machine Pro
Storage:           BTRFS (system SSD + multi-device HDD pool)
Backup:            LUKS-encrypted external drives
```

### Key Features

- ✅ **Zero-trust security** - Authentication required for all services
- ✅ **Automatic SSL** - Let's Encrypt certificates with auto-renewal
- ✅ **Threat protection** - CrowdSec with global threat intelligence
- ✅ **Dynamic DNS** - Automatic IP updates every 30 minutes
- ✅ **Rootless containers** - Enhanced security with user-space isolation
- ✅ **High availability** - Automatic container restarts on failure
- ✅ **BTRFS snapshots** - Hourly, daily, weekly, monthly snapshots
- ✅ **Monitoring ready** - Structured logs and metrics available

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
    ├── Security Headers
    └── Route to service
    ↓
[5] Tinyauth (Authentication)
    ✓ Valid session → Service access
    ✗ No session → Login redirect
    ↓
[6] Service (Jellyfin, etc.)
    Render response
    ↓
[7] Return to User
```

### Container Network Topology

```
Host: fedora-htpc (192.168.1.70)
│
├─── systemd-reverse_proxy Network (10.89.2.0/24)
│    │
│    ├─── traefik (10.89.2.x)
│    │    ├─ Port 80 → Host:80
│    │    ├─ Port 443 → Host:443
│    │    └─ Port 8080 → Host:8080
│    │
│    ├─── crowdsec (10.89.2.x)
│    │    └─ Port 8080 (internal only)
│    │
│    ├─── tinyauth (10.89.2.x)
│    │    └─ Port 3000 (internal only)
│    │
│    └─── jellyfin (10.89.2.x)
│         └─ Port 8096 (internal only)
│
├─── systemd-auth_services Network (idle)
│    └─── (No services currently assigned)
│
├─── systemd-media_services Network
│    └─── (Future: dedicated media network)
│
└─── Host Network
     ├─ DNS: 192.168.1.69 (Pi-hole)
     ├─ Gateway: 192.168.1.1 (UDM Pro)
     └─ Public IP: 62.249.184.112 (Dynamic)
```

**Network Type:** Podman bridge networks
**DNS:** Internal DNS resolution between containers
**Isolation:** Containers can only communicate within assigned networks

---

## 🔧 Service Stack

### Core Infrastructure

| Service | Purpose | Technology | Port(s) | Network | Status |
|---------|---------|------------|---------|---------|--------|
| **Traefik** | Reverse proxy & SSL | Traefik v3.2 | 80, 443, 8080 | reverse_proxy | Running ✅ |
| **CrowdSec** | Threat protection | CrowdSec latest | 8080 (internal) | reverse_proxy | Running ✅ |
| **Tinyauth** | SSO Authentication | Tinyauth v4 | 3000 (internal) | reverse_proxy | Running ✅ |

### Application Services

| Service | Purpose | Technology | Port | Network | Status |
|---------|---------|------------|------|---------|--------|
| **Jellyfin** | Media server | Jellyfin latest | 8096 (internal) | reverse_proxy | Running ✅ |

### Planned Services

| Service | Purpose | Technology | Priority | Notes |
|---------|---------|------------|----------|-------|
| **Nextcloud** | File sync & share | Nextcloud latest | High | Storage ready |
| **Grafana** | Monitoring dashboard | Grafana latest | High | For observability stack |
| **Prometheus** | Metrics collection | Prometheus latest | High | For observability stack |
| **Loki** | Log aggregation | Loki latest | High | For observability stack |
| **Heimdall** | Service dashboard | Homepage latest | Medium | Central access point |

### External Dependencies

| Service | Purpose | Provider | Configuration |
|---------|---------|----------|---------------|
| **Cloudflare DNS** | Public DNS | Cloudflare | Auto-update via API (every 30 min) |
| **Pi-hole** | Local DNS | Self-hosted | 192.168.1.69 |
| **Let's Encrypt** | SSL Certificates | ACME | Auto-renew every 90 days |

---

## 🛡️ Security Layers

### Defense in Depth Strategy

```
Layer 7: Application Authentication (Tinyauth + Future 2FA)
    ↓
Layer 6: Rate Limiting (Traefik Middleware)
    ↓
Layer 5: Threat Intelligence (CrowdSec Bouncer)
    ↓
Layer 4: TLS Encryption (Let's Encrypt)
    ↓
Layer 3: Security Headers (Traefik Middleware)
    ↓
Layer 2: Port Filtering (UDM Pro Firewall)
    ↓
Layer 1: Network Isolation (Container Bridge Networks)
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

#### 2. **Authentication (Tinyauth)**
- **Method:** Forward authentication
- **Session:** Cookie-based
- **Password:** Bcrypt hashed
- **Scope:** All services except auth portal
- **Future:** 2FA with TOTP/WebAuthn planned

#### 3. **Rate Limiting**
- **Global:** 100 requests/minute (burst: 50)
- **Applied to:** All routes
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
# Additional strict headers in security-headers-strict.yml
```

#### 6. **Container Security**
- **Rootless:** All containers run as user (UID 1000)
- **SELinux:** Enforcing mode
- **Isolation:** Each service in separate container
- **Networks:** Isolated bridge networks per function # not yet implemented fully
- **No privileged containers:** Principle of least privilege

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
- **Frequency:** Every 30 minutes (cron or systemd timer)
- **Method:** Cloudflare API
- **Credentials:** `~/containers/secrets/cloudflare_token` and `cloudflare_zone_id`

### Local DNS (Pi-hole)

**Server:** 192.168.1.69
**Purpose:** Local resolution for LAN clients

**Custom Records:**

| Domain | IP | Purpose |
|--------|----|---------| 
| patriark.org | 192.168.1.70 | Local routing |
| *.patriark.org | 192.168.1.70 | Wildcard for all services |

**Services Accessible Locally:**
- auth.patriark.org
- jellyfin.patriark.org
- traefik.patriark.org
- (future services)

**Benefit:** LAN traffic stays local, doesn't hairpin through WAN

---

## 💾 Storage & Data

### High-Level Architecture

```
[Clients]
   │ HTTPS
   ▼
[Traefik] — [Tinyauth] — [CrowdSec]
   │
   │ (Podman networks per app + reverse_proxy)
   ▼
[App containers]
   │
   ▼
[Persistent volumes]
   │   ↳  Config (SSD)
   │   ↳  Hot data (SSD, NOCOW for DB/Redis only)
   │   ↳  Cold data (BTRFS HDD pool)  ← media, docs, photos, Nextcloud user data
   ▼
[BTRFS: system SSD mounted / + multi-device HDD pool mounted /mnt; external backup drives use LUKS and mounts to /run/media/patriark/WD-18TB]
```

### System SSD (BTRFS)

**Device:** NVMe SSD
**Mount:** `/`
**Encryption:** Unencrypted (system disk)
**Mount Options:** `compress=zstd:1,ssd,discard=async,noatime`

**Subvolumes:**
- `root` → `/`
- `home` → `/home`

**Key Directories:**
- `~/containers/config/<service>` — Service configurations
- `~/containers/data/<service>` — Service persistent data
- `~/containers/db/<service>` — Databases (with NOCOW: `chattr +C`)
- `~/containers/docs/` — Documentation
- `~/containers/scripts/` — Automation scripts
- `~/containers/secrets/` — Sensitive credentials (chmod 600)
- `~/containers/quadlets` → symlink to `~/.config/containers/systemd`

**Snapshot Layout and Strategy:**
- `~/.snapshots/home/YYYYmmddHH-hourly` (keep 24)
- `~/.snapshots/home/YYYYmmdd-daily` (keep 14)
- `~/.snapshots/home/YYYYmmdd-weekly` (keep 8)
- `~/.snapshots/home/YYYYmmdd-monthly` (keep 6)
- `~/.snapshots/root/YYYYmmdd-monthly` (keep 6)

### Data Pool (BTRFS Multi-Device)

**Mountpoint:** `/mnt` (pool mounted here)
**Subvolume Base:** `/mnt/btrfs-pool/`
**Current Profile:** Data: single, Metadata: single
**Future Profile:** Data: RAID1, Metadata: RAID1
**Encryption:** Unencrypted (main pool), LUKS for backup drives

**7 Primary Subvolumes:**

```
/mnt/btrfs-pool/
  ├─ subvol1-docs           (Documents for Nextcloud, personal/work)
  ├─ subvol2-pics           (Pictures, art, wallpapers for Nextcloud)
  ├─ subvol3-photos         (Personal photos for Nextcloud & Immich)
  ├─ subvol4-multimedia     (Media/video library for Jellyfin)
  ├─ subvol5-music          (Music collection)
  ├─ subvol6-tmp            (Secondary storage for temporary files that do not need SSD speeds and might take)
  └─ subvol7-containers     (Secondary storage for container data and databases that need more storage space)
```

**Purpose-Specific Storage:**
- **Config data:** System SSD for speed
- **Database data:** System SSD with NOCOW (`chattr +C`)
- **Media files:** HDD pool (large, sequential access)
- **User documents:** HDD pool (Nextcloud sync)

**Snapshot Layout and Strategy:**
```
/mnt/btrfs-pool/.snapshots/
  ├─ subvol1-docs/
  │   ├─ 2025102512-hourly
  │   ├─ 20251025-daily
  │   └─ ...
  ├─ subvol2-pics/
  └─ ... (one directory per subvolume)
```

### External Backup Drives

**Encryption:** LUKS (all backup drives)
**Format:** BTRFS on LUKS container
**Purpose:** Off-site/offline backup via `btrfs send`

**Example:**
```
WD-18TB → /dev/mapper/WD-18TB → /run/media/patriark/WD-18TB
```

### Complete Directory Structure

```
/home/patriark/containers/
│
├── config/                          # Service configurations
│   ├── traefik/
│   │   ├── traefik.yml             # Static configuration
│   │   ├── dynamic/                # Dynamic configurations
│   │   │   ├── routers.yml         # Route definitions
│   │   │   ├── middleware.yml      # Security & auth
│   │   │   ├── tls.yml             # TLS options
│   │   │   ├── security-headers-strict.yml
│   │   │   └── rate-limit.yml      # Rate limiting rules
│   │   ├── letsencrypt/            # SSL certificates
│   │   │   └── acme.json           # Let's Encrypt data
│   │   └── certs/                  # (deprecated, can remove)
│   │
│   ├── crowdsec/                   # CrowdSec config (auto-generated)
│   ├── jellyfin/                   # Jellyfin configuration
│   └── tinyauth/                   # (config via env vars)
│
├── data/                           # Persistent service data
│   ├── crowdsec/
│   │   ├── db/                     # Decision database
│   │   └── config/                 # Runtime config
│   ├── jellyfin/                   # Media library metadata
│   └── nextcloud/                  # (to be created)
│
├── scripts/                        # Automation scripts
│   ├── cloudflare-ddns.sh          # DNS updater (cron/systemd every 30 min)
│   ├── collect-storage-info.sh     # Storage info (has bugs, needs revision)
│   ├── deploy-jellyfin-with-traefik.sh # (legacy, archive candidate)
│   ├── fix-podman-secrets.sh       # (legacy, scrutiny needed)
│   ├── homelab-diagnose.sh         # (legacy, needs revision)
│   ├── jellyfin-manage.sh          # (legacy, needs documentation)
│   ├── jellyfin-status.sh          # (legacy, needs documentation)
│   ├── organize-docs.sh            # (needs revision for new structure)
│   ├── security-audit.sh           # (legacy, may have valid checks)
│   ├── show-pod-status.sh          # (legacy)
│   └── survey.sh                   # (recent but has bugs)
│
├── secrets/                        # Sensitive data (chmod 600)
│   ├── cloudflare_token           # API token
│   ├── cloudflare_zone_id         # Zone ID
│   ├── crowdsec_api_key           # LAPI for Crowdsec
│   ├── redis_password             # (legacy from Authelia, can remove)
│   └── smtp_password              # (legacy from Authelia, can remove)
│
├── backups/                        # Configuration backups
│   └── (short term copies in addition to snapshots - a config archive)    # (May be superfluous with BTRFS snaps)
│
├── docs/                           # Documentation
│   ├── 00-foundation/
│   │   ├── day01-learnings.md
│   │   ├── day02-networking.md
│   │   ├── day03-pod-commands.md
│   │   ├── day03-pods.md
│   │   ├── day03-pods-vs-containers.md
│   │   └── podman-cheatsheet.md
│   ├── 10-services/
│   │   ├── day04-jellyfin-final.md
│   │   ├── day06-complete.md
│   │   ├── day06-quadlet-success.md
│   │   ├── day06-traefik-routing.md
│   │   ├── day07-yubikey-inventory.md
│   │   └── quadlets-vs-generated.md
│   ├── 20-operations/
│   │   ├── 20251023-storage_data_architecture_revised.md
│   │   ├── DAILY-PROGRESS-2025-10-23.md
│   │   ├── HOMELAB-ARCHITECTURE-DIAGRAMS.md
│   │   ├── HOMELAB-ARCHITECTURE-DOCUMENTATION.md
│   │   ├── NEXTCLOUD-INSTALLATION-GUIDE.md
│   │   ├── QUICK-REFERENCE.md
│   │   ├── readme-week02.md
│   │   ├── storage-layout.md
│   │   └── TODAYS-ACHIEVEMENTS.md
│   ├── 30-security/
│   │   └── TINYAUTH-GUIDE.md
│   ├── 90-archive/
│   │   └── (older versions and deprecated docs)
│   └── 99-reports/
│       ├── 20251024-configurations-quadlets-and-more.md
│       ├── 20251025-storage-architecture-authoritative.md
│       ├── 20251025-storage-architecture-authoritative-rev2.md
│       └── (diagnostic outputs and summaries)
│
|── /home/patriark/containers/quadlets → /home/patriark/.config/containers/systemd  # Symlink to systemd units
|   ├── auth_services.network
|   ├── crowdsec.container
|   ├── jellyfin.container
|   ├── media_services.network
|   ├── reverse_proxy.network
|   ├── tinyauth.container
|   └── traefik.container 

/home/patriark/.config/containers/systemd/
├── auth_services.network           # Podman bridge network (idle, no services)
├── crowdsec.container              # CrowdSec service definition
├── jellyfin.container              # Jellyfin service definition
├── media_services.network          # Media Services network (future use)
├── reverse_proxy.network           # Reverse Proxy network (all services)
├── tinyauth.container              # Tinyauth service definition
└── traefik.container               # Traefik service definition
```

### Storage Quick Reference Commands

```bash
# View block devices
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,LABEL,UUID,FSTYPE

# BTRFS filesystem overview
sudo btrfs filesystem show
sudo btrfs fi usage -T /mnt

# Subvolume listing
sudo btrfs subvolume list -p /mnt
sudo btrfs subvolume list -p /

# Snapshot management
sudo btrfs subvolume snapshot -r <source> <destination>
sudo btrfs subvolume delete <snapshot-path>

# Health checks
sudo btrfs scrub start -Bd /mnt
sudo btrfs scrub status /mnt
sudo smartctl -H /dev/sdX

# Container storage
podman volume ls
podman volume inspect <volume-name>
```

---

## 🔄 Backup Strategy

### BTRFS Snapshot Strategy

**System SSD Snapshots:**
- **Frequency:** Automated via systemd timers
- **Retention:** 24 hourly, 14 daily, 8 weekly, 6 monthly
- **Location:** `~/.snapshots/`

**Data Pool Snapshots:**
- **Frequency:** Per subvolume automation
- **Retention:** Same as system
- **Location:** `/mnt/btrfs-pool/.snapshots/`

### External Backup Workflow

**Weekly Incremental:**
```bash
# Example for subvol1-docs
sudo btrfs send -p \
  /mnt/btrfs-pool/.snapshots/subvol1-docs/20251018-daily \
  /mnt/btrfs-pool/.snapshots/subvol1-docs/20251025-daily \
  | sudo btrfs receive /run/media/patriark/WD-18TB/.snapshots/subvol1-docs
```

**Quarterly Full Backup:**
```bash
for sv in /mnt/btrfs-pool/subvol[1-7]*; do
  sudo btrfs subvolume snapshot -r "$sv" \
    /mnt/btrfs-pool/.snapshots/$(basename "$sv")/$(date +%Y%m%d)-monthly
done
```

**Configuration Backup:**
```bash
# Manual config backup
tar -czf ~/backup-$(date +%Y%m%d).tar.gz \
  ~/containers/config \
  ~/.config/containers/systemd \
  ~/containers/secrets

# Store on backup drive
cp ~/backup-$(date +%Y%m%d).tar.gz /mnt/btrfs-pool/subvol7-backups/
```

---

## 🔧 Service Details

### Traefik Configuration

**Static Config:** `~/containers/config/traefik/traefik.yml`
**Dynamic Config:** `~/containers/config/traefik/dynamic/`

**Key Features:**
- Automatic Let's Encrypt certificate management
- HTTP to HTTPS redirect
- CrowdSec bouncer integration
- Forward auth to Tinyauth
- Rate limiting middleware
- Security headers middleware

**Dashboard Access:** https://traefik.patriark.org (requires Tinyauth)

### Tinyauth Configuration

**Environment Variables:**
- `APP_URL` - Base URL for the application
- `SECRET_KEY` - Session encryption key
- `USERS` - User credentials (bcrypt hashed)

**Features:**
- Simple forward authentication
- Cookie-based sessions
- Bcrypt password hashing
- Minimal resource footprint

**Future Enhancements:**
- TOTP 2FA support
- WebAuthn/FIDO2 support # is this really supported on tinyauth?
- User management interface

### CrowdSec Configuration

**Components:**
- CrowdSec engine (threat detection)
- Traefik bouncer plugin (enforcement)

**Management:**
```bash
# View metrics
podman exec crowdsec cscli metrics

# List decisions (banned IPs)
podman exec crowdsec cscli decisions list

# List bouncers
podman exec crowdsec cscli bouncers list

# Manual ban (testing)
podman exec crowdsec cscli decisions add --ip X.X.X.X --duration 5m
```

### Jellyfin Configuration

**Media Library Paths:** # This is incorrect and needs to be revised.
- Movies: `/mnt/btrfs-pool/subvol5-multimedia/Filmer`
- TV Shows: `/mnt/btrfs-pool/subvol5-multimedia/Serier`
- Music: `/mnt/btrfs-pool/subvol4-music`

**Hardware Acceleration:** Configured for Intel Quick Sync (if available) # why? the user has AMD Ryzen system
**Metadata:** Stored in `~/containers/data/jellyfin`
**Authentication:** Protected by Tinyauth forward auth

---

## 🚀 Expansion Guide

### Adding a New Service

**Step-by-step Process:**

1. **Research & Plan**
   ```bash
   # Identify requirements
   - Docker image name and version
   - Required ports
   - Volume mounts needed
   - Environment variables
   - Network placement
   ```

2. **Create Directory Structure**
   ```bash
   mkdir -p ~/containers/config/<service>
   mkdir -p ~/containers/data/<service>
   ```

3. **Create Quadlet File**
   ```bash
   # Create in ~/.config/containers/systemd/<service>.container
   [Container]
   Image=docker.io/<image>:<tag>
   Volume=%h/containers/config/<service>:/config
   Volume=%h/containers/data/<service>:/data
   Network=systemd-reverse_proxy.network
   Environment=KEY=value
   
   [Service]
   Restart=always
   
   [Install]
   WantedBy=default.target
   ```

4. **Configure Traefik Routing**
   ```bash
   # Edit ~/containers/config/traefik/dynamic/routers.yml
   # Add router and service definitions
   ```

5. **Reload and Start**
   ```bash
   systemctl --user daemon-reload
   systemctl --user start <service>.service
   ```

6. **Verify and Test**
   ```bash
   podman ps | grep <service>
   journalctl --user -u <service>.service -f
   curl -I https://<service>.patriark.org
   ```

7. **Document**
   - Update this documentation
   - Add to service inventory
   - Document any special configurations

### Next Planned Services

#### 1. Monitoring Stack (Priority: High)
- **Grafana** - Visualization dashboard
- **Prometheus** - Metrics collection
- **Loki** - Log aggregation
- **Node Exporter** - System metrics
- **cAdvisor** - Container metrics

**Purpose:** Comprehensive observability and monitoring

#### 2. Nextcloud (Priority: High)
- **Storage:** Use subvol1-docs, subvol2-pics, subvol3-opptak
- **Database:** PostgreSQL or MariaDB (with NOCOW)
- **Redis:** Caching (with NOCOW)
- **Authentication:** Integrate with Tinyauth

**Purpose:** File sync, calendar, contacts, photos

#### 3. Service Dashboard (Priority: Medium)
- **Heimdall**
- **Purpose:** Central access point for all services
- **Features:** Service status, quick links, custom widgets

#### 4. Additional Services (Priority: Low)
- **Uptime Kuma** - Uptime monitoring
- **Vaultwarden** - Password manager
- **Immich** - Photo management (use subvol3-opptak)
- **Paperless-ngx** - Document management
- **Audiobookshelf** - Audiobook server

---

## 🔧 Maintenance

### Daily Tasks

**Automated:**
- Cloudflare DDNS updates (every 30 minutes)
- Container health checks (systemd)
- Automatic restarts on failure

**Manual Verification (optional):**
```bash
# Quick health check
podman ps --format "table {{.Names}}\t{{.Status}}"

# Check CrowdSec activity
podman exec crowdsec cscli metrics

# Verify SSL expiry
echo | openssl s_client -servername patriark.org -connect patriark.org:443 2>/dev/null | \
  openssl x509 -noout -dates
```

### Weekly Tasks

1. **Review Logs**
   ```bash
   journalctl --user -u traefik.service --since "1 week ago" | grep -i error
   journalctl --user -u crowdsec.service --since "1 week ago"
   ```

2. **Check Disk Usage**
   ```bash
   sudo btrfs fi usage -T /mnt
   df -h /
   ```

3. **Review CrowdSec Decisions**
   ```bash
   podman exec crowdsec cscli decisions list
   ```

### Monthly Tasks

1. **BTRFS Scrub**
   ```bash
   sudo btrfs scrub start -Bd /mnt
   sudo btrfs scrub start -Bd /
   sudo btrfs scrub status /mnt
   ```

2. **SMART Tests**
   ```bash
   sudo smartctl -t short /dev/sda
   sudo smartctl -t short /dev/sdb
   # Wait 2 minutes
   sudo smartctl -H /dev/sda
   sudo smartctl -H /dev/sdb
   ```

3. **Container Updates**
   ```bash
   podman auto-update --dry-run
   podman auto-update
   systemctl --user restart traefik.service crowdsec.service tinyauth.service jellyfin.service
   ```

4. **Backup Verification**
   ```bash
   # Mount backup drive
   sudo mount /dev/mapper/WD-18TB /run/media/patriark/WD-18TB
   
   # Verify snapshots exist
   sudo btrfs subvolume list -p /run/media/patriark/WD-18TB/.snapshots
   
   # Verify space
   sudo btrfs fi usage -T /run/media/patriark/WD-18TB
   ```

5. **SSL Certificate Check**
   ```bash
   # Verify auto-renewal is working
   ls -la ~/containers/config/traefik/letsencrypt/acme.json
   ```

### Quarterly Tasks

1. **Full System Review**
   - Review all logs for patterns
   - Check for security advisories
   - Review firewall rules
   - Audit user accounts and permissions

2. **BTRFS Balance**
   ```bash
   sudo btrfs balance start -dusage=50 /mnt
   ```

3. **Snapshot Cleanup**
   ```bash
   # Remove snapshots older than 90 days
   sudo find /mnt/btrfs-pool/.snapshots -type d -mtime +90 \
     -exec btrfs subvolume delete {} +
   ```

4. **Documentation Update**
   - Review and update this document
   - Update network diagrams if changed
   - Document any new services or changes

---

## 🔍 Troubleshooting

### Service Won't Start

```bash
# Check service status
systemctl --user status <service>.service

# View logs
journalctl --user -u <service>.service -n 50

# Verify quadlet file
cat ~/.config/containers/systemd/<service>.container

# Check if image exists
podman images | grep <service>

# Try pulling image manually
podman pull docker.io/<image>:<tag>

# Reload systemd and restart
systemctl --user daemon-reload
systemctl --user restart <service>.service
```

### SSL Certificate Issues

```bash
# Check certificate expiry
echo | openssl s_client -servername patriark.org -connect patriark.org:443 2>/dev/null | \
  openssl x509 -noout -dates

# Verify acme.json exists
ls -la ~/containers/config/traefik/letsencrypt/acme.json

# Check Traefik logs
podman logs traefik --tail 100 | grep -i certificate

# Force certificate renewal (if needed)
# Remove acme.json and restart Traefik
rm ~/containers/config/traefik/letsencrypt/acme.json
systemctl --user restart traefik.service
```

### Authentication Loop

```bash
# Check Tinyauth is running
podman ps | grep tinyauth

# Check Tinyauth logs
podman logs tinyauth --tail 50

# Verify APP_URL environment variable
podman inspect tinyauth | grep APP_URL

# Check Traefik middleware configuration
cat ~/containers/config/traefik/dynamic/middleware.yml

# Clear browser cookies and try again
# Test with curl
curl -I https://jellyfin.patriark.org
```

### CrowdSec Not Blocking

```bash
# Check CrowdSec is running
podman ps | grep crowdsec

# Check bouncer connection
podman exec crowdsec cscli bouncers list

# View current decisions
podman exec crowdsec cscli decisions list

# Test manual ban
MY_IP=$(curl -s ifconfig.me)
podman exec crowdsec cscli decisions add --ip $MY_IP --duration 5m
curl -I https://jellyfin.patriark.org
# Should return 403

# Remove test ban
podman exec crowdsec cscli decisions delete --ip $MY_IP
```

### DNS Not Resolving

```bash
# Check public DNS
dig @1.1.1.1 patriark.org
dig @8.8.8.8 jellyfin.patriark.org

# Check Cloudflare DNS
dig @cam.ns.cloudflare.com patriark.org

# Check local Pi-hole
dig @192.168.1.69 patriark.org

# Verify DDNS script
~/containers/scripts/cloudflare-ddns.sh

# Check current public IP
curl -s ifconfig.me
```

### Container Networking Issues

```bash
# List networks
podman network ls

# Inspect network
podman network inspect systemd-reverse_proxy

# Check container network assignment
podman inspect <container> | grep -A 5 Networks

# Restart networking
systemctl --user restart traefik.service
```

### BTRFS Issues

```bash
# Check filesystem health
sudo btrfs scrub status /mnt

# View errors in logs
sudo journalctl -k | grep -i btrfs

# Check space
sudo btrfs fi usage -T /mnt

# Check device stats
sudo btrfs device stats /mnt

# Run scrub if needed
sudo btrfs scrub start -Bd /mnt
```

### Storage Full

```bash
# Check space
df -h
sudo btrfs fi usage -T /mnt

# Find large files
du -h --max-depth=1 /mnt/btrfs-pool | sort -h

# Clean up old snapshots
sudo btrfs subvolume list -p /mnt/btrfs-pool/.snapshots
sudo btrfs subvolume delete <old-snapshot>

# Clean up container storage
podman system prune -a
```

---

## 📊 Monitoring & Observability

### Current Monitoring Capabilities

**Service Health:**
- Systemd status (`systemctl --user status`)
- Container health checks (Podman)
- Process monitoring (automatic restarts)

**Logs:**
- Systemd journal (`journalctl --user`)
- Container logs (`podman logs`)
- Traefik access logs

**Security:**
- CrowdSec alerts and decisions
- Traefik error logs
- Failed authentication attempts (Tinyauth logs)

**Metrics:**
- CrowdSec metrics (`cscli metrics`)
- Traefik internal metrics (API on port 8080)
- System resources (`htop`, `podman stats`)

### Future Monitoring Stack (Planned)

```
Grafana (Visualization)
    ↓
Prometheus (Metrics Collection)
    ↓
├── Node Exporter (System metrics)
├── cAdvisor (Container metrics)
├── Traefik metrics endpoint
└── BTRFS exporter (Storage metrics)
    ↓
Loki (Log Aggregation)
    ↓
├── Traefik logs
├── CrowdSec logs
├── Application logs
└── Systemd journal
```

**Benefits:**
- Centralized dashboards
- Historical trend analysis
- Proactive alerting
- Capacity planning
- Performance optimization

---

## 🎓 Learning Resources

### Core Technologies

**Traefik:**
- Official docs: https://doc.traefik.io/traefik/
- Getting started: https://doc.traefik.io/traefik/getting-started/quick-start/

**Podman:**
- Official docs: https://docs.podman.io/
- Quadlets guide: https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html

**CrowdSec:**
- Official docs: https://docs.crowdsec.net/
- Traefik bouncer: https://github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin

**BTRFS:**
- Arch Wiki (excellent resource): https://wiki.archlinux.org/title/Btrfs
- Official docs: https://btrfs.readthedocs.io/

**Let's Encrypt:**
- How it works: https://letsencrypt.org/how-it-works/
- ACME protocol: https://letsencrypt.org/docs/client-options/

### System Design Principles

**Homelab Best Practices:**
- Infrastructure as Code
- Declarative configuration
- Immutable infrastructure
- Defense in depth
- Least privilege access
- Regular backups and snapshots
- Monitoring and observability
- Documentation as you build

---

## 📝 Change Log

### 2025-10-25 Rev 2 - Storage Architecture Integration
- Integrated detailed storage architecture from authoritative rev2
- Added complete BTRFS subvolume structure (7 subvolumes)
- Documented LUKS-encrypted backup strategy
- Updated directory tree with script status annotations
- Added network topology details (auth_services, media_services)
- Clarified future monitoring stack plans
- Updated next steps priorities

### 2025-10-23 - Initial Production Setup
- Replaced Authelia with Tinyauth
- Configured Cloudflare DDNS
- Implemented Let's Encrypt SSL
- Added CrowdSec security
- Documented complete architecture

### Future Changes
- [Date] - Add 2FA to Tinyauth
- [Date] - Deploy monitoring stack (Grafana/Prometheus/Loki)
- [Date] - Deploy Nextcloud
- [Date] - Add service dashboard (Homepage)

---

## 🎯 Next Steps (Priority Order)

### Phase 1: Documentation & Git (Current Focus)
1. ✅ Get documentation in order
2. ⬜ Initialize Git repository
3. ⬜ Create .gitignore (exclude secrets, tokens)
4. ⬜ Commit current configuration
5. ⬜ Set up Git workflow (branching strategy)
6. ⬜ Document Git usage in operations guide

### Phase 2: Monitoring & Observability
1. ⬜ Deploy Prometheus
2. ⬜ Deploy Grafana
3. ⬜ Deploy Loki
4. ⬜ Configure exporters (Node, cAdvisor)
5. ⬜ Create dashboards
6. ⬜ Set up alerting rules

### Phase 3: Service Dashboard
1. ⬜ Deploy Homepage or Heimdall
2. ⬜ Configure service links
3. ⬜ Add service status widgets
4. ⬜ Integrate with monitoring

### Phase 4: Enhanced Security
1. ⬜ Add 2FA to Tinyauth (TOTP)
2. ⬜ Consider WebAuthn/FIDO2
3. ⬜ Security audit of current setup
4. ⬜ Harden container configurations
5. ⬜ Review and update firewall rules

### Phase 5: Nextcloud Deployment
1. ⬜ Deploy MariaDB (with NOCOW)
2. ⬜ Deploy Redis (with NOCOW)
3. ⬜ Deploy Nextcloud
4. ⬜ Configure storage mounts
5. ⬜ Integrate authentication
6. ⬜ Set up mobile apps

---

## 📞 Quick Reference

### Important URLs

| Service | URL | Authentication |
|---------|-----|----------------|
| Jellyfin | https://jellyfin.patriark.org | Tinyauth → Jellyfin |
| Traefik Dashboard | https://traefik.patriark.org | Tinyauth |
| Tinyauth Portal | https://auth.patriark.org | Direct login |

### Important Commands

```bash
# Restart all services
systemctl --user restart traefik.service crowdsec.service tinyauth.service jellyfin.service

# View service logs
journalctl --user -u traefik.service -f

# Update containers
podman auto-update

# Create config backup
tar -czf ~/backup-$(date +%Y%m%d).tar.gz ~/containers/config ~/.config/containers/systemd

# Check CrowdSec status
podman exec crowdsec cscli metrics

# Manual DDNS update
~/containers/scripts/cloudflare-ddns.sh

# BTRFS scrub
sudo btrfs scrub start -Bd /mnt
sudo btrfs scrub status /mnt

# Check storage
sudo btrfs fi usage -T /mnt
```

### Important Files

```bash
# Traefik
~/containers/config/traefik/traefik.yml
~/containers/config/traefik/dynamic/routers.yml
~/containers/config/traefik/dynamic/middleware.yml

# Systemd Quadlets
~/.config/containers/systemd/*.container
~/.config/containers/systemd/*.network

# Secrets
~/containers/secrets/cloudflare_token
~/containers/secrets/cloudflare_zone_id

# Scripts
~/containers/scripts/cloudflare-ddns.sh
~/containers/scripts/security-audit.sh
```

### Storage Locations

```bash
# System SSD
/ - Root filesystem (BTRFS)
/home - User data (BTRFS)
~/.snapshots - SSD snapshots

# Data Pool
/mnt/btrfs-pool - Multi-device BTRFS pool
/mnt/btrfs-pool/.snapshots - Pool snapshots
/mnt/btrfs-pool/subvol[1-7]* - Data subvolumes

# Backup Drives (LUKS)
/run/media/patriark/WD-18TB - External backup
```

---

## 🏆 Best Practices Implemented

1. ✅ **Least Privilege** - Rootless containers, minimal permissions
2. ✅ **Defense in Depth** - Multiple security layers
3. ✅ **Automation** - DDNS, SSL renewal, restarts, snapshots
4. ✅ **Declarative Config** - Quadlets, YAML files
5. ✅ **Immutable Infrastructure** - Containers, not processes
6. ✅ **Observability** - Structured logs, metrics available
7. ✅ **Documentation** - Comprehensive architecture docs
8. ✅ **Backups** - BTRFS snapshots, LUKS-encrypted external backups
9. ✅ **Secrets Management** - Separated, protected files (chmod 600)
10. ✅ **Network Segmentation** - Isolated container networks

---

## 🎊 Conclusion

This homelab represents a **production-grade, secure, self-hosted infrastructure** using modern DevOps practices and enterprise-grade tools. The architecture is:

- **Secure** - Multiple layers of protection, encrypted backups
- **Reliable** - Self-healing, automatic recovery, BTRFS snapshots
- **Maintainable** - Well-documented, easy to understand
- **Scalable** - Easy to add new services, expandable storage
- **Professional** - Industry-standard tools and practices
- **Storage-optimized** - BTRFS with snapshots, RAID1-ready, encrypted backups

**You're building something impressive!** 🌟

---

**Document Version:** 2.0
**Last Review:** October 25, 2025
**Next Review:** January 25, 2026
**Authoritative Sources:**
- This document (overall architecture)
- 20251025-storage-architecture-authoritative-rev2.md (storage details)
