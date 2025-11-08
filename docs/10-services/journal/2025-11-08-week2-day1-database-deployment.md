# Week 2 Day 1: Database Infrastructure Deployment

**Date:** 2025-11-08
**Task:** Deploy PostgreSQL and Redis for Immich
**Status:** ✅ Complete
**Duration:** ~1.5 hours (planned 2-3 hours)

---

## What Was Done

### Phase 1: Network Setup (15 minutes) ✅

**Created systemd-photos network Quadlet:**
- File: `~/.config/containers/systemd/photos.network`
- Subnet: 10.89.5.0/24
- Gateway: 10.89.5.1
- DNS: 192.168.1.69

**Key Learning:** Network Quadlet files follow the pattern:
- Filename: `photos.network`
- Generated service: `photos-network.service`
- Podman network: `systemd-photos`
- Dependencies in other Quadlets: `Requires=photos-network.service`

**Verification:**
```bash
podman network ls | grep systemd-photos
# Result: systemd-photos network active
```

---

### Phase 2: Storage Setup (20 minutes) ✅

**Storage structure created on BTRFS pool:**

```
/mnt/btrfs-pool/
├── subvol3-opptak/immich/           # Photo library (existing subvolume, COW enabled)
│   ├── library/                     # Original photos/videos
│   ├── thumbs/                      # Generated thumbnails
│   └── encoded-video/               # Transcoded videos
│
└── subvol7-containers/
    ├── postgresql-immich/           # PostgreSQL data (NOCOW for performance)
    ├── redis-immich/                # Redis persistence (NOCOW)
    └── immich-ml-cache/             # ML model cache (20GB, COW)
```

**Key Decisions:**
- ✅ **Used existing subvol3-opptak** instead of creating new subvol8-photos
- ✅ **All data on BTRFS pool** (not system SSD) to avoid space pressure
- ✅ **NOCOW applied to database directories** for write performance
- ✅ **Photo library keeps COW** for BTRFS snapshot protection

**NOCOW Verification:**
```bash
lsattr -d /mnt/btrfs-pool/subvol7-containers/postgresql-immich
# Result: ---------------C-- (NOCOW enabled)

lsattr -d /mnt/btrfs-pool/subvol7-containers/redis-immich
# Result: ---------------C-- (NOCOW enabled)
```

**Why NOCOW for databases?**
- PostgreSQL performs many random writes (index updates, WAL)
- BTRFS COW doubles write amplification
- NOCOW eliminates snapshot overhead
- Trade-off: We backup via `pg_dump` instead of relying on BTRFS snapshots

---

### Phase 3: Secrets Creation (15 minutes) ✅

**Created three Podman secrets:**
1. `postgres-password` - PostgreSQL database authentication
2. `redis-password` - Redis authentication (for future use)
3. `immich-jwt-secret` - Immich session token signing

**Generated with:**
```bash
openssl rand -base64 32  # Strong 256-bit passwords
```

**Secrets stored securely:**
- Podman secret store: `~/.local/share/containers/storage/secrets/`
- User password manager: Encrypted backup
- **Never in Git or plain text files**

**Note:** Discovered duplicate `redis_password` (underscore) from old Authelia attempt. New Immich secret uses `redis-password` (hyphen), so no conflict. Cleanup can happen later.

**Verification:**
```bash
podman secret ls
# Result: 3 new secrets created successfully
```

---

### Phase 4: PostgreSQL Deployment (45 minutes) ✅

**Created PostgreSQL Quadlet:**
- File: `~/.config/containers/systemd/postgresql-immich.container`
- Image: `ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0`
- Network: `systemd-photos`
- Storage: `/mnt/btrfs-pool/subvol7-containers/postgresql-immich` (NOCOW)

**Configuration:**
```ini
Environment=POSTGRES_USER=immich
Environment=POSTGRES_DB=immich
Secret=postgres-password,type=env,target=POSTGRES_PASSWORD
Environment=POSTGRES_INITDB_ARGS=--data-checksums
PodmanArgs=--shm-size=128m
```

**Key Learning - Network Dependencies:**
Initial Quadlet used incorrect syntax:
```ini
# ❌ Wrong:
After=systemd-photos-network.service
Network=systemd-photos.network

# ✅ Correct:
After=photos-network.service
Requires=photos-network.service
Network=systemd-photos
```

Pattern: `<filename>.network` → `<filename>-network.service` (systemd generator conversion)

**First Start Behavior:**
- Database initialization took ~60 seconds
- Created `immich` database automatically
- Several `FATAL: database "immich" does not exist` messages during init (NORMAL - happens before DB creation)
- Vector extensions (vectorchord, pgvectors) built into image, will activate when Immich runs migrations

**Verification:**
```bash
systemctl --user status postgresql-immich.service
# Result: active (running)

podman healthcheck run postgresql-immich
# Result: healthy (no output = success)

podman exec postgresql-immich psql -U immich -c '\l'
# Result: immich database listed
```

**Resource Usage:**
- Memory: ~930MB (peak: 983MB)
- CPU: 10.7s initialization
- Storage: ~50MB (empty database)

---

### Phase 5: Redis Deployment (30 minutes) ✅

**Created Redis Quadlet:**
- File: `~/.config/containers/systemd/redis-immich.container`
- Image: `docker.io/valkey/valkey:8` (Redis fork, official Immich recommendation)
- Network: `systemd-photos`
- Storage: `/mnt/btrfs-pool/subvol7-containers/redis-immich` (NOCOW, persistent)

**Configuration:**
```ini
HealthCmd=valkey-cli ping
HealthInterval=10s
Volume=/mnt/btrfs-pool/subvol7-containers/redis-immich:/data:Z
```

**Warnings Observed (informational, not errors):**

1. **Memory overcommit warning:**
   - Redis wants `vm.overcommit_memory=1` for background saves
   - Impact: Minimal for Immich (cache/job queue usage, not heavy persistence)
   - Optional fix: `sudo sysctl vm.overcommit_memory=1` (can do later)

2. **No config file warning:**
   - Using Redis defaults (no custom valkey.conf)
   - Impact: None - defaults are appropriate for cache use case

**Verification:**
```bash
systemctl --user status redis-immich.service
# Result: active (running)

podman healthcheck run redis-immich
# Result: healthy

podman exec redis-immich valkey-cli ping
# Result: PONG
```

**Resource Usage:**
- Memory: ~130MB (peak: 227MB)
- CPU: 2.2s initialization
- Storage: Minimal (empty cache)

---

### Phase 6: Enable Auto-Start (5 minutes) ✅

**Attempted traditional systemctl enable:**
```bash
systemctl --user enable postgresql-immich.service
# Error: Unit is transient or generated
```

**Key Learning - Quadlet Auto-Start:**
- Quadlet-generated services are **transient** (created dynamically)
- Cannot use `systemctl enable` on them
- Auto-start is controlled by `[Install]` section in Quadlet file:
  ```ini
  [Install]
  WantedBy=default.target
  ```
- Both Quadlet files already have this → **auto-start already configured** ✅

**This is expected and correct behavior for Quadlets.**

---

## Results Summary

### Services Deployed

| Service | Status | Memory | Storage | Network |
|---------|--------|--------|---------|---------|
| **postgresql-immich** | ✅ Running | 930MB | 50MB | systemd-photos |
| **redis-immich** | ✅ Running | 130MB | <10MB | systemd-photos |
| **systemd-photos network** | ✅ Active | - | - | 10.89.5.0/24 |

**Total resource usage:** ~1.1GB RAM, ~60MB disk (will grow with data)

---

### Storage Layout Final

```
BTRFS Pool: /mnt/btrfs-pool/
├── subvol3-opptak/immich/           0 GB (empty, ready for photos)
├── postgresql-immich/               50 MB (database initialized)
├── redis-immich/                    <10 MB (cache empty)
└── immich-ml-cache/                 0 GB (models download on Day 2)
```

**System SSD:** Still at ~52% (no additional load - all Immich data on BTRFS) ✅

---

## Issues Encountered & Resolved

### Issue 1: Quadlet Network Reference Syntax

**Problem:** Service failed to start with "Unit not found"

**Root Cause:** Incorrect network reference in Quadlet:
```ini
# Wrong:
Network=systemd-photos.network
After=systemd-photos-network.service

# Correct:
Network=systemd-photos
After=photos-network.service
```

**Resolution:** Quadlet generator converts `photos.network` file → `photos-network.service` (not `systemd-photos-network.service`)

**Learning:** Always reference the **filename** (without extension) for dependencies, and **network name** for Network= directive.

---

### Issue 2: Duplicate redis-password Secret

**Problem:** Found existing `redis_password` (underscore) from old Authelia deployment

**Impact:** None - new Immich secret uses `redis-password` (hyphen), different name

**Resolution:** Noted for future cleanup after Immich is confirmed working

---

### Issue 3: PostgreSQL "FATAL: database immich does not exist" Messages

**Problem:** Scary-looking error messages during first start

**Root Cause:** Initialization script checks for database before creating it

**Resolution:** This is **expected behavior** during first-time setup. Database was created successfully.

**Learning:** Don't panic at init messages - verify final state instead.

---

### Issue 4: Cannot Enable Quadlet Services

**Problem:** `systemctl --user enable` returns "Unit is transient or generated"

**Root Cause:** Quadlet services are generated dynamically, not static files

**Resolution:** `[Install] WantedBy=default.target` in Quadlet file already handles auto-start

**Learning:** Quadlets work differently than traditional systemd units - this error is expected and correct.

---

## Configuration Files Created

### 1. photos.network
**Location:** `~/.config/containers/systemd/photos.network`
```ini
[Unit]
Description=Photos Service Network

[Network]
Subnet=10.89.5.0/24
Gateway=10.89.5.1
DNS=192.168.1.69

[Install]
WantedBy=default.target
```

---

### 2. postgresql-immich.container
**Location:** `~/.config/containers/systemd/postgresql-immich.container`
```ini
[Unit]
Description=PostgreSQL for Immich
After=network-online.target photos-network.service
Wants=network-online.target
Requires=photos-network.service

[Container]
Image=ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0
ContainerName=postgresql-immich
AutoUpdate=registry

Network=systemd-photos

Environment=POSTGRES_USER=immich
Environment=POSTGRES_DB=immich
Secret=postgres-password,type=env,target=POSTGRES_PASSWORD
Environment=POSTGRES_INITDB_ARGS=--data-checksums

Volume=/mnt/btrfs-pool/subvol7-containers/postgresql-immich:/var/lib/postgresql/data:Z

PodmanArgs=--shm-size=128m

HealthCmd=pg_isready -U immich -d immich
HealthInterval=10s
HealthTimeout=5s
HealthRetries=5

[Service]
Restart=always
TimeoutStartSec=900

[Install]
WantedBy=default.target
```

---

### 3. redis-immich.container
**Location:** `~/.config/containers/systemd/redis-immich.container`
```ini
[Unit]
Description=Redis for Immich
After=network-online.target photos-network.service
Wants=network-online.target
Requires=photos-network.service

[Container]
Image=docker.io/valkey/valkey:8
ContainerName=redis-immich
AutoUpdate=registry

Network=systemd-photos

Volume=/mnt/btrfs-pool/subvol7-containers/redis-immich:/data:Z

HealthCmd=valkey-cli ping
HealthInterval=10s
HealthTimeout=5s
HealthRetries=5

[Service]
Restart=always
TimeoutStartSec=300

[Install]
WantedBy=default.target
```

---

## Verification Commands

### Check All Services

```bash
# Status
systemctl --user status postgresql-immich.service redis-immich.service

# Health checks
podman healthcheck run postgresql-immich
podman healthcheck run redis-immich

# Container list
podman ps | grep -E 'postgresql-immich|redis-immich'
```

### Test Database Connectivity

```bash
# PostgreSQL
podman exec postgresql-immich psql -U immich -c '\l'
podman exec postgresql-immich psql -U immich -d immich -c 'SELECT version();'

# Redis
podman exec redis-immich valkey-cli ping
podman exec redis-immich valkey-cli INFO server
```

### Check Network

```bash
# List networks
podman network ls

# Inspect photos network
podman network inspect systemd-photos

# Verify containers on network
podman network inspect systemd-photos | jq '.[].containers'
```

### Monitor Resources

```bash
# Real-time stats
podman stats --no-stream postgresql-immich redis-immich

# Storage usage
du -sh /mnt/btrfs-pool/subvol7-containers/postgresql-immich
du -sh /mnt/btrfs-pool/subvol7-containers/redis-immich
```

---

## Learning Outcomes

### Technical Skills Acquired

- ✅ Quadlet network creation and dependency management
- ✅ Podman secrets for secure credential storage
- ✅ PostgreSQL deployment with vector extensions
- ✅ Redis/Valkey cache deployment
- ✅ BTRFS NOCOW attribute for database optimization
- ✅ Multi-network container architecture patterns
- ✅ Quadlet auto-start configuration (`[Install]` section)
- ✅ Health check implementation and verification

### Key Insights

1. **Quadlet naming matters:** Filename `photos.network` becomes service `photos-network.service`, not `systemd-photos-network.service`

2. **Network references are dual:**
   - Dependency: `Requires=photos-network.service` (service name)
   - Connection: `Network=systemd-photos` (network name)

3. **NOCOW is critical for databases:** Write amplification would hurt PostgreSQL performance on COW filesystem

4. **Secrets are isolated:** Podman secrets with similar names (`redis_password` vs `redis-password`) don't conflict

5. **Quadlets auto-enable differently:** `[Install] WantedBy=default.target` replaces `systemctl enable`

6. **First-start messages can be misleading:** PostgreSQL init errors are normal, verify final state

7. **Storage placement matters:** All Immich data on BTRFS pool prevents system SSD pressure

### Confidence Gained

- ✅ Database layer is solid and ready for Immich Server
- ✅ Network isolation working as designed
- ✅ Storage strategy optimized (NOCOW + COW where appropriate)
- ✅ Quadlet pattern mastered (can apply to future services)
- ✅ Secrets management secure and repeatable
- ✅ Ready for Week 2 Day 2: Immich Server deployment

---

## Time Investment

- **Planned:** 2-3 hours
- **Actual:** ~1.5 hours
- **Efficiency:** ✅ Excellent (better than expected)

**Breakdown:**
- Phase 1 (Network): 15 min
- Phase 2 (Storage): 20 min
- Phase 3 (Secrets): 15 min
- Phase 4 (PostgreSQL): 45 min (including troubleshooting)
- Phase 5 (Redis): 30 min
- Phase 6 (Auto-start): 5 min

---

## Next Steps

### Immediate (Week 2 Day 2)

**Deploy Immich Server and ML containers:**

1. Create Immich Server Quadlet
   - Multi-network: systemd-photos, systemd-reverse_proxy, systemd-monitoring
   - Environment: DB and Redis connection strings
   - Storage: Mount subvol3-opptak/immich for photo library
   - Traefik labels for photos.patriark.org

2. Create Immich ML Quadlet (CPU-only first)
   - Network: systemd-photos only (isolated)
   - Storage: Mount immich-ml-cache for models
   - Wait for 15-20GB model download

3. Traefik Integration
   - Verify routing to photos.patriark.org
   - Test TinyAuth middleware
   - Complete Immich setup wizard

4. Basic functionality test
   - Upload test photos
   - Verify thumbnail generation
   - Check ML inference (may be slow on CPU)

**Estimated time:** 2-3 hours

---

### Week 2 Remaining Days

- **Day 3:** GPU acceleration (AMD ROCm for ML inference)
- **Day 4:** Monitoring integration (Prometheus + Grafana)
- **Day 5:** Backup integration (add to BTRFS automation)
- **Day 6-7:** Testing, optimization, documentation

---

## System State

### Services Running

**Immich Stack (partial):**
- ✅ postgresql-immich (database ready)
- ✅ redis-immich (cache ready)
- ⏳ immich-server (Day 2)
- ⏳ immich-ml (Day 2)

**Existing Infrastructure:**
- ✅ Traefik + CrowdSec
- ✅ Jellyfin
- ✅ TinyAuth
- ✅ Prometheus + Grafana + Loki + Alertmanager

### Resource Usage

**Current:**
- System SSD: 52% (no change from Day 1 start)
- BTRFS Pool: ~60MB added (PostgreSQL + Redis)
- Memory: +1.1GB (database containers)

**Projected after Day 2:**
- System SSD: 52% (still no change - all data on BTRFS)
- BTRFS Pool: +20GB (ML model cache)
- Memory: +1.5GB (Immich server + ML containers)

**Total projected:** System SSD still at ~52%, BTRFS has plenty of headroom

---

## Success Criteria: ✅ All Met

- ✅ systemd-photos network created and functional
- ✅ PostgreSQL running, healthy, database initialized
- ✅ Redis running, healthy, responding to commands
- ✅ Secrets created and secured
- ✅ Storage optimized (NOCOW for databases, COW for photos)
- ✅ Services configured for auto-start on boot
- ✅ All services on correct network (systemd-photos)
- ✅ System SSD usage unchanged (all data on BTRFS)

**Status:** Database infrastructure complete, ready for Immich Server deployment

---

## References

- ADR: `docs/10-services/decisions/2025-11-08-immich-deployment-architecture.md`
- Storage Planning: `docs/10-services/journal/2025-11-08-immich-network-and-storage-planning.md`
- Deployment Checklist: `docs/10-services/guides/immich-deployment-checklist.md`
- Journey Guide: `docs/10-services/journal/20251107-immich-deployment-journey.md` (Week 2 Day 1)

---

**Prepared by:** Claude Code & patriark
**Journey:** Week 2 Day 1 of Immich Deployment (Proposal C)
**Status:** ✅ Day 1 Complete - Ready for Day 2 (Immich Server Deployment)
