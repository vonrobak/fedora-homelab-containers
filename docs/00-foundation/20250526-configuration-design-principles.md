# Configuration Design Principles & Ordering Guide

**Purpose:** Deep understanding of configuration sequencing, design principles, and system customization
**Last Updated:** October 26, 2025
**Audience:** System architects and engineers building secure, maintainable homelabs

---

## Table of Contents

1. [Configuration Sequencing: Does Order Matter?](#configuration-sequencing)
2. [Core Design Principles](#core-design-principles)
3. [Anatomy of Common Configurations](#anatomy-of-common-configurations)
4. [Service Addition Workflow with Design Thinking](#service-addition-workflow)
5. [Network Security & Segmentation Patterns](#network-security--segmentation)
6. [Authentication & Authorization Patterns](#authentication--authorization)
7. [Advanced Customization Techniques](#advanced-customization-techniques)
8. [Real-World Examples](#real-world-examples)

---

## Configuration Sequencing: Does Order Matter?

### TL;DR: **It Depends on the Configuration Type**

```
┌─────────────────────────────────────────────────────────────┐
│  CONFIGURATION ORDERING MATRIX                               │
├─────────────────────────────────────────────────────────────┤
│  Type                  │ Order Matters?  │ Reason            │
├────────────────────────┼─────────────────┼───────────────────┤
│  Quadlet .container    │ Partially       │ Some sections     │
│  Traefik YAML          │ No              │ Declarative       │
│  Systemd .network      │ No              │ Declarative       │
│  Docker Compose        │ Yes (depends_on)│ Startup sequence  │
│  Shell scripts         │ Yes (critical)  │ Sequential exec   │
│  Environment vars      │ Sometimes       │ Override behavior │
│  YAML lists            │ Sometimes       │ Context-dependent │
└────────────────────────┴─────────────────┴───────────────────┘
```

---

## 1. Quadlet Configuration Files (.container, .network)

### Ordering Analysis

**Within a .container file:**

```ini
[Unit]
Description=My Service
After=network-online.target
Wants=network-online.target

[Container]
Image=docker.io/myimage:latest
Network=systemd-reverse_proxy.network
Volume=%h/containers/config/service:/config:Z
Volume=%h/containers/data/service:/data:Z
Environment=KEY=value
Environment=ANOTHER_KEY=value

[Service]
Restart=always
TimeoutStartSec=900

[Install]
WantedBy=default.target
```

**Order Significance:**

1. **[Unit] section** - Order DOES NOT matter within section
   - `After=`, `Before=`, `Wants=`, `Requires=` are all processed together
   - Systemd builds a dependency graph from all units

2. **[Container] section** - Order MATTERS for some directives
   - `Network=` - Can have multiple, evaluated in order
   - `Volume=` - Order doesn't matter (all mounted simultaneously)
   - `Environment=` - **Later definitions override earlier ones**
   - `PublishPort=` - Order doesn't matter
   - `Label=` - Order doesn't matter

3. **[Service] section** - Order DOES NOT matter
   - All directives processed together

4. **[Install] section** - Order DOES NOT matter

### Critical Ordering: Environment Variables

```ini
# ⚠️ ORDER MATTERS HERE
[Container]
Environment=LOG_LEVEL=info     # Set default
Environment=LOG_LEVEL=debug    # This OVERRIDES the previous one!

# Result: LOG_LEVEL=debug
```

**Best Practice:**
```ini
# ✅ BETTER: Single definition
[Container]
Environment=LOG_LEVEL=debug

# Or use EnvironmentFile for complex configs
EnvironmentFile=%h/containers/config/service/env
```

### Critical Ordering: Network Assignment

```ini
# Order matters when multiple networks
[Container]
Network=systemd-reverse_proxy.network   # Primary network
Network=systemd-database.network        # Secondary network

# Container will:
# 1. Get IP on reverse_proxy network
# 2. Get IP on database network
# 3. Default route typically uses FIRST network
```

---

## 2. Traefik Configuration Files

### Static Configuration (traefik.yml)

```yaml
# Order DOES NOT matter - declarative configuration
api:
  dashboard: true
  insecure: false

entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"

providers:
  file:
    directory: /etc/traefik/dynamic
    watch: true

certificatesResolvers:
  letsencrypt:
    acme:
      email: admin@example.com
      storage: /letsencrypt/acme.json
```

**Principle:** Traefik reads entire file, then applies configuration. Order is irrelevant.

### Dynamic Configuration (routers.yml)

```yaml
http:
  routers:
    # Order DOES NOT matter for router definitions
    jellyfin-router:
      rule: "Host(`jellyfin.example.com`)"
      service: jellyfin-service
      middlewares:
        - crowdsec-bouncer
        - rate-limit
        - auth
        - security-headers  # ⚠️ Middleware order DOES matter!
      tls:
        certResolver: letsencrypt

  services:
    jellyfin-service:
      loadBalancer:
        servers:
          - url: "http://jellyfin:8096"
```

**Critical Ordering: Middleware Chain**

```yaml
middlewares:
  - crowdsec-bouncer    # 1. Check IP reputation FIRST
  - rate-limit          # 2. Check rate limits
  - auth                # 3. Authenticate user
  - security-headers    # 4. Add headers to response LAST
```

**Why this order?**
1. **crowdsec-bouncer** - Reject bad IPs before wasting resources
2. **rate-limit** - Prevent abuse before expensive auth checks
3. **auth** - Verify user identity before allowing access
4. **security-headers** - Add headers to final response

**Wrong order example:**
```yaml
middlewares:
  - auth                # ❌ Waste CPU on banned IPs
  - crowdsec-bouncer    # ❌ Check IP AFTER auth
  - security-headers    # ❌ Headers first is illogical
  - rate-limit          # ❌ Rate limit last is ineffective
```

---

## 3. BTRFS and Storage Operations

### Order MATTERS in Storage Setup

```bash
# ✅ CORRECT ORDER: Setup new storage
sudo mkfs.btrfs -L data_pool /dev/sdb /dev/sdc    # 1. Create filesystem
sudo mount /dev/sdb /mnt                          # 2. Mount
sudo btrfs subvolume create /mnt/btrfs-pool       # 3. Create subvols
sudo btrfs quota enable /mnt                      # 4. Enable quotas
sudo btrfs subvolume snapshot -r /mnt/btrfs-pool/subvol1 /mnt/snapshots/backup  # 5. Snapshot

# ❌ WRONG ORDER
sudo btrfs subvolume create /mnt/subvol1          # ❌ Can't create before mount
sudo mount /dev/sdb /mnt                          # ❌ Too late
```

**Principle:** Physical → Logical → Features → Data

---

## Core Design Principles

### Principle 1: Defense in Depth (Layered Security)

**Concept:** Multiple independent security layers, each providing protection

```
┌─────────────────────────────────────────────────┐
│  Security Onion Model                            │
└─────────────────────────────────────────────────┘

    Layer 7: Application Authentication
              ↓ (Tinyauth validates user)
    Layer 6: Rate Limiting
              ↓ (Prevent abuse)
    Layer 5: Threat Intelligence
              ↓ (CrowdSec blocks malicious IPs)
    Layer 4: TLS Encryption
              ↓ (Encrypted communication)
    Layer 3: Security Headers
              ↓ (Browser protections)
    Layer 2: Port Filtering
              ↓ (Firewall rules)
    Layer 1: Network Isolation
              ↓ (Container networks)
    
    Core: Application (Jellyfin, Nextcloud, etc.)
```

**Why this order?**
- **Outer layers fail first** - Quick rejection of bad actors
- **Inner layers more expensive** - Auth and encryption are CPU-intensive
- **Each layer independent** - Compromise of one doesn't compromise all

**Application to Traefik Middleware:**
```yaml
# Middleware chain implements Defense in Depth
middlewares:
  - crowdsec-bouncer    # Outermost: Block known bad actors (cheap)
  - rate-limit          # Second: Prevent abuse (cheap)
  - auth                # Third: Verify identity (expensive)
  - security-headers    # Innermost: Protect browser (cheap)
```

---

### Principle 2: Least Privilege

**Concept:** Grant minimum necessary permissions

**Example: Container User Mapping**
```ini
# ❌ BAD: Running as root
[Container]
Image=myapp:latest
# Implicitly runs as root (UID 0)

# ✅ GOOD: Explicit non-root user
[Container]
Image=myapp:latest
User=1000:1000  # Run as user patriark
```

**Example: Volume Permissions**
```ini
# ❌ BAD: Full read-write everywhere
[Container]
Volume=%h/containers/config:/config:Z

# ✅ BETTER: Read-only where possible
[Container]
Volume=%h/containers/config:/config:ro,Z      # Read-only config
Volume=%h/containers/data:/data:Z             # Read-write data only
Volume=/mnt/btrfs-pool/subvol5-media:/media:ro,Z  # Read-only media
```

**Example: Network Access**
```ini
# ❌ BAD: All services on one network
[Container]
Network=systemd-default.network
# Everything can talk to everything

# ✅ GOOD: Segmented networks
[Container]
Network=systemd-reverse_proxy.network  # Only talk to Traefik
# Cannot directly access database
```

---

### Principle 3: Fail-Safe Defaults

**Concept:** System should fail into a secure state

**Example: Traefik Authentication**
```yaml
# ✅ GOOD: Explicit opt-out of auth
http:
  routers:
    # Public service (explicitly no auth)
    public-api:
      rule: "Host(`api.example.com`) && PathPrefix(`/public`)"
      middlewares:
        - crowdsec-bouncer
        # No auth middleware - intentional
      service: api-service
    
    # Private service (auth required by default)
    admin-panel:
      rule: "Host(`admin.example.com`)"
      middlewares:
        - crowdsec-bouncer
        - rate-limit
        - auth  # ✅ Fail-safe: auth required
      service: admin-service
```

**Example: Systemd Service**
```ini
# ✅ GOOD: Fail-safe restart policy
[Service]
Restart=on-failure      # Restart if crashes
TimeoutStartSec=900     # Fail if doesn't start in 15 min
RestartSec=10           # Wait 10s before restart

# ❌ BAD: Always restart (could restart with bad config)
[Service]
Restart=always  # Dangerous: may restart with security vulnerability
```

---

### Principle 4: Separation of Concerns

**Concept:** Each component has one clear responsibility

**Example: Service Architecture**
```
┌─────────────────────────────────────────────────┐
│  Separation of Concerns in Practice              │
└─────────────────────────────────────────────────┘

Traefik:      Routing, SSL, Load Balancing
              ↓
CrowdSec:     Threat Intelligence, IP Blocking
              ↓
Tinyauth:     Authentication, Session Management
              ↓
Jellyfin:     Media Streaming (business logic only)
```

**Anti-pattern: Mixing Concerns**
```yaml
# ❌ BAD: Authentication in application config
jellyfin-router:
  rule: "Host(`jellyfin.example.com`) && Headers(`X-API-Key`, `secret`)"
  # ❌ Auth logic in routing layer - wrong layer!

# ✅ GOOD: Authentication in auth layer
jellyfin-router:
  rule: "Host(`jellyfin.example.com`)"
  middlewares:
    - auth  # ✅ Auth handled by dedicated service
```

---

### Principle 5: Idempotency

**Concept:** Operation can be applied multiple times with same result

**Example: BTRFS Snapshots**
```bash
# ✅ IDEMPOTENT: Check before create
SNAPSHOT="/mnt/snapshots/backup-$(date +%Y%m%d)"
if [ ! -d "$SNAPSHOT" ]; then
    sudo btrfs subvolume snapshot -r /mnt/data "$SNAPSHOT"
fi

# ❌ NOT IDEMPOTENT: Always creates, fails if exists
sudo btrfs subvolume snapshot -r /mnt/data "$SNAPSHOT"
```

**Example: Quadlet Network Creation**
```ini
# ✅ IDEMPOTENT: Quadlet handles existence check
[Network]
NetworkName=systemd-reverse_proxy
# Systemd creates if doesn't exist, does nothing if exists
```

---

### Principle 6: Configuration as Code

**Concept:** All configuration in version-controlled files

```
┌─────────────────────────────────────────────────┐
│  Configuration Hierarchy                         │
└─────────────────────────────────────────────────┘

Git Repository (source of truth)
    ↓
Declarative Configs (.container, .yml, .conf)
    ↓
Generated Runtime State (containers, networks)
    ↓
Ephemeral Data (logs, temp files)
```

**What to version control:**
```
✅ Quadlet files (.container, .network)
✅ Traefik configs (traefik.yml, dynamic/*.yml)
✅ Service configs (application-specific)
✅ Scripts (automation, backup, maintenance)
✅ Documentation

❌ Secrets (tokens, passwords, keys)
❌ SSL certificates (generated)
❌ Runtime data (logs, databases)
❌ Temporary files
```

---

## Anatomy of Common Configurations

### Quadlet .container File - Detailed Breakdown

```ini
# ═══════════════════════════════════════════════════════════
# SECTION 1: UNIT (Systemd Integration)
# ═══════════════════════════════════════════════════════════
[Unit]
# Human-readable description
Description=Grafana Monitoring Dashboard

# Documentation references (shown in systemctl status)
Documentation=https://grafana.com/docs/

# Dependency: Start AFTER these units are active
After=network-online.target
After=traefik.service
After=prometheus.service

# Soft dependency: Start these if available
Wants=network-online.target

# Hard dependency: Fail if these fail
Requires=prometheus.service

# Start before these units
Before=multi-user.target

# ═══════════════════════════════════════════════════════════
# SECTION 2: CONTAINER (Podman Configuration)
# ═══════════════════════════════════════════════════════════
[Container]
# Container image
Image=docker.io/grafana/grafana:10.2.0

# Container name
ContainerName=grafana

# User mapping (run as patriark inside container)
User=1000:1000

# Network connections (can specify multiple)
Network=systemd-reverse_proxy.network
# Network=systemd-monitoring.network  # If on multiple networks

# Volume mounts
# Format: HOST_PATH:CONTAINER_PATH:OPTIONS
Volume=%h/containers/config/grafana:/etc/grafana:Z
Volume=%h/containers/data/grafana:/var/lib/grafana:Z

# Environment variables
Environment=GF_SERVER_ROOT_URL=https://grafana.patriark.org
Environment=GF_SERVER_DOMAIN=grafana.patriark.org
Environment=GF_SECURITY_ADMIN_USER=admin
Environment=GF_INSTALL_PLUGINS=grafana-clock-panel,grafana-piechart-panel

# Or load from file
# EnvironmentFile=%h/containers/config/grafana/env

# Port publishing (usually avoid with reverse proxy)
# PublishPort=3000:3000  # Uncomment only if needed directly

# Labels for Traefik (if using labels mode)
Label=traefik.enable=true
Label=traefik.http.routers.grafana.rule=Host(`grafana.patriark.org`)

# Health check
HealthCmd=curl -f http://localhost:3000/api/health || exit 1
HealthInterval=30s
HealthTimeout=3s
HealthRetries=3

# Security options
# ReadOnly=true  # Uncomment if app supports read-only root
SecurityLabelType=container_runtime_t

# Resource limits (optional but recommended)
# Memory=2G
# CPUQuota=200%  # 2 CPU cores

# ═══════════════════════════════════════════════════════════
# SECTION 3: SERVICE (Systemd Service Configuration)
# ═══════════════════════════════════════════════════════════
[Service]
# Restart policy
Restart=on-failure
RestartSec=10s

# Timeouts
TimeoutStartSec=300
TimeoutStopSec=70

# ═══════════════════════════════════════════════════════════
# SECTION 4: INSTALL (Systemd Installation)
# ═══════════════════════════════════════════════════════════
[Install]
# Auto-start on boot
WantedBy=default.target
```

**Design Decisions Explained:**

1. **Why `After=prometheus.service`?**
   - Grafana queries Prometheus for data
   - Starting before Prometheus would cause connection errors
   - Systemd ensures correct startup order

2. **Why `Network=systemd-reverse_proxy.network`?**
   - Grafana needs to be accessible via Traefik
   - Traefik is on reverse_proxy network
   - Keeping services on same network enables communication

3. **Why `Volume=%h/containers/config/grafana:/etc/grafana:Z`?**
   - Config persistence across container updates
   - `:Z` = SELinux label (required on Fedora)
   - Split config/data for better backup strategy

4. **Why `Restart=on-failure` not `always`?**
   - `on-failure` = restart only if crashed
   - `always` = restart even if explicitly stopped (dangerous)
   - Fail-safe default: don't restart bad configurations

---

### Traefik Dynamic Configuration - Detailed Breakdown

```yaml
# ═══════════════════════════════════════════════════════════
# ROUTERS: Define how to route incoming requests
# ═══════════════════════════════════════════════════════════
http:
  routers:
    # Router name (arbitrary but descriptive)
    grafana-router:
      # RULE: When this matches, use this router
      # Multiple conditions can be combined with &&
      rule: "Host(`grafana.patriark.org`)"
      # rule: "Host(`grafana.patriark.org`) && PathPrefix(`/api`)"  # More specific
      
      # ENTRYPOINT: Which port/protocol to listen on
      entryPoints:
        - websecure  # HTTPS (443)
      
      # MIDDLEWARE CHAIN: Applied in order (CRITICAL!)
      middlewares:
        - crowdsec-bouncer@file    # 1. Check IP reputation
        - rate-limit-strict@file   # 2. Rate limiting
        - auth-forward@file        # 3. Authentication
        - security-headers@file    # 4. Security headers
      
      # SERVICE: Where to forward request
      service: grafana-service
      
      # TLS: SSL certificate configuration
      tls:
        certResolver: letsencrypt
        # Optional: Specific certificate domain
        domains:
          - main: grafana.patriark.org
      
      # PRIORITY: Higher priority = evaluated first
      # priority: 100  # Optional, default is based on rule specificity

# ═══════════════════════════════════════════════════════════
# SERVICES: Define backend servers
# ═══════════════════════════════════════════════════════════
  services:
    grafana-service:
      loadBalancer:
        servers:
          - url: "http://grafana:3000"  # Container name:port
          # Multiple servers for load balancing:
          # - url: "http://grafana-replica-1:3000"
          # - url: "http://grafana-replica-2:3000"
        
        # Health check (optional)
        healthCheck:
          path: /api/health
          interval: 30s
          timeout: 3s
        
        # Sticky sessions (optional)
        # sticky:
        #   cookie:
        #     name: grafana_session
        #     httpOnly: true
        #     secure: true

# ═══════════════════════════════════════════════════════════
# MIDDLEWARES: Reusable request/response processors
# ═══════════════════════════════════════════════════════════
  middlewares:
    # Authentication middleware
    auth-forward:
      forwardAuth:
        address: http://tinyauth:3000/auth
        trustForwardHeader: true
        authResponseHeaders:
          - X-User
          - X-Email
    
    # Rate limiting middleware
    rate-limit-strict:
      rateLimit:
        average: 100    # Requests per period
        period: 1m      # Time period
        burst: 50       # Burst allowance
    
    # Security headers middleware
    security-headers:
      headers:
        # Security headers
        stsSeconds: 31536000
        stsIncludeSubdomains: true
        stsPreload: true
        forceSTSHeader: true
        
        # XSS Protection
        browserXssFilter: true
        contentTypeNosniff: true
        
        # Frame options
        frameDeny: true
        
        # Custom headers
        customResponseHeaders:
          X-Robots-Tag: "noindex, nofollow"
          Server: ""  # Hide server header
    
    # CORS middleware (if needed)
    cors-headers:
      headers:
        accessControlAllowMethods:
          - GET
          - POST
          - PUT
        accessControlAllowOriginList:
          - "https://app.patriark.org"
        accessControlMaxAge: 100
        addVaryHeader: true
```

**Design Decisions Explained:**

1. **Why middleware order `crowdsec → rate-limit → auth → headers`?**
   ```
   Performance Pyramid:
   
   [Most Expensive]
       Auth (DB lookup, bcrypt)
            ↑
       Rate Limit (memory check)
            ↑
       CrowdSec (cache lookup)
   [Least Expensive]
   
   Principle: Fail fast at cheapest layer
   ```

2. **Why `entryPoints: [websecure]` not `web`?**
   - `web` = HTTP (port 80)
   - `websecure` = HTTPS (port 443)
   - Security principle: Always use encryption
   - HTTP should redirect to HTTPS (separate router)

3. **Why `service: grafana-service` references container name `grafana`?**
   - Containers on same Podman network resolve by name
   - DNS: `grafana` → container IP
   - Alternative: explicit IP (less maintainable)

---

## Service Addition Workflow with Design Thinking

### Phase 1: Planning (CRITICAL - Don't Skip!)

```
┌─────────────────────────────────────────────────┐
│  Pre-Implementation Checklist                    │
└─────────────────────────────────────────────────┘

□ What problem does this service solve?
□ What are the security implications?
□ What data does it need to access?
□ What services does it depend on?
□ What services depend on it?
□ What network segment should it be on?
□ Does it need authentication?
□ What are the resource requirements?
□ What is the backup strategy?
□ What is the update strategy?
□ What are the failure modes?
```

### Example: Adding Nextcloud

#### 1. Service Analysis

```
Service: Nextcloud
Purpose: File sync, calendar, contacts

Dependencies:
  ├─ PostgreSQL (database)
  ├─ Redis (caching)
  ├─ Traefik (reverse proxy)
  └─ Tinyauth (authentication)

Data Requirements:
  ├─ Config: ~/containers/config/nextcloud
  ├─ App data: ~/containers/data/nextcloud
  ├─ User files: /mnt/btrfs-pool/subvol1-docs
  ├─ Photos: /mnt/btrfs-pool/subvol3-photos
  └─ Database: ~/containers/db/postgresql (NOCOW)

Security Requirements:
  ├─ Authentication: Yes (Tinyauth integration)
  ├─ Network: Needs to talk to PostgreSQL and Redis
  └─ External access: Yes (via Traefik)

Resource Requirements:
  ├─ Memory: 1-2 GB
  ├─ CPU: Moderate
  └─ Storage: Large (user files)
```

#### 2. Network Design Decision

```
┌─────────────────────────────────────────────────┐
│  Network Segmentation Design                     │
└─────────────────────────────────────────────────┘

OPTION 1: Single Network (Simple)
─────────────────────────────────
reverse_proxy network:
  ├─ Traefik
  ├─ Nextcloud
  ├─ PostgreSQL
  └─ Redis

✅ Pros: Simple configuration
❌ Cons: Nextcloud can talk directly to all services


OPTION 2: Multiple Networks (Secure) ⭐ RECOMMENDED
──────────────────────────────────────
reverse_proxy network:
  ├─ Traefik
  └─ Nextcloud

database network:
  ├─ Nextcloud
  ├─ PostgreSQL
  └─ Redis

✅ Pros: 
  - Traefik cannot access database directly
  - PostgreSQL only accessible to Nextcloud
  - Better isolation

❌ Cons: 
  - Slightly more complex
  - Need to manage multiple networks
```

**Decision: Use Option 2 (Defense in Depth principle)**

#### 3. Create Network Configuration

```ini
# File: ~/.config/containers/systemd/database.network
[Network]
NetworkName=systemd-database
Label=app=homelab
Label=network=database
Subnet=10.89.3.0/24
# Gateway=10.89.3.1  # Optional, auto-assigned
```

```bash
# Reload and create
systemctl --user daemon-reload
# Network creates automatically when referenced
```

#### 4. Create Database Service (PostgreSQL)

```ini
# File: ~/.config/containers/systemd/postgresql.container
[Unit]
Description=PostgreSQL Database for Nextcloud
Documentation=https://www.postgresql.org/docs/
After=network-online.target
Wants=network-online.target

[Container]
Image=docker.io/postgres:16-alpine
ContainerName=postgresql
User=999:999  # postgres user

# NETWORK DESIGN: Only on database network
Network=systemd-database.network

# STORAGE DESIGN: Use NOCOW for database
# Create directory first: mkdir -p ~/containers/db/postgresql
# Set NOCOW: chattr +C ~/containers/db/postgresql
Volume=%h/containers/db/postgresql:/var/lib/postgresql/data:Z

# SECURITY: Environment variables
Environment=POSTGRES_DB=nextcloud
Environment=POSTGRES_USER=nextcloud
EnvironmentFile=%h/containers/secrets/postgresql.env
# postgresql.env contains: POSTGRES_PASSWORD=<random-password>

# RELIABILITY: Health check
HealthCmd=pg_isready -U nextcloud
HealthInterval=30s
HealthTimeout=3s
HealthRetries=3

[Service]
Restart=on-failure
TimeoutStartSec=120

[Install]
WantedBy=default.target
```

**Design Decisions:**
- `Network=systemd-database.network` ONLY - Not on reverse_proxy
- `chattr +C` for database files - BTRFS copy-on-write disabled
- Health check ensures database is ready
- Secrets in separate file

#### 5. Create Cache Service (Redis)

```ini
# File: ~/.config/containers/systemd/redis.container
[Unit]
Description=Redis Cache for Nextcloud
Documentation=https://redis.io/documentation
After=network-online.target

[Container]
Image=docker.io/redis:7-alpine
ContainerName=redis
User=999:999

# NETWORK DESIGN: Only on database network
Network=systemd-database.network

# STORAGE DESIGN: NOCOW for Redis data
Volume=%h/containers/db/redis:/data:Z

# CONFIGURATION: Redis config file
Volume=%h/containers/config/redis/redis.conf:/etc/redis/redis.conf:ro,Z

# SECURITY: Require password
Environment=REDIS_PASSWORD_FILE=/run/secrets/redis_password

# RELIABILITY
HealthCmd=redis-cli ping
HealthInterval=30s

[Service]
Restart=on-failure

[Install]
WantedBy=default.target
```

#### 6. Create Nextcloud Service

```ini
# File: ~/.config/containers/systemd/nextcloud.container
[Unit]
Description=Nextcloud File Sync and Share
Documentation=https://docs.nextcloud.com/
After=network-online.target
After=postgresql.service
After=redis.service
Requires=postgresql.service
Requires=redis.service

[Container]
Image=docker.io/nextcloud:28-apache
ContainerName=nextcloud
User=33:33  # www-data

# NETWORK DESIGN: On BOTH networks
Network=systemd-reverse_proxy.network  # For Traefik access
Network=systemd-database.network       # For PostgreSQL/Redis access

# STORAGE DESIGN: Multiple volumes for different purposes
Volume=%h/containers/config/nextcloud:/var/www/html:Z              # App
Volume=%h/containers/data/nextcloud:/var/www/html/data:Z           # Metadata
Volume=/mnt/btrfs-pool/subvol1-docs:/mnt/docs:Z                    # User docs
Volume=/mnt/btrfs-pool/subvol3-photos:/mnt/photos:Z                # Photos

# ENVIRONMENT: Database connection
Environment=POSTGRES_HOST=postgresql
Environment=POSTGRES_DB=nextcloud
Environment=POSTGRES_USER=nextcloud
EnvironmentFile=%h/containers/secrets/nextcloud.env

# Redis configuration
Environment=REDIS_HOST=redis
Environment=REDIS_HOST_PASSWORD_FILE=/run/secrets/redis_password

# Nextcloud configuration
Environment=NEXTCLOUD_TRUSTED_DOMAINS=nextcloud.patriark.org
Environment=TRUSTED_PROXIES=10.89.2.0/24
Environment=OVERWRITEPROTOCOL=https
Environment=OVERWRITECLIURL=https://nextcloud.patriark.org

[Service]
Restart=on-failure
TimeoutStartSec=600  # Nextcloud can take time to start

[Install]
WantedBy=default.target
```

**Critical Design Decisions:**

1. **Dual Network Assignment:**
   ```ini
   Network=systemd-reverse_proxy.network  # Traefik can reach Nextcloud
   Network=systemd-database.network       # Nextcloud can reach PostgreSQL
   ```
   
   Result:
   ```
   Traefik → Nextcloud → PostgreSQL ✅
   Traefik → PostgreSQL ❌ (Not on same network)
   ```

2. **Volume Mapping Strategy:**
   ```
   App Code:    ~/containers/config/nextcloud    (SSD, fast)
   Metadata:    ~/containers/data/nextcloud      (SSD, fast)
   User Files:  /mnt/btrfs-pool/subvol1-docs     (HDD, large)
   Photos:      /mnt/btrfs-pool/subvol3-photos   (HDD, large)
   ```

3. **Trusted Proxies:**
   ```ini
   Environment=TRUSTED_PROXIES=10.89.2.0/24
   ```
   Nextcloud needs to know Traefik is trusted to handle X-Forwarded-For headers

#### 7. Create Traefik Routing

```yaml
# File: ~/containers/config/traefik/dynamic/routers.yml
http:
  routers:
    nextcloud-router:
      rule: "Host(`nextcloud.patriark.org`)"
      entryPoints:
        - websecure
      middlewares:
        - crowdsec-bouncer@file
        - rate-limit@file
        - auth-forward@file
        - nextcloud-headers@file  # Nextcloud-specific headers
      service: nextcloud-service
      tls:
        certResolver: letsencrypt
  
  services:
    nextcloud-service:
      loadBalancer:
        servers:
          - url: "http://nextcloud:80"
  
  middlewares:
    nextcloud-headers:
      headers:
        customRequestHeaders:
          X-Forwarded-Proto: "https"
        customResponseHeaders:
          Strict-Transport-Security: "max-age=31536000"
```

#### 8. Start Services in Correct Order

```bash
# 1. Create database directory with NOCOW
mkdir -p ~/containers/db/postgresql
sudo chattr +C ~/containers/db/postgresql
mkdir -p ~/containers/db/redis
sudo chattr +C ~/containers/db/redis

# 2. Create secrets
mkdir -p ~/containers/secrets
echo "POSTGRES_PASSWORD=$(openssl rand -base64 32)" > ~/containers/secrets/postgresql.env
echo "$(openssl rand -base64 32)" > ~/containers/secrets/redis_password
chmod 600 ~/containers/secrets/*

# 3. Reload systemd
systemctl --user daemon-reload

# 4. Start in dependency order
systemctl --user start postgresql.service
systemctl --user start redis.service
# Wait a few seconds for databases to be ready
sleep 5
systemctl --user start nextcloud.service

# 5. Verify
podman ps
podman logs nextcloud
```

---

## Network Security & Segmentation Patterns

### Pattern 1: Reverse Proxy Isolation

```
GOAL: Services only accessible via reverse proxy

┌────────────────────────────────────────┐
│           Internet                      │
└──────────────┬─────────────────────────┘
               │
               │ HTTPS (443)
               ↓
┌──────────────────────────────────────────┐
│      reverse_proxy network               │
│  ┌─────────┐     ┌──────────┐           │
│  │ Traefik │────→│ Nextcloud│           │
│  └─────────┘     └──────────┘           │
└──────────────────────────────────────────┘
                      │
                      │ Internal
                      ↓
┌──────────────────────────────────────────┐
│       database network                   │
│  ┌──────────┐     ┌──────┐              │
│  │PostgreSQL│     │ Redis│              │
│  └──────────┘     └──────┘              │
└──────────────────────────────────────────┘

RULES:
✅ Internet → Traefik
✅ Traefik → Nextcloud
✅ Nextcloud → PostgreSQL
✅ Nextcloud → Redis
❌ Internet → Nextcloud (not on reverse_proxy only from Traefik)
❌ Traefik → PostgreSQL (not on database network)
❌ Internet → PostgreSQL (isolated)
```

**Implementation:**
```ini
# Traefik: Only on reverse_proxy
[Container]
Network=systemd-reverse_proxy.network

# Nextcloud: On BOTH networks
[Container]
Network=systemd-reverse_proxy.network
Network=systemd-database.network

# PostgreSQL: Only on database network
[Container]
Network=systemd-database.network
```

### Pattern 2: Service-Specific Networks

```
ADVANCED: Multiple specialized networks

┌────────────────────────────────────────┐
│      reverse_proxy network (public)    │
│  ┌─────────┐                           │
│  │ Traefik │                           │
│  └────┬────┘                           │
└───────┼────────────────────────────────┘
        │
        ├───────────────┬────────────────┐
        │               │                │
┌───────▼─────┐  ┌──────▼──────┐  ┌─────▼──────┐
│media network│  │app network  │  │auth network│
│ ┌─────────┐ │  │┌──────────┐ │  │┌──────────┐│
│ │ Jellyfin│ │  ││Nextcloud │ │  ││ Tinyauth ││
│ └─────────┘ │  │└──────────┘ │  │└──────────┘│
│             │  │      │       │  │            │
│             │  │┌─────▼──────┐│  │            │
│             │  ││PostgreSQL  ││  │            │
│             │  │└────────────┘│  │            │
└─────────────┘  └──────────────┘  └────────────┘

BENEFIT: Lateral movement prevention
```

### Pattern 3: Authentication Network Isolation

```
GOAL: Isolate authentication services

┌────────────────────────────────────────┐
│      reverse_proxy network             │
│  ┌─────────┐                           │
│  │ Traefik │                           │
│  └────┬────┘                           │
└───────┼────────────────────────────────┘
        │
        ├──────────────┬────────────────┐
        │              │                │
┌───────▼────────┐ ┌───▼───────┐ ┌─────▼──────┐
│ Services       │ │  Tinyauth │ │  Keycloak  │
│ (protected)    │ │  (auth)   │ │  (future)  │
└────────────────┘ └───────────┘ └────────────┘
                        │
                  ┌─────▼──────┐
                  │Auth Database│
                  │ (isolated) │
                  └────────────┘

PRINCIPLE: Auth infrastructure isolated from apps
```

---

## Authentication & Authorization Patterns

### Pattern 1: Forward Authentication (Current)

```
┌──────────────────────────────────────────────────────┐
│  Forward Auth Flow                                    │
└──────────────────────────────────────────────────────┘

1. User → https://jellyfin.patriark.org
                │
                ↓
2. Traefik checks middleware chain
                │
                ├─ CrowdSec: IP OK?
                ├─ Rate Limit: Under limit?
                ↓
3. Forward Auth middleware
                │
                ↓ HTTP request to auth service
4. Tinyauth: http://tinyauth:3000/auth
                │
                ├─ Has valid session cookie?
                │   YES → Return 200 OK + headers
                │   NO  → Return 302 Redirect to login
                ↓
5. Traefik receives auth response
                │
                ├─ 200 OK: Forward to Jellyfin
                └─ 302 Redirect: Send user to auth.patriark.org
```

**Traefik Configuration:**
```yaml
middlewares:
  auth-forward:
    forwardAuth:
      address: http://tinyauth:3000/auth
      authResponseHeaders:
        - X-User
        - X-Email
```

**Why this pattern?**
- Centralized authentication
- Services don't need auth code
- Easy to add 2FA to one place
- Consistent across all services

### Pattern 2: Service-Specific Authentication

```
ALTERNATIVE: Each service has own auth

❌ Problems with this approach:
   - Different passwords per service
   - Multiple login screens
   - No single sign-on (SSO)
   - Harder to add 2FA
   - More attack surface

✅ Forward auth solves these
```

### Pattern 3: OAuth2/OIDC (Future Enhancement)

```
ADVANCED: OAuth2 Provider (Keycloak, Authentik)

┌────────────────────────────────────┐
│           Keycloak                  │
│      (Identity Provider)            │
│  - User management                  │
│  - 2FA (TOTP, WebAuthn)            │
│  - Social login (Google, GitHub)    │
│  - Fine-grained permissions         │
└──────────────┬─────────────────────┘
               │ OAuth2/OIDC
               ↓
┌──────────────────────────────────────┐
│         Traefik + OAuth2 Proxy       │
└──────────────┬───────────────────────┘
               │
        ┌──────┴───────┬───────────┐
        ↓              ↓           ↓
    Nextcloud     Grafana    Custom App
  (OIDC client) (OIDC)    (OAuth2)

BENEFITS:
✅ Centralized user management
✅ Standard protocols
✅ Advanced features (groups, roles)
✅ Third-party service integration
```

---

## Advanced Customization Techniques

### Technique 1: Conditional Configuration with Labels

```yaml
# Traefik can route based on labels in container
[Container]
Label=traefik.enable=true
Label=traefik.http.routers.myapp.rule=Host(`app.patriark.org`)
Label=traefik.http.routers.myapp.middlewares=auth@file,rate-limit@file
Label=traefik.http.services.myapp.loadbalancer.server.port=8080

# Benefit: Configuration lives with service definition
```

### Technique 2: Environment-Specific Configs

```bash
# Use environment variables for flexibility
[Container]
EnvironmentFile=%h/containers/config/app/env.${ENVIRONMENT}

# env.prod
LOG_LEVEL=warn
DEBUG=false

# env.dev
LOG_LEVEL=debug
DEBUG=true
```

### Technique 3: Layered Volume Mounts

```ini
# Read-only base config, writable overrides
[Container]
Volume=%h/containers/config/app/base.yml:/app/config/base.yml:ro,Z
Volume=%h/containers/config/app/custom.yml:/app/config/custom.yml:Z

# App reads base first, then applies custom overrides
```

### Technique 4: Init Containers Pattern

```ini
# Main service depends on init completing
[Unit]
After=app-init.service
Requires=app-init.service

# app-init.service runs once to setup
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/podman run --rm \
  -v %h/containers/data/app:/data:Z \
  alpine sh -c "chmod -R 755 /data && chown -R 1000:1000 /data"
```

---

## Real-World Examples

### Example 1: Adding Grafana with Complete Thought Process

**Step 1: Define Requirements**
```
Purpose: Monitoring dashboard
Dependencies: Prometheus (data source)
Data: Dashboards, settings (small, SSD)
Network: Needs Traefik access, may need Prometheus access
Auth: Yes, via Tinyauth
Resources: Low (< 512 MB)
```

**Step 2: Network Design**
```
OPTIONS:
A) Single network (reverse_proxy) - Grafana + Prometheus + Traefik
   ✅ Simple
   ❌ Grafana can access all services on network

B) Dual network (reverse_proxy + monitoring)
   ✅ Better isolation
   ✅ Monitoring services together
   ❌ More complex

DECISION: Use Option B (monitoring network)
REASON: Prepare for future metrics exporters
```

**Step 3: Create Monitoring Network**
```ini
# ~/.config/containers/systemd/monitoring.network
[Network]
NetworkName=systemd-monitoring
Subnet=10.89.4.0/24
```

**Step 4: Update Prometheus (if needed)**
```ini
# Add monitoring network to Prometheus
[Container]
Network=systemd-monitoring.network
```

**Step 5: Create Grafana Service**
```ini
# ~/.config/containers/systemd/grafana.container
[Unit]
Description=Grafana Monitoring Dashboard
After=prometheus.service
Wants=prometheus.service

[Container]
Image=docker.io/grafana/grafana:10.2.0
ContainerName=grafana
User=472:472  # grafana user

# DUAL NETWORK: reverse_proxy for Traefik, monitoring for Prometheus
Network=systemd-reverse_proxy.network
Network=systemd-monitoring.network

Volume=%h/containers/config/grafana:/etc/grafana:Z
Volume=%h/containers/data/grafana:/var/lib/grafana:Z

Environment=GF_SERVER_ROOT_URL=https://grafana.patriark.org
Environment=GF_SERVER_DOMAIN=grafana.patriark.org
Environment=GF_AUTH_PROXY_ENABLED=true
Environment=GF_AUTH_PROXY_HEADER_NAME=X-User
Environment=GF_AUTH_PROXY_HEADER_PROPERTY=username
Environment=GF_AUTH_PROXY_AUTO_SIGN_UP=true

[Service]
Restart=on-failure

[Install]
WantedBy=default.target
```

**Design Insights:**
1. `Network=systemd-reverse_proxy.network` - Traefik can route to Grafana
2. `Network=systemd-monitoring.network` - Grafana can query Prometheus
3. `GF_AUTH_PROXY_*` - Integrate with Tinyauth forward auth
4. `User=472:472` - Non-root user (security)

**Step 6: Traefik Routing**
```yaml
http:
  routers:
    grafana-router:
      rule: "Host(`grafana.patriark.org`)"
      middlewares:
        - crowdsec-bouncer@file
        - rate-limit@file
        - auth-forward@file
        - grafana-headers@file
      service: grafana-service
      tls:
        certResolver: letsencrypt
  
  services:
    grafana-service:
      loadBalancer:
        servers:
          - url: "http://grafana:3000"
  
  middlewares:
    grafana-headers:
      headers:
        customRequestHeaders:
          X-Forwarded-Proto: https
```

**Step 7: Deploy**
```bash
# 1. Create directories
mkdir -p ~/containers/config/grafana
mkdir -p ~/containers/data/grafana
chown -R 472:472 ~/containers/data/grafana

# 2. Reload
systemctl --user daemon-reload

# 3. Start
systemctl --user start grafana.service

# 4. Verify
podman logs grafana
curl -I https://grafana.patriark.org

# 5. Configure Prometheus data source in Grafana UI
# URL: http://prometheus:9090
```

---

### Example 2: Adding Homepage Dashboard

**Requirements Analysis:**
```
Purpose: Service dashboard / homepage
Dependencies: None (standalone)
Data: Minimal config (YAML files)
Network: Needs Traefik access
Auth: Yes (or no for public dashboard)
Resources: Minimal
```

**Decision: Make it Public (No Auth)**
```
REASONING:
- Dashboard shows service status
- No sensitive information
- Easier for quick checks
- Still protected by CrowdSec + rate limiting
```

**Implementation:**
```ini
# ~/.config/containers/systemd/homepage.container
[Unit]
Description=Homepage Service Dashboard

[Container]
Image=ghcr.io/gethomepage/homepage:latest
ContainerName=homepage

# SINGLE NETWORK: Only needs Traefik
Network=systemd-reverse_proxy.network

Volume=%h/containers/config/homepage:/app/config:Z

[Service]
Restart=on-failure

[Install]
WantedBy=default.target
```

**Traefik Routing (No Auth):**
```yaml
http:
  routers:
    homepage-router:
      rule: "Host(`home.patriark.org`)"
      middlewares:
        - crowdsec-bouncer@file  # Still check bad IPs
        - rate-limit@file         # Still rate limit
        # NO AUTH - intentionally public
      service: homepage-service
      tls:
        certResolver: letsencrypt
```

**Configuration:**
```yaml
# ~/containers/config/homepage/services.yaml
---
- Infrastructure:
    - Traefik:
        href: https://traefik.patriark.org
        description: Reverse Proxy
        server: local
        container: traefik
        
- Media:
    - Jellyfin:
        href: https://jellyfin.patriark.org
        description: Media Server
        server: local
        container: jellyfin
```

---

## Summary: Key Principles to Remember

### 1. **Ordering Matters When:**
- Middleware chains (most important!)
- Environment variable overrides
- Multiple network assignments (default route)
- Systemd dependencies (After/Before)
- Storage setup operations

### 2. **Ordering Doesn't Matter When:**
- Declarative configs (Traefik YAML, Quadlet sections)
- Volume mounts (all mounted simultaneously)
- Labels
- Most Quadlet directives within sections

### 3. **Always Consider:**
- Defense in depth
- Least privilege
- Fail-safe defaults
- Separation of concerns
- Network segmentation
- Authentication layer placement

### 4. **When Adding Services, Ask:**
1. What problem does this solve?
2. What are the security implications?
3. What network should it be on?
4. What services can it talk to?
5. Does it need authentication?
6. Where should data be stored?
7. What are the failure modes?

### 5. **Best Practices:**
- Start simple, add complexity as needed
- Use multiple networks for isolation
- Always apply auth unless intentionally public
- Place cheap security checks before expensive ones
- Version control all configuration
- Document design decisions
- Test failure scenarios

---

## Next Steps for Your Homelab

### Immediate (Documentation Phase)
1. Review your current service configurations
2. Identify any ordering issues
3. Plan network segmentation improvements
4. Document design decisions

### Short-term (Monitoring Phase)
1. Apply these principles to monitoring stack
2. Create dedicated monitoring network
3. Implement proper middleware ordering

### Medium-term (Service Expansion)
1. Use these patterns for Nextcloud
2. Implement database network
3. Review and improve auth integration

### Long-term (Advanced)
1. Migrate to OAuth2/OIDC
2. Implement advanced network policies
3. Add service mesh (if needed)

---

**Document Version:** 1.0
**Created:** October 26, 2025
**Purpose:** Comprehensive guide to configuration design principles and ordering
