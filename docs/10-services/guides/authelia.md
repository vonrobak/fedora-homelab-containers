# Authelia SSO & MFA Service Guide

**Last Updated:** 2025-11-11
**Service Type:** Authentication & Authorization
**Version:** 4.38
**Status:** Production

## Overview

Authelia is the SSO (Single Sign-On) and multi-factor authentication server protecting admin and media services. It provides YubiKey/WebAuthn-first authentication with TOTP fallback, replacing the previous TinyAuth system.

**Key Features:**
- Hardware-based phishing-resistant authentication (YubiKey FIDO2/WebAuthn)
- TOTP fallback for mobile devices
- Single sign-on across multiple services
- Granular access control (per-service policies)
- Session management with Redis backend
- Security events logging

**SSO Portal:** https://sso.patriark.org

## Architecture

### Service Components

```
┌─────────────┐
│   Browser   │
└──────┬──────┘
       │
       ▼
┌─────────────┐     ┌──────────────┐
│   Traefik   │────▶│   Authelia   │
│ (Reverse    │     │ (Port 9091)  │
│  Proxy)     │     └──────┬───────┘
└─────────────┘            │
                           ▼
                    ┌─────────────┐
                    │    Redis    │
                    │ (Sessions)  │
                    └─────────────┘
```

**Container:** `authelia`
**Image:** `docker.io/authelia/authelia:4.38`
**Networks:**
- `systemd-reverse_proxy` - Traefik communication
- `systemd-auth_services` - Redis communication

**Dependencies:**
- Redis (redis-authelia) - session storage
- Traefik - reverse proxy and routing

### Storage

**Configuration:** `~/containers/config/authelia/`
- `configuration.yml` - Main configuration (template in Git)
- `users_database.yml` - User credentials (GITIGNORED)

**Data:** `~/containers/data/authelia/`
- `db.sqlite3` - SQLite database (device registrations, TOTP secrets, security events)
- `notification.txt` - One-time codes for device registration

**Secrets:** Podman secrets (tmpfs, not persisted)
- `authelia_jwt_secret` - JWT token signing
- `authelia_session_secret` - Session cookie encryption
- `authelia_storage_key` - Database encryption

### Traefik Integration

**Middleware:** `authelia@file` in `/config/traefik/dynamic/middleware.yml`

```yaml
authelia:
  forwardAuth:
    address: "http://authelia:9091/api/verify?rd=https://sso.patriark.org"
    trustForwardHeader: true
    authResponseHeaders:
      - "Remote-User"
      - "Remote-Groups"
      - "Remote-Name"
      - "Remote-Email"
```

**Pattern:** ForwardAuth sends authentication requests to Authelia. If authenticated, Authelia returns headers and allows request. If not, redirects to SSO portal.

**Middleware stack:**
```yaml
middlewares:
  - crowdsec-bouncer    # 1. IP reputation
  - rate-limit          # 2. Request throttling
  - authelia@file       # 3. Authentication
```

## Protected Services

### Tier 1: Admin Services (YubiKey Required)

| Service | Domain | Policy |
|---------|--------|--------|
| Grafana | grafana.patriark.org | two_factor |
| Prometheus | prometheus.patriark.org | two_factor |
| Loki | loki.patriark.org | two_factor |
| Traefik Dashboard | traefik.patriark.org | two_factor |

**Required group:** `admins`

### Tier 2: Media Services (Conditional)

**Jellyfin (jellyfin.patriark.org):**
- Web UI: Requires YubiKey authentication
- Mobile apps: API endpoints bypass Authelia (native authentication)

**Immich (photos.patriark.org):**
- NOT protected by Authelia
- Uses native authentication (web + mobile)
- Reason: Dual-auth UX issues, mobile app compatibility

### Bypass Rules

**Health check endpoints:** All services
```yaml
resources:
  - '^/api/health$'
  - '^/health$'
  - '^/ping$'
```

**Jellyfin API endpoints:** Mobile app compatibility
```yaml
resources:
  - '^/api/.*'
  - '^/System/.*'
  - '^/Sessions/.*'
  - '^/Users/.*/Authenticate'
```

## Authentication Methods

### Primary: WebAuthn/FIDO2 (YubiKey)

**Enrolled devices:**
- YubiKey 5 NFC
- YubiKey 5C Nano

**Authentication flow:**
1. Navigate to protected service
2. Redirected to https://sso.patriark.org
3. Enter username + password
4. Browser prompts for YubiKey touch (and possibly PIN)
5. Touch YubiKey
6. Redirected back to service

**PIN requirement:** Depends on YubiKey configuration. If PIN set, browser prompts for PIN before touch.

### Fallback: TOTP (Time-Based One-Time Password)

**Enrolled device:**
- Microsoft Authenticator (mobile)

**Use cases:**
- Mobile browser access (WebAuthn/NFC limited support)
- Backup if YubiKeys unavailable
- Testing authentication flow

**Authentication flow:** Same as WebAuthn, but enter 6-digit code instead of YubiKey touch.

### Base: Username + Password

**User:** `patriark`
**Password:** Argon2id hashed in `users_database.yml`
**Groups:** `admins`, `users`

**Why passwords required:** Authelia needs credential establishment before WebAuthn enrollment. Provides recovery if all YubiKeys lost.

## Session Management

### Session Lifecycle

**Storage:** Redis (redis-authelia container)
**Cookie name:** `authelia_session`
**Cookie domain:** `.patriark.org` (covers all subdomains)

**Timeouts:**
- **Expiration:** 1 hour (absolute)
- **Inactivity:** 15 minutes
- **Remember me:** 1 month (optional checkbox at login)

**Session flow:**
1. User authenticates with YubiKey
2. Authelia creates session in Redis
3. Browser receives session cookie
4. Subsequent requests to ANY protected service use existing session (SSO!)
5. Session expires after 1 hour OR 15 minutes of inactivity
6. User must re-authenticate

### Session Security

**Cookie attributes:**
- `SameSite: lax` - CSRF protection
- `Secure: true` - HTTPS only
- `HttpOnly: true` - No JavaScript access

**Session data encrypted:** Yes (via `authelia_session_secret`)

## User Management

### Password Operations

#### Change Password (Hash Generation)

**Method 1: Interactive (Recommended)**
```bash
podman exec -it authelia authelia crypto hash generate argon2 --random
# Prompts for password securely (no shell history)
```

**Method 2: Command-line**
```bash
podman exec -it authelia authelia crypto hash generate argon2 --password 'NEW_PASSWORD'
```

**Output example:**
```
Password hash: $argon2id$v=19$m=65536,t=3,p=4$BASE64SALT$BASE64HASH
```

**Apply password:**
1. Copy hash output
2. Edit `~/containers/config/authelia/users_database.yml`
3. Replace password line:
   ```yaml
   users:
     patriark:
       password: $argon2id$v=19$m=65536,t=3,p=4$BASE64SALT$BASE64HASH
   ```
4. Restart Authelia:
   ```bash
   systemctl --user restart authelia.service
   ```

**Configuration watch:** Authelia watches `users_database.yml` for changes. Restart ensures immediate reload.

### YubiKey Management

#### Enroll YubiKey

1. Navigate to https://sso.patriark.org/settings
2. Authenticate with username + password
3. Click "Two-Factor Authentication" section
4. Click "Register Security Key"
5. Browser prompts for key insertion (if not already inserted)
6. Browser may prompt for PIN (if YubiKey configured with PIN)
7. Touch YubiKey when LED flashes
8. Confirm enrollment

**Troubleshooting enrollment failures:**
- Clear browser site data: History → Manage History → Right-click `sso.patriark.org` → "Forget About This Site"
- Try different browser (Firefox, Vivaldi, Chrome)
- Check YubiKey firmware version (some variants may have limitations)

#### Remove YubiKey

**Web UI:** https://sso.patriark.org/settings → Two-Factor Authentication → Click trash icon next to device

**Database method (if UI unavailable):**
1. Stop Authelia: `systemctl --user stop authelia.service`
2. Backup database: `cp ~/containers/data/authelia/db.sqlite3 ~/containers/data/authelia/db.sqlite3.backup`
3. Edit database with SQLite client
4. Restart Authelia: `systemctl --user start authelia.service`

**Caution:** Direct database editing risky. Use web UI when possible.

### TOTP Management

#### Enroll TOTP Device

1. Navigate to https://sso.patriark.org/settings
2. Authenticate with username + password
3. Click "Two-Factor Authentication" section
4. Click "Add TOTP"
5. Scan QR code with authenticator app (Microsoft Authenticator, Google Authenticator, Authy)
6. Enter 6-digit code to verify
7. Confirm enrollment

**OTP code for confirmation:** Check `~/containers/data/authelia/notification.txt` if using filesystem notifier.

#### Remove TOTP Device

**Web UI:** https://sso.patriark.org/settings → Two-Factor Authentication → Click trash icon next to TOTP device

## Device Registration

### Registration Workflow

When enrolling YubiKey or TOTP, Authelia may send one-time codes for verification.

**Filesystem notifier configured:** Codes written to file instead of email.

**Retrieve codes:**
```bash
cat ~/containers/data/authelia/notification.txt
```

**Example output:**
```
A6HFV4AV
V6KLAAKR
```

**Usage:** Enter code when prompted during device registration.

**Security note:** This file contains sensitive one-time codes. Restrict access:
```bash
chmod 600 ~/containers/data/authelia/notification.txt
```

## Access Control

### Policy Types

**bypass:** No authentication required
- Use case: Health checks, public endpoints

**one_factor:** Username + password only
- Use case: Low-security services (none currently)

**two_factor:** Username + password + YubiKey/TOTP
- Use case: Admin services, media web UIs

**deny:** Explicit denial
- Use case: Default policy (fail-secure)

### Policy Configuration

**File:** `~/containers/config/authelia/configuration.yml`

**Structure:**
```yaml
access_control:
  default_policy: deny  # Fail-secure

  rules:
    # Order matters! First matching rule wins

    # Bypass health checks
    - domain: '*.patriark.org'
      policy: bypass
      resources:
        - '^/api/health$'

    # Protect admin services
    - domain:
        - 'grafana.patriark.org'
        - 'prometheus.patriark.org'
      policy: two_factor
      subject:
        - 'group:admins'

    # Jellyfin API bypass (mobile apps)
    - domain: 'jellyfin.patriark.org'
      policy: bypass
      resources:
        - '^/api/.*'

    # Jellyfin web UI protection
    - domain: 'jellyfin.patriark.org'
      policy: two_factor
      subject:
        - 'group:users'
```

**Rule matching:**
1. First rule that matches domain + resource wins
2. More specific rules MUST come before general rules
3. `default_policy` applies if no rules match

### Subject Matching

**By group:**
```yaml
subject:
  - 'group:admins'
  - 'group:users'
```

**By user:**
```yaml
subject:
  - 'user:patriark'
```

**Any authenticated user:**
```yaml
# Omit subject field entirely
policy: two_factor
```

### Resource Matching

**Regex patterns:**
```yaml
resources:
  - '^/api/.*'              # All /api/ paths
  - '^/health$'             # Exact /health
  - '^/admin/.*\.php$'      # PHP files in /admin/
```

**Regex syntax:** Go regex (similar to PCRE)

**Testing regex:** Use https://regex101.com/ with "Golang" flavor

## Operations

### Service Management

**Status:**
```bash
systemctl --user status authelia.service
```

**Logs:**
```bash
# Follow logs
podman logs -f authelia

# Last 50 lines
podman logs authelia --tail 50

# journalctl method
journalctl --user -u authelia.service -f
```

**Restart:**
```bash
systemctl --user restart authelia.service
```

**Stop/Start:**
```bash
systemctl --user stop authelia.service
systemctl --user start authelia.service
```

### Health Checks

**Container health:**
```bash
podman healthcheck run authelia
# healthy
```

**HTTP health endpoint:**
```bash
curl -f http://localhost:9091/api/health
# {"status":"UP"}
```

**Metrics endpoint:**
```bash
curl http://localhost:9091/api/health
# Prometheus-formatted metrics
```

### Configuration Reload

**File watch enabled:** Authelia watches `configuration.yml` and `users_database.yml` for changes.

**Automatic reload:** Changes detected and applied automatically (30-second delay).

**Force reload:** Restart service to guarantee immediate reload:
```bash
systemctl --user restart authelia.service
```

**Traefik dynamic config:** No Authelia restart needed. Traefik watches `/config/traefik/dynamic/` and reloads automatically.

### Database Operations

#### Backup Database

**Manual backup:**
```bash
cp ~/containers/data/authelia/db.sqlite3 \
   ~/containers/data/authelia/db.sqlite3.backup-$(date +%Y%m%d)
```

**BTRFS snapshot method:**
```bash
sudo btrfs subvolume snapshot \
  /mnt/btrfs-pool/subvol7-containers \
  /mnt/btrfs-pool/snapshots/containers-$(date +%Y%m%d-%H%M)
```

**What's stored in database:**
- WebAuthn device registrations (YubiKey public keys)
- TOTP secrets
- Security events history
- User preferences

**Backup frequency:** Daily BTRFS snapshots (included in homelab backup strategy).

#### Inspect Database

**SQLite client:**
```bash
podman exec -it authelia sqlite3 /data/db.sqlite3
```

**Useful queries:**
```sql
-- List tables
.tables

-- Show registered devices
SELECT * FROM webauthn_devices;

-- Show TOTP devices
SELECT * FROM totp_configurations;

-- Show authentication logs
SELECT * FROM authentication_logs ORDER BY time DESC LIMIT 10;

-- Exit
.quit
```

**Caution:** Read-only queries safe. Modifications may break Authelia.

#### Reset Database

**Use case:** Corrupted database, testing, secret key change

**Steps:**
1. Stop Authelia:
   ```bash
   systemctl --user stop authelia.service
   ```

2. Backup database:
   ```bash
   cp ~/containers/data/authelia/db.sqlite3 ~/containers/data/authelia/db.sqlite3.old
   ```

3. Delete database:
   ```bash
   rm ~/containers/data/authelia/db.sqlite3
   ```

4. Start Authelia (creates new database):
   ```bash
   systemctl --user start authelia.service
   ```

5. Re-enroll all YubiKeys and TOTP devices

**Impact:** All device registrations lost. Users must re-enroll 2FA devices.

### Session Operations

#### View Active Sessions

**Redis client:**
```bash
podman exec -it redis-authelia redis-cli
```

**Commands:**
```redis
# Count sessions
DBSIZE

# List all keys (sessions)
KEYS *

# View session data (encrypted)
GET <key>

# Exit
quit
```

**Note:** Session data encrypted. Can verify sessions exist but not read contents.

#### Force Logout (Clear All Sessions)

**Method 1: Restart Redis (fastest)**
```bash
systemctl --user restart redis-authelia.service
```

**Impact:** All users logged out immediately. Must re-authenticate.

**Method 2: Flush Redis database**
```bash
podman exec -it redis-authelia redis-cli FLUSHDB
```

**Method 3: User self-logout**
- Navigate to https://sso.patriark.org
- Click "Logout" button
- Session cookie cleared, Redis session deleted

#### Session Monitoring

**Redis stats:**
```bash
podman exec redis-authelia redis-cli INFO stats
```

**Key metrics:**
- `keyspace_hits` - Successful session lookups
- `keyspace_misses` - Session not found (expired or invalid)
- `expired_keys` - Sessions auto-expired by Redis

**Memory usage:**
```bash
podman exec redis-authelia redis-cli INFO memory
```

## Troubleshooting

### Authentication Issues

#### "There was an issue retrieving the current user state"

**Symptoms:** Browser shows error, SSO portal won't load.

**Causes:**
1. **Rate limiting too strict** - Assets blocked
2. **Browser cache issues** - Old config cached
3. **Authelia not running** - Service down

**Diagnosis:**
```bash
# Check Authelia running
systemctl --user status authelia.service

# Check rate limiting (Traefik logs)
podman logs traefik | grep 429

# Check Authelia health
curl http://localhost:9091/api/health
```

**Fix 1: Rate limit adjustment**

Edit `/config/traefik/dynamic/routers.yml`:
```yaml
authelia-portal:
  middlewares:
    - crowdsec-bouncer
    - rate-limit  # Use 100 req/min, NOT rate-limit-auth (10 req/min)
```

Traefik auto-reloads. Test in browser.

**Fix 2: Clear browser cache**

Firefox: History → Manage History → Right-click `sso.patriark.org` → "Forget About This Site"

**Fix 3: Restart Authelia**
```bash
systemctl --user restart authelia.service
```

#### YubiKey Touch Not Registering

**Symptoms:** Touch YubiKey, LED lights up, but browser doesn't register touch.

**Cause:** Browser cached old WebAuthn configuration.

**Fix:**
1. Clear browser site data (see above)
2. Close all browser tabs for `sso.patriark.org`
3. Restart browser
4. Navigate to https://sso.patriark.org
5. Retry authentication

**Alternative:** Try different browser (Firefox, Vivaldi, Chrome).

#### "You cancelled the attestation request"

**Symptoms:** YubiKey enrollment fails with this error.

**Causes:**
1. Hardware/firmware limitation (some YubiKey variants)
2. Browser incompatibility
3. WebAuthn configuration too strict

**Troubleshooting:**
1. Try different browser
2. Try different YubiKey (if multiple available)
3. Relax WebAuthn settings (not recommended for production):
   ```yaml
   webauthn:
     attestation_conveyance_preference: none
     user_verification: discouraged
   ```

**Acceptable workaround:** 2 YubiKeys + TOTP provides sufficient redundancy. Third YubiKey failure acceptable.

#### Redirect Loop (sso.patriark.org ↔ service)

**Symptoms:** Browser keeps redirecting between SSO portal and service, never loads.

**Causes:**
1. Session cookie not being set
2. `default_redirection_url` equals `authelia_url`
3. Browser blocking third-party cookies

**Diagnosis:**
```bash
# Check session configuration
grep -A5 "cookies:" ~/containers/config/authelia/configuration.yml
```

**Fix:** Ensure `default_redirection_url` ≠ `authelia_url`:
```yaml
cookies:
  - domain: patriark.org
    authelia_url: https://sso.patriark.org
    default_redirection_url: https://grafana.patriark.org  # Different!
```

**Browser cookies:** Ensure browser allows cookies for `*.patriark.org`.

### Service Access Issues

#### 403 Forbidden After Authentication

**Symptoms:** Authenticated with YubiKey, but service returns 403.

**Causes:**
1. User not in required group
2. Access control rule mismatch
3. Middleware ordering issue

**Diagnosis:**
```bash
# Check Authelia logs for authorization decision
podman logs authelia | grep -i "access denied"

# Check user groups
grep -A10 "users:" ~/containers/config/authelia/users_database.yml
```

**Fix 1: Add user to group**

Edit `users_database.yml`:
```yaml
users:
  patriark:
    groups:
      - admins  # Required for admin services
      - users
```

Restart Authelia:
```bash
systemctl --user restart authelia.service
```

**Fix 2: Review access control rules**

Check `configuration.yml` access_control section. Ensure service domain + user group matches a rule.

#### Service Returns 500 Internal Server Error

**Symptoms:** Authentication succeeds, but backend service errors.

**Cause:** Backend service issue (NOT Authelia).

**Diagnosis:**
```bash
# Check backend service logs
podman logs <service-name>

# Example
podman logs grafana
```

**Fix:** Troubleshoot backend service directly.

### Mobile App Issues

#### Jellyfin App "Server Not Reachable"

**Symptoms:** Mobile app can't connect after Authelia deployment.

**Cause:** API endpoints not in bypass rules.

**Fix:** Ensure bypass rules in `configuration.yml`:
```yaml
- domain: 'jellyfin.patriark.org'
  policy: bypass
  resources:
    - '^/api/.*'
    - '^/System/.*'
    - '^/Sessions/.*'
    - '^/Users/.*/Authenticate'
```

**Order matters:** Bypass rule MUST come BEFORE two_factor rule.

**Verification:**
```bash
# Test API endpoint (should not redirect)
curl -I https://jellyfin.patriark.org/api/health
# HTTP/1.1 200 OK (no redirect to SSO)
```

#### Immich App Dual Authentication

**Symptoms:** App prompts for Authelia authentication, then Immich native login (confusing).

**Recommendation:** Remove Authelia from Immich entirely. Use native authentication.

**Fix:**
1. Remove Immich rules from `configuration.yml`
2. Remove `authelia@file` from Immich router in Traefik config
3. Restart Authelia and verify Traefik config reloaded

**Result:** Consistent native authentication for web + mobile.

### Database Issues

#### "encryption key does not appear to be valid for this database"

**Symptoms:** Authelia won't start, logs show encryption error.

**Cause:** `authelia_storage_key` secret changed, but database created with old key.

**Fix:**
1. Stop Authelia: `systemctl --user stop authelia.service`
2. Backup database: `cp ~/containers/data/authelia/db.sqlite3 ~/containers/data/authelia/db.sqlite3.old`
3. Delete database: `rm ~/containers/data/authelia/db.sqlite3`
4. Start Authelia: `systemctl --user start authelia.service` (creates new database)
5. Re-enroll all YubiKeys and TOTP devices

**Prevention:** Don't change `authelia_storage_key` secret after initial deployment.

#### Database Corruption

**Symptoms:** Authelia crashes, SQLite errors in logs.

**Diagnosis:**
```bash
podman exec -it authelia sqlite3 /data/db.sqlite3 "PRAGMA integrity_check;"
```

**Fix:**
1. Stop Authelia
2. Restore from BTRFS snapshot or backup
3. Start Authelia

**If no backup:** Reset database (see "Reset Database" above).

### Redis Issues

#### Redis Not Reachable

**Symptoms:** Authelia logs show "connection refused" to Redis.

**Diagnosis:**
```bash
# Check Redis running
systemctl --user status redis-authelia.service

# Check Redis health
podman exec redis-authelia redis-cli ping
# PONG

# Check network connectivity
podman exec authelia ping redis-authelia
```

**Fix:**
```bash
systemctl --user restart redis-authelia.service
systemctl --user restart authelia.service
```

#### Redis Memory Full

**Symptoms:** Sessions not being created, Redis logs show OOM errors.

**Diagnosis:**
```bash
podman exec redis-authelia redis-cli INFO memory
# used_memory_human: 128.00M (at limit)
```

**Fix 1: Increase memory limit**

Edit `redis-authelia.container`:
```ini
Exec=redis-server --maxmemory 256mb ...
```

Restart Redis:
```bash
systemctl --user daemon-reload
systemctl --user restart redis-authelia.service
```

**Fix 2: Flush old sessions**
```bash
podman exec redis-authelia redis-cli FLUSHDB
```

**Prevention:** LRU eviction policy configured - should auto-evict old sessions.

## Configuration Reference

### WebAuthn Settings

```yaml
webauthn:
  disable: false
  timeout: 60s                               # How long to wait for YubiKey touch
  display_name: Patriark Homelab             # Shown in browser prompt
  attestation_conveyance_preference: indirect  # Privacy vs verification balance
  user_verification: preferred               # Request PIN but don't require
```

**Attestation options:**
- `none` - Maximum privacy (no hardware verification)
- `indirect` - Balanced (default)
- `direct` - Full hardware verification (least privacy)

**User verification options:**
- `discouraged` - No PIN required
- `preferred` - Request PIN if available (default)
- `required` - PIN mandatory

### TOTP Settings

```yaml
totp:
  disable: false
  issuer: patriark.org                       # Shown in authenticator app
  algorithm: sha1                            # Standard (sha1/sha256/sha512)
  digits: 6                                  # Code length
  period: 30                                 # Seconds per code
  skew: 1                                    # Allow ±1 period for clock drift
```

### Session Settings

```yaml
session:
  secret: file:///run/secrets/authelia_session_secret
  name: authelia_session                     # Cookie name
  same_site: lax                             # CSRF protection (lax/strict/none)
  expiration: 1h                             # Absolute timeout
  inactivity: 15m                            # Idle timeout
  remember_me: 1M                            # "Remember me" checkbox duration

  cookies:
    - domain: patriark.org                   # Cookie domain (covers *.patriark.org)
      authelia_url: https://sso.patriark.org
      default_redirection_url: https://grafana.patriark.org

  redis:
    host: redis-authelia
    port: 6379
    database_index: 0
    maximum_active_connections: 8
    minimum_idle_connections: 0
```

### Password Hashing Settings

```yaml
authentication_backend:
  file:
    password:
      algorithm: argon2
      argon2:
        variant: argon2id                    # Most secure variant
        iterations: 3                        # Time cost
        memory: 65536                        # Memory cost (KB)
        parallelism: 4                       # CPU cores
        key_length: 32                       # Hash length
        salt_length: 16                      # Salt length
```

**Security note:** These settings balance security vs performance. Argon2id resists GPU cracking attacks.

## Monitoring

### Metrics

**Prometheus endpoint:** `http://authelia:9091/metrics`

**Key metrics:**
- `authelia_authentication_success_total` - Successful logins
- `authelia_authentication_failure_total` - Failed logins
- `authelia_request_duration_seconds` - Response time
- `authelia_webauthn_credential_verifications_total` - YubiKey verifications

**Grafana dashboard:** Import official Authelia dashboard or create custom.

### Logs

**Log level:** `debug` (production should use `info`)

**Change log level:** Edit `configuration.yml`:
```yaml
log:
  level: info  # debug, info, warn, error
  format: text  # text or json
```

**Common log patterns:**

**Successful authentication:**
```
level=info msg="Successful authentication" username=patriark remote_ip=62.249.184.112
```

**Failed authentication:**
```
level=warn msg="Authentication attempt failed" username=patriark reason="invalid credentials"
```

**YubiKey verification:**
```
level=debug msg="WebAuthn credential verified" username=patriark device=YubiKey-5-NFC
```

**Session creation:**
```
level=debug msg="Session created" username=patriark expiration=2025-11-11T14:30:00Z
```

## Security Considerations

### Threat Model

**Protected against:**
- ✅ Password phishing (YubiKey FIDO2 phishing-resistant)
- ✅ Credential stuffing (2FA required)
- ✅ Session hijacking (short timeouts, encrypted cookies)
- ✅ Brute force (rate limiting + account lockout)
- ✅ MITM (TLS encryption)

**Not protected against:**
- ❌ Physical access to YubiKey (PIN provides some protection)
- ❌ Malware on client device (can steal session cookies)
- ❌ Social engineering (user-dependent)

### Best Practices

1. **YubiKey PIN:** Set PIN on YubiKeys for physical theft protection
2. **Session timeouts:** Keep short (1 hour max) for high-security environments
3. **Log monitoring:** Alert on repeated failed login attempts
4. **Database backups:** Include in regular backup strategy (contains 2FA secrets)
5. **Secret rotation:** Periodically rotate JWT/session secrets (requires re-authentication)

### Incident Response

**Suspected compromised account:**
1. Force logout: `systemctl --user restart redis-authelia.service`
2. Change password (see "Password Operations")
3. Review authentication logs for suspicious activity
4. Consider removing and re-enrolling YubiKeys

**Lost YubiKey:**
1. Login with remaining YubiKey or TOTP
2. Navigate to https://sso.patriark.org/settings
3. Remove lost YubiKey
4. Verify remaining 2FA devices functional

**Suspected database compromise:**
1. Stop Authelia immediately
2. Analyze database for unauthorized changes
3. Restore from known-good backup
4. Rotate all secrets
5. Force all users to re-enroll 2FA devices

## Related Documentation

- **Architecture Decision:** `/docs/30-security/decisions/2025-11-11-decision-005-authelia-sso-yubikey-deployment.md`
- **Deployment Journal:** `/docs/30-security/journal/2025-11-11-authelia-deployment.md`
- **Traefik Configuration:** `/docs/00-foundation/guides/middleware-configuration.md`
- **Redis Operations:** `/docs/10-services/guides/redis.md` (if exists)

## Quick Reference

### Common Commands

```bash
# Service management
systemctl --user status authelia.service
systemctl --user restart authelia.service
podman logs -f authelia

# Health checks
podman healthcheck run authelia
curl http://localhost:9091/api/health

# Password hash generation
podman exec -it authelia authelia crypto hash generate argon2 --random

# Database backup
cp ~/containers/data/authelia/db.sqlite3 ~/containers/data/authelia/db.sqlite3.backup

# Session management
systemctl --user restart redis-authelia.service  # Force logout all users

# Configuration reload
systemctl --user restart authelia.service  # After editing configuration.yml

# View notification codes
cat ~/containers/data/authelia/notification.txt
```

### URLs

- **SSO Portal:** https://sso.patriark.org
- **Settings:** https://sso.patriark.org/settings
- **Logout:** https://sso.patriark.org/logout
- **Health Check:** http://localhost:9091/api/health (internal)
- **Metrics:** http://localhost:9091/metrics (internal)

### Files

- **Quadlet:** `~/.config/containers/systemd/authelia.container`
- **Main config:** `~/containers/config/authelia/configuration.yml`
- **Users:** `~/containers/config/authelia/users_database.yml` (gitignored)
- **Database:** `~/containers/data/authelia/db.sqlite3`
- **Notifications:** `~/containers/data/authelia/notification.txt`
- **Traefik middleware:** `~/containers/config/traefik/dynamic/middleware.yml`
- **Traefik routers:** `~/containers/config/traefik/dynamic/routers.yml`
