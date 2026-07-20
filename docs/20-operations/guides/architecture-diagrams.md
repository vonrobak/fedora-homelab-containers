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
                    │   Cloudflare   │ patriark.org → 203.0.113.42
                    │   DNS Server   │
                    └────────────────┘
                             │
                             │ HTTPS Request
                             ↓
                ┌────────────────────────┐
                │   ISP / Public IP      │
                │   203.0.113.42         │
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
     └─ Public IP: 203.0.113.42 (Dynamic)
```

---

## 📊 Data Flow: User Request

```
1. User enters URL
   https://jellyfin.patriark.org
   
2. DNS Resolution
   Browser → Pi-hole (192.168.1.69) → 192.168.1.70 (LAN)
   Browser → Cloudflare → 203.0.113.42 (WAN)
   
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
├── quadlets/                        # Systemd quadlet unit files (37 containers,
│   │                                #  12 .network files) — the deployment layer
│   ├── <service>.container          # One quadlet per container, digest-pinned images
│   └── <name>.network               # Podman network definitions
│
├── config/                          # Service configurations (one dir per service)
│   ├── traefik/
│   │   ├── traefik.yml              # Static configuration
│   │   └── dynamic/                 # Dynamic config (auto-reloads)
│   │       ├── routers.yml          # ALL routing rules (ADR-016: never in labels)
│   │       ├── middleware.yml       # CrowdSec, rate limiting, auth, headers
│   │       └── tls.yml              # TLS options
│   ├── prometheus/ | grafana/ | loki/ | alertmanager/   # Monitoring stack
│   ├── supply-chain/                # Bake policy, egress baselines (ADR-030/036/039)
│   └── <service>/                   # Per-service config dirs
│
├── scripts/                         # Automation (85 scripts — see automation-reference.md)
│
├── data/                            # Persistent service data (bind mounts, :Z labels)
│
├── docs/                            # Public documentation (this tree — see docs/README.md)
│   ├── 00-40 sections               # Guides + ADRs + runbooks
│   └── AUTO-*.md                    # Auto-generated daily views
│
├── builds/                          # Local image builds (Tier 2, digest-pinned bases)
├── backups/  cache/  systemd/       # Operational directories
└── secrets/                         # Gitignored (runtime secrets come from OpenBao, ADR-041)
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
