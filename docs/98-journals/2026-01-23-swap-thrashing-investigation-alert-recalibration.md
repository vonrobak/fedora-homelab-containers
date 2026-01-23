# Swap Thrashing Investigation & Alert Recalibration

**Date:** 2026-01-23
**Type:** Investigation + Bug Fix
**Status:** ✅ ALERT FIXED | ⚠️ ROOT CAUSE UNCLEAR

## Problem Summary

Daily SwapThrashing alerts firing since at least 2026-01-17, despite system showing:
- 32GB RAM with only 39% usage (12GB used, 18GB available)
- Swappiness=10 (should avoid swapping)
- Configured container memory limits
- No performance degradation observed

Paradox: Plenty of free RAM but persistent swap activity above alert threshold (300 pages/sec).

## Investigation Findings

### Finding 1: Vivaldi Virtual Memory Anomaly

**Observation:**
```
Physical RAM:     32GB (30.9GB available to OS)
RAM usage:        39.4% (12GB used, 18GB available)
Memory overcommit: +0.8GB (system committed 32.2GB)

Vivaldi VSZ:      14.13 TB across 25 processes
Jellyfin VSZ:     275 GB
Claude VSZ:       75 GB
```

**User behavior:** 1-2 browser tabs, 4 extensions (well-maintained, highly rated)

**Skepticism required:** The 14TB number is **extremely abnormal** for 1-2 tabs. Typical Chromium behavior:
- 10 tabs: 50-200GB VSZ
- 50 tabs: 300-600GB VSZ
- **This case: 1-2 tabs = 14TB VSZ** ← Measurement error? Bug? Needs validation.

**Hypothesis:** Vivaldi's VSZ caused memory overcommit → kernel page table overhead → swap pressure despite "free" RAM.

**Test:** Closed Vivaldi at 14:02. Result: 1h40m with zero new alerts.

**Impact:**
- Memory overcommit resolved immediately (+0.8GB → -9.4GB)
- Page table overhead reduced (120MB → 93MB)
- No new alerts fired

### Finding 2: Alert Miscalibration for Zram

**System uses zram (compressed in-memory swap), not disk swap.**

```
Baseline swap activity: 230 pages/sec (normal)
Old alert threshold:    300 pages/sec (designed for disk)
Observed activity:      500-700 pages/sec spikes (no system impact)

System behavior during "thrashing":
- Load: 0.08 per CPU (idle)
- CPU wait: 0% (no I/O blocking)
- Memory available: 64.8%
- System responsiveness: Normal
```

**Root cause:** Alert threshold designed for disk swap I/O (expensive, blocks CPU). Zram swap is CPU-bound compression - much higher rates are normal and non-harmful.

**Evidence:** System lifetime average swap rate = 231 pages/sec (chronically near threshold).

## Solution Implemented

**File:** `config/prometheus/alerts/infrastructure-warnings.yml` (lines 137-182)

**Changes:**
```yaml
Old: rate(node_vmstat_pswpin[5m]) > 300
New: rate(node_vmstat_pswpin[5m]) > 1000 (fire) / > 600 (resolve)

Added conditions:
- High load: >0.7 per CPU, OR
- Low memory: <15% available

Added hysteresis to prevent flapping
```

**Rationale:**
- Threshold increased to account for normal zram baseline
- Requires actual system impact (load OR memory pressure) to fire
- Follows existing alert pattern (HighSystemLoad hysteresis)

**Validation:**
```
Current system state:
- Swap: 744 pages/sec
- Load: 0.08 per CPU
- RAM: 64.8% available

Old alert: Would fire (false positive)
New alert: Silent (correct)
```

## Open Questions & Further Investigation

### 1. Vivaldi 14TB VSZ Anomaly

**The 14TB measurement seems implausible for 1-2 tabs.** Possible explanations:
- Measurement error (ps VSZ reporting bug?)
- Flatpak isolation issue (sandboxing artifact?)
- Site isolation bug (iframes spawning excessive renderers?)
- Extension bug (one of 4 extensions leaking processes?)
- Profile corruption (3.2GB profile for 2 tabs is large)

**Recommended validation when restarting Vivaldi:**
```bash
# Monitor process count in real-time
watch -n 2 'ps aux | grep vivaldi | wc -l'

# Check memory maps detail
cat /proc/$(pgrep vivaldi | head -1)/maps | wc -l

# Test with fresh profile
flatpak run --command=vivaldi com.vivaldi.Vivaldi --user-data-dir=/tmp/test

# Compare VSZ calculation methods
ps aux | grep vivaldi  # VSZ column
pmap $(pgrep vivaldi | head -1) | tail -1  # total mapping
```

**If 14TB is real:** This represents a serious Vivaldi/Flatpak bug warranting upstream report.
**If 14TB is measurement error:** Need to identify actual root cause of swap pressure.

### 2. Why Did Closing Vivaldi Stop Alerts?

Two possibilities:
1. **Vivaldi was the cause** - VSZ overhead triggered kernel pressure (hypothesis)
2. **Correlation not causation** - Timing coincidence, or simply reducing active processes lowered baseline swap activity below new threshold

**Test:** Restart Vivaldi with monitoring. If alerts return immediately, confirms causal relationship.

### 3. Was Alert Miscalibration the Primary Issue?

**Conservative interpretation:** The old 300 pages/sec threshold may have been appropriate for detecting *abnormal* zram activity. The fact that baseline is 230 pages/sec suggests the system is chronically swap-reliant.

**Alternative hypothesis:** Both issues were real:
- Vivaldi caused temporary spikes >300 (acute problem)
- System baseline 230 pages/sec indicates architectural issue (chronic problem)

Closing Vivaldi may have addressed acute spikes while missing chronic swap dependency.

## Lessons Learned

1. **Alert thresholds must match storage technology** - Disk vs zram swap have different performance characteristics
2. **High virtual memory ≠ high physical memory** - But extreme VSZ (14TB) can still cause kernel pressure
3. **Multi-condition alerts reduce false positives** - Swap rate alone insufficient, need system impact confirmation
4. **Skepticism required for extreme measurements** - 14TB VSZ warrants validation before drawing conclusions

## Action Items

- [x] Fix SwapThrashing alert threshold and add impact conditions
- [ ] Monitor Vivaldi behavior on next startup (process count, VSZ, extensions)
- [ ] Validate 14TB VSZ measurement with alternative tools
- [ ] Consider if 230 pages/sec baseline indicates need for architectural changes
- [ ] Document zram vs disk swap differences in memory-management.md

## References

- Alert rule: `config/prometheus/alerts/infrastructure-warnings.yml:137-182`
- Investigation started: 2026-01-23 13:43
- Vivaldi closed: 2026-01-23 14:02
- Alert fix deployed: 2026-01-23 14:41
- Last alert before fix: 2026-01-17 (at least, possibly earlier)
