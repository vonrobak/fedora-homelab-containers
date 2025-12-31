# Configuration Design Philosophy Analysis

**Date:** 2025-12-31
**Purpose:** Holistic analysis of homelab configuration design principles
**Scope:** ADR-002 (Quadlets), ADR-010 (Patterns), Traefik routing, secrets management
**Status:** Analysis complete, recommendations ready for planning

---

## Executive Summary

After comprehensive investigation of 23 deployed services, deployment patterns, and configuration management across the homelab, I've discovered a **remarkably consistent and well-architected system** with a clear design philosophy. However, there are opportunities to:

1. **Codify implicit design principles** that are already being followed
2. **Standardize secrets management** across three current patterns
3. **Align deployment patterns** with proven production practices
4. **Document the philosophy** to guide future deployments

**Key Finding:** The homelab already implements a sophisticated "separation of concerns" model where:
- **Quadlets = Service Deployment** (what runs, where, with what resources)
- **Traefik Dynamic Config = Network Routing** (how external traffic reaches services)
- **Podman Secrets = Credential Management** (how sensitive data is injected)

This is production-grade architecture, but it's **implicit, not explicit** in documentation.

---

## Current State Analysis

### 1. Traefik Configuration: A Tale of Two Worlds

#### The Stated Approach (CLAUDE.md, ADR-010)

CLAUDE.md says deployment patterns should include labels:
```yaml
labels:
  traefik.enable: "true"
  traefik.http.routers.service.rule: "Host(`{{hostname}}`)"
```

ADR-010 deployment patterns reference "Traefik templates" but don't clearly specify labels vs dynamic config.

#### The Actual Implementation (Production Reality)

**100% dynamic configuration, zero container labels.**

**Evidence:**
- 23 quadlet files analyzed
- **0 Traefik labels** (`traefik.*`) in any quadlet
- 13 services with routes in `routers.yml` (248 lines)
- All middleware centralized in `middleware.yml` (13,749 bytes)

**Example from actual quadlet (alertmanager.container:39-40):**
```ini
# Note: Traefik routing configured in ~/containers/config/traefik/dynamic/routers.yml
# Per design principles: routing belongs in dynamic YAML, not container labels
```

**Example from actual routing (routers.yml):**
```yaml
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

#### Why This Matters (Design Philosophy Revealed)

The production implementation shows a deliberate architectural choice:

**Separation of Concerns:**
- **Quadlet responsibility:** "I am a Jellyfin server on port 8096"
- **Traefik responsibility:** "I route jellyfin.patriark.org → http://jellyfin:8096"

**Benefits Observed:**
1. **Single source of truth** - All routing in `routers.yml` (auditable at a glance)
2. **Clean quadlets** - No infrastructure annotations cluttering service definitions
3. **Centralized security** - Middleware chains applied uniformly
4. **Git-friendly** - Routing changes tracked separately from service deployments
5. **Fail-fast middleware** - CrowdSec → Rate Limit → Auth ordering enforced centrally

**Comparison to Label-Based Approach:**

| Aspect | Dynamic Config (Current) | Container Labels (Alternative) |
|--------|--------------------------|--------------------------------|
| Source of truth | Single file (routers.yml) | Distributed across 23 quadlets |
| Auditability | See all routes at once | Must grep across quadlets |
| Change tracking | Routing changes isolated | Routing + service mixed |
| Middleware consistency | Enforced centrally | Must remember per service |
| Fail-fast ordering | Guaranteed correct | Easy to misorder |
| Scalability | Add routes without touching quadlets | Every service must have labels |

**Verdict:** The production approach is **objectively superior** for this homelab's scale and security requirements.

---

### 2. Deployment Patterns: The Misalignment

#### Pattern Files vs Production Reality

**Deployment patterns reference labels:**
```yaml
# patterns/web-app-with-database.yml
quadlet:
  container:
    labels:
      traefik.enable: "true"
      traefik.http.routers.service.rule: "Host(`{{hostname}}`)"
```

**But production deployments use dynamic config:**
```yaml
# Templates actually generate routers.yml entries, not labels
```

#### The Disconnect

The patterns were designed **before** the centralized routing philosophy matured. They reflect an earlier Docker Compose-style approach where labels were the norm.

**Evidence from pattern templates:**
```
.claude/skills/homelab-deployment/templates/traefik/
├── authenticated-service.yml
├── public-service.yml
├── api-service.yml
└── admin-service.yml
```

These templates **generate dynamic config** but patterns still reference label syntax.

#### Impact

New deployments might:
1. Add labels to quadlets (following pattern examples)
2. Then manually create dynamic config (following production reality)
3. End up with **redundant configuration** in two places
4. Create confusion about which is authoritative

---

### 3. Secrets Management: Three Patterns, One Goal

#### Discovery: 19 Podman Secrets, 3 Usage Patterns

**Podman secrets properly implemented:**
```bash
$ podman secret ls
authelia_jwt_secret
authelia_session_secret
postgres-password
immich-jwt-secret
crowdsec_api_key
smtp_password
nextcloud_db_password
grafana_admin_password
... (19 total)
```

**But THREE different consumption patterns:**

**Pattern 1: File Reference (Authelia)**
```ini
# Quadlet
Secret=authelia_jwt_secret

# Application config
jwt_secret: file:///run/secrets/authelia_jwt_secret
```
✅ **Best for:** Applications natively supporting `file://` URIs

**Pattern 2: Environment Variable Injection (Nextcloud, Grafana)**
```ini
Secret=nextcloud_db_password,type=env,target=MYSQL_PASSWORD
```
✅ **Best for:** 12-factor apps expecting environment variables
✅ **Most portable** - Works with any application

**Pattern 3: Shell Command Expansion (Nextcloud Redis)**
```ini
Secret=nextcloud_redis_password
Exec=sh -c 'redis-server --requirepass "$(cat /run/secrets/nextcloud_redis_password)"'
```
⚠️ **Works but fragile** - Shell expansion, command injection risk

**Pattern 4: Legacy .env File (Vaultwarden ONLY)**
```ini
EnvironmentFile=%h/containers/config/vaultwarden/vaultwarden.env
```
❌ **Plaintext file** - Not using Podman secrets at all

#### Inconsistencies Detected

| Service | Pattern | Issue |
|---------|---------|-------|
| CrowdSec | Pattern 1 + wrapper script | Needs `traefik-entrypoint.sh` to export env var |
| Alertmanager | Pattern 1 | Secret created but unused (no injection mechanism) |
| Vaultwarden | .env file | Not using Podman secrets |
| Nextcloud Redis | Pattern 3 | Shell expansion fragile |
| All others | Pattern 2 | ✅ Correct |

#### Source Files Protection

```bash
~/containers/secrets/  # 600 permissions
├── crowdsec_api_key
├── redis_password
├── smtp_password
├── cloudflare_token
└── cloudflare_zone_id
```

These are **source files** used to create Podman secrets, then deleted/retained as backup. Protected by filesystem permissions (acceptable).

---

## Design Principles Analysis

### What ADR-002 Says (Systemd Quadlets Philosophy)

**Core tenets:**
1. Native systemd integration (no abstraction layers)
2. Infrastructure as code (Git-tracked configuration)
3. One file per container (modularity)
4. Dependency management via systemd
5. Unified logging (journald)

**Trade-off accepted:**
- Slightly more files → Better modularity
- Learning systemd → Transferable skills
- Fedora-specific → Production-grade approach

### What Production Reality Shows (Implicit Principles)

The deployed system reveals additional principles **not codified in ADRs:**

#### Principle A: Separation of Deployment from Routing

**Deployment (Quadlet):** Service configuration
```ini
[Container]
Image=jellyfin/jellyfin:latest
ContainerName=jellyfin
Network=systemd-reverse_proxy.network
Volume=%h/containers/config/jellyfin:/config:Z
```

**Routing (Traefik Dynamic):** Network ingress
```yaml
routers:
  jellyfin-secure:
    rule: "Host(`jellyfin.patriark.org`)"
    service: jellyfin
```

**Rationale:** Quadlets answer "what runs?", Traefik answers "how is it accessed?"

#### Principle B: Fail-Fast Security Layering

**Middleware ordering enforced centrally:**
```yaml
middlewares:
  - crowdsec-bouncer@file    # 1. Block bad IPs (cache lookup - fastest)
  - rate-limit@file           # 2. Prevent abuse (memory check - fast)
  - authelia@file             # 3. Authenticate (database + bcrypt - expensive)
  - security-headers@file     # 4. Add headers (response modification - last)
```

**Cost pyramid:**
```
     [Most Expensive]  Auth (database, bcrypt)
          ↑
     Rate Limit (memory check)
          ↑
     [Least Expensive]  CrowdSec (cache lookup)
```

**Centralization ensures** this ordering is never violated.

#### Principle C: Service-Aware Security Policies

**Different middleware chains for different access patterns:**

| Service Type | Middleware Chain | Rationale |
|--------------|------------------|-----------|
| Admin panels | crowdsec → ip-whitelist → rate-limit-strict → authelia | Maximum security |
| Authenticated apps | crowdsec → rate-limit → authelia | Standard security |
| Native auth apps | crowdsec → rate-limit-[tier] → security-headers | No SSO (own auth) |
| High-throughput | crowdsec → rate-limit-[500/min] → circuit-breaker | Performance focus |
| Public content | crowdsec → rate-limit-public | Minimal friction |

**Example - Immich (photos):**
```yaml
middlewares:
  - crowdsec-bouncer@file
  - rate-limit-immich@file      # 500 req/min, 2000 burst (thumbnail scrolling)
  - circuit-breaker@file         # Prevent cascade failures
  - retry@file                   # Transient error recovery
  - compression@file             # Optimize media delivery
  - security-headers@file
```

**Centralized configuration enables** this nuanced security model.

#### Principle D: Secrets Injection via Platform Primitives

**Preference hierarchy:**
1. Podman secrets (type=env) - **Preferred** (portable, secure)
2. Podman secrets (file) - **Acceptable** (for apps supporting file://)
3. Entrypoint wrapper - **Last resort** (adds complexity)
4. .env files - **Deprecated** (plaintext, legacy)

**Observed best practice:**
```ini
Secret=db_password,type=env,target=DB_PASSWORD
```

Podman automatically creates `DB_PASSWORD` environment variable from secret file.

---

## Alternative Approaches Considered

### Alternative 1: Use Container Labels (Docker Compose Style)

**How it would work:**
```ini
# jellyfin.container
[Container]
Image=jellyfin/jellyfin:latest
Label=traefik.enable=true
Label=traefik.http.routers.jellyfin.rule=Host(`jellyfin.patriark.org`)
Label=traefik.http.routers.jellyfin.middlewares=crowdsec-bouncer,rate-limit
Label=traefik.http.services.jellyfin.loadbalancer.server.port=8096
```

**Pros:**
- Self-contained (service + routing in one file)
- Traefik auto-discovers via Docker provider
- Familiar to Docker Compose users
- One less config file to maintain

**Cons:**
- No single source of truth for routing (distributed across 23 quadlets)
- Difficult to audit all routes (must grep across files)
- Easy to forget middleware or misorder them
- Routing changes mixed with service changes in git history
- Can't see security policy at a glance
- Traefik dynamic config still needed for complex middleware
- Creates dual-mode configuration (some dynamic, some labels)

**Assessment:** ❌ **Rejected** - Loses centralized visibility and security consistency

---

### Alternative 2: Hybrid Approach (Labels + Dynamic Config)

**How it would work:**
```ini
# jellyfin.container
Label=traefik.enable=true
Label=traefik.http.routers.jellyfin.rule=Host(`jellyfin.patriark.org`)
# Middleware still in dynamic config
```

**Pros:**
- Route discovery automatic
- Middleware centralized for consistency

**Cons:**
- Worst of both worlds (configuration split between two places)
- Must check both quadlet AND dynamic config to understand routing
- Potential for label/dynamic config conflicts
- Unclear which takes precedence
- Maintenance burden doubled

**Assessment:** ❌ **Rejected** - Creates confusion and dual configuration burden

---

### Alternative 3: Pure Dynamic Config (Current Approach)

**How it works:**
```yaml
# routers.yml
http:
  routers:
    jellyfin-secure:
      rule: "Host(`jellyfin.patriark.org`)"
      service: "jellyfin"
      middlewares: [crowdsec-bouncer@file, rate-limit-public@file, ...]
  services:
    jellyfin:
      loadBalancer:
        servers:
          - url: "http://jellyfin:8096"
```

```ini
# jellyfin.container (no Traefik labels)
[Container]
Image=jellyfin/jellyfin:latest
ContainerName=jellyfin
Network=systemd-reverse_proxy.network
```

**Pros:**
- ✅ Single source of truth (`routers.yml`)
- ✅ Audit all routes in one file
- ✅ Centralized middleware ordering enforcement
- ✅ Clean separation (deployment vs routing)
- ✅ Git history tracks routing changes separately
- ✅ Easy to see security policy holistically
- ✅ Service-aware middleware chains
- ✅ No label sprawl in quadlets

**Cons:**
- Must manually add route when deploying service (not auto-discovered)
- Two files to update (quadlet + routers.yml)
- Requires understanding Traefik dynamic config syntax

**Assessment:** ✅ **Current approach - Superior for this environment**

**Why it works:**
- Homelab scale: 13 public routes (manageable in one file)
- Security-first: Centralized middleware prevents mistakes
- Auditability: See all attack surface in 248 lines
- Stability: Routes rarely change (add new, don't modify existing)

---

### Alternative 4: Full Infrastructure as Code (Terraform/Ansible)

**How it would work:**
```hcl
# terraform/jellyfin.tf
resource "podman_container" "jellyfin" {
  name  = "jellyfin"
  image = "jellyfin/jellyfin:latest"
}

resource "traefik_router" "jellyfin" {
  rule = "Host(`jellyfin.patriark.org`)"
  service = "jellyfin"
}
```

**Pros:**
- Declarative infrastructure
- State management
- Dependency graph
- Multi-provider (Podman + Traefik + Cloudflare DNS)

**Cons:**
- ❌ Massive complexity overhead for single-host homelab
- ❌ Requires learning Terraform/Ansible
- ❌ Conflicts with ADR-002 (systemd quadlets philosophy)
- ❌ Hides underlying container mechanics (anti-learning)
- ❌ Overkill for 23 services

**Assessment:** ❌ **Rejected** - Violates learning-focused homelab principles, too complex

---

## Secrets Management: Path Forward

### Current State Assessment

**Strengths:**
- ✅ 19/23 services using Podman secrets
- ✅ Source files protected (600 permissions)
- ✅ Git exclusions comprehensive
- ✅ Pattern 2 (env injection) works well where used

**Weaknesses:**
- ⚠️ Three different patterns (inconsistent)
- ⚠️ Alertmanager secret unused (created but not injected)
- ⚠️ CrowdSec requires wrapper script
- ⚠️ Vaultwarden still using .env file
- ⚠️ No documented rotation schedule

### Proposed Standard: Pattern 2 (Environment Variable Injection)

**Recommended approach for ALL services:**
```ini
Secret=service_secret,type=env,target=SERVICE_PASSWORD
```

**Why Pattern 2:**
1. **Universal compatibility** - Works with any application expecting env vars
2. **No wrapper scripts** - Podman handles injection
3. **12-factor compliant** - Standard application config method
4. **Secure** - Secret never written to disk in container
5. **Simple** - One-line quadlet declaration

**Migration path:**
- **Keep Pattern 1** for Authelia (native `file://` support)
- **Migrate Pattern 3** to Pattern 2 (Nextcloud Redis)
- **Fix Pattern 4** by creating Podman secret for Vaultwarden
- **Document Pattern 2** as standard in deployment patterns

### Secret Lifecycle Management

**Creation:**
```bash
# 1. Generate secret
openssl rand -base64 32 > ~/containers/secrets/service_secret

# 2. Create Podman secret
podman secret create service_secret ~/containers/secrets/service_secret

# 3. Reference in quadlet
Secret=service_secret,type=env,target=SERVICE_SECRET

# 4. Secure source file
chmod 600 ~/containers/secrets/service_secret
```

**Rotation (proposed quarterly schedule):**
```bash
# 1. Generate new secret
openssl rand -base64 32 > ~/containers/secrets/service_secret.new

# 2. Delete old Podman secret
podman secret rm service_secret

# 3. Create new Podman secret
podman secret create service_secret ~/containers/secrets/service_secret.new

# 4. Restart service
systemctl --user restart service.service

# 5. Verify
systemctl --user status service.service

# 6. Replace source file
mv ~/containers/secrets/service_secret.new ~/containers/secrets/service_secret
```

**Documentation needs:**
- Secret inventory with rotation schedule
- Per-service secret requirements
- Rotation runbook
- Testing procedures

---

## Deployment Patterns: Alignment Recommendations

### Current Pattern Structure

**9 patterns, 4 Traefik templates:**

Patterns:
1. `media-server-stack` → authenticated-service.yml
2. `web-app-with-database` → authenticated-service.yml
3. `document-management` → authenticated-service.yml
4. `authentication-stack` → authenticated-service.yml
5. `password-manager` → authenticated-service.yml (custom)
6. `database-service` → none
7. `cache-service` → none
8. `reverse-proxy-backend` → authenticated-service.yml
9. `monitoring-exporter` → none

Templates:
- `authenticated-service.yml` - SSO-protected service
- `public-service.yml` - Public access
- `api-service.yml` - CORS-enabled API
- `admin-service.yml` - Admin interface (strict security)

### The Problem

**Pattern YAML shows:**
```yaml
quadlet:
  container:
    labels:
      traefik.enable: "true"
      traefik.http.routers.service.rule: "Host(`{{hostname}}`)"
```

**Templates should generate:**
```yaml
# routers.yml entry
http:
  routers:
    {{service_name}}-secure:
      rule: "Host(`{{hostname}}`)"
      service: "{{service_name}}"
      middlewares: [...]
```

### Proposed Solution

**Update pattern definitions to reflect dynamic config generation:**

```yaml
# patterns/web-app-with-database.yml
deployment:
  traefik:
    routing_method: dynamic_config
    template: authenticated-service.yml
    generates: routers.yml entry

  quadlet:
    container:
      image: "{{image}}"
      networks:
        - systemd-reverse_proxy.network
      # NO LABELS - routing in dynamic config
```

**Update templates to generate routers.yml snippets:**

```yaml
# templates/traefik/authenticated-service.yml
http:
  routers:
    {{service_name}}-secure:
      rule: "Host(`{{hostname}}`)"
      entryPoints:
        - websecure
      middlewares:
        - crowdsec-bouncer@file
        - rate-limit@file
        - authelia@file
        - security-headers@file
      service: "{{service_name}}"
      tls:
        certResolver: letsencrypt

  services:
    {{service_name}}:
      loadBalancer:
        servers:
          - url: "http://{{service_name}}:{{port}}"
```

**Deployment script modification:**

```bash
# deploy-from-pattern.sh
# OLD: Adds labels to quadlet
# NEW: Generates routers.yml entry and appends to dynamic config

cat >> ~/containers/config/traefik/dynamic/routers.yml <<EOF
    ${service_name}-secure:
      rule: "Host(\`${hostname}\`)"
      # ... (from template)
EOF

# Reload Traefik to pick up changes
podman exec traefik kill -SIGHUP 1
```

---

## Recommended Design Principles (Codified)

### Principle 1: Separation of Concerns

**Quadlet files define service deployment:**
- What container image runs
- What resources it needs (CPU, memory, volumes)
- What networks it joins
- What secrets it consumes
- Health checks and restart policies

**Traefik dynamic config defines network routing:**
- What hostnames route to what services
- What middleware protects each route
- What TLS certificates are used
- What load balancing strategy applies

**Anti-pattern:** Mixing routing configuration into quadlets via labels

**Rationale:**
- Single source of truth for routing (routers.yml)
- Centralized security policy enforcement
- Clean separation enables independent evolution
- Audit trail clarity (git blame shows routing vs service changes)

---

### Principle 2: Centralized Security Enforcement

**All middleware chains defined in one place:**
- `middleware.yml` - Security stack definitions
- `routers.yml` - Per-service middleware application

**Fail-fast ordering guaranteed:**
```yaml
middlewares:
  - crowdsec-bouncer@file    # Cheapest: cache lookup
  - rate-limit@file           # Fast: memory check
  - authelia@file             # Expensive: database + crypto
  - security-headers@file     # Response modification
```

**Service-aware policies:**
- Admin panels: ip-whitelist + strict rate limits
- Auth endpoints: very strict rate limits (5-10 req/min)
- High-throughput: generous limits + circuit breakers
- Public content: minimal friction

**Anti-pattern:** Per-service middleware ordering in labels (easy to misorder)

**Rationale:**
- Prevents security policy drift
- Ensures fail-fast principle
- Enables consistent security posture
- Simplifies security audits

---

### Principle 3: Secrets via Platform Primitives

**Standard: Podman secrets with environment variable injection**
```ini
Secret=service_secret,type=env,target=SERVICE_SECRET
```

**Acceptable: Podman secrets with file reference**
```ini
Secret=authelia_jwt_secret  # App reads /run/secrets/authelia_jwt_secret
```
Only for applications natively supporting file:// URIs.

**Deprecated: Environment files (.env)**
```ini
EnvironmentFile=%h/containers/config/service/service.env  # Legacy only
```

**Anti-pattern:** Hardcoded secrets in quadlets or config files

**Rationale:**
- Platform-native secret management
- Secure secret injection (never on disk in container)
- Rotation-friendly (update secret, restart service)
- Git-safe (secrets never committed)

---

### Principle 4: Configuration as Code

**All configuration in Git:**
- Quadlet definitions
- Traefik dynamic config
- Application configs (with secrets excluded)
- Deployment patterns
- Documentation

**Git exclusions (.gitignore):**
- `*.env` files
- `*secret*`, `*password*`, `*api_key*`
- Database files (`*.db`, `*.sqlite*`)
- Certificates (`*.key`, `*.pem`, `acme.json`)

**Anti-pattern:** Undocumented manual configuration

**Rationale:**
- Version control for all infrastructure
- Audit trail of all changes
- Disaster recovery (git clone + restore secrets)
- Collaboration-friendly

---

### Principle 5: Fail-Safe Defaults

**Default to most secure configuration:**
- Require authentication unless explicitly made public
- Apply all security headers by default
- Use strict rate limits for sensitive endpoints
- Run containers as non-root (User=1000:1000)
- Mount volumes read-only unless write needed
- Enable health checks on all services

**Explicit opt-out when needed:**
```yaml
# jellyfin-secure: No Authelia (native auth)
middlewares:
  - crowdsec-bouncer@file
  - rate-limit-public@file
  # authelia@file - INTENTIONALLY OMITTED (native auth)
  - security-headers@file
```

**Anti-pattern:** Starting permissive and tightening later

**Rationale:**
- Security by default
- Explicit documentation of security decisions
- Easier to relax than to harden post-deployment

---

### Principle 6: Service Discovery via Naming Convention

**Container names match service hostnames:**
```ini
# quadlet
ContainerName=jellyfin

# Traefik
url: "http://jellyfin:8096"
```

**Network placement determines reachability:**
- Backend services: Internal networks only
- Frontend services: reverse_proxy + internal networks

**Anti-pattern:** Hardcoded IP addresses, random container names

**Rationale:**
- DNS-based service discovery
- Self-documenting configuration
- No IP address management burden
- Network segmentation enforced

---

## Documentation Updates Required

### 1. Update ADR-002 (Systemd Quadlets)

**Add section: "Traefik Routing Philosophy"**

Current ADR focuses on systemd integration but doesn't address Traefik configuration.

**Proposed addition:**
```markdown
## Traefik Routing Configuration

**Decision:** Traefik routing is defined in dynamic YAML files, NOT container labels.

**Rationale:**
- Separation of concerns (deployment vs routing)
- Centralized security policy
- Single source of truth for routes
- Git-friendly change tracking

**Implementation:**
- Quadlet files contain NO Traefik labels
- All routes defined in ~/containers/config/traefik/dynamic/routers.yml
- Middleware centralized in middleware.yml
- Service discovery via container hostnames

**Example:**
[quadlet + routers.yml example]
```

---

### 2. Update ADR-010 (Pattern-Based Deployment)

**Remove references to labels, add dynamic config generation:**

**Current (line 91-93):**
```yaml
labels:
  traefik.enable: "true"
  traefik.http.routers.service.rule: "Host(`{{hostname}}`)"
```

**Proposed replacement:**
```yaml
traefik_routing:
  method: dynamic_config
  template: authenticated-service.yml
  output_file: ~/containers/config/traefik/dynamic/routers.yml
  reload_command: podman exec traefik kill -SIGHUP 1
```

**Add section: "Traefik Configuration Generation"**
```markdown
## Traefik Configuration Generation

Patterns generate entries for Traefik's dynamic configuration file (`routers.yml`),
not container labels. This maintains separation of concerns and centralized routing.

**Workflow:**
1. Pattern specifies Traefik template (authenticated-service.yml, public-service.yml, etc.)
2. Deployment script renders template with variables
3. Generated router appended to routers.yml
4. Traefik reloaded to apply changes (SIGHUP or wait for auto-reload)

**Example:**
[Template → Generated config example]
```

---

### 3. Create New ADR: Configuration Design Principles

**File:** `docs/00-foundation/decisions/2025-12-31-ADR-016-configuration-design-principles.md`

**Purpose:** Codify the six principles discovered in production

**Structure:**
```markdown
# ADR-016: Configuration Design Principles

## Context
After deploying 23 services, clear design patterns emerged that guide consistent,
secure, maintainable deployments. These principles were implicit in practice but
not explicitly documented.

## Decision
We adopt six core configuration design principles...

[Each principle with rationale, examples, anti-patterns]

## Consequences
[Benefits of codified principles]

## Implementation Guidelines
[How to apply principles in new deployments]
```

---

### 4. Update Configuration Design Quick Reference

**File:** `docs/00-foundation/guides/configuration-design-quick-reference.md`

**Add section: "Traefik Configuration Method"**

```markdown
## 🌐 Traefik Configuration: Dynamic Config vs Labels

**ALWAYS use dynamic config files, NEVER use container labels.**

WHY?
✅ Single source of truth (routers.yml)
✅ Centralized security enforcement
✅ Clean separation of concerns
✅ Git-friendly change tracking
✅ Easier auditing

**Deployment workflow:**
1. Create quadlet file (NO Traefik labels)
2. Add route to ~/containers/config/traefik/dynamic/routers.yml
3. Traefik auto-reloads (or send SIGHUP)

**Quick reference:**
```yaml
# routers.yml
http:
  routers:
    service-name-secure:
      rule: "Host(`service.patriark.org`)"
      service: "service-name"
      middlewares: [crowdsec-bouncer@file, rate-limit@file, ...]

  services:
    service-name:
      loadBalancer:
        servers:
          - url: "http://service-name:port"
```
```

---

### 5. Create Secrets Management Guide

**File:** `docs/30-security/guides/secrets-management.md`

**Purpose:** Document standard secrets workflow

**Contents:**
- Podman secrets overview
- Pattern 2 (env injection) as standard
- Secret creation workflow
- Rotation schedule and procedures
- Service-specific requirements
- Migration guide (Pattern 3/4 → Pattern 2)
- Troubleshooting

---

### 6. Update Deployment Pattern Files

**Update all 9 pattern YAML files:**

**Change:**
```yaml
# OLD
labels:
  traefik.enable: "true"
  traefik.http.routers.service.rule: "Host(`{{hostname}}`)"

# NEW
traefik_routing:
  method: dynamic_config
  template: authenticated-service.yml
```

**Update deployment script** to generate routers.yml entries instead of adding labels.

---

### 7. Update CLAUDE.md

**Section: "Service Deployment"**

**Current mentions labels:**
```markdown
# Create container with podman run (Traefik labels excluded as they should be defined in Traefik dynamic files)
```

**Strengthen to:**
```markdown
## Service Deployment

**CRITICAL: Traefik routing is ALWAYS defined in dynamic config files, NEVER in container labels.**

**Deployment workflow:**
1. Create quadlet file (service deployment - NO Traefik labels)
2. Add route to ~/containers/config/traefik/dynamic/routers.yml (network routing)
3. Choose middleware template based on service type
4. Traefik auto-reloads configuration

**Why dynamic config?**
- Separation of concerns (ADR-016)
- Centralized security enforcement
- Single source of truth for routing
- See all routes in one 248-line file

**Pattern-based deployment handles this automatically:**
```bash
cd .claude/skills/homelab-deployment
./scripts/deploy-from-pattern.sh --pattern web-app-with-database ...
# Generates both quadlet AND routers.yml entry
```
```

---

## Proposed Action Plan (Summary)

### Phase 1: Documentation (No service impact)

1. **Create ADR-016: Configuration Design Principles**
   - Codify six principles
   - Document rationale
   - Provide examples and anti-patterns

2. **Update ADR-002 (Systemd Quadlets)**
   - Add "Traefik Routing Philosophy" section
   - Clarify no-labels approach

3. **Update ADR-010 (Pattern-Based Deployment)**
   - Remove label references
   - Add dynamic config generation section
   - Update pattern structure

4. **Create Secrets Management Guide**
   - Document Pattern 2 as standard
   - Rotation procedures
   - Migration guide

5. **Update Configuration Design Quick Reference**
   - Add Traefik configuration decision tree
   - Secrets management quick ref

6. **Update CLAUDE.md**
   - Strengthen routing philosophy
   - Add deployment workflow

### Phase 2: Deployment Patterns (Low risk)

7. **Update pattern YAML files (9 files)**
   - Replace label syntax with traefik_routing block
   - Document dynamic config generation

8. **Update Traefik templates (4 files)**
   - Ensure templates generate routers.yml entries
   - Add comments explaining usage

9. **Update deploy-from-pattern.sh**
   - Generate routers.yml entries
   - Reload Traefik after config changes
   - Verify routing works

### Phase 3: Secrets Standardization (Service restarts required)

10. **Fix Alertmanager SMTP secret**
    - Implement injection mechanism OR remove unused secret

11. **Migrate Vaultwarden to Podman secrets**
    - Create secrets from .env file
    - Update quadlet
    - Test and verify

12. **Document CrowdSec entrypoint pattern**
    - Add comments explaining why wrapper needed
    - Consider if Pattern 2 can work instead

13. **Create secret rotation schedule**
    - Document rotation frequency per secret
    - Create rotation runbook
    - Add calendar reminders

### Phase 4: Validation (Automated)

14. **Add configuration validation to deployment patterns**
    - Check: Quadlet has no Traefik labels
    - Check: Route exists in routers.yml
    - Check: Secrets use Pattern 2 (or documented exception)

15. **Create configuration audit script**
    - Scan all quadlets for Traefik labels (should be zero)
    - Verify all routes in routers.yml match running services
    - Check secret pattern consistency

---

## Questions for User Review

Before finalizing the plan, I have several questions:

### 1. Traefik Configuration Philosophy

**Observation:** Your production system uses 100% dynamic config with ZERO labels. This is objectively superior for your environment.

**Question:** Do you want to:
- **Option A:** Formalize this as the official approach (recommended)
- **Option B:** Support both methods (hybrid - not recommended)
- **Option C:** Migrate to labels (not recommended - would be step backward)

**My recommendation:** Option A - Codify dynamic config as official approach

---

### 2. Secrets Management Standard

**Observation:** Pattern 2 (env injection) works best for most services. Pattern 1 acceptable for apps with native file:// support.

**Question:** Should we:
- **Option A:** Mandate Pattern 2 for all new services (recommended)
- **Option B:** Allow Pattern 1 or Pattern 2 based on app capabilities
- **Option C:** Migrate ALL services to Pattern 2 (including Authelia)

**My recommendation:** Option B - Pattern 2 by default, Pattern 1 for apps that natively support it (Authelia)

---

### 3. Deployment Pattern Migration

**Observation:** Current patterns reference labels but production uses dynamic config.

**Question:** Should pattern deployment:
- **Option A:** Generate BOTH quadlet + routers.yml entry (recommended)
- **Option B:** Generate quadlet only, require manual router creation
- **Option C:** Generate router entry only, assume quadlet exists

**My recommendation:** Option A - Patterns generate both files for complete automation

---

### 4. Documentation Scope

**Question:** Which documentation updates are highest priority?
- **Tier 1:** ADR-016 (new principles), CLAUDE.md updates, pattern YAML updates
- **Tier 2:** ADR-002/010 updates, quick reference updates
- **Tier 3:** Secrets guide, validation scripts

**My recommendation:** Start with Tier 1 (defines philosophy), then Tier 2 (aligns existing docs), Tier 3 as time permits

---

### 5. Secrets Migration Urgency

**Question:** How urgent is migrating Vaultwarden from .env to Podman secrets?
- **High:** Security risk, do immediately
- **Medium:** Technical debt, next maintenance window
- **Low:** Works fine, migrate when convenient

**My recommendation:** Medium - It works, but standardizing would be cleaner

---

## Conclusion

This homelab demonstrates **production-grade architecture** with thoughtful separation of concerns. The core design is sound; the task is to:

1. **Make implicit principles explicit** (documentation)
2. **Align deployment patterns with reality** (code updates)
3. **Standardize secrets management** (consistency)
4. **Validate compliance automatically** (tooling)

The investigation revealed a mature system with clear philosophy. Codifying this will ensure future deployments maintain the same quality and consistency.

**Next step:** Review this analysis, answer questions, then I'll create the detailed implementation plan.
