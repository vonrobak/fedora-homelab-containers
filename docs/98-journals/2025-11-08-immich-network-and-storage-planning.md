# Immich Network Topology & Storage Planning

**Date:** 2025-11-08
**Task:** Week 1 Day 4 - Network and Storage Architecture
**Status:** ✅ Complete
**Context:** Detailed planning following ADR approval

---

## Network Topology Design

### Current Network Infrastructure

**Existing Networks:**
```
systemd-reverse_proxy  (10.89.2.0/24)  - Traefik, external-facing services
systemd-media_services (10.89.1.0/24)  - Jellyfin
systemd-auth_services  (10.89.3.0/24)  - TinyAuth, Authelia (planned)
systemd-monitoring     (10.89.4.0/24)  - Prometheus, Grafana, Loki, Alertmanager
```

### New Network for Photos Service

**systemd-photos** (10.89.5.0/24)
- **Purpose:** Isolate photo management infrastructure
- **Subnet:** 10.89.5.0/24 (254 usable IPs)
- **Gateway:** 10.89.5.1
- **DNS:** Podman aardvark-dns

**Network Creation:**
```bash
podman network create \
  --driver bridge \
  --subnet 10.89.5.0/24 \
  --gateway 10.89.5.1 \
  --opt com.docker.network.bridge.name=br-photos \
  systemd-photos
```

**Quadlet Network File:** `~/.config/containers/systemd/systemd-photos.network`
```ini
[Network]
Driver=bridge
Subnet=10.89.5.0/24
Gateway=10.89.5.1
Label=app=immich
Label=network=photos
```

---

### Multi-Network Service Architecture

**Immich Server (immich-server):**
- **Primary network:** systemd-photos (10.89.5.x)
- **Secondary networks:**
  - systemd-reverse_proxy (10.89.2.x) - Traefik routing
  - systemd-monitoring (10.89.4.x) - Prometheus metrics scraping

**Why multi-network?**
- Accept HTTP requests from Traefik (reverse_proxy network)
- Communicate with PostgreSQL and Redis (photos network)
- Export metrics to Prometheus (monitoring network)

**Quadlet Configuration:**
```ini
[Container]
Network=systemd-photos.network
Network=systemd-reverse_proxy.network
Network=systemd-monitoring.network
```

---

### Service Network Membership Table

| Service | systemd-photos | systemd-reverse_proxy | systemd-monitoring |
|---------|----------------|----------------------|--------------------|
| **immich-server** | ✅ Primary | ✅ Traefik access | ✅ Metrics export |
| **immich-ml** | ✅ Only | ❌ | ❌ |
| **postgresql-immich** | ✅ Only | ❌ | ⚠️ Optional* |
| **redis-immich** | ✅ Only | ❌ | ⚠️ Optional* |
| **traefik** | ❌ | ✅ Primary | ✅ Metrics export |
| **prometheus** | ❌ | ❌ | ✅ Primary |

*Optional: If using postgres_exporter/redis_exporter sidecars for monitoring

---

### Communication Flow Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                    Internet (443/80)                             │
└────────────────────────────┬─────────────────────────────────────┘
                             │
┌────────────────────────────▼─────────────────────────────────────┐
│ systemd-reverse_proxy (10.89.2.0/24)                             │
│                                                                   │
│  ┌─────────────┐            ┌─────────────────┐                 │
│  │   Traefik   │───routes──▶│ immich-server   │                 │
│  │ :80, :443   │            │ :2283           │                 │
│  └─────────────┘            └────────┬────────┘                 │
│                                      │                           │
└──────────────────────────────────────┼───────────────────────────┘
                                       │
┌──────────────────────────────────────▼───────────────────────────┐
│ systemd-photos (10.89.5.0/24)                                    │
│                                                                   │
│  ┌─────────────────┐        ┌──────────────────┐                │
│  │ immich-server   │───────▶│ postgresql-immich│                │
│  │ (bridge)        │ :5432  │ PostgreSQL 14    │                │
│  └────────┬────────┘        └──────────────────┘                │
│           │                                                       │
│           │                 ┌──────────────────┐                │
│           └────────────────▶│  redis-immich    │                │
│                      :6379  │  Valkey 8        │                │
│                             └──────────────────┘                │
│                                                                   │
│  ┌─────────────────┐                                             │
│  │ immich-ml       │───requests via immich-server API            │
│  │ ML Inference    │                                             │
│  └─────────────────┘                                             │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
                                       │
┌──────────────────────────────────────▼───────────────────────────┐
│ systemd-monitoring (10.89.4.0/24)                                │
│                                                                   │
│  ┌─────────────┐                                                 │
│  │ Prometheus  │◀──scrapes /metrics from immich-server           │
│  └─────────────┘                                                 │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

---

### Service Discovery and DNS

**Internal DNS Resolution (aardvark-dns):**

Within `systemd-photos` network:
```
immich-server.dns.podman     → 10.89.5.10
postgresql-immich.dns.podman → 10.89.5.11
redis-immich.dns.podman      → 10.89.5.12
immich-ml.dns.podman         → 10.89.5.13
```

**Environment Variables for Service Discovery:**
```bash
# immich-server container
DB_HOSTNAME=postgresql-immich
REDIS_HOSTNAME=redis-immich
IMMICH_MACHINE_LEARNING_URL=http://immich-ml:3003
```

**External DNS (Pi-hole):**
```
photos.patriark.org → 192.168.1.70 (fedora-htpc)
```

---

### Security Boundaries

**Network Isolation:**

1. **Internet-facing (systemd-reverse_proxy):**
   - Only Traefik and services needing external access
   - CrowdSec bouncer protects all ingress

2. **Backend services (systemd-photos):**
   - No direct internet access
   - Only accessible via immich-server bridge

3. **Data layer (postgresql-immich, redis-immich):**
   - Completely isolated on systemd-photos
   - No external network connectivity

**Firewall Rules (existing):**
```bash
# Already configured on fedora-htpc
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload

# Podman rootless uses slirp4netns - no additional firewall config needed
```

---

## Storage Architecture Planning

### Overview

**Design Goals:**
- **Performance:** PostgreSQL database on fast storage with NOCOW
- **Capacity:** Photo library can grow to 500GB+ on BTRFS pool
- **Reliability:** BTRFS snapshots for disaster recovery
- **Efficiency:** Separate backup tiers for critical vs regenerable data

---

### Storage Layout

#### System SSD (NVMe - 128GB, currently 52% used)

```
/home/patriark/containers/config/immich/
├── server/                   # Immich server config files (minimal)
│   └── config.yml           # Server configuration
│
└── machine-learning/         # ML model cache (15-25GB)
    ├── clip/                # CLIP models for semantic search
    ├── facial-recognition/  # Face detection models
    └── cache/               # Inference cache
```

**Capacity Planning:**
- ML models: 15-25GB (one-time download)
- Config files: <100MB
- **Total SSD impact:** ~25GB (52% → 70% usage)
- **Monitoring:** Alert if SSD usage > 80%

**Fallback:** If SSD fills up, move ML cache to BTRFS pool (slower but acceptable)

---

#### BTRFS Pool (/mnt/btrfs-pool/ - 10TB)

**subvol7-containers/** (existing - operational data)
```
/mnt/btrfs-pool/subvol7-containers/
├── postgresql-immich/        # Database files (NOCOW)
│   └── data/                # PostgreSQL data directory
│       ├── base/            # Database tables (1-3GB initially)
│       ├── pg_wal/          # Write-ahead logs
│       └── pg_stat/         # Statistics
│
└── redis-immich/             # Redis persistent storage (NOCOW)
    ├── dump.rdb             # Redis snapshot (minimal)
    └── appendonly.aof       # Append-only file (if enabled)
```

**NOCOW Attribute:**
```bash
# Applied to database directories to prevent snapshot overhead
sudo chattr +C /mnt/btrfs-pool/subvol7-containers/postgresql-immich
sudo chattr +C /mnt/btrfs-pool/subvol7-containers/redis-immich

# Verify NOCOW
lsattr -d /mnt/btrfs-pool/subvol7-containers/postgresql-immich
# Expected: ---------------C--
```

**Why NOCOW for databases?**
- PostgreSQL performs many random writes (index updates, WAL)
- BTRFS COW doubles write amplification for databases
- NOCOW eliminates this overhead
- Trade-off: Database files won't benefit from snapshots, but we backup via `pg_dump`

---

**subvol8-photos/** (NEW - photo library)
```
/mnt/btrfs-pool/subvol8-photos/
├── library/                  # Original photos/videos (COW enabled)
│   ├── upload/              # Temporary upload staging
│   └── <user-id>/           # User photo libraries
│       ├── 2025/            # Organized by year
│       │   ├── 01/          # Month
│       │   │   └── IMG_*.jpg
│       │   └── 02/
│       └── ...
│
├── thumbs/                   # Generated thumbnails (COW enabled)
│   ├── preview/             # Web preview thumbnails
│   └── thumbnail/           # Grid view thumbnails
│
└── encoded-video/            # Transcoded videos (COW enabled)
    └── <video-id>/          # Transcoded versions
```

**Subvolume Creation:**
```bash
# Create new subvolume for photos
sudo btrfs subvolume create /mnt/btrfs-pool/subvol8-photos

# Set ownership for rootless container
sudo chown -R $(id -u):$(id -g) /mnt/btrfs-pool/subvol8-photos

# Set SELinux context for Podman
sudo chcon -R -t container_file_t /mnt/btrfs-pool/subvol8-photos

# Mount in immich-server and immich-ml containers
Volume=/mnt/btrfs-pool/subvol8-photos:/usr/src/app/upload:Z
```

**Why COW (no +C) for photo library?**
- BTRFS snapshots work on photo library (daily/weekly backups)
- Mostly sequential writes (new photos uploaded, rarely modified)
- COW overhead negligible for large sequential files
- Snapshot protection is valuable for user data

---

### Storage Capacity Planning

**Initial Deployment (Week 2):**
```
PostgreSQL:        1 GB     (metadata for 0 photos initially)
Redis:             50 MB    (session cache)
ML models:         20 GB    (system SSD)
Photo library:     0 GB     (empty initially)
Thumbnails:        0 GB
────────────────────────────
Total:             ~21 GB
```

**After 6 Months (estimated 10k photos):**
```
PostgreSQL:        2 GB     (10k photo metadata + face embeddings)
Redis:             100 MB
ML models:         20 GB    (no growth - models cached)
Photo library:     50 GB    (10k photos @ 5MB average)
Thumbnails:        5 GB     (10% of library)
────────────────────────────
Total:             ~77 GB
```

**After 2 Years (estimated 50k photos):**
```
PostgreSQL:        4 GB     (50k photo metadata)
Redis:             200 MB
ML models:         20 GB
Photo library:     250 GB   (50k photos)
Thumbnails:        25 GB
────────────────────────────
Total:             ~299 GB
```

**After 5 Years (estimated 100k photos):**
```
PostgreSQL:        6 GB
Redis:             300 MB
ML models:         20 GB
Photo library:     500 GB   (100k photos)
Thumbnails:        50 GB
────────────────────────────
Total:             ~576 GB
```

**BTRFS Pool Capacity:** 10TB available
**Headroom:** Even at 500GB photos, only 5% of pool used

---

### Backup Strategy Integration

**Tier Assignment:**

| Data Type | Location | Backup Tier | Retention |
|-----------|----------|-------------|-----------|
| **PostgreSQL** | subvol7-containers | Tier 1 (Critical) | 7 daily local + 8 weekly external |
| **Photo library** | subvol8-photos/library | Tier 1 (Critical) | 7 daily local + 8 weekly external |
| **Thumbnails** | subvol8-photos/thumbs | Tier 2 (Regenerable) | 7 daily local only |
| **Encoded video** | subvol8-photos/encoded-video | Tier 2 (Regenerable) | 7 daily local only |
| **ML models** | system SSD | Not backed up | Can re-download |
| **Redis** | subvol7-containers | Tier 2 (Regenerable) | 7 daily local only |

**Rationale:**
- **PostgreSQL:** Metadata is irreplaceable (face tags, albums, search index)
- **Photo library:** Original photos are irreplaceable
- **Thumbnails:** Can regenerate from originals (CPU/GPU cost acceptable)
- **Encoded video:** Can re-transcode from originals
- **ML models:** Can re-download from Immich repository (~1 hour)
- **Redis:** Ephemeral cache, no critical data

---

**Backup Script Integration:**

Update `scripts/btrfs-snapshot-backup.sh` configuration:

```bash
# Add new Tier 1 entry for photos
TIER1_PHOTOS_ENABLED=true
TIER1_PHOTOS_SOURCE="/mnt/btrfs-pool/subvol8-photos"
TIER1_PHOTOS_LOCAL_RETENTION_DAILY=7
TIER1_PHOTOS_EXTERNAL_RETENTION_WEEKLY=8
TIER1_PHOTOS_EXTERNAL_RETENTION_MONTHLY=12

# PostgreSQL already in Tier 1 (subvol7-containers)
# No changes needed - already backing up containers subvolume
```

**PostgreSQL Logical Backup (in addition to snapshots):**

```bash
# Create pg_dump backup before snapshots
# Added to btrfs-snapshot-backup.sh

POSTGRES_BACKUP_DIR="/mnt/btrfs-pool/subvol7-containers/postgresql-backups"
mkdir -p "$POSTGRES_BACKUP_DIR"

podman exec postgresql-immich pg_dump -U immich immich \
  | gzip > "$POSTGRES_BACKUP_DIR/immich-$(date +%Y%m%d).sql.gz"

# Retention: keep 7 daily logical backups
find "$POSTGRES_BACKUP_DIR" -name "immich-*.sql.gz" -mtime +7 -delete
```

**Why both BTRFS snapshots AND pg_dump?**
- **BTRFS snapshots:** Fast recovery, entire database state
- **pg_dump:** Portable, version-independent, can restore to different PostgreSQL version

---

### Monitoring and Alerts

**Storage Monitoring (Grafana):**

**Dashboard: Immich Storage Health**
```
Panel 1: System SSD Usage
  - Gauge: 0-100% (alert at 80%)
  - Current: ML model cache size

Panel 2: Photo Library Growth
  - Graph: Photo count over time
  - Graph: Storage usage (GB)
  - Projection: Months until 1TB

Panel 3: Database Size
  - PostgreSQL data directory size
  - Growth rate (MB/day)

Panel 4: BTRFS Pool Capacity
  - Overall pool usage
  - Allocated to subvol8-photos
  - Snapshot overhead
```

**Alertmanager Rules:**

```yaml
- alert: SystemSSDHighUsage
  expr: (node_filesystem_size_bytes{mountpoint="/"} - node_filesystem_avail_bytes{mountpoint="/"}) / node_filesystem_size_bytes{mountpoint="/"} > 0.80
  for: 10m
  annotations:
    summary: "System SSD usage above 80%"
    description: "Consider moving ML cache to BTRFS pool"

- alert: PhotoLibraryGrowthRapid
  expr: rate(immich_library_size_bytes[7d]) > 10000000000  # 10GB/week
  annotations:
    summary: "Photo library growing >10GB/week"
    description: "Review storage capacity planning"

- alert: PostgreSQLSizeLarge
  expr: pg_database_size_bytes{datname="immich"} > 10000000000  # 10GB
  for: 1h
  annotations:
    summary: "Immich database exceeds 10GB"
    description: "Investigate metadata growth or vacuum needed"
```

---

### Performance Considerations

**PostgreSQL Performance Tuning:**

```bash
# Applied via environment variables in Quadlet
Environment=POSTGRES_SHARED_BUFFERS=256MB       # 25% of expected DB size
Environment=POSTGRES_EFFECTIVE_CACHE_SIZE=1GB   # System memory for caching
Environment=POSTGRES_WORK_MEM=16MB              # Per-operation memory
Environment=POSTGRES_MAINTENANCE_WORK_MEM=128MB # For VACUUM, CREATE INDEX
```

**BTRFS Optimization:**

```bash
# Mount options for photo subvolume (already applied at pool level)
# /etc/fstab entry for BTRFS pool includes:
# compress=zstd:1,noatime,space_cache=v2

# Compression saves space on photo metadata
# noatime reduces unnecessary writes
# space_cache=v2 improves performance
```

**Expected Performance:**
- Photo upload: 10-50 MB/s (network limited, not storage)
- Thumbnail generation: GPU-accelerated, 100+ photos/minute
- Database queries: <50ms for metadata lookups
- ML inference: 5-10 photos/second (AMD GPU ROCm)

---

## Implementation Checklist

### Network Setup (Week 2 Day 1)

- [ ] Create systemd-photos.network Quadlet file
- [ ] Activate network: `systemctl --user daemon-reload && systemctl --user start systemd-photos-network.service`
- [ ] Verify network: `podman network ls | grep systemd-photos`
- [ ] Inspect network: `podman network inspect systemd-photos`
- [ ] Update CLAUDE.md with new network documentation

### Storage Setup (Week 2 Day 1)

- [ ] Create subvol8-photos: `sudo btrfs subvolume create /mnt/btrfs-pool/subvol8-photos`
- [ ] Set ownership: `sudo chown -R $(id -u):$(id -g) /mnt/btrfs-pool/subvol8-photos`
- [ ] Create directory structure: library/, thumbs/, encoded-video/
- [ ] Apply NOCOW to PostgreSQL directory: `sudo chattr +C /mnt/btrfs-pool/subvol7-containers/postgresql-immich`
- [ ] Apply NOCOW to Redis directory: `sudo chattr +C /mnt/btrfs-pool/subvol7-containers/redis-immich`
- [ ] Verify attributes: `lsattr -d /mnt/btrfs-pool/subvol7-containers/postgresql-immich`
- [ ] Set SELinux contexts: `sudo chcon -R -t container_file_t /mnt/btrfs-pool/subvol8-photos`

### Backup Integration (Week 2 Day 2)

- [ ] Update btrfs-snapshot-backup.sh with subvol8-photos configuration
- [ ] Add PostgreSQL pg_dump to backup script
- [ ] Test manual backup: `~/containers/scripts/btrfs-snapshot-backup.sh --local-only --verbose`
- [ ] Verify snapshots created for subvol8-photos
- [ ] Update backup guide with Immich-specific procedures

### Monitoring Setup (Week 2 Day 5)

- [ ] Create Grafana dashboard: Immich Storage Health
- [ ] Add Prometheus metrics: photo count, library size, database size
- [ ] Configure Alertmanager rules for storage thresholds
- [ ] Test alerts by simulating high SSD usage

---

## Validation Tests

### Network Connectivity Tests (Week 2 Day 1)

```bash
# Test 1: Verify network exists
podman network inspect systemd-photos | jq '.[] | .name'
# Expected: "systemd-photos"

# Test 2: Deploy test container on network
podman run -d --name test-photos --network systemd-photos alpine sleep 300
podman exec test-photos ping -c 3 10.89.5.1  # Gateway
# Expected: 3 packets transmitted, 3 received

# Test 3: DNS resolution (after services deployed)
podman exec immich-server getent hosts postgresql-immich
# Expected: <IP> postgresql-immich.dns.podman

# Cleanup
podman rm -f test-photos
```

### Storage Tests (Week 2 Day 1)

```bash
# Test 1: Verify NOCOW on PostgreSQL
lsattr -d /mnt/btrfs-pool/subvol7-containers/postgresql-immich | grep 'C'
# Expected: ---------------C-- (NOCOW enabled)

# Test 2: Verify COW on photos (no C attribute)
lsattr -d /mnt/btrfs-pool/subvol8-photos | grep -v 'C'
# Expected: ---------------- (COW enabled, no C)

# Test 3: Test snapshot creation
sudo btrfs subvolume snapshot -r /mnt/btrfs-pool/subvol8-photos /mnt/btrfs-pool/.snapshots/photos/test-snapshot
sudo btrfs subvolume list /mnt/btrfs-pool | grep test-snapshot
# Expected: Snapshot listed

# Cleanup
sudo btrfs subvolume delete /mnt/btrfs-pool/.snapshots/photos/test-snapshot
```

### Performance Baseline (Week 2 Day 5)

```bash
# Test 1: PostgreSQL write performance
podman exec postgresql-immich pgbench -i -s 10 immich
podman exec postgresql-immich pgbench -c 10 -t 100 immich
# Baseline TPS for comparison after optimization

# Test 2: Storage write speed
dd if=/dev/zero of=/mnt/btrfs-pool/subvol8-photos/test bs=1M count=1000 conv=fdatasync
# Baseline: ~200-500 MB/s on BTRFS RAID0

# Test 3: Photo upload simulation (after deployment)
# Upload 100 test photos, measure time
# Calculate: photos/second, MB/second

# Cleanup
rm /mnt/btrfs-pool/subvol8-photos/test
```

---

## References

- **ADR:** `docs/10-services/decisions/2025-11-08-immich-deployment-architecture.md`
- **Network Architecture:** `docs/00-foundation/guides/network-architecture.md`
- **Backup Strategy:** `docs/20-operations/guides/backup-strategy.md`
- **BTRFS Management:** `docs/20-operations/guides/btrfs-management.md`
- **Journey Guide:** `docs/10-services/journal/20251107-immich-deployment-journey.md`

---

**Prepared by:** Claude Code & patriark
**Journey:** Week 1 Day 4 of Immich Deployment (Proposal C)
**Status:** ✅ Day 4 Planning Complete - Ready for Week 2 Implementation
