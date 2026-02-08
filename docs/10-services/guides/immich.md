# Immich Photo Management Service

**Last Updated:** 2026-02-08
**Version:** v2.5.5 (pinned)
**Status:** Production
**URL:** https://photos.patriark.org
**Networks:** systemd-reverse_proxy, systemd-photos, systemd-monitoring
**Dependencies:** PostgreSQL (vectorchord), Valkey (Redis), Traefik
**Assets:** ~10,608 photos/videos, 254GB storage

---

## Overview

Immich is a **self-hosted photo and video management solution** designed as an alternative to Google Photos.

**Key Features:**
- Mobile app (iOS/Android) for automatic photo backup
- Smart search powered by machine learning
- Face detection and recognition
- Object detection and classification
- Timeline view and map integration
- Sharing albums and password-protected links
- Duplicate photo detection

**Current Deployment (4 containers):**

| Container | Image | Memory Limit | Typical Usage |
|-----------|-------|-------------|---------------|
| immich-server | ghcr.io/immich-app/immich-server:v2.5.5 | 4G | ~280MB |
| immich-ml | ghcr.io/immich-app/immich-machine-learning:v2.5.5 | 4G | ~19MB idle |
| postgresql-immich | tensorchord/cloudnative-pgvecto.rs:14-v0.4.0 | 1G | ~32MB |
| redis-immich | valkey:latest | 512M | ~13MB |

---

## Quick Reference

### Service Management

```bash
# Status check (all 4 services)
systemctl --user status immich-server immich-ml postgresql-immich redis-immich

# Restart
systemctl --user restart immich-server.service

# Logs
podman logs immich-server -f
podman logs immich-ml -f

# Health checks
podman healthcheck run immich-server
podman healthcheck run immich-ml
podman healthcheck run postgresql-immich
podman healthcheck run redis-immich
```

### Access Points

- **Web Interface:** https://photos.patriark.org
- **Mobile App:** Download from App Store/Play Store
  - Server URL: https://photos.patriark.org
  - Authentication: Immich accounts (not Authelia - by design for family sharing)

---

## Architecture

### Component Overview

```
Mobile App / Web Browser
    ↓
Traefik (HTTPS + routing)
  Middleware: crowdsec → rate-limit-immich → circuit-breaker → retry → compression → security-headers
    ↓
immich-server:2283 (API + web UI + WebSocket)
    ↓
    ├─→ PostgreSQL 14 + vectorchord (metadata + ML vectors)
    ├─→ Valkey/Redis (caching)
    ├─→ immich-ml:3003 (ML processing)
    └─→ BTRFS pool (photo/video storage)
```

### Network Topology

```
systemd-reverse_proxy (10.89.2.0/24) - Internet-facing
└── immich-server (10.89.2.12, static IP per ADR-018)

systemd-photos (10.89.5.0/24) - Internal stack
├── immich-server (10.89.5.5)
├── immich-ml (10.89.5.2)
├── postgresql-immich (10.89.5.3)
└── redis-immich (10.89.5.4)

systemd-monitoring (10.89.4.0/24) - Metrics collection
└── immich-server (10.89.4.22)
```

**Note:** immich-server is on **three networks**:
- `systemd-reverse_proxy` (first = default route for internet access)
- `systemd-photos` (communication with ML/database/redis)
- `systemd-monitoring` (Prometheus scraping)

**Static IP:** Traefik resolves immich-server via /etc/hosts → 10.89.2.12 (ADR-018)

### Storage Layout

```
/mnt/btrfs-pool/subvol3-opptak/immich/
├── upload/          # User uploads (main library)
├── library/         # Additional library content
├── thumbs/          # Generated thumbnails
└── encoded-video/   # Transcoded videos

/mnt/btrfs-pool/subvol7-containers/
├── immich-ml-cache/         # ML model cache (NOCOW)
├── postgresql-immich/       # Database data (NOCOW)
└── redis-immich/            # Valkey persistence
```

**NOCOW Requirement:**
- PostgreSQL and ML cache use NOCOW (no copy-on-write) for BTRFS performance
- Set with: `chattr +C /path/to/directory` (before first use)

---

## Machine Learning (ML) Configuration

Immich ML provides smart search, face detection, and object recognition.

### Current Setup (VAAPI hardware acceleration)

**Image:** `ghcr.io/immich-app/immich-server:v2.5.5` (server has `/dev/dri` for VAAPI transcoding)

**ML Service:** `ghcr.io/immich-app/immich-machine-learning:v2.5.5` (CPU-based ML inference)

**Resource Usage:**
- Memory: ~500MB-1GB during processing
- CPU: 400-600% during ML jobs (all cores)
- Processing time: ~1.5s per photo (face detection on CPU)
- Start period: 600s (10 minutes - allows model downloading on first boot)

---

## Health Checks

All 4 services have health checks configured:

| Service | Check Command | Interval | Start Period |
|---------|--------------|----------|-------------|
| immich-server | `curl -f http://localhost:2283/api/server/ping` | 30s | 300s |
| immich-ml | `python3 urllib (IPv6-compatible)` | 30s | 600s |
| postgresql-immich | `pg_isready -U immich -d immich` | 30s | 30s |
| redis-immich | `valkey-cli ping` | 30s | 15s |

---

## SLO Monitoring

### Availability SLO (SLO-003)

- **Target:** 99.5% over 30 days (216 min/month error budget)
- **SLI:** Traefik request success ratio (HTTP 2xx/3xx + WebSocket code=0)
- **Note:** WebSocket code=0 is a successful connection, not an error
- **Dashboard:** Grafana SLO dashboard

### Upload Success SLO (SLO-004)

- **Target:** 99.5% of uploads succeed
- **SLI:** POST/PUT/PATCH success ratio via Traefik metrics
- **Note:** Returns 1.0 (100%) when no uploads are in progress

### Thumbnail Failure Alert

- **Alert:** `ImmichThumbnailFailureHigh` (Prometheus via Promtail counter)
- **Threshold:** >5 failures in 1 hour (sustained for 10 min)
- **Pipeline:** Journal logs → Promtail regex → `promtail_custom_immich_thumbnail_failures_total` → Prometheus → Alertmanager → Discord
- **Investigation:** `journalctl --user -u immich-server.service --since "1 hour ago" | grep "AssetGenerateThumbnails.*ERROR"`

---

## Common Operations

### Mobile App Setup

1. **Install app:** Download from App Store (iOS) or Play Store (Android)
2. **Server URL:** https://photos.patriark.org
3. **Create account:** First user becomes admin
4. **Enable auto-backup:** Settings → Backup → Auto backup

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

---

## Troubleshooting

### Service Not Accessible

```bash
# 1. Check all containers healthy
podman healthcheck run immich-server immich-ml postgresql-immich redis-immich

# 2. Check Traefik routing
curl -sI https://photos.patriark.org | head -5

# 3. Check internal DNS
podman exec immich-server getent hosts postgresql-immich
podman exec immich-server getent hosts redis-immich
podman exec immich-server getent hosts immich-ml

# 4. Check Traefik resolves immich-server
podman exec traefik getent hosts immich-server
# Should return: 10.89.2.12
```

### Thumbnail Failures

**Symptom:** Thumbnails not generating, alert fires

```bash
# Check recent errors
journalctl --user -u immich-server.service --since "1 hour ago" | grep -i "error\|fail\|thumbnail"

# Check ML service (thumbnail generation requires ML)
podman healthcheck run immich-ml
podman logs immich-ml --tail 20

# If persistent, recreate the container
systemctl --user restart immich-server.service
```

### Database Issues

```bash
# Check PostgreSQL logs
podman logs postgresql-immich --tail 50

# Test connectivity
podman exec postgresql-immich pg_isready -U immich -d immich

# Manual vacuum
podman exec postgresql-immich psql -U immich -c "VACUUM ANALYZE;"
```

### Known Issues

- **User=1000:1000 removed:** Immich folder integrity check is incompatible with explicit UID mapping in quadlets. Container runs as default user.
- **WebSocket code=0:** Traefik reports WebSocket connections as HTTP code 0. These are successful connections and are correctly handled in SLO calculations (fixed 2026-02-07).

---

## Backup and Recovery

### What to Backup

**Critical data:**
1. **Photo library:** `/mnt/btrfs-pool/subvol3-opptak/immich/`
2. **Database:** `/mnt/btrfs-pool/subvol7-containers/postgresql-immich/`
3. **ML cache:** Can be regenerated (optional backup)

**Configuration:**
- Quadlet files: `~/containers/quadlets/immich-*.container`
- Traefik routing: `~/containers/config/traefik/dynamic/routers.yml`

### Database Export

```bash
# Export PostgreSQL database
podman exec postgresql-immich pg_dump -U immich immich > immich-backup-$(date +%Y%m%d).sql

# Restore
podman exec -i postgresql-immich psql -U immich immich < immich-backup-YYYYMMDD.sql
```

---

## Security

- **Authentication:** Immich-native (not Authelia - allows family sharing)
- **Traefik middleware:** CrowdSec IP reputation → rate-limit-immich → circuit-breaker → retry → compression → security-headers
- **Rate limit:** Custom `rate-limit-immich` (higher capacity for photo operations)
- **No Authelia:** Immich handles its own auth; Authelia would break mobile app sync
- **TLS:** Let's Encrypt via Traefik, HSTS enabled

---

## Related Documentation

- ADR-004: Immich Deployment Architecture
- ADR-018: Static IP Multi-Network Services
- `config/prometheus/rules/slo-recording-rules.yml` (SLO-003, SLO-004)
- `config/prometheus/rules/log-based-alerts.yml` (ImmichThumbnailFailureHigh)
- `docs/40-monitoring-and-documentation/guides/monitoring-stack.md`

---

**Last Updated:** 2026-02-07
**Maintained By:** patriark + Claude Code
**Review Frequency:** After major Immich updates or infrastructure changes
