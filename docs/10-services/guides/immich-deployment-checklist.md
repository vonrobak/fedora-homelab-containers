# Immich Deployment Checklist

**Purpose:** Step-by-step checklist for deploying Immich photo management service
**Reference:** ADR `docs/10-services/decisions/2025-11-08-immich-deployment-architecture.md`
**Timeline:** Week 2 (4-6 hours total)
**Status:** Historical deployment record (November 2025)

**Note:** This checklist references TinyAuth, which was later replaced by Authelia (ADR-006, 2025-11-11). The deployment steps remain valid; substitute "authelia@file" for "tinyauth@file" in middleware configurations.

---

## Pre-Deployment Verification

### System Health Check

- [ ] **Backup system active:** `systemctl --user list-timers | grep btrfs-backup`
- [ ] **System SSD usage:** `df -h /` (should be <80%, currently ~52%)
- [ ] **BTRFS pool available:** `df -h /mnt/btrfs-pool` (need ~100GB free)
- [ ] **External backup drive:** Mounted at `/run/media/patriark/WD-18TB`
- [ ] **All existing services healthy:** `podman ps` (Traefik, Jellyfin, monitoring stack)

### Review Planning Documents

- [ ] Read ADR: `docs/10-services/decisions/2025-11-08-immich-deployment-architecture.md`
- [ ] Review network plan: `docs/10-services/journal/2025-11-08-immich-network-and-storage-planning.md`
- [ ] Review journey guide: `docs/10-services/journal/20251107-immich-deployment-journey.md` (Week 2 section)

---

## Week 2 Day 1: Database Infrastructure (2-3 hours)

### Phase 1: Network Setup (30 minutes)

- [ ] **Create systemd-photos network Quadlet**

  ```bash
  mkdir -p ~/.config/containers/systemd
  cat > ~/.config/containers/systemd/systemd-photos.network <<'EOF'
  [Network]
  Driver=bridge
  Subnet=10.89.5.0/24
  Gateway=10.89.5.1
  Label=app=immich
  Label=network=photos

  [Install]
  WantedBy=default.target
  EOF
  ```

- [ ] **Reload systemd and start network**

  ```bash
  systemctl --user daemon-reload
  systemctl --user start systemd-photos-network.service
  ```

- [ ] **Verify network created**

  ```bash
  podman network ls | grep systemd-photos
  podman network inspect systemd-photos
  ```

- [ ] **Test network connectivity**

  ```bash
  podman run -d --name test-photos --network systemd-photos alpine sleep 300
  podman exec test-photos ping -c 3 10.89.5.1
  podman rm -f test-photos
  ```

### Phase 2: Storage Setup (30 minutes)

- [ ] **Create BTRFS subvolume for photos**

  ```bash
  sudo btrfs subvolume create /mnt/btrfs-pool/subvol8-photos
  ```

- [ ] **Create directory structure**

  ```bash
  mkdir -p /mnt/btrfs-pool/subvol8-photos/{library,thumbs,encoded-video}
  ```

- [ ] **Set ownership for rootless Podman**

  ```bash
  sudo chown -R $(id -u):$(id -g) /mnt/btrfs-pool/subvol8-photos
  ```

- [ ] **Set SELinux context**

  ```bash
  sudo chcon -R -t container_file_t /mnt/btrfs-pool/subvol8-photos
  ```

- [ ] **Create PostgreSQL directory** (if not exists)

  ```bash
  mkdir -p /mnt/btrfs-pool/subvol7-containers/postgresql-immich
  sudo chown -R $(id -u):$(id -g) /mnt/btrfs-pool/subvol7-containers/postgresql-immich
  ```

- [ ] **Apply NOCOW to PostgreSQL directory**

  ```bash
  sudo chattr +C /mnt/btrfs-pool/subvol7-containers/postgresql-immich
  lsattr -d /mnt/btrfs-pool/subvol7-containers/postgresql-immich | grep 'C'
  # Expected: ---------------C--
  ```

- [ ] **Create Redis directory** (if not exists)

  ```bash
  mkdir -p /mnt/btrfs-pool/subvol7-containers/redis-immich
  sudo chown -R $(id -u):$(id -g) /mnt/btrfs-pool/subvol7-containers/redis-immich
  ```

- [ ] **Apply NOCOW to Redis directory**

  ```bash
  sudo chattr +C /mnt/btrfs-pool/subvol7-containers/redis-immich
  lsattr -d /mnt/btrfs-pool/subvol7-containers/redis-immich | grep 'C'
  ```

- [ ] **Verify storage setup**

  ```bash
  sudo btrfs subvolume list /mnt/btrfs-pool | grep subvol8-photos
  ls -la /mnt/btrfs-pool/subvol8-photos
  ```

### Phase 3: Secrets Creation (15 minutes)

- [ ] **Generate strong passwords**

  ```bash
  POSTGRES_PW=$(openssl rand -base64 32)
  REDIS_PW=$(openssl rand -base64 32)
  JWT_SECRET=$(openssl rand -base64 32)

  # Display for verification (DO NOT commit to Git)
  echo "PostgreSQL password: $POSTGRES_PW"
  echo "Redis password: $REDIS_PW"
  echo "JWT secret: $JWT_SECRET"
  ```

- [ ] **Create Podman secrets**

  ```bash
  echo -n "$POSTGRES_PW" | podman secret create postgres-password -
  echo -n "$REDIS_PW" | podman secret create redis-password -
  echo -n "$JWT_SECRET" | podman secret create immich-jwt-secret -
  ```

- [ ] **Verify secrets created**

  ```bash
  podman secret ls | grep -E 'postgres-password|redis-password|immich-jwt-secret'
  ```

- [ ] **Store backup of secrets securely** (NOT in Git)

  ```bash
  # Example: Use password manager or encrypted vault
  # DO NOT: echo "$POSTGRES_PW" > secrets.txt
  ```

### Phase 4: PostgreSQL Deployment (45 minutes)

- [ ] **Create PostgreSQL Quadlet file**

  ```bash
  cat > ~/.config/containers/systemd/postgresql-immich.container <<'EOF'
  [Unit]
  Description=PostgreSQL for Immich
  After=network-online.target systemd-photos-network.service
  Wants=network-online.target
  Requires=systemd-photos-network.service

  [Container]
  Image=ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0
  ContainerName=postgresql-immich
  AutoUpdate=registry

  # Network
  Network=systemd-photos.network

  # Environment
  Environment=POSTGRES_USER=immich
  Environment=POSTGRES_DB=immich
  Secret=postgres-password,type=env,target=POSTGRES_PASSWORD
  Environment=POSTGRES_INITDB_ARGS=--data-checksums

  # Storage
  Volume=/mnt/btrfs-pool/subvol7-containers/postgresql-immich:/var/lib/postgresql/data:Z

  # Resources
  ShmSize=128m

  # Health check
  HealthCmd=pg_isready -U immich -d immich
  HealthInterval=10s
  HealthTimeout=5s
  HealthRetries=5

  [Service]
  Restart=always
  TimeoutStartSec=900

  [Install]
  WantedBy=default.target
  EOF
  ```

- [ ] **Reload systemd and start PostgreSQL**

  ```bash
  systemctl --user daemon-reload
  systemctl --user start postgresql-immich.service
  ```

- [ ] **Check PostgreSQL status**

  ```bash
  systemctl --user status postgresql-immich.service
  podman ps | grep postgresql-immich
  ```

- [ ] **Verify PostgreSQL health**

  ```bash
  podman healthcheck run postgresql-immich
  # Expected: healthy
  ```

- [ ] **Test database connection**

  ```bash
  podman exec postgresql-immich psql -U immich -c '\l'
  # Should list immich database
  ```

- [ ] **Verify pgvecto.rs extension available**

  ```bash
  podman exec postgresql-immich psql -U immich -d immich -c 'CREATE EXTENSION IF NOT EXISTS vectorchord;'
  podman exec postgresql-immich psql -U immich -d immich -c '\dx'
  # Should show vectorchord extension
  ```

### Phase 5: Redis Deployment (30 minutes)

- [ ] **Create Redis Quadlet file**

  ```bash
  cat > ~/.config/containers/systemd/redis-immich.container <<'EOF'
  [Unit]
  Description=Redis for Immich
  After=network-online.target systemd-photos-network.service
  Wants=network-online.target
  Requires=systemd-photos-network.service

  [Container]
  Image=docker.io/valkey/valkey:8
  ContainerName=redis-immich
  AutoUpdate=registry

  # Network
  Network=systemd-photos.network

  # Storage (optional persistence)
  Volume=/mnt/btrfs-pool/subvol7-containers/redis-immich:/data:Z

  # Health check
  HealthCmd=valkey-cli ping
  HealthInterval=10s
  HealthTimeout=5s
  HealthRetries=5

  [Service]
  Restart=always
  TimeoutStartSec=300

  [Install]
  WantedBy=default.target
  EOF
  ```

- [ ] **Reload systemd and start Redis**

  ```bash
  systemctl --user daemon-reload
  systemctl --user start redis-immich.service
  ```

- [ ] **Check Redis status**

  ```bash
  systemctl --user status redis-immich.service
  podman ps | grep redis-immich
  ```

- [ ] **Verify Redis health**

  ```bash
  podman healthcheck run redis-immich
  # Expected: healthy
  ```

- [ ] **Test Redis connection**

  ```bash
  podman exec redis-immich valkey-cli ping
  # Expected: PONG
  ```

### Phase 6: Enable Services (10 minutes)

- [ ] **Enable PostgreSQL to start on boot**

  ```bash
  systemctl --user enable postgresql-immich.service
  ```

- [ ] **Enable Redis to start on boot**

  ```bash
  systemctl --user enable redis-immich.service
  ```

- [ ] **Verify enabled**

  ```bash
  systemctl --user list-unit-files | grep -E 'postgresql-immich|redis-immich'
  ```

---

## Week 2 Day 2: Immich Server (2-3 hours)

### Phase 1: ML Model Cache Setup (15 minutes)

- [ ] **Create ML cache directory on system SSD**

  ```bash
  mkdir -p ~/containers/config/immich/machine-learning
  ```

- [ ] **Check available SSD space**

  ```bash
  df -h / | grep nvme
  # Need ~25GB free for ML models
  ```

### Phase 2: Immich Server Deployment (60 minutes)

- [ ] **Create Immich Server Quadlet file**

  ```bash
  cat > ~/.config/containers/systemd/immich-server.container <<'EOF'
  [Unit]
  Description=Immich Server
  After=network-online.target postgresql-immich.service redis-immich.service
  Wants=network-online.target
  Requires=postgresql-immich.service redis-immich.service

  [Container]
  Image=ghcr.io/immich-app/immich-server:release
  ContainerName=immich-server
  AutoUpdate=registry

  # Networks
  Network=systemd-photos.network
  Network=systemd-reverse_proxy.network
  Network=systemd-monitoring.network

  # Environment - Database
  Environment=DB_HOSTNAME=postgresql-immich
  Environment=DB_USERNAME=immich
  Environment=DB_DATABASE_NAME=immich
  Secret=postgres-password,type=env,target=DB_PASSWORD

  # Environment - Redis
  Environment=REDIS_HOSTNAME=redis-immich
  Environment=REDIS_PORT=6379

  # Environment - ML
  Environment=IMMICH_MACHINE_LEARNING_URL=http://immich-ml:3003

  # Environment - Security
  Secret=immich-jwt-secret,type=env,target=JWT_SECRET

  # Environment - Upload
  Environment=UPLOAD_LOCATION=/usr/src/app/upload

  # Storage
  Volume=/mnt/btrfs-pool/subvol8-photos:/usr/src/app/upload:Z

  # Expose port for Traefik
  PublishPort=2283:2283

  # Traefik labels
  Label=traefik.enable=true
  Label=traefik.http.routers.immich.rule=Host(\`photos.patriark.org\`)
  Label=traefik.http.routers.immich.entrypoints=websecure
  Label=traefik.http.routers.immich.tls=true
  Label=traefik.http.routers.immich.middlewares=crowdsec-bouncer@file,rate-limit@file,tinyauth@file
  Label=traefik.http.services.immich.loadbalancer.server.port=2283

  # Health check
  HealthCmd=curl -f http://localhost:2283/api/server-info/ping || exit 1
  HealthInterval=30s
  HealthTimeout=10s
  HealthRetries=3

  [Service]
  Restart=always
  TimeoutStartSec=900

  [Install]
  WantedBy=default.target
  EOF
  ```

- [ ] **Reload systemd and start Immich Server**

  ```bash
  systemctl --user daemon-reload
  systemctl --user start immich-server.service
  ```

- [ ] **Check Immich Server status**

  ```bash
  systemctl --user status immich-server.service
  podman ps | grep immich-server
  ```

- [ ] **Check logs for errors**

  ```bash
  podman logs immich-server --tail 50
  ```

- [ ] **Wait for database migration to complete** (first startup takes 2-5 minutes)

  ```bash
  podman logs immich-server -f
  # Watch for: "Database migration completed"
  ```

- [ ] **Verify health**

  ```bash
  podman healthcheck run immich-server
  # Expected: healthy (may take 2-3 minutes after first start)
  ```

### Phase 3: Immich Machine Learning (CPU-only first) (45 minutes)

- [ ] **Create Immich ML Quadlet file (CPU-only)**

  ```bash
  cat > ~/.config/containers/systemd/immich-ml.container <<'EOF'
  [Unit]
  Description=Immich Machine Learning
  After=network-online.target systemd-photos-network.service
  Wants=network-online.target
  Requires=systemd-photos-network.service

  [Container]
  Image=ghcr.io/immich-app/immich-machine-learning:release
  ContainerName=immich-ml
  AutoUpdate=registry

  # Network
  Network=systemd-photos.network

  # Storage - ML model cache
  Volume=/home/patriark/containers/config/immich/machine-learning:/cache:Z

  # Environment
  Environment=MACHINE_LEARNING_CACHE_FOLDER=/cache

  # Health check
  HealthCmd=curl -f http://localhost:3003/ping || exit 1
  HealthInterval=30s
  HealthTimeout=10s
  HealthRetries=3

  [Service]
  Restart=always
  TimeoutStartSec=900

  [Install]
  WantedBy=default.target
  EOF
  ```

- [ ] **Reload systemd and start Immich ML**

  ```bash
  systemctl --user daemon-reload
  systemctl --user start immich-ml.service
  ```

- [ ] **Check Immich ML status**

  ```bash
  systemctl --user status immich-ml.service
  podman ps | grep immich-ml
  ```

- [ ] **Monitor ML model download** (first start takes 10-20 minutes)

  ```bash
  podman logs immich-ml -f
  # Watch for model downloads (CLIP, face detection, etc.)
  ```

- [ ] **Check ML cache size**

  ```bash
  du -sh ~/containers/config/immich/machine-learning
  # Expected: 15-20GB after models downloaded
  ```

- [ ] **Verify health**

  ```bash
  podman healthcheck run immich-ml
  # Expected: healthy
  ```

### Phase 4: Enable Immich Services (5 minutes)

- [ ] **Enable Immich Server to start on boot**

  ```bash
  systemctl --user enable immich-server.service
  ```

- [ ] **Enable Immich ML to start on boot**

  ```bash
  systemctl --user enable immich-ml.service
  ```

- [ ] **Verify all Immich services enabled**

  ```bash
  systemctl --user list-unit-files | grep immich
  ```

### Phase 5: Traefik Integration Test (30 minutes)

- [ ] **Verify Traefik detects Immich**

  ```bash
  podman logs traefik --tail 100 | grep immich
  # Look for: "Creating router immich"
  ```

- [ ] **Access Traefik dashboard**

  - Open: https://traefik.patriark.org
  - Navigate to HTTP → Routers
  - Verify: immich router exists with rule `Host(photos.patriark.org)`

- [ ] **Test external access** (from another device on network)

  ```bash
  curl -k https://photos.patriark.org
  # Should redirect to Immich web UI or TinyAuth login
  ```

- [ ] **Test authentication**

  - Open: https://photos.patriark.org
  - Expected: Redirected to TinyAuth login
  - Login with TinyAuth credentials
  - Expected: Access to Immich setup wizard

- [ ] **Complete Immich setup wizard**

  - Create admin account
  - Configure storage settings (defaults OK)
  - Enable ML features
  - Skip mobile app setup (for now)

---

## Week 2 Day 3: GPU Acceleration (Optional - 1-2 hours)

### AMD GPU ROCm Setup

- [ ] **Verify AMD GPU available**

  ```bash
  ls -la /dev/dri
  # Expected: card0, renderD128
  ```

- [ ] **Stop Immich ML service**

  ```bash
  systemctl --user stop immich-ml.service
  ```

- [ ] **Update Immich ML Quadlet for ROCm**

  ```bash
  # Edit ~/.config/containers/systemd/immich-ml.container
  # Change Image line:
  Image=ghcr.io/immich-app/immich-machine-learning:release-rocm

  # Add device passthrough:
  Device=/dev/dri:/dev/dri

  # Add environment (if needed for GPU compatibility):
  Environment=HSA_OVERRIDE_GFX_VERSION=10.3.0
  ```

- [ ] **Reload and restart ML service**

  ```bash
  systemctl --user daemon-reload
  systemctl --user start immich-ml.service
  ```

- [ ] **Monitor ROCm initialization**

  ```bash
  podman logs immich-ml -f
  # Look for ROCm/GPU detection messages
  ```

- [ ] **Verify GPU access inside container**

  ```bash
  podman exec immich-ml ls -la /dev/dri
  # Expected: card0, renderD128
  ```

- [ ] **Test GPU acceleration** (upload test photo and check inference speed)

  - Upload a photo via web UI
  - Check logs: `podman logs immich-ml -f`
  - Look for GPU usage or inference time

- [ ] **If ROCm fails:** Revert to CPU-only image

  ```bash
  # Edit Quadlet: Image=ghcr.io/immich-app/immich-machine-learning:release
  systemctl --user daemon-reload
  systemctl --user restart immich-ml.service
  ```

---

## Week 2 Day 4: Monitoring Integration (1-2 hours)

### Prometheus Configuration

- [ ] **Add Immich metrics scrape job**

  Edit `~/containers/config/prometheus/prometheus.yml`:

  ```yaml
  scrape_configs:
    - job_name: 'immich'
      static_configs:
        - targets: ['immich-server:2283']
      metrics_path: '/metrics'
      scrape_interval: 30s
  ```

- [ ] **Reload Prometheus**

  ```bash
  # If using systemd service:
  systemctl --user restart prometheus.service

  # OR send SIGHUP:
  podman kill -s SIGHUP prometheus
  ```

- [ ] **Verify Prometheus scraping Immich**

  - Open: http://prometheus.patriark.org (or local port)
  - Go to Status → Targets
  - Verify: immich target is UP

### Grafana Dashboard

- [ ] **Create Grafana dashboard: Immich Service Health**

  Panels to include:
  - API response time (histogram)
  - Upload queue depth (gauge)
  - ML job completion rate (counter)
  - Photo library size (gauge)
  - Database size (gauge)
  - System SSD usage (gauge with alert at 80%)

- [ ] **Import Immich community dashboard** (if available)

  - Search Grafana dashboards: https://grafana.com/grafana/dashboards/
  - Look for "Immich" dashboards
  - Import via JSON

### Alertmanager Rules

- [ ] **Add Immich alerting rules**

  Edit `~/containers/config/alertmanager/rules/immich.yml`:

  ```yaml
  groups:
    - name: immich
      interval: 30s
      rules:
        - alert: ImmichDatabaseDown
          expr: up{job="postgresql-immich"} == 0
          for: 2m
          annotations:
            summary: "Immich PostgreSQL is down"

        - alert: ImmichServerDown
          expr: up{job="immich"} == 0
          for: 2m
          annotations:
            summary: "Immich server is down"

        - alert: ImmichUploadQueueStuck
          expr: immich_upload_queue_depth > 100
          for: 10m
          annotations:
            summary: "Immich upload queue stuck (>100 items for 10min)"
  ```

- [ ] **Reload Alertmanager**

  ```bash
  systemctl --user restart alertmanager.service
  ```

- [ ] **Test alerts** (trigger manually or simulate)

---

## Week 2 Day 5: Backup Integration (1 hour)

### Backup Script Updates

- [ ] **Update BTRFS backup script**

  Edit `~/containers/scripts/btrfs-snapshot-backup.sh`:

  ```bash
  # Add Tier 1 entry for photos
  TIER1_PHOTOS_ENABLED=true
  TIER1_PHOTOS_SOURCE="/mnt/btrfs-pool/subvol8-photos"
  TIER1_PHOTOS_LOCAL_RETENTION_DAILY=7
  TIER1_PHOTOS_EXTERNAL_RETENTION_WEEKLY=8
  TIER1_PHOTOS_EXTERNAL_RETENTION_MONTHLY=12
  ```

- [ ] **Add PostgreSQL pg_dump to backup script**

  Add function to script:

  ```bash
  backup_immich_database() {
    local BACKUP_DIR="/mnt/btrfs-pool/subvol7-containers/postgresql-backups"
    mkdir -p "$BACKUP_DIR"

    podman exec postgresql-immich pg_dump -U immich immich \
      | gzip > "$BACKUP_DIR/immich-$(date +%Y%m%d).sql.gz"

    # Retention: keep 7 daily
    find "$BACKUP_DIR" -name "immich-*.sql.gz" -mtime +7 -delete
  }
  ```

- [ ] **Test manual backup**

  ```bash
  ~/containers/scripts/btrfs-snapshot-backup.sh --local-only --verbose
  ```

- [ ] **Verify snapshots created**

  ```bash
  ls -la /mnt/btrfs-pool/.snapshots/subvol8-photos/
  # Expected: Dated snapshots
  ```

- [ ] **Verify PostgreSQL backup**

  ```bash
  ls -la /mnt/btrfs-pool/subvol7-containers/postgresql-backups/
  # Expected: immich-YYYYMMDD.sql.gz
  ```

- [ ] **Test restore procedure** (dry-run)

  ```bash
  # Don't actually restore, just verify backup is readable
  zcat /mnt/btrfs-pool/subvol7-containers/postgresql-backups/immich-*.sql.gz | head -20
  # Expected: SQL dump header
  ```

---

## Week 2 Day 6-7: Testing & Documentation (2-3 hours)

### Functional Testing

- [ ] **Test photo upload** (web UI)

  - Upload 5-10 test photos
  - Verify thumbnails generated
  - Check photos appear in library

- [ ] **Test ML features**

  - Wait for face detection to complete
  - Verify faces detected and grouped
  - Test object recognition search

- [ ] **Test video upload**

  - Upload a test video
  - Verify transcoding occurs
  - Test video playback in web UI

- [ ] **Test mobile app** (optional for Week 2)

  - Install Immich mobile app (iOS/Android)
  - Configure server URL: https://photos.patriark.org
  - Login with credentials
  - Test photo backup from mobile

### Performance Testing

- [ ] **Upload performance test**

  - Upload 50 photos
  - Measure: time to upload, time to process
  - Baseline: photos/minute

- [ ] **ML inference speed**

  - Upload photos without faces detected
  - Measure: time to detect faces
  - Baseline: photos/second

- [ ] **Database query performance**

  - Browse library with 50+ photos
  - Search for objects
  - Measure: page load time, search time

- [ ] **Storage usage check**

  ```bash
  # PostgreSQL size
  podman exec postgresql-immich psql -U immich -c "SELECT pg_size_pretty(pg_database_size('immich'));"

  # Photo library size
  du -sh /mnt/btrfs-pool/subvol8-photos/library

  # Thumbnail size
  du -sh /mnt/btrfs-pool/subvol8-photos/thumbs

  # ML cache size
  du -sh ~/containers/config/immich/machine-learning

  # System SSD usage
  df -h / | grep nvme
  ```

### Security Testing

- [ ] **Test authentication**

  - Logout from Immich
  - Verify redirect to TinyAuth
  - Test invalid credentials (should deny)
  - Test valid credentials (should allow)

- [ ] **Test middleware chain**

  ```bash
  # Check Traefik logs for middleware execution
  podman logs traefik --tail 100 | grep immich
  # Verify: crowdsec-bouncer → rate-limit → tinyauth
  ```

- [ ] **Test CrowdSec integration**

  - Attempt multiple failed logins
  - Verify rate limiting kicks in
  - Check CrowdSec metrics

- [ ] **Test API access** (for future mobile app)

  ```bash
  curl -k https://photos.patriark.org/api/server-info/ping
  # Should return server info or auth required
  ```

### Documentation

- [ ] **Create Immich operation guide**

  `docs/10-services/guides/immich.md`:
  - Service overview
  - Architecture diagram
  - Management commands
  - Troubleshooting
  - Backup/restore procedures

- [ ] **Document deployment in journal**

  `docs/10-services/journal/YYYY-MM-DD-immich-deployment.md`:
  - What was deployed
  - Issues encountered and resolutions
  - Performance baselines
  - Lessons learned

- [ ] **Update CLAUDE.md**

  Add Immich-specific guidance:
  - Quadlet file locations
  - Network topology
  - Backup procedures
  - Upgrade process

- [ ] **Update system state report**

  `docs/99-reports/YYYY-MM-DD-system-state.md`:
  - Add Immich to service inventory
  - Update resource usage
  - Update backup strategy section

---

## Post-Deployment Verification

### Service Health Check

- [ ] **All services running**

  ```bash
  podman ps | grep -E 'immich|postgresql|redis'
  # Expected: immich-server, immich-ml, postgresql-immich, redis-immich (all Up)
  ```

- [ ] **All services healthy**

  ```bash
  for service in immich-server immich-ml postgresql-immich redis-immich; do
    echo "Checking $service..."
    podman healthcheck run $service
  done
  # Expected: All healthy
  ```

- [ ] **All services enabled**

  ```bash
  systemctl --user list-unit-files | grep -E 'immich|postgresql|redis' | grep enabled
  # Expected: All enabled
  ```

- [ ] **Traefik routing working**

  ```bash
  curl -k https://photos.patriark.org
  # Expected: Immich web UI or TinyAuth redirect
  ```

### Resource Usage Check

- [ ] **System SSD usage**

  ```bash
  df -h / | grep nvme
  # Expected: <80% (including ~20GB ML models)
  ```

- [ ] **BTRFS pool usage**

  ```bash
  df -h /mnt/btrfs-pool
  # Expected: Photo library + database (<100GB initially)
  ```

- [ ] **Memory usage**

  ```bash
  podman stats --no-stream | grep -E 'immich|postgresql|redis'
  # Expected: Total <2GB RAM
  ```

### Monitoring Check

- [ ] **Prometheus scraping Immich**

  - Check Prometheus targets: http://prometheus.patriark.org/targets
  - Verify: immich target UP

- [ ] **Grafana dashboard working**

  - Open Immich dashboard in Grafana
  - Verify: Metrics displaying (may take 5-10 minutes)

- [ ] **Alerts configured**

  - Check Alertmanager rules: http://alertmanager.patriark.org/#/alerts
  - Verify: Immich alerts loaded

### Backup Verification

- [ ] **BTRFS snapshots created**

  ```bash
  ls -la /mnt/btrfs-pool/.snapshots/subvol8-photos/
  # Expected: Snapshot directories with timestamps
  ```

- [ ] **PostgreSQL dumps created**

  ```bash
  ls -la /mnt/btrfs-pool/subvol7-containers/postgresql-backups/
  # Expected: immich-YYYYMMDD.sql.gz files
  ```

- [ ] **Backup timers active**

  ```bash
  systemctl --user list-timers | grep btrfs-backup
  # Expected: Daily and weekly timers active
  ```

---

## Troubleshooting Common Issues

### Immich Server won't start

```bash
# Check logs
podman logs immich-server --tail 100

# Common issues:
# 1. PostgreSQL not ready - wait 2-3 minutes
# 2. Database migration failed - check PostgreSQL logs
# 3. Secrets not found - verify podman secret ls
```

### ML inference not working

```bash
# Check ML container logs
podman logs immich-ml --tail 100

# Common issues:
# 1. Models still downloading - wait 10-20 minutes
# 2. ROCm GPU not detected - check /dev/dri passthrough
# 3. Out of memory - check system RAM usage
```

### Can't access via Traefik

```bash
# Check Traefik logs
podman logs traefik --tail 100 | grep immich

# Check Traefik dashboard
# https://traefik.patriark.org → HTTP → Routers → immich

# Common issues:
# 1. Container not on reverse_proxy network
# 2. Labels not applied correctly
# 3. TinyAuth middleware blocking access
```

### Photos not uploading

```bash
# Check Immich server logs
podman logs immich-server -f

# Check storage permissions
ls -la /mnt/btrfs-pool/subvol8-photos/library

# Check disk space
df -h /mnt/btrfs-pool

# Common issues:
# 1. SELinux blocking - check audit logs
# 2. Disk full - clean up or expand
# 3. Upload folder permissions - chown to container user
```

### System SSD filling up

```bash
# Check what's using space
du -sh ~/containers/config/immich/machine-learning
du -sh ~/.local/share/containers

# Move ML cache to BTRFS pool
systemctl --user stop immich-ml.service
mv ~/containers/config/immich/machine-learning /mnt/btrfs-pool/subvol7-containers/
ln -s /mnt/btrfs-pool/subvol7-containers/machine-learning ~/containers/config/immich/
systemctl --user start immich-ml.service
```

---

## Rollback Procedure

If deployment fails critically:

### Stop all Immich services

```bash
systemctl --user stop immich-server.service
systemctl --user stop immich-ml.service
systemctl --user stop postgresql-immich.service
systemctl --user stop redis-immich.service
```

### Remove containers

```bash
podman rm -f immich-server immich-ml postgresql-immich redis-immich
```

### Remove network

```bash
podman network rm systemd-photos
```

### Clean up storage

```bash
# Optional: Remove subvolume (DANGER: deletes all photos!)
# sudo btrfs subvolume delete /mnt/btrfs-pool/subvol8-photos

# Optional: Remove database directory
# rm -rf /mnt/btrfs-pool/subvol7-containers/postgresql-immich
```

### Remove Quadlet files

```bash
rm ~/.config/containers/systemd/immich-*.container
rm ~/.config/containers/systemd/postgresql-immich.container
rm ~/.config/containers/systemd/redis-immich.container
rm ~/.config/containers/systemd/systemd-photos.network
```

### Reload systemd

```bash
systemctl --user daemon-reload
```

---

## Success Criteria

Deployment is complete when:

- ✅ All 4 containers running and healthy
- ✅ Accessible via https://photos.patriark.org
- ✅ TinyAuth authentication working
- ✅ Photo upload and thumbnail generation working
- ✅ ML face detection working (CPU or GPU)
- ✅ Prometheus scraping metrics
- ✅ Grafana dashboard displaying data
- ✅ Backup automation including Immich data
- ✅ Documentation complete (operation guide + journal)

---

## Next Steps (Week 3)

After successful Immich deployment:

- [ ] **Complete Authelia SSO deployment**
- [ ] **Migrate Immich to Authelia forward auth**
- [ ] **Configure mobile app OAuth2 (if Authelia supports)**
- [ ] **Migrate Jellyfin to Authelia**
- [ ] **Migrate Grafana to Authelia**
- [ ] **Decommission TinyAuth**
- [ ] **Security review of homelab**
- [ ] **Performance optimization based on usage data**

---

**Reference:** ADR `docs/10-services/decisions/2025-11-08-immich-deployment-architecture.md`
**Journey Guide:** `docs/10-services/journal/20251107-immich-deployment-journey.md`
**Last Updated:** 2025-11-08
