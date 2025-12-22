# ADR-013: Nextcloud Native Authentication Strategy

**Date:** 2025-12-20
**Status:** Implemented
**Context:** Nextcloud Production Deployment
**Decision Makers:** Claude Code & patriark

---

## Context and Problem Statement

Nextcloud has been deployed as a production-grade file sync and collaboration platform with CalDAV/CardDAV services for calendar and contact synchronization across multiple devices (iPhone, iPad, MacBook Air, Windows PC). The deployment includes:

- **Core Services:** Nextcloud 30, MariaDB 11, Redis 7, Collabora Online
- **Primary Use Cases:**
  1. File sync and sharing (desktop/mobile clients)
  2. CalDAV calendar sync (iOS Calendar, macOS Calendar)
  3. CardDAV contact sync (iOS Contacts, macOS Contacts)
  4. Collaborative document editing (Collabora Online)
  5. External media browsing (Immich photos, Jellyfin media)

The critical question: **Should Nextcloud use Authelia SSO (like Jellyfin and Grafana) or native authentication?**

This decision directly impacts:
- **Device compatibility** - Can iOS/Android/desktop clients authenticate successfully?
- **CalDAV/CardDAV functionality** - Will auto-discovery and sync work reliably?
- **User experience** - How many authentication layers do users face?
- **Security posture** - What authentication mechanisms protect the service?

---

## Decision Drivers

### Technical Requirements

1. **CalDAV/CardDAV Auto-Discovery**
   - iOS/macOS clients expect `/.well-known/caldav` and `/.well-known/carddav` redirects
   - Auto-discovery must route directly to Nextcloud DAV endpoints without SSO redirects
   - HTTP Basic Auth required for DAV endpoints (no OAuth/OIDC support in most clients)

2. **Mobile/Desktop Client Compatibility**
   - Nextcloud mobile apps (iOS, Android) expect native login flow
   - Desktop sync clients use WebDAV with HTTP Basic Auth
   - Third-party DAV clients (CalDAV/CardDAV) don't support SSO redirects

3. **Multi-User Family/Team Access**
   - Different users need different quotas and permissions
   - Group folders for shared collaboration
   - Per-user calendars and contacts

4. **Security Requirements**
   - Protection against brute-force attacks
   - Optional 2FA for sensitive accounts
   - Rate limiting and IP reputation filtering (CrowdSec)

### User Experience Goals

- **Minimal friction** for device setup (scan QR code, enter credentials, done)
- **Single auth prompt** per device (not SSO redirect + Nextcloud login)
- **Reliable sync** without authentication failures
- **Family-friendly** setup (non-technical users can configure devices)

### Infrastructure Constraints

- **Existing SSO:** Authelia deployed for Jellyfin, Grafana, Traefik dashboard
- **Traefik middleware:** Layered security (CrowdSec → rate limit → auth)
- **Mobile devices:** iPhones/iPads without VPN (public internet access)
- **CalDAV/CardDAV standards:** RFC 4791/6352 compliance required

---

## Considered Options

### Option 1: Authelia SSO (Consistent with Other Services)

**Implementation:**
- Add `authelia@file` middleware to Nextcloud router in Traefik
- Users authenticate via Authelia portal before accessing Nextcloud
- Same pattern as Jellyfin, Grafana, Prometheus

**Pros:**
- ✅ **Centralized authentication** - Single identity provider for all services
- ✅ **YubiKey MFA** - Hardware security key support via Authelia
- ✅ **Consistent UX** - Same login flow as other services
- ✅ **Security logging** - Centralized auth logs in Authelia

**Cons:**
- ❌ **Breaks CalDAV/CardDAV** - Auto-discovery redirects to Authelia SSO, not DAV endpoints
- ❌ **Mobile app incompatibility** - Nextcloud iOS/Android apps don't handle SSO redirects
- ❌ **Desktop client failures** - Sync clients expect HTTP Basic Auth, not OAuth
- ❌ **Third-party DAV clients** - Cannot authenticate (Calendars.app, Contacts.app, etc.)
- ❌ **Double authentication** - Users auth through Authelia, THEN Nextcloud native auth
- ❌ **Complex troubleshooting** - Two-layer auth makes debugging sync issues difficult

**Technical Blockers:**
```
iOS Calendar Setup:
1. User enters server: nextcloud.patriark.org
2. Client discovers /.well-known/caldav
3. Client follows redirect → gets Authelia login page (HTML)
4. Client expects DAV XML response → auth fails ❌
5. Calendar sync never works
```

**Decision:** ❌ **Rejected** - Fundamentally incompatible with CalDAV/CardDAV standards

---

### Option 2: Native Authentication (Nextcloud Handles Auth) ✅ **SELECTED**

**Implementation:**
- Nextcloud router does NOT include `authelia@file` middleware
- Layered security still applies:
  1. CrowdSec Bouncer (IP reputation - fail-fast)
  2. Rate limiting (200 req/min for WebDAV sync bursts)
  3. Circuit breaker (prevent cascade failures)
  4. Retry middleware (handle transient errors)
  5. CalDAV redirect middleware (/.well-known/ → /remote.php/dav/)
- Nextcloud native login with optional TOTP 2FA
- Brute-force protection via Nextcloud built-in mechanisms

**Pros:**
- ✅ **CalDAV/CardDAV works** - Auto-discovery routes directly to DAV endpoints
- ✅ **Mobile app compatibility** - iOS/Android Nextcloud apps authenticate natively
- ✅ **Desktop sync works** - HTTP Basic Auth supported out-of-box
- ✅ **Third-party clients** - Any CalDAV/CardDAV client works (Apple Calendar, Thunderbird, DAVx5)
- ✅ **Single authentication** - One login per device, no SSO redirect confusion
- ✅ **Simple troubleshooting** - Direct auth path, clear error messages
- ✅ **Built-in 2FA** - Nextcloud supports TOTP (Google Authenticator, Authy)
- ✅ **Proven pattern** - Aligns with ADR-005 (OCIS native auth decision)
- ✅ **Standards compliance** - RFC 4791/6352 CalDAV/CardDAV fully functional

**Cons:**
- ⚠️ **YubiKey via FIDO2 only** - Nextcloud supports WebAuthn/FIDO2 passwordless (see ADR-014), not Authelia's YubiKey integration
- ⚠️ **Separate user database** - Nextcloud users != Authelia users (manageable for family)
- ⚠️ **Per-service passwords** - Users have different credentials for Nextcloud vs Jellyfin (or can use passwordless - see ADR-014)

**Security Mitigations:**
1. **CrowdSec perimeter defense** - Malicious IPs blocked before reaching Nextcloud
2. **Rate limiting** - 200 req/min limit prevents brute-force (WebDAV sync headroom maintained)
3. **Nextcloud brute-force protection** - Built-in throttling after failed login attempts
4. **TOTP 2FA enforcement** - Can be required for all users or specific groups
5. **Strong password policy** - Enforced via Nextcloud password_policy app
6. **Session management** - Redis-backed sessions with configurable timeout
7. **Audit logging** - Nextcloud logs all authentication attempts

**Traefik Configuration:**
```yaml
# config/traefik/dynamic/routers.yml
nextcloud-secure:
  rule: "Host(`nextcloud.patriark.org`)"
  service: "nextcloud"
  middlewares:
    - crowdsec-bouncer@file        # [1] IP reputation (fail-fast)
    - rate-limit-ocis@file          # [2] 200 req/min (WebDAV headroom)
    - circuit-breaker@file          # [3] Prevent cascade failures
    - retry@file                    # [4] Transient error handling
    - nextcloud-caldav              # [5] /.well-known/ redirects
    # NO authelia@file!
    # NO security-headers@file! (Nextcloud sets own CSP)
```

**CalDAV/CardDAV Auto-Discovery:**
```yaml
# Middleware in routers.yml
nextcloud-caldav:
  redirectRegex:
    permanent: true
    regex: "^https://(.*)/.well-known/(card|cal)dav"
    replacement: "https://${1}/remote.php/dav/"
```

**Working Flow:**
```
iOS Calendar Setup:
1. User enters server: nextcloud.patriark.org
2. Client discovers /.well-known/caldav
3. Traefik redirects to /remote.php/dav/ (HTTP 308)
4. Client sends credentials via HTTP Basic Auth
5. Nextcloud validates credentials
6. Calendar sync works perfectly ✅
```

**Decision:** ✅ **Selected** - Enables full functionality while maintaining security

---

### Option 3: Hybrid Approach (SSO for Web, Native for DAV)

**Implementation:**
- Web UI (/) protected by Authelia
- DAV endpoints (/remote.php/dav) bypass Authelia
- Complex Traefik routing rules to differentiate

**Pros:**
- ✅ **Web UI SSO** - Centralized auth for browser access
- ✅ **DAV compatibility** - CalDAV/CardDAV works

**Cons:**
- ❌ **Complex configuration** - Multiple routers with path-based differentiation
- ❌ **Inconsistent UX** - Web uses SSO, apps use native (confusing)
- ❌ **Maintenance burden** - Two auth paths to troubleshoot and maintain
- ❌ **Sync client issues** - Desktop clients might try web paths first, fail
- ❌ **Security gaps** - Easy to misconfigure and leave endpoints unprotected

**Decision:** ❌ **Rejected** - Complexity not justified for marginal benefit

---

## Decision Outcome

**Selected Option:** **Option 2 - Native Authentication**

### Rationale

Nextcloud's primary value proposition is **cross-device file/calendar/contact sync**, not web UI access. The deployment succeeds or fails based on whether:
- iPhone Calendar can sync appointments
- iPad Contacts can sync phone numbers
- MacBook Air can sync files seamlessly
- Desktop clients can background-sync without authentication failures

**Authelia SSO fundamentally breaks these use cases.** While it provides excellent security for web-only services (Grafana, Jellyfin), it's incompatible with CalDAV/CardDAV standards that expect HTTP Basic Auth and direct endpoint access.

The decision aligns with **ADR-005 (OCIS Native Auth)**, establishing a pattern:

> **Services with native mobile/desktop clients OR CalDAV/CardDAV → Native authentication**
> **Services accessed primarily via web browser → Authelia SSO**

This creates clear criteria for future service deployments:
- **Web-first services** (Grafana, Jellyfin, Traefik dashboard) → Authelia SSO
- **Sync-first services** (Nextcloud, OCIS) → Native authentication
- **API-first services** (Prometheus) → Internal-only or IP whitelist

### Implementation Details

**Traefik Middleware Stack (No Authelia):**
```
Internet → Port 443 → Traefik
  ↓
[1] CrowdSec Bouncer (IP reputation check)
  ↓
[2] Rate Limit (200 req/min, burst 100)
  ↓
[3] Circuit Breaker (>30% network errors = open)
  ↓
[4] Retry (3 attempts, 100ms interval)
  ↓
[5] CalDAV Redirect (/.well-known/ → /remote.php/dav/)
  ↓
Nextcloud Native Auth (HTTP Basic or session cookie)
```

**Security Comparison:**

| Layer | Authelia SSO | Native Auth | Notes |
|-------|--------------|-------------|-------|
| **Perimeter** | CrowdSec | CrowdSec | ✅ Equal |
| **Rate Limiting** | 100 req/min | 200 req/min | Native has WebDAV headroom |
| **Primary Auth** | Authelia (YubiKey) | Nextcloud (FIDO2/WebAuthn) | ✅ Equal (see ADR-014) |
| **2FA** | YubiKey + TOTP | FIDO2 Passwordless (YubiKey) | ✅ Equal (ADR-014) |
| **Brute-Force** | Authelia throttle | Nextcloud throttle | ✅ Equal |
| **Session Security** | Authelia Redis | Nextcloud Redis | ✅ Equal |
| **Password Policy** | Authelia | Not applicable (passwordless) | Native advantage (no password) |

**Security Trade-off UPDATE (2025-12-20):** Initial assessment assumed TOTP-only 2FA. **ADR-014** documents that Nextcloud 30 supports FIDO2/WebAuthn passwordless authentication, providing **superior security** to Authelia SSO:
1. ✅ YubiKey support via FIDO2 passwordless (3 YubiKeys + Vaultwarden + Touch ID)
2. ✅ Complete phishing resistance (no password to phish)
3. ✅ Zero credential storage risk (public keys only)
4. ✅ CrowdSec perimeter defense remains active
5. ✅ Rate limiting prevents brute-force attempts

### Consequences

**Positive:**
- ✅ **Full device compatibility** - iOS, Android, macOS, Windows all sync reliably
- ✅ **CalDAV/CardDAV auto-discovery** - Standard-compliant implementation
- ✅ **Simple troubleshooting** - Single auth path, clear error messages
- ✅ **Proven pattern** - Aligns with OCIS decision (ADR-005)
- ✅ **User experience** - One login per device, no confusion

**Negative:**
- ⚠️ **Separate user management** - Nextcloud users managed independently
- ⚠️ **Different credentials** - Users have Nextcloud FIDO2 devices separate from Authelia credentials

**Mitigation Strategies:**

1. **User Management Overhead:**
   - Small user base (family/team) makes separate management acceptable
   - Nextcloud OCC CLI enables scriptable user provisioning
   - Group folders reduce per-user configuration

2. **Authentication Strategy (UPDATE: See ADR-014):**
   - ✅ **YubiKey support available** via FIDO2/WebAuthn passwordless
   - ✅ **Hardware MFA implemented** - 3 YubiKeys + Vaultwarden + Touch ID
   - ✅ **Phishing-resistant** - FIDO2 provides superior security to Authelia
   - ✅ **No password required** - Passwordless eliminates password attack surface

3. **Credential Fragmentation:**
   - Document clearly which services use which auth (Nextcloud vs Authelia)
   - Vaultwarden stores Nextcloud passkey for emergency access
   - Future: Investigate LDAP/SAML for unified identity (out of scope for now)

### Future Considerations

**UPDATE (2025-12-20): FIDO2/WebAuthn Support Confirmed**
- ✅ Nextcloud 30 supports FIDO2/WebAuthn passwordless authentication
- ✅ Implementation documented in ADR-014
- ✅ Native auth decision validated - correct choice for CalDAV/CardDAV compatibility

**If Authelia adds CalDAV/CardDAV proxy support:**
- Unlikely (not in Authelia's scope)
- Would require full DAV protocol implementation
- Re-evaluate decision if this becomes available

**For LDAP/SAML Integration (Future ADR):**
- Nextcloud supports LDAP backend
- Could unify Nextcloud + Authelia identity stores
- Trade-off: Complexity vs single-sign-on convenience
- Defer until user base grows beyond family scope

---

## Related Decisions

- **ADR-014:** Nextcloud Passwordless Authentication (FIDO2/WebAuthn implementation - supersedes TOTP 2FA recommendation)
- **ADR-005:** OCIS Native Authentication (same rationale applies)
- **ADR-002:** Systemd Quadlets Over Docker Compose (deployment pattern)
- **ADR-001:** Rootless Containers (security foundation)

---

## Compliance and Verification

**CalDAV/CardDAV RFC Compliance:**
- ✅ RFC 4791 (CalDAV) - Auto-discovery via /.well-known/caldav
- ✅ RFC 6352 (CardDAV) - Auto-discovery via /.well-known/carddav
- ✅ RFC 2518 (WebDAV) - HTTP Basic Auth for file sync
- ✅ RFC 5545 (iCalendar) - Calendar data format

**Tested Device Configurations:**
- ✅ iOS Calendar (native app)
- ✅ iOS Contacts (native app)
- ✅ macOS Calendar (native app)
- ✅ macOS Contacts (native app)
- ✅ Nextcloud iOS app
- ✅ Nextcloud desktop client (macOS)
- ✅ Nextcloud desktop client (Windows)

**Security Validation:**
```bash
# Verify CalDAV redirect works
curl -ILk https://nextcloud.patriark.org/.well-known/caldav
# Expected: HTTP/2 308 → HTTP/2 401 (auth required)

# Verify CardDAV redirect works
curl -ILk https://nextcloud.patriark.org/.well-known/carddav
# Expected: HTTP/2 308 → HTTP/2 401 (auth required)

# Verify DAV endpoint requires auth
curl -u admin:PASSWORD https://nextcloud.patriark.org/remote.php/dav/
# Expected: HTTP/2 207 Multi-Status (WebDAV)

# Verify rate limiting active
curl -I https://nextcloud.patriark.org/status.php
# Check headers for rate limit info
```

---

## Lessons Learned

1. **Authentication strategy must match service type:**
   - Web-first → SSO acceptable
   - Sync-first → Native auth required
   - Don't force SSO on services with mobile/desktop clients

2. **Standards compliance matters:**
   - CalDAV/CardDAV RFC specs assume direct endpoint access
   - HTTP Basic Auth is standard for WebDAV/CalDAV/CardDAV
   - Breaking standards breaks ecosystem compatibility

3. **Security is layered, not monolithic:**
   - SSO is one layer, not the only layer
   - CrowdSec + rate limiting + native auth = strong security
   - Perimeter defense (CrowdSec) matters more than SSO for public services

4. **User experience drives adoption:**
   - Complex auth flows = users avoid the service
   - Seamless device setup = service gets used daily
   - Security that breaks functionality = ignored security

5. **Document the "why" for future reference:**
   - "Why doesn't Nextcloud use Authelia like other services?"
   - This ADR answers that question comprehensively
   - Prevents future refactoring debates

---

**Last Updated:** 2025-12-20
**Author:** Claude Code (Sonnet 4.5)
**Reviewed By:** patriark
**Status:** Implemented and Validated
