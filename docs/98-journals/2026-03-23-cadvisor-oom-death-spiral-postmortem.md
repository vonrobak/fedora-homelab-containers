# cAdvisor OOM Death Spiral — Post-Mortem

**Date:** 2026-03-23
**Incident:** Recurring cAdvisor unresponsiveness causing hourly Discord alert spam
**Severity:** Medium (monitoring degraded, alert noise — no data loss or service impact)
**Resolution:** Tuned cAdvisor resource parameters and raised memory limit
**Recurrence:** At least 2 cycles observed (service restarted 2026-03-22, failed again within ~10h)

---

## Executive Summary

cAdvisor was entering a death spiral every ~10 hours: memory exhaustion → swap thrashing → healthcheck zombie accumulation → Prometheus scrape failure → HostDown alert → Discord notification every 65 minutes. Restarting the service only reset the clock. Root cause was default cAdvisor settings being too aggressive for a 30-container homelab, combined with a memory limit (256M) that couldn't contain the resulting workload.

**Outcome:** Tuned housekeeping interval, stats retention, and disabled expensive unused metrics. Raised memory limit from 256M to 512M. Service now runs at ~40M with 420M headroom.

---

## Timeline

| Time (CET) | Event |
|------------|-------|
| 2026-03-22 21:32 | cAdvisor restarted (consumed 13h19m CPU, 240M peak, 403M swap peak) |
| 2026-03-23 ~06:00 | Memory limit hit again (~10h after restart) |
| 2026-03-23 08:15 | HostDown alert starts firing (cAdvisor `up == 0` for >5m) |
| 2026-03-23 09:26 | First Discord notification (alert delayed by group_wait + evaluation) |
| 2026-03-23 09:26–16:56 | Discord notification every ~65 minutes (7 notifications total) |
| 2026-03-23 17:20 | Investigation + fix applied |
| 2026-03-23 17:24 | cAdvisor healthy, Prometheus scraping, alert resolving |

---

## Root Cause Analysis

### The Death Spiral (5 stages)

```
Stage 1: Memory Growth
  cAdvisor defaults: 1s housekeeping, 2m stats retention, all metrics enabled
  → Monitoring 30+ containers + ALL system cgroups = unbounded memory growth

Stage 2: Memory Exhaustion
  Hit MemoryHigh (230M) → kernel throttles allocations
  Hit MemoryMax (256M) → pushed to swap (grew to 1.1G)

Stage 3: Zombie Accumulation
  Healthcheck wget processes spawn every 30s
  cAdvisor too slow to respond (thrashing swap) → wget hangs
  PID 1 too busy to reap child processes → 668 zombie wget processes

Stage 4: Service Unresponsive
  cAdvisor at 59% CPU (all swap I/O), 0B memory available
  /healthz endpoint times out → Podman marks container unhealthy
  Prometheus /metrics scrape fails → up{job="cadvisor"} == 0

Stage 5: Alert Storm
  HostDown alert fires after 5m (infrastructure-critical.yml)
  Routes to discord-critical receiver (repeat_interval: 1h)
  → Discord notification every ~65 minutes until resolved
```

### Why restart didn't fix it

The 256M memory limit was fundamentally insufficient for cAdvisor's default configuration monitoring 30+ containers. Every restart just reset the ~10 hour countdown to the next OOM event.

### Contributing factors

1. **Default housekeeping interval (1s)** — polls every container's cgroup stats once per second. With 30+ containers and hundreds of cgroup entries, this generates enormous memory churn.
2. **Default storage duration (2m)** — keeps 2 minutes of stats samples in memory per container.
3. **All metrics enabled** — `percpu` alone creates 12 metric series per container (one per CPU core). `perf_event`, `hugetlb`, `referenced_memory`, etc. add overhead with zero value for homelab monitoring.
4. **Full cgroup hierarchy monitoring** — cAdvisor with `--privileged --cgroupns=host` sees every cgroup on the system, not just containers. Note: `--docker_only` was attempted but doesn't work with rootless Podman (can't correlate container IDs with storage layers).

---

## Fix Applied

Three changes to `quadlets/cadvisor.container`:

### 1. Reduced monitoring frequency and retention

```ini
Exec=-logtostderr -housekeeping_interval=10s -storage_duration=1m0s \
  -disable_metrics=percpu,perf_event,hugetlb,referenced_memory,resctrl,advtcp,udp,sched,process,tcp
```

| Parameter | Before (default) | After | Rationale |
|-----------|-------------------|-------|-----------|
| `housekeeping_interval` | 1s | 10s | Homelab doesn't need per-second container stats |
| `storage_duration` | 2m | 1m | Halves in-memory sample retention |
| `disable_metrics` | none | 10 types | Drops expensive metrics with zero homelab value |

### 2. Raised memory limit to match actual workload

```ini
MemoryMax=512M   # was 256M
MemoryHigh=460M  # was 230M
```

### Verification

| Metric | Before fix | After fix |
|--------|-----------|-----------|
| Memory used | 234M + 1.1G swap | 40M |
| Memory available | 0B | 420M |
| Zombie processes | 668 | 0 |
| Healthcheck | timeout | ok |
| Prometheus `up` | 0 | 1 |
| Metrics exposed | — | 15,048 lines (244 container_memory entries) |

---

## What Went Wrong With Previous Restart

The 2026-03-22 restart was a symptom-level fix. It didn't investigate *why* cAdvisor was consuming 240M + 403M swap. The "consumed 13h19m CPU time" line in the stop log was a signal that should have prompted investigation — a metrics exporter should not be consuming 13 hours of CPU time in a day.

---

## Lessons Learned

### 1. Memory limits without understanding workload are time bombs
The 256M limit was set during initial deployment when there were fewer containers. As the homelab grew to 30 containers, the limit was never revisited. Memory limits should be set based on observed steady-state usage with headroom, not arbitrary round numbers.

### 2. cAdvisor defaults are tuned for production Kubernetes, not homelabs
Default 1s housekeeping is appropriate for auto-scaling decisions in production. For a homelab where Prometheus scrapes every 15-30s, a 10s housekeeping interval loses nothing.

### 3. Healthcheck zombies are a symptom amplifier
When a process is under memory pressure, healthchecks that spawn subprocesses (wget) create a positive feedback loop: each zombie adds memory pressure, which slows response to future healthchecks, which creates more zombies. Consider healthcheck mechanisms that don't spawn child processes for memory-constrained services.

### 4. `--docker_only` doesn't work with rootless Podman
cAdvisor's Podman factory registered successfully with `-podman=unix:///var/run/docker.sock`, but `--docker_only` mode failed to discover any containers — "unable to determine rw layer id" for every container. The systemd factory (cgroup-based discovery) is the only working path for rootless Podman.

---

## Monitoring Gap Identified

There is no alert for **container memory approaching its limit**. The existing `ContainerMemoryPressure` alert (if it exists) didn't fire, and `HostDown` only fires after the service is already dead. Consider adding:

```yaml
- alert: ContainerMemoryNearLimit
  expr: container_memory_usage_bytes / container_spec_memory_limit_bytes > 0.85
  for: 10m
  labels:
    severity: warning
```

This would catch the problem hours before the death spiral begins.
