# Authelia Implementation Plan - YubiKey-First Architecture

**Date:** 2025-11-10 (Revised)
**Status:** Planning
**Related:** ADR-004 (Authelia SSO & MFA Architecture)
**Current Auth:** TinyAuth (working, stable)
**Design Principles:** Rootless, Configuration as Code, Health-Aware, Zero-Trust

---

## Executive Summary

Gradual, service-by-service migration from TinyAuth to Authelia SSO with **YubiKey/WebAuthn as primary authentication**. Conservative approach prioritizing stability, proper secrets management, and alignment with homelab design principles.

**Authentication Strategy:**
- **Primary:** WebAuthn/FIDO2 with YubiKey (phishing-resistant hardware authentication)
- **Fallback:** TOTP for future users without hardware keys
- **Session:** Redis-backed SSO across all services

**Core Principles Honored:**
1. **Rootless containers** - Authelia and Redis run as UID 1000
2. **Middleware ordering** - Maintain fail-fast (CrowdSec → rate limit → Authelia)
3. **Configuration as code** - All configs in Git, secrets via Podman secrets
4. **Health-aware deployment** - Verify readiness before declaring success
5. **Zero-trust model** - Auth required for all internet-accessible services

---

## Design Decisions

### YubiKey-First Authentication Model

**Hardware:**
- 3x YubiKeys available (primary, backup, backup)
- FIDO2/WebAuthn capable
- Phishing-resistant authentication

**Authentication Flow:**
```
User accesses service
  ↓
Authelia checks session (Redis)
  ↓
[No session] → Redirect to auth.patriark.org
  ↓
Username/password entry
  ↓
**YubiKey prompt** (WebAuthn challenge)
  ↓
User touches YubiKey (FIDO2 assertion)
  ↓
Session created (SSO enabled)
  ↓
Redirect to original service
```

**Why YubiKey Primary:**
- ✅ **Phishing-resistant** - Domain-bound, can't be intercepted
- ✅ **Convenience** - Touch to authenticate (no typing codes)
- ✅ **Industry standard** - FIDO2 is the future of authentication
- ✅ **Hardware redundancy** - 3 keys available
- ✅ **Portfolio value** - Demonstrates modern auth architecture

**TOTP as Fallback:**
- For future users without YubiKeys
- Less secure but more accessible
- Still better than password-only

---

## Secrets Management Strategy

### Adhering to Configuration as Code Principle

Following existing patterns from `traefik.container`, `alertmanager.container`:

**Pattern:**
```ini
# Template file (in Git): authelia.container.template
[Container]
Image=authelia/authelia:latest
Secret=authelia_jwt_secret,type=env,target=AUTHELIA_JWT_SECRET
Secret=authelia_session_secret,type=env,target=AUTHELIA_SESSION_SECRET
Secret=authelia_storage_encryption_key,type=env,target=AUTHELIA_STORAGE_ENCRYPTION_KEY

# Actual file (gitignored): authelia.container
# Created during deployment from template
```

**Secrets to Manage:**
1. **JWT Secret** - For token signing (64 char random)
2. **Session Secret** - For session encryption (64 char random)
3. **Storage Encryption Key** - For database encryption (64 char random)
4. **Redis Password** (optional, can use network isolation)

**Creation:**
```bash
# Generate secrets
openssl rand -hex 64 | podman secret create authelia_jwt_secret -
openssl rand -hex 64 | podman secret create authelia_session_secret -
openssl rand -hex 64 | podman secret create authelia_storage_encryption_key -
```

**No hardcoded secrets in quadlets** ✅

---

## Service Categorization & Access Policies

### Tier 1: Administrative (YubiKey Required - Two-Factor)

**Services:**
- Grafana (dashboards)
- Prometheus (metrics)
- Traefik dashboard
- Alertmanager

**Access Policy:**
```yaml
access_control:
  rules:
    - domain:
        - "grafana.patriark.org"
        - "prometheus.patriark.org"
        - "traefik.patriark.org"
        - "alertmanager.patriark.org"
      policy: two_factor
      subject: "group:admins"
```

**Rationale:**
- Infrastructure control interfaces
- Can modify system configurations
- **Must use YubiKey** (WebAuthn required)
- **Highest security requirement**

**Users:** Admin account only (you)

---

### Tier 2: User Services (Password + YubiKey OR TOTP)

**Services:**
- Jellyfin (media streaming)
- Immich (photos)

**Access Policy:**
```yaml
access_control:
  rules:
    - domain:
        - "jellyfin.patriark.org"
        - "immich.patriark.org"
      policy: two_factor  # Note: Changed from one_factor
      subject: "group:users"
```

**Rationale:**
- User-facing media services
- Personal content (not infrastructure)
- **YubiKey for you, TOTP option for future users**
- Balance security with future multi-user UX

**Users:** You (YubiKey) + potential family/friends (TOTP)

**Note:** Even though these are "user" services, we're requiring two-factor. You have YubiKeys - use them everywhere!

---

### Tier 3: Internal Only (Network Restricted - No Authelia)

**Services:**
- node_exporter, cadvisor, promtail
- loki (API), prometheus (API)
- redis-immich, postgresql-immich

**Access Policy:**
```yaml
# No Authelia policy needed
# Traefik middleware: internal-only (IP whitelist)
```

**Rationale:**
- Backend services, container-to-container communication
- Network segmentation provides security
- No user authentication needed

---

### Tier 4: Public/Bypass (Health Checks Only)

**Resources:**
```yaml
access_control:
  rules:
    - domain: "*.patriark.org"
      policy: bypass
      resources:
        - "^/api/health$"
        - "^/health$"
        - "^/ping$"
```

**Rationale:**
- Monitoring probes need access
- No sensitive data exposed

---

## Revised Decisions

### ✅ Decision 1: MFA Strategy

**REVISED:** YubiKey/WebAuthn PRIMARY for all externally accessible services

**Policy:**
- Admin services (Tier 1): **WebAuthn required** (two_factor policy)
- User services (Tier 2): **WebAuthn OR TOTP** (two_factor policy, method choice)
- Your account: **YubiKey registered as primary device**
- Future users: **TOTP option available**

**Why this works:**
- You have 3 YubiKeys - leverage them
- TOTP available for guests without forcing hardware purchase
- Authelia supports multiple methods per user

---

### ✅ Decision 2: MFA Method Priority

**ANSWER: B - WebAuthn first, TOTP fallback**

**Implementation:**
```yaml
# Authelia configuration.yml
webauthn:
  disable: false
  display_name: Patriark Homelab
  attestation_conveyance_preference: indirect
  user_verification: preferred

totp:
  disable: false
  issuer: patriark.org
  period: 30
  skew: 1
```

**User Configuration:**
- **Your account:** Register all 3 YubiKeys as WebAuthn devices
- **Future users:** TOTP enrollment via QR code

**Enrollment Order (for you):**
1. YubiKey #1 (primary - daily use)
2. YubiKey #2 (backup - keep in different location)
3. YubiKey #3 (backup - secure storage)
4. TOTP (optional backup if all YubiKeys unavailable)

---

### ✅ Decision 3: Session Duration

**ANSWER: A - Start with defaults, tune later**

**Configuration:**
```yaml
session:
  expiration: 1h           # Hard timeout
  inactivity: 15m          # Idle timeout
  remember_me_duration: 1M # "Remember me" checkbox
  domain: patriark.org
  same_site: lax

  redis:
    host: redis-authelia
    port: 6379
```

**Rationale:**
- YubiKey makes re-auth fast (touch vs typing code)
- Shorter timeouts acceptable with hardware key
- Can extend if becomes friction

---

### ✅ Decision 4: Migration Pace

**ANSWER: A - Slow & steady (4 weeks), adapting as we grow confidence**

**Timeline:**
- Week 1: Foundation (Redis + Authelia, YubiKey enrollment)
- Week 2: First service (Grafana - test WebAuthn)
- Week 3: User services (Jellyfin, Immich - test SSO)
- Week 4: Completion + TinyAuth decommission

**Flexibility:** Pause at any phase if needed

---

### ✅ Decision 5: User Base

**ANSWER: A - Single-user now, multi-user later**

**Initial:**
- One admin account (you)
- 3 YubiKeys registered
- TOTP configured as backup

**Future:**
- Add family/friends to "users" group
- They use TOTP (not YubiKeys)
- Separate access policies per group

---

### ✅ Decision 6: First Service

**ANSWER: Grafana ✅**

**Why:**
- Non-critical (downtime acceptable)
- Admin-only (only you affected)
- **Tests WebAuthn requirement**
- **Tests YubiKey touch flow**
- Low risk

---

## Implementation Roadmap

### Phase 1: Foundation (Week 1)

**Objective:** Deploy Authelia and Redis, enroll YubiKeys, test authentication

#### Day 1: Redis Deployment

**Tasks:**
1. Create `redis-authelia.container` quadlet
2. Configure persistence (AOF + RDB)
3. Network: `systemd-auth_services`
4. Deploy and verify health

**Success Criteria:**
- Redis healthy and responding
- Data persisting across restarts
- Accessible from Authelia network

---

#### Day 2: Authelia Deployment

**Tasks:**
1. Generate secrets (JWT, session, storage encryption)
2. Create `authelia.container.template` (in Git)
3. Create `authelia.container` from template (gitignored)
4. Configure for WebAuthn + TOTP
5. Deploy container
6. Verify health check

**Configuration Highlights:**
```yaml
# /config/authelia/configuration.yml
server:
  host: 0.0.0.0
  port: 9091

webauthn:
  disable: false
  display_name: Patriark Homelab
  attestation_conveyance_preference: indirect
  user_verification: preferred
  timeout: 60s

totp:
  disable: false
  issuer: patriark.org

authentication_backend:
  file:
    path: /config/users_database.yml
    password:
      algorithm: argon2id

session:
  domain: patriark.org
  redis:
    host: redis-authelia
    port: 6379

access_control:
  default_policy: deny
  # Policies defined per tier above

storage:
  local:
    path: /data/db.sqlite3

notifier:
  filesystem:
    filename: /data/notification.txt
```

**Success Criteria:**
- Authelia healthy and responding
- Can access auth.patriark.org
- Health endpoint returns 200 OK

---

#### Day 3: User Creation & YubiKey Enrollment

**Tasks:**
1. Create admin user in `users_database.yml`
2. Access auth.patriark.org
3. **Enroll YubiKey #1** (primary)
4. **Enroll YubiKey #2** (backup)
5. **Enroll YubiKey #3** (secure backup)
6. Optionally enroll TOTP as fallback
7. Test authentication flow

**User Configuration:**
```yaml
# /config/authelia/users_database.yml
users:
  patriark:
    displayname: "Patriark"
    password: "$argon2id$..." # Generated via authelia hash-password
    email: "patriark@patriark.org"
    groups:
      - admins
      - users
```

**YubiKey Enrollment Process:**
1. Log in with password
2. Navigate to security settings
3. Add device → WebAuthn/Security Key
4. Insert YubiKey, touch when prompted
5. Name device (e.g., "YubiKey 5C NFC - Primary")
6. Repeat for additional keys

**Testing:**
1. Log out
2. Log in with password
3. **YubiKey prompt appears**
4. Touch YubiKey
5. Access granted
6. Test with all 3 keys

**Success Criteria:**
- All 3 YubiKeys enrolled successfully
- Can authenticate with each key
- TOTP backup configured (optional)
- **Authentication feels fast and smooth**

---

#### Day 4-5: Traefik Integration & Testing

**Tasks:**
1. Create Authelia middleware in Traefik
2. Deploy test subdomain with Authelia protection
3. Test full authentication flow
4. Verify SSO (session persistence)
5. Test session expiration

**Traefik Middleware:**
```yaml
# config/traefik/dynamic/middleware.yml
http:
  middlewares:
    authelia:
      forwardAuth:
        address: "http://authelia:9091/api/verify?rd=https://auth.patriark.org"
        trustForwardHeader: true
        authResponseHeaders:
          - "Remote-User"
          - "Remote-Groups"
          - "Remote-Name"
          - "Remote-Email"
```

**Test Service:**
```yaml
# Create simple test router
http:
  routers:
    test-authelia:
      rule: "Host(`test.patriark.org`)"
      middlewares:
        - crowdsec-bouncer@file
        - rate-limit@file
        - authelia@file
      service: whoami@docker
```

**Testing Checklist:**
- [ ] Access test.patriark.org redirects to auth.patriark.org
- [ ] Login with password prompts for YubiKey
- [ ] Touch YubiKey grants access
- [ ] Redirected back to test.patriark.org successfully
- [ ] Open new tab to test.patriark.org - **NO re-auth required** (SSO working)
- [ ] Wait 16 minutes - **session expires, re-auth required**
- [ ] "Remember me" checkbox extends session to 1 month

**Success Criteria:**
- Full auth flow working end-to-end
- YubiKey authentication smooth
- SSO validated
- Session management correct
- **No production services migrated yet**

---

### Phase 2: First Production Service (Week 2)

**Service: Grafana** (Admin - YubiKey required)

#### Pre-Migration

**Tasks:**
1. Document current Grafana authentication state
2. Create rollback plan
3. Backup Traefik router configuration

**Current State:**
```yaml
# Grafana router (before)
traefik.http.routers.grafana.middlewares=crowdsec-bouncer@file,rate-limit@file,tinyauth@file
```

---

#### Migration

**Tasks:**
1. Create Authelia access policy for Grafana
2. Update Grafana router middleware
3. Restart Traefik
4. Test authentication

**Authelia Policy:**
```yaml
# /config/authelia/configuration.yml
access_control:
  rules:
    - domain: "grafana.patriark.org"
      policy: two_factor
      subject: "group:admins"
```

**Updated Router:**
```yaml
# Change middleware
traefik.http.routers.grafana.middlewares=crowdsec-bouncer@file,rate-limit@file,authelia@file
```

**Testing:**
1. Access grafana.patriark.org
2. Redirected to Authelia
3. **YubiKey authentication**
4. Access granted
5. Verify Grafana functionality

---

#### Validation (48 hours)

**Monitor:**
- [ ] Can access Grafana reliably
- [ ] YubiKey authentication works consistently
- [ ] No errors in Authelia logs
- [ ] No errors in Traefik logs
- [ ] Grafana dashboards functional
- [ ] No session issues

**Rollback (if needed):**
```yaml
# Revert router middleware
traefik.http.routers.grafana.middlewares=crowdsec-bouncer@file,rate-limit@file,tinyauth@file
```
Restart Traefik - back on TinyAuth in <2 minutes

**Success Criteria:**
- 48 hours of stable operation
- YubiKey authentication smooth
- No functional issues
- **Ready to proceed to next service**

---

### Phase 3: Second Service - SSO Validation (Week 2)

**Service: Prometheus** (Admin - YubiKey required)

**Objective:** Validate SSO between Grafana and Prometheus

**Migration:**
1. Add Prometheus policy to Authelia
2. Update Prometheus router
3. Restart Traefik

**Key Test:**
- Sign into Grafana (YubiKey auth)
- Access Prometheus **in same browser session**
- **Should NOT prompt for YubiKey again** (SSO working)
- Session shared across services

**Success Criteria:**
- SSO validated
- No double authentication
- Both services accessible

---

### Phase 4: User Services (Week 3)

**Services: Jellyfin, Immich** (User - YubiKey OR TOTP)

**Policy:**
```yaml
access_control:
  rules:
    - domain:
        - "jellyfin.patriark.org"
        - "immich.patriark.org"
      policy: two_factor
      subject: "group:users"
```

**Migration Order:**
1. Jellyfin (Day 1-2)
2. Validate 48 hours
3. Immich (Day 3-4)
4. Validate SSO between Jellyfin and Immich

**User Experience Testing:**
- Access Jellyfin → YubiKey prompt
- Access Immich **in same session** → No prompt (SSO)
- Test on mobile (if applicable)

---

### Phase 5: Remaining Services (Week 4)

**Services: Traefik Dashboard, Alertmanager**

**Migration:**
- Same pattern as previous services
- Less critical, lower risk
- Complete migration of public-facing services

---

### Phase 6: TinyAuth Decommission (Week 4+)

**Pre-Decommission Checklist:**
- [ ] All services using Authelia middleware
- [ ] YubiKey authentication working on all services
- [ ] SSO working across all services
- [ ] Session management stable
- [ ] No auth errors for 7+ days
- [ ] Metrics showing successful auth
- [ ] Comfortable with Authelia reliability

**Decommission Steps:**
1. Stop tinyauth service
2. **Monitor for 48 hours** (any breakage?)
3. Remove tinyauth quadlet
4. Remove tinyauth middleware from Traefik
5. Archive TinyAuth documentation
6. Update CLAUDE.md (remove TinyAuth references)
7. Celebrate! 🎉

**Rollback Window:** Keep TinyAuth backup for 30 days

---

## Secrets Management Implementation

### Following Homelab Patterns

**Pattern from `traefik.container`:**
```ini
[Container]
Secret=traefik_crowdsec_api_key,type=env,target=CROWDSEC_API_KEY
```

**Authelia Quadlet (authelia.container.template in Git):**
```ini
[Unit]
Description=Authelia - SSO & MFA Authentication Server
After=network-online.target redis-authelia.service
Requires=redis-authelia.service

[Container]
Image=authelia/authelia:4.38
ContainerName=authelia
AutoUpdate=registry

# Networks
Network=systemd-reverse_proxy.network
Network=systemd-auth_services.network

# Volumes (SELinux :Z labels)
Volume=%h/containers/config/authelia:/config:Z
Volume=%h/containers/data/authelia:/data:Z

# Secrets (Podman secrets - not hardcoded)
Secret=authelia_jwt_secret,type=env,target=AUTHELIA_JWT_SECRET
Secret=authelia_session_secret,type=env,target=AUTHELIA_SESSION_SECRET
Secret=authelia_storage_encryption_key,type=env,target=AUTHELIA_STORAGE_ENCRYPTION_KEY

# Health check
HealthCmd=wget --no-verbose --tries=1 --spider http://127.0.0.1:9091/api/health || exit 1
HealthInterval=30s
HealthTimeout=10s
HealthRetries=3
HealthStartPeriod=60s

# Resource limits
MemoryMax=512M
CPUQuota=100%

# Traefik labels
Label=traefik.enable=true
Label=traefik.http.routers.authelia.rule=Host(`auth.patriark.org`)
Label=traefik.http.routers.authelia.entrypoints=websecure
Label=traefik.http.routers.authelia.tls=true
Label=traefik.http.routers.authelia.tls.certresolver=letsencrypt
Label=traefik.http.services.authelia.loadbalancer.server.port=9091

[Service]
Restart=on-failure
RestartSec=30s
TimeoutStopSec=70s

[Install]
WantedBy=default.target
```

**Redis Quadlet (redis-authelia.container):**
```ini
[Unit]
Description=Redis - Authelia Session Storage
After=network-online.target

[Container]
Image=redis:7-alpine
ContainerName=redis-authelia
AutoUpdate=registry

# Network
Network=systemd-auth_services.network

# Persistence
Volume=%h/containers/data/redis-authelia:/data:Z

# Redis configuration
Exec=redis-server --appendonly yes --appendfsync everysec

# Health check
HealthCmd=redis-cli ping || exit 1
HealthInterval=10s
HealthTimeout=5s
HealthRetries=3

# Resource limits
MemoryMax=128M
CPUQuota=50%

[Service]
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=default.target
```

**Secret Creation Script:**
```bash
#!/usr/bin/env bash
# scripts/create-authelia-secrets.sh

set -euo pipefail

echo "🔐 Creating Authelia secrets..."

# Generate random secrets
JWT_SECRET=$(openssl rand -hex 64)
SESSION_SECRET=$(openssl rand -hex 64)
ENCRYPTION_KEY=$(openssl rand -hex 64)

# Create Podman secrets
echo "$JWT_SECRET" | podman secret create authelia_jwt_secret -
echo "$SESSION_SECRET" | podman secret create authelia_session_secret -
echo "$ENCRYPTION_KEY" | podman secret create authelia_storage_encryption_key -

echo "✅ Secrets created successfully"
echo ""
echo "Secrets stored in Podman:"
podman secret ls | grep authelia
```

**Configuration as Code:**
- ✅ `.container.template` files in Git
- ✅ `.container` files gitignored
- ✅ Secrets via Podman secrets (not environment variables)
- ✅ No hardcoded credentials

---

## Health-Aware Deployment

### Following Homelab Principle

**Every service has health checks defined in quadlets:**

**Authelia Health Check:**
```ini
HealthCmd=wget --no-verbose --tries=1 --spider http://127.0.0.1:9091/api/health || exit 1
HealthInterval=30s
HealthTimeout=10s
HealthRetries=3
HealthStartPeriod=60s
```

**Deployment Script Pattern:**
```bash
#!/usr/bin/env bash
# scripts/deploy-authelia.sh

set -euo pipefail

echo "Deploying Authelia..."

# 1. Pre-deployment checks
echo "▶ Checking Redis health..."
if ! systemctl --user is-active --quiet redis-authelia.service; then
    echo "✗ Redis not running"
    exit 1
fi

# 2. Deploy service
systemctl --user daemon-reload
systemctl --user restart authelia.service

# 3. Wait for health check
echo "▶ Waiting for Authelia to become healthy..."
for i in {1..30}; do
    if podman healthcheck run authelia &>/dev/null; then
        echo "✓ Authelia is healthy"
        break
    fi
    echo "  Attempt $i/30..."
    sleep 2
done

# 4. Verify health endpoint
echo "▶ Verifying health endpoint..."
if curl -f http://localhost:9091/api/health &>/dev/null; then
    echo "✓ Health endpoint responding"
else
    echo "✗ Health endpoint not responding"
    exit 1
fi

echo "🎉 Authelia deployed successfully"
```

**Never declare success until health checks pass** ✅

---

## Middleware Ordering

### Maintaining Fail-Fast Principle

**Current Order:**
```
[1] CrowdSec IP Reputation (cache - fastest)
[2] Rate Limiting (memory check)
[3] TinyAuth (database + bcrypt - expensive)
[4] Security Headers (response)
```

**New Order (Authelia replaces TinyAuth):**
```
[1] CrowdSec IP Reputation (cache - fastest)
[2] Rate Limiting (memory check)
[3] Authelia SSO (session check + database + WebAuthn - expensive)
[4] Security Headers (response)
```

**Why this works:**
- Still fail-fast (reject bad IPs before expensive auth)
- Authelia session check is fast (Redis lookup)
- Only hits database/WebAuthn if no session
- Maintains performance characteristics

**Traefik Router Example:**
```yaml
traefik.http.routers.grafana.middlewares=crowdsec-bouncer@file,rate-limit@file,authelia@file,security-headers@file
```

**Order preserved** ✅

---

## Risk Management

### Critical Risks & Mitigations

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| **Authelia down = all services locked** | CRITICAL | Medium | Keep TinyAuth running; Health checks + auto-restart; Monitor health |
| **Redis failure = sessions lost** | HIGH | Low | Redis persistence (AOF+RDB); Re-auth acceptable fallback |
| **All YubiKeys lost** | HIGH | Very Low | TOTP backup configured; Recovery codes generated; Physical security |
| **Config error locks you out** | HIGH | Medium | Test with test service first; SSH access to fix; Rollback plan documented |
| **YubiKey not recognized** | MEDIUM | Low | 3 keys enrolled; TOTP fallback; Test all keys during enrollment |

---

## Success Criteria

### Must-Have (Before Declaring Success)

**Technical:**
- [ ] Authelia uptime >99% over 30 days
- [ ] Health check always passing
- [ ] Auth latency <200ms (p95)
- [ ] Redis availability >99.9%

**Security:**
- [ ] All 3 YubiKeys enrolled and working
- [ ] WebAuthn enforced for admin services
- [ ] TOTP configured as backup
- [ ] No failed auth attempts (brute force blocked)

**Functionality:**
- [ ] SSO working (sign in once, access all)
- [ ] Session management correct
- [ ] All production services migrated
- [ ] No user-reported issues for 7 days
- [ ] TinyAuth safely decommissioned

**Configuration:**
- [ ] All secrets via Podman secrets
- [ ] No hardcoded credentials
- [ ] Template files in Git
- [ ] Actual configs gitignored

---

## Documentation & Archival

### Following Documentation Standards

**During Implementation:**
1. Create journal entry: `docs/30-security/journal/2025-11-XX-authelia-deployment.md`
2. Update guides: `docs/30-security/guides/authelia.md`
3. Document YubiKey enrollment: `docs/30-security/guides/yubikey-enrollment.md`

**After Successful Migration:**
1. Update CLAUDE.md (replace TinyAuth with Authelia)
2. Archive TinyAuth docs:
   ```bash
   git mv docs/30-security/guides/tinyauth.md docs/90-archive/
   ```
3. Add archival header to tinyauth.md:
   ```markdown
   > **ARCHIVED:** 2025-11-XX
   > **Reason:** Replaced by Authelia SSO
   > **Superseded by:** docs/30-security/guides/authelia.md
   > **Historical context:** TinyAuth served well as lightweight auth
   ```
4. Update archive index: `docs/90-archive/ARCHIVE-INDEX.md`

**ADR Status Update:**
```markdown
# ADR-004: Authelia SSO & MFA Architecture

**Status:** Accepted ✅
**Implementation Date:** 2025-11-XX
**Related Implementation:** docs/30-security/journal/2025-11-XX-authelia-deployment.md
```

---

## Next Steps

### Immediate Actions

**User Review:**
1. Read this revised plan
2. Confirm YubiKey-first approach acceptable
3. Confirm secrets management pattern acceptable
4. Approve to proceed with Phase 1

**Phase 1 Preparation:**
1. Create deployment scripts (Redis, Authelia, secrets)
2. Create quadlet templates
3. Create configuration files
4. Prepare testing checklist

**Timeline:**
- Planning approval: Today
- Phase 1 start: When you're ready
- Target completion: 4 weeks from start (flexible)

---

## Summary of Revisions

**Changes from Original Plan:**

1. ✅ **YubiKey/WebAuthn PRIMARY** (not optional)
2. ✅ **TOTP as fallback** (not primary)
3. ✅ **Podman secrets** (not environment variables)
4. ✅ **Configuration as code** (templates in Git)
5. ✅ **Health-aware deployment** (explicit health checks)
6. ✅ **Middleware ordering preserved** (fail-fast principle)
7. ✅ **Documentation standards** (journal, guides, archive)
8. ✅ **All Tier 2 services require MFA** (not just Tier 1)

**Alignment with Design Principles:**
- ✅ Rootless containers
- ✅ Middleware ordering (fail-fast)
- ✅ Configuration as code
- ✅ Health-aware deployment
- ✅ Zero-trust model

**Ready to proceed?** This plan honors your homelab's design philosophy and leverages your YubiKey hardware for modern, phishing-resistant authentication.

---

**Status:** Awaiting user approval
**Created:** 2025-11-10 (Revised for YubiKey-first)
**Owner:** User + Claude collaboration
