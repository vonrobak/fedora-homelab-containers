# Secrets Management Guide

**Created:** 2025-12-26
**Purpose:** Secure handling of authentication tokens, passwords, and API keys

---

## Overview

This homelab uses **three approaches** for secrets management, depending on the service type:

1. **Podman Secrets** (PREFERRED for containers) - Encrypted, native integration
2. **Environment Variables** (for systemd services) - Simple, systemd-native
3. **Secure Files** (legacy fallback) - Last resort only

**Key Principle:** Choose the most secure method appropriate for your service type.

---

## Decision Tree: Which Secrets Method?

```
Is your service running in a container?
│
├─ YES → Use Podman Secrets (PREFERRED)
│         • Encrypted storage
│         • Native podman integration
│         • Mount as file or environment variable
│         • Example: Database passwords, API keys for containerized apps
│
└─ NO → Is it a systemd service?
    │
    ├─ YES → Use EnvironmentFile (RECOMMENDED)
    │         • Simple and secure for bare-metal services
    │         • Systemd-native
    │         • Example: Webhook handler, backup scripts
    │
    └─ NO → Use secure files with strict permissions
              • Last resort only
              • Mode 600, outside Git
              • Example: Scripts without systemd integration
```

---

## Method 1: Podman Secrets (PREFERRED for Containers)

### When to Use

✅ **Use Podman secrets when:**
- Service runs in a container (via podman or quadlet)
- Need encrypted storage
- Want native container integration
- Secret is used by container application

❌ **Don't use Podman secrets when:**
- Service runs as bare systemd service (not containerized)
- Need to share secret across host and containers easily
- Debugging secret access is critical (harder to inspect)

### How It Works

Podman secrets are **encrypted at rest** and only decrypted when mounted into containers.

**Storage:** `~/.local/share/containers/storage/secrets/`
**Access:** Via `podman secret` commands
**Encryption:** Yes (libsecret or basic encryption)

### Examples

#### Create Secret

```bash
# Create from stdin
echo "my-secret-password" | podman secret create db_password -

# Create from file
podman secret create api_token ~/path/to/token.txt

# Verify
podman secret ls
```

#### Use in Container

**Option A: Mount as file (recommended)**
```bash
podman run -d \
  --name myapp \
  --secret db_password,type=mount,target=/run/secrets/db_password \
  myimage:latest
```

Container reads: `/run/secrets/db_password`

**Option B: Mount as environment variable**
```bash
podman run -d \
  --name myapp \
  --secret db_password,type=env,target=DB_PASSWORD \
  myimage:latest
```

Container reads: `$DB_PASSWORD` environment variable

#### Use in Quadlet

**File:** `~/.config/containers/systemd/myapp.container`

```ini
[Container]
Image=myimage:latest
ContainerName=myapp

# Mount secret as file
Secret=db_password,type=mount,target=/run/secrets/db_password

# Or as environment variable
# Secret=db_password,type=env,target=DB_PASSWORD

[Service]
Restart=on-failure
```

### Rotation

```bash
# Remove old secret
podman secret rm db_password

# Create new secret
echo "new-password" | podman secret create db_password -

# Restart container to pick up new secret
systemctl --user restart myapp.service
```

---

## Method 2: EnvironmentFile (for Systemd Services)

### When to Use

✅ **Use EnvironmentFile when:**
- Service runs as systemd service (NOT containerized)
- Simple token/password needs
- Easy rotation required
- Service runs on bare metal

❌ **Don't use EnvironmentFile when:**
- Service runs in container (use Podman secrets instead)
- Need encrypted storage
- Sharing secrets across multiple services

### How It Works

Systemd loads environment variables from a file before starting the service.

**Storage:** `~/.config/*.env` (outside Git, mode 600)
**Access:** Via `EnvironmentFile=` directive in systemd service
**Encryption:** No (plain text file with strict permissions)

---

## Webhook Authentication Token (Example: EnvironmentFile)

**Why EnvironmentFile here?** The webhook handler runs as a bare systemd service (Python script), not in a container. Podman secrets are only accessible to containers, so EnvironmentFile is the appropriate choice.

**Alternative approach:** If we containerized the webhook handler, we would use Podman secrets instead.

### Storage Location

```bash
~/.config/remediation-webhook.env
```

**Permissions:** `600` (read/write owner only)
**Format:**
```bash
WEBHOOK_AUTH_TOKEN=<base64-encoded-secret>
```

### Setup

1. **Generate new token** (if needed):
   ```bash
   openssl rand -base64 32
   ```

2. **Create secrets file**:
   ```bash
   cat > ~/.config/remediation-webhook.env << EOF
   WEBHOOK_AUTH_TOKEN=<your-generated-token>
   EOF
   chmod 600 ~/.config/remediation-webhook.env
   ```

3. **Verify systemd loads it**:
   ```bash
   systemctl --user cat remediation-webhook.service | grep EnvironmentFile
   # Expected: EnvironmentFile=%h/.config/remediation-webhook.env
   ```

4. **Restart service**:
   ```bash
   systemctl --user restart remediation-webhook.service
   ```

### Security Features

- ✅ **Not committed to Git** - Secrets file is in `~/.config/` (outside repository)
- ✅ **Strict permissions** - Mode 600 (owner-only access)
- ✅ **Environment variable** - Loaded by systemd, not hardcoded in scripts
- ✅ **Fail-closed** - Service refuses to start without valid token
- ✅ **Rotation-friendly** - Edit `.env` file and restart service

---

## Alertmanager Webhook URL

### Problem

Alertmanager needs the webhook token in its configuration to call the remediation webhook:

```yaml
- url: 'http://host.containers.internal:9096/webhook?token=<TOKEN>'
```

Alertmanager doesn't support environment variable substitution in config files.

### Solution

**Local file** (`config/alertmanager/alertmanager.yml`) contains real token
**Template file** (`config/alertmanager/alertmanager.yml.example`) has placeholder
**Git ignores** `alertmanager.yml` to prevent committing secrets

### Setup

1. **Copy template** (first-time setup):
   ```bash
   cp ~/containers/config/alertmanager/alertmanager.yml.example \
      ~/containers/config/alertmanager/alertmanager.yml
   ```

2. **Get webhook token**:
   ```bash
   grep WEBHOOK_AUTH_TOKEN ~/.config/remediation-webhook.env
   # Output: WEBHOOK_AUTH_TOKEN=CB5sbWz55FUDTdcAHu0c9otJE5pDshr/QnpRXHjOiDs=
   ```

3. **Update alertmanager.yml**:
   ```bash
   TOKEN=$(grep WEBHOOK_AUTH_TOKEN ~/.config/remediation-webhook.env | cut -d= -f2)
   sed -i "s|token=REPLACE_WITH_ACTUAL_TOKEN|token=$TOKEN|" \
     ~/containers/config/alertmanager/alertmanager.yml
   ```

4. **Restart Alertmanager**:
   ```bash
   systemctl --user restart alertmanager.service
   ```

### Git Protection

```bash
# .gitignore includes:
config/alertmanager/alertmanager.yml
```

This prevents the file with real secrets from being committed.

**Important:** If the file is already tracked by Git, you must untrack it:

```bash
# Remove from Git index (keep local file)
git rm --cached config/alertmanager/alertmanager.yml

# Commit the removal
git commit -m "chore: Remove alertmanager.yml from Git (contains secrets)"

# File is now ignored, local changes won't be committed
```

---

## Discord Webhook URL

### Storage

Discord webhook URL is stored in the `alert-discord-relay` container environment.

**Access:**
```bash
podman exec alert-discord-relay env | grep DISCORD_WEBHOOK_URL
```

### Security

- Container-only access (not in filesystem)
- Not committed to Git
- Accessed via podman exec when needed

---

## Other Secrets

### Let's Encrypt Certificates

**Location:** `~/containers/data/letsencrypt/acme.json`
**Protection:** Automatically excluded by `.gitignore` pattern `acme.json`

### Authelia User Database

**Location:** `~/containers/config/authelia/users_database.yml`
**Contains:** Argon2 password hashes (not plaintext)
**Protection:** Hashes are safe to commit (computationally infeasible to reverse)

### YubiKey Credentials

**Location:** Stored in YubiKey hardware, never on filesystem
**Protection:** Hardware-protected, cannot be extracted

---

## Secret Rotation

### Webhook Token Rotation

1. **Generate new token**:
   ```bash
   NEW_TOKEN=$(openssl rand -base64 32)
   echo "New token: $NEW_TOKEN"
   ```

2. **Update secrets file**:
   ```bash
   sed -i "s/WEBHOOK_AUTH_TOKEN=.*/WEBHOOK_AUTH_TOKEN=$NEW_TOKEN/" \
     ~/.config/remediation-webhook.env
   ```

3. **Update Alertmanager config**:
   ```bash
   sed -i "s|token=[^']*|token=$NEW_TOKEN|" \
     ~/containers/config/alertmanager/alertmanager.yml
   ```

4. **Restart services**:
   ```bash
   systemctl --user restart remediation-webhook.service
   systemctl --user restart alertmanager.service
   ```

5. **Verify**:
   ```bash
   # Test webhook with new token
   curl -s -w "%{http_code}\n" -X POST \
     "http://localhost:9096/webhook?token=$NEW_TOKEN" \
     -d '{"alerts": []}'
   # Expected: 200
   ```

---

## Verification Checklist

### Pre-Commit Check

Before committing to Git, verify no secrets are exposed:

```bash
# Check for webhook token
git -C ~/containers grep "CB5sbWz55FUDTdcAHu0c9otJE5pDshr" 2>&1
# Expected: No output (or "not found")

# Check for Discord URLs
git -C ~/containers grep "discord.com/api/webhooks" 2>&1
# Expected: No output (or "not found")

# Check .gitignore is working
git -C ~/containers status --ignored
# Should see:
#   config/alertmanager/alertmanager.yml (ignored)
#   Any *.env files (ignored)
```

### Runtime Check

Verify services are using environment variables:

```bash
# Webhook handler should log environment usage
journalctl --user -u remediation-webhook.service -n 50 | \
  grep -i "auth_token\|WEBHOOK_AUTH_TOKEN"

# Should NOT see:
#   "Using auth_token from config file"
# Should see:
#   "Starting webhook handler on 127.0.0.1:9096"
#   (No warnings about config file usage)
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ SECRETS ARCHITECTURE                                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ~/.config/remediation-webhook.env (600, NOT in Git)       │
│  ┌────────────────────────────────────────┐                │
│  │ WEBHOOK_AUTH_TOKEN=<secret>            │                │
│  └───────────────┬────────────────────────┘                │
│                  │                                          │
│                  │ EnvironmentFile=                        │
│                  ▼                                          │
│  remediation-webhook.service                                │
│  ┌────────────────────────────────────────┐                │
│  │ Environment: WEBHOOK_AUTH_TOKEN=*****  │                │
│  │ ExecStart: webhook-handler.py          │                │
│  └───────────────┬────────────────────────┘                │
│                  │                                          │
│                  │ os.environ.get('WEBHOOK_AUTH_TOKEN')    │
│                  ▼                                          │
│  remediation-webhook-handler.py                             │
│  ┌────────────────────────────────────────┐                │
│  │ expected_token = os.environ.get(...)   │                │
│  │ if token == expected_token: allow      │                │
│  └────────────────────────────────────────┘                │
│                                                             │
│  ┌─────────────────────────────────────────────┐           │
│  │ Alertmanager (separate config)              │           │
│  │ ┌─────────────────────────────────────────┐ │           │
│  │ │ webhook URL includes token as query     │ │           │
│  │ │ param (not ideal, but Alertmanager      │ │           │
│  │ │ limitation)                              │ │           │
│  │ └─────────────────────────────────────────┘ │           │
│  │ File: alertmanager.yml (in .gitignore)      │           │
│  └─────────────────────────────────────────────┘           │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Comparison Table

| Feature | Podman Secrets | EnvironmentFile | Secure Files |
|---------|----------------|-----------------|--------------|
| **Encryption** | ✅ Yes | ❌ No | ❌ No |
| **For containers** | ✅ Yes | ❌ No | ⚠️ Via mount |
| **For systemd services** | ❌ No | ✅ Yes | ✅ Yes |
| **Native integration** | ✅ Podman | ✅ Systemd | ❌ Manual |
| **Ease of rotation** | ✅ Easy | ✅ Easy | ⚠️ Manual |
| **Git protection** | ✅ Automatic | ⚠️ Need .gitignore | ⚠️ Need .gitignore |
| **Debugging** | ⚠️ Harder | ✅ Easy | ✅ Easy |
| **Permissions** | 🔒 Encrypted | 🔒 Mode 600 | 🔒 Mode 600 |
| **Best for** | Containers | Systemd services | Legacy scripts |

**Recommendation hierarchy:**
1. **Podman Secrets** - if running in container
2. **EnvironmentFile** - if systemd service (not containerized)
3. **Secure Files** - only if neither above applies

---

## Best Practices

1. **Choose the right method for your service type**
   - Containers → Podman secrets (encrypted)
   - Systemd services → EnvironmentFile
   - Scripts → Secure files (mode 600)

2. **Never commit secrets to Git**
   - Use `.env` files in `~/.config/` or `~/.secret/`
   - Add to `.gitignore` immediately
   - Use Podman secrets for containers (auto-protected)

3. **Prefer encryption when available**
   - Podman secrets provide encryption at rest
   - EnvironmentFile is plain text (but mode 600)
   - Consider migrating services to containers to use Podman secrets

4. **Strict file permissions**
   - Secrets files: `chmod 600` (owner-only)
   - Config directories: `chmod 700` (owner-only access)
   - Podman secrets: Automatic (encrypted storage)

5. **Rotate regularly**
   - Webhook tokens: Annually or after suspected exposure
   - API keys: Per service policy
   - Passwords: 90 days or per policy

6. **Audit before commits**
   - Run `git diff` before committing
   - Check for patterns like `token=`, `password=`, `webhook_url=`
   - Use pre-commit hooks if available

7. **Document everything**
   - Keep this guide updated
   - Document new secrets in this file
   - Include rotation procedures

---

## Podman Secrets Patterns & Migration Strategy

**(ADR-016: Secrets via Platform Primitives)**

### Pattern Hierarchy (Preference Order)

**Pattern 2 (RECOMMENDED): `type=env` - Environment Variable Injection**
```bash
# Create secret
echo -n "my-secret-value" | podman secret create service_password -

# Use in quadlet
[Container]
Secret=service_password,type=env,target=SERVICE_PASSWORD

# App reads from environment variable
SERVICE_PASSWORD=my-secret-value
```

✅ **Use Pattern 2 when:**
- Application supports environment variable configuration
- Secret is a simple string/token/password
- No complex file format required

**Pattern 1 (ACCEPTABLE): `type=mount` - File Mount**
```bash
# Create secret
podman secret create authelia_config - < config.yml

# Use in quadlet
[Container]
Secret=authelia_config,type=mount,target=/config/configuration.yml,mode=0400

# App reads from file path
/config/configuration.yml
```

✅ **Use Pattern 1 when:**
- Application REQUIRES file-based configuration (e.g., `file://` URL schemes)
- Complex YAML/JSON structure needed
- Pattern 2 not feasible (Authelia, some apps with file:// URIs)

**Pattern 3 (MIGRATE): Shell Expansion - `${SECRET_VAR}`**
```bash
# DEPRECATED - Migrate to Pattern 2
Environment=${SOME_SECRET}

# INSTEAD USE:
Secret=some_secret,type=env,target=SOME_SECRET
```

⚠ **Migrate Pattern 3 to Pattern 2:**
1. Back up current .env file to Vaultwarden
2. Create podman secrets from values
3. Update quadlet to use Secret= with type=env
4. Test service restart
5. Decommission .env file after successful migration

**Pattern 4 (FIX): EnvironmentFile**
```bash
# LEGACY - Migrate to Pattern 2 for containers
[Container]
EnvironmentFile=/path/to/.env

# INSTEAD USE:
Secret=var1,type=env,target=VAR1
Secret=var2,type=env,target=VAR2
```

⚠ **Fix Pattern 4:**
- Acceptable for bare systemd services (non-containerized)
- For containers, migrate to Podman secrets Pattern 2
- Vaultwarden: migrate EnvironmentFile to podman secrets

### Migration Procedure

**Step-by-step migration from .env files to podman secrets:**

```bash
# 1. Backup to Vaultwarden (CRITICAL)
# Create secure note in Vaultwarden with current .env contents

# 2. Create podman secrets from .env
while IFS='=' read -r key value; do
  [[ "$key" =~ ^#.*$ ]] && continue  # Skip comments
  echo -n "$value" | podman secret create "${service}_${key,,}" -
done < ~/.config/service/.env

# 3. Update quadlet (replace EnvironmentFile with Secret=)
nano ~/.config/containers/systemd/service.container

# Before:
EnvironmentFile=%h/.config/service/.env

# After:
Secret=service_var1,type=env,target=VAR1
Secret=service_var2,type=env,target=VAR2

# 4. Test restart
systemctl --user daemon-reload
systemctl --user restart service.service

# 5. Verify service health
systemctl --user status service.service
podman logs service

# 6. Decommission .env file (ONLY after successful verification)
mv ~/.config/service/.env ~/.config/service/.env.decommissioned-$(date +%Y%m%d)
```

**Decommissioning policy:**
- ✅ Decommission files ONLY after:
  - Secret imported to podman secrets ✓
  - Backed up in Vaultwarden ✓
  - Service tested and verified working ✓
- ⏸ Keep .env.decommissioned-YYYYMMDD for 30 days as safety net
- 🗑 Securely delete after 30 days: `shred -u file`

### Current Status (As of 2025-12-31)

**Services using Pattern 2 (type=env):** 15 secrets ✅ (RECOMMENDED)
- Most services successfully migrated

**Services using Pattern 1 (type=mount):** 0 secrets (Acceptable)
- Authelia uses file:// URIs - Pattern 1 is appropriate

**Services using Pattern 3 (shell expansion):** TBD (MIGRATE)
- Candidate for migration to Pattern 2

**Services using Pattern 4 (EnvironmentFile):** 1 file (MIGRATE)
- Candidate: migrate to Pattern 2 with Vaultwarden backup

**Migration goal:** 100% Pattern 2 where feasible, Pattern 1 where file:// required

---

## Troubleshooting

### "No auth_token configured" error

**Cause:** Environment variable not loaded or secrets file missing

**Fix:**
```bash
# Check secrets file exists
ls -l ~/.config/remediation-webhook.env

# Check systemd service references it
systemctl --user cat remediation-webhook.service | grep EnvironmentFile

# Reload and restart
systemctl --user daemon-reload
systemctl --user restart remediation-webhook.service
```

### "Using auth_token from config file" warning

**Cause:** Environment variable not set, falling back to config file (less secure)

**Fix:**
```bash
# Ensure WEBHOOK_AUTH_TOKEN is set in secrets file
grep WEBHOOK_AUTH_TOKEN ~/.config/remediation-webhook.env

# Restart service to reload environment
systemctl --user restart remediation-webhook.service
```

### Alertmanager returns 401 Unauthorized

**Cause:** Token in alertmanager.yml doesn't match webhook handler token

**Fix:**
```bash
# Sync tokens
TOKEN=$(grep WEBHOOK_AUTH_TOKEN ~/.config/remediation-webhook.env | cut -d= -f2)
sed -i "s|token=[^']*|token=$TOKEN|" ~/containers/config/alertmanager/alertmanager.yml
systemctl --user restart alertmanager.service
```

---

## Related Documentation

- [Security Audit Guide](./security-audit.md)
- [Remediation Webhook Documentation](../../20-operations/guides/remediation-webhook.md)
- [Alertmanager Configuration](../../40-monitoring-and-documentation/guides/alertmanager-config.md)
