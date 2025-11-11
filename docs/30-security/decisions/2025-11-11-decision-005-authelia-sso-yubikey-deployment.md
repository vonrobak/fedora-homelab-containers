# ADR-005: Authelia SSO with YubiKey-First Authentication

**Date:** 2025-11-11
**Status:** Accepted
**Supersedes:** TinyAuth authentication (de facto, gradual migration)

## Context

The homelab initially deployed TinyAuth as the authentication layer for admin services (Traefik dashboard, Grafana, Prometheus). While functional, TinyAuth has significant limitations:

1. **No hardware 2FA support** - Only password-based authentication, vulnerable to phishing
2. **No SSO capabilities** - Each service requires separate authentication
3. **Limited security features** - No session management, device registration, or security events
4. **Minimal adoption/maintenance** - Small project with limited community support
5. **No mobile app considerations** - Cannot differentiate between web UI and API authentication

The user owns three YubiKey devices and requires **phishing-resistant authentication** as the primary security layer. Hardware FIDO2/WebAuthn authentication eliminates password-based phishing attacks and provides strong second-factor verification.

**Requirements:**
- YubiKey/WebAuthn as PRIMARY authentication method (not just fallback)
- SSO portal for unified authentication experience
- Support for gradual service migration (admin services first, media services conditional)
- Mobile app compatibility (bypass SSO for API endpoints while protecting web UI)
- Session management with configurable timeouts
- TOTP fallback for devices without WebAuthn support

**Environment:**
- Existing Traefik reverse proxy with dynamic configuration pattern
- Podman rootless containers orchestrated via systemd quadlets
- Redis available for session storage
- Let's Encrypt TLS certificates via Traefik

## Decision

Deploy **Authelia 4.38** as the SSO and multi-factor authentication server with the following architecture:

### Authentication Flow

1. **Primary: WebAuthn/FIDO2** (YubiKey touch + optional PIN)
2. **Fallback: TOTP** (Microsoft Authenticator for mobile devices)
3. **Base authentication:** Username + password (Argon2id hashed)

**Rationale for keeping username/password:** Authelia requires credential establishment before WebAuthn enrollment. Passwords provide account recovery mechanism if all hardware tokens are lost.

### Service Tiers

**Tier 1 - Admin Services (YubiKey Required):**
- Traefik Dashboard (traefik.patriark.org)
- Grafana (grafana.patriark.org)
- Prometheus (prometheus.patriark.org)
- Loki (loki.patriark.org)
- Policy: `two_factor` - Requires WebAuthn or TOTP

**Tier 2 - Media Services (Conditional Protection):**
- **Jellyfin:** Web UI requires YubiKey, API endpoints bypass Authelia (mobile app compatibility)
- **Immich:** Uses NATIVE authentication only (removed from Authelia to avoid dual-auth UX issues)

**Tier 3 - Public Services:**
- TinyAuth portal (auth.patriark.org) - Remains accessible during migration, will be decommissioned

### Technical Architecture

**Secrets Management:**
- Podman secrets mounted as files in `/run/secrets/`
- Three secrets: `authelia_jwt_secret`, `authelia_session_secret`, `authelia_storage_key`
- Users database (`users_database.yml`) gitignored for security

**Session Storage:**
- Redis backend (redis-authelia container)
- 1-hour session expiration, 15-minute inactivity timeout
- 1-month "remember me" option

**Access Control:**
- Default policy: `deny` (fail-secure)
- Health check endpoints bypass authentication
- Per-service rules with domain + resource matching
- Group-based access control (admins, users)

**Network Segmentation:**
- Authelia joins both `systemd-reverse_proxy` (Traefik) and `systemd-auth_services` (Redis)
- First network determines default route (reverse_proxy provides internet access)

**Traefik Integration:**
- ForwardAuth middleware: `http://authelia:9091/api/verify?rd=https://sso.patriark.org`
- Authentication headers forwarded to backend services (Remote-User, Remote-Groups)
- Rate limiting: 100 req/min for SSO portal (asset-heavy SPA)

**Mobile App Pattern:**
```yaml
# Jellyfin example - bypass API, protect web UI
- domain: 'jellyfin.patriark.org'
  policy: bypass
  resources:
    - '^/api/.*'
    - '^/System/.*'
    - '^/Sessions/.*'
    - '^/Users/.*/Authenticate'

- domain: 'jellyfin.patriark.org'
  policy: two_factor
  subject:
    - 'group:users'
```

### Configuration-as-Code

Following project architecture principles:
- **Container definition:** `~/.config/containers/systemd/authelia.container` (NO Traefik labels)
- **Routing configuration:** `~/containers/config/traefik/dynamic/routers.yml`
- **Middleware definition:** `~/containers/config/traefik/dynamic/middleware.yml`
- **Authelia config:** `~/containers/config/authelia/configuration.yml` (template in Git)
- **Users database:** `~/containers/config/authelia/users_database.yml` (GITIGNORED)

## Consequences

### Positive

1. **Phishing-resistant authentication** - YubiKey FIDO2 prevents credential phishing attacks
2. **Single sign-on** - Authenticate once, access all protected services
3. **Granular access control** - Per-service policies, group-based authorization
4. **Mobile app compatibility** - API bypass pattern allows native app authentication
5. **Session management** - Automatic logout on inactivity, device registration tracking
6. **Security events** - Login attempts, failed authentication, device registrations logged
7. **Industry-standard solution** - Widely deployed, active development, strong community
8. **Transferable skills** - Authelia patterns apply to enterprise IAM systems

### Negative

1. **Increased complexity** - More moving parts than TinyAuth (Authelia + Redis vs single binary)
2. **Memory overhead** - ~512MB for Authelia + 256MB for Redis (vs ~50MB TinyAuth)
3. **Initial configuration effort** - More extensive setup than TinyAuth
4. **Username/password still required** - Cannot go fully passwordless (Authelia limitation)
5. **Browser caching issues** - WebAuthn settings cached aggressively, requires cache clearing on config changes

### Operational Impact

**Migration Strategy:**
1. ✅ Deploy Authelia alongside TinyAuth (both running)
2. ✅ Migrate admin services first (Grafana, Prometheus, Loki, Traefik)
3. ✅ Test authentication flows (Firefox, Vivaldi, LibreWolf, mobile)
4. ✅ Migrate media services with mobile app testing
5. ⏳ Keep TinyAuth running 1-2 weeks as safety net
6. ⏳ Decommission TinyAuth once confidence established

**Maintenance Requirements:**
- **Password management:** Users set via `podman exec authelia authelia crypto hash generate argon2`
- **YubiKey enrollment:** Through SSO portal (sso.patriark.org/settings)
- **OTP code retrieval:** Filesystem notifier writes to `/data/notification.txt` (no email configured)
- **Session cleanup:** Automatic via Redis expiration
- **Database backups:** SQLite database at `/data/db.sqlite3` (included in container data backups)

### Lessons Learned During Deployment

1. **Dual authentication anti-pattern** - Having both Authelia SSO AND service native auth (Immich) creates confusing UX and mobile app issues. Choose one or the other.

2. **Rate limiting for SPAs** - Modern single-page applications load many assets simultaneously. Standard rate limits (10-30 req/min) are insufficient. SSO portal requires 100+ req/min.

3. **Browser WebAuthn caching** - Security-related browser features cache aggressively. Configuration changes may require clearing site data ("Forget About This Site").

4. **Architecture compliance matters** - Traefik routing belongs in dynamic YAML files, NOT quadlet container labels. Separation of concerns prevents configuration drift.

5. **IP whitelisting vs authentication** - Hardware 2FA (YubiKey) provides stronger security than IP-based access control. Remove redundant IP whitelists.

6. **Secrets as files, not env vars** - Podman secrets default to file mounts. Database encryption expects file-based keys. Changing secret delivery method requires database recreation.

## Alternatives Considered

### 1. Keep TinyAuth + Add YubiKey Support

**Rejected because:**
- TinyAuth has no WebAuthn/FIDO2 support
- Adding 2FA would require forking/patching (maintenance burden)
- No SSO capabilities (each service separate authentication)
- Limited community adoption/support

### 2. Keycloak (Enterprise SSO)

**Rejected because:**
- Massive resource requirements (~2GB RAM minimum)
- Over-engineered for homelab scale
- Complex LDAP/database backend required
- Steep learning curve for single-user environment

### 3. Authentik (Modern SSO)

**Considered but rejected:**
- More complex than needed (OAuth/OIDC focus)
- Requires PostgreSQL or MySQL (additional infrastructure)
- Better suited for multi-user environments
- Authelia simpler for homelab use case

### 4. Ory Kratos + Ory Hydra

**Rejected because:**
- Requires multiple services (identity + OAuth server)
- More complex architecture than Authelia
- Better for microservices architectures
- Overkill for homelab needs

### 5. Passwordless-Only (WebAuthn without passwords)

**Considered but rejected:**
- Authelia requires username/password for account creation
- No recovery mechanism if all YubiKeys lost
- Would require different solution (Ory, custom implementation)
- Passwords + YubiKey = acceptable compromise

### 6. OAuth2 Proxy + External Provider

**Rejected because:**
- Requires external OAuth provider (Google, GitHub, etc.)
- Defeats self-hosted philosophy
- Adds external dependency for critical auth
- No YubiKey support from common providers

## Implementation Notes

### Critical Configuration Decisions

**WebAuthn Settings:**
```yaml
webauthn:
  attestation_conveyance_preference: indirect  # Balance between privacy and verification
  user_verification: preferred                  # Request PIN but don't require it
```

**Initial attempt used `none` and `discouraged`** to troubleshoot YubiKey 5C Lightning enrollment failure. Reverted to `indirect`/`preferred` after determining hardware limitation (2/3 YubiKeys working is acceptable).

**Session Cookie Domain:**
```yaml
cookies:
  - domain: patriark.org                        # Covers all subdomains
    authelia_url: https://sso.patriark.org
    default_redirection_url: https://grafana.patriark.org  # NOT sso.patriark.org
```

**Authelia validation error:** `default_redirection_url` cannot equal `authelia_url`. Grafana chosen as default destination (primary admin interface).

**Middleware Ordering:**
```yaml
middlewares:
  - crowdsec-bouncer    # 1. IP reputation (fastest)
  - rate-limit          # 2. Request throttling
  - authelia@file       # 3. Authentication (most expensive)
```

**Fail-fast principle:** Reject malicious IPs immediately before expensive auth checks.

## References

- **Authelia Documentation:** https://www.authelia.com/
- **WebAuthn Specification:** https://www.w3.org/TR/webauthn-2/
- **FIDO2 Overview:** https://fidoalliance.org/fido2/
- **Project Architecture Docs:** `/home/patriark/containers/docs/00-foundation/guides/`
- **Deployment Journal:** `/home/patriark/containers/docs/30-security/journal/2025-11-11-authelia-deployment.md` (companion document)

## Status History

- **2025-11-11:** Accepted - Authelia deployed successfully, admin services migrated, testing complete

---

**Next ADR:** Will document future authentication decisions (e.g., if migrating to passwordless, adding LDAP, or implementing hardware security modules).
