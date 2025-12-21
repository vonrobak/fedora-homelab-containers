# ADR: Immich Deployment Architecture

**Date:** 2025-11-08
**Status:** Proposed
**Context:** Week 1 Day 3-4 - Immich Research & Architecture Planning
**Decision Makers:** Claude Code & patriark

---

## Context and Problem Statement

We need to deploy Immich, a self-hosted photo and video management solution (Google Photos alternative), as part of the Week 1-4 balanced expansion roadmap. This deployment represents:

1. **First database-backed service** - PostgreSQL + Redis infrastructure pattern
2. **First ML workload** - Machine learning for face detection and object recognition
3. **First multi-container service** - 4+ containers working together
4. **First mobile-integrated service** - iOS/Android apps connecting to homelab
5. **Largest storage consumer** - Photo library potentially 100GB+ over time

The deployment must align with existing infrastructure patterns (rootless Podman, systemd quadlets, Traefik integration, layered security) while establishing reusable patterns for future database-backed services.

---

## Decision Drivers

### Technical Requirements

- **Performance:** ML inference and video transcoding need hardware acceleration
- **Security:** Photo library is sensitive data requiring authentication and encryption
- **Reliability:** Photo backup is critical - data loss unacceptable
- **Scalability:** Must handle 10k-50k photos initially, grow to 100k+
- **Maintainability:** Configuration as code, repeatable deployment

### Learning Objectives

- Database deployment and management (PostgreSQL + Redis)
- Multi-container orchestration with systemd
- ML workload integration and GPU acceleration
- Mobile app integration patterns
- Complex service networking
- Performance optimization techniques

### Infrastructure Constraints

- **Platform:** Fedora Workstation 42, rootless Podman
- **Orchestration:** systemd quadlets (not docker-compose)
- **Networking:** Existing Traefik reverse proxy, systemd-managed networks
- **Storage:** BTRFS pool (10TB available), System SSD (128GB, currently 52% used)
- **GPU:** AMD GPU available for hardware acceleration
- **Authentication:** TinyAuth currently, Authelia SSO planned (Week 3)

---

## Considered Options

### Option 1: Monolithic Container (imagegenius/docker-immich)

**Pros:**
- Single container simplifies deployment
- Lower resource overhead
- Easier troubleshooting (one container to debug)

**Cons:**
- Less flexible (can't scale individual services)
- Not official Immich approach
- Harder to upgrade individual components
- Doesn't teach microservices patterns
- Black box architecture (limited learning)

**Decision:** ❌ Rejected - Doesn't align with learning objectives

---

### Option 2: Docker Compose (Official Approach)

**Pros:**
- Official Immich deployment method
- Well-documented and community-tested
- Simple to set up initially

**Cons:**
- Docker Compose not native to Podman workflow
- Doesn't integrate with systemd
- Conflicts with existing quadlet-based infrastructure
- Requires `podman-compose` or translation layer
- Doesn't align with homelab architecture

**Decision:** ❌ Rejected - Incompatible with systemd quadlet pattern

---

### Option 3: Systemd Quadlets (Podman-Native Microservices) ✅ **SELECTED**

**Pros:**
- Native Podman integration with systemd
- Each container managed as systemd service
- Full control over service dependencies
- Aligns with existing infrastructure (Traefik, Jellyfin, monitoring)
- Excellent learning opportunity (microservices orchestration)
- Production-grade reliability (systemd supervision)
- Reusable pattern for future database services

**Cons:**
- More initial setup complexity
- Manual Quadlet file creation
- Network configuration more verbose
- Requires understanding systemd dependencies

**Decision:** ✅ **CHOSEN** - Best alignment with infrastructure and learning goals

---

## Architecture Decisions

### 1. Container Structure

**Decision:** Deploy 4 containers as separate systemd services using Quadlets

**Components:**

1. **immich-server** (Main API and background jobs)
   - Image: `ghcr.io/immich-app/immich-server:release`
   - Purpose: REST API, photo uploads, metadata extraction, thumbnail generation
   - Service file: `~/.config/containers/systemd/immich-server.container`
   - Dependencies: PostgreSQL, Redis

2. **immich-machine-learning** (ML inference)
   - Image: `ghcr.io/immich-app/immich-machine-learning:release-rocm`
   - Purpose: Face detection, object recognition, CLIP semantic search
   - Service file: `~/.config/containers/systemd/immich-ml.container`
   - Hardware: AMD GPU via ROCm acceleration

3. **postgresql** (Database)
   - Image: `ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0`
   - Purpose: Metadata storage, vector similarity search (pgvecto.rs extension)
   - Service file: `~/.config/containers/systemd/postgresql-immich.container`
   - Storage: BTRFS subvolume with NOCOW attribute

4. **redis** (Cache and job queue)
   - Image: `docker.io/valkey/valkey:8`
   - Purpose: Session management, job queue coordination
   - Service file: `~/.config/containers/systemd/redis-immich.container`
   - Note: Using Valkey (Redis fork) per official Immich 2025 recommendation

**Rationale:**
- Separate services enable independent scaling and troubleshooting
- systemd dependency chains ensure proper startup order
- Each service can be monitored, restarted, and updated independently
- Aligns with existing quadlet-based infrastructure

---

### 2. Network Topology

**Decision:** Create dedicated `systemd-photos` network with selective connectivity to other networks

**Network Architecture:**

```
┌─────────────────────────────────────────────────────────────┐
│ systemd-reverse_proxy (10.89.2.0/24)                        │
│  - traefik                                                   │
│  - immich-server (photos.patriark.org)                      │
└─────────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────────┐
│ systemd-photos (10.89.5.0/24) - NEW                         │
│  - immich-server                                             │
│  - immich-ml                                                 │
│  - postgresql-immich                                         │
│  - redis-immich                                              │
└─────────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────────┐
│ systemd-monitoring (10.89.4.0/24)                           │
│  - prometheus (scrapes /metrics from immich-server)          │
└─────────────────────────────────────────────────────────────┘
```

**Network Membership:**
- **immich-server:** systemd-reverse_proxy (Traefik routing), systemd-photos (backend access), systemd-monitoring (metrics export)
- **immich-ml:** systemd-photos only (isolated, no external access)
- **postgresql-immich:** systemd-photos only (database isolation)
- **redis-immich:** systemd-photos only (cache isolation)

**Rationale:**
- **Security:** Database and Redis isolated from internet-facing networks
- **Flexibility:** Immich-server bridges networks for routing and monitoring
- **Scalability:** Dedicated network can grow (future: mobile app API gateway, backup containers)
- **Learning:** Demonstrates multi-network service architecture

**Network Creation:**
```bash
podman network create \
  --driver bridge \
  --subnet 10.89.5.0/24 \
  --gateway 10.89.5.1 \
  systemd-photos
```

---

### 3. Storage Strategy

**Decision:** Multi-tier storage with BTRFS subvolumes and NOCOW for databases

**Storage Layout:**

```
SYSTEM SSD (NVMe - 128GB):
  /home/patriark/containers/config/immich/
    ├── config.yml           # Immich server configuration
    └── machine-learning/    # ML model cache (15-20GB)

BTRFS POOL (/mnt/btrfs-pool/ - 10TB):
  subvol7-containers/
    ├── postgresql-immich/   # Database files (NOCOW, 1-3GB)
    └── redis-immich/        # Persistent cache (minimal)

  subvol8-photos/            # NEW SUBVOLUME
    ├── library/             # Original photos/videos (grow to 100GB+)
    │   ├── upload/         # User uploads
    │   └── library/        # Organized by user/date
    ├── thumbs/             # Generated thumbnails (10-20% of library size)
    └── encoded-video/      # Transcoded videos (varies)
```

**NOCOW Configuration:**
```bash
# Create subvolume for photos
sudo btrfs subvolume create /mnt/btrfs-pool/subvol8-photos

# Disable copy-on-write for database directories (performance)
sudo chattr +C /mnt/btrfs-pool/subvol7-containers/postgresql-immich
sudo chattr +C /mnt/btrfs-pool/subvol7-containers/redis-immich

# Keep COW enabled for photos (snapshot-friendly)
# No +C attribute on subvol8-photos/
```

**Backup Strategy:**

| Data Type | Location | Tier | Local Retention | External Retention |
|-----------|----------|------|-----------------|-------------------|
| PostgreSQL DB | subvol7-containers | Tier 1 (Critical) | 7 daily | 8 weekly + 12 monthly |
| Photo library | subvol8-photos | Tier 1 (Critical) | 7 daily | 8 weekly + 12 monthly |
| ML model cache | system SSD | Not backed up | - | - |
| Thumbnails | subvol8-photos | Tier 2 (Regenerable) | 7 daily | 4 monthly |

**Rationale:**
- **Performance:** NOCOW on PostgreSQL prevents snapshot overhead during heavy writes
- **Reliability:** Photo library uses COW for BTRFS snapshot protection
- **Efficiency:** ML model cache on fast SSD, regenerable thumbnails not externally backed up
- **Scalability:** Dedicated subvolume can grow independently, easy to monitor

---

### 4. Database Architecture

**Decision:** Dedicated PostgreSQL instance for Immich (not shared)

**PostgreSQL Configuration:**
- **Version:** PostgreSQL 14 (Immich-tested)
- **Extensions:** pgvecto.rs (vector similarity search for ML features)
- **Image:** `ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0`
- **Storage:** 1-3GB initially, grows with photo metadata
- **Shared memory:** 128MB (default sufficient for <50k photos)

**Why dedicated vs. shared PostgreSQL?**

**Chosen: Dedicated PostgreSQL instance per service**

**Pros:**
- Version isolation (Immich needs specific PostgreSQL + extension versions)
- Easier upgrades (Immich DB can upgrade without affecting other services)
- Failure isolation (Immich DB issues don't impact future Nextcloud, etc.)
- Simpler backup/restore (per-service database backups)
- Learning: Understand database deployment pattern, repeat for future services

**Cons:**
- Higher memory overhead (~200MB per PostgreSQL instance)
- More containers to manage

**Future Consideration:** If deploying 5+ database-backed services, re-evaluate shared PostgreSQL with separate databases. For 1-3 services, dedicated instances are cleaner.

---

### 5. Hardware Acceleration

**Decision:** AMD GPU acceleration for both ML inference and video transcoding

**ML Acceleration (immich-machine-learning):**

**Approach:** Use ROCm-enabled container image
- Image: `ghcr.io/immich-app/immich-machine-learning:release-rocm`
- Device passthrough: `/dev/dri` (AMD GPU render nodes)
- ROCm version: 6.3.4+ (verify AMD GPU compatibility)

**Benefits:**
- 5-10x faster face detection vs CPU
- Faster CLIP semantic search
- Reduced CPU load during photo library scan

**Considerations:**
- ROCm image requires ~35GB disk space (first install)
- May need `HSA_OVERRIDE_GFX_VERSION` for unsupported AMD GPU models
- Higher idle GPU power consumption (5 min cooldown after inference)

**Video Transcoding (immich-server):**

**Approach:** VAAPI (Video Acceleration API) for AMD GPUs
- Device passthrough: `/dev/dri`
- FFmpeg hardware encoder: `h264_vaapi`, `hevc_vaapi`
- Tone mapping: OpenCL-based (requires ROCm, experimental)

**Benefits:**
- Hardware-accelerated video thumbnail generation
- Faster video transcoding for web playback
- Lower CPU usage during video processing

**Limitations:**
- AMD GPUs don't support VP9 encoding (fallback to CPU)
- Tone mapping on AMD is experimental (may use CPU fallback)

**Device Passthrough Configuration:**
```ini
# In Quadlet files:
Device=/dev/dri:/dev/dri  # AMD GPU render nodes

# Environment variables (if needed):
Environment=HSA_OVERRIDE_GFX_VERSION=10.3.0
Environment=HSA_USE_SVM=0
```

**Verification:**
```bash
# Check AMD GPU access inside container
podman exec immich-ml ls -la /dev/dri
# Expected: card0, renderD128, etc.

# Check ROCm detection
podman exec immich-ml rocm-smi
# Should show AMD GPU info
```

**Fallback Plan:** If ROCm issues arise, use CPU-only image (`release` tag) and accept slower ML inference. Video transcoding can still use VAAPI independently.

---

### 6. Authentication & Access Control

**Decision:** Two-phase authentication integration

**Phase 1 (Week 2): TinyAuth Forward Authentication**
- Traefik middleware: `crowdsec-bouncer → rate-limit → tinyauth`
- Access: `photos.patriark.org` requires TinyAuth login
- Immich internal auth: Disabled or single admin user
- Mobile apps: Use Immich API key (bypasses Traefik middleware)

**Phase 2 (Week 3): Migrate to Authelia SSO**
- Traefik middleware: `crowdsec-bouncer → rate-limit → authelia`
- Access: `photos.patriark.org` uses Authelia SSO with TOTP/YubiKey
- Immich internal auth: Still disabled (Authelia handles all auth)
- Mobile apps: Authelia supports OAuth2/OIDC (if Immich enables it)

**Rationale:**
- **Week 2 Priority:** Get Immich functional quickly with existing TinyAuth
- **Week 3 Enhancement:** Migrate entire homelab (Jellyfin, Grafana, Immich) to Authelia SSO
- **Security:** Forward auth ensures photos never exposed without authentication
- **Flexibility:** Immich internal auth remains available for direct access (emergency)

**Mobile App Access:**

During TinyAuth phase:
```yaml
# Traefik rule for API access (bypass auth for API keys)
immich-api:
  rule: Host(`photos.patriark.org`) && PathPrefix(`/api`)
  middlewares:
    - crowdsec-bouncer
    - rate-limit-api  # More restrictive for API
  # No TinyAuth middleware for API endpoints
```

After Authelia migration: Evaluate Authelia OAuth2 proxy for mobile apps.

---

### 7. Secrets Management

**Decision:** Podman secrets for all sensitive credentials

**Secrets Required:**
1. `postgres-password` - PostgreSQL superuser password
2. `redis-password` - Redis authentication (optional but recommended)
3. `immich-jwt-secret` - Immich session tokens
4. `immich-api-key` - Mobile app access

**Secret Creation:**
```bash
# Generate strong passwords
POSTGRES_PW=$(openssl rand -base64 32)
REDIS_PW=$(openssl rand -base64 32)
JWT_SECRET=$(openssl rand -base64 32)

# Create Podman secrets
echo -n "$POSTGRES_PW" | podman secret create postgres-password -
echo -n "$REDIS_PW" | podman secret create redis-password -
echo -n "$JWT_SECRET" | podman secret create immich-jwt-secret -
```

**Quadlet Secret Integration:**
```ini
[Container]
Secret=postgres-password,type=env,target=POSTGRES_PASSWORD
Secret=immich-jwt-secret,type=env,target=JWT_SECRET
```

**Rationale:**
- Secrets never in Git or Quadlet files
- Podman manages secret lifecycle
- Easy rotation (recreate secret, restart service)
- Aligns with existing infrastructure (TinyAuth, Redis already use secrets)

---

### 8. Service Dependencies

**Decision:** Explicit systemd dependency chains

**Startup Order:**
1. Networks (systemd-photos.network)
2. PostgreSQL (postgresql-immich.service)
3. Redis (redis-immich.service)
4. Immich Server (immich-server.service) - Depends on PostgreSQL + Redis
5. Immich ML (immich-ml.service) - Can start independently

**Quadlet Dependency Example:**
```ini
# immich-server.container
[Unit]
Description=Immich Server
After=network-online.target postgresql-immich.service redis-immich.service
Requires=postgresql-immich.service redis-immich.service
Wants=immich-ml.service

[Container]
Image=ghcr.io/immich-app/immich-server:release
Network=systemd-photos.network
Network=systemd-reverse_proxy.network
Environment=DB_HOSTNAME=postgresql-immich
Environment=REDIS_HOSTNAME=redis-immich

[Install]
WantedBy=default.target
```

**Health Checks:**
- PostgreSQL: `pg_isready` check before Immich starts
- Redis: `redis-cli PING` check
- Immich Server: HTTP health endpoint `/api/server-info/ping`

**Rationale:**
- Prevents startup failures due to missing dependencies
- systemd handles restart logic if database crashes
- Clear service relationships for troubleshooting

---

### 9. Monitoring & Observability

**Decision:** Full Prometheus/Grafana integration from Day 1

**Metrics Export:**
- Immich Server: `/metrics` endpoint (Prometheus format)
- PostgreSQL: `postgres_exporter` sidecar container
- Redis: `redis_exporter` sidecar container
- GPU: `rocm_smi_exporter` for AMD GPU metrics

**Grafana Dashboards:**
1. **Immich Service Health**
   - API response times
   - Upload queue depth
   - ML job completion rate
   - Storage usage trends

2. **Database Performance**
   - PostgreSQL query latency
   - Connection pool utilization
   - Cache hit ratio

3. **Hardware Utilization**
   - AMD GPU memory usage (ROCm)
   - GPU compute utilization
   - Transcode queue

**Alerting:**
```yaml
# Alertmanager rules
- alert: ImmichDatabaseDown
  expr: up{job="postgresql-immich"} == 0
  for: 2m
  annotations:
    summary: "Immich PostgreSQL is down"

- alert: ImmichUploadQueueStuck
  expr: immich_upload_queue_depth > 100
  for: 10m
  annotations:
    summary: "Immich upload queue stuck"
```

**Rationale:**
- Monitoring infrastructure already exists (Prometheus, Grafana, Alertmanager)
- Early visibility into performance and issues
- Learning: Understand database and GPU metrics

---

### 10. Upgrade Strategy

**Decision:** Blue-green deployment with data persistence

**Approach:**
1. **Data is persistent** - PostgreSQL, Redis, and photo storage on BTRFS volumes
2. **Containers are ephemeral** - Pull new images, recreate containers
3. **Quadlet files version-pinned** - `Image=ghcr.io/immich-app/immich-server:v1.120.0`

**Upgrade Process:**
```bash
# 1. Backup database before upgrade
podman exec postgresql-immich pg_dump -U immich > immich-backup-$(date +%Y%m%d).sql

# 2. Update Quadlet files with new version
sed -i 's/:v1.120.0/:v1.121.0/' ~/.config/containers/systemd/immich-*.container

# 3. Reload and restart services
systemctl --user daemon-reload
systemctl --user restart immich-server.service
systemctl --user restart immich-ml.service

# 4. Verify health
curl https://photos.patriark.org/api/server-info/ping
```

**Rollback:**
```bash
# Revert Quadlet files to old version
sed -i 's/:v1.121.0/:v1.120.0/' ~/.config/containers/systemd/immich-*.container

# Restart with old version
systemctl --user daemon-reload
systemctl --user restart immich-server.service
```

**Rationale:**
- No downtime for database (data persists across container recreations)
- Easy rollback by reverting image tags
- Aligns with existing Jellyfin upgrade pattern

---

## Consequences

### Positive

- ✅ **Reusable database pattern** - PostgreSQL + Redis deployment applies to Nextcloud, Paperless, etc.
- ✅ **Production-grade reliability** - systemd supervision, health checks, dependency management
- ✅ **Security by design** - Network isolation, forward auth, secrets management
- ✅ **Hardware efficiency** - GPU acceleration for ML and transcoding
- ✅ **Excellent learning outcomes** - Microservices, databases, networking, GPU passthrough
- ✅ **Scalable foundation** - Can add services to systemd-photos network easily

### Negative

- ⚠️ **Higher complexity** - 4 containers vs 1 monolithic, more moving parts
- ⚠️ **Longer initial setup** - Manual Quadlet creation vs docker-compose up
- ⚠️ **ROCm disk space** - ML image requires 35GB (monitor system SSD)
- ⚠️ **AMD GPU limitations** - No VP9 encoding, tone mapping experimental

### Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| ROCm incompatibility with AMD GPU | ML runs on CPU (slow) | Verify GPU support, use `HSA_OVERRIDE_GFX_VERSION`, fallback to CPU image |
| System SSD fills up (52% → 90%) | Service failures | Monitor with Grafana, alert at 80%, move ML cache to BTRFS if needed |
| PostgreSQL performance issues | Slow UI, upload delays | NOCOW attribute, tune `shared_buffers`, monitor with postgres_exporter |
| Photo library grows to 500GB+ | Storage pressure | Monitor growth, plan external archive, implement Immich storage quota |
| Immich breaking changes in update | Service outage | Pin versions in Quadlet, test upgrades in dev first, backup before upgrade |

---

## Implementation Plan

### Week 2 Day 1-2: Database Layer (4-6 hours)

1. Create `systemd-photos` network
2. Deploy PostgreSQL container with Quadlet
3. Deploy Redis container with Quadlet
4. Create Podman secrets (passwords, JWT)
5. Test database connectivity
6. Configure BTRFS subvolumes (subvol8-photos, NOCOW for DB)
7. Add PostgreSQL to backup automation

### Week 2 Day 3-4: Immich Core (4-6 hours)

1. Deploy immich-server container
2. Deploy immich-ml container (CPU-only first, then ROCm)
3. Configure Traefik routing (`photos.patriark.org`)
4. Integrate TinyAuth middleware
5. Test upload and basic functionality
6. Configure GPU passthrough and test

### Week 2 Day 5: Monitoring & Polish (2-3 hours)

1. Configure Prometheus scraping
2. Create Grafana dashboard
3. Set up Alertmanager rules
4. Test health checks and restarts
5. Document deployment in operation guide

### Week 3: Authelia Migration (Week 3 tasks)

1. Complete Authelia deployment
2. Migrate Immich to Authelia forward auth
3. Configure mobile app access (API keys or OAuth2)
4. Security review

---

## Alternative Decisions Rejected

### Pod-based deployment (4 containers in 1 pod)

**Why rejected:**
- Pods share network namespace (all containers on 127.0.0.1)
- Harder to monitor individual services
- Restart/upgrade affects entire pod
- Doesn't align with existing infrastructure (separate services)
- Less flexibility for future scaling

### Shared PostgreSQL instance

**Why rejected (for now):**
- Version coupling (all services must use same PostgreSQL version)
- Harder to troubleshoot (multiple databases in one instance)
- Backup complexity (need per-database backup scripts)
- Better to learn dedicated deployment first, re-evaluate after 3+ services

### Nginx Proxy Manager instead of Traefik

**Why rejected:**
- Already invested in Traefik infrastructure
- Traefik forward auth works well with TinyAuth/Authelia
- NPM doesn't integrate as cleanly with Podman service discovery
- No compelling reason to switch

---

## References

### Official Documentation
- Immich GitHub: https://github.com/immich-app/immich
- Immich Docker Compose: https://github.com/immich-app/immich/blob/main/docker/docker-compose.yml
- PostgreSQL Extensions: pgvecto.rs, vectorchord

### Community Resources
- Podman Quadlets: https://github.com/jbtrystram/immich-podman-systemd
- AMD GPU ROCm: https://immich.app/docs/features/ml-hardware-acceleration/
- VAAPI Transcoding: https://immich.app/docs/features/hardware-transcoding/

### Homelab Documentation
- Journey Guide: `docs/10-services/journal/20251107-immich-deployment-journey.md`
- Roadmap: `docs/99-reports/20251107-roadmap-proposals.md`
- Backup Strategy: `docs/20-operations/guides/backup-strategy.md`
- Network Architecture: `docs/00-foundation/guides/network-architecture.md`

---

## Review and Approval

**Prepared by:** Claude Code
**Reviewed by:** patriark
**Approval Date:** 2025-11-08 (pending)
**Status:** Proposed → Under Review

**Next Steps:**
1. Review this ADR and approve or request changes
2. Proceed to Day 4: Detailed network topology diagram and storage planning
3. Begin Week 2 implementation

---

**Document Status:** Architecture Decision Record (ADR)
**Immutability:** Once approved, this ADR is immutable. Future changes require new ADR referencing this one.
