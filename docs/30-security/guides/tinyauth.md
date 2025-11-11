# Tinyauth Setup Guide - Complete

> ## ⚠️ DEPRECATED - Superseded by Authelia
>
> **This setup guide is NO LONGER RECOMMENDED.**
>
> **Migration complete:** 2025-11-11
> **Superseded by:** Authelia SSO with YubiKey/WebAuthn authentication
>
> **See current authentication documentation:**
> - **Authelia Service Guide:** `/docs/10-services/guides/authelia.md`
> - **Architecture Decision (ADR-005):** `/docs/30-security/decisions/2025-11-11-decision-005-authelia-sso-yubikey-deployment.md`
> - **Deployment Journal:** `/docs/30-security/journal/2025-11-11-authelia-deployment.md`
>
> **This document preserved for historical reference only.**

---

## 🎯 What is Tinyauth?

**Tinyauth** is a simple, modern authentication middleware that:
- Works seamlessly with Traefik forward auth
- No database required (users stored in environment variables)
- Single container, no dependencies
- Supports OAuth (Google, GitHub) or simple username/password
- Actually works reliably

**Much simpler than Authelia** - no Redis, no complex config, just works.

---

## ⚡ Quick Setup (5 Minutes)

### Step 1: Remove Authelia

```bash
# Copy and run the removal script
cp /path/to/outputs/remove-authelia.sh ~/containers/scripts/
chmod +x ~/containers/scripts/remove-authelia.sh
~/containers/scripts/remove-authelia.sh

# This backs up everything and removes Authelia cleanly
```

---

### Step 2: Setup Tinyauth

```bash
# Copy and run the tinyauth setup script
cp /path/to/outputs/setup-tinyauth.sh ~/containers/scripts/
chmod +x ~/containers/scripts/setup-tinyauth.sh
~/containers/scripts/setup-tinyauth.sh

# You'll be prompted for:
# - Username (e.g., "patriark")
# - Password (choose strong password)
# - Confirm password
```

**What the script does:**
1. Generates password hash using tinyauth's built-in CLI
2. Generates random session secret
3. Creates tinyauth.container quadlet
4. Updates Traefik routers to use tinyauth middleware
5. Starts tinyauth service
6. Restarts Traefik

---

### Step 3: Test

```bash
# Go to any protected service
https://jellyfin.patriark.lokal

# You should:
# 1. Be redirected to: https://auth.patriark.lokal
# 2. See Tinyauth login page
# 3. Enter your username and password
# 4. Be redirected back to Jellyfin
# 5. Access granted! ✅
```

---

## 📋 Configuration Files Created

### 1. Tinyauth Quadlet
**Location:** `~/.config/containers/systemd/tinyauth.container`

```ini
[Container]
Image=ghcr.io/steveiliop56/tinyauth:v4
ContainerName=tinyauth
Network=systemd-reverse_proxy

Environment=APP_URL=https://auth.patriark.lokal
Environment=SECRET=<random-secret>
Environment=USERS=username:$2a$10$hash...

# Traefik labels
Label=traefik.enable=true
Label=traefik.http.routers.tinyauth.rule=Host(`auth.patriark.lokal`)
Label=traefik.http.middlewares.tinyauth.forwardauth.address=http://tinyauth:3000/api/auth/traefik
```

### 2. Traefik Routers
**Location:** `~/containers/config/traefik/dynamic/routers.yml`

```yaml
http:
  routers:
    traefik-dashboard:
      rule: "Host(`traefik.patriark.lokal`)"
      middlewares:
        - tinyauth@docker  # ← Uses tinyauth
      tls: {}
    
    jellyfin-secure:
      rule: "Host(`jellyfin.patriark.lokal`)"
      middlewares:
        - tinyauth@docker  # ← Uses tinyauth
      tls: {}
```

---

## 👥 Managing Users

### Add a New User

```bash
# Generate user hash
podman run --rm -i ghcr.io/steveiliop56/tinyauth:v4 user create \
  --username newuser \
  --password newpassword

# Output will be: newuser:$2a$10$hash...
```

**Add to tinyauth.container:**
```bash
nano ~/.config/containers/systemd/tinyauth.container

# Find the USERS line and add the new user (comma-separated):
Environment=USERS=user1:$2a$10$hash1...,user2:$2a$10$hash2...

# Restart tinyauth
systemctl --user daemon-reload
systemctl --user restart tinyauth.service
```

### Remove a User

```bash
# Edit tinyauth.container
nano ~/.config/containers/systemd/tinyauth.container

# Remove the user from USERS environment variable
# Make sure to keep commas correct between remaining users

# Restart
systemctl --user daemon-reload
systemctl --user restart tinyauth.service
```

### Change Password

```bash
# Generate new hash for existing user
podman run --rm -i ghcr.io/steveiliop56/tinyauth:v4 user create \
  --username existinguser \
  --password newpassword

# Replace the old hash in tinyauth.container
nano ~/.config/containers/systemd/tinyauth.container

# Restart
systemctl --user daemon-reload
systemctl --user restart tinyauth.service
```

---

## 🔓 Protect Additional Services

To protect any service with tinyauth:

### Option 1: Docker Labels (if service has them)

```bash
# Edit the service's quadlet
nano ~/.config/containers/systemd/yourservice.container

# Add labels:
Label=traefik.enable=true
Label=traefik.http.routers.yourservice.rule=Host(`yourservice.patriark.lokal`)
Label=traefik.http.routers.yourservice.middlewares=tinyauth@docker

# Restart
systemctl --user daemon-reload
systemctl --user restart yourservice.service
```

### Option 2: Dynamic Configuration

```bash
# Edit routers.yml
nano ~/containers/config/traefik/dynamic/routers.yml

# Add router:
http:
  routers:
    yourservice:
      rule: "Host(`yourservice.patriark.lokal`)"
      service: "yourservice"
      middlewares:
        - tinyauth@docker
      tls: {}
  
  services:
    yourservice:
      loadBalancer:
        servers:
          - url: "http://yourservice:PORT"

# Restart Traefik
systemctl --user restart traefik.service
```

---

## 🌐 Support for Both .lokal and .org Domains

Tinyauth already supports both domains! The routers are configured with:
```yaml
rule: "Host(`jellyfin.patriark.lokal`) || Host(`jellyfin.patriark.org`)"
```

When you're ready for internet access (after Let's Encrypt):
1. Tinyauth will automatically work on both domains
2. Cookies will be set for `.patriark.lokal` (LAN) and `.patriark.org` (internet)
3. No additional configuration needed

---

## 🔍 Troubleshooting

### Tinyauth not starting

```bash
# Check status
systemctl --user status tinyauth.service

# Check logs
journalctl --user -u tinyauth.service -n 30
podman logs tinyauth --tail 30

# Common issues:
# - Invalid USERS hash format
# - SECRET not 32 characters
# - Network not connected
```

### Not redirecting to login

```bash
# Check Traefik logs
podman logs traefik --tail 20 | grep tinyauth

# Verify middleware is registered
curl http://localhost:8080/api/http/middlewares | jq | grep tinyauth

# Restart Traefik
systemctl --user restart traefik.service
```

### Login doesn't work

```bash
# Check tinyauth logs for authentication attempts
podman logs tinyauth --tail 30

# Verify user hash is correct
podman run --rm -i ghcr.io/steveiliop56/tinyauth:v4 user create \
  --username youruser \
  --password yourpassword

# Compare hash in tinyauth.container
```

### Redirect loop

```bash
# Usually means APP_URL is wrong
nano ~/.config/containers/systemd/tinyauth.container

# APP_URL must match the domain you're accessing tinyauth from
Environment=APP_URL=https://auth.patriark.lokal

# Restart
systemctl --user daemon-reload
systemctl --user restart tinyauth.service
```

---

## 📊 Comparison: Tinyauth vs Authelia

| Feature | Authelia | Tinyauth |
|---------|----------|----------|
| **Containers** | 2 (Auth + Redis) | 1 |
| **Dependencies** | Redis, DB | None |
| **Config files** | 5+ | 1 quadlet |
| **User management** | YAML file | Environment var |
| **Setup time** | 30+ minutes | 5 minutes |
| **Reliability** | Variable | Excellent |
| **Debugging** | Complex | Simple |
| **2FA** | Yes (TOTP, WebAuthn) | Optional (TOTP) |
| **OAuth** | Limited | Yes (Google, GitHub, generic) |
| **Learning curve** | Steep | Minimal |

---

## 🚀 Advanced: OAuth with Google

If you want OAuth (login with Google):

### 1. Create Google OAuth Client

1. Go to: https://console.cloud.google.com/apis/credentials
2. Create OAuth 2.0 Client ID
3. Authorized redirect URIs: `https://auth.patriark.lokal/oauth/callback`
4. Copy Client ID and Client Secret

### 2. Update Tinyauth Configuration

```bash
nano ~/.config/containers/systemd/tinyauth.container

# Add OAuth environment variables:
Environment=OAUTH_PROVIDER=google
Environment=OAUTH_CLIENT_ID=your-client-id
Environment=OAUTH_CLIENT_SECRET=your-client-secret
Environment=OAUTH_WHITELIST=your-email@gmail.com,another@gmail.com

# Restart
systemctl --user daemon-reload
systemctl --user restart tinyauth.service
```

### 3. Login

- Go to protected service
- Redirected to tinyauth
- Click "Login with Google"
- Authenticate with Google
- Redirected back to service ✅

---

## 🎓 How Tinyauth Works

### Authentication Flow:

1. **User requests:** `https://jellyfin.patriark.lokal`
2. **Traefik forwards:** to `http://tinyauth:3000/api/auth/traefik`
3. **Tinyauth checks:** Is there a valid session cookie?
4. **If NO cookie:**
   - Tinyauth responds: "302 Redirect to login page"
   - User sees: `https://auth.patriark.lokal`
   - User enters credentials
   - Tinyauth validates against USERS hash
   - Tinyauth sets session cookie
   - Tinyauth redirects back to `jellyfin.patriark.lokal`
5. **If YES cookie (valid):**
   - Tinyauth responds: "200 OK" + headers
   - Traefik forwards request to Jellyfin
   - User sees Jellyfin ✅

### Session Management:

- **Cookie name:** `tinyauth_session` (default)
- **Cookie domain:** `.patriark.lokal` (covers all subdomains)
- **Cookie lifetime:** 30 days (default)
- **Cookie security:** HttpOnly, Secure, SameSite=Lax
- **Session encryption:** AES-256 using your SECRET

---

## ✅ Advantages of Tinyauth

1. **Simplicity** - One container, minimal config
2. **Reliability** - No complex dependencies
3. **Modern** - Active development, responsive maintainer
4. **Flexible** - Username/password OR OAuth
5. **Lightweight** - ~50MB container vs Authelia's 200MB+
6. **Fast** - No database lookups, sessions in encrypted cookies
7. **Transparent** - Easy to understand and debug

---

## 📁 Backup & Restore

### Backup Tinyauth Config

```bash
# Backup quadlet
cp ~/.config/containers/systemd/tinyauth.container \
   ~/containers/backups/tinyauth.container.$(date +%Y%m%d)

# Backup routers
cp ~/containers/config/traefik/dynamic/routers.yml \
   ~/containers/backups/routers.yml.$(date +%Y%m%d)
```

### Restore

```bash
# Restore quadlet
cp ~/containers/backups/tinyauth.container.TIMESTAMP \
   ~/.config/containers/systemd/tinyauth.container

# Restore routers
cp ~/containers/backups/routers.yml.TIMESTAMP \
   ~/containers/config/traefik/dynamic/routers.yml

# Reload
systemctl --user daemon-reload
systemctl --user restart tinyauth.service traefik.service
```

---

## 🎉 Success Criteria

After setup, you should have:

- ✅ Tinyauth container running
- ✅ Traefik using tinyauth middleware
- ✅ Login page at auth.patriark.lokal
- ✅ Jellyfin protected (requires login)
- ✅ Traefik dashboard protected (requires login)
- ✅ No more Authelia complexity
- ✅ Simple, working authentication

---

**Tinyauth: Simple, modern, reliable authentication. No Redis, no complexity, just works.** 🚀
