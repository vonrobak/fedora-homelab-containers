# Homelab Architecture - Visual Diagrams

**Last Updated:** October 25, 2025 (Rev 2)
**Owner:** patriark
**Companion Document:** HOMELAB-ARCHITECTURE-DOCUMENTATION-rev2.md
**Storage Details:** 20251025-storage-architecture-authoritative-rev2.md

---

## 🌐 Network Flow Diagram

```
                          INTERNET
                             │
                             │ DNS Query
                             ↓
                    ┌────────────────┐
                    │   Cloudflare   │ patriark.org → 62.249.184.112
                    │   DNS Server   │ (Updated every 30 min via API)
                    └────────────────┘
                             │
                             │ HTTPS Request
                             ↓
                ┌────────────────────────┐
                │   ISP / Public IP      │
                │   62.249.184.112       │
                └────────────────────────┘
                             │
                             │ Port Forward
                             │ :80 → :80
                             │ :443 → :443
                             ↓
                ┌────────────────────────┐
                │   UDM Pro Firewall     │
                │   192.168.1.1          │
                │   ┌──────────────────┐ │
                │   │ Port Forwarding  │ │
                │   │ :80  → .70:80    │ │
                │   │ :443 → .70:443   │ │
                │   └──────────────────┘ │
                └────────────────────────┘
                             │
                             │ Local Network
                             │ 192.168.1.0/24
                             ↓
                ┌────────────────────────┐
                │   fedora-htpc          │
                │   192.168.1.70         │
                │                        │
                │   ┌────────────────┐   │
                │   │   CrowdSec     │   │ ← Threat Check
                │   │   Layer        │   │   ✓ Pass / ✗ Block 403
                │   └────────────────┘   │
                │           │            │
                │           ↓            │
                │   ┌────────────────┐   │
                │   │    Traefik     │   │ ← Reverse Proxy
                │   │   :80 / :443   │   │   • SSL Termination
                │   │                │   │   • Rate Limiting
                │   └────────────────┘   │   • Route Matching
                │           │            │
                │           ↓            │
                │   ┌────────────────┐   │
                │   │   Tinyauth     │   │ ← Authentication
                │   │   :3000        │   │   ✓ Session / ✗ Login
                │   └────────────────┘   │   (Future: 2FA support)
                │           │            │
                │           ↓            │
                │   ┌────────────────┐   │
                │   │    Service     │   │ ← Application
                │   │  (Jellyfin)    │   │   Render Response
                │   │    :8096       │   │
                │   └────────────────┘   │
                └────────────────────────┘
                             │
                             ↓
                        RESPONSE
```

---

## 🔐 Security Layers

```
┌─────────────────────────────────────────────────────────┐
│  LAYER 7: APPLICATION AUTH                               │
│  ┌───────────────────────────────────────────────────┐  │
│  │ Tinyauth SSO                                      │  │
│  │ • Session-based authentication                    │  │
│  │ • Bcrypt password hashing                         │  │
│  │ • Cookie management                               │  │
│  │ • Future: TOTP 2FA / WebAuthn                     │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────┐
│  LAYER 6: RATE LIMITING                                  │
│  ┌───────────────────────────────────────────────────┐  │
│  │ Traefik Middleware                                │  │
│  │ • 100 requests/minute                             │  │
│  │ • Burst: 50 requests                              │  │
│  │ • Per-IP tracking                                 │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────┐
│  LAYER 5: THREAT INTELLIGENCE                            │
│  ┌───────────────────────────────────────────────────┐  │
│  │ CrowdSec Bouncer                                  │  │
│  │ • Global IP reputation                            │  │
│  │ • Behavioral analysis                             │  │
│  │ • Community blocklists                            │  │
│  │ • Automatic banning                               │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────┐
│  LAYER 4: TLS ENCRYPTION                                 │
│  ┌───────────────────────────────────────────────────┐  │
│  │ Let's Encrypt Certificates                        │  │
│  │ • TLS 1.2+ only                                   │  │
│  │ • Strong ciphers                                  │  │
│  │ • Perfect forward secrecy                         │  │
│  │ • Auto-renewal every 90 days                      │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────┐
│  LAYER 3: SECURITY HEADERS                               │
│  ┌───────────────────────────────────────────────────┐  │
│  │ HTTP Security Headers                             │  │
│  │ • X-Frame-Options: SAMEORIGIN                     │  │
│  │ • X-Content-Type-Options: nosniff                 │  │
│  │ • HSTS: max-age=31536000                          │  │
│  │ • Strict headers in security-headers-strict.yml   │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────┐
│  LAYER 2: PORT FILTERING                                 │
│  ┌───────────────────────────────────────────────────┐  │
│  │ UDM Pro Firewall                                  │  │
│  │ • Only ports 80/443 exposed                       │  │
│  │ • Port forwarding rules                           │  │
│  │ • Stateful inspection                             │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────┐
│  LAYER 1: NETWORK ISOLATION                              │
│  ┌───────────────────────────────────────────────────┐  │
│  │ Container Networks                                │  │
│  │ • Isolated bridge networks                        │  │
│  │ • No direct internet access for containers        │  │
│  │ • Traefik as only gateway                         │  │
│  │ • Rootless containers (UID 1000)                  │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

---

## 🐳 Container Network Topology

```
Host: fedora-htpc (192.168.1.70)
│
├─── systemd-reverse_proxy Network (10.89.2.0/24)
│    │
│    ├─── traefik (10.89.2.x)
│    │    ├─ Port 80 → Host:80
│    │    ├─ Port 443 → Host:443
│    │    └─ Port 8080 → Host:8080 (Dashboard)
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
├─── systemd-auth_services Network (IDLE)
│    └─── (No services currently assigned)
│    └─── (Reserved for future auth infrastructure)
│
├─── systemd-media_services Network
│    └─── (Future: dedicated media network separation)
│
└─── Host Network
     ├─ DNS: 192.168.1.69 (Pi-hole)
     ├─ Gateway: 192.168.1.1 (UDM Pro)
     └─ Public IP: 62.249.184.112 (Dynamic, DDNS every 30 min)
```

---

## 💾 Storage Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    STORAGE HIERARCHY                         │ # External backup HDD is also in use for System SSD snapshots
└─────────────────────────────────────────────────────────────┘
                             │
              ┌──────────────┴──────────────┐
              │                             │
      ┌───────▼────────┐            ┌──────▼─────────┐
      │  System SSD    │            │   HDD Pool     │
      │   (BTRFS)      │            │   (BTRFS)      │
      │  Unencrypted   │            │  Unencrypted   │
      └───────┬────────┘            └──────┬─────────┘
              │                             │
              │                             │
      ┌───────▼────────┐            ┌──────▼─────────┐
      │ Subvolumes:    │            │ 7 Subvolumes:  │
      │ • root (/)     │            │ • subvol1-docs │
      │ • home (/home) │            │ • subvol2-pics │
      └───────┬────────┘            │ • subvol3-photos│
              │                     │ • subvol4-music│
              │                     │ • subvol5-media│
      ┌───────▼────────┐            │ • subvol6-arch │
      │ ~/containers/  │            │ • subvol7-back │
      │ ├─ config/     │            └──────┬─────────┘
      │ ├─ data/       │                   │
      │ ├─ db/ (NOCOW) │                   │
      │ ├─ docs/       │            ┌──────▼─────────┐
      │ ├─ scripts/    │            │ Snapshots:     │
      │ └─ secrets/    │            │ .snapshots/    │
      └───────┬────────┘            │ ├─ hourly (24) │
              │                     │ ├─ daily (14)  │
              │                     │ ├─ weekly (8)  │
      ┌───────▼────────┐            │ └─ monthly (6) │
      │ Snapshots:     │            └──────┬─────────┘
      │ ~/.snapshots/  │                   │
      │ ├─ home/       │                   │
      │ └─ root/       │                   │
      └────────────────┘                   │
                                           │
                                    ┌──────▼─────────┐
                                    │ External Backup│
                                    │  (LUKS-BTRFS)  │
                                    │    Encrypted   │
                                    │  WD-18TB etc.  │
                                    └────────────────┘
```

### Storage Data Flow

```
[Service Container]
       │
       │ Mount volumes
       ▼
[Config: SSD]          [Data: SSD or HDD]         [Media: HDD]
~/containers/          ~/containers/data/          /mnt/btrfs-pool/
config/<svc>/          <svc>/ (if small)          subvol5-multimedia/
       │                      │                           │
       │                      │                           │
       ▼                      ▼                           ▼
[BTRFS Subvolume]     [BTRFS Subvolume]          [BTRFS Subvolume]
    /home                   /home                      /mnt
       │                      │                           │
       │                      │                           │
       ▼                      ▼                           ▼
[Automatic Snapshots]  [Automatic Snapshots]      [Automatic Snapshots]
~/.snapshots/          ~/.snapshots/              /mnt/btrfs-pool/
home/                  home/                      .snapshots/
       │                      │                           │
       └──────────────┬───────┴───────────────────────────┘
                      │
                      │ Weekly: btrfs send/receive
                      ▼
             [LUKS-encrypted Backup]
             /run/media/patriark/WD-18TB
```

---

## 📊 Data Flow: User Request

```
1. User enters URL
   https://jellyfin.patriark.org
   
2. DNS Resolution
   Browser → Pi-hole (192.168.1.69) → 192.168.1.70 (LAN)
   Browser → Cloudflare → 62.249.184.112 (WAN)
   
3. TLS Handshake
   Browser ←TLS→ Traefik
   • Certificate validation (Let's Encrypt)
   • Encrypted connection established
   
4. HTTP Request Hits Traefik
   GET https://jellyfin.patriark.org/
   ├─ Load CrowdSec middleware
   │  └─ Check IP reputation
   │     ├─ Banned? → 403 Forbidden (STOP)
   │     └─ Clean? → Continue
   ├─ Load Rate Limit middleware
   │  └─ Check request rate
   │     ├─ Exceeded? → 429 Too Many Requests (STOP)
   │     └─ OK? → Continue
   ├─ Load Security Headers middleware
   │  └─ Add security headers to response
   ├─ Load Forward Auth middleware (Tinyauth)
   │  └─ Check session cookie
   │     ├─ Valid session? → Continue to service
   │     └─ No session? → 302 Redirect to auth.patriark.org
   │
   └─ Forward to Jellyfin service
      GET http://jellyfin:8096/
      
5. Service Response
   Jellyfin → Traefik → Browser
   • Response includes security headers
   • Response cached if applicable
   
6. If Authentication Required
   User redirected to auth.patriark.org
   ├─ User enters credentials
   ├─ Tinyauth validates (bcrypt)
   ├─ Creates session cookie
   └─ Redirects back to jellyfin.patriark.org
```

---

## 🗂️ Complete Directory Structure

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
│   │   └── certs/                  # (deprecated - can remove)
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
├── db/                             # Database storage (NOCOW)
│   └── (apply chattr +C when creating)
│
├── scripts/                        # Automation scripts
│   ├── cloudflare-ddns.sh          # ACTIVE: DNS updater (every 30 min)
│   ├── collect-storage-info.sh     # BUGGY: needs revision
│   ├── deploy-jellyfin-with-traefik.sh # LEGACY: archive candidate
│   ├── fix-podman-secrets.sh       # LEGACY: scrutiny needed
│   ├── homelab-diagnose.sh         # LEGACY: needs revision
│   ├── jellyfin-manage.sh          # LEGACY: needs documentation
│   ├── jellyfin-status.sh          # LEGACY: needs documentation
│   ├── organize-docs.sh            # OUTDATED: needs revision
│   ├── security-audit.sh           # LEGACY: may have valid checks
│   ├── show-pod-status.sh          # LEGACY: unclear status
│   └── survey.sh                   # RECENT: has bugs, needs revision
│
├── secrets/                        # Sensitive data (chmod 600)
│   ├── cloudflare_token           # ACTIVE: API token
│   ├── cloudflare_zone_id         # ACTIVE: Zone ID
│   ├── redis_password             # LEGACY: from Authelia, can remove
│   └── smtp_password              # LEGACY: from Authelia, can remove
│
├── backups/                        # Configuration backups
│   └── (May be superfluous with BTRFS snapshots)
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
│   │   ├── HOMELAB-ARCHITECTURE-DIAGRAMS.md (this file)
│   │   ├── HOMELAB-ARCHITECTURE-DOCUMENTATION.md
│   │   ├── NEXTCLOUD-INSTALLATION-GUIDE.md
│   │   ├── QUICK-REFERENCE.md
│   │   └── (other operational docs)
│   ├── 30-security/
│   │   └── TINYAUTH-GUIDE.md
│   ├── 90-archive/
│   │   └── (older versions and deprecated docs)
│   └── 99-reports/
│       ├── 20251025-storage-architecture-authoritative-rev2.md
│       └── (diagnostic outputs and summaries)
│
└── quadlets → ~/.config/containers/systemd  # Symlink

/home/patriark/.config/containers/systemd/
├── auth_services.network           # Bridge network (IDLE, no services)
├── crowdsec.container              # CrowdSec service definition
├── jellyfin.container              # Jellyfin service definition
├── media_services.network          # Bridge network (future use)
├── reverse_proxy.network           # Bridge network (all current services)
├── tinyauth.container              # Tinyauth service definition
└── traefik.container               # Traefik service definition

/mnt/btrfs-pool/                    # BTRFS multi-device pool
├── subvol1-docs/                   # Documents (Nextcloud R/W)
├── subvol2-pics/                   # Pictures (Nextcloud R/W)
├── subvol3-photos/                 # Personal photos (Nextcloud/Immich)
├── subvol4-music/                  # Music library
├── subvol5-media-video/            # Video library (Jellyfin)
│   ├── movies/
│   └── tv/
├── subvol6-archives/               # Long-term archives
├── subvol7-backups/                # Config backups destination
└── .snapshots/                     # Snapshot storage
    ├── subvol1-docs/
    │   ├── 2025102512-hourly
    │   ├── 20251025-daily
    │   ├── 20251020-weekly
    │   └── 20251001-monthly
    └── (one directory per subvolume)
```

---

## 🔄 Update & Maintenance Flow

```
┌─────────────────────────────────────────────────────────┐
│                    MONTHLY MAINTENANCE                   │
└─────────────────────────────────────────────────────────┘
                             │
                             ↓
                    ┌────────────────┐
                    │ BTRFS Scrub    │
                    │ • sudo btrfs   │
                    │   scrub start  │
                    │   -Bd /mnt     │
                    └────────┬───────┘
                             ↓
                    ┌────────────────┐
                    │ SMART Tests    │
                    │ • smartctl -t  │
                    │   short /dev/  │
                    │   sd[abc]      │
                    └────────┬───────┘
                             ↓
                    ┌────────────────┐
                    │ Create Backup  │
                    │ • BTRFS snap   │
                    │ • Config tar   │
                    └────────┬───────┘
                             ↓
                    ┌────────────────┐
                    │ Update Check   │
                    │ podman auto-   │
                    │ update --dry   │
                    └────────┬───────┘
                             ↓
                    ┌────────────────┐
                    │ Pull Updates   │
                    │ podman auto-   │
                    │ update         │
                    └────────┬───────┘
                             ↓
                    ┌────────────────┐
                    │ Restart Svc    │
                    │ systemctl      │
                    │ restart *      │
                    └────────┬───────┘
                             ↓
                    ┌────────────────┐
                    │ Test Services  │
                    │ • Check access │
                    │ • Check logs   │
                    └────────┬───────┘
                             ↓
                    ┌────────────────┐
                    │ All OK?        │
                    └────────┬───────┘
                             │
                    ┌────────┴────────┐
                    │                 │
                   Yes               No
                    │                 │
                    ↓                 ↓
            ┌───────────┐     ┌──────────────┐
            │ Complete  │     │ Rollback     │
            │           │     │ BTRFS snap   │
            └───────────┘     └──────────────┘
```

---

## 🚀 Service Addition Workflow

```
┌────────────────────────────────────────────────────────┐
│                   ADD NEW SERVICE                       │
└────────────────────────────────────────────────────────┘
                            │
                            ↓
                   ┌────────────────┐
                   │ 1. Research    │
                   │ • Find image   │
                   │ • Check ports  │
                   │ • Read docs    │
                   │ • Plan storage │
                   └────────┬───────┘
                            ↓
                   ┌────────────────┐
                   │ 2. Create Dir  │
                   │ mkdir config/  │
                   │ mkdir data/    │
                   │ (or map HDD)   │
                   └────────┬───────┘
                            ↓
                   ┌────────────────┐
                   │ 3. Quadlet     │
                   │ Write .container│
                   │ file + volumes │
                   │ + network      │
                   └────────┬───────┘
                            ↓
                   ┌────────────────┐
                   │ 4. Network     │
                   │ Assign to      │
                   │ correct bridge │
                   └────────┬───────┘
                            ↓
                   ┌────────────────┐
                   │ 5. Traefik     │
                   │ Add router +   │
                   │ service +      │
                   │ middleware     │
                   └────────┬───────┘
                            ↓
                   ┌────────────────┐
                   │ 6. Start       │
                   │ systemctl      │
                   │ daemon-reload  │
                   │ start service  │
                   └────────┬───────┘
                            ↓
                   ┌────────────────┐
                   │ 7. Test        │
                   │ • Check logs   │
                   │ • Test access  │
                   │ • Verify auth  │
                   │ • Check storage│
                   └────────┬───────┘
                            ↓
                   ┌────────────────┐
                   │ 8. Snapshot    │
                   │ Create BTRFS   │
                   │ snapshot of    │
                   │ working state  │
                   └────────┬───────┘
                            ↓
                   ┌────────────────┐
                   │ 9. Document    │
                   │ Update docs    │
                   │ with new svc   │
                   └────────────────┘
```

---

## 📈 Monitoring Stack Architecture (Planned)

```
┌─────────────────────────────────────────────────────────┐
│                     OBSERVABILITY STACK                  │
└─────────────────────────────────────────────────────────┘
                             │
                    ┌────────┴────────┐
                    │                 │
            ┌───────▼───────┐  ┌──────▼──────┐
            │   Grafana     │  │  Alerting   │
            │  (Dashboard)  │  │   Manager   │
            └───────┬───────┘  └─────────────┘
                    │
        ┌───────────┼───────────┐
        │           │           │
┌───────▼──────┐ ┌──▼──────┐ ┌─▼────────┐
│  Prometheus  │ │  Loki   │ │  Tempo   │
│  (Metrics)   │ │ (Logs)  │ │ (Traces) │
└───────┬──────┘ └──┬──────┘ └──────────┘
        │           │
        └─────┬─────┘
              │
    ┌─────────┼─────────┬─────────┐
    │         │         │         │
┌───▼────┐ ┌──▼────┐ ┌──▼───┐ ┌──▼─────┐
│  Node  │ │cAdvisor│ │Traefik│ │ App   │
│Exporter│ │ (cont) │ │metrics│ │ logs  │
└────────┘ └────────┘ └───────┘ └────────┘
```

### Metrics Collection

```
[System Metrics]          [Container Metrics]       [App Metrics]
Node Exporter      →      cAdvisor           →      Traefik
• CPU usage               • CPU per container       • Request rate
• Memory                  • Memory per container    • Response time
• Disk I/O                • Network per container   • Error rate
• Network                 • Disk I/O per container  • Status codes
      │                         │                         │
      └─────────────────────────┼─────────────────────────┘
                                │
                          [Prometheus]
                          Time-series DB
                                │
                          [Grafana]
                          Dashboards
```

### Log Aggregation

```
[Container Logs]          [System Logs]           [Application Logs]
Podman logs        →      Journald         →      Traefik access logs
• stdout/stderr           • systemd units         • CrowdSec logs
• Container events        • kernel messages       • Auth attempts
      │                         │                         │
      └─────────────────────────┼─────────────────────────┘
                                │
                            [Promtail]
                          Log shipper
                                │
                             [Loki]
                        Log aggregation
                                │
                          [Grafana]
                        Log explorer
```

---

## 🎯 Next Steps Visualization

```
┌────────────────────────────────────────────────────────┐
│                    PROJECT ROADMAP                      │
└────────────────────────────────────────────────────────┘

PHASE 1: DOCUMENTATION & GIT (CURRENT)
├─ ✅ Consolidate documentation
├─ ⬜ Initialize Git repository
├─ ⬜ Create .gitignore
├─ ⬜ Initial commit
└─ ⬜ Document Git workflow
       │
       ↓
PHASE 2: MONITORING & OBSERVABILITY (HIGH PRIORITY)
├─ ⬜ Deploy Prometheus
├─ ⬜ Deploy Grafana
├─ ⬜ Deploy Loki + Promtail
├─ ⬜ Configure exporters
├─ ⬜ Create dashboards
└─ ⬜ Set up alerting
       │
       ↓
PHASE 3: SERVICE DASHBOARD (HIGH PRIORITY)
├─ ⬜ Deploy Homepage/Heimdall
├─ ⬜ Configure service links
└─ ⬜ Add monitoring widgets
       │
       ↓
PHASE 4: ENHANCED SECURITY (HIGH PRIORITY)
├─ ⬜ Add 2FA to Tinyauth
├─ ⬜ Security audit
├─ ⬜ Container hardening
└─ ⬜ Firewall review
       │
       ↓
PHASE 5: NEXTCLOUD (HIGH PRIORITY)
├─ ⬜ Deploy PostgreSQL
├─ ⬜ Deploy Redis
├─ ⬜ Deploy Nextcloud
└─ ⬜ Configure storage mounts
       │
       ↓
FUTURE: ADDITIONAL SERVICES
├─ ⬜ Immich (photos)
├─ ⬜ Vaultwarden (passwords)
├─ ⬜ Paperless-ngx (documents)
└─ ⬜ AudioBookshelf (audiobooks)
```

---

## 🔐 Security Hardening Checklist

```
┌────────────────────────────────────────────────────────┐
│                  SECURITY POSTURE                       │
└────────────────────────────────────────────────────────┘

✅ IMPLEMENTED
├─ ✓ Rootless containers
├─ ✓ SELinux enforcing
├─ ✓ Multi-layer defense
├─ ✓ Forward authentication
├─ ✓ Rate limiting
├─ ✓ CrowdSec threat intel
├─ ✓ TLS 1.2+ only
├─ ✓ Security headers
├─ ✓ Port minimization (80/443 only)
├─ ✓ Network isolation
└─ ✓ Encrypted backups (LUKS)

⬜ PLANNED IMPROVEMENTS
├─ ⬜ 2FA (TOTP/WebAuthn)
├─ ⬜ Fail2ban integration
├─ ⬜ Automated security scanning
├─ ⬜ WAF (Web Application Firewall)
├─ ⬜ Intrusion detection (IDS)
└─ ⬜ Regular penetration testing

📋 AUDIT AREAS
├─ Container configurations
├─ File permissions
├─ Secret management
├─ Network policies
├─ Firewall rules
└─ Update procedures
```

---

## 📊 System Health Overview

```
┌────────────────────────────────────────────────────────┐
│                   HEALTH INDICATORS                     │
└────────────────────────────────────────────────────────┘

SERVICES
├─ traefik.service    → systemctl --user status traefik.service
├─ crowdsec.service   → systemctl --user status crowdsec.service
├─ tinyauth.service   → systemctl --user status tinyauth.service
└─ jellyfin.service   → systemctl --user status jellyfin.service

STORAGE
├─ SSD usage          → df -h /
├─ HDD pool usage     → sudo btrfs fi usage -T /mnt
├─ Snapshot count     → sudo btrfs subvolume list -p /mnt | grep -c .snapshots
└─ SMART health       → sudo smartctl -H /dev/sd[abc]

SECURITY
├─ CrowdSec metrics   → podman exec crowdsec cscli metrics
├─ Active bans        → podman exec crowdsec cscli decisions list
├─ SSL expiry         → openssl s_client -connect patriark.org:443
└─ Auth attempts      → podman logs tinyauth | grep -i login

NETWORK
├─ Public IP          → curl -s ifconfig.me
├─ DNS resolution     → dig patriark.org
├─ Port forwarding    → nmap -p 80,443 62.249.184.112
└─ Container network  → podman network inspect systemd-reverse_proxy
```

---

This visual documentation complements the text documentation and provides clear diagrams for understanding the system architecture, with special emphasis on storage architecture and the integration of BTRFS with snapshots and encrypted backups.

---

**Document Version:** 2.0
**Last Review:** October 25, 2025
**Next Review:** January 25, 2026
**Related Documents:**
- HOMELAB-ARCHITECTURE-DOCUMENTATION-rev2.md (companion text documentation)
- 20251025-storage-architecture-authoritative-rev2.md (detailed storage reference)
