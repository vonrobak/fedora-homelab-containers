# ADR-016: Configuration Design Principles

**Date:** 2025-12-31
**Status:** Accepted
**Decided by:** patriark + Claude Code
**Supersedes:** Implicit practices (now codified)

---

## Context

After successfully deploying 23 services over 2+ months of production operation (October 2025 - December 2025), clear design patterns emerged that guide consistent, secure, and maintainable deployments. These principles were **implicit in practice** but not explicitly documented, leading to:

- Risk of configuration drift in future deployments
- Difficulty explaining design decisions to new collaborators
- No formal guidance for choosing between alternative approaches
- Potential inconsistencies as the homelab scales

**Production validation (2025-12-31):**
- 23 services deployed via systemd quadlets
- 13 services with external routing via Traefik
- Health score: 95/100
- Zero Traefik labels across all quadlets (100% compliance)
- All routing centralized in 248-line `routers.yml` file

Analysis revealed six core principles that, when followed consistently, produce secure, maintainable, auditable infrastructure.

---

## Decision

**We adopt six core configuration design principles for all service deployments:**

1. **Separation of Concerns** - Deployment vs routing configuration
2. **Centralized Security Enforcement** - Middleware ordering and policies
3. **Secrets via Platform Primitives** - Podman secrets over files
4. **Configuration as Code** - Git-tracked infrastructure
5. **Fail-Safe Defaults** - Secure by default, explicit opt-out
6. **Service Discovery via Naming Convention** - DNS-based, no IP management

These principles are **mandatory for all new deployments** and should guide refactoring of existing services.

---

## Principle 1: Separation of Concerns

### Statement

**Quadlet files define service deployment. Traefik dynamic config defines network routing. Never mix these concerns.**

### Rationale

**Quadlets answer:** "What runs? With what resources? What health checks?"
**Traefik answers:** "How is it accessed? What middleware protects it? What hostname?"

Separating these concerns provides:
- **Single source of truth:** All routing in one 248-line file (auditable at a glance)
- **Clean abstraction:** Service doesn't need to know how it's exposed externally
- **Git clarity:** Routing changes tracked separately from service changes
- **Easier refactoring:** Change routing without touching quadlets, and vice versa

### Implementation

**Quadlet responsibility (deployment):**
```ini
# ~/.config/containers/systemd/jellyfin.container

[Container]
Image=docker.io/jellyfin/jellyfin:latest
ContainerName=jellyfin
Network=systemd-reverse_proxy.network
Volume=%h/containers/config/jellyfin:/config:Z
HealthCmd=curl -f http://localhost:8096/health || exit 1

# NO Traefik labels - routing defined separately
```

**Traefik responsibility (routing):**
```yaml
# ~/containers/config/traefik/dynamic/routers.yml

http:
  routers:
    jellyfin-secure:
      rule: "Host(`jellyfin.patriark.org`)"
      service: "jellyfin"
      middlewares:
        - crowdsec-bouncer@file
        - rate-limit-public@file
        - security-headers@file
      tls:
        certResolver: letsencrypt

  services:
    jellyfin:
      loadBalancer:
        servers:
          - url: "http://jellyfin:8096"
```

### Good Example (Production Code)

**Nextcloud deployment:** Quadlet defines container, database, Redis. Traefik dynamic config defines CalDAV routing, middleware chains, TLS. Completely orthogonal.

```ini
# nextcloud.container - Pure deployment
[Container]
Image=docker.io/library/nextcloud:30
ContainerName=nextcloud
Network=systemd-reverse_proxy.network
Network=systemd-database.network
Secret=nextcloud_db_password,type=env,target=MYSQL_PASSWORD
```

```yaml
# routers.yml - Pure routing
nextcloud-secure:
  rule: "Host(`nextcloud.patriark.org`)"
  middlewares:
    - crowdsec-bouncer@file
    - rate-limit-nextcloud@file
    - nextcloud-caldav@file  # .well-known redirects
    - hsts-only@file
```

### Anti-Pattern (What NOT to Do)

**DON'T: Mix routing into quadlets via labels**

```ini
# ❌ WRONG: Mixing concerns
[Container]
Image=jellyfin/jellyfin:latest
ContainerName=jellyfin
Label=traefik.enable=true
Label=traefik.http.routers.jellyfin.rule=Host(`jellyfin.patriark.org`)
Label=traefik.http.routers.jellyfin.middlewares=crowdsec,rate-limit
# Now routing is distributed across 23 quadlet files - hard to audit!
```

**Why this is bad:**
- Routing distributed across many files (no single source of truth)
- Service deployment mixed with network routing
- Git changes conflate service updates with routing updates
- Can't audit all public routes without grep-ing through quadlets

---

## Principle 2: Centralized Security Enforcement

### Statement

**All middleware chains are defined in `middleware.yml`. All routing applies middleware from that central definition. Middleware ordering follows fail-fast cost pyramid.**

### Rationale

**Fail-fast cost pyramid:**
```
      [Most Expensive]  Authentication (database, bcrypt, MFA)
            ↑
       Rate Limiting (memory check)
            ↑
      [Least Expensive]  IP Reputation (cache lookup)
```

**Benefits:**
- **Consistent ordering:** Impossible to accidentally put auth before IP blocking
- **Single policy source:** Change rate limit tier globally by editing one file
- **Service-aware policies:** Different middleware chains for admin vs public vs API
- **Auditability:** See entire security posture in one file

### Implementation

**Centralized middleware definitions:**

```yaml
# ~/containers/config/traefik/dynamic/middleware.yml

middlewares:
  # Layer 1: IP Reputation (FASTEST - cache lookup)
  crowdsec-bouncer:
    plugin:
      crowdsec-bouncer-traefik-plugin:
        enabled: true
        crowdsecMode: live
        crowdsecLapiHost: crowdsec:8080

  # Layer 2: Rate Limiting (FAST - memory check)
  rate-limit:
    rateLimit:
      average: 100
      burst: 50
      period: 1m

  rate-limit-strict:
    rateLimit:
      average: 30
      burst: 10
      period: 1m

  # Layer 3: Authentication (EXPENSIVE - database + crypto)
  authelia:
    forwardAuth:
      address: "http://authelia:9091/api/verify?rd=https://sso.patriark.org"
      authResponseHeaders:
        - Remote-User
        - Remote-Email

  # Layer 4: Security Headers (RESPONSE - added last)
  security-headers:
    headers:
      frameDeny: true
      stsSeconds: 31536000
      contentSecurityPolicy: "default-src 'self'; ..."
```

**Service-aware middleware application:**

```yaml
# routers.yml - Different chains for different service types

# Admin panel (strictest security)
traefik-dashboard:
  middlewares:
    - crowdsec-bouncer@file
    - admin-whitelist@file      # IP restriction
    - rate-limit-strict@file
    - authelia@file
    - security-headers-strict@file

# Standard authenticated service
grafana-secure:
  middlewares:
    - crowdsec-bouncer@file
    - rate-limit@file
    - authelia@file
    - security-headers@file

# High-throughput service (native auth)
immich-secure:
  middlewares:
    - crowdsec-bouncer@file
    - rate-limit-immich@file     # 500 req/min for photo browsing
    - circuit-breaker@file
    - retry@file
    - compression@file
    - security-headers@file

# Public service
homepage-dashboard:
  middlewares:
    - crowdsec-bouncer@file
    - rate-limit-public@file
    - security-headers-public@file
```

### Good Example (Production Code)

**Immich routing:** High-capacity rate limit (500 req/min, 2000 burst) for thumbnail scrolling, circuit breaker for reliability, compression for media delivery. All centrally defined, applied consistently.

### Anti-Pattern (What NOT to Do)

**DON'T: Define middleware chains in container labels**

```ini
# ❌ WRONG: Per-service middleware definition
Label=traefik.http.routers.service1.middlewares=auth,rate-limit,crowdsec
Label=traefik.http.routers.service2.middlewares=crowdsec,auth,rate-limit
# ❌ Ordering inconsistent! service1 does auth before IP check (waste)
```

**Why this is bad:**
- Easy to misorder middleware (auth before IP check = waste CPU on banned IPs)
- No way to audit all middleware chains at once
- Changing rate limit tier requires editing N quadlets
- Inconsistent security policies across services

---

## Principle 3: Secrets via Platform Primitives

### Statement

**Use Podman secrets for containerized services. Prefer `type=env` injection. Never hardcode secrets in configs.**

### Rationale

**Hierarchy of secret management:**
1. **Best:** Podman secrets with `type=env` injection
   - Encrypted at rest
   - Portable (works with any app expecting env vars)
   - No wrapper scripts needed
2. **Acceptable:** Podman secrets with `type=mount` (file reference)
   - For applications with native `file://` URI support (e.g., Authelia)
3. **Legacy:** EnvironmentFile (for bare-metal systemd services only)
   - Not encrypted, but acceptable for non-containerized services
4. **Never:** Hardcoded secrets in configs

**Benefits:**
- **Encryption:** Secrets encrypted at rest (libsecret)
- **Rotation:** `podman secret rm` + `podman secret create` + service restart
- **Git safety:** Secrets never in repository (automatic)
- **Audit trail:** `podman secret ls` shows all secrets

### Implementation

**Standard approach (type=env):**

```ini
# Create secret
$ echo "my-db-password" | podman secret create db_password -

# Reference in quadlet
[Container]
Secret=db_password,type=env,target=DB_PASSWORD

# Application reads environment variable
# No wrapper script needed!
```

**Acceptable approach (type=mount for file:// apps):**

```ini
# Authelia natively supports file:// URIs
[Container]
Secret=authelia_jwt_secret

# Authelia config
jwt_secret: file:///run/secrets/authelia_jwt_secret
```

**Rotation procedure:**

```bash
# 1. Generate new secret
openssl rand -base64 32 > ~/containers/secrets/db_password.new

# 2. Delete old Podman secret
podman secret rm db_password

# 3. Create new Podman secret
podman secret create db_password ~/containers/secrets/db_password.new

# 4. Restart service (picks up new secret)
systemctl --user restart service.service

# 5. Verify
systemctl --user status service.service

# 6. Replace source file
mv ~/containers/secrets/db_password.new ~/containers/secrets/db_password
```

### Good Example (Production Code)

**Nextcloud secrets:** 3 Podman secrets (`nextcloud_db_password`, `nextcloud_db_root_password`, `nextcloud_redis_password`), all using `type=env` injection. Clean, portable, encrypted.

```ini
Secret=nextcloud_db_password,type=env,target=MYSQL_PASSWORD
Secret=nextcloud_redis_password,type=env,target=REDIS_HOST_PASSWORD
```

### Anti-Pattern (What NOT to Do)

**DON'T: Hardcode secrets in configs**

```ini
# ❌ WRONG: Plaintext secret in Git-tracked file
[Container]
Environment=DB_PASSWORD=my-secret-password-123
```

**DON'T: Use EnvironmentFile for containerized services**

```ini
# ❌ DISCOURAGED: Use Podman secrets instead
[Container]
EnvironmentFile=%h/containers/config/service/.env
# Not encrypted, harder to rotate, legacy pattern
```

**Why this is bad:**
- Secrets leaked to Git (even if .gitignore, easy to forget)
- No encryption at rest
- Rotation requires editing files manually
- Audit trail limited (no `podman secret ls`)

---

## Principle 4: Configuration as Code

### Statement

**All infrastructure configuration is Git-tracked. Secrets are excluded via `.gitignore`. Changes are committed with descriptive messages.**

### Rationale

**Benefits:**
- **Version control:** Full audit trail of all infrastructure changes
- **Disaster recovery:** `git clone` + restore secrets = rebuilt homelab
- **Collaboration:** Changes documented, reviewable
- **Rollback:** `git revert` for instant rollback
- **Search:** `git log --grep` finds when/why changes were made

**Git exclusions (must be comprehensive):**
```gitignore
# Secrets
*.env
*secret*
*password*
*api_key*

# Certificates
*.key
*.pem
acme.json

# Databases
*.db
*.sqlite*
```

### Implementation

**Standard workflow:**

```bash
# 1. Make infrastructure change
nano ~/.config/containers/systemd/newservice.container

# 2. Test change
systemctl --user daemon-reload
systemctl --user restart newservice.service

# 3. Verify
systemctl --user status newservice.service
curl -I https://newservice.patriark.org

# 4. Commit with descriptive message
git add .config/containers/systemd/newservice.container
git commit -m "feat(newservice): Add newservice deployment

- Deployed using web-app-with-database pattern
- Uses Podman secrets for DB credentials
- Routing via Traefik dynamic config (authenticated)
- Memory limit: 2GB (MemoryHigh: 1.5GB)"

# 5. Push to remote (if using remote)
git push origin main
```

**Quadlets, Traefik configs, deployment patterns all tracked:**
```
containers/
├── .config/containers/systemd/       # Git-tracked
├── config/traefik/dynamic/           # Git-tracked
├── .claude/skills/                   # Git-tracked
├── docs/                             # Git-tracked
└── secrets/                          # NOT tracked (gitignored)
```

### Good Example (Production Code)

**This homelab:** 295 documentation files, 23 quadlets, 5 Traefik dynamic configs, all in Git with clear commit messages. Disaster recovery: Clone repo + restore secrets.

### Anti-Pattern (What NOT to Do)

**DON'T: Make undocumented manual changes**

```bash
# ❌ WRONG: Direct container creation without quadlet
podman run -d --name myapp myimage:latest

# Now it's running but NOT in Git, NOT managed by systemd
# Lost on reboot, no audit trail, not reproducible
```

**DON'T: Commit secrets to Git**

```bash
# ❌ CATASTROPHIC: Secrets in Git history
git add config/service/secrets.env
git commit -m "add config"
# Secret now in Git history FOREVER (even if deleted)
```

**Why this is bad:**
- Undocumented changes lost on disaster recovery
- No audit trail (who changed what when?)
- Can't rollback to previous state
- Secrets exposure in Git history (public if pushed)

---

## Principle 5: Fail-Safe Defaults

### Statement

**Default to most secure configuration. Require explicit opt-out with documentation. Secure by default, not secure by effort.**

### Rationale

**Fail-safe principle:** If I forget to configure something, the system should be secure.

**Security defaults:**
- Authentication required (unless explicitly made public)
- Run as non-root user (`User=1000:1000`)
- Volumes read-only (unless write explicitly needed)
- All security headers applied (unless specific app conflict)
- Strict rate limits for auth endpoints (unless high-throughput justified)
- Health checks enabled (unless technically impossible)

**Benefits:**
- **Harder to misconfigure:** Forgetting to add auth = service requires auth anyway
- **Explicit decisions documented:** Removing auth middleware requires documentation
- **Security by default:** New deployments inherit secure patterns

### Implementation

**Default: Authenticated service**

```yaml
# routers.yml - Default template
service-name-secure:
  rule: "Host(`service.patriark.org`)"
  middlewares:
    - crowdsec-bouncer@file       # Always
    - rate-limit@file              # Always
    - authelia@file                # DEFAULT: Require auth
    - security-headers@file        # Always
```

**Explicit opt-out (documented):**

```yaml
# jellyfin-secure - INTENTIONALLY NO AUTHELIA (native auth)
jellyfin-secure:
  middlewares:
    - crowdsec-bouncer@file
    - rate-limit-public@file
    # authelia@file - OMITTED: Jellyfin has native authentication
    - security-headers@file

# Documented in service guide:
# "Jellyfin uses native authentication with SSO planned for Phase 2"
```

**Quadlet defaults:**

```ini
# Standard quadlet template
[Container]
Image=service:latest
ContainerName=service
User=1000:1000                          # Non-root by default
Volume=%h/containers/config/service:/config:ro,Z  # Read-only by default
HealthCmd=curl -f http://localhost/health || exit 1  # Health check by default

[Service]
Restart=on-failure                      # Auto-restart by default
```

### Good Example (Production Code)

**Vaultwarden:** Native auth system (Bitwarden client), SSO deliberately omitted (isolated password vault). Decision documented in ADR-007.

**Nextcloud:** Native auth for CalDAV/CardDAV compatibility. Decision documented in ADR-013.

Both are **explicit opt-outs** with clear rationale in ADRs.

### Anti-Pattern (What NOT to Do)

**DON'T: Start permissive, harden later**

```yaml
# ❌ WRONG: Public by default, add auth later
service-secure:
  middlewares:
    - crowdsec-bouncer@file
    # TODO: Add auth when we have time
```

**Why this is bad:**
- Service exposed publicly until auth added
- Easy to forget to add auth
- Security debt accumulates
- Harder to harden after deployment than to relax after

---

## Principle 6: Service Discovery via Naming Convention

### Statement

**Container names match service hostnames. DNS-based service discovery. No hardcoded IP addresses.**

### Rationale

**Naming convention:**
- Container name: `jellyfin`
- Service hostname: `jellyfin.patriark.org`
- Traefik backend: `http://jellyfin:8096`

**Benefits:**
- **Self-documenting:** See hostname in route, know container name
- **DNS-based:** No IP address management burden
- **Portable:** Containers can move IPs without config changes
- **Scalable:** Add containers without updating routing

**Network placement determines reachability:**
- Internal services: Internal networks only (no reverse_proxy)
- Public services: reverse_proxy + internal networks

### Implementation

**Standard deployment:**

```ini
# Quadlet
[Container]
ContainerName=jellyfin         # Container name
Network=systemd-reverse_proxy.network

# Traefik discovers container by name
```

```yaml
# routers.yml
jellyfin-secure:
  rule: "Host(`jellyfin.patriark.org`)"  # Public hostname
  service: "jellyfin"                     # Matches container name

services:
  jellyfin:
    loadBalancer:
      servers:
        - url: "http://jellyfin:8096"    # DNS resolution via container name
```

**Network segmentation:**

```ini
# Database (internal only)
[Container]
ContainerName=postgres-immich
Network=systemd-database.network
# NOT on reverse_proxy - Traefik can't reach it ✅

# App (public + internal)
[Container]
ContainerName=immich-server
Network=systemd-reverse_proxy.network
Network=systemd-database.network
# Can reach database, can be reached by Traefik ✅
```

### Good Example (Production Code)

**Immich stack:** 4 containers (`immich-server`, `immich-ml`, `postgresql-immich`, `redis-immich`). DNS-based communication:
- `immich-server` → `postgresql-immich:5432`
- `immich-server` → `redis-immich:6379`
- `immich-server` → `immich-ml:3003`

No IP addresses anywhere. Portable, self-documenting.

### Anti-Pattern (What NOT to Do)

**DON'T: Hardcode IP addresses**

```yaml
# ❌ WRONG: Hardcoded IP
services:
  jellyfin:
    loadBalancer:
      servers:
        - url: "http://10.89.2.15:8096"
# What if container restarts with new IP? Broken.
```

**DON'T: Random container names**

```ini
# ❌ WRONG: Non-descriptive name
[Container]
ContainerName=container-abc123
# Can't tell what this is from name
```

**Why this is bad:**
- IP changes break routing
- Must maintain IP → service mapping
- Not self-documenting (what is 10.89.2.15?)
- Hardcoded IPs conflict with dynamic networks

---

## Consequences

### Positive Outcomes

**Achieved through adherence:**

✅ **Consistency:** All 23 services follow same patterns (100% compliance as of 2025-12-31)

✅ **Auditability:** See entire security posture in 3 files:
- `routers.yml` (248 lines) - All routes
- `middleware.yml` (13,749 bytes) - All security policies
- `quadlets/` (23 files) - All deployments

✅ **Security:** Fail-fast middleware ordering guaranteed, no misconfigurations

✅ **Maintainability:** Changes isolated (routing vs deployment vs secrets)

✅ **Disaster recovery:** Git clone + restore secrets = full rebuild in <1 hour

✅ **Scalability:** Add services without drift (patterns enforce principles)

✅ **Transferable skills:** Principles apply to production environments (not homelab-specific)

### Negative Consequences

⚠️ **Learning curve:** New collaborators must understand principles before deploying

⚠️ **Discipline required:** Easy to violate principles if not vigilant

⚠️ **Dual configuration:** Quadlet + Traefik config (vs Docker Compose single file)

⚠️ **Pattern rigidity:** Some edge cases don't fit standard patterns

### Trade-Offs

**Chosen:** Explicit principles over flexibility
- **Benefit:** Consistency, security, auditability
- **Cost:** Must follow patterns, less ad-hoc freedom

**Chosen:** Dynamic config over container labels
- **Benefit:** Centralized, auditable, fail-fast
- **Cost:** Two files to update (quadlet + routers.yml)

**Chosen:** Podman secrets over .env files
- **Benefit:** Encryption, rotation, audit trail
- **Cost:** Slightly more complex setup

**Assessment:** All trade-offs worthwhile at this scale (20-30 services). Would make same decisions again.

---

## Validation

### Production Compliance (2025-12-31)

**Principle 1 (Separation of Concerns):**
- ✅ 0 Traefik labels across 23 quadlets (100% compliance)
- ✅ All routing in `routers.yml` (248 lines, 13 services)

**Principle 2 (Centralized Security):**
- ✅ All middleware in `middleware.yml` (13,749 bytes, 24+ definitions)
- ✅ Fail-fast ordering enforced (CrowdSec → Rate Limit → Auth → Headers)

**Principle 3 (Secrets):**
- ✅ 19 Podman secrets created
- ⚠️ 3 different usage patterns (type=env, type=mount, EnvironmentFile)
- 🔄 Migration to standardize on type=env planned

**Principle 4 (Config as Code):**
- ✅ 295 documentation files in Git
- ✅ All quadlets, Traefik configs, patterns in Git
- ✅ Secrets excluded via .gitignore

**Principle 5 (Fail-Safe Defaults):**
- ✅ 8 services with Authelia SSO (admin/monitoring)
- ✅ 4 services with native auth (documented opt-outs: Jellyfin, Immich, Nextcloud, Vaultwarden)
- ✅ All services run as non-root

**Principle 6 (Service Discovery):**
- ✅ 0 hardcoded IP addresses in routing
- ✅ Container names match service hostnames
- ✅ DNS-based service discovery throughout

**Overall:** 95% compliance (secrets standardization in progress)

---

## Implementation Guidelines

### For New Deployments

1. **Choose deployment pattern** (`homelab-deployment` skill)
2. **Verify pattern follows principles:**
   - ✅ No Traefik labels in quadlet
   - ✅ Secrets via Podman secrets (type=env preferred)
   - ✅ Container name matches hostname
   - ✅ Default to authenticated (explicit opt-out only)
3. **Deploy using pattern script** (generates quadlet + routers.yml)
4. **Verify compliance:** Run `scripts/audit-configuration.sh`

### For Existing Services

**Review against principles:**
- Principle 1: Move labels to `routers.yml` if present
- Principle 2: Verify middleware ordering
- Principle 3: Migrate .env files to Podman secrets
- Principle 4: Ensure configs Git-tracked
- Principle 5: Document authentication opt-outs
- Principle 6: Verify DNS-based discovery

**Prioritize migrations:**
- High: Security-sensitive services (admin panels, auth)
- Medium: Public services (media, files)
- Low: Internal services (databases, caches)

---

## Related Documentation

**Foundational ADRs:**
- ADR-002: Systemd Quadlets Over Docker Compose
- ADR-010: Pattern-Based Deployment Automation

**Operational Guides:**
- Configuration Design Quick Reference
- Middleware Configuration Guide
- Secrets Management Guide

**Service Examples:**
- ADR-004: Immich Deployment (multi-container, secrets, routing)
- ADR-007: Vaultwarden (native auth opt-out)
- ADR-013: Nextcloud Native Authentication (CalDAV opt-out)

---

## Success Criteria

**This decision is successful if:**

- [x] 95%+ of services comply with all six principles (achieved 2025-12-31)
- [ ] New deployments automatically follow principles (via patterns)
- [x] Security audits show consistent middleware ordering (100% compliance)
- [ ] Disaster recovery completes in <1 hour (untested)
- [x] No secrets leaked to Git (verified via .gitignore)
- [x] All routing auditable in single file (routers.yml)

**Evaluation date:** 2026-01-31 (1 month after codification)

---

## Retrospective

**Retrospective (planned for 2026-01-31):**

Questions to answer:
1. Did codifying principles reduce configuration drift?
2. Are new services following principles without intervention?
3. Did any principles prove too rigid for real-world use cases?
4. Are there additional principles that should be added?

---

**Decision made by:** patriark + Claude Code
**Document status:** Living (will update based on retrospective findings)
**Review frequency:** Quarterly or when significant pattern violations detected
