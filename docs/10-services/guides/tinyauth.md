# TinyAuth Authentication Service

**Last Updated:** 2025-11-07
**Version:** Custom (lightweight forward auth)
**Status:** Production
**Networks:** reverse_proxy, auth_services

---

## Overview

TinyAuth is a **lightweight forward authentication service** providing centralized authentication for all Traefik-routed services.

**Key features:**
- Forward authentication compatible with Traefik
- Simple username/password authentication
- Session management
- Minimal resource footprint (~15MB RAM)
- SQLite backend (no separate database needed)

**Integration:** Works with Traefik's `forwardAuth` middleware

---

## Quick Reference

### Access Points

- **Auth endpoint:** http://tinyauth:3000/auth (internal only)
- **Login page:** Appears automatically when accessing protected services
- **Status:** Check via Traefik dashboard

### Service Management

```bash
# Status
systemctl --user status tinyauth.service
podman ps | grep tinyauth

# Control
systemctl --user restart tinyauth.service
systemctl --user stop tinyauth.service
systemctl --user start tinyauth.service

# Logs
journalctl --user -u tinyauth.service -f
podman logs -f tinyauth
```

### Configuration

```
Location: ~/containers/data/tinyauth/
└── tinyauth.db  # SQLite database (users, sessions)
```

---

## Architecture

### Authentication Flow

```
User requests protected service (e.g., jellyfin.patriark.org)
  ↓
Traefik intercepts request
  ↓
Checks tinyauth middleware
  ↓
Forwards to TinyAuth: http://tinyauth:3000/auth
  ↓
TinyAuth checks session cookie
  │
  ├─ Valid session → Returns 200 OK → Traefik allows request
  └─ No/invalid session → Returns 401 → Traefik shows login page
```

### Network Topology

```
systemd-auth_services (10.89.3.0/24)
├── TinyAuth (authentication backend)
└── Traefik (can reach TinyAuth for auth checks)

systemd-reverse_proxy (10.89.2.0/24)
├── TinyAuth (serves login page)
└── Traefik
```

**Why two networks?**
- `auth_services`: Backend auth checks (Traefik → TinyAuth)
- `reverse_proxy`: Serve login page to users

---

## Configuration

### Traefik Integration

**Middleware definition** (`config/traefik/dynamic/middleware.yml`):

```yaml
http:
  middlewares:
    tinyauth:
      forwardAuth:
        address: "http://tinyauth:3000/auth"
        trustForwardHeader: true
        authResponseHeaders:
          - X-Forwarded-User
```

**Apply to routes** (`config/traefik/dynamic/routers.yml`):

```yaml
http:
  routers:
    jellyfin-secure:
      middlewares:
        - crowdsec-bouncer@file
        - rate-limit@file
        - tinyauth@file          # Authentication layer
        - security-headers@file
```

### User Management

**Currently:** Manual database modification (no admin UI)

**Add user:**
```bash
# Access database
sqlite3 ~/containers/data/tinyauth/tinyauth.db

# Create user (password should be bcrypt hashed)
INSERT INTO users (username, password_hash) VALUES ('username', 'bcrypt_hash');

# Exit
.exit
```

**Generate bcrypt hash:**
```bash
# Using Python
python3 -c "import bcrypt; print(bcrypt.hashpw(b'password', bcrypt.gensalt()).decode())"

# Or using htpasswd
htpasswd -nbBC 12 USER PASSWORD | cut -d: -f2
```

---

## Operations

### Adding Protected Service

**In Traefik router configuration:**

```yaml
http:
  routers:
    newservice-secure:
      rule: "Host(`newservice.patriark.org`)"
      middlewares:
        - crowdsec-bouncer@file
        - rate-limit@file
        - tinyauth@file          # Add this line
        - security-headers@file
```

**That's it!** TinyAuth will automatically protect the service.

### Removing Authentication

**To make a service public:**

Remove `tinyauth@file` from middleware chain:

```yaml
http:
  routers:
    publicservice-secure:
      middlewares:
        - crowdsec-bouncer@file
        - rate-limit@file
        # - tinyauth@file        # Removed
        - security-headers@file
```

### Session Management

**Session storage:** In-memory (lost on restart)

**Session duration:** Configurable (default: 24 hours)

**Force logout all users:**
```bash
# Restart TinyAuth (clears sessions)
systemctl --user restart tinyauth.service
```

---

## Troubleshooting

### Login Loop (Redirects Forever)

**Symptoms:**
- Login page appears
- Enter credentials
- Redirects back to login page

**Causes:**
1. **Traefik not on auth_services network**
   ```bash
   podman inspect traefik | grep -A 10 Networks
   # Must show systemd-auth_services
   ```

2. **TinyAuth not reachable from Traefik**
   ```bash
   podman exec traefik wget -O- http://tinyauth:3000/auth
   # Should not timeout
   ```

3. **Cookie domain mismatch**
   - Check TinyAuth logs for cookie errors
   - Verify `X-Forwarded-Host` header passed correctly

### Authentication Not Required

**Service accessible without login:**

1. **Check middleware applied:**
   ```bash
   curl http://localhost:8080/api/http/routers/servicename@file | grep middlewares
   # Should show: tinyauth@file
   ```

2. **Check middleware exists:**
   ```bash
   curl http://localhost:8080/api/http/middlewares/tinyauth@file
   # Should return middleware definition
   ```

3. **Verify TinyAuth running:**
   ```bash
   systemctl --user status tinyauth.service
   podman logs tinyauth | tail -20
   ```

### Can't Login (Invalid Credentials)

**Check user exists:**
```bash
sqlite3 ~/containers/data/tinyauth/tinyauth.db "SELECT username FROM users;"
```

**Check password hash:**
```bash
# Compare entered password hash with database
sqlite3 ~/containers/data/tinyauth/tinyauth.db \
  "SELECT username, password_hash FROM users WHERE username='youruser';"
```

**Reset password:**
```bash
# Generate new bcrypt hash
NEW_HASH=$(python3 -c "import bcrypt; print(bcrypt.hashpw(b'newpassword', bcrypt.gensalt()).decode())")

# Update database
sqlite3 ~/containers/data/tinyauth/tinyauth.db \
  "UPDATE users SET password_hash='$NEW_HASH' WHERE username='youruser';"
```

---

## Security Considerations

### Session Security

**Current implementation:**
- Sessions stored in memory (not persistent)
- Session cookies with `HttpOnly` and `Secure` flags
- CSRF protection (if implemented)

**Limitations:**
- Restart clears all sessions (users must re-login)
- No distributed session store (single host only)

**Improvements (future):**
- Redis for persistent sessions
- Configurable session timeout
- Automatic session cleanup

### Password Storage

**bcrypt hashing:**
- Industry-standard password hashing
- Configurable work factor (cost)
- Salted automatically

**Best practices:**
- Minimum 12-round bcrypt cost
- Enforce strong passwords
- No password recovery (must reset manually)

### Network Isolation

**Critical:** TinyAuth should ONLY be accessible via Traefik

**Verify:**
```bash
# Should timeout from internet
curl http://tinyauth:3000/auth
# (only works from containers on same network)
```

**Never expose TinyAuth directly to internet!**

---

## Monitoring

### Health Checks

**No built-in health endpoint** (lightweight service)

**Check if responding:**
```bash
# From Traefik container
podman exec traefik wget -O- http://tinyauth:3000/auth
# Should return 401 (unauthorized) - means service is up
```

### Performance

**Resource usage:**
- RAM: ~15MB
- CPU: <1% (minimal)
- Network: Only during auth checks

**Monitor:**
```bash
podman stats tinyauth
```

### Logs

**Authentication attempts:**
```bash
podman logs tinyauth | grep -i "auth"
```

**Failures:**
```bash
podman logs tinyauth | grep -i "failed\|error"
```

---

## Backup and Recovery

### What to Backup

**Critical:**
- `~/containers/data/tinyauth/tinyauth.db` (user database)

**Not needed:**
- Sessions (in-memory, not persistent)
- Container (recreate from quadlet)

### Backup Procedure

```bash
# Simple backup
cp ~/containers/data/tinyauth/tinyauth.db ~/backups/tinyauth-$(date +%Y%m%d).db

# Or include in automated backup
# (already covered by BTRFS snapshot of home directory)
```

### Restore Procedure

```bash
# 1. Stop TinyAuth
systemctl --user stop tinyauth.service

# 2. Restore database
cp ~/backups/tinyauth-YYYYMMDD.db ~/containers/data/tinyauth/tinyauth.db

# 3. Restart
systemctl --user start tinyauth.service
```

---

## Upgrade / Replacement

**TinyAuth is a placeholder** for future SSO solution.

### Migration to Authelia (Planned)

**When ready:**
1. Deploy Authelia service
2. Update Traefik middleware to point to Authelia
3. Migrate users to Authelia
4. Test authentication
5. Remove TinyAuth

**Benefits of Authelia:**
- 2FA support (TOTP, WebAuthn)
- LDAP/Active Directory integration
- More features and better UI
- Active development

**Keep TinyAuth for now:**
- Works well for current needs
- Minimal overhead
- Simple to troubleshoot

---

## Related Documentation

- **TinyAuth guide (extended):** `docs/30-security/guides/tinyauth.md`
- **Traefik integration:** `docs/10-services/guides/traefik.md`
- **Middleware configuration:** `docs/00-foundation/guides/middleware-configuration.md`

---

## Common Commands

```bash
# Status
systemctl --user status tinyauth.service
podman logs tinyauth | tail -20

# Restart (clear sessions)
systemctl --user restart tinyauth.service

# Check users
sqlite3 ~/containers/data/tinyauth/tinyauth.db "SELECT * FROM users;"

# Add user
sqlite3 ~/containers/data/tinyauth/tinyauth.db \
  "INSERT INTO users (username, password_hash) VALUES ('user', 'hash');"

# Test authentication from Traefik
podman exec traefik wget -O- http://tinyauth:3000/auth

# View auth attempts
podman logs tinyauth | grep auth
```

---

**Maintainer:** patriark
**Authentication:** Username/password with bcrypt
**Future replacement:** Authelia with 2FA
