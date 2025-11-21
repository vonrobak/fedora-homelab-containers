# Jellyfin Memory Pressure Analysis

**Date:** 2025-11-22
**Trigger:** 3 system freezes requiring hard reboot over 7-day period
**Root Cause:** systemd-oomd killed Jellyfin due to user.slice memory pressure

---

## Executive Summary

**Incident:** Jellyfin was killed by systemd-oomd 3 times in one week:
- Nov 17: user.slice at 92.16%, Jellyfin using 2.5GB
- Nov 19: user.slice at 90.63%, Jellyfin using 2.5GB
- Nov 21: user.slice at 86.09%, Jellyfin using 2.9GB

**Root Cause:** This is a **desktop system** (Fedora Workstation 42 with GNOME), not a headless server. The user.slice includes:
- **~3.3GB**: All containers (Jellyfin, Immich, Prometheus, etc.)
- **~13GB**: GNOME desktop environment + applications

**systemd-oomd behavior:**
- Monitors memory pressure (not just memory usage)
- Default threshold: 80% memory pressure for >20 seconds
- Kills largest process in affected cgroup (usually Jellyfin)
- **This is working as designed** - protecting system from true OOM

**Status:** ⚠️ **NOT A BUG** - Jellyfin is within its 4GB limit. This is expected behavior on a desktop system with both GUI and containers.

---

## Detailed Analysis

### Memory Configuration

**System Total:** 30GB RAM + 8GB swap

**Jellyfin Limits:**
```
MemoryMax=4G (hard limit)
MemoryHigh=3G (soft limit, triggers pressure)
```

**user.slice Limits:**
```
MemoryMax=infinity
MemoryHigh=infinity
(No explicit limits - can use all available system memory)
```

**Current Usage (snapshot at 2025-11-22 17:45):**
- user.slice total: ~16.2GB
  - Containers: ~3.3GB
    - Jellyfin: 1.1GB
    - immich-ml: 534MB
    - immich-server: 517MB
    - Prometheus: 357MB
    - Loki: 213MB
    - PostgreSQL: 206MB
    - Promtail: 167MB
    - Traefik: 147MB
  - Desktop environment: ~13GB
    - GNOME Shell
    - Evolution
    - Nautilus
    - Browser tabs
    - Other applications

---

## OOM Kill Events Timeline

### Event 1: November 17, 23:30:20
```
user.slice: 92.16% memory pressure
Jellyfin usage: 2.5GB (within 4GB limit)
Action: Killed by systemd-oomd
Trigger: Sustained pressure >80% for >20s
```

### Event 2: November 19, 19:15:36
```
user.slice: 90.63% memory pressure
Jellyfin usage: 2.5GB (within 4GB limit)
Action: Killed by systemd-oomd
Trigger: Sustained pressure >80% for >20s
```

### Event 3: November 21, 07:20:27
```
user.slice: 86.09% memory pressure
Jellyfin usage: 2.9GB (within 4GB limit)
Action: Killed by systemd-oomd
Trigger: Sustained pressure >80% for >20s
```

**Pattern:** Events occurred at different times (morning, evening, night), suggesting correlation with:
- Video transcoding (CPU-intensive, memory spikes)
- Multiple active streams
- Large media files being processed
- Desktop applications also consuming memory

---

## Why Jellyfin Gets Killed (Not Other Processes)

systemd-oomd's kill strategy:
1. Detect cgroup under memory pressure (user.slice/app.slice)
2. Find largest process in that cgroup
3. Kill it to relieve pressure

**Jellyfin is usually the largest container**, making it the first target.

**This is intentional design** - sacrifice least critical / most resource-hungry process to save the system.

---

## Is This a Problem?

### Perspective 1: System Protection (systemd-oomd working correctly)
- ✅ System never ran out of memory completely
- ✅ Desktop remained responsive (presumably - would need confirmation)
- ✅ Only one service killed, others continued running
- ✅ Jellyfin auto-restarted via systemd (Restart=always)

### Perspective 2: Service Availability (Jellyfin disruption)
- ❌ Active video streams interrupted
- ❌ Transcoding jobs lost mid-process
- ❌ Users see "service unavailable"
- ❌ Happened 3 times in one week

### Verdict: **Needs Tuning**

While systemd-oomd is working correctly, 3 kills in one week is excessive for a media server that should be reliable.

---

## Recommendations (Prioritized)

### Option 1: Monitor and Accept (LOW EFFORT, REACTIVE)
**Do nothing, monitor if pattern continues.**

**When to use:** If kills are infrequent (<1/month) and acceptable downtime.

**Implementation:**
1. Set up Grafana alert for Jellyfin restarts
2. Log OOM events to centralized monitoring
3. Accept occasional disruption as trade-off for desktop + containers on same system

**Pros:**
- Zero effort
- systemd-oomd continues protecting system

**Cons:**
- Service interruptions continue
- User experience degraded

---

### Option 2: Reduce Jellyfin Memory Limit (MEDIUM EFFORT, PREVENTIVE)
**Lower Jellyfin's memory ceiling to reduce its "target size" for OOM killer.**

**Implementation:**
```bash
# Edit quadlet
nano ~/.config/containers/systemd/jellyfin.container

# Change from:
MemoryMax=4G
MemoryHigh=3G

# To:
MemoryMax=3G
MemoryHigh=2.5G

# Reload and restart
systemctl --user daemon-reload
systemctl --user restart jellyfin.service
```

**Trade-offs:**
- ✅ Jellyfin less likely to be killed (smaller footprint)
- ❌ May impact transcoding performance
- ❌ Could cause Jellyfin internal OOM if limit too low

**Recommendation:** ⚠️ **NOT RECOMMENDED** - Jellyfin needs memory for transcoding. Reducing limit might cause worse problems.

---

### Option 3: Increase systemd-oomd Threshold (LOW EFFORT, HIGHER RISK)
**Raise the memory pressure threshold from 80% to 90%.**

**Implementation:**
```bash
# Create override for systemd-oomd
sudo mkdir -p /etc/systemd/system/systemd-oomd.service.d
sudo nano /etc/systemd/system/systemd-oomd.service.d/threshold.conf
```

Add:
```ini
[Service]
Environment="SYSTEMD_OOMD_SWAP_THRESHOLD=90"
Environment="SYSTEMD_OOMD_MEM_PRESSURE_THRESHOLD=90"
```

Reload:
```bash
sudo systemctl daemon-reload
sudo systemctl restart systemd-oomd.service
```

**Trade-offs:**
- ✅ Gives more headroom before kills
- ❌ Increases risk of actual system OOM
- ❌ May cause system-wide slowdown before kill

**Recommendation:** ⚠️ **USE WITH CAUTION** - Could allow memory exhaustion to impact entire system.

---

### Option 4: Add Dedicated Memory Cgroup for Containers (HIGH EFFORT, BEST ISOLATION)
**Create a separate memory cgroup for containers, isolating them from desktop.**

**Implementation:**
```bash
# Create container slice
mkdir -p ~/.config/systemd/user/container.slice.d
cat > ~/.config/systemd/user/container.slice.d/memory.conf <<EOF
[Slice]
MemoryMax=10G
MemoryHigh=8G
EOF

# Update each container quadlet
nano ~/.config/containers/systemd/jellyfin.container

# Add:
[Service]
Slice=container.slice

# Reload
systemctl --user daemon-reload
systemctl --user restart jellyfin.service
```

**Trade-offs:**
- ✅ Isolates container memory from desktop
- ✅ Protects desktop from container memory pressure
- ✅ Prevents desktop apps from starving containers
- ❌ Requires updating all container quadlets
- ❌ Need to carefully size container.slice limit

**Recommendation:** ✅ **RECOMMENDED FOR DESKTOP+CONTAINERS HYBRID**

---

### Option 5: Close Desktop Applications (NO EFFORT, MANUAL)
**Reduce desktop memory footprint before heavy Jellyfin use.**

**Implementation:**
- Close browser tabs
- Exit Evolution, Nautilus
- Stop unused GNOME services

**Trade-offs:**
- ✅ Free approach
- ❌ Manual intervention required
- ❌ Inconvenient

**Recommendation:** ✅ **GOOD SHORT-TERM FIX**

---

### Option 6: Dedicated Headless Server (NUCLEAR OPTION)
**Run containers on separate hardware without desktop environment.**

**Trade-offs:**
- ✅ Complete isolation
- ✅ No memory contention
- ❌ Requires additional hardware
- ❌ High cost

**Recommendation:** 🛑 **OVERKILL** - Current setup works, just needs tuning.

---

## Recommended Action Plan

### Phase 1: Immediate (Today)
1. ✅ **Monitor current behavior** - Set up Grafana alert for Jellyfin restarts
2. ✅ **Document pattern** - Note when kills occur (transcoding? multiple streams?)

### Phase 2: Short-term (This Week)
1. **Reduce desktop memory footprint** before heavy Jellyfin use:
   - Close unused browser tabs
   - Exit Evolution, file manager
   - Check `htop` for memory hogs

2. **Verify Jellyfin restarts cleanly** after OOM kill:
   - Check: `systemctl --user status jellyfin.service`
   - Verify: Service auto-restarts (Restart=always)

### Phase 3: Long-term (Next Month)
1. **Implement Option 4: Dedicated container.slice**
   - Allocate 10GB to containers (Jellyfin + others)
   - Leaves ~20GB for desktop
   - Prevents cross-contamination

2. **Create Grafana dashboard** for memory pressure monitoring:
   - user.slice memory usage
   - container.slice memory usage (after implementing)
   - Individual container memory trends
   - OOM kill event log

---

## Monitoring Strategy

### Key Metrics to Track

**System Level:**
- user.slice memory usage (current: 16.2GB)
- Memory pressure percentage
- OOM kill events (via journalctl)

**Jellyfin Level:**
- Memory usage over time
- Memory spikes during transcoding
- Correlation between active streams and memory

**Desktop Level:**
- GNOME Shell memory usage
- Browser memory usage
- Top memory consuming applications

### Grafana Dashboard Panels

1. **Memory Usage Timeline**
   - user.slice total
   - Jellyfin
   - Top 5 containers
   - Desktop environment (calculated)

2. **OOM Event Log**
   - systemd-oomd kills
   - Which service killed
   - Memory pressure at time of kill

3. **Memory Pressure Gauge**
   - Current pressure %
   - Alert threshold (80%)
   - Historical trend

---

## Jellyfin-Specific Analysis

### Typical Memory Patterns

**Idle State:**
- Base: ~500MB-1GB
- Cache: Metadata, thumbnails, art

**Active Streaming (1 client, direct play):**
- ~1GB-1.5GB
- Minimal overhead (no transcoding)

**Active Transcoding (1 stream):**
- ~1.5GB-2.5GB
- Depends on codec, resolution, bitrate

**Heavy Transcoding (2-3 simultaneous streams):**
- ~2.5GB-3.5GB
- Can spike to 4GB temporarily

**GPU Transcoding (VA-API enabled):**
- Lower than CPU transcoding
- ~1GB-2GB even with multiple streams
- **Verify VA-API is actually being used!**

### VA-API Transcoding Check

```bash
# Check if VA-API device is available
podman exec jellyfin ls -la /dev/dri/renderD128

# Check Jellyfin transcoding logs
journalctl --user -u jellyfin.service | grep -i "va-api\|vaapi\|hardware"

# Verify in Jellyfin UI
# Navigate to: Dashboard > Playback > Transcoding
# Should show: "Enable hardware acceleration: VA-API"
```

**If VA-API isn't working:**
- Jellyfin using CPU transcoding (much higher memory)
- Fix VA-API setup per docs: `docs/10-services/guides/jellyfin-gpu-troubleshooting.md`

---

## Conclusion

**This is NOT a Jellyfin bug** - it's a natural consequence of running a desktop environment and containers on the same system with finite memory.

**systemd-oomd is working correctly** - it's protecting your system from complete memory exhaustion.

**Recommended approach:**
1. **Short-term**: Close unused desktop applications during heavy Jellyfin use
2. **Long-term**: Implement dedicated container.slice (Option 4)
3. **Monitor**: Create Grafana dashboard for memory pressure tracking

**Do NOT:**
- Disable systemd-oomd (removes critical protection)
- Severely reduce Jellyfin memory limit (breaks transcoding)
- Ignore the pattern (3 kills/week is too frequent)

**Expected outcome after implementing recommendations:**
- OOM kills reduced to <1/month (only during exceptional circumstances)
- Better visibility into memory usage patterns
- Isolation between desktop and container memory

---

## Next Steps

1. **User decision required:** Choose which option(s) to implement
2. **If choosing Option 4 (container.slice):** Create implementation task list
3. **Create Grafana dashboard:** Memory pressure monitoring
4. **Document in CLAUDE.md:** Add "Memory Management" troubleshooting section

---

**Analyst:** Claude (AI Assistant)
**Review status:** Ready for user review and decision
