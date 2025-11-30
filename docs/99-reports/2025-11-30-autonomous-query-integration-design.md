# Autonomous Operations + Query Integration Design

**Date:** 2025-11-30
**Purpose:** Design document for integrating query-homelab.sh into autonomous-check.sh
**Priority:** 1 (Quick win, immediate value)
**Estimated Effort:** 1-2 hours

---

## Overview

Integrate the natural language query system (Session 5C) into autonomous operations (Session 6) to:
- Reduce OBSERVE phase execution time
- Lower token usage by 90% via query cache
- Simplify code maintenance
- Improve data consistency

---

## Current OBSERVE Phase Analysis

### Functions in autonomous-check.sh

| Function | Current Implementation | Lines | Can Be Enhanced |
|----------|----------------------|-------|-----------------|
| `observe_health()` | Calls homelab-intel.sh | 222-247 | ❌ No (specialized) |
| `observe_predictions()` | Calls predict-resource-exhaustion.sh | 249-271 | ❌ No (specialized) |
| `observe_drift()` | Calls check-drift.sh | 273-299 | ❌ No (specialized) |
| `observe_services()` | **Direct systemctl/podman loops** | 301-339 | ✅ **YES** |
| `observe_disk()` | **Direct df calls** | 341-361 | ✅ **YES** |

### Integration Opportunities

**Priority 1: observe_disk()** ✅ READY NOW
- Current: 2 direct `df` calls (root + BTRFS)
- Enhanced: Single `query-homelab.sh "show me disk usage"` call
- Query pattern: `disk_usage_summary` (already exists)
- Benefit: Cached result, structured JSON

**Priority 2: observe_services()** ⚠️ NEEDS NEW PATTERN
- Current: Loop through 7 services with systemctl + podman healthcheck
- Enhanced: Single query for unhealthy services
- Query pattern: **NEW** - `service_health_check_all`
- Benefit: Single call vs 7-14 individual calls

---

## Available Query Patterns

### Disk Usage (READY)

**Pattern:** `disk_usage_summary`
```bash
$ query-homelab.sh "show me disk usage"
Disk usage:
  /: 75%
  /mnt/btrfs-pool: 77%
```

**JSON Output:**
```json
{
  "filesystems": [
    {"mount": "/", "usage_pct": "75%"},
    {"mount": "/mnt/btrfs-pool", "usage_pct": "77%"}
  ]
}
```

**Perfect fit!** Already returns exactly what observe_disk() needs.

---

### Service Health (NEEDS ENHANCEMENT)

**Current Patterns:**
- `service_status_specific` - Check one service
- `list_services_all` - List all services

**Gap:** No pattern for "unhealthy services only"

**Solution:** Add new query pattern

---

## Implementation Plan

### Phase 1: Disk Usage Integration (30 minutes)

**Task:** Replace observe_disk() with query-homelab.sh

**Current Code (lines 341-361):**
```bash
observe_disk() {
    log DEBUG "Checking disk usage..."

    if $DRY_RUN; then
        echo '{"root_usage_pct": 50, "btrfs_usage_pct": 30}'
        return
    fi

    local root_pct btrfs_pct

    root_pct=$(df / | awk 'NR==2 {gsub(/%/,""); print $5}')

    # Check BTRFS pool if exists
    if [[ -d /mnt/btrfs-pool ]]; then
        btrfs_pct=$(df /mnt/btrfs-pool | awk 'NR==2 {gsub(/%/,""); print $5}' 2>/dev/null || echo 0)
    else
        btrfs_pct=0
    fi

    echo "{\"root_usage_pct\": $root_pct, \"btrfs_usage_pct\": $btrfs_pct}"
}
```

**Enhanced Code:**
```bash
observe_disk() {
    log DEBUG "Checking disk usage..."

    if $DRY_RUN; then
        echo '{"root_usage_pct": 50, "btrfs_usage_pct": 30}'
        return
    fi

    # Use query-homelab.sh for cached disk info
    local QUERY_HOMELAB="$SCRIPT_DIR/query-homelab.sh"

    if [[ -x "$QUERY_HOMELAB" ]]; then
        local disk_result
        disk_result=$("$QUERY_HOMELAB" "show me disk usage" --json 2>/dev/null || echo "")

        if [[ -n "$disk_result" ]]; then
            # Parse query result and convert to expected format
            local root_pct btrfs_pct
            root_pct=$(echo "$disk_result" | jq -r '.filesystems[] | select(.mount == "/") | .usage_pct' | tr -d '%')
            btrfs_pct=$(echo "$disk_result" | jq -r '.filesystems[] | select(.mount == "/mnt/btrfs-pool") | .usage_pct' | tr -d '%' 2>/dev/null || echo 0)

            echo "{\"root_usage_pct\": $root_pct, \"btrfs_usage_pct\": $btrfs_pct, \"cached\": true}"
            return
        fi
    fi

    # Fallback to direct calls if query system unavailable
    log DEBUG "Query system unavailable, using direct disk checks"
    local root_pct btrfs_pct
    root_pct=$(df / | awk 'NR==2 {gsub(/%/,""); print $5}')
    if [[ -d /mnt/btrfs-pool ]]; then
        btrfs_pct=$(df /mnt/btrfs-pool | awk 'NR==2 {gsub(/%/,""); print $5}' 2>/dev/null || echo 0)
    else
        btrfs_pct=0
    fi
    echo "{\"root_usage_pct\": $root_pct, \"btrfs_usage_pct\": $btrfs_pct, \"cached\": false}"
}
```

**Benefits:**
- ✅ Uses query cache when available (instant response)
- ✅ Graceful fallback to direct calls
- ✅ Tracks cache usage via `cached` field
- ✅ Same JSON output structure (backward compatible)

---

### Phase 2: Add Service Health Query Pattern (45 minutes)

**Task:** Create new query pattern for unhealthy services

**New Pattern in query-patterns.json:**
```json
{
  "id": "service_health_all_unhealthy",
  "description": "Find all unhealthy or stopped critical services",
  "match": ["unhealthy", "services"],
  "match_any": ["stopped", "failed", "down", "not running"],
  "intent": "service_health",
  "executor": "get_unhealthy_services",
  "cache_key": "unhealthy_services",
  "cache_ttl": 60,
  "examples": [
    "What services are unhealthy?",
    "Show me stopped services",
    "Which services are down?"
  ]
}
```

**New Executor in query-homelab.sh:**
```bash
# Get unhealthy services
get_unhealthy_services() {
    local critical_services=("traefik" "prometheus" "grafana" "alertmanager" "authelia" "jellyfin" "immich-server")
    local unhealthy=()

    for service in "${critical_services[@]}"; do
        if systemctl --user is-active "$service.service" >/dev/null 2>&1; then
            # Service running, check health if container exists
            if podman container exists "$service" 2>/dev/null; then
                if ! podman healthcheck run "$service" >/dev/null 2>&1; then
                    unhealthy+=("$service")
                fi
            fi
        elif systemctl --user list-unit-files "$service.service" >/dev/null 2>&1; then
            # Service exists but not running
            unhealthy+=("$service")
        fi
    done

    # Output JSON array
    if (( ${#unhealthy[@]} > 0 )); then
        printf '{'
        printf '"unhealthy_services": ['
        local first=true
        for s in "${unhealthy[@]}"; do
            $first || printf ','
            printf '"%s"' "$s"
            first=false
        done
        printf ']}'
    else
        echo '{"unhealthy_services": []}'
    fi
}
```

**Add to Response Formatter:**
```bash
service_health_all_unhealthy)
    if [[ "$(echo "$result" | jq '.unhealthy_services | length')" -gt 0 ]]; then
        echo "Unhealthy services${cache_note}:"
        echo "$result" | jq -r '.unhealthy_services[]' | sed 's/^/  ❌ /'
    else
        echo "All services healthy${cache_note}"
    fi
    ;;
```

---

### Phase 3: Service Health Integration (30 minutes)

**Task:** Replace observe_services() with query-homelab.sh

**Current Code (lines 301-339):**
```bash
observe_services() {
    log DEBUG "Checking service states..."

    if $DRY_RUN; then
        echo '{"unhealthy_services": []}'
        return
    fi

    local unhealthy=()

    # Check critical services
    for service in traefik prometheus grafana alertmanager authelia jellyfin immich-server; do
        if systemctl --user is-active "$service.service" >/dev/null 2>&1; then
            # Service is running, check health if container exists
            if podman container exists "$service" 2>/dev/null; then
                if ! podman healthcheck run "$service" >/dev/null 2>&1; then
                    unhealthy+=("$service")
                fi
            fi
        elif systemctl --user list-unit-files "$service.service" >/dev/null 2>&1; then
            # Service exists but not running
            unhealthy+=("$service")
        fi
    done

    # Output as JSON array
    if (( ${#unhealthy[@]} > 0 )); then
        printf '{"unhealthy_services": ['
        local first=true
        for s in "${unhealthy[@]}"; do
            $first || printf ','
            printf '"%s"' "$s"
            first=false
        done
        printf ']}'
    else
        echo '{"unhealthy_services": []}'
    fi
}
```

**Enhanced Code:**
```bash
observe_services() {
    log DEBUG "Checking service states..."

    if $DRY_RUN; then
        echo '{"unhealthy_services": []}'
        return
    fi

    # Use query-homelab.sh for cached service health
    local QUERY_HOMELAB="$SCRIPT_DIR/query-homelab.sh"

    if [[ -x "$QUERY_HOMELAB" ]]; then
        local service_result
        service_result=$("$QUERY_HOMELAB" "what services are unhealthy" --json 2>/dev/null || echo "")

        if [[ -n "$service_result" ]]; then
            log DEBUG "Using cached service health data"
            echo "$service_result"
            return
        fi
    fi

    # Fallback to direct checks
    log DEBUG "Query system unavailable, using direct service checks"
    local unhealthy=()

    for service in traefik prometheus grafana alertmanager authelia jellyfin immich-server; do
        if systemctl --user is-active "$service.service" >/dev/null 2>&1; then
            if podman container exists "$service" 2>/dev/null; then
                if ! podman healthcheck run "$service" >/dev/null 2>&1; then
                    unhealthy+=("$service")
                fi
            fi
        elif systemctl --user list-unit-files "$service.service" >/dev/null 2>&1; then
            unhealthy+=("$service")
        fi
    done

    if (( ${#unhealthy[@]} > 0 )); then
        printf '{"unhealthy_services": ['
        local first=true
        for s in "${unhealthy[@]}"; do
            $first || printf ','
            printf '"%s"' "$s"
            first=false
        done
        printf ']}'
    else
        echo '{"unhealthy_services": []}'
    fi
}
```

**Benefits:**
- ✅ Single query vs 7-14 individual system calls
- ✅ Cache TTL of 60s (fresh enough for autonomous operations)
- ✅ Graceful fallback maintains reliability
- ✅ Identical output format (backward compatible)

---

## Performance Impact Analysis

### Current OBSERVE Phase

```
observe_health()       → 1 call (homelab-intel.sh)
observe_predictions()  → 1 call (predict-resource-exhaustion.sh)
observe_drift()        → 1 call (check-drift.sh)
observe_services()     → 7-14 calls (systemctl + podman healthcheck)
observe_disk()         → 2 calls (df / + df /mnt/btrfs-pool)

Total: ~12-21 system calls per OBSERVE cycle
```

### Enhanced OBSERVE Phase

```
observe_health()       → 1 call (homelab-intel.sh)
observe_predictions()  → 1 call (predict-resource-exhaustion.sh)
observe_drift()        → 1 call (check-drift.sh)
observe_services()     → 1 call (query-homelab.sh) OR fallback to 7-14
observe_disk()         → 1 call (query-homelab.sh) OR fallback to 2

Total: 5 calls (if cached) vs 12-21 calls (current)
Improvement: 58-76% reduction in system calls
```

### Cache Hit Scenarios

**Scenario 1: Daily 06:30 run (cache cold)**
- First run: Executes queries, populates cache
- Execution time: Similar to current (no benefit yet)

**Scenario 2: Subsequent runs within cache TTL**
- Cache hit: Instant results from query-cache.json
- Execution time: ~90% faster
- Token usage: ~90% lower (no command execution overhead)

**Scenario 3: Manual runs for debugging**
- User runs autonomous-check.sh multiple times
- Cache provides instant results
- Debugging experience dramatically improved

---

## Implementation Checklist

### Phase 1: Disk Usage (30 min)

- [ ] Add QUERY_HOMELAB variable definition
- [ ] Enhance observe_disk() function
- [ ] Test with cache hit
- [ ] Test with cache miss (fallback)
- [ ] Test dry-run mode
- [ ] Verify JSON output structure unchanged

### Phase 2: Service Health Pattern (45 min)

- [ ] Add service_health_all_unhealthy pattern to query-patterns.json
- [ ] Implement get_unhealthy_services() executor in query-homelab.sh
- [ ] Add response formatter
- [ ] Test query: "what services are unhealthy"
- [ ] Verify JSON output matches observe_services() format
- [ ] Add to precompute-queries.sh for cache warming

### Phase 3: Service Health Integration (30 min)

- [ ] Enhance observe_services() function
- [ ] Test with cache hit
- [ ] Test with cache miss (fallback)
- [ ] Test dry-run mode
- [ ] Verify backward compatibility

### Phase 4: Testing & Validation (15 min)

- [ ] Run full autonomous-check.sh with enhancements
- [ ] Compare output structure (should be identical)
- [ ] Measure execution time improvement
- [ ] Verify cache field appears in output
- [ ] Test circuit breaker/pause states still work

### Phase 5: Documentation (15 min)

- [ ] Update autonomous-operations.md with query integration
- [ ] Document cache warming in precompute-queries.sh
- [ ] Add troubleshooting note for query system unavailable

---

## Testing Strategy

### Test 1: Baseline Performance

```bash
# Before changes
time ~/containers/scripts/autonomous-check.sh --verbose

# Record:
# - Execution time
# - Number of system calls (strace)
# - Output structure
```

### Test 2: Enhanced Performance (Cache Cold)

```bash
# Clear cache
rm ~/.claude/context/query-cache.json

# Run enhanced version
time ~/containers/scripts/autonomous-check.sh --verbose

# Should be similar to baseline (populating cache)
```

### Test 3: Enhanced Performance (Cache Warm)

```bash
# Warm cache
~/containers/scripts/precompute-queries.sh

# Run enhanced version
time ~/containers/scripts/autonomous-check.sh --verbose

# Should be significantly faster
```

### Test 4: Fallback Behavior

```bash
# Temporarily rename query-homelab.sh
mv ~/containers/scripts/query-homelab.sh ~/containers/scripts/query-homelab.sh.bak

# Run enhanced version
~/containers/scripts/autonomous-check.sh --verbose

# Should fall back gracefully, same output

# Restore
mv ~/containers/scripts/query-homelab.sh.bak ~/containers/scripts/query-homelab.sh
```

### Test 5: Backward Compatibility

```bash
# Run enhanced autonomous-check.sh
output=$(~/containers/scripts/autonomous-check.sh --json)

# Verify structure matches expectations
echo "$output" | jq '.observations.disk.root_usage_pct' >/dev/null || echo "FAIL: disk structure changed"
echo "$output" | jq '.observations.services.unhealthy_services' >/dev/null || echo "FAIL: services structure changed"
```

---

## Rollback Plan

If issues arise:

1. **Revert observe_disk() and observe_services()** to original implementations
2. **Keep query patterns** (no harm in having them)
3. **Document reason** for rollback in decision log
4. **Investigate root cause** before re-attempting

---

## Expected Benefits

### Immediate (Phase 1+3 Complete)

- ✅ 58-76% reduction in system calls
- ✅ ~90% faster OBSERVE phase on cache hits
- ✅ Lower CPU/IO load during autonomous checks
- ✅ Consistent data format via query system

### Long-term

- ✅ Easier to add new OBSERVE data sources (just add query patterns)
- ✅ Better debuggability (query cache visible/inspectable)
- ✅ Foundation for query-based ORIENT phase enhancements
- ✅ Token usage reduction in Claude interactions

---

## Next Steps After Integration

Once this integration is complete:

1. **Add more query patterns** for predictions data (move predictions to query cache)
2. **Enhance ORIENT phase** with historical queries
3. **Create query-based health scoring** (replace parts of homelab-intel.sh)
4. **Implement intelligent cache warming** based on autonomous schedule

---

**Status:** Design complete, ready for implementation
**Estimated Total Effort:** 2 hours (1.75h coding + 0.25h testing)
**Risk Level:** Low (graceful fallbacks, backward compatible)
**ROI:** High (immediate performance gain, foundation for more improvements)
