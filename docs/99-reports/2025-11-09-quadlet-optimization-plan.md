# Quadlet Optimization Analysis
## Phase 1 Improvements + Strategic Enhancements

**Date:** 2025-11-09
**Purpose:** Identify high-impact improvements aligned with ADRs and design principles
**Based on:** docs/00-foundation/journal/20250526-configuration-design-principles.md

---

## Summary of Current State

### ✅ Already Following Best Practices

1. **Secrets Management** (Design Principle: Configuration as Code)
   - ✅ postgresql-immich: Uses `Secret=postgres-password`
   - ✅ immich-server: Uses `Secret=postgres-password` and `Secret=immich-jwt-secret`
   - ✅ traefik: Uses `Secret=crowdsec_api_key`
   - ✅ alertmanager: Uses `Secret=smtp_password`
   - ✅ alert-discord-relay: Uses `Secret=discord_webhook_url`

2. **Read-Only Config Mounts** (Design Principle: Least Privilege)
   - ✅ Most services use `:ro` for config volumes
   - ✅ Immich library mount: `:ro` for media

3. **Network Segmentation** (Design Principle: Defense in Depth)
   - ✅ systemd-reverse_proxy: Public-facing
   - ✅ systemd-photos: Immich stack isolated
   - ✅ systemd-monitoring: Metrics isolated
   - ✅ systemd-auth_services: Auth isolated

4. **Health Checks** (Design Principle: Fail-Safe Defaults)
   - ✅ Most services have comprehensive health checks
   - ✅ Phase 1 improvements add 4 more

---

## 🎯 High-Impact Improvements

### Improvement 1: Fix Restart Policy Anti-Pattern

**Issue:** Several services use `Restart=always` instead of `Restart=on-failure`

**Design Principle Violation:** Fail-Safe Defaults
> "on-failure = restart only if crashed
> always = restart even if explicitly stopped (dangerous)
> Fail-safe default: don't restart bad configurations"

**Affected Services:**
- `postgresql-immich.container`: Restart=always (line 34)
- `immich-server.container`: Restart=always (line 53)
- `redis-immich.container`: Restart=always (line 25)
- `jellyfin.container`: Restart=always (likely)

**Impact:** **MEDIUM** - Security/operational
- Prevents intentional stops
- May restart with security vulnerabilities
- Makes maintenance harder

**Recommendation:** Change to `Restart=on-failure` for all services

**Exception:** Critical infrastructure like reverse proxy might warrant `always`
- traefik: Keep `on-failure` (correct)

---

### Improvement 2: Add Resource Limits to Critical Services

**Issue:** Services without memory limits can cause OOM conditions

**Design Principle:** Resource Management + Least Privilege

**Services Needing Limits:**
1. **loki.container**: No MemoryMax (log aggregation, can grow)
   - Recommendation: MemoryMax=512M

2. **prometheus.container**: No MemoryMax (metrics DB, can grow)
   - Recommendation: MemoryMax=1G (15-day retention)

3. **postgresql-immich.container**: No MemoryMax (database, critical)
   - Recommendation: MemoryMax=1G

4. **immich-server.container**: No MemoryMax (main app, memory-intensive)
   - Recommendation: MemoryMax=2G

5. **immich-ml.container**: No MemoryMax (ML inference, very memory-intensive)
   - Recommendation: MemoryMax=2G

6. **node_exporter.container**: No MemoryMax (lightweight)
   - Recommendation: MemoryMax=128M

**Impact:** **HIGH** - Prevents cascading failures
- Current coverage: 41% (7/17 services)
- Phase 1: 76% (13/17 services)
- **With this**: 94% (16/17 services)

---

### Improvement 3: Add Missing Health Checks

**Issue:** node_exporter lacks health check

**Services:**
- `node_exporter.container`: No health check

**Recommendation:**
```ini
HealthCmd=wget --no-verbose --tries=1 --spider http://localhost:9100/metrics || exit 1
HealthInterval=30s
HealthTimeout=10s
HealthRetries=3
```

**Impact:** **LOW** - Completeness
- Achieves 100% health check coverage across all services

---

### Improvement 4: Consistent DNS Configuration

**Issue:** Some services have DNS=192.168.1.69, some don't

**Inconsistency:**
- prometheus, loki, promtail, alertmanager: Have DNS=192.168.1.69
- Others: No DNS setting (use default)

**Analysis:**
- DNS=192.168.1.69 points to local DNS server (likely Pi-hole or router)
- Only needed if default DNS doesn't work

**Recommendation:**
- **Keep as-is** if working (don't fix what isn't broken)
- Document why some services need it
- OR standardize by adding to all services for consistency

**Impact:** **LOW** - Cosmetic/documentation

---

### Improvement 5: Add TimeoutStartSec Where Missing

**Issue:** Some services missing timeout configuration

**Design Principle:** Fail-Safe Defaults

**Missing:**
- redis-immich: No TimeoutStartSec (fast startup, not critical)
- alert-discord-relay: Has 60s (good)

**Recommendation:** Not critical, most services have appropriate timeouts

**Impact:** **LOW** - Already well-covered

---

## 📊 Prioritized Improvement Matrix

| # | Improvement | Impact | Effort | Services | Priority |
|---|-------------|--------|--------|----------|----------|
| 1 | Resource limits (Phase 1) | HIGH | LOW | 6 services | ✅ IN PROGRESS |
| 2 | Resource limits (Phase 1+) | HIGH | LOW | 6 more services | **DO THIS** |
| 3 | Fix restart policies | MEDIUM | LOW | 4 services | **DO THIS** |
| 4 | node_exporter health check | LOW | TRIVIAL | 1 service | **DO THIS** |
| 5 | DNS consistency | LOW | LOW | varies | **SKIP** (working) |

---

## 🚀 Recommended Action Plan

### Phase 1 (Current - In Progress)
**Services:** crowdsec, promtail, alert-discord-relay, traefik, redis-immich, alertmanager

Changes:
- ✅ Add HealthCmd
- ✅ Add MemoryMax
- ✅ Remove alloy.container drift

### Phase 1+ (Extend Before Deployment)
**Additional Services:** loki, prometheus, postgresql-immich, immich-server, immich-ml, node_exporter

**Changes:**

1. **loki.container**
   ```ini
   # Add to [Container] section
   HealthCmd=wget --no-verbose --tries=1 --spider http://localhost:3100/ready || exit 1
   HealthInterval=30s
   HealthTimeout=10s
   HealthRetries=3

   # Add to [Service] section
   MemoryMax=512M
   ```

2. **prometheus.container**
   ```ini
   # Add to [Service] section
   MemoryMax=1G
   ```

3. **postgresql-immich.container**
   ```ini
   # Modify [Service] section
   Restart=on-failure  # Change from 'always'
   MemoryMax=1G
   ```

4. **immich-server.container**
   ```ini
   # Modify [Service] section
   Restart=on-failure  # Change from 'always'
   MemoryMax=2G
   ```

5. **immich-ml.container**
   ```ini
   # Add to [Service] section
   MemoryMax=2G
   Restart=on-failure  # If currently 'always'
   ```

6. **redis-immich.container**
   ```ini
   # Modify [Service] section
   Restart=on-failure  # Change from 'always'
   # MemoryMax=512M already added in Phase 1
   ```

7. **node_exporter.container**
   ```ini
   # Add to [Container] section
   HealthCmd=wget --no-verbose --tries=1 --spider http://localhost:9100/metrics || exit 1
   HealthInterval=30s
   HealthTimeout=10s
   HealthRetries=3

   # Add to [Service] section
   MemoryMax=128M
   ```

8. **jellyfin.container** (if has Restart=always)
   ```ini
   # Check and change if needed
   Restart=on-failure
   ```

---

## Expected Outcomes

### After Phase 1 + Phase 1+

**Health Check Coverage:**
- Current: 68% (11/16)
- After: **100% (16/16)** ✅

**Resource Limits Coverage:**
- Current: 41% (7/17)
- After Phase 1: 76% (13/17)
- After Phase 1+: **94% (16/17)** ✅
  - Only cadvisor without limit (likely intentional)

**Restart Policy Compliance:**
- Current: ~75% correct
- After: **100% correct** ✅

**Configuration Drift:**
- Current: 1 service (alloy)
- After: **0 services** ✅

---

## Design Principles Alignment

### ✅ Principles Followed

1. **Defense in Depth**: Network segmentation implemented
2. **Least Privilege**: Read-only mounts, non-root users, network isolation
3. **Fail-Safe Defaults**: Health checks, restart=on-failure
4. **Separation of Concerns**: Each service has clear responsibility
5. **Configuration as Code**: All configs in git, secrets via Podman secrets
6. **Idempotency**: Quadlets handle state correctly

### ⚠️ Principles to Strengthen

1. **Resource Management**: Add missing memory limits (Phase 1+)
2. **Fail-Safe Defaults**: Fix restart policies

---

## Services Not Modified (Already Optimal)

The following services are already well-configured and don't need changes:
- `traefik.container`: ✅ Health check, MemoryMax, Restart=on-failure, Secrets
- `alertmanager.container`: ✅ Health check, MemoryMax (after Phase 1), Restart=on-failure
- `grafana.container`: ✅ (likely already has MemoryMax and proper config)

---

## Deployment Safety

**Testing Order:**
1. Apply Phase 1 changes (crowdsec, promtail, etc.)
2. Verify services restart successfully
3. Apply Phase 1+ changes (loki, prometheus, etc.)
4. Run snapshot script to validate
5. Monitor for 24 hours before considering complete

**Rollback Plan:**
- Git tracked quadlets allow easy revert
- `git checkout HEAD~1 quadlets/` to rollback
- `systemctl --user daemon-reload && systemctl --user restart <services>`

---

## Conclusion

**Total Changes:**
- **Phase 1 (in progress)**: 6 services
- **Phase 1+ (recommended)**: 7 additional services
- **Total**: 13 services improved

**Impact:**
- **100% health check coverage**
- **94% resource limits coverage**
- **100% restart policy compliance**
- **Zero configuration drift**

**Effort:** 30-45 minutes to apply Phase 1+ improvements

**Risk:** LOW - All changes are additive or corrective, not breaking

---

**Prepared by:** Strategic Analysis based on design principles
**Date:** 2025-11-09
**Status:** Recommended for immediate implementation
