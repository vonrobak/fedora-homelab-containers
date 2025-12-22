# Immich Photo Management Service

**Last Updated:** 2025-11-10
**Version:** Latest (with AMD GPU acceleration support)
**Status:** Production
**Networks:** systemd-photos
**Dependencies:** PostgreSQL, Redis, Traefik

---

## Overview

Immich is a **self-hosted photo and video management solution** designed as an alternative to Google Photos. This guide covers deployment, operation, GPU acceleration, and troubleshooting.

**Key Features:**
- Mobile app (iOS/Android) for automatic photo backup
- Smart search powered by machine learning
- Face detection and recognition
- Object detection and classification
- Timeline view and map integration
- Sharing albums and links
- Duplicate photo detection

**Current Deployment:**
- immich-server: Web interface and API
- immich-ml: Machine learning (with optional GPU acceleration)
- postgresql-immich: Database backend
- redis-immich: Caching layer

---

## Quick Reference

### Service Management

```bash
# Status check
systemctl --user status immich-server.service
systemctl --user status immich-ml.service
systemctl --user status postgresql-immich.service
systemctl --user status redis-immich.service

# Restart services
systemctl --user restart immich-server.service
systemctl --user restart immich-ml.service

# Logs
podman logs immich-server -f
podman logs immich-ml -f

# Health checks
podman healthcheck run immich-server
podman healthcheck run immich-ml
```

### Access Points

- **Web Interface:** https://immich.patriark.org
- **Mobile App:** Download from App Store/Play Store
  - Server URL: https://immich.patriark.org
  - Authentication: Immich accounts (not TinyAuth/Authelia)

---

## Architecture

### Component Overview

```
Mobile App / Web Browser
    ↓
Traefik (HTTPS + routing)
    ↓
immich-server:2283 (API + web UI)
    ↓
    ├─→ PostgreSQL (metadata storage)
    ├─→ Redis (caching)
    ├─→ immich-ml:3003 (ML processing)
    └─→ BTRFS pool (photo/video storage)
```

### Network Topology

```
systemd-photos (10.89.5.0/24) - Isolated network
├── immich-server
├── immich-ml
├── postgresql-immich
└── redis-immich

systemd-reverse_proxy (10.89.2.0/24) - Public-facing
└── immich-server (exposed via Traefik)
```

**Note:** immich-server is on **both networks**:
- systemd-photos: Communication with ML/database/redis
- systemd-reverse_proxy: Traefik reverse proxy access

### Storage Layout

```
/mnt/btrfs-pool/subvol7-containers/
├── immich-library/          # Photos and videos (SELinux: :Z)
├── immich-ml-cache/         # ML model cache (SELinux: :Z, NOCOW)
├── postgresql-immich/       # Database data (SELinux: :Z, NOCOW)
└── redis-immich/            # Redis persistence (SELinux: :Z)
```

**NOCOW Requirement:**
- PostgreSQL and Redis use NOCOW (no copy-on-write) for performance
- Required for databases on BTRFS to prevent fragmentation
- Set with: `chattr +C /path/to/directory` (before first use)

---

## Machine Learning (ML) Configuration

Immich ML provides smart search, face detection, and object recognition.

### CPU-Only Operation (Default)

**Image:** `ghcr.io/immich-app/immich-machine-learning:release`

**Resource Usage:**
- Memory: ~500MB-1GB during processing
- CPU: 400-600% during ML jobs (all cores)
- Processing time: ~1.5s per photo (face detection)

**Configuration:**
```ini
[Container]
Image=ghcr.io/immich-app/immich-machine-learning:release
Volume=/mnt/btrfs-pool/subvol7-containers/immich-ml-cache:/cache:Z
Environment=MACHINE_LEARNING_CACHE_FOLDER=/cache
MemoryMax=2G
```

### GPU Acceleration (AMD ROCm) ✨

**Status:** Available (Day 4-5 deployment ready)

**Image:** `ghcr.io/immich-app/immich-machine-learning:release-rocm`

**Prerequisites:**
- AMD GPU with ROCm support
- ROCm drivers installed (`/dev/kfd` device exists)
- User in `render` group
- ~35GB disk space (ROCm image is large)

**Benefits:**
- 5-10x faster ML processing
- Face detection: ~0.15s per photo (vs 1.5s CPU)
- Reduced CPU load (400% → 50-100%)
- 1,000 photos: 5 minutes vs 45 minutes

**Deployment:**

See comprehensive guide at: `docs/99-reports/2025-11-10-day4-5-gpu-acceleration.md`

Quick deployment:
```bash
# Step 1: Validate GPU prerequisites
./scripts/detect-gpu-capabilities.sh

# Step 2: Deploy GPU acceleration
./scripts/deploy-immich-gpu-acceleration.sh

# Step 3: Verify
podman exec -it immich-ml ls -la /dev/kfd /dev/dri
```

**GPU Configuration:**
```ini
[Container]
Image=ghcr.io/immich-app/immich-machine-learning:release-rocm
AddDevice=/dev/kfd
AddDevice=/dev/dri
GroupAdd=keep-groups
MemoryMax=4G  # Increased for GPU workloads
```

**Monitoring GPU utilization:**
```bash
# During ML processing (upload photos to trigger)
watch -n 1 cat /sys/kernel/debug/dri/0/amdgpu_pm_info

# Or with radeontop (if installed)
radeontop

# Or with rocm-smi
watch -n 1 rocm-smi
```

---

## Health Checks

All Immich services have health checks configured for auto-recovery.

### immich-server

**Health Check:**
```bash
curl -f http://localhost:2283/api/server/ping || exit 1
```

**Intervals:**
- Check every: 30s
- Timeout: 10s
- Retries: 3
- Start period: 60s

**Manual check:**
```bash
podman healthcheck run immich-server
curl http://localhost:2283/api/server/ping
```

### immich-ml

**Health Check:**
```bash
python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:3003/ping', timeout=5)" || exit 1
```

**Note:** Uses python3 because service listens on `[::]:3003` (IPv6)

**Intervals:**
- Check every: 30s
- Timeout: 10s
- Retries: 3
- Start period: **600s** (10 minutes - allows model downloading)

**Manual check:**
```bash
podman healthcheck run immich-ml
podman exec immich-ml wget -O- http://127.0.0.1:3003/ping
```

### PostgreSQL

**Health Check:**
```bash
pg_isready -U immich -d immich
```

### Redis

**Health Check:**
```bash
valkey-cli ping  # Returns PONG if healthy
```

---

## Resource Limits

All services have MemoryMax configured to prevent OOM conditions:

| Service | MemoryMax | Typical Usage | Notes |
|---------|-----------|---------------|-------|
| immich-server | 2G | ~500MB | Web + API |
| immich-ml (CPU) | 2G | ~800MB | ML processing |
| immich-ml (GPU) | 4G | ~1-2GB | GPU workloads need more |
| postgresql-immich | 1G | ~200MB | Database |
| redis-immich | 512M | ~50MB | Cache |

**Total:** ~5.5-7.5GB depending on CPU/GPU configuration

---

## Common Operations

### Mobile App Setup

1. **Install app:** Download from App Store (iOS) or Play Store (Android)
2. **Server URL:** https://immich.patriark.org
3. **Create account:** First user becomes admin
4. **Enable auto-backup:** Settings → Backup → Auto backup

**Authentication:**
- Immich has its own user accounts (separate from TinyAuth/Authelia)
- Can create multiple users for family sharing

### Uploading Photos

**Via Mobile App:**
- Auto-backup: Configured in app settings
- Manual: Select photos → Upload button

**Via Web:**
- Drag and drop into browser
- Or use upload button

### Smart Search

**ML features:** (requires immich-ml healthy)
- **Face search:** Click on face, search for similar
- **Object search:** "dog", "beach", "car", etc.
- **Location search:** Map view
- **Date search:** Timeline slider

**First upload:**
- ML processing happens in background
- Face detection: ~0.15s/photo (GPU) or ~1.5s/photo (CPU)
- Check progress: Settings → Jobs

### Sharing

**Create album:**
1. Select photos
2. Create album
3. Share link (public or private)

**Shared links:**
- Can be password protected
- Expiration date optional
- Download enabled/disabled

---

## Troubleshooting

### immich-server Issues

**Symptom:** Web interface not loading

**Check:**
```bash
# Service status
systemctl --user status immich-server.service

# Logs
podman logs immich-server --tail 50

# Network connectivity
podman exec immich-server wget -O- http://postgresql-immich:5432 || echo "Cannot reach DB"
podman exec immich-server wget -O- http://redis-immich:6379 || echo "Cannot reach Redis"
```

**Common issues:**
1. Database not ready (check postgresql-immich)
2. Redis connection failed (check redis-immich)
3. Network issue (verify systemd-photos network)

### immich-ml Unhealthy

**See:** `immich-ml-troubleshooting.md` for detailed investigation steps

**Quick checks:**
```bash
# Health check details
podman inspect immich-ml --format '{{json .State.Health}}' | jq .

# Check if ML endpoint responding
podman exec immich-ml wget -O- http://127.0.0.1:3003/ping

# Check GPU access (if GPU-enabled)
podman exec immich-ml ls -la /dev/kfd /dev/dri

# Resource usage
podman stats immich-ml --no-stream
```

**GPU-specific troubleshooting:**

See full guide: `docs/99-reports/2025-11-10-day4-5-gpu-acceleration.md`

Common GPU issues:
1. **Permission denied /dev/kfd:** User not in render group
2. **Device not found:** ROCm drivers not installed
3. **GPU not being used:** Verify devices in container, upload photos to trigger ML

### Database Issues

**PostgreSQL won't start:**
```bash
# Check logs
podman logs postgresql-immich --tail 100

# Check NOCOW attribute (must be set before first use)
lsattr -d /mnt/btrfs-pool/subvol7-containers/postgresql-immich
# Should show 'C' flag
```

**If NOCOW missing after deployment:**
- Cannot fix retroactively without data loss
- Must backup, remove, set NOCOW, restore

### Performance Issues

**Slow photo uploads:**
- Check network speed (mobile app → server)
- Check disk I/O: `iostat -x 1`
- Check BTRFS pool space

**Slow ML processing:**
- CPU-only: Expected, ~1.5s/photo
- GPU: Check GPU utilization (should show activity during processing)
- Memory pressure: Check `podman stats immich-ml`

**Slow database queries:**
- Check PostgreSQL logs for slow queries
- Consider VACUUM/ANALYZE: `podman exec postgresql-immich psql -U immich -c "VACUUM ANALYZE;"`

---

## Backup and Recovery

### What to Backup

**Critical data:**
1. **Photo library:** `/mnt/btrfs-pool/subvol7-containers/immich-library/`
2. **Database:** PostgreSQL data (automated via BTRFS snapshots)
3. **ML cache:** Can be regenerated (optional backup)

**Configuration:**
- Quadlet files: `~/.config/containers/systemd/immich-*.container`
- Environment files: (if using separate .env files)

### Backup Strategy

**Automated BTRFS snapshots:** Already configured
```bash
# Check snapshot schedule
systemctl --user list-timers | grep btrfs-backup

# Manual snapshot
sudo btrfs subvolume snapshot /mnt/btrfs-pool/subvol7-containers /mnt/btrfs-pool/.snapshots/subvol7-$(date +%Y%m%d-%H%M%S)
```

**Database export (optional):**
```bash
# Export PostgreSQL database
podman exec postgresql-immich pg_dump -U immich immich > immich-backup-$(date +%Y%m%d).sql

# Restore
podman exec -i postgresql-immich psql -U immich immich < immich-backup-YYYYMMDD.sql
```

### Disaster Recovery

**Complete failure scenario:**
1. Restore BTRFS snapshot containing immich data
2. Redeploy containers (quadlets already in git)
3. Verify database integrity
4. Regenerate ML cache (if needed)

**Data integrity:**
```bash
# Verify PostgreSQL
podman exec postgresql-immich pg_isready

# Check immich-server can connect
podman logs immich-server --tail 20 | grep -i database
```

---

## Monitoring

### Prometheus Metrics

**Exposed on:**
- immich-server: Port 2283 (application metrics)
- postgresql-immich: Port 9187 (postgres_exporter)
- redis-immich: Built-in metrics

**Key metrics to monitor:**
- Upload rate (photos/hour)
- ML processing queue depth
- Database query performance
- Storage usage growth
- Memory consumption

### Health Dashboards

**Grafana dashboards:**
- Immich service health (custom)
- PostgreSQL performance (standard)
- Container resources (cAdvisor)

**See:** `docs/40-monitoring-and-documentation/guides/monitoring-stack.md`

### Alerts

**Configured alerts:**
- Immich ML unhealthy >15 minutes
- PostgreSQL connection failures
- High memory usage (>80% of limit)
- Storage pool >85% full

**See:** `config/prometheus/alerts/immich.yml`

---

## Maintenance

### Weekly

- Review upload stats in Immich admin panel
- Check ML job queue (Settings → Jobs)
- Verify mobile app auto-backup working

### Monthly

- Review storage growth trends
- Check PostgreSQL vacuum stats
- Review and organize shared albums
- Check for duplicate photos

### Quarterly

- Review user accounts (add/remove as needed)
- Consider ML cache cleanup (if very large)
- Review and archive old photos (if desired)
- Update to latest Immich release (test first!)

---

## Updates and Upgrades

### Updating Immich

**Current version tracking:**
```ini
AutoUpdate=registry  # Enabled in quadlets
```

**Manual update:**
```bash
# Pull latest images
podman pull ghcr.io/immich-app/immich-server:release
podman pull ghcr.io/immich-app/immich-machine-learning:release  # or :release-rocm

# Restart services (quadlets will use new image)
systemctl --user restart immich-server.service
systemctl --user restart immich-ml.service
```

**Migration:**
- Immich handles database migrations automatically
- Check release notes for breaking changes
- Always have recent BTRFS snapshot before major updates

### Switching Between CPU and GPU

**CPU → GPU:**
```bash
./scripts/deploy-immich-gpu-acceleration.sh
```

**GPU → CPU (rollback):**
```bash
# Restore CPU quadlet
cp quadlets/immich-ml.container ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user restart immich-ml.service
```

---

## Security Considerations

### Authentication

**Current:** Immich-native authentication (separate from Traefik middleware)
- Each user has their own Immich account
- Not integrated with Authelia (by design - allows family sharing)

**Future:** Authelia SSO integration (see ADR-004)
- OIDC support in Immich
- Single sign-on for admin access
- Per-user access still via Immich accounts

### Network Exposure

**Internet-accessible:** Yes (via Traefik)
- Required for mobile app auto-backup
- Protected by HTTPS (Let's Encrypt certificates)
- Rate limiting via Traefik middleware

**Internal access:** All database and ML services on private network (systemd-photos)

### Data Privacy

**Self-hosted benefits:**
- Photos stay on your hardware
- No third-party AI scanning
- Complete control over data

**Sharing considerations:**
- Shared links are publicly accessible (if you share them)
- Password protection available
- Consider expiration dates for sensitive shares

---

## Performance Tuning

### Database Optimization

**PostgreSQL tuning:**
```sql
-- Check current settings
podman exec postgresql-immich psql -U immich -c "SHOW ALL;"

-- Increase shared_buffers if you have RAM
-- (requires PostgreSQL restart)
-- Default: 128MB, Consider: 512MB-1GB
```

**Vacuum maintenance:**
```bash
# Auto-vacuum is enabled by default
# Manual vacuum for optimization
podman exec postgresql-immich psql -U immich -c "VACUUM FULL ANALYZE;"
```

### ML Performance

**CPU-only optimization:**
- Increase `MACHINE_LEARNING_WORKERS` for parallel processing
- Trade-off: More CPU usage, faster processing

**GPU optimization:**
- Ensure GPU clock speeds high during processing
- Monitor with `radeontop` or `rocm-smi`
- Check GPU memory utilization

### Storage Performance

**BTRFS optimization:**
- NOCOW on database directories (already configured)
- Regular scrubs: Monthly
- Compression: Can be enabled for library (slight CPU cost)

**Check performance:**
```bash
# I/O statistics
iostat -x 1 10

# BTRFS device stats
btrfs device stats /mnt/btrfs-pool
```

---

## Advanced Topics

### Multi-User Setup

**Admin user:** First account created
**Additional users:** Settings → Users → Add user

**Permissions:**
- Each user has their own library
- Sharing between users via albums
- Admin can see all libraries (optional setting)

### External Libraries

**Importing existing photos:**
1. Copy to immich-library volume
2. Immich → Settings → External Libraries
3. Scan and import

**Limitations:**
- Slower than direct upload
- Metadata may be incomplete

### API Access

**Immich API:** Full REST API available
- Documentation: https://immich.app/docs/api
- API key: Settings → API Keys
- Use cases: Custom integrations, scripts, automation

**Example:**
```bash
API_KEY="your-api-key"
curl -H "x-api-key: $API_KEY" https://immich.patriark.org/api/server/version
```

---

## Related Documentation

**Deployment:**
- `docs/10-services/journal/2025-11-08-week2-day1-database-deployment.md` - Initial deployment
- `docs/10-services/journal/2025-11-08-week1-completion-summary.md` - Week 1 summary
- `docs/10-services/decisions/2025-11-08-immich-deployment-architecture.md` - Architecture ADR

**GPU Acceleration:**
- `docs/99-reports/2025-11-10-day4-5-gpu-acceleration.md` - Complete GPU guide
- `scripts/detect-gpu-capabilities.sh` - GPU validation script
- `scripts/deploy-immich-gpu-acceleration.sh` - Automated GPU deployment

**Troubleshooting:**
- `docs/10-services/guides/immich-ml-troubleshooting.md` - ML troubleshooting
- `docs/10-services/guides/immich-deployment-checklist.md` - Deployment checklist

**Networking:**
- `docs/00-foundation/guides/podman-fundamentals.md` - Network concepts
- `docs/10-services/guides/traefik.md` - Reverse proxy configuration

---

**Last Updated:** 2025-11-10
**Maintained By:** patriark + Claude Code
**Review Frequency:** After major Immich updates or infrastructure changes
**Next Review:** After GPU deployment validation

---

**Quick Links:**
- Immich Official Docs: https://immich.app/docs
- Immich GitHub: https://github.com/immich-app/immich
- Immich Discord: Community support and discussions
- ROCm Documentation: https://rocm.docs.amd.com/
