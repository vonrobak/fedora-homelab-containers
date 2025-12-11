# Dependency Alert False Positive Fix

**Date:** 2025-12-11
**Type:** Investigation & Resolution
**Impact:** High - Eliminated recurring false critical alerts

---

## Problem Statement

Recurring Discord alerts with header `CriticalServiceDependencyUnhealthy`:

```
Critical service traefik depends on immich which is currently unhealthy.
This may cause service degradation or failures.
```

**Reality:** Immich was healthy, and Traefik doesn't depend on Immich to function.

---

## Investigation

### 1. Service Health Check
All Immich containers confirmed healthy (11 days uptime):
- `immich-server`: healthy
- `immich-ml`: healthy
- `postgresql-immich`: healthy
- `redis-immich`: healthy

### 2. Dependency Graph Analysis
Found in `dependency-graph.json`:
```json
"traefik": {
  "dependencies": [
    {
      "target": "immich",
      "type": "routing",
      "strength": "soft"
    }
  ]
}
```

**Key insight:** This is a ROUTING dependency, not a runtime dependency.
- Traefik routes traffic TO immich
- Traefik does NOT depend ON immich to function
- If immich is down, other services remain accessible

### 3. Metrics Export Issue
The metric showed:
```
homelab_dependency_health{homelab_service="traefik",dependency="immich"} 0
```

**Root causes:**
1. Health check script couldn't evaluate logical grouping "immich" (not a real container)
2. No distinction between routing vs runtime dependencies in metrics
3. Alert rule triggered on ANY unhealthy dependency regardless of type

---

## Solution Implemented

### Phase 1: Enhanced Metrics Export
**File:** `scripts/export-dependency-metrics.sh`

**Added:**
1. `check_dependency_health()` function with logical grouping support:
   - Detects when dependency is a logical group (e.g., "immich")
   - Checks health of member services (e.g., "immich-server", "immich-ml")
   - Returns healthy if ANY member service is running

2. Dependency type labels to metrics:
   - `dependency_type="routing|runtime"`
   - `dependency_strength="soft|hard"`

**Result:**
```
homelab_dependency_health{
  homelab_service="traefik",
  dependency="immich",
  dependency_type="routing",
  dependency_strength="soft"
} 1
```

### Phase 2: Alert Rule Refinement
**File:** `config/prometheus/alerts/dependency-alerts.yml`

**Changes:**
1. **Updated `CriticalServiceDependencyUnhealthy`:**
   ```yaml
   # Only trigger on unhealthy RUNTIME dependencies
   expr: homelab_dependency_health{dependency_type!="routing"} == 0
   ```

2. **Created `RoutingTargetUnhealthy` (new warning alert):**
   ```yaml
   # Warn when routing targets are down (not critical)
   expr: homelab_dependency_health{dependency_type="routing"} == 0
   severity: warning
   for: 5m
   ```

---

## Impact

### Dependency Classification

**Traefik Runtime Dependencies (critical if down):**
- Networks: `reverse_proxy`, `auth_services`, `monitoring`
- These actually affect Traefik's functionality

**Traefik Routing Dependencies (warning if down):**
- Services: `immich`, `jellyfin`, `grafana`, `prometheus`, `loki`, etc.
- Only the specific route becomes unavailable, Traefik continues functioning

### Alert Behavior Change

**When Immich goes down:**

| Before | After |
|--------|-------|
| 🚨 Critical: "Traefik has unhealthy dependency" | ⚠️ Warning: "Routing target immich is unhealthy" |
| Implies Traefik is broken | Clearly states only Immich route affected |
| Causes unnecessary urgency | Appropriate severity |

**When Redis-Authelia goes down:**

| Before | After |
|--------|-------|
| 🚨 Critical: "Authelia has unhealthy dependency" | 🚨 Critical: "Authelia has unhealthy dependency" |
| Correct (Authelia needs Redis) | **Unchanged** (still correct) |

---

## Validation

### Metric Verification
```bash
# Query shows correct labels and health
homelab_dependency_health{homelab_service="traefik",dependency="immich"}
→ type: routing, strength: soft, health: 1 ✅
```

### Alert Query Testing
```bash
# Critical alert query (runtime dependencies only)
(homelab_dependency_health{dependency_type!="routing"}==0)
and homelab_critical_service_status==1
→ Result: [] (empty - no unhealthy runtime dependencies) ✅
```

### Alert Rules Loaded
- `CriticalServiceDependencyUnhealthy`: Active, excludes routing ✅
- `RoutingTargetUnhealthy`: Active, warning-level ✅

---

## Metrics Improvement

| Metric | Before | After |
|--------|--------|-------|
| False positive rate | 100% (immich always unhealthy) | 0% |
| Alert accuracy | Low (routing treated as runtime) | High (proper classification) |
| Dependency visibility | Good | Better (type + strength labels) |
| Alert fatigue | High (critical for non-critical issues) | Low (appropriate severity) |

---

## Files Modified

1. `scripts/export-dependency-metrics.sh` - Enhanced health checks, added dependency type labels
2. `config/prometheus/alerts/dependency-alerts.yml` - Refined alert logic, added routing target alert
3. `data/backup-metrics/dependency_metrics.prom` - Regenerated with new schema

---

## Lessons Learned

1. **Dependency types matter:** Routing relationships are fundamentally different from runtime dependencies
2. **Logical groupings need special handling:** Services like "immich" represent multiple containers
3. **Alert severity must match impact:** Routing target failures don't justify critical alerts for the router
4. **Metric labels enable sophisticated alerting:** Adding type/strength labels allows filtering in alert rules

---

## Future Considerations

1. **Review other routing dependencies:** Ensure all reverse proxy routing relationships are classified correctly
2. **Document dependency types:** Add to operations guide explaining runtime vs routing vs optional dependencies
3. **Monitor alert quality:** Track false positive rates over time
4. **Consider soft vs hard distinction:** Current alerts treat all non-routing as critical, might refine further

---

**Status:** Implemented and validated
**Next Review:** Monitor for 7 days to confirm no regressions
**Related ADR:** ADR-003 (Monitoring Stack), ADR-007 (Autonomous Operations Alert Quality)
