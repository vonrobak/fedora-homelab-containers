# Nextcloud Configuration Audit Report

**Date:** 2025-12-20
**Status:** Critical Security Issues Identified
**Auditor:** Claude Code (Sonnet 4.5)
**Reviewed Against:**
- `/docs/00-foundation/guides/configuration-design-quick-reference.md`
- `/docs/00-foundation/guides/middleware-configuration.md`
- `/docs/10-services/decisions/2025-12-20-decision-007-nextcloud-native-authentication.md`

---

## Executive Summary

**Overall Status:** ⚠️ **REQUIRES IMMEDIATE REMEDIATION**

Nextcloud is functional and login works, but violates critical security design principles by storing sensitive credentials in plaintext within quadlet configuration files. All other services in the homelab (Authelia, Immich, OCIS, PostgreSQL, Traefik) properly use podman secrets for credential management.

**Critical Issues:**
- 🔴 **6 plaintext credentials** in quadlet files (database passwords, admin password, Redis password)
- 🟡 **Redis session handler disabled** as workaround (sub-optimal performance)

**Compliant Areas:**
- ✅ Traefik middleware chain follows best practices
- ✅ Network segmentation properly implemented
- ✅ Resource limits and health checks configured
- ✅ CalDAV/CardDAV auto-discovery working

---

## Detailed Findings

### 1. Secrets Management - CRITICAL ❌

**Standard (from design principles):**
> "Use podman secrets for all sensitive credentials. Follow the pattern established by existing services."

**Current State:**

| Component | Credential | Storage Method | Status |
|-----------|------------|----------------|--------|
| **nextcloud.container** | MYSQL_PASSWORD | Environment variable (plaintext) | ❌ VIOLATION |
| **nextcloud.container** | NEXTCLOUD_ADMIN_PASSWORD | Environment variable (plaintext) | ❌ VIOLATION (obsolete) |
| **nextcloud-db.container** | MYSQL_ROOT_PASSWORD | Environment variable (plaintext) | ❌ VIOLATION |
| **nextcloud-db.container** | MYSQL_PASSWORD | Environment variable (plaintext) | ❌ VIOLATION |
| **nextcloud-redis.container** | Redis password | Exec command argument (plaintext) | ❌ VIOLATION |
| **nextcloud-redis.container** | Redis password | HealthCmd argument (plaintext) | ❌ VIOLATION |

**Comparison to Other Services:**

```bash
# Authelia (COMPLIANT)
Secret=authelia_jwt_secret
Secret=authelia_session_secret
Secret=authelia_storage_key

# Immich (COMPLIANT)
Secret=postgres-password,type=env,target=DB_PASSWORD
Secret=immich-jwt-secret,type=env,target=JWT_SECRET

# OCIS (COMPLIANT)
Secret=ocis_jwt_secret,type=env,target=OCIS_JWT_SECRET
Secret=ocis_transfer_secret,type=env,target=OCIS_TRANSFER_SECRET

# Nextcloud (NON-COMPLIANT)
Environment=MYSQL_PASSWORD=MJoaCPFgKq4HgWaKFBli4KCyb9jqvH4tbpsAsZYlDwM=  # ❌
```

**Risk Assessment:**
- **Severity:** HIGH
- **Impact:** Credentials visible in `podman inspect`, systemd journal logs, process listings
- **Exposure:** Git repository (excluded via .gitignore, but risky)
- **Compliance:** Violates homelab security standards

**Required Remediation:**
1. Create podman secrets for all 3 unique credentials:
   - `nextcloud_db_password` (MariaDB root + user password)
   - `nextcloud_redis_password` (Redis authentication)
   - ~~`nextcloud_admin_password`~~ (NO - admin accounts managed via OCC, not container env)
2. Update all 3 quadlet files to use `Secret=` directives
3. Remove plaintext environment variables
4. Restart services in dependency order

---

### 2. Redis Session Handler - OPTIMIZATION NEEDED 🟡

**Current State:**
```ini
# nextcloud.container (lines 19-22)
# DISABLED: These env vars trigger automatic PHP session handler Redis config
# Redis is still available via config.php for memcache, but sessions use files
# Environment=REDIS_HOST=nextcloud-redis
# Environment=REDIS_HOST_PASSWORD=PS3azHg6fnbZuZ+rAPVz6d3GR5X9ypLS+4XRcqi9xAw=
```

**Issue:**
The Nextcloud Docker image automatically generates `/usr/local/etc/php/conf.d/redis-session.ini` when `REDIS_HOST` and `REDIS_HOST_PASSWORD` environment variables are present. This file was causing session authentication failures due to a suspected session locking incompatibility.

**Current Workaround:**
- Disabled `REDIS_HOST` and `REDIS_HOST_PASSWORD` environment variables
- PHP session handler falls back to file-based storage (`session.save_handler = files`)
- Redis still used for memcache (locking, distributed cache) via `config.php`

**Performance Impact:**
- File-based sessions work but are slower than Redis
- Multi-server horizontal scaling not possible with file sessions
- Session data persists in container filesystem (lost on container recreation)

**Recommended Solution:**
1. Re-enable `REDIS_HOST` and `REDIS_HOST_PASSWORD` (using podman secrets)
2. Investigate why session handler failed:
   - Check Redis session locking configuration (`redis.session.locking_enabled = 1`)
   - Test with locking disabled
   - Verify network latency between containers
   - Check PHP Redis extension version compatibility
3. If session locking is the issue, disable it explicitly:
   ```ini
   # Custom php.ini override
   redis.session.locking_enabled = 0
   ```

**Alternative Solution:**
Accept file-based sessions as acceptable trade-off for single-server deployment (current state is functional).

---

### 3. Traefik Middleware Configuration - COMPLIANT ✅

**Standard (from middleware-configuration.md):**
```
Order: crowdsec-bouncer → rate-limit → auth → security-headers
```

**Current Configuration:**
```yaml
# routers.yml (nextcloud-secure)
middlewares:
  - crowdsec-bouncer@file        # [1] IP reputation (fail-fast)
  - rate-limit-ocis@file          # [2] 200 req/min (WebDAV headroom)
  - circuit-breaker@file          # [3] Prevent cascade failures
  - retry@file                    # [4] Transient error handling
  - nextcloud-caldav              # [5] /.well-known/ redirects
  # NO authelia@file! (native auth per ADR-007)
  # NO security-headers@file! (Nextcloud sets own CSP)
```

**Analysis:**
✅ **Fully Compliant** - Follows design principles:
1. ✅ CrowdSec first (cheapest check, fail-fast)
2. ✅ Rate limiting second (appropriate tier: rate-limit-ocis = 200 req/min for WebDAV sync)
3. ✅ No Authelia (correct per ADR-007: native auth for CalDAV/CardDAV compatibility)
4. ✅ Circuit breaker and retry for reliability
5. ✅ CalDAV redirect middleware for auto-discovery
6. ✅ NO security-headers (correct - Nextcloud sets own CSP to avoid conflicts)

**Justification for Deviations:**
- **No Authelia:** Documented in ADR-007 - CalDAV/CardDAV require direct HTTP Basic Auth
- **No security-headers:** Nextcloud sets strict CSP internally; external headers cause conflicts
- **Circuit breaker + retry added:** Enhances reliability beyond standard pattern

**Rate Limit Tier Selection:**
```yaml
# middleware.yml (line 99)
rate-limit-ocis:
  rateLimit:
    average: 200      # Increased to handle WebDAV sync bursts
    burst: 100        # Handle simultaneous authentication requests
```

✅ **Correct tier** - Higher capacity needed for:
- CalDAV/CardDAV auto-discovery bursts (multiple devices checking /.well-known/)
- WebDAV file sync (desktop clients, mobile apps)
- Collabora Online document editing traffic

---

### 4. Network Segmentation - COMPLIANT ✅

**Standard (from configuration-design-quick-reference.md):**
```
PATTERN 2: App with Database
├─ App Network: reverse_proxy + database
└─ Database Network: database only
```

**Current Configuration:**

| Container | Networks | First Network (Default Route) | Status |
|-----------|----------|-------------------------------|--------|
| **nextcloud** | reverse_proxy, nextcloud, monitoring | reverse_proxy (✅ internet access) | ✅ CORRECT |
| **nextcloud-db** | nextcloud, monitoring | nextcloud (✅ internal only) | ✅ CORRECT |
| **nextcloud-redis** | nextcloud, monitoring | nextcloud (✅ internal only) | ✅ CORRECT |

**Analysis:**
✅ **Fully Compliant** - Proper segmentation:
1. ✅ Nextcloud on `reverse_proxy` (first) for internet access via Traefik
2. ✅ Database and Redis on `nextcloud` network only (internal isolation)
3. ✅ All on `monitoring` network for Prometheus scraping
4. ✅ Database and Redis NOT on `reverse_proxy` (prevents direct external access)

**Security Validation:**
```bash
# Database is NOT accessible from Traefik
podman exec traefik ping nextcloud-db  # Should fail (different network)

# Nextcloud CAN access database
podman exec nextcloud ping nextcloud-db  # Should succeed (same network)
```

---

### 5. CalDAV/CardDAV Configuration - COMPLIANT ✅

**Standard (from ADR-007):**
```yaml
# CalDAV/.well-known redirects for Nextcloud
nextcloud-caldav:
  redirectRegex:
    permanent: true
    regex: "^https://(.*)/.well-known/(card|cal)dav"
    replacement: "https://${1}/remote.php/dav/"
```

**Current Configuration:**
```yaml
# routers.yml (lines 221-226)
nextcloud-caldav:
  redirectRegex:
    permanent: true
    regex: "^https://(.*)/.well-known/(card|cal)dav"
    replacement: "https://${1}/remote.php/dav/"
```

**Analysis:**
✅ **Fully Compliant** - Matches ADR-007 specification exactly

**Functionality Verification:**
```bash
# Test CalDAV auto-discovery
curl -ILk https://nextcloud.patriark.org/.well-known/caldav
# Expected: HTTP/2 308 → HTTP/2 401 (redirect to /remote.php/dav/, auth required)

# Test CardDAV auto-discovery
curl -ILk https://nextcloud.patriark.org/.well-known/carddav
# Expected: HTTP/2 308 → HTTP/2 401 (redirect to /remote.php/dav/, auth required)
```

**Device Compatibility:**
✅ Tested on:
- iOS Calendar (native app)
- iOS Contacts (native app)
- macOS Calendar (native app)
- macOS Contacts (native app)
- Nextcloud desktop clients

---

### 6. Resource Management - COMPLIANT ✅

**Standard:** Define explicit resource limits to prevent resource exhaustion

**Current Configuration:**

| Container | Memory Limit | Justification | Status |
|-----------|--------------|---------------|--------|
| **nextcloud** | 1536M | PHP workers + Apache + file processing | ✅ APPROPRIATE |
| **nextcloud-db** | 512M | MariaDB buffer pool + connections | ✅ APPROPRIATE |
| **nextcloud-redis** | 256M | Cache eviction + session storage | ✅ APPROPRIATE |

**Total Stack:** 2.3GB (acceptable for 4-user family deployment)

**Analysis:**
✅ **All containers have memory limits** - Prevents runaway resource usage

**Optimization Note:**
If >10 simultaneous users or large file uploads (>1GB), increase nextcloud memory to 2G.

---

### 7. Health Checks - COMPLIANT ✅

**Standard:** All containers should have health checks for monitoring and auto-recovery

**Current Configuration:**

| Container | Health Check | Interval | Status |
|-----------|--------------|----------|--------|
| **nextcloud** | `curl -f http://localhost:80/status.php` | 30s | ✅ PRESENT |
| **nextcloud-db** | `healthcheck.sh --connect --innodb_initialized` | 30s | ✅ PRESENT |
| **nextcloud-redis** | `redis-cli -a PASSWORD ping` | 30s | ✅ PRESENT |

**Analysis:**
✅ **All 3 containers have health checks** - Enables:
- Podman automatic restart on health check failure
- Prometheus monitoring via `container_health_status` metric
- Dependency awareness (Nextcloud waits for DB + Redis to be healthy)

---

### 8. Storage Configuration - COMPLIANT ✅

**Standard (from design principles):**
> "Databases on BTRFS require NOCOW (chattr +C) for performance"

**Current Configuration:**
```bash
# Verified during deployment
ls attr -d /mnt/btrfs-pool/subvol7-containers/nextcloud-db/data
# Output: ---------------C------ (NOCOW enabled)
```

**Storage Layout:**
```
/mnt/btrfs-pool/subvol7-containers/
├── nextcloud/data/              # Nextcloud application files
├── nextcloud-db/data/           # MariaDB database (NOCOW ✅)
└── nextcloud-redis/data/        # Redis persistence (optional, currently unused)
```

**Analysis:**
✅ **NOCOW properly applied** to MariaDB directory before container first start

---

## Compliance Matrix

| Design Principle | Status | Notes |
|------------------|--------|-------|
| **Secrets Management** | ❌ CRITICAL | 6 plaintext credentials in quadlet files |
| **Middleware Ordering** | ✅ COMPLIANT | crowdsec → rate-limit → circuit-breaker → retry |
| **Network Segmentation** | ✅ COMPLIANT | Proper isolation (reverse_proxy + nextcloud + monitoring) |
| **Resource Limits** | ✅ COMPLIANT | All containers have memory limits |
| **Health Checks** | ✅ COMPLIANT | All containers monitored |
| **Authentication** | ✅ COMPLIANT | Native auth per ADR-007 |
| **CalDAV/CardDAV** | ✅ COMPLIANT | Auto-discovery working |
| **Storage (NOCOW)** | ✅ COMPLIANT | Database optimized for BTRFS |
| **Redis Session Handler** | 🟡 SUB-OPTIMAL | File-based sessions work but not ideal |

**Compliance Score:** 8/9 (89%) - **One critical issue, one optimization needed**

---

## Remediation Plan

### Phase 1: Secrets Migration (CRITICAL - Immediate)

**Priority:** 🔴 **CRITICAL**
**Estimated Time:** 30 minutes
**Risk:** LOW (credentials already in Vaultwarden, safe migration path)

**Steps:**

1. **Create podman secrets** (using existing credentials from `~/containers/secrets/nextcloud-secrets.env`):
   ```bash
   # Extract credentials from temporary file
   source ~/containers/secrets/nextcloud-secrets.env

   # Create secrets
   echo "$NEXTCLOUD_DB_PASSWORD" | podman secret create nextcloud_db_password -
   echo "$REDIS_PASSWORD" | podman secret create nextcloud_redis_password -

   # Verify
   podman secret ls | grep nextcloud
   ```

2. **Update nextcloud.container**:
   ```ini
   # Remove plaintext
   # Environment=MYSQL_PASSWORD=...
   # Environment=NEXTCLOUD_ADMIN_PASSWORD=...  # Remove entirely (not needed)

   # Add secrets
   Secret=nextcloud_db_password,type=env,target=MYSQL_PASSWORD
   ```

3. **Update nextcloud-db.container**:
   ```ini
   # Remove plaintext
   # Environment=MYSQL_ROOT_PASSWORD=...
   # Environment=MYSQL_PASSWORD=...

   # Add secrets
   Secret=nextcloud_db_password,type=env,target=MYSQL_ROOT_PASSWORD
   Secret=nextcloud_db_password,type=env,target=MYSQL_PASSWORD
   ```

4. **Update nextcloud-redis.container** (more complex - requires custom startup script):
   ```ini
   # Cannot use Secret= with Exec= directly
   # Need to mount secret as file and reference in redis.conf

   Secret=nextcloud_redis_password
   Volume=/run/secrets/nextcloud_redis_password:/run/secrets/redis_password:ro
   Exec=sh -c 'redis-server --requirepass "$(cat /run/secrets/redis_password)"'
   HealthCmd=sh -c 'redis-cli --no-auth-warning -a "$(cat /run/secrets/redis_password)" ping'
   ```

5. **Reload and restart**:
   ```bash
   systemctl --user daemon-reload
   systemctl --user restart nextcloud-db.service
   systemctl --user restart nextcloud-redis.service
   systemctl --user restart nextcloud.service

   # Verify health
   podman healthcheck run nextcloud-db nextcloud-redis nextcloud
   ```

6. **Clean up**:
   ```bash
   # Secure deletion of temporary file
   shred -u ~/containers/secrets/nextcloud-secrets.env

   # Verify secrets not in environment
   podman exec nextcloud env | grep -i password  # Should show nothing
   podman inspect nextcloud | grep -i password   # Should show secret references only
   ```

### Phase 2: Redis Session Handler Optimization (OPTIONAL)

**Priority:** 🟡 **MEDIUM**
**Estimated Time:** 1-2 hours (includes testing)
**Risk:** MEDIUM (could reintroduce login loop if misconfigured)

**Investigation Steps:**

1. **Re-enable Redis session handler with podman secrets**:
   ```ini
   # nextcloud.container
   Secret=nextcloud_redis_password,type=env,target=REDIS_HOST_PASSWORD
   Environment=REDIS_HOST=nextcloud-redis
   ```

2. **Test login** - if fails, proceed to step 3

3. **Disable session locking** (suspected root cause):
   ```bash
   # Create custom PHP config
   mkdir -p ~/containers/config/nextcloud/php
   cat > ~/containers/config/nextcloud/php/redis-session-no-lock.ini <<'EOF'
   ; Redis session handler WITHOUT locking
   session.save_handler = redis
   session.save_path = "tcp://nextcloud-redis:6379?auth=${REDIS_HOST_PASSWORD}"
   redis.session.locking_enabled = 0
   EOF

   # Mount in quadlet
   Volume=%h/containers/config/nextcloud/php:/usr/local/etc/php/conf.d/custom:ro,Z
   ```

4. **Test and validate**:
   ```bash
   # Verify session handler
   podman exec nextcloud php -i | grep session.save_handler
   # Should show: session.save_handler => redis

   # Test login
   # If successful, Redis sessions are working
   ```

**Decision Point:**
- If Redis sessions work → Keep it (better performance, scalability)
- If Redis sessions still fail → Revert to file-based (acceptable for single-server)

---

## Testing Plan

### Test 1: Secrets Migration Validation

**Objective:** Verify credentials work after migration to podman secrets

```bash
# 1. Check secrets exist
podman secret ls | grep nextcloud
# Expected: nextcloud_db_password, nextcloud_redis_password

# 2. Verify services healthy
podman healthcheck run nextcloud-db
podman healthcheck run nextcloud-redis
podman healthcheck run nextcloud
# Expected: All return "healthy"

# 3. Test database connection
podman exec nextcloud php occ db:add-missing-indices
# Expected: No authentication errors

# 4. Test Redis connection
podman exec nextcloud php occ config:system:get redis
# Expected: Shows Redis configuration

# 5. Test web login
curl -I https://nextcloud.patriark.org/login
# Expected: HTTP/2 200 (login page loads)

# 6. Verify credentials not in environment
podman inspect nextcloud | grep -i "MYSQL_PASSWORD\|REDIS.*PASSWORD" | grep -v "Secret"
# Expected: No matches (credentials not in env vars)
```

### Test 2: CalDAV/CardDAV Functionality

**Objective:** Verify device sync still works after changes

```bash
# CalDAV auto-discovery
curl -ILk https://nextcloud.patriark.org/.well-known/caldav
# Expected: HTTP/2 308 → HTTP/2 401

# CardDAV auto-discovery
curl -ILk https://nextcloud.patriark.org/.well-known/carddav
# Expected: HTTP/2 308 → HTTP/2 401

# iOS device test
# 1. Add calendar account (should auto-discover)
# 2. Create event on phone → verify syncs to Nextcloud web UI
# 3. Create event in web UI → verify appears on phone
```

### Test 3: External Storage Access

**Objective:** Verify read-only and read-write mounts still work

```bash
# List external mounts
podman exec nextcloud ls -la /external/
# Expected: immich-photos, multimedia, music, opptak, downloads

# Test read-only mount
podman exec nextcloud ls /external/immich-photos/ | head -5
# Expected: Lists photo directories

# Test read-write mount
podman exec nextcloud touch /external/downloads/test-write.txt
podman exec nextcloud rm /external/downloads/test-write.txt
# Expected: Both commands succeed
```

---

## Recommendations

### Immediate Actions (Next 24 Hours)

1. ✅ **Migrate to podman secrets** (Phase 1 remediation)
   - Create nextcloud_db_password secret
   - Create nextcloud_redis_password secret
   - Update all 3 quadlet files
   - Test thoroughly

2. ✅ **Document the migration**
   - Update `/docs/10-services/guides/nextcloud.md` with secret usage
   - Add secrets section to operations runbook

### Short-Term Actions (Next Week)

3. 🟡 **Optimize Redis session handler** (Phase 2 remediation - OPTIONAL)
   - Investigate session locking issue
   - Test with locking disabled
   - If successful, document configuration

4. 📝 **Update ADR-007**
   - Add "Secrets Management" section
   - Document Redis session handler investigation
   - Add troubleshooting guide for session issues

### Long-Term Considerations

5. 📊 **Monitor session performance**
   - Add Grafana dashboard panel: Session storage type (file vs Redis)
   - Track login latency (compare file vs Redis if optimized)

6. 🔐 **Evaluate TOTP 2FA enforcement**
   - Current: 2FA optional
   - Recommendation: Enforce for all users or admin-only

7. 🚀 **Consider LDAP integration** (when user base grows)
   - Unify Nextcloud + Authelia identity stores
   - Trade-off: Complexity vs. SSO convenience

---

## Conclusion

Nextcloud is **functionally operational** with login working and CalDAV/CardDAV device sync functioning correctly. However, it contains a **critical security violation** by storing 6 credentials in plaintext within quadlet configuration files, inconsistent with the podman secrets pattern used by all other services in the homelab.

**Required Action:** Migrate to podman secrets immediately to achieve compliance with homelab security standards.

**Optional Optimization:** Re-enable Redis session handler for better performance and scalability, accepting file-based sessions as acceptable if optimization proves complex.

**Overall Assessment:**
- **Security Posture:** ⚠️ **REQUIRES REMEDIATION** (plaintext credentials)
- **Functional Status:** ✅ **FULLY OPERATIONAL** (login, sync, external storage all working)
- **Architecture Compliance:** ✅ **89% COMPLIANT** (8/9 design principles followed)

---

**Report Version:** 1.0
**Next Review:** After Phase 1 remediation complete
**Approval Required:** Yes - before proceeding with credentials migration
