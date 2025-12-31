# Journal Entry: Vaultwarden Secrets Migration to Pattern 2

**Date:** 2025-12-31
**Session Duration:** ~45 minutes
**Status:** Complete
**Related:** ADR-016 (Secrets via Platform Primitives), `docs/30-security/guides/secrets-management.md`

---

## Context

Final secrets management migration implementing ADR-016 Pattern 2 (podman secrets with `type=env`) for Vaultwarden, the last service using Pattern 4 (EnvironmentFile).

**Goal:** Migrate Vaultwarden from EnvironmentFile to podman secrets with Argon2-hashed admin token, completing the homelab-wide secrets standardization.

---

## Migration Summary

### Before (Pattern 4)
```ini
[Container]
EnvironmentFile=%h/containers/config/vaultwarden/vaultwarden.env
```

**File:** `~/containers/config/vaultwarden/vaultwarden.env`
- Plain text admin token (base64-encoded)
- Mixed secrets and configuration
- No encryption at rest

### After (Pattern 2)
```ini
[Container]
# Secret (Pattern 2: type=env - migrated 2025-12-31, Argon2 hash applied)
# Admin panel DISABLED - no admin token provided (uncomment Secret line to re-enable)
# Secret=vaultwarden_admin_token,type=env,target=ADMIN_TOKEN

# Essential configuration (non-secrets)
Environment=DOMAIN=https://vault.patriark.org
Environment=SIGNUPS_ALLOWED=false
Environment=INVITATIONS_ALLOWED=true
# ... (14 total environment variables)
```

**Secret Storage:** Podman encrypted secrets
- Argon2id-hashed admin token
- Encrypted at rest
- Accessed via environment variable injection

---

## Migration Procedure

### Phase 1: Token Generation & Backup

1. **Extracted old admin token** from commented line in .env file
2. **Generated new admin token:**
   ```bash
   openssl rand -base64 48
   # Result: rvxDvEmQgtfMsR/4j/3tK8/wvAR4jxD7/p0bu3GIK28mkXGl4V5bpRFo/t7uSI+o
   ```
3. **User backed up both tokens** to Vaultwarden vault (secure note)

### Phase 2: Podman Secret Creation (Plain Text)

```bash
echo -n "rvxDvEmQgtfMsR/4j/3tK8/wvAR4jxD7/p0bu3GIK28mkXGl4V5bpRFo/t7uSI+o" | \
  podman secret create vaultwarden_admin_token -
```

### Phase 3: Quadlet Migration

**Updated:** `~/.config/containers/systemd/vaultwarden.container`

**Changes:**
- Removed: `EnvironmentFile=%h/containers/config/vaultwarden/vaultwarden.env`
- Added: `Secret=vaultwarden_admin_token,type=env,target=ADMIN_TOKEN`
- Converted 14 environment variables to `Environment=` directives
- Applied changes: `systemctl --user daemon-reload && systemctl --user restart vaultwarden.service`

**Verification:** ✅ Service healthy, main vault accessible, admin panel accessible with token

### Phase 4: Argon2 Hash Upgrade

Vaultwarden recommends Argon2 hashing for admin tokens instead of plain text.

```bash
# Generated Argon2id hash using container tool
podman exec -it vaultwarden /vaultwarden hash
# Entered plain text token, received Argon2id PHC string

# Updated podman secret with Argon2 hash
podman secret rm vaultwarden_admin_token
echo -n "$argon2id$v=19$m=65540,t=3,p=4$..." | \
  podman secret create vaultwarden_admin_token -

# Restarted service
systemctl --user restart vaultwarden.service
```

**User backed up Argon2 hash** to Vaultwarden vault.

**Verification:** ✅ Admin panel accessible with Argon2 hash

### Phase 5: Admin Panel Deactivation

For security, disabled admin panel access (can be re-enabled by uncommenting Secret line).

```ini
# Secret=vaultwarden_admin_token,type=env,target=ADMIN_TOKEN  # Commented out
```

**Verification:** ✅ Admin panel shows "admin panel is disabled" message

### Phase 6: Decommissioning

```bash
mv ~/containers/config/vaultwarden/vaultwarden.env \
   ~/containers/config/vaultwarden/vaultwarden.env.decommissioned-20251231
```

**Safety net:** 30-day retention period
**Secure deletion:** After 2025-01-30: `shred -u vaultwarden.env.decommissioned-20251231`

**Git protection:** Added `*.env.decommissioned-*` pattern to .gitignore

---

## Security Improvements

### Before
- ❌ Plain text admin token in file
- ❌ No encryption at rest
- ❌ EnvironmentFile accessible on filesystem

### After
- ✅ Argon2id-hashed admin token (industry standard)
- ✅ Encrypted storage via podman secrets
- ✅ Environment variable injection (no files)
- ✅ Admin panel disabled by default
- ✅ Dual backup (plain text + Argon2 hash in Vaultwarden vault)

---

## Configuration Details

### Podman Secret
- **Name:** `vaultwarden_admin_token`
- **Type:** env (Pattern 2)
- **Target:** ADMIN_TOKEN environment variable
- **Hash:** Argon2id v19, m=65540, t=3, p=4
- **Status:** Created, admin panel currently disabled (secret line commented)

### Environment Variables (14 total)
Essential non-secret configuration migrated to `Environment=` directives:
- DOMAIN, SIGNUPS_ALLOWED, INVITATIONS_ALLOWED
- DATABASE_URL, WEBSOCKET_ENABLED, WEBSOCKET_ADDRESS, WEBSOCKET_PORT
- PASSWORD_ITERATIONS, LOG_LEVEL, IP_HEADER
- ROCKET_ADDRESS, ROCKET_PORT

---

## Verification

```bash
# Service status
systemctl --user status vaultwarden.service
# ✅ Active (running)

# Podman secret exists
podman secret ls | grep vaultwarden
# ✅ vaultwarden_admin_token

# No admin token in environment (disabled)
podman exec vaultwarden env | grep ADMIN
# ✅ No output (admin panel disabled)

# Main vault accessible
curl -I https://vault.patriark.org
# ✅ HTTP 200

# Admin panel disabled
curl https://vault.patriark.org/admin
# ✅ "The admin panel is disabled, please configure the 'ADMIN_TOKEN' variable to enable it"
```

---

## Re-Enabling Admin Panel (Future Use)

**Method 1: Edit quadlet**
```bash
nano ~/.config/containers/systemd/vaultwarden.container
# Uncomment: Secret=vaultwarden_admin_token,type=env,target=ADMIN_TOKEN
systemctl --user daemon-reload && systemctl --user restart vaultwarden.service
```

**Method 2: One-liner**
```bash
sed -i 's/^# Secret=vaultwarden_admin_token/Secret=vaultwarden_admin_token/' \
  ~/.config/containers/systemd/vaultwarden.container && \
systemctl --user daemon-reload && systemctl --user restart vaultwarden.service
```

**Access:** https://vault.patriark.org/admin (use Argon2 hash from Vaultwarden vault)

---

## Secrets Management Status (Final)

**Pattern 2 (type=env):** 16 secrets ✅
- All containerized secrets now use Pattern 2
- Vaultwarden: Latest migration (Argon2 upgrade applied)

**Pattern 1 (type=mount):** 0 secrets
- Reserved for services requiring file:// URIs (e.g., Authelia)

**Pattern 3 (shell expansion):** 0 secrets
- Deprecated, all migrated

**Pattern 4 (EnvironmentFile):** 0 containers ✅
- ✅ **MIGRATION COMPLETE** - All containers migrated to Pattern 2
- Acceptable only for bare systemd services (non-containerized)

**Goal Achieved:** ✅ 100% Pattern 2 adoption for containerized secrets

---

## Lessons Learned

1. **Argon2 hashing recommended** - Plain text admin tokens work but Argon2id is industry best practice. Vaultwarden's built-in hash generator makes this easy.

2. **Admin panel security model** - `DISABLE_ADMIN_TOKEN=true` does NOT disable the admin panel, it disables the token requirement (security risk!). To disable admin panel: remove/comment the ADMIN_TOKEN secret.

3. **Interactive container commands** - `podman exec -it` required for interactive tools like `vaultwarden hash`. Non-interactive piping doesn't work for password prompts.

4. **Decommissioned file patterns** - `.gitignore` pattern `*.env` doesn't match `*.env.decommissioned-YYYYMMDD`. Added explicit pattern for safety.

5. **Dual backup strategy** - Keeping both plain text and Argon2 hash in secure vault provides flexibility (can use either for authentication, plain text for re-hashing if needed).

---

## Impact

### Immediate
- Vaultwarden admin token secured with Argon2id hashing
- Admin panel disabled for reduced attack surface
- Pattern 4 completely phased out for containers
- Decommissioned .env file protected from git commits

### Long-term
- ✅ 100% secrets standardization achieved (ADR-016 compliance)
- Simplified secrets management (single pattern for all containers)
- Enhanced security posture (encrypted storage, industry-standard hashing)
- Clear re-enablement path for admin panel when needed

---

## References

- ADR-016: Configuration Design Principles (Secrets via Platform Primitives)
- `docs/30-security/guides/secrets-management.md` - Complete migration guide
- `docs/98-journals/2025-12-31-tier-1-2-3-configuration-design-implementation.md` - Migration planning
- Vaultwarden Wiki: Enabling admin page - Secure the ADMIN_TOKEN

---

**Migration complete.** All containerized secrets now use Pattern 2 (podman secrets with environment variable injection), achieving 100% compliance with ADR-016 secrets management principles.
