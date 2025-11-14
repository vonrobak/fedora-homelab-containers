# Vaultwarden Deployment Guide

**Date:** 2025-11-12 (Updated: 2025-11-14)
**Service:** Vaultwarden (Bitwarden-compatible password manager)
**URL:** https://vault.patriark.org
**Status:** 📋 Ready for deployment

---

## Overview

Vaultwarden is a lightweight, self-hosted implementation of the Bitwarden password manager API. This deployment uses:

- **Database:** SQLite (perfect for homelab scale)
- **Authentication:** Master password + YubiKey/WebAuthn + TOTP 2FA
- **Network:** `systemd-reverse_proxy` (Traefik integration)
- **Storage:** BTRFS pool with automated snapshots
- **Rate Limiting:** Strict (5 attempts/min for auth endpoints)
- **Admin Panel:** Enabled for setup, then disabled for security

---

## Prerequisites

Before deploying, ensure:

- ✅ Traefik is running (`systemctl --user status traefik.service`)
- ✅ Backup automation is working (see `docs/20-operations/guides/backup-automation-setup.md`)
- ✅ DNS record for `vault.patriark.org` points to your public IP
- ✅ Ports 80/443 are forwarded to your server

---

## Deployment Method

### Pattern-Based Deployment (Recommended - Future)

**Note:** As of 2025-11-14, Vaultwarden can be deployed using the `password-manager` pattern from the homelab-deployment skill. This provides consistent configuration and validation.

**Pattern deployment:**
```bash
cd .claude/skills/homelab-deployment

# Deploy Vaultwarden with pattern
./scripts/deploy-from-pattern.sh \
  --pattern password-manager \
  --service-name vaultwarden \
  --hostname vault.patriark.org \
  --memory 512M
```

**What the pattern provides:**
- ✅ Optimized resource limits (512MB RAM suitable for password manager)
- ✅ Correct network configuration (reverse_proxy for Traefik access)
- ✅ Traefik labels with strict rate limiting
- ✅ Security middleware (CrowdSec, auth protection)
- ✅ BTRFS storage layout recommendations
- ✅ Health check integration

**Post-deployment steps:**
1. Configure environment variables (admin token, SMTP, etc.)
2. Set up YubiKey/WebAuthn 2FA
3. Create initial user accounts
4. Disable admin panel after setup

**Pattern reference:** See `.claude/skills/homelab-deployment/patterns/password-manager.yml`

**Documentation:**
- **Pattern guide:** `docs/10-services/guides/pattern-selection-guide.md`
- **ADR-007:** `docs/20-operations/decisions/2025-11-14-decision-007-pattern-based-deployment.md`

### Manual Deployment (Current Process)

**The following manual steps are preserved** for:
- Understanding the existing Vaultwarden deployment
- Customizing beyond pattern capabilities
- Historical reference

**Manual deployment workflow:**

---

## Manual Deployment Steps

### Step 1: Create Data Directory

```bash
# Create directory on BTRFS pool (for automated backups)
sudo mkdir -p /mnt/btrfs-pool/subvol7-containers/vaultwarden

# Set ownership
sudo chown -R $(id -u):$(id -g) /mnt/btrfs-pool/subvol7-containers/vaultwarden

# Verify
ls -ld /mnt/btrfs-pool/subvol7-containers/vaultwarden
```

---

### Step 2: Create Environment File

```bash
# Copy template
cp ~/fedora-homelab-containers/config/vaultwarden/vaultwarden.env.template \
   ~/fedora-homelab-containers/config/vaultwarden/vaultwarden.env

# Generate admin token
openssl rand -base64 48

# Edit environment file
nano ~/fedora-homelab-containers/config/vaultwarden/vaultwarden.env
```

**Required changes:**
1. Replace `ADMIN_TOKEN=CHANGE_ME...` with your generated token
2. (Optional) Configure SMTP settings if you want email notifications

**Critical settings to verify:**
```bash
DOMAIN=https://vault.patriark.org  # Must match your actual domain
SIGNUPS_ALLOWED=false              # Disable public registration
ADMIN_TOKEN=<your-generated-token> # Strong random token
```

---

### Step 3: Reload Systemd and Start Service

```bash
# Reload systemd to pick up new quadlet
systemctl --user daemon-reload

# Start Vaultwarden
systemctl --user start vaultwarden.service

# Check status
systemctl --user status vaultwarden.service
```

**Expected output:**
```
● vaultwarden.service - Vaultwarden Password Manager
     Loaded: loaded
     Active: active (running)
```

---

### Step 4: Verify Service Health

```bash
# Check container is running
podman ps | grep vaultwarden

# Check health status
podman healthcheck run vaultwarden

# View logs
podman logs vaultwarden | tail -20
```

**Expected in logs:**
```
[INFO] Rocket has launched from http://0.0.0.0:80
[INFO] WebSocket listening on 0.0.0.0:3012
```

---

### Step 5: Verify Traefik Routing

```bash
# Test internal connection
curl -I http://vaultwarden:80/alive

# Check Traefik dashboard
# Navigate to: https://traefik.patriark.org/dashboard/
# Look for "vaultwarden-secure" router
```

---

### Step 6: Access Web Vault

Open your browser and navigate to:
**https://vault.patriark.org**

You should see the Bitwarden web vault interface.

---

### Step 7: Access Admin Panel

Navigate to:
**https://vault.patriark.org/admin**

Enter the `ADMIN_TOKEN` you generated in Step 2.

---

### Step 8: Create User Account

In the admin panel:

1. Click **"Users"** tab
2. Click **"Invite User"** (even though invitations are disabled, admin can create users)
3. Enter your email address
4. Click **"Invite"**

Since email is not configured (or if you skipped SMTP), manually confirm:

```bash
# View Vaultwarden logs for confirmation link
podman logs vaultwarden | grep -A 5 "Invitation"
```

Or create user via CLI:

```bash
# Access Vaultwarden container
podman exec -it vaultwarden /bin/sh

# Create user (if supported by container - may need web UI)
# Most secure: Use admin panel to create user
```

**Recommended:** Use admin panel web UI to create user account.

---

### Step 9: Configure Master Password & 2FA

1. **Register Account:**
   - Navigate to https://vault.patriark.org
   - Click "Create Account" (if email invite was sent) OR log in with admin-created credentials
   - Set a **strong master password** (20+ characters, random, stored in physical backup)

2. **Enable YubiKey/WebAuthn:**
   - Log in to web vault
   - Settings → Security → Two-step Login
   - Click **"FIDO2 WebAuthn"**
   - Insert YubiKey, click "Add Security Key"
   - Follow prompts to register YubiKey
   - **Name it:** "YubiKey 5 NFC #16173971" (or your key's serial)

3. **Enable TOTP Backup:**
   - Settings → Security → Two-step Login
   - Click **"Authenticator App (TOTP)"**
   - Scan QR code with authenticator app (Authy, Google Authenticator, etc.)
   - Enter code to confirm
   - **Save recovery code in physical backup!**

---

### Step 10: Test 2FA Authentication

1. Log out of web vault
2. Log in again
3. Enter master password
4. You should be prompted for second factor
5. Touch YubiKey (or enter TOTP code)
6. Should successfully authenticate

**Test fallback:**
- Log out
- Log in with master password
- When prompted for 2FA, use TOTP code instead of YubiKey
- Verify TOTP works as backup

---

### Step 11: Disable Admin Panel (CRITICAL SECURITY STEP)

Once you've created your account and configured 2FA:

```bash
# Edit environment file
nano ~/fedora-homelab-containers/config/vaultwarden/vaultwarden.env

# Comment out or remove ADMIN_TOKEN line:
# ADMIN_TOKEN=

# Restart service
systemctl --user restart vaultwarden.service

# Verify admin panel is disabled
curl -I https://vault.patriark.org/admin
# Should return 404 Not Found
```

**Why disable admin panel:**
- Reduces attack surface
- Admin functions no longer needed after initial setup
- User management can be done via direct database access if needed (rare)

---

### Step 12: Enable Automatic Start on Boot

```bash
# Enable service
systemctl --user enable vaultwarden.service

# Verify
systemctl --user is-enabled vaultwarden.service
# Should return: enabled
```

---

### Step 13: Verify Backups Include Vaultwarden

```bash
# Run backup manually (with local-only flag)
~/fedora-homelab-containers/scripts/btrfs-snapshot-backup.sh --local-only --verbose

# Check snapshot includes Vaultwarden data
sudo btrfs subvolume list /mnt/btrfs-pool | grep containers

# List snapshots
ls -lah /mnt/btrfs-pool/.snapshots/subvol7-containers/

# Verify Vaultwarden database in snapshot
ls -lah /mnt/btrfs-pool/.snapshots/subvol7-containers/$(ls -t /mnt/btrfs-pool/.snapshots/subvol7-containers/ | head -1)/vaultwarden/
```

**Expected files in snapshot:**
- `db.sqlite3` - Main database
- `db.sqlite3-shm` - Shared memory file
- `db.sqlite3-wal` - Write-ahead log
- `rsa_key.pem` - Server encryption key
- `config.json` - Server configuration

---

## Client Setup

### Desktop (Linux, Windows, Mac)

1. Download Bitwarden desktop app: https://bitwarden.com/download/
2. At login screen, click **"Server URL"** (gear icon)
3. Enter: `https://vault.patriark.org`
4. Log in with master password + 2FA

### Browser Extension (Chrome, Firefox, Edge)

1. Install Bitwarden extension from browser store
2. Click extension icon → Settings (gear icon)
3. Set "Server URL" to `https://vault.patriark.org`
4. Log in with master password + 2FA

### Mobile (Android, iOS)

1. Install Bitwarden app from App Store / Play Store
2. Tap settings gear icon
3. Set "Server URL" to `https://vault.patriark.org`
4. Log in with master password + 2FA

**Note:** Mobile apps use YubiKey NFC (tap to authenticate) or TOTP codes

---

## Verification Checklist

After deployment, verify:

- [ ] Service running (`systemctl --user is-active vaultwarden.service` → `active`)
- [ ] Web vault accessible at https://vault.patriark.org
- [ ] TLS certificate valid (Let's Encrypt)
- [ ] User account created
- [ ] YubiKey 2FA configured and tested
- [ ] TOTP backup 2FA configured and tested
- [ ] Admin panel disabled
- [ ] Rate limiting working (test with wrong password 6 times → should be rate-limited)
- [ ] Desktop client syncs successfully
- [ ] Browser extension syncs successfully
- [ ] Mobile app syncs successfully
- [ ] Backups include Vaultwarden data
- [ ] Service enabled for boot (`systemctl --user is-enabled vaultwarden.service` → `enabled`)

---

## Testing Rate Limiting

Verify strict rate limiting is working:

```bash
# Attempt 6 failed logins rapidly
for i in {1..6}; do
  curl -X POST https://vault.patriark.org/identity/connect/token \
    -d "username=test@example.com" \
    -d "password=wrongpassword" \
    -d "grant_type=password"
  echo "Attempt $i"
done
```

**Expected result:** After 5 attempts, you should receive rate limit error (429 Too Many Requests).

---

## Monitoring

### Service Health

```bash
# Check service status
systemctl --user status vaultwarden.service

# View recent logs
journalctl --user -u vaultwarden.service -n 50 -f

# Check health endpoint
curl http://localhost:80/alive  # Inside container network
podman healthcheck run vaultwarden
```

### Metrics (Future Enhancement)

Add Vaultwarden metrics to Prometheus:

```yaml
# In prometheus.yml
scrape_configs:
  - job_name: 'vaultwarden'
    static_configs:
      - targets: ['vaultwarden:80']
    metrics_path: '/metrics'  # If Vaultwarden exports Prometheus metrics
```

**Note:** Vaultwarden doesn't natively export Prometheus metrics. Monitor via:
- Container health checks
- Traefik metrics (request rates, response times)
- Systemd service status

---

## Backup & Restoration

### Manual Backup Export

**From Web Vault:**
1. Log in to https://vault.patriark.org
2. Settings → Tools → Export Vault
3. Choose format: **JSON (Encrypted)** (recommended) or JSON/CSV
4. Enter master password
5. Save file to secure location (encrypted USB drive, offline storage)

**Frequency:** Export manually quarterly or before major changes.

### Restore from BTRFS Snapshot

See: `docs/20-operations/guides/backup-automation-setup.md` → Restoration Process

**Quick restore:**
```bash
# 1. Stop Vaultwarden
systemctl --user stop vaultwarden.service

# 2. Find snapshot
ls -lah /mnt/btrfs-pool/.snapshots/subvol7-containers/

# 3. Copy database from snapshot
sudo cp /mnt/btrfs-pool/.snapshots/subvol7-containers/20251112-containers/vaultwarden/db.sqlite3 \
        /mnt/btrfs-pool/subvol7-containers/vaultwarden/db.sqlite3

# 4. Restart service
systemctl --user start vaultwarden.service
```

---

## Troubleshooting

### Can't Access Web Vault

**Check Traefik routing:**
```bash
# Verify Traefik is running
systemctl --user status traefik.service

# Check Traefik logs
podman logs traefik | grep vaultwarden

# Test internal routing
curl -I http://vaultwarden:80/
```

**Check DNS:**
```bash
dig vault.patriark.org
# Should return your public IP
```

### Admin Panel Shows 404

**If you disabled admin panel:** This is expected behavior.

**To re-enable temporarily:**
1. Edit `config/vaultwarden/vaultwarden.env`
2. Uncomment `ADMIN_TOKEN=...`
3. Restart: `systemctl --user restart vaultwarden.service`
4. Access admin panel
5. **Remember to disable again after use!**

### 2FA Not Working

**YubiKey not recognized:**
- Ensure using modern browser (Chrome, Firefox, Edge)
- Try different USB port
- Check YubiKey blinks when touched
- Verify WebAuthn is supported: https://webauthn.me

**TOTP codes rejected:**
- Check time sync on phone/computer
- Use most recent code (don't reuse old codes)
- Verify authenticator app is synced

### Clients Can't Sync

**Check server URL:**
- Desktop/mobile settings → Server URL: `https://vault.patriark.org`
- Must include `https://` prefix
- No trailing slash

**Network connectivity:**
```bash
# From client machine
curl -I https://vault.patriark.org
# Should return 200 OK
```

### Database Locked Errors

**SQLite lock issues:**
```bash
# Check for multiple processes accessing database
podman exec vaultwarden ls -l /data/db.sqlite3*

# Restart service (releases locks)
systemctl --user restart vaultwarden.service
```

### High Memory Usage

**Check resource limits:**
```bash
# View current memory usage
podman stats vaultwarden --no-stream

# If consistently >512MB, increase limit in quadlet:
nano ~/.config/containers/systemd/vaultwarden.container
# Change: Memory=1G
# Then: systemctl --user daemon-reload && systemctl --user restart vaultwarden.service
```

---

## Security Considerations

### Master Password Best Practices

- **Length:** 20+ characters minimum
- **Randomness:** Use Diceware or password generator
- **Storage:** Write on paper, store in fireproof safe
- **Never:** Store digitally (defeats purpose of password manager)

### YubiKey Best Practices

- **Primary:** YubiKey on daily keyring
- **Backup:** Second YubiKey in safe
- **Register both:** Add backup YubiKey to Vaultwarden account
- **Test regularly:** Verify backup YubiKey works

### TOTP Backup Best Practices

- **Recovery code:** Print and store with will/important docs
- **Authenticator app:** Use app with cloud backup (Authy) OR store seed in safe
- **Test recovery:** Verify you can restore TOTP from recovery code

### Database Encryption

**Vaultwarden encrypts sensitive data:**
- Master password: Never stored (only hashed)
- Vault items: Encrypted with master password
- Attachments: Encrypted before storage

**Database file (`db.sqlite3`) contains encrypted data.**
- Safe to backup to cloud (end-to-end encrypted)
- Cannot be decrypted without master password
- Server encryption key (`rsa_key.pem`) protects server-side operations

### Network Security

**Vaultwarden is protected by:**
1. **CrowdSec:** Blocks malicious IPs before reaching Vaultwarden
2. **Rate Limiting:** 5 login attempts/min (prevents brute-force)
3. **TLS 1.2+:** All traffic encrypted in transit
4. **Security Headers:** XSS, clickjacking, MIME-sniffing protection

**No Authelia:** Vaultwarden uses its own strong authentication (master password + 2FA). Adding Authelia would create UX friction without meaningful security gain.

---

## Updating Vaultwarden

Vaultwarden is configured for automatic updates (`AutoUpdate=registry` in quadlet).

**Manual update:**
```bash
# Pull latest image
podman pull docker.io/vaultwarden/server:latest

# Recreate container with new image
systemctl --user restart vaultwarden.service

# Verify update
podman inspect vaultwarden | grep -A 5 "Image"
podman logs vaultwarden | grep -i version
```

**Update process:**
1. Automatic backup (happens daily at 02:00 AM)
2. Pull new image
3. Restart service
4. Verify service healthy
5. Test login with 2FA

**Rollback if needed:**
```bash
# Stop service
systemctl --user stop vaultwarden.service

# Restore from snapshot (see Backup & Restoration section)

# Start service
systemctl --user start vaultwarden.service
```

---

## Next Steps

1. **Week 1:** Use Vaultwarden actively, migrate passwords from old manager
2. **Week 2:** Set up family members (if desired - requires re-enabling invitations)
3. **Month 1:** Review backup strategy, test restoration
4. **Ongoing:** Export encrypted vault backup quarterly

---

## Related Documentation

- **ADR-006:** `docs/10-services/decisions/2025-11-12-decision-006-vaultwarden-architecture.md`
- **Backup Strategy:** `docs/20-operations/guides/backup-strategy.md`
- **Backup Automation:** `docs/20-operations/guides/backup-automation-setup.md`
- **Traefik Configuration:** `docs/10-services/guides/traefik.md`
- **Rate Limiting Design:** `docs/00-foundation/guides/middleware-configuration.md`
