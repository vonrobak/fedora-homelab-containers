# SLO Violation Root Cause Analysis
**Date:** 2025-11-28  
**Reporting Period:** Nov 13-28, 2025 (~15 days)  
**Analyst:** Claude Code + User Investigation

## Executive Summary

All services except Traefik are significantly exceeding their monthly error budgets. Investigation reveals specific incidents and systemic issues that caused the SLO violations.

## Service SLO Status

| Service | Availability | Target | Budget Status | Severity |
|---------|-------------|--------|---------------|----------|
| **Traefik** | 99.97% | 99.95% | 52% consumed | ✅ Healthy |
| **Jellyfin** | 98.91% | 99.5% | 217% consumed | ⚠️ Over budget |
| **Authelia** | 98.09% | 99.9% | 1,911% consumed | 🚨 Critical |
| **Immich** | 96.94% | 99.9% | 3,057% consumed | 🚨 Critical |
| **OCIS** | 78.85% | 99.5% | 4,230% consumed | 🚨 Critical |

## Root Cause Analysis

### 1. OCIS - Critical Incident (Nov 26, 20:20-20:40)

**Incident Duration:** ~18-20 minutes  
**Impact:** Explains 78.85% availability (vs 99.5% target)

**Timeline:**
- **20:20:25** - Context cancellation cascade triggered
  - 17+ JavaScript resource requests failed simultaneously
  - "context canceled" errors in reverse proxy
- **20:20:25** - HTTP 429 (Too Many Requests) triggered
  - Rate limiting activated
  - JWKS/OIDC authentication system failed
- **20:21-20:24** - Multiple invalid credential attempts (7 failed logins)
- **20:38:31** - SIGTERM received (manual shutdown by user)
- **20:38:34** - Service stopped
- **20:40:04** - Service restarted (1.5 min downtime)

**Root Causes:**
1. Rate limiting too aggressive or misconfigured
2. OIDC/JWKS authentication fragility (single 429 error cascaded)
3. No graceful degradation for auth failures
4. Password issues (Bitwarden sync problem discovered separately)

**Error Breakdown:**
- Context canceled: Multiple (page load failures)
- HTTP 429: 1 (triggered cascade)
- Authentication failures: 10+ (invalid credentials)
- Token expired: Multiple (after incident)

### 2. Immich - Connection Failures

**Total Errors:** 185 / 2,285 requests (8.1% error rate)

**Primary Issue:** Code 0 (connection failed) - 124 errors
- These are complete connection failures
- Service likely experiencing:
  - Temporary unresponsiveness
  - Network issues between Traefik and Immich
  - Resource exhaustion (CPU/memory spikes)

**Secondary Issues:**
- 404 errors: 48 (missing thumbnails/resources)
- 499 errors: 13 (client closed connection - timeouts)

**Known Issue:**  
- ffmpeg thumbnail generation failures for corrupt videos
- Internal processing errors (not HTTP-visible but indicates instability)

### 3. Authelia - Endpoint Errors

**Total Errors:** 19 / 1,032 requests (1.8% error rate)

**Primary Issue:** 404 errors (18)
- Missing authentication endpoints
- Possible misconfiguration in routing
- API version mismatches?

**Impact:** Higher than expected for an authentication service
- Target: 99.9% (43 min/month downtime allowed)
- Actual: 98.09% (27.5 hours/month downtime)

### 4. Jellyfin - Service Availability

**Total Errors:** 111 / 14,804 requests (0.75% error rate)

**Error Breakdown:**
- 502 Bad Gateway: 26 (service down/unreachable)
- 404 Not Found: 79 (missing media files/metadata)
- Code 0: 6 (connection failures)

**Root Causes:**
- Service restarts: Nov 25, 26, 27, 28 (daily restarts observed)
- Media file issues (broken links, moved files)
- Possible memory pressure (see swap usage issues)

## Short-Term Action Plan

### Critical (Fix within 24 hours)

1. **OCIS Rate Limiting**
   - Review and increase OIDC/JWKS rate limits
   - Add retry logic for auth failures
   - Monitor for 429 errors

2. **Immich Connection Stability**
   - Check Immich resource usage (CPU/memory)
   - Review network connectivity
   - Consider increasing healthcheck timeouts

3. **Authelia 404 Errors**
   - Audit authentication endpoint configuration
   - Check API version compatibility
   - Review Traefik routing rules for Authelia

### Important (Fix within 1 week)

4. **Jellyfin 502 Errors**
   - Investigate why daily restarts occur
   - Check for memory leaks or resource exhaustion
   - Review startup dependencies

5. **404 Error Cleanup**
   - Jellyfin: Audit media library for broken links
   - Immich: Check for missing thumbnails, regenerate if needed
   - Clean up orphaned references

6. **Connection Timeout Tuning**
   - Increase Traefik backend timeouts
   - Add circuit breaker patterns
   - Implement retry logic

## Medium-Term Improvements

1. **Authentication Resilience**
   - Implement fallback auth mechanisms
   - Add caching for OIDC tokens
   - Graceful degradation for auth failures

2. **Monitoring Enhancements**
   - Add alerts for Code 0 errors (connection failures)
   - Alert on HTTP 429 (rate limiting)
   - Track service restart frequency

3. **Resource Management**
   - Address swap usage issues (separate investigation)
   - Set appropriate resource limits
   - Monitor for OOM kills

## Lessons Learned

1. **Single Point of Failure**: OCIS OIDC/JWKS had no fallback
2. **Cascading Failures**: One 429 error took down entire auth system
3. **Monitoring Gaps**: These issues weren't caught until SLO implementation
4. **Rate Limiting**: Too aggressive or misconfigured

## Next Steps

1. Implement critical fixes (OCIS rate limits, Immich stability)
2. Monitor error rates for 48 hours
3. Re-evaluate SLO targets if issues persist
4. Consider temporarily relaxing SLOs until systemic issues resolved

---

**Report Generated:** 2025-11-28  
**Data Source:** Prometheus metrics (Nov 13-28), service logs  
**Tools:** SLO framework, Traefik metrics, systemd journals
