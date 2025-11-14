# Pattern Selection Guide

**Purpose:** Choose the right deployment pattern for your service

**Last Updated:** 2025-11-14

---

## Quick Decision Tree

```
What type of service are you deploying?

├─ Media Streaming (Jellyfin, Plex, Emby)
│  └─ USE: media-server-stack
│
├─ Web Application with Database (Nextcloud, Wiki.js, Bookstack)
│  └─ USE: web-app-with-database
│
├─ Document Management (Paperless-ngx, Nextcloud)
│  └─ USE: document-management
│
├─ Authentication/SSO (Authelia, Keycloak)
│  └─ USE: authentication-stack
│
├─ Password Manager (Vaultwarden, Bitwarden)
│  └─ USE: password-manager (future: use web-app-with-database)
│
├─ Database (PostgreSQL, MySQL, MariaDB)
│  └─ USE: database-service
│
├─ Cache/Session Storage (Redis, Memcached)
│  └─ USE: cache-service
│
├─ Internal API/Dashboard (No public access)
│  └─ USE: reverse-proxy-backend
│
└─ Monitoring Tool (Exporters, collectors)
   └─ USE: monitoring-exporter
```

---

## Pattern Comparison Matrix

| Pattern | Public Access | Database Needed | Network Complexity | Resource Tier | Typical Use Case |
|---------|---------------|-----------------|-------------------|---------------|------------------|
| media-server-stack | Optional (Authelia) | No | Medium (3 networks) | High (4GB+) | Jellyfin, Plex, Emby |
| web-app-with-database | Yes (Authelia) | Yes | High (app network) | Medium (2GB) | Nextcloud, Wiki.js |
| document-management | Yes (Authelia) | Yes | High (3-service) | High (3GB+) | Paperless-ngx |
| authentication-stack | Yes (public SSO) | Yes (Redis) | Medium | Low (512MB) | Authelia, Keycloak |
| password-manager | Yes (own auth) | No | Low | Low (512MB) | Vaultwarden |
| database-service | No (internal) | N/A | Low (app network) | Medium (1-2GB) | PostgreSQL, MySQL |
| cache-service | No (internal) | N/A | Low (app network) | Low (256-512MB) | Redis, Memcached |
| reverse-proxy-backend | Yes (Authelia required) | Optional | Medium | Low (512MB) | Internal APIs |
| monitoring-exporter | No (metrics only) | No | Low (monitoring) | Minimal (128MB) | Node exporter |

---

## Pattern Selection by Service Type

### Media Services

**Pattern:** `media-server-stack`

**Services:** Jellyfin, Plex, Emby, Tautulli

**Why this pattern:**
- GPU transcoding support
- Large media library volumes
- Optional authentication (can be public)
- Optimized for streaming bandwidth

**Key characteristics:**
- 4GB+ RAM (transcoding intensive)
- Hardware device passthrough (/dev/dri)
- Multiple volume mounts (media libraries)
- systemd-media_services network

**Example deployment:**
```bash
./scripts/deploy-from-pattern.sh \
  --pattern media-server-stack \
  --service-name jellyfin \
  --hostname jellyfin.patriark.org \
  --memory 4G
```

---

### Web Applications

**Pattern:** `web-app-with-database` or `document-management`

**Services:** Nextcloud, Wiki.js, Bookstack, Ghost, WordPress

**Decision point:**
- Simple app + database → `web-app-with-database`
- Complex stack (app + DB + cache + workers) → `document-management`

**web-app-with-database characteristics:**
- 2-container stack (app + database)
- Simple network topology
- Standard authentication pattern
- General-purpose web apps

**document-management characteristics:**
- 3+ container stack (app + DB + Redis + workers)
- OCR/indexing/search capabilities
- Large document storage
- Background job processing

**Example:**
```bash
# Simple web app
./scripts/deploy-from-pattern.sh \
  --pattern web-app-with-database \
  --service-name wiki \
  --hostname wiki.patriark.org \
  --memory 2G

# Complex document system
./scripts/deploy-from-pattern.sh \
  --pattern document-management \
  --service-name paperless \
  --hostname paperless.patriark.org \
  --memory 2G
```

---

### Backend Services (Databases, Caches)

**Pattern:** `database-service` or `cache-service`

**Decision matrix:**

| Criteria | Use database-service | Use cache-service |
|----------|---------------------|-------------------|
| Persistence required | Yes | Optional |
| Data loss acceptable | No | Yes (sessions OK to lose) |
| ACID compliance needed | Yes | No |
| Primary use | Application data | Temporary data, sessions |
| BTRFS NOCOW | **Required** | No |
| Typical size | 5-50GB | 256MB-1GB |

**Database services:** PostgreSQL, MySQL, MariaDB
**Cache services:** Redis, Memcached, KeyDB

**Critical for databases:**
```bash
# MUST set NOCOW before first use
mkdir -p /mnt/btrfs-pool/subvol7-containers/myapp-db/data
chattr +C /mnt/btrfs-pool/subvol7-containers/myapp-db/data
```

---

### Authentication & Security

**Pattern:** `authentication-stack` or `password-manager`

**Decision point:**
- SSO across multiple services → `authentication-stack` (Authelia + Redis)
- Password vault only → `password-manager` (Vaultwarden)

**Authentication-stack characteristics:**
- Protects other services (middleware)
- YubiKey/WebAuthn support
- Session storage (Redis required)
- Central authentication point

**Password-manager characteristics:**
- Self-contained (no dependencies)
- Own authentication system
- Browser extension integration
- Sync across devices

---

### Internal Services

**Pattern:** `reverse-proxy-backend`

**Services:** Internal APIs, admin panels, management interfaces, development tools

**When to use:**
- Service should NOT be directly accessible
- Must go through Traefik reverse proxy
- Requires authentication (Authelia mandatory)
- No public exposure needed

**Security requirements:**
- No `PublishPort` in quadlet (enforced)
- Authelia middleware required (non-negotiable)
- Stricter rate limiting
- Often IP whitelist candidates

**Example:**
```bash
./scripts/deploy-from-pattern.sh \
  --pattern reverse-proxy-backend \
  --service-name admin-panel \
  --hostname admin.patriark.org \
  --memory 512M
```

---

### Monitoring & Observability

**Pattern:** `monitoring-exporter`

**Services:** node_exporter, cadvisor, postgres_exporter, redis_exporter

**Characteristics:**
- Minimal resources (128-256MB)
- systemd-monitoring network only
- Prometheus scrape targets
- No public access
- No authentication needed (internal)

---

## Network Decision Guide

Every pattern defines networks, but understanding why helps customization:

### Network Purposes

| Network | Purpose | Services That Need It |
|---------|---------|----------------------|
| systemd-reverse_proxy | Traefik routing, internet access | All public services |
| systemd-{app}_services | App-specific isolation | App + its database + cache |
| systemd-monitoring | Prometheus scraping | Services exposing metrics |
| systemd-media_services | Media service isolation | Jellyfin, Plex, Sonarr |
| systemd-auth_services | Authelia + Redis | Authelia, Redis |

### Network Ordering Rule

**CRITICAL:** First network gets default route (internet access)

```ini
# Correct (has internet access)
Network=systemd-reverse_proxy.network
Network=systemd-monitoring.network

# Wrong (no internet access)
Network=systemd-monitoring.network
Network=systemd-reverse_proxy.network
```

**Pattern-specific guidance:**
- Public services: `reverse_proxy` MUST be first
- Internal services: Order doesn't matter (no internet needed)
- Databases: Never need reverse_proxy network

---

## Resource Allocation Guidelines

### Memory Recommendations

| Service Category | Minimum | Recommended | High Load |
|-----------------|---------|-------------|-----------|
| Cache (Redis) | 256MB | 512MB | 1GB |
| Database (PostgreSQL) | 1GB | 2GB | 4GB |
| Web app (simple) | 512MB | 1GB | 2GB |
| Media server | 2GB | 4GB | 8GB |
| Document management | 2GB | 3GB | 4GB |
| Authentication | 256MB | 512MB | 1GB |
| Monitoring exporter | 128MB | 256MB | 512MB |

### CPU Priority (CPUWeight)

Patterns set appropriate defaults:
- Databases: 500 (higher priority)
- Caches: 300 (lower priority)
- Web apps: 400 (medium)
- Media: 400 (medium, but spikes during transcode)

---

## Storage Decision Guide

### When to Use BTRFS Pool vs System SSD

**BTRFS Pool (`/mnt/btrfs-pool`):**
- Large data (media, documents, backups)
- Can tolerate slightly slower I/O
- Needs snapshots/compression
- **Required for databases with NOCOW**

**System SSD (`~/containers/data`):**
- Small, frequently accessed data
- Needs fast I/O (Redis, config files)
- Limited space (128GB total)
- Temporary data OK to lose

**Pattern defaults:**
- media-server-stack → BTRFS pool
- database-service → BTRFS pool (with NOCOW)
- cache-service → System SSD
- web-app-with-database → BTRFS pool (data), SSD (config)

---

## Authentication Strategy

### Middleware Tiers

**Strict (admin services):**
```yaml
middleware:
  - crowdsec-bouncer@file
  - rate-limit-auth@file    # 10 req/min
  - authelia@file           # Required
  - security-headers@file
```

**Standard (user services):**
```yaml
middleware:
  - crowdsec-bouncer@file
  - rate-limit-public@file  # 100 req/min
  - authelia@file           # Optional
  - security-headers@file
```

**Public (no auth):**
```yaml
middleware:
  - crowdsec-bouncer@file
  - rate-limit-public@file
  - security-headers@file
```

**Pattern defaults:**
- reverse-proxy-backend → Strict (authelia required)
- web-app-with-database → Standard (authelia optional)
- media-server-stack → Standard (authelia optional, can remove)
- monitoring-exporter → None (internal only)

---

## Common Pattern Modifications

### Removing Authentication

For public services (media servers, blogs):

```bash
# After deploying from pattern, edit quadlet:
nano ~/.config/containers/systemd/jellyfin.container

# Remove authelia middleware from labels:
Label=traefik.http.routers.jellyfin.middlewares=crowdsec-bouncer@file,rate-limit-public@file,security-headers@file

# Apply:
systemctl --user daemon-reload
systemctl --user restart jellyfin.service
```

### Adding GPU Access

For transcoding (Jellyfin, Plex):

```bash
# Edit quadlet:
nano ~/.config/containers/systemd/jellyfin.container

# Add under [Container] section:
AddDevice=/dev/dri/renderD128

# Apply:
systemctl --user daemon-reload
systemctl --user restart jellyfin.service
```

### Changing Memory Limits

```bash
# Edit quadlet:
nano ~/.config/containers/systemd/service.container

# Modify [Service] section:
Memory=4G        # From 2G to 4G
MemoryHigh=3G    # 75% of Memory limit

# Apply:
systemctl --user daemon-reload
systemctl --user restart service.service
```

---

## Anti-Patterns (What NOT to Do)

### ❌ Wrong Pattern Choices

**Don't use media-server-stack for databases**
- Media pattern assumes GPU, large volumes
- Databases need NOCOW, different networks

**Don't use reverse-proxy-backend for public services**
- Pattern enforces strict auth
- Not suitable for public websites

**Don't use web-app-with-database for complex stacks**
- Pattern assumes 2 containers
- Use document-management for 3+ containers

### ❌ Network Mistakes

**Don't put databases on reverse_proxy network**
- Unnecessary exposure
- Use app-specific network only

**Don't forget network order**
- First network = default route
- Public services need reverse_proxy first

### ❌ Resource Mistakes

**Don't skip BTRFS NOCOW for databases**
- Causes severe performance degradation
- Fragmentation leads to slow queries

**Don't use system SSD for large data**
- 128GB fills quickly
- Use BTRFS pool instead

---

## Pattern Evolution Guide

### When Current Patterns Don't Fit

**If no pattern matches exactly:**
1. Choose closest pattern
2. Deploy using pattern
3. Modify quadlet for specific needs
4. Document modifications for future pattern

**Example: Deploying Immich (complex photo management)**

Immich needs: app + postgres + redis + ML + typesense (5 containers)

Current approach:
1. Use `document-management` as base (closest match)
2. Deploy additional containers manually
3. Use app-specific network for all containers
4. Document as candidate for future "photo-management-stack" pattern

### Creating New Patterns

When you deploy the same type of service 2-3 times:
1. Copy best existing pattern as template
2. Modify for new service type
3. Test deployment thoroughly
4. Document in pattern library
5. Update this guide

**Pattern template location:** `.claude/skills/homelab-deployment/patterns/`

---

## Quick Reference: Pattern → Command

```bash
# Media server
./scripts/deploy-from-pattern.sh --pattern media-server-stack --service-name jellyfin --memory 4G

# Web app
./scripts/deploy-from-pattern.sh --pattern web-app-with-database --service-name wiki --memory 2G

# Document management
./scripts/deploy-from-pattern.sh --pattern document-management --service-name paperless --memory 2G

# Authentication
./scripts/deploy-from-pattern.sh --pattern authentication-stack --service-name authelia --memory 512M

# Password manager
./scripts/deploy-from-pattern.sh --pattern password-manager --service-name vaultwarden --memory 512M

# Database
./scripts/deploy-from-pattern.sh --pattern database-service --service-name app-db --memory 2G

# Cache
./scripts/deploy-from-pattern.sh --pattern cache-service --service-name app-redis --memory 512M

# Internal service
./scripts/deploy-from-pattern.sh --pattern reverse-proxy-backend --service-name admin --memory 512M

# Monitoring
./scripts/deploy-from-pattern.sh --pattern monitoring-exporter --service-name node-exporter --memory 128M
```

---

## Next Steps

After selecting a pattern:
1. Review pattern file: `cat .claude/skills/homelab-deployment/patterns/<pattern>.yml`
2. Check deployment notes section
3. Verify prerequisites in validation_checks section
4. Deploy using command above
5. Follow post_deployment checklist

**Related Documentation:**
- Skill usage: `.claude/skills/homelab-deployment/SKILL.md`
- Integration guide: `docs/10-services/guides/skill-integration-guide.md`
- Quick recipes: `.claude/skills/homelab-deployment/COOKBOOK.md`
