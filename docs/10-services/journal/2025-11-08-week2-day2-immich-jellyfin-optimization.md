# Week 2 Day 2: Immich Deployment & Jellyfin Optimization

**Date:** 2025-11-08
**Focus:** Deploy Immich photo management, optimize Jellyfin for GPU acceleration, eliminate swap usage
**Status:** ✅ Complete - All services operational with remote access

---

## Mission Objectives

1. ✅ Deploy Immich Server and Machine Learning containers
2. ✅ Configure Traefik routing for Immich with proper static asset handling
3. ✅ Import existing photo library (9000+ photos) via External Library
4. ✅ Investigate and fix swap usage crisis (92.5% swap with 14GB free RAM)
5. ✅ Optimize Jellyfin with GPU acceleration and memory limits
6. ✅ Migrate to file-based Traefik routing architecture
7. ✅ Enable remote access with per-service authentication

---

## Part 1: Immich Server Deployment

### Initial Deployment

**Services deployed:**
- `immich-server`: Core API, upload handling, metadata management
- `immich-ml`: Machine learning inference for face detection, object recognition, CLIP search
- `postgresql-immich`: PostgreSQL 17 database (deployed Day 1)
- `redis-immich`: Redis cache for job queuing (deployed Day 1)
- `photos` network: Isolated network for Immich microservices (10.89.5.0/24)

**Health check fix:**
Initial deployment failed health checks. Investigation revealed incorrect endpoint.

```bash
# Wrong endpoint (returned 404)
HealthCmd=curl -f http://localhost:2283/api/server-info/ping || exit 1

# Correct endpoint
HealthCmd=curl -f http://localhost:2283/api/server/ping || exit 1
```

**Lesson learned:** Always test health check endpoints directly before deploying.

### Traefik Routing Challenge

**Problem:** JavaScript loading error in browser:
```
error loading dynamically imported module: /_app/immutable/nodes/19.DtksgQgX.js (500)
```

**Root cause:** TinyAuth middleware was requiring authentication for static JavaScript/CSS files.

**Solution:** Implemented priority-based routing with two routers:

```yaml
# High priority - bypass auth for static assets
immich-assets:
  rule: "Host(`photos.patriark.org`) && PathPrefix(`/_app/`)"
  priority: 100  # Evaluated first
  middlewares:
    - crowdsec-bouncer
    - rate-limit

# Default priority - auth for main application
immich-secure:
  rule: "Host(`photos.patriark.org`)"
  middlewares:
    - crowdsec-bouncer
    - rate-limit
    - tinyauth@file
```

**Architecture decision:** Migrated from Docker labels to file-based routing for consistency across all services.

### Machine Learning Model Management

**Behavior:** Models download on-demand (not at startup)
- First face detection request triggers model download
- Current cache size: 786MB on BTRFS pool (`subvol7-containers/immich-ml-cache`)
- ML model directory configured: `MACHINE_LEARNING_CACHE_FOLDER=/cache`

**Health check configuration:**
```ini
HealthStartPeriod=600s  # 10 minutes - allows time for model downloads
```

### External Library Import

**Objective:** Import existing photos from `/mnt/btrfs-pool/subvol3-opptak/Mobil` without moving them.

**Challenge:** Immich's External Library feature rejects paths that are subdirectories of `/usr/src/app/upload` (Immich's managed storage).

**Initial attempts:**
1. ❌ Copying to `/usr/src/app/upload/library` - Photos didn't populate
2. ❌ Using `/usr/src/app/upload/library` as External Library path - Path validation failed

**Working solution:** Dual volume mount strategy

```ini
# Primary upload directory (Immich-managed)
Volume=/mnt/btrfs-pool/subvol3-opptak/immich:/usr/src/app/upload:Z

# External Library mount (separate container path)
Volume=/mnt/btrfs-pool/subvol3-opptak/immich/library:/mnt/media:ro,Z
```

**Configuration in Immich UI:**
- External Library path: `/mnt/media`
- Import strategy: Scan existing files (read-only)
- Result: Successfully imported photos, ML processing started

**Storage layout:**
```
/mnt/btrfs-pool/subvol3-opptak/
├── immich/              # New uploads from Immich
│   ├── upload/
│   ├── thumbs/
│   └── library/         # Imported photos (moved from Mobil/)
└── Mobil/ (archived)    # Original location
```

---

## Part 2: System Stability Crisis

### Swap Usage Investigation

**Symptom:** System using 92.5% swap (8GB) despite having 14GB free RAM.

**Investigation:**
```bash
$ free -h
              total        used        free      shared  buff/cache   available
Mem:           31Gi       9.9Gi        14Gi       3.2Gi       8.9Gi        20Gi
Swap:         8.0Gi       7.4Gi       641Mi

$ smem -rs swap -c "name pid swap"
name                         pid   swap
jellyfin                  534219  5.4G  # 🚨 Main culprit
qbittorrent              1234567  1.1G
chromium                 5678901  800M
...
```

**Root cause analysis:**
1. High `vm.swappiness` value (60) causing aggressive swapping
2. Jellyfin had no memory limits - allowed unbounded growth
3. System preferred freeing RAM for cache rather than keeping active processes in memory

### Solution: Multi-Layered Approach

**1. Immediate relief - Clear swap:**
```bash
sudo swapoff -a
sudo swapon -a
```

**2. Permanent swappiness tuning:**
```bash
# Set swappiness to 10 (prefer RAM for processes)
echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Verify
cat /proc/sys/vm/swappiness
# Output: 10
```

**3. Jellyfin memory limits (implemented in quadlet):**
```ini
[Service]
MemoryMax=4G      # Hard limit - OOM kill if exceeded
MemoryHigh=3G     # Soft limit - throttle if exceeded
```

**Results:**
- Swap usage: 8GB (92.5%) → 17MB
- Jellyfin memory: 1.4G used, 3G soft limit, 4G hard limit
- System stability: ✅ No more swap thrashing

**Why this works:**
- `swappiness=10`: System only swaps when RAM is truly exhausted
- `MemoryHigh=3G`: Jellyfin throttled before hitting swap
- `MemoryMax=4G`: Hard ceiling prevents runaway growth

---

## Part 3: Jellyfin Optimization

### Hardware Acceleration Setup

**Hardware identified:**
- CPU: AMD Ryzen 5 5600G with Radeon Graphics
- iGPU: AMD Radeon Vega Series (Cezanne)
- Devices: `/dev/dri/card1`, `/dev/dri/renderD128`

**GPU passthrough configuration:**
```ini
# AMD Radeon Vega GPU Hardware Acceleration
AddDevice=/dev/dri/renderD128
PodmanArgs=--group-add=render --group-add=video
```

**Critical lesson:** Must use specific device path (`/dev/dri/renderD128`), not generic directory (`/dev/dri`). The generic path causes Quadlet generator to fail silently or service to fail with exit code 126.

### Architecture Alignment

**Multi-network configuration:**
```ini
# Networks (reverse_proxy FIRST for internet access - first network gets default route)
Network=systemd-reverse_proxy
Network=systemd-media_services
Network=systemd-monitoring
```

**Why network order matters:** In Quadlets with multiple `Network=` lines, the **first network gets the default route**. Jellyfin needs internet access for metadata lookup, so `reverse_proxy` must be first.

### Resource Optimization

**CPU priority boost:**
```ini
Nice=-5  # Higher priority for smooth streaming
```

**Health check tuning:**
```ini
HealthStartPeriod=60s  # Allow time for Jellyfin startup
```

### Traefik Routing Migration

**Before (labels in quadlet):**
```ini
Label=traefik.enable=true
Label=traefik.http.routers.jellyfin.rule=Host(`jellyfin.patriark.org`)
Label=traefik.http.routers.jellyfin.middlewares=...
```

**After (file-based routing):**
```yaml
# config/traefik/dynamic/routers.yml
jellyfin-secure:
  rule: "Host(`jellyfin.patriark.org`)"
  service: "jellyfin"
  middlewares:
    - crowdsec-bouncer
    - rate-limit-public  # More generous (200/min) for streaming
```

**Benefits:**
- Centralized routing configuration
- Version controlled
- Easier to audit and modify
- No container restart needed to change routing

---

## Part 4: The Great Traefik Mystery

### The Ghost in the Machine

**Problem:** After removing TinyAuth from Jellyfin router configuration, TinyAuth login page still appeared when accessing from remote device.

**Symptoms:**
- Configuration looked correct (TinyAuth commented out)
- Traefik logs showed: `HTTP router already configured, skipping filename=routers.yml routerName=jellyfin-secure`
- No request logs appeared when accessing Jellyfin externally
- Traefik API returned 404 (dashboard was actually on different port)

**Investigation:**
```bash
# Found the culprit
find ~/containers/config/traefik -name "*.yml"
# Output included:
# /home/patriark/containers/config/traefik/dynamic/backup/routers.yml
```

**Root cause:** Traefik's file provider watches the **entire directory tree recursively** when configured with `directory: /etc/traefik/dynamic`. The `backup/` subdirectory contained old configuration files with TinyAuth enabled, which loaded FIRST and took precedence.

**Solution:**
```bash
# Move backups OUT of dynamic directory
mkdir -p ~/containers/config/traefik/backups-archive
mv ~/containers/config/traefik/dynamic/backup/* ~/containers/config/traefik/backups-archive/
rmdir ~/containers/config/traefik/dynamic/backup

# Traefik auto-reloaded within seconds
# ✅ TinyAuth no longer appearing
```

### Critical Lesson Learned

**Traefik file provider behavior:**
- `directory: /path/to/config` watches ALL subdirectories recursively
- Files are processed in **alphabetical order by full path**
- Duplicate router names: First wins, subsequent skipped with warning
- **Backup folders inside dynamic/ directory will be loaded!**

**Best practices going forward:**
1. ✅ Keep backups OUTSIDE the dynamic directory
2. ✅ Use version control (Git) for config history instead of backup folders
3. ✅ Monitor Traefik startup logs for "already configured, skipping" warnings
4. ✅ Use descriptive router names to avoid collisions

---

## Part 5: Remote Access Architecture

### Authentication Strategy

**Philosophy:** Services handle their own authentication - no forced gateway auth for all services.

**Per-service authentication:**
- **Immich** (`photos.patriark.org`): TinyAuth gateway → Immich internal auth
- **Jellyfin** (`jellyfin.patriark.org`): Direct to Jellyfin auth (no gateway)
- **Grafana** (`grafana.patriark.org`): TinyAuth gateway → Grafana internal auth
- **Traefik Dashboard** (`traefik.patriark.org`): TinyAuth gateway only

**Why this approach:**
- Mobile apps (Jellyfin) work without gateway auth complications
- Each service maintains its own user management
- Gateway auth available as optional extra layer
- Flexibility to adjust per service based on needs

### Security Layers

All internet-accessible services still protected by:
1. **CrowdSec IP reputation** (first layer - fastest rejection)
2. **Rate limiting** (per-service tuning)
3. **Service-level authentication** (Immich, Jellyfin, Grafana each handle their own)
4. **Optional TinyAuth gateway** (additional layer for admin interfaces)

---

## Final Architecture State

### Network Topology

```
Internet → Port Forward (80/443)
  ↓
Traefik (systemd-reverse_proxy: 10.89.2.0/24)
  ├─ CrowdSec IP filtering
  ├─ Rate limiting
  └─ Per-service routing
      ├─ photos.patriark.org → Immich Server (10.89.2.x + 10.89.5.x)
      ├─ jellyfin.patriark.org → Jellyfin (10.89.2.x + 10.89.1.x)
      ├─ grafana.patriark.org → Grafana (10.89.2.x + 10.89.4.x)
      └─ auth.patriark.org → TinyAuth (10.89.2.x + 10.89.3.x)

Internal networks:
- systemd-photos (10.89.5.0/24): Immich microservices + PostgreSQL + Redis
- systemd-media_services (10.89.1.0/24): Jellyfin media processing
- systemd-monitoring (10.89.4.0/24): Prometheus, Grafana, Loki, Alertmanager
- systemd-auth_services (10.89.3.0/24): TinyAuth authentication
```

### Storage Layout

```
System SSD (128GB):
├─ /home/patriark/containers/config/  # Service configs (~2GB)
└─ /home/patriark/containers/data/    # Temporary data

BTRFS Pool (4TB):
├─ subvol3-opptak/immich/             # Immich uploads (COW enabled)
│   ├── upload/                       # New uploads
│   ├── thumbs/                       # Thumbnails
│   └── library/                      # Imported photos
├─ subvol7-containers/                # Database files (NOCOW)
│   ├── immich-ml-cache/              # ML models: 786MB
│   ├── jellyfin/data/                # Jellyfin metadata
│   ├── postgresql-immich/            # Immich database
│   └── redis-immich/                 # Redis persistence
├─ subvol6-tmp/                       # Transient data
│   ├── jellyfin-cache/               # Jellyfin cache
│   └── jellyfin-transcodes/          # Temporary transcodes
├─ subvol4-multimedia/                # Media library (movies, TV)
└─ subvol5-music/                     # Music library
```

### Resource Usage (After Optimization)

**Memory:**
- Total containers: ~3.5GB (down from 5GB+ before limits)
- Jellyfin: 1.4GB (limit: 3GB soft, 4GB hard)
- Immich stack: ~800MB (server 400MB, ML 200MB, PostgreSQL 150MB, Redis 50MB)
- Monitoring stack: ~500MB
- Traefik + CrowdSec: ~150MB

**Swap:**
- Before: 7.4GB / 8GB (92.5%)
- After: 17MB / 8GB (0.2%)

**Disk:**
- System SSD: 52% (stable)
- BTRFS pool: 35% (plenty of space)

---

## Services Status Matrix

| Service | Status | External URL | Auth Layer | GPU | Memory Limit |
|---------|--------|--------------|------------|-----|--------------|
| Traefik | ✅ Running | traefik.patriark.org | TinyAuth | - | - |
| CrowdSec | ✅ Running | - | - | - | - |
| TinyAuth | ✅ Running | auth.patriark.org | Self | - | - |
| Jellyfin | ✅ Running | jellyfin.patriark.org | Self | ✅ Vega iGPU | 4GB |
| Immich Server | ✅ Running | photos.patriark.org | Self + TinyAuth | - | - |
| Immich ML | ✅ Running | (internal) | - | - | - |
| PostgreSQL | ✅ Running | (internal) | - | - | - |
| Redis | ✅ Running | (internal) | - | - | - |
| Prometheus | ✅ Running | prometheus.patriark.org | TinyAuth | - | - |
| Grafana | ✅ Running | grafana.patriark.org | Self + TinyAuth | - | - |
| Loki | ✅ Running | loki.patriark.org | TinyAuth | - | - |
| Alertmanager | ✅ Running | (internal) | - | - | - |

---

## Key Takeaways

### Technical Wins

1. **File-based Traefik routing** is superior to Docker labels for:
   - Version control and auditability
   - Centralized configuration
   - Hot-reload without container restarts
   - **But watch out for backup folders in dynamic directory!**

2. **Multi-network architecture** provides excellent isolation:
   - Services only join networks they need
   - Internal services (PostgreSQL, Redis) never exposed
   - First network in quadlet gets default route (critical!)

3. **Memory limits prevent system issues:**
   - `MemoryHigh` provides soft throttling
   - `MemoryMax` provides hard safety net
   - Combined with `swappiness=10` eliminates swap thrashing

4. **GPU passthrough for Jellyfin:**
   - Use specific device path (`/dev/dri/renderD128`)
   - Requires `--group-add=render --group-add=video`
   - Ready for VAAPI configuration in Jellyfin UI

5. **Priority-based routing** solves static asset auth issues:
   - Higher priority routes evaluated first
   - Allows bypassing auth for JS/CSS while protecting main app

### Operational Lessons

1. **Always test health check endpoints** before deploying
2. **Backup directories must live OUTSIDE watched config directories**
3. **Version control > backup folders** for configuration management
4. **Network order matters** in multi-network quadlets
5. **Per-service authentication** provides more flexibility than gateway-only auth
6. **Swappiness tuning** is critical on systems with abundant RAM

### Architecture Principles Validated

✅ **Rootless containers** - All services run as unprivileged user
✅ **Systemd quadlets** - Native integration, clear dependencies
✅ **File-based routing** - Centralized, version-controlled
✅ **Network segmentation** - Security through isolation
✅ **Resource limits** - Prevent cascading failures
✅ **Health-aware deployment** - Verify before declaring success

---

## Next Steps

### Immediate Tasks

1. **Configure VAAPI in Jellyfin UI:**
   - Dashboard → Playback → Transcoding
   - Hardware acceleration: "Video Acceleration API (VAAPI)"
   - VA-API Device: `/dev/dri/renderD128`
   - Enable hardware decoding: H264, HEVC, VP9, AV1
   - Enable hardware encoding
   - Test transcode and verify GPU usage

2. **Test Immich ML features:**
   - Face detection and recognition
   - Object/scene recognition
   - CLIP-based semantic search
   - Monitor ML model downloads and cache growth

3. **Create Grafana alerts:**
   - Jellyfin memory usage (>3GB warning, >3.8GB critical)
   - Swap usage (>50% warning)
   - Jellyfin service down
   - Immich service health

### Future Enhancements

1. **Immich features to explore:**
   - Shared albums
   - Public sharing links
   - Mobile app upload automation
   - Facial recognition training

2. **Jellyfin optimizations:**
   - Verify VAAPI transcoding performance
   - Monitor GPU usage during transcodes
   - Consider hardware tone mapping for HDR content
   - Test mobile app remote access

3. **Monitoring improvements:**
   - GPU utilization metrics
   - Container memory pressure metrics
   - Traefik request rate per service
   - Storage growth trends

4. **Documentation:**
   - Create Immich service guide (living document)
   - Update Traefik best practices guide
   - Document External Library setup pattern
   - Create troubleshooting runbook

---

## Reflections

This day demonstrated the value of **systematic troubleshooting** and **architectural consistency**. The Traefik backup folder issue could have been frustrating, but methodical investigation (checking logs, inspecting file structure, understanding provider behavior) led directly to the solution.

The migration to file-based Traefik routing, while initially seeming like extra work, proved its value immediately when we needed to iterate on Immich's static asset routing. No container restarts, just edit YAML and Traefik reloads within seconds.

The swap crisis highlighted the importance of **resource limits** even in a homelab environment. Production-grade practices (memory limits, health checks, monitoring) aren't overkill—they prevent cascading failures and make troubleshooting easier.

Most importantly, this homelab is now **remotely accessible and production-ready**. Services are protected, monitored, and optimized. The architecture is clean, documented, and maintainable.

**This is thrilling!** 🎉

---

## Commands Reference

### Swap Management
```bash
# Check swap usage
free -h
smem -rs swap -c "name pid swap"

# Clear swap
sudo swapoff -a && sudo swapon -a

# Set swappiness permanently
echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### Traefik Debugging
```bash
# Check active routers
curl -s http://localhost:8080/api/http/routers | jq '.'

# Watch logs
podman logs -f traefik

# Find all config files
find ~/containers/config/traefik -name "*.yml"

# Check for duplicates
grep -rn "jellyfin" ~/containers/config/traefik/
```

### Service Management
```bash
# Reload quadlets
systemctl --user daemon-reload

# Restart service
systemctl --user restart jellyfin.service

# Check service status with memory
systemctl --user status jellyfin.service

# Check container health
podman healthcheck run immich-server
```

### GPU Verification
```bash
# List GPU devices
ls -la /dev/dri/

# Check GPU info
lspci | grep -i vga

# Monitor GPU usage (if available)
watch -n 1 'cat /sys/class/drm/card1/device/gpu_busy_percent 2>/dev/null'
```
