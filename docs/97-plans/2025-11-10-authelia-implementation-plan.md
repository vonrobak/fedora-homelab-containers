# Authelia Implementation Plan - Gradual Rollout

**Date:** 2025-11-10
**Status:** Planning
**Related:** ADR-004 (Authelia SSO & MFA Architecture)
**Current Auth:** TinyAuth (working, stable)

---

## Executive Summary

Gradual, service-by-service migration from TinyAuth to Authelia SSO with MFA. Conservative approach prioritizing stability, with extensive testing at each step and instant rollback capability.

**Key Principles:**
1. **No big-bang deployment** - One service at a time
2. **TinyAuth stays running** - Fallback always available
3. **Test extensively** - Each service validated before moving forward
4. **User-driven pace** - We proceed when you're comfortable, not on a schedule

---

## Current State Analysis

### Services Inventory (16 Services)

**Infrastructure & Security (5):**
- traefik (reverse proxy)
- crowdsec (IP reputation)
- tinyauth (current auth)
- alert-discord-relay
- (future: authelia)

**Media Services (2):**
- jellyfin (media streaming)
- immich-server (photo management)

**Immich Stack (3):**
- immich-ml (machine learning)
- postgresql-immich (database)
- redis-immich (cache)

**Monitoring Stack (6):**
- prometheus (metrics)
- grafana (dashboards) *[likely deployed]*
- loki (logs)
- alertmanager (alerting)
- promtail (log collection)
- node_exporter (system metrics)
- cadvisor (container metrics)

### Current Authentication

**TinyAuth Configuration:**
- Middleware: `http://tinyauth:3000/api/auth/traefik`
- Simple forward auth pattern
- Password-only (no MFA)
- Working and stable ✅

**Services Currently Protected:**
- Traefik dashboard (traefik.patriark.org)
- Jellyfin (jellyfin.patriark.org)
- Likely: Grafana, Prometheus, others

---

## Service Categorization & Access Policies

Based on ADR-004 principles, here's the proposed categorization:

### Tier 1: Administrative (Two-Factor Required)

**Services:**
- Grafana (dashboards)
- Prometheus (metrics)
- Traefik dashboard
- Alertmanager

**Access Policy:**
```yaml
policy: two_factor
subject: "group:admins"
```

**Rationale:**
- Infrastructure control interfaces
- Can view sensitive system data
- Can modify configurations
- **Highest security requirement**

**Users:** Admin accounts only (you)

---

### Tier 2: User Services (One-Factor)

**Services:**
- Jellyfin (media streaming)
- Immich (photos)

**Access Policy:**
```yaml
policy: one_factor
subject: "group:users"
```

**Rationale:**
- User-facing media services
- Personal content (not infrastructure)
- Balance between security and UX
- Can add MFA later if desired

**Users:** You + potential family/friends

---

### Tier 3: Internal Only (No Auth - Network Restricted)

**Services:**
- node_exporter
- cadvisor
- promtail
- loki (API)
- prometheus (API)
- redis-immich
- postgresql-immich

**Access Policy:**
```yaml
policy: bypass  # No Authelia required
middleware: internal-only  # IP whitelist only
```

**Rationale:**
- Backend services not exposed externally
- Accessed by other containers only
- Network segmentation provides security
- No need for user authentication

**Users:** N/A (service-to-service only)

---

### Tier 4: Public/Bypass (Health Checks)

**Resources:**
- Health check endpoints (`/api/health`, `/health`, `/ping`)
- Monitoring probes

**Access Policy:**
```yaml
policy: bypass
resources:
  - "^/api/health$"
  - "^/health$"
  - "^/ping$"
```

**Rationale:**
- Allow monitoring systems to check health
- No sensitive data exposed
- Required for reliability

---

## Key Decisions to Make

### 🤔 Decision 1: MFA Enrollment Strategy

**Option A: MFA Optional Initially (Recommended)**
- Deploy Authelia with MFA available
- Require MFA only for admin services (Tier 1)
- Let users enable MFA voluntarily for media services
- Gradually enforce MFA over time

**Option B: MFA Mandatory From Day One**
- All users must set up TOTP/WebAuthn immediately
- Higher security bar
- More friction during migration

**Recommendation:** Option A - Start with admin-only MFA, expand gradually

---

### 🤔 Decision 2: TOTP vs WebAuthn Priority

**TOTP (Time-Based One-Time Password):**
- ✅ Works with any authenticator app (Google Auth, Authy, 1Password)
- ✅ Easy to set up (scan QR code)
- ✅ Universal support
- ⚠️ Less secure than hardware keys (can be phished)

**WebAuthn (Hardware Keys):**
- ✅ Most secure (YubiKey, Titan, etc.)
- ✅ Phishing-resistant
- ✅ Biometric options (FaceID, fingerprint)
- ⚠️ Requires hardware purchase (~$50 for YubiKey)
- ⚠️ More complex setup

**Recommendation:** **Start with TOTP**, add WebAuthn support for your admin account later

---

### 🤔 Decision 3: Session Duration

**Proposed Settings:**
```yaml
session:
  expiration: 1h           # Hard timeout
  inactivity: 15m          # Idle timeout
  remember_me_duration: 1M # "Remember me" checkbox
```

**Questions:**
- Is 1 hour too short for daily usage? (Could go to 4h or 8h)
- Is 15min inactivity reasonable? (Could go to 30min or 1h)
- Should "remember me" be 1 month or longer?

**Recommendation:** Start with these defaults, adjust based on actual usage patterns

---

### 🤔 Decision 4: User Database Backend

**Option A: File-Based (Recommended for Start)**
- Users stored in `/config/users_database.yml`
- Simple, no additional dependencies
- Easy to backup and edit
- Sufficient for small user base (<10 users)

**Option B: Database-Backed (PostgreSQL)**
- Users in PostgreSQL
- Better for large user bases
- More complex setup
- Can migrate later if needed

**Recommendation:** Start with file-based, migrate if you exceed ~10 users

---

### 🤔 Decision 5: Migration Pace

**How fast should we go?**

**Option A: Slow & Steady (Recommended)**
- Week 1: Deploy Authelia + Redis, test with dummy service
- Week 2: Migrate 1-2 Tier 1 services (Grafana, Prometheus)
- Week 3: Migrate Tier 2 services (Jellyfin, Immich)
- Week 4: Stability testing, then decommission TinyAuth

**Option B: Sprint Approach**
- Days 1-2: Deploy Authelia + Redis
- Days 3-4: Migrate all services
- Day 5: Decommission TinyAuth

**Option C: Super Conservative**
- Month 1: Authelia deployed, parallel with TinyAuth
- Month 2: Migrate one service, observe for 2 weeks
- Month 3: Continue gradual migration

**Recommendation:** Option A - Balance between progress and safety

---

## Proposed Migration Order

Based on risk tolerance and learning progression:

### Phase 1: Foundation (Week 1)

**Deploy New Services:**
1. **Redis for Authelia** (sessions)
   - Deploy redis container
   - Configure persistence
   - Health checks

2. **Authelia Container**
   - Deploy with basic config
   - Connect to Redis
   - Verify health

3. **Create Test User**
   - Your admin account in Authelia
   - Set up TOTP for testing
   - Verify login flow works

**Success Criteria:**
- Authelia healthy and responding
- Can log in at auth.patriark.org
- TOTP working
- **No production services migrated yet**

---

### Phase 2: First Production Service (Week 2)

**Migrate: Grafana** (First service to prove the pattern)

**Why Grafana first?**
- ✅ Non-critical (downtime acceptable for testing)
- ✅ Admin-only (only you affected if issues)
- ✅ Tests MFA requirement (two_factor policy)
- ✅ Tests SSO (will use for Prometheus next)

**Steps:**
1. Create Authelia access policy for Grafana
2. Update Traefik router (tinyauth → authelia middleware)
3. Test authentication flow
4. Test MFA prompt
5. **Keep for 48 hours, monitor for issues**

**Rollback:** Switch middleware back to tinyauth, restart Grafana

---

### Phase 3: Second Service - Test SSO (Week 2)

**Migrate: Prometheus**

**Why Prometheus second?**
- ✅ Also admin-only
- ✅ **Tests SSO behavior** (already signed into Grafana → should not prompt again)
- ✅ Validates session sharing across services
- ✅ Still low risk

**Steps:**
1. Create Authelia access policy for Prometheus
2. Update Traefik router
3. **Key test:** Access Prometheus while already signed into Grafana
   - Should NOT prompt for credentials again
   - Should NOT prompt for MFA again (same session)
4. This validates SSO is working

---

### Phase 4: User-Facing Service (Week 3)

**Migrate: Jellyfin** (First user-facing service)

**Why Jellyfin?**
- ✅ Tests one-factor policy (no MFA required)
- ✅ User-facing UX matters here
- ✅ Most frequently accessed service (good test case)
- ✅ Immediate SSO benefit (if also using Immich)

**Steps:**
1. Create Authelia policy (one_factor, group:users)
2. Update Traefik router
3. Test user experience
4. **Gather feedback on SSO UX**
5. Monitor for 72 hours

---

### Phase 5: Complete Media Stack (Week 3)

**Migrate: Immich**

**Why Immich?**
- ✅ Tests SSO with Jellyfin (sign in once, access both)
- ✅ Completes Tier 2 migration
- ✅ Same policy as Jellyfin (consistency)

---

### Phase 6: Remaining Services (Week 4)

**Migrate: Traefik Dashboard, Alertmanager**

**Why last?**
- Traefik dashboard less frequently accessed
- Alertmanager admin-only, low risk

---

### Phase 7: Decommission TinyAuth (Week 4+)

**Only after:**
- [ ] All services migrated successfully
- [ ] No auth issues for 7+ days
- [ ] MFA working reliably
- [ ] Session management behaving correctly
- [ ] You're confident in rollback procedures

**Steps:**
1. Stop tinyauth service
2. **Monitor for 48 hours** (any breakage?)
3. Remove tinyauth quadlet
4. Remove tinyauth middleware definition
5. Archive tinyauth data (keep 30 days)
6. Update documentation

---

## Implementation Checklist Template

For each service migration:

```markdown
### Service: _________
**Date:** _________
**Tier:** [ ] 1-Admin [ ] 2-User [ ] 3-Internal
**MFA Required:** [ ] Yes [ ] No

**Pre-Migration:**
- [ ] Authelia policy configured for this service
- [ ] Test user account ready in Authelia
- [ ] Rollback plan documented
- [ ] User notified (if multi-user)

**Migration:**
- [ ] Backup current Traefik router config
- [ ] Update router middleware (tinyauth → authelia)
- [ ] Restart Traefik
- [ ] Test authentication flow
- [ ] Test SSO (if applicable)
- [ ] Test MFA (if required)

**Validation:**
- [ ] Can access service after auth
- [ ] Session persists across browser tabs
- [ ] Session expires correctly (test timeout)
- [ ] No errors in logs
- [ ] Service functional after auth

**Post-Migration:**
- [ ] Monitor for 24-48 hours
- [ ] Gather user feedback
- [ ] Document any issues
- [ ] Mark service as "Authelia-protected" in docs

**Rollback (if needed):**
- [ ] Revert router middleware to tinyauth
- [ ] Restart Traefik
- [ ] Verify service accessible
- [ ] Document failure reason
```

---

## Risk Management

### Critical Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Authelia down = all services locked out** | CRITICAL | Keep TinyAuth running during migration; Health checks + auto-restart; Monitor Authelia health |
| **Redis failure = sessions lost** | HIGH | Redis persistence enabled; Short re-auth is acceptable fallback |
| **Config error locks you out** | HIGH | Test with separate account first; Keep SSH access to fix config; Document rollback steps |
| **MFA device lost** | MEDIUM | Generate recovery codes; Keep backup TOTP seed; Test recovery procedure |
| **Forgot to migrate a service** | LOW | Document all services; Test each one before decommissioning TinyAuth |

### Rollback Strategy

**Per-Service Rollback:**
```yaml
# In router config
# Before: middlewares=crowdsec-bouncer@file,rate-limit@file,authelia@file
# After:  middlewares=crowdsec-bouncer@file,rate-limit@file,tinyauth@file
```
Restart Traefik, service back on TinyAuth immediately.

**Full System Rollback:**
1. Stop Authelia service
2. Revert all router middlewares to tinyauth
3. Restart Traefik
4. System back to original state

**Timeline:** <5 minutes to roll back any service

---

## Resources Required

### Compute Resources

**Redis for Authelia:**
- Memory: ~50MB
- CPU: Negligible
- Disk: ~100MB (with persistence)

**Authelia:**
- Memory: ~512MB (max limit)
- CPU: <5% average
- Disk: ~200MB (config + logs + database)

**Total overhead:** ~600MB memory (vs TinyAuth's ~15MB)
**Acceptable?** Yes, for SSO + MFA benefits

### Time Investment

**Setup Phase:**
- Redis deployment: 30 min
- Authelia deployment: 1-2 hours
- Configuration: 1-2 hours
- Testing: 1 hour
- **Total: 3-5 hours**

**Migration Phase:**
- Per service: 30 min each
- 6 services: ~3 hours total

**Monitoring/Tuning:**
- Week 1-2: Daily checks (10 min/day)
- Week 3-4: Less frequent

**Total time investment:** ~10-15 hours over 4 weeks

---

## Success Criteria

### Must-Have (Before Declaring Success)

- [ ] Authelia healthy and stable >99% uptime
- [ ] SSO working (sign in once, access all services)
- [ ] MFA working for admin services
- [ ] All production services migrated
- [ ] Session management working correctly
- [ ] No user-reported auth issues for 7 days
- [ ] Rollback tested and documented
- [ ] Metrics showing successful auth attempts
- [ ] TinyAuth safely decommissioned

### Nice-to-Have (Post-Migration Improvements)

- [ ] WebAuthn working (YubiKey tested)
- [ ] Grafana dashboard showing auth metrics
- [ ] Alertmanager notifications for auth failures
- [ ] Session analytics (when users sign in, from where)
- [ ] Fine-tuned session timeouts based on usage
- [ ] Documentation for adding new users

---

## Questions for Review

Before we start implementation, please confirm:

### 1. MFA Strategy
**Q:** Should MFA be required only for admin services initially, or all services?
**Recommendation:** Admin-only initially

### 2. Session Duration
**Q:** Are the proposed timeouts acceptable (1h expiration, 15min inactivity, 1M remember-me)?
**Recommendation:** Start with defaults, tune later

### 3. Migration Pace
**Q:** Prefer slow & steady (4 weeks), sprint (1 week), or super conservative (months)?
**Recommendation:** Slow & steady (Week 1-4 plan above)

### 4. First Service
**Q:** Agree with Grafana as first service to migrate?
**Recommendation:** Yes - non-critical, admin-only, tests MFA

### 5. User Base
**Q:** Will this be single-user (just you) or multi-user (family/friends)?
**Recommendation:** Affects policy design and testing scope

### 6. WebAuthn Priority
**Q:** Do you have/want YubiKey or other hardware key immediately, or start with TOTP?
**Recommendation:** Start TOTP, add WebAuthn later

---

## Next Steps

**After you review this plan:**

1. **Discuss and approve** decisions above
2. **Adjust migration pace** if needed
3. **I'll create detailed deployment scripts** for Phase 1
4. **We begin with Redis + Authelia foundation** (no service migration yet)
5. **Extensive testing before any production service touches Authelia**

---

## Related Documents

- **ADR-004:** Full Authelia architecture decision (this is the implementation plan)
- **TinyAuth Guide:** `docs/30-security/guides/tinyauth.md`
- **Middleware Config:** `config/traefik/dynamic/middleware.yml`
- **Security Architecture:** `CLAUDE.md` (middleware ordering)

---

**Status:** Awaiting user approval to proceed
**Created:** 2025-11-10
**Owner:** Claude + User collaboration
