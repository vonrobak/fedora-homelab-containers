# ADR-004: Authelia SSO & MFA Architecture

**Status:** Proposed
**Date:** 2025-11-10
**Decision Makers:** System Architect
**Related ADRs:** ADR-001 (Rootless Containers), ADR-002 (Systemd Quadlets), ADR-003 (Monitoring Stack)

---

## Context

### Current State: TinyAuth

The homelab currently uses **TinyAuth** for forward authentication:

**Strengths:**
- ✅ Lightweight (~15MB RAM)
- ✅ Simple deployment (single container)
- ✅ Works with Traefik forward auth
- ✅ SQLite backend (no separate database)
- ✅ Minimal attack surface

**Limitations:**
- ❌ No single sign-on (SSO) - auth per service
- ❌ No multi-factor authentication (MFA/2FA)
- ❌ No hardware key support (YubiKey, etc.)
- ❌ Basic session management
- ❌ No LDAP/external identity provider integration
- ❌ Limited audit logging
- ❌ No per-service access control policies

### Business Drivers

As the homelab grows from **16 services** and continues expanding, several needs emerge:

1. **User Experience:** Typing password for each service is friction
2. **Security Posture:** Password-only authentication is insufficient for 2025
3. **Learning Value:** SSO and MFA are industry-standard enterprise patterns
4. **Portfolio Value:** Demonstrating modern auth architecture
5. **Future-Proofing:** Ability to add services without auth complexity

### Strategic Timing

**Why now?**
- ✅ Foundation complete (100% health checks and resource limits)
- ✅ Monitoring stack operational (can observe auth failures)
- ✅ Intelligence system can track auth patterns
- ✅ Architecture stable (good time for major change)
- ⚠️ Before adding more services (establish pattern early)

---

## Decision

**Deploy Authelia as the primary authentication and authorization provider**, replacing TinyAuth for most services while maintaining a phased migration approach.

### What is Authelia?

**Authelia** is an open-source authentication and authorization server providing:

- **SSO:** Single sign-on across all services
- **MFA:** Multiple second-factor options (TOTP, WebAuthn, Duo, etc.)
- **Hardware Keys:** YubiKey, Titan, etc. via WebAuthn
- **Access Control:** Per-service, per-user, per-group policies
- **Session Management:** Configurable timeouts, remember me, activity tracking
- **Identity Providers:** LDAP, file-based, future: external IdP
- **Rich Audit Logs:** Who accessed what, when, from where

### Deployment Architecture

**Container:**
```
authelia.service (systemd quadlet)
├── Image: authelia/authelia:latest
├── Networks: systemd-reverse_proxy, systemd-auth_services
├── Storage:
│   ├── /config (Authelia configuration)
│   ├── /data (user database, sessions)
│   └── /secrets (encryption keys, JWT secrets)
├── Dependencies: Redis (sessions), PostgreSQL (optional for users)
├── Health Check: http://localhost:9091/api/health
└── Resource Limits: MemoryMax=512M
```

**Integration Points:**

1. **Traefik Forward Auth:**
   ```yaml
   # middleware.yml
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

2. **Network Topology:**
   ```
   systemd-reverse_proxy (10.89.2.0/24)
   ├── Traefik (reverse proxy)
   ├── Authelia (serves login portal)
   └── Protected services

   systemd-auth_services (10.89.3.0/24)
   ├── Authelia (backend verification)
   ├── Traefik (verification requests)
   └── Redis (session storage)
   ```

3. **Middleware Ordering (Fail-Fast):**
   ```
   [1] CrowdSec IP Reputation (cache - fastest)
   [2] Rate Limiting (memory check)
   [3] Authelia SSO (session check + database - expensive)
   [4] Security Headers (applied on response)
   ```

   **Why this order:** Follows ADR principle of fail-fast. Reject malicious IPs immediately before wasting cycles on auth lookups.

### Key Configuration Elements

**Session Management:**
```yaml
session:
  domain: patriark.org
  expiration: 1h
  inactivity: 15m
  remember_me_duration: 1M
  redis:
    host: redis-authelia
    port: 6379
```

**Access Control Policies:**
```yaml
access_control:
  default_policy: deny
  rules:
    # Public services (no auth)
    - domain: "*.patriark.org"
      policy: bypass
      resources:
        - "^/api/health$"

    # Monitoring (admin only)
    - domain:
        - "grafana.patriark.org"
        - "prometheus.patriark.org"
      policy: two_factor
      subject: "group:admins"

    # Media (authenticated users)
    - domain:
        - "jellyfin.patriark.org"
        - "immich.patriark.org"
      policy: one_factor
      subject: "group:users"
```

**MFA Configuration:**
```yaml
authentication_backend:
  file:
    path: /config/users_database.yml
    password:
      algorithm: argon2id
      iterations: 3
      memory: 65536
      parallelism: 4

totp:
  issuer: patriark.org
  period: 30
  skew: 1

webauthn:
  display_name: Patriark Homelab
  attestation_conveyance_preference: indirect
  user_verification: preferred
```

---

## Integration with Existing Architecture

### Relation to ADR-001: Rootless Containers

**Compatibility:** ✅ Fully compatible

Authelia runs rootless like all other services:
- No privileged capabilities needed
- Bind to high ports (9091), Traefik handles 80/443
- SELinux `:Z` labels on all volumes
- Runs as UID 1000 (unprivileged user)

**Implementation:**
```ini
[Container]
# Rootless - no User= directive needed
Volume=%h/containers/config/authelia:/config:Z
Volume=%h/containers/data/authelia:/data:Z
```

### Relation to ADR-002: Systemd Quadlets

**Compatibility:** ✅ Fully compatible

Authelia deployed as systemd quadlet:
```ini
[Unit]
Description=Authelia - Authentication & Authorization Server
After=network-online.target redis-authelia.service reverse_proxy-network.service
Requires=redis-authelia.service reverse_proxy-network.service

[Container]
Image=authelia/authelia:latest
ContainerName=authelia
# ... (standard quadlet pattern)

[Service]
Restart=on-failure
MemoryMax=512M

[Install]
WantedBy=default.target
```

**Management:**
```bash
systemctl --user status authelia.service
journalctl --user -u authelia.service -f
```

### Relation to ADR-003: Monitoring Stack

**Compatibility:** ✅ Enhanced by monitoring

Authelia provides rich metrics and logs:

**Prometheus Metrics:**
```yaml
# Authelia exposes metrics on :9091/metrics
- job_name: 'authelia'
  static_configs:
    - targets: ['authelia:9091']
```

**Grafana Dashboard:**
- Authentication attempts (success/failure)
- MFA verification rates
- Session counts and duration
- Per-user activity patterns
- Geographic distribution (IP analysis)

**Loki Logs:**
```yaml
# Promtail scrapes Authelia logs
- job_name: authelia
  static_configs:
    - targets:
        - localhost
      labels:
        job: authelia
        __path__: /var/log/authelia/*.log
```

**Alertmanager Triggers:**
- Repeated auth failures (potential attack)
- MFA bypass attempts
- Session anomalies (impossible travel)
- Service becoming unhealthy

### Security Architecture Enhancement

Authelia **strengthens** the layered security model from CLAUDE.md:

**Current Flow:**
```
Internet → Port Forward (80/443)
  ↓
[1] CrowdSec IP Reputation
  ↓
[2] Rate Limiting
  ↓
[3] TinyAuth (password only)
  ↓
[4] Security Headers
  ↓
Backend Service
```

**Enhanced Flow:**
```
Internet → Port Forward (80/443)
  ↓
[1] CrowdSec IP Reputation
  ↓
[2] Rate Limiting
  ↓
[3] Authelia SSO + MFA
  │   ├─ Session check (fast)
  │   ├─ Password verification (if needed)
  │   ├─ MFA challenge (if enabled)
  │   └─ Access control policy check
  ↓
[4] Security Headers
  ↓
Backend Service (with user identity headers)
```

**Key improvements:**
- ✅ SSO reduces password exposure (type once vs. per-service)
- ✅ MFA adds second factor (TOTP, WebAuthn, YubiKey)
- ✅ Policy engine (per-service access control)
- ✅ Session management (timeout, remember-me)
- ✅ Rich audit trail (who accessed what)

---

## Migration Strategy

### Phase 1: Parallel Deployment (Week 1)

**Objective:** Deploy Authelia alongside TinyAuth without disrupting existing auth

**Steps:**
1. Deploy Redis for Authelia sessions
2. Deploy Authelia container with basic config
3. Create test users in Authelia
4. Configure Authelia middleware in Traefik (don't apply yet)
5. Test Authelia with a non-critical service (e.g., test subdomain)

**Services:**
- TinyAuth: Still protecting all production services
- Authelia: Protecting only test services
- **Zero disruption to existing auth**

**Success Criteria:**
- Authelia healthy and responding
- Test service accessible via Authelia SSO
- MFA working (TOTP or WebAuthn)

### Phase 2: Gradual Migration (Week 2)

**Objective:** Migrate services one by one from TinyAuth to Authelia

**Service Migration Order:**
1. **Monitoring services** (Grafana, Prometheus) - Admin only, test MFA
2. **Media services** (Jellyfin, Immich) - User-facing, test SSO UX
3. **Infrastructure** (Traefik dashboard, cAdvisor) - Less critical
4. **Authentication service itself** (auth.patriark.org) - Last

**Migration Pattern per Service:**
```yaml
# Before (TinyAuth):
traefik.http.routers.jellyfin.middlewares=crowdsec-bouncer@file,rate-limit@file,tinyauth@file

# After (Authelia):
traefik.http.routers.jellyfin.middlewares=crowdsec-bouncer@file,rate-limit@file,authelia@file
```

**Rollback Plan:**
- Keep TinyAuth running during migration
- Switch back to tinyauth middleware if issues
- Document user credentials in both systems during transition

### Phase 3: TinyAuth Decommission (Week 3+)

**Objective:** Remove TinyAuth once all services migrated

**Pre-decommission Checklist:**
- [ ] All services using Authelia middleware
- [ ] All users can authenticate via Authelia
- [ ] MFA configured for admin accounts
- [ ] Session management working correctly
- [ ] Audit logs being collected
- [ ] Monitoring dashboards showing Authelia metrics
- [ ] 1+ week of stable operation

**Decommission Steps:**
1. Stop TinyAuth service
2. Monitor for 48 hours (any breakage?)
3. Remove TinyAuth quadlet
4. Remove tinyauth middleware definition
5. Archive TinyAuth data (keep backup)
6. Update documentation

**Rollback Window:** Keep TinyAuth backup for 30 days

---

## Consequences

### Positive

**Security:**
- ✅ **MFA protection** on all services (password + second factor)
- ✅ **Hardware key support** (YubiKey, Titan) for admins
- ✅ **SSO** reduces password fatigue and reuse
- ✅ **Per-service access control** (admins vs. users vs. guests)
- ✅ **Rich audit logs** for compliance and forensics
- ✅ **Session management** with timeout and remember-me

**User Experience:**
- ✅ **Sign in once**, access all services
- ✅ **Centralized login page** (consistent UX)
- ✅ **Remember me** option (1 month sessions)
- ✅ **Modern auth UX** (not basic HTTP auth)

**Operations:**
- ✅ **Centralized user management** (one place to add/remove users)
- ✅ **Policy as code** (access control in YAML)
- ✅ **Prometheus metrics** (authentication visibility)
- ✅ **Standards-based** (OIDC ready for future)

**Learning:**
- ✅ **Industry-standard SSO pattern**
- ✅ **MFA implementation experience**
- ✅ **WebAuthn/FIDO2 knowledge**
- ✅ **Policy-based access control**
- ✅ **Portfolio-worthy authentication architecture**

### Negative

**Complexity:**
- ⚠️ **More complex** than TinyAuth (configuration, dependencies)
- ⚠️ **Additional service** to monitor and maintain
- ⚠️ **Redis dependency** for session storage (adds moving part)
- ⚠️ **Migration effort** required (phased rollout)

**Resources:**
- ⚠️ **Higher memory usage**: ~512MB vs. TinyAuth's ~15MB
- ⚠️ **Additional disk**: Config, logs, session data
- ⚠️ **Network hops**: Traefik → Authelia → Redis (vs. TinyAuth direct)

**Operational:**
- ⚠️ **User setup**: Need to register MFA for each user
- ⚠️ **Session management**: Need to understand expiration behavior
- ⚠️ **Backup complexity**: Encryption keys, user database, sessions
- ⚠️ **Learning curve**: More configuration options = more to learn

### Risks and Mitigations

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| **Auth service down = all services inaccessible** | High | Medium | Health checks + auto-restart + monitoring alerts |
| **Redis failure breaks sessions** | Medium | Low | Redis persistence + health checks + fallback to re-auth |
| **Config error locks out users** | High | Medium | Keep TinyAuth running during migration + test users first |
| **MFA device lost** | Medium | Medium | Recovery codes + backup TOTP + YubiKey backup |
| **Session hijacking** | High | Low | Secure cookies + same-site + HTTPS only + short timeouts |
| **Performance impact** | Low | Medium | Resource limits + monitoring + Redis caching |

---

## Implementation Roadmap

### Week 1: Foundation

**Day 1: Redis Deployment**
- Deploy Redis for session storage
- Configure persistence (AOF + RDB)
- Health checks and resource limits
- Verify Prometheus metrics

**Day 2: Authelia Deployment**
- Create Authelia quadlet
- Basic configuration (file-based users)
- Deploy container
- Verify health check

**Day 3: Configuration**
- Session settings (expiration, Redis)
- Access control policies (initial set)
- TOTP configuration
- WebAuthn setup (optional)

**Day 4: Testing**
- Create test users
- Test authentication flow
- Test SSO behavior
- Test MFA (TOTP)

**Day 5: Monitoring Integration**
- Prometheus scraping Authelia metrics
- Grafana dashboard for auth visibility
- Loki log collection
- Alertmanager rules

### Week 2: Migration

**Day 6-7: Monitoring Services**
- Migrate Grafana to Authelia
- Migrate Prometheus to Authelia
- Test admin access with MFA
- Verify SSO between services

**Day 8-9: Media Services**
- Migrate Jellyfin to Authelia
- Migrate Immich to Authelia
- Test user experience
- Gather feedback

**Day 10: Infrastructure Services**
- Migrate Traefik dashboard
- Migrate cAdvisor
- Migrate remaining services

### Week 3+: Consolidation

**Day 11-17: Stability Period**
- Monitor for issues
- Tune session timeouts
- Refine access policies
- Collect metrics

**Day 18+: Decommission TinyAuth**
- Follow decommission checklist
- Archive TinyAuth data
- Update documentation
- Celebrate! 🎉

---

## Alternatives Considered

### Alternative 1: Keep TinyAuth

**Pros:**
- ✅ Already working
- ✅ Minimal resources
- ✅ Simple to understand

**Cons:**
- ❌ No SSO
- ❌ No MFA
- ❌ Limited learning value
- ❌ Not portfolio-worthy

**Verdict:** Rejected - doesn't meet evolving security and UX needs

### Alternative 2: Keycloak

**Pros:**
- ✅ Full-featured enterprise SSO
- ✅ OIDC, SAML, LDAP support
- ✅ User federation
- ✅ Industry standard

**Cons:**
- ❌ **Heavy** (~2GB RAM, Java-based)
- ❌ Complex setup (steeper learning curve)
- ❌ Overkill for homelab scale
- ❌ Requires PostgreSQL

**Verdict:** Rejected - too heavy for homelab scale

### Alternative 3: OAuth2 Proxy + External IdP (Google, GitHub)

**Pros:**
- ✅ Simple deployment
- ✅ Leverage existing accounts
- ✅ Low maintenance

**Cons:**
- ❌ **External dependency** (internet required for auth)
- ❌ Privacy concerns (Google/GitHub knows your access patterns)
- ❌ Less control over auth flow
- ❌ Not self-hosted (defeats homelab purpose)

**Verdict:** Rejected - defeats self-hosting purpose

### Alternative 4: Authelia (Chosen)

**Pros:**
- ✅ Self-hosted and open source
- ✅ SSO + MFA + hardware keys
- ✅ Moderate resource usage (~512MB)
- ✅ Designed for reverse proxy integration
- ✅ Rich access control policies
- ✅ Good documentation and community
- ✅ OIDC support (future identity provider)

**Cons:**
- ⚠️ More complex than TinyAuth
- ⚠️ Requires Redis dependency
- ⚠️ Migration effort

**Verdict:** **SELECTED** - Best balance of features, resources, and learning value

---

## Success Metrics

### Technical Metrics

**Reliability:**
- [ ] Authelia uptime: >99.9% (measured over 30 days)
- [ ] Health check: Always healthy
- [ ] Auth latency: <100ms (p95)
- [ ] Redis availability: >99.9%

**Security:**
- [ ] MFA enrollment: 100% of admin accounts
- [ ] MFA enforcement: Enabled for monitoring services
- [ ] Failed auth attempts: <1% of total (normal user errors)
- [ ] Brute force protection: Working (rate limiting + CrowdSec)

**Performance:**
- [ ] No perceptible latency vs. TinyAuth
- [ ] Memory usage: <512MB
- [ ] CPU usage: <5% average
- [ ] Session cache hit rate: >90%

### User Experience Metrics

**SSO:**
- [ ] Users sign in once per session
- [ ] "Remember me" works for 30 days
- [ ] No duplicate password prompts

**MFA:**
- [ ] TOTP enrollment working
- [ ] WebAuthn working (YubiKey tested)
- [ ] Recovery codes available

**Access Control:**
- [ ] Admins can access all services
- [ ] Users can access media services
- [ ] Guests blocked from infrastructure services

### Operational Metrics

**Monitoring:**
- [ ] Prometheus scraping Authelia metrics
- [ ] Grafana dashboard showing auth stats
- [ ] Loki collecting auth logs
- [ ] Alerts firing on auth failures

**Documentation:**
- [ ] ADR written (this document)
- [ ] Deployment guide created
- [ ] User guide for MFA enrollment
- [ ] Troubleshooting guide

**Migration:**
- [ ] All services migrated from TinyAuth
- [ ] TinyAuth decommissioned
- [ ] No user-reported auth issues
- [ ] Rollback plan tested

---

## References

### Documentation

- **Authelia Official Docs:** https://www.authelia.com/
- **Traefik Forward Auth:** https://doc.traefik.io/traefik/middlewares/http/forwardauth/
- **WebAuthn Spec:** https://www.w3.org/TR/webauthn/
- **TOTP RFC:** https://tools.ietf.org/html/rfc6238

### Related Homelab Documents

- **CLAUDE.md:** Security architecture (middleware ordering)
- **ADR-001:** Rootless containers principle
- **ADR-002:** Systemd quadlets deployment pattern
- **ADR-003:** Monitoring stack integration
- **docs/10-services/guides/tinyauth.md:** Current auth implementation

### Community Resources

- **Awesome Selfhosted:** https://github.com/awesome-selfhosted/awesome-selfhosted
- **r/selfhosted:** Community discussions on SSO implementations
- **Authelia Discord:** Real-time help and community support

---

## Approval and Review

**Proposed by:** Claude (AI Assistant)
**Review Date:** 2025-11-10
**Decision Date:** TBD (User approval)
**Implementation Start:** TBD (After GPU acceleration deployment)

**Review Questions for User:**

1. Is the migration strategy (3-phase rollout) acceptable?
2. Should we prioritize TOTP or WebAuthn for initial MFA?
3. Are there any services that should remain password-only (no MFA)?
4. Is 512MB memory allocation for Authelia acceptable?
5. Should we plan for OIDC (future external IdP) from day one?

---

## Appendix A: Example Authelia Configuration

**Minimal Production Configuration:**

```yaml
# /config/configuration.yml
server:
  host: 0.0.0.0
  port: 9091

log:
  level: info
  format: text

theme: dark

jwt_secret: <GENERATE_RANDOM_64_CHAR_STRING>

default_redirection_url: https://patriark.org

totp:
  issuer: patriark.org
  period: 30
  skew: 1

webauthn:
  disable: false
  display_name: Patriark Homelab
  attestation_conveyance_preference: indirect

authentication_backend:
  file:
    path: /config/users_database.yml
    password:
      algorithm: argon2id

access_control:
  default_policy: deny
  rules:
    # Health checks (bypass auth)
    - domain: "*.patriark.org"
      policy: bypass
      resources:
        - "^/api/health$"

    # Monitoring (two-factor)
    - domain:
        - "grafana.patriark.org"
        - "prometheus.patriark.org"
      policy: two_factor

    # Media (one-factor for users)
    - domain:
        - "jellyfin.patriark.org"
        - "immich.patriark.org"
      policy: one_factor

session:
  name: authelia_session
  domain: patriark.org
  same_site: lax
  expiration: 1h
  inactivity: 15m
  remember_me_duration: 1M

  redis:
    host: redis-authelia
    port: 6379

regulation:
  max_retries: 5
  find_time: 2m
  ban_time: 5m

storage:
  local:
    path: /data/db.sqlite3

notifier:
  filesystem:
    filename: /data/notification.txt
```

---

## Appendix B: Service Migration Checklist Template

**Service Name:** _______________
**Migration Date:** _______________
**Migrated By:** _______________

**Pre-Migration:**
- [ ] Service currently protected by TinyAuth
- [ ] Test users created in Authelia
- [ ] Access control policy defined for this service
- [ ] Rollback plan documented

**Migration:**
- [ ] Update Traefik labels (tinyauth → authelia middleware)
- [ ] Restart service
- [ ] Test authentication flow
- [ ] Test SSO (sign in once, access service)
- [ ] Test MFA (if applicable)

**Post-Migration:**
- [ ] Service accessible via Authelia
- [ ] No user-reported issues after 24 hours
- [ ] Metrics showing successful auth requests
- [ ] Logs show no auth errors

**Rollback (if needed):**
- [ ] Revert Traefik labels (authelia → tinyauth middleware)
- [ ] Restart service
- [ ] Verify working with TinyAuth

---

**End of ADR-004**

*This ADR will be updated as implementation progresses and learnings emerge.*
