---
type: Guide
title: "Homelab Architecture - Visual Diagrams"
description: "Reference guide with visual diagrams of the homelab's network flow, request path, and service topology from internet through Traefik to backends."
sensitivity: public
created: 2025-10-31
updated: 2025-12-22
---

# Homelab Architecture - Visual Diagrams

**Last Updated:** 2025-12-22
**Status:** Updated for Authelia SSO (replaced TinyAuth)

## 🌐 Network Flow Diagram

```
                          INTERNET
                             │
                             │ DNS Query
                             ↓
                    ┌────────────────┐
                    │   Cloudflare   │ patriark.org → 62.249.184.112
                    │   DNS Server   │
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
                │   │   Authelia     │   │ ← SSO Authentication
                │   │   :9091        │   │   ✓ Session / ✗ YubiKey+TOTP
                │   └────────────────┘   │
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
│  LAYER 7: APPLICATION AUTH (Authelia SSO)                │
│  ┌───────────────────────────────────────────────────┐  │
│  │ Authelia SSO + Multi-Factor Authentication        │  │
│  │ • YubiKey/WebAuthn (phishing-resistant 2FA)       │  │
│  │ • TOTP fallback (Microsoft Authenticator)         │  │
│  │ • Argon2id password hashing                       │  │
│  │ • Redis-backed session management (1h expiry)     │  │
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
│  │ • No direct internet access                       │  │
│  │ • Traefik as only gateway                         │  │
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
└─── Host Network
     ├─ DNS: 192.168.1.69 (Pi-hole)
     ├─ Gateway: 192.168.1.1 (UDM Pro)
     └─ Public IP: 62.249.184.112 (Dynamic)
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
   │     ├─ Exceeded? → 429 Too Many (STOP)
   │     └─ OK? → Continue
   ├─ Load Authelia middleware
   │  └─ Check authentication
   │     ├─ No session? → 302 Redirect to sso.patriark.org
   │     └─ Valid session? → Continue
   └─ Route to service
      └─ Forward to http://jellyfin:8096
      
5. Service Processes Request
   Jellyfin receives request
   ├─ Verify Jellyfin user session
   │  ├─ No login? → Show Jellyfin login
   │  └─ Logged in? → Render content
   └─ Return response
   
6. Response Returns
   Jellyfin → Traefik → TLS → Browser
   
7. User Sees Content
   Page renders in browser
```

---

## 🔄 Service Startup Order

```
Boot
 │
 ├─→ System Services
 │   ├─ Network
 │   ├─ Podman
 │   └─ Systemd User Session
 │
 └─→ User Services (UID 1000)
     │
     ├─→ [1] Networks Created
     │   └─ systemd-reverse_proxy
     │
     ├─→ [2] CrowdSec
     │   ├─ Load collections
     │   ├─ Start LAPI
     │   └─ Ready to accept bouncers
     │
     ├─→ [3] Authelia + Redis
     │   ├─ Load configuration
     │   ├─ Start HTTP server (:9091)
     │   ├─ Connect to Redis (session storage)
     │   └─ Ready for auth requests
     │
     ├─→ [4] Traefik
     │   ├─ Load static config
     │   ├─ Connect to Podman socket
     │   ├─ Load dynamic configs
     │   ├─ Initialize CrowdSec bouncer
     │   ├─ Check SSL certificates
     │   └─ Start listening on :80/:443
     │
     └─→ [5] Application Services
         ├─ Jellyfin
         └─ (Other services)
```

---

## 🎯 Request Path: Authenticated Access

```
┌──────────┐
│  User    │
│  Browser │
└─────┬────┘
      │
      │ 1. https://jellyfin.patriark.org
      ↓
┌─────────────┐
│  Traefik    │ ← 2. No auth cookie
└─────┬───────┘
      │
      │ 3. 302 Redirect
      ↓
┌─────────────┐
│  Authelia   │ ← 4. Show SSO login page (sso.patriark.org)
└─────┬───────┘
      │
      │ 5. POST /api/firstfactor (username + password)
      │ 6. POST /api/secondfactor/webauthn (YubiKey touch)
      ↓
┌─────────────┐
│  Authelia   │ ← 7. Validate credentials + 2FA
└─────┬───────┘
      │
      │ 7. Set session cookie
      │ 8. 302 Redirect back
      ↓
┌─────────────┐
│  Traefik    │ ← 9. Request with cookie
└─────┬───────┘
      │
      │ 10. Verify with Authelia
      ↓
┌─────────────┐
│  Authelia   │ ← 11. Validate session (check Redis)
└─────┬───────┘
      │
      │ 12. Return: Valid
      ↓
┌─────────────┐
│  Traefik    │ ← 13. Forward to service
└─────┬───────┘
      │
      │ 14. Proxy request
      ↓
┌─────────────┐
│  Jellyfin   │ ← 15. Process request
└─────┬───────┘
      │
      │ 16. Return response
      ↓
┌──────────┐
│  User    │ ← 17. Content displayed
│  Browser │
└──────────┘
```

---

## 📦 Service Dependencies

```
                    ┌──────────────┐
                    │   Internet   │
                    └───────┬──────┘
                            │
                    ┌───────▼──────┐
                    │  Cloudflare  │
                    │     DNS      │
                    └───────┬──────┘
                            │
                    ┌───────▼──────┐
                    │   UDM Pro    │
                    │   Firewall   │
                    └───────┬──────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
   ┌────▼─────┐      ┌──────▼─────┐      ┌─────▼────┐
   │ Traefik  │◄─────│  CrowdSec  │      │ Authelia │
   │ (Gateway)│      │ (Security) │      │(SSO+MFA) │
   └────┬─────┘      └────────────┘      └─────┬────┘
        │                                       │
        │           ┌───────────────────────────┘
        │           │
        └───────┬───┴───┬─────────┬──────────┐
                │       │         │          │
           ┌────▼───┐   │    ┌────▼────┐    │
           │Jellyfin│   │    │Next     │    │
           │        │   │    │cloud    │    │
           └────────┘   │    └─────────┘    │
                        │                   │
                   ┌────▼────┐         ┌────▼────┐
                   │ Future  │         │ Future  │
                   │Service 1│         │Service 2│
                   └─────────┘         └─────────┘

Legend:
◄──── = Depends on / Communicates with
```

---

## 🗂️ Directory Structure Tree

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
│   │   │   └── rate-limit.yml      # Rate limiting rules
│   │   ├── letsencrypt/            # SSL certificates
│   │   │   └── acme.json           # Let's Encrypt data
│   │   └── certs/                  # (deprecated)
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
│   ├── cloudflare-ddns.sh         # DNS updater - with cron or systemd (do not remember) jobs to update every 30 mins
│   ├── security-audit.sh          # Security checker
│   └── health-check.sh            # System health
│
├── secrets/                        # Sensitive data (chmod 600)
│   ├── cloudflare_token           # API token
│   └── cloudflare_zone_id         # Zone ID
│
├── backups/                        # Configuration backups
│   ├── phase1-TIMESTAMP/          # Authelia migration backup
│   ├── config-YYYYMMDD/           # Regular config backups
│   └── pre-change-TIMESTAMP/      # Pre-change snapshots
│
├── docs/                  # Documentation
├──     00-foundation/
│       ├── day01-learnings.md
│       ├── day02-networking.md
│       ├── day03-pod-commands.md
│       ├── day03-pods.md
│       ├── day03-pods-vs-containers.md
│       └── podman-cheatsheet.md
├──     10-services/
│       ├── day04-jellyfin-final.md
│       ├── day06-complete.md
│       ├── day06-quadlet-success.md
│       ├── day06-traefik-routing.md
│       ├── day07-yubikey-inventory.md
│       └── quadlets-vs-generated.md
├──     20-operations/
│       ├── 20251023-storage_data_architecture_revised.md
│       ├── DAILY-PROGRESS-2025-10-23.md
│       ├── HOMELAB-ARCHITECTURE-DIAGRAMS.md
│       ├── HOMELAB-ARCHITECTURE-DOCUMENTATION.md
│       ├── NEXTCLOUD-INSTALLATION-GUIDE.md
│       ├── QUICK-REFERENCE.md
│       ├── readme-week02.md
│       ├── storage-layout.md
│       └── TODAYS-ACHIEVEMENTS.md
├──     30-security/
│       └── TINYAUTH-GUIDE.md
├──     90-archive/
│       ├── 20251024-storage_data_architecture-and-2fa-proposal.md
│       ├── 2025-10-24-storage_data_architecture_tailored_addendum.md
│       ├── checklist-week02.md
│       ├── DOMAIN-CHANGE-SUMMARY.md
│       ├── progress.md
│       ├── quick-reference.bak-20251021-172023.md
│       ├── quick-reference.bak-20251021-221915.md
│       ├── quick-reference.md
│       ├── quick-reference-v2.md
│       ├── quick-start-guide-week02.md
│       ├── readme.bak-20251021-172023.md
│       ├── readme.bak-20251021-221915.md
│       ├── readme.md
│       ├── revised-learning-plan.md
│       ├── SCRIPT-EXPLANATION.md
│       ├── summary-revised.md
│       ├── TOMORROW-QUICK-START.md
│       ├── week02-failed-authelia-but-tinyauth-goat.md
│       ├── week02-implementation-plan.md
│       └── week02-security-and-tls.md
└── 99-reports/
        ├── 20251024-configurations-quadlets-and-more.md
        ├── 20251025-storage-architecture-authoritative.md
        ├── 20251025-storage-architecture-authoritative-rev2.md
        ├── authelia-diag-20251020-183321.txt
        ├── failed-authelia-adventures-of-week-02-current-state-of-system.md
        ├── homelab-diagnose-20251021-165859.txt
        ├── latest-summary.md
        ├── pre-letsencrypt-diag-20251022-161247.txt
        ├── script2-week2-authelia-dual-domain.md
        └── system-state-20251022-213400.txt

/home/patriark/.config/containers/systemd/          # quadlet configuration directory
├── auth_services.network           # podman bridge network - currently idle with no services
├── crowdsec.container              # CrowdSec service definition
├── jellyfin.container              # Jellyfin service definition
├── media_services.network          # Media Services podman bridge network
├── reverse_proxy.network           # Reverse Proxy podman bridge network - members: all
├── authelia.container              # Authelia SSO service definition
├── redis-authelia.container        # Redis for Authelia sessions
└── traefik.container               # Traefik service definition
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
                   └────────┬───────┘
                            ↓
                   ┌────────────────┐
                   │ 2. Create Dir  │
                   │ mkdir config/  │
                   │ mkdir data/    │
                   └────────┬───────┘
                            ↓
                   ┌────────────────┐
                   │ 3. Quadlet     │
                   │ Write .container│
                   │ file           │
                   └────────┬───────┘
                            ↓
                   ┌────────────────┐
                   │ 4. Traefik     │
                   │ Add router +   │
                   │ service        │
                   └────────┬───────┘
                            ↓
                   ┌────────────────┐
                   │ 5. Start       │
                   │ systemctl      │
                   │ start service  │
                   └────────┬───────┘
                            ↓
                   ┌────────────────┐
                   │ 6. Test        │
                   │ • Check logs   │
                   │ • Test access  │
                   │ • Verify auth  │
                   └────────┬───────┘
                            ↓
                   ┌────────────────┐
                   │ 7. Document    │
                   │ Update docs    │
                   │ with new svc   │
                   └────────────────┘
```

---

This visual documentation complements the text documentation and provides clear diagrams for understanding the system architecture.
