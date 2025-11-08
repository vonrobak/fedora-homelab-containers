# Immich Deployment - Balanced Expansion Journey

**Proposal:** C (Balanced Expansion)
**Timeline:** 4 weeks
**Status:** Ready to Begin
**Date Created:** 2025-11-07

---

## 🎯 Journey Overview

This is your roadmap to deploying Immich (self-hosted photo management) while hardening your existing homelab infrastructure. By the end, you'll have:

- ✅ A production-ready Immich deployment with ML-powered photo search
- ✅ PostgreSQL database infrastructure (reusable for future services)
- ✅ Complete backup automation (BTRFS + external)
- ✅ Enhanced security (CrowdSec active, Authelia SSO)
- ✅ Mobile app integration for automatic photo backup
- ✅ Comprehensive documentation of everything learned

**Why this journey matters:**
- First complex multi-service deployment (4 containers + 2 databases)
- Database management skills transferable to Nextcloud, Vaultwarden, etc.
- ML workload integration (new territory)
- Mobile-first application (different from media server)
- Real-world value (replace Google Photos)

---

## 📅 Week-by-Week Journey Map

### Week 1: Foundation & Planning
**Theme:** "Prepare the Ground"
**Goal:** Activate critical infrastructure, research Immich thoroughly

### Week 2: Database Infrastructure & Immich Foundation
**Theme:** "Lay the Database Layer"
**Goal:** Deploy PostgreSQL/Redis, begin Immich deployment

### Week 3: Immich Deployment & Security Hardening
**Theme:** "Build the Service"
**Goal:** Complete Immich stack, enhance security

### Week 4: Integration, Optimization & Documentation
**Theme:** "Polish and Perfect"
**Goal:** Mobile integration, performance tuning, comprehensive docs

---

## 🗓️ WEEK 1: Foundation & Planning

**Dates:** [Start Date] - [Start Date + 7 days]
**Focus:** Infrastructure hardening + Immich preparation
**Estimated Time:** 6-8 hours total

### Day 1: Activate Backup System (Critical!)

**Priority:** HIGHEST
**Time:** 2-3 hours
**Why:** Protect everything before adding complexity

**Tasks:**
1. **Review backup automation** (already created)
   ```bash
   cat ~/containers/scripts/btrfs-snapshot-backup.sh
   cat ~/containers/docs/backup-strategy-guide.md
   ```

2. **Verify external backup destination**
   - Mount external drive
   - Check available space (need ~100GB minimum)
   - Test write permissions

3. **Enable systemd timers**
   ```bash
   systemctl --user enable btrfs-backup-daily.timer
   systemctl --user enable btrfs-backup-weekly.timer
   systemctl --user start btrfs-backup-daily.timer
   systemctl --user start btrfs-backup-weekly.timer
   ```

4. **Run first backup (manual)**
   ```bash
   ~/containers/scripts/btrfs-snapshot-backup.sh --verbose
   ```

5. **Test restore procedure (file level)**
   - Restore a single file from snapshot
   - Document the process
   - Verify integrity

**Success Criteria:**
- ✅ Daily timer shows next run time
- ✅ Weekly timer scheduled for Sunday 3am
- ✅ First backup completed successfully
- ✅ Test file restored successfully
- ✅ External drive has snapshots

**Documentation:**
- Create journal entry: `docs/20-operations/journal/YYYY-MM-DD-backup-activation.md`

**Learning Objectives:**
- Understand BTRFS snapshot mechanics
- Learn systemd timer configuration
- Practice disaster recovery procedures

---

### Day 2: Activate CrowdSec & System Cleanup

**Priority:** HIGH
**Time:** 2 hours
**Why:** Security hardening before exposing new services

**Tasks:**

**Part 1: CrowdSec Activation** (1 hour)

1. **Verify CrowdSec configuration**
   ```bash
   podman logs crowdsec | tail -50
   cat ~/containers/config/traefik/dynamic/middleware.yml | grep crowdsec
   ```

2. **Check bouncer status**
   ```bash
   podman exec crowdsec cscli bouncers list
   ```

3. **Test ban mechanism**
   - Trigger a test ban (multiple failed auth attempts)
   - Verify Traefik blocks the IP
   - Check CrowdSec decisions: `cscli decisions list`

4. **Monitor CrowdSec metrics**
   - Check if Prometheus is scraping CrowdSec
   - View in Grafana dashboard

**Part 2: System Cleanup** (1 hour)

1. **Check current SSD usage**
   ```bash
   df -h /
   # Target: Get from 94% → <80%
   ```

2. **Identify space hogs**
   ```bash
   du -sh /home/patriark/* | sort -h
   podman system df
   ```

3. **Clean up candidates**
   ```bash
   # Remove old container images
   podman image prune -a --filter "until=720h"  # 30 days

   # Clean build cache
   podman system prune --volumes

   # Check journal size
   journalctl --disk-usage
   sudo journalctl --vacuum-size=500M
   ```

4. **Verify result**
   ```bash
   df -h /
   # Should be <80% now
   ```

**Success Criteria:**
- ✅ CrowdSec actively blocking IPs
- ✅ Bouncer connected and responding
- ✅ System SSD < 80% full
- ✅ At least 10GB freed up

**Documentation:**
- Update `docs/30-security/guides/crowdsec.md` with activation notes
- Document cleanup in journal entry

**Learning Objectives:**
- Understand CrowdSec decision engine
- Learn container image lifecycle management
- Practice system maintenance

---

### Day 3-4: Immich Research & Architecture Planning

**Priority:** MEDIUM
**Time:** 3-4 hours
**Why:** Thorough planning prevents deployment issues

**Research Tasks:**

**Part 1: Immich Architecture Study** (1.5 hours)

1. **Read official documentation**
   - Immich installation docs
   - Architecture overview
   - Hardware requirements

2. **Watch deployment videos** (optional)
   - Look for Podman/rootless deployments
   - Note any gotchas mentioned

3. **Study container requirements**
   - immich-server (API backend)
   - immich-machine-learning (ML inference)
   - immich-web (frontend)
   - immich-microservices (background jobs)
   - PostgreSQL (with pgvector extension)
   - Redis (job queue + cache)

4. **Hardware acceleration research**
   - AMD GPU support in Immich
   - VAAPI configuration for transcoding
   - ML inference acceleration options

**Part 2: Network & Storage Planning** (1.5 hours)

1. **Design network topology**
   ```
   Should Immich be on:
   - New network: systemd-photos?
   - Existing: systemd-media_services?
   - Multiple networks?

   Consider:
   - Database isolation
   - Internet access needs (for ML models)
   - Traefik routing
   ```

2. **Plan BTRFS storage**
   ```bash
   # Create subvolume for photos?
   sudo btrfs subvolume create /mnt/btrfs-pool/subvol8-photos

   # Or use existing subvol2-pics?
   # Consider: separation of personal photos vs other images
   ```

3. **Calculate storage needs**
   - How many photos do you have?
   - Estimate thumbnail storage (10-15% of originals)
   - ML model storage (~2GB)
   - Database size estimate

**Part 3: Create Deployment ADR** (1 hour)

Create: `docs/10-services/decisions/YYYY-MM-DD-decision-002-immich-architecture.md`

Template structure:
```markdown
# ADR 002: Immich Architecture Decisions

**Date:** YYYY-MM-DD
**Status:** Proposed
**Deciders:** [Your name]

## Context

We need to deploy Immich for self-hosted photo management...

## Decision

### Network Topology
- Immich containers will use: [decision]
- Database containers will use: [decision]
- Rationale: [why]

### Storage Strategy
- Photo library location: [decision]
- Database location: [decision]
- Backup strategy: [decision]

### Hardware Acceleration
- GPU passthrough: [yes/no + why]
- ML acceleration: [decision]

### Authentication
- Initial: TinyAuth
- Migration to Authelia: Week 3
- Rationale: [why staged approach]

## Consequences

**Positive:**
- [benefit 1]
- [benefit 2]

**Negative:**
- [tradeoff 1]
- [tradeoff 2]

**Risks:**
- [risk 1 + mitigation]
```

**Success Criteria:**
- ✅ Understand all 6 Immich components
- ✅ Network topology decided and documented
- ✅ Storage strategy planned
- ✅ ADR written and committed
- ✅ Hardware acceleration approach chosen

**Documentation:**
- ADR in decisions folder
- Research notes in journal

**Learning Objectives:**
- Understand multi-container application architecture
- Learn ADR format for documenting decisions
- Practice system design thinking

---

### Day 5: Database Deployment Planning

**Priority:** MEDIUM
**Time:** 1-2 hours
**Why:** Database is foundation for Immich

**Planning Tasks:**

1. **PostgreSQL research**
   - Learn about pgvector extension (required for Immich ML)
   - Understand PostgreSQL configuration for containers
   - Research backup strategies for PostgreSQL

2. **Create deployment checklist**

Create: `docs/10-services/journal/YYYY-MM-DD-database-deployment-checklist.md`

```markdown
# Database Deployment Checklist

## Pre-deployment
- [ ] Create systemd-database network
- [ ] Create BTRFS storage for databases (NOCOW)
- [ ] Plan database credentials (Podman secrets)
- [ ] Design backup integration

## PostgreSQL Deployment
- [ ] Create Quadlet file
- [ ] Configure pgvector extension
- [ ] Set up persistent storage
- [ ] Configure resource limits
- [ ] Test connection
- [ ] Create Immich database + user
- [ ] Enable in Prometheus monitoring

## Redis Deployment
- [ ] Create Quadlet file
- [ ] Configure persistence
- [ ] Set memory limits
- [ ] Test connection
- [ ] Enable in monitoring

## Post-deployment
- [ ] Backup verification
- [ ] Performance baseline
- [ ] Documentation update
```

3. **Study Quadlet patterns**
   ```bash
   # Review existing quadlets
   cat ~/.config/containers/systemd/jellyfin.container
   cat ~/.config/containers/systemd/prometheus.container

   # Note patterns for databases
   ```

4. **Research Podman secrets**
   - How to create secrets
   - How to mount in containers
   - Best practices

**Success Criteria:**
- ✅ Understand PostgreSQL + pgvector
- ✅ Deployment checklist created
- ✅ Secrets strategy planned
- ✅ Ready to deploy databases Week 2

**Learning Objectives:**
- Database containerization best practices
- Secrets management patterns
- Pre-deployment planning discipline

---

### Day 6-7: Week 1 Wrap-up & Preparation

**Priority:** LOW
**Time:** 1 hour
**Why:** Ensure Week 1 complete before moving to Week 2

**Tasks:**

1. **Verify Week 1 completion**
   - [ ] Backups running automatically
   - [ ] CrowdSec actively protecting
   - [ ] System SSD < 80% full
   - [ ] Immich ADR written
   - [ ] Database checklist ready

2. **Create Week 1 summary**

Create: `docs/40-monitoring-and-documentation/journal/YYYY-MM-DD-week1-immich-journey.md`

```markdown
# Week 1: Foundation & Planning - Summary

## Completed
- Backup automation activated
- CrowdSec threat protection active
- System cleaned up (X GB freed)
- Immich architecture researched and planned
- Database deployment checklist created

## Decisions Made
- [Key architectural decisions from ADR]

## Challenges Encountered
- [Any issues and how you resolved them]

## Week 2 Readiness
- [ ] Ready to deploy databases
- [ ] Network topology finalized
- [ ] Storage strategy clear
- [ ] Time allocated for deployment

## Learning Highlights
- [What you learned this week]
```

3. **Update system state report**
   - Copy `docs/99-reports/SYSTEM-STATE-2025-11-06.md`
   - Create `docs/99-reports/YYYY-MM-DD-system-state.md`
   - Update with Week 1 changes

4. **Commit everything**
   ```bash
   git add docs/
   git commit -m "Week 1 complete: Foundation hardening and Immich planning

   - Activated BTRFS backup automation
   - Activated CrowdSec threat protection
   - System cleanup (freed XGB)
   - Immich architecture ADR written
   - Database deployment planned

   Ready for Week 2: Database layer deployment"
   ```

**Success Criteria:**
- ✅ All Week 1 tasks complete
- ✅ Summary documentation written
- ✅ Clear plan for Week 2
- ✅ Confidence to proceed

---

## 🗓️ WEEK 2: Database Infrastructure & Immich Foundation

**Dates:** [Week 2 Start] - [Week 2 End]
**Focus:** Deploy PostgreSQL + Redis, begin Immich deployment
**Estimated Time:** 8-10 hours total

### Day 8-9: Database Layer Deployment

**Priority:** HIGHEST
**Time:** 4-5 hours
**Why:** Foundation for all Immich containers

**Part 1: Network Setup** (30 minutes)

1. **Create database network**

Create: `~/.config/containers/systemd/database.network`

```ini
[Unit]
Description=Database Services Network
Documentation=https://github.com/vonrobak/fedora-homelab-containers

[Network]
Subnet=10.89.5.0/24
Gateway=10.89.5.1
DNS=192.168.1.69
Label=app=database

[Install]
WantedBy=default.target
```

2. **Activate network**
   ```bash
   systemctl --user daemon-reload
   podman network ls | grep database
   ```

**Part 2: PostgreSQL Deployment** (2 hours)

1. **Create storage with NOCOW**
   ```bash
   sudo mkdir -p /mnt/btrfs-pool/subvol7-containers/postgresql
   sudo chattr +C /mnt/btrfs-pool/subvol7-containers/postgresql
   sudo chown -R $(id -u):$(id -g) /mnt/btrfs-pool/subvol7-containers/postgresql
   ```

2. **Create Podman secret for password**
   ```bash
   echo "your-secure-password-here" | podman secret create postgres-password -
   ```

3. **Create PostgreSQL Quadlet**

Create: `~/.config/containers/systemd/postgresql.container`

```ini
[Unit]
Description=PostgreSQL 16 Database Server
Documentation=https://www.postgresql.org/docs/16/
After=network-online.target database.network
Wants=network-online.target
Requires=database.network

[Container]
Image=docker.io/library/postgres:16-alpine
ContainerName=postgresql
HostName=postgresql

# Network
Network=systemd-database.network

# Environment
Environment=POSTGRES_USER=immich
Environment=POSTGRES_DB=immich
Secret=postgres-password,type=env,target=POSTGRES_PASSWORD

# Storage
Volume=/mnt/btrfs-pool/subvol7-containers/postgresql:/var/lib/postgresql/data:Z

# Resources
Memory=1G
MemorySwap=1G

# Health check
HealthCmd=pg_isready -U immich
HealthInterval=10s
HealthTimeout=5s
HealthRetries=3

[Service]
Restart=on-failure
TimeoutStartSec=300

[Install]
WantedBy=default.target
```

4. **Deploy and test**
   ```bash
   systemctl --user daemon-reload
   systemctl --user enable --now postgresql.service
   systemctl --user status postgresql.service

   # Test connection
   podman exec postgresql pg_isready -U immich
   ```

5. **Install pgvector extension**
   ```bash
   podman exec -it postgresql psql -U immich -c "CREATE EXTENSION IF NOT EXISTS vector;"
   podman exec -it postgresql psql -U immich -c "\dx"  # List extensions
   ```

**Part 3: Redis Deployment** (1.5 hours)

1. **Create storage**
   ```bash
   mkdir -p ~/containers/data/redis
   ```

2. **Create Redis Quadlet**

Create: `~/.config/containers/systemd/redis.container`

```ini
[Unit]
Description=Redis In-Memory Data Store
Documentation=https://redis.io/documentation
After=network-online.target database.network
Wants=network-online.target
Requires=database.network

[Container]
Image=docker.io/library/redis:7-alpine
ContainerName=redis
HostName=redis

# Network
Network=systemd-database.network

# Command - enable persistence
Exec=redis-server --appendonly yes --maxmemory 512mb --maxmemory-policy allkeys-lru

# Storage
Volume=%h/containers/data/redis:/data:Z

# Resources
Memory=512M
MemorySwap=512M

# Health check
HealthCmd=redis-cli ping
HealthInterval=10s
HealthTimeout=3s
HealthRetries=3

[Service]
Restart=on-failure
TimeoutStartSec=60

[Install]
WantedBy=default.target
```

3. **Deploy and test**
   ```bash
   systemctl --user daemon-reload
   systemctl --user enable --now redis.service

   # Test
   podman exec redis redis-cli ping  # Should return PONG
   ```

**Part 4: Monitoring Integration** (30 minutes)

1. **Add postgres_exporter** (optional but recommended)

2. **Add to Prometheus scrape config**
   ```yaml
   # Edit: ~/containers/config/prometheus/prometheus.yml
   - job_name: 'postgresql'
     static_configs:
       - targets: ['postgresql:5432']
         labels:
           service: 'postgresql'

   - job_name: 'redis'
     static_configs:
       - targets: ['redis:6379']
         labels:
           service: 'redis'
   ```

3. **Restart Prometheus**
   ```bash
   systemctl --user restart prometheus.service
   ```

4. **Create Grafana dashboard** (can do later)

**Success Criteria:**
- ✅ Database network created
- ✅ PostgreSQL healthy and accepting connections
- ✅ pgvector extension installed
- ✅ Redis healthy and responding to ping
- ✅ Both databases monitored in Prometheus
- ✅ NOCOW attribute set on PostgreSQL data

**Documentation:**
- Create guide: `docs/00-foundation/guides/database-deployment.md`
- Journal entry for deployment experience

**Learning Objectives:**
- PostgreSQL containerization
- Redis configuration for persistence
- Database networking and isolation
- Extension management in PostgreSQL

---

### Day 10-11: Immich Container Preparation

**Priority:** HIGH
**Time:** 3-4 hours
**Why:** Set up storage and initial containers

**Part 1: Storage Setup** (1 hour)

1. **Create photos subvolume**
   ```bash
   sudo btrfs subvolume create /mnt/btrfs-pool/subvol8-photos
   sudo chown -R $(id -u):$(id -g) /mnt/btrfs-pool/subvol8-photos

   # Create subdirectories
   mkdir -p /mnt/btrfs-pool/subvol8-photos/library
   mkdir -p /mnt/btrfs-pool/subvol8-photos/upload
   mkdir -p /mnt/btrfs-pool/subvol8-photos/thumbs
   mkdir -p /mnt/btrfs-pool/subvol8-photos/encoded-video
   mkdir -p /mnt/btrfs-pool/subvol8-photos/profile
   ```

2. **Create Immich config directory**
   ```bash
   mkdir -p ~/containers/config/immich
   ```

3. **Decide on network strategy**
   - Option A: Create new `systemd-photos.network`
   - Option B: Use existing `systemd-media_services.network`

   Document decision in ADR.

**Part 2: Immich-Server Deployment** (1.5 hours)

1. **Create environment file**

Create: `~/containers/config/immich/immich.env`

```bash
# Database
DB_HOSTNAME=postgresql
DB_PORT=5432
DB_USERNAME=immich
DB_PASSWORD=your-password-here  # TODO: Move to secret
DB_DATABASE_NAME=immich

# Redis
REDIS_HOSTNAME=redis
REDIS_PORT=6379

# Immich
UPLOAD_LOCATION=/usr/src/app/upload
IMMICH_MACHINE_LEARNING_URL=http://immich-machine-learning:3003
```

2. **Create immich-server Quadlet**

Create: `~/.config/containers/systemd/immich-server.container`

```ini
[Unit]
Description=Immich Server - Backend API
Documentation=https://immich.app/docs
After=postgresql.service redis.service
Requires=postgresql.service redis.service
Wants=network-online.target

[Container]
Image=ghcr.io/immich-app/immich-server:release
ContainerName=immich-server
HostName=immich-server

# Networks
Network=systemd-reverse_proxy.network
Network=systemd-database.network
# Add photos network if created

# Environment
EnvironmentFile=%h/containers/config/immich/immich.env

# Storage
Volume=/mnt/btrfs-pool/subvol8-photos/library:/usr/src/app/upload:Z
Volume=/etc/localtime:/etc/localtime:ro

# Resources
Memory=2G

# Health check
HealthCmd=wget --no-verbose --tries=1 --spider http://localhost:3001/api/server-info/ping || exit 1
HealthInterval=30s
HealthTimeout=10s
HealthRetries=3

[Service]
Restart=on-failure
TimeoutStartSec=300

[Install]
WantedBy=default.target
```

3. **Deploy immich-server**
   ```bash
   systemctl --user daemon-reload
   systemctl --user enable --now immich-server.service
   systemctl --user status immich-server.service

   # Check logs
   journalctl --user -u immich-server.service -f
   ```

**Part 3: Immich Machine Learning** (1 hour)

Create: `~/.config/containers/systemd/immich-machine-learning.container`

```ini
[Unit]
Description=Immich Machine Learning - ML Inference
Documentation=https://immich.app/docs
After=immich-server.service
Wants=network-online.target

[Container]
Image=ghcr.io/immich-app/immich-machine-learning:release
ContainerName=immich-machine-learning
HostName=immich-machine-learning

# Network
Network=systemd-database.network

# Environment
Environment=MACHINE_LEARNING_CACHE_FOLDER=/cache

# Storage
Volume=%h/containers/data/immich-ml-cache:/cache:Z

# Resources - ML needs more memory
Memory=4G

# Health check
HealthCmd=wget --no-verbose --tries=1 --spider http://localhost:3003/ping || exit 1
HealthInterval=30s

[Service]
Restart=on-failure
TimeoutStartSec=300

[Install]
WantedBy=default.target
```

Deploy:
```bash
mkdir -p ~/containers/data/immich-ml-cache
systemctl --user daemon-reload
systemctl --user enable --now immich-machine-learning.service
```

**Success Criteria:**
- ✅ Photo storage subvolume created
- ✅ immich-server container running
- ✅ immich-machine-learning container running
- ✅ Both containers can reach PostgreSQL and Redis
- ✅ ML models downloading (check logs)

**Documentation:**
- Update journal with deployment progress
- Note any issues encountered

---

### Day 12: Week 2 Wrap-up

**Priority:** LOW
**Time:** 1 hour

1. **Verify database layer health**
   - Check PostgreSQL connections
   - Check Redis memory usage
   - Review logs for errors

2. **Backup database**
   ```bash
   # Add to backup script if not already included
   podman exec postgresql pg_dump -U immich immich > ~/containers/backups/immich-db-$(date +%Y%m%d).sql
   ```

3. **Document Week 2**
   - Create summary journal entry
   - Update system state report
   - Commit all changes

4. **Plan Week 3**
   - Review remaining Immich containers to deploy
   - Plan Traefik integration
   - Schedule time for security hardening

---

## 🗓️ WEEK 3: Immich Completion & Security Hardening

**Dates:** [Week 3 Start] - [Week 3 End]
**Focus:** Complete Immich deployment, integrate Authelia
**Estimated Time:** 8-10 hours total

### Day 15-16: Complete Immich Stack

**Priority:** HIGHEST
**Time:** 4-5 hours

**Part 1: Immich Microservices** (1 hour)

Create: `~/.config/containers/systemd/immich-microservices.container`

```ini
[Unit]
Description=Immich Microservices - Background Jobs
Documentation=https://immich.app/docs
After=immich-server.service postgresql.service redis.service
Requires=postgresql.service redis.service

[Container]
Image=ghcr.io/immich-app/immich-server:release
ContainerName=immich-microservices
HostName=immich-microservices

# Networks
Network=systemd-database.network

# Environment
EnvironmentFile=%h/containers/config/immich/immich.env

# Command override for microservices
Exec=start-microservices.sh

# Storage
Volume=/mnt/btrfs-pool/subvol8-photos/library:/usr/src/app/upload:Z
Volume=/etc/localtime:/etc/localtime:ro

# Resources
Memory=2G

[Service]
Restart=on-failure
TimeoutStartSec=300

[Install]
WantedBy=default.target
```

**Part 2: Immich Web Frontend** (1 hour)

Create: `~/.config/containers/systemd/immich-web.container`

```ini
[Unit]
Description=Immich Web - Frontend UI
Documentation=https://immich.app/docs
After=immich-server.service
Requires=immich-server.service

[Container]
Image=ghcr.io/immich-app/immich-web:release
ContainerName=immich-web
HostName=immich-web

# Network
Network=systemd-reverse_proxy.network

# Environment
Environment=IMMICH_SERVER_URL=http://immich-server:3001

# Resources
Memory=512M

# Health check
HealthCmd=wget --no-verbose --tries=1 --spider http://localhost:3000 || exit 1
HealthInterval=30s

[Service]
Restart=on-failure
TimeoutStartSec=120

[Install]
WantedBy=default.target
```

**Part 3: Traefik Integration** (2 hours)

1. **Add router configuration**

Edit: `~/containers/config/traefik/dynamic/routers.yml`

```yaml
http:
  routers:
    immich-secure:
      rule: "Host(`photos.patriark.org`)"
      service: "immich-web"
      entryPoints:
        - websecure
      middlewares:
        - crowdsec-bouncer@file
        - rate-limit@file
        - tinyauth@file  # Will change to authelia later
        - security-headers@file
      tls:
        certResolver: letsencrypt

  services:
    immich-web:
      loadBalancer:
        servers:
          - url: "http://immich-web:3000"
```

2. **Test access**
   ```bash
   curl -I https://photos.patriark.org
   # Should get 200 OK (after auth)
   ```

3. **Create Immich admin account**
   - Navigate to https://photos.patriark.org
   - Complete first-time setup
   - Create admin user

**Part 4: Hardware Acceleration (AMD GPU)** (1 hour)

1. **Test GPU passthrough**
   ```bash
   # Check if GPU accessible
   ls -la /dev/dri/

   # May need to add user to render group
   sudo usermod -aG render $(whoami)
   ```

2. **Update immich-server Quadlet**
   Add GPU device:
   ```ini
   # Add to [Container] section:
   Device=/dev/dri:/dev/dri
   ```

3. **Configure Immich for hardware transcoding**
   - In Immich settings, enable hardware acceleration
   - Select VAAPI as acceleration method
   - Test video upload and transcoding

**Success Criteria:**
- ✅ All 4 Immich containers running
- ✅ Accessible via https://photos.patriark.org
- ✅ Admin account created
- ✅ Can upload test photos
- ✅ Face detection working (ML)
- ✅ Hardware acceleration functional

---

### Day 17-18: Security Hardening

**Priority:** HIGH
**Time:** 3-4 hours

**Part 1: Complete Authelia Deployment** (2 hours)

1. **Review existing Authelia configuration**
   ```bash
   systemctl --user status authelia.service
   ```

2. **Configure YubiKey 2FA**
   - Test YubiKey OTP with Authelia
   - Add hardware keys to your account

3. **Create Authelia middleware for Immich**

Edit: `~/containers/config/traefik/dynamic/middleware.yml`

```yaml
http:
  middlewares:
    authelia-immich:
      forwardAuth:
        address: "http://authelia:9091/api/verify?rd=https://auth.patriark.org"
        trustForwardHeader: true
        authResponseHeaders:
          - Remote-User
          - Remote-Groups
          - Remote-Name
          - Remote-Email
```

4. **Update Immich router to use Authelia**

Edit: `~/containers/config/traefik/dynamic/routers.yml`

```yaml
    immich-secure:
      middlewares:
        - crowdsec-bouncer@file
        - rate-limit@file
        - authelia-immich@file  # Changed from tinyauth
        - security-headers@file
```

5. **Test authentication flow**
   - Logout from Immich
   - Access https://photos.patriark.org
   - Should redirect to Authelia
   - Login with YubiKey 2FA
   - Should redirect back to Immich

**Part 2: Service-Wide SSO Migration** (1.5 hours)

1. **Migrate Jellyfin to Authelia**
2. **Migrate Grafana to Authelia**
3. **Migrate Prometheus/Loki to Authelia**
4. **Test all services**

**Part 3: Security Audit** (30 minutes)

```bash
~/containers/scripts/security-audit.sh
```

Review and address any findings.

**Success Criteria:**
- ✅ Authelia fully operational
- ✅ All services using SSO
- ✅ YubiKey 2FA working
- ✅ No security audit failures

---

### Day 19-20: Week 3 Wrap-up

**Priority:** MEDIUM
**Time:** 1-2 hours

1. **Test complete Immich workflow**
   - Upload photos from computer
   - Verify thumbnails generated
   - Test face detection
   - Create album
   - Test sharing

2. **Performance baseline**
   - Document upload speeds
   - ML inference time
   - Web UI responsiveness

3. **Backup verification**
   - Ensure Immich database backed up
   - Verify photo library in backup
   - Test restore of single photo

4. **Week 3 documentation**
   - Create comprehensive summary
   - Update system state report
   - Document any issues and solutions

---

## 🗓️ WEEK 4: Integration, Optimization & Documentation

**Dates:** [Week 4 Start] - [Week 4 End]
**Focus:** Mobile integration, performance tuning, comprehensive documentation
**Estimated Time:** 6-8 hours total

### Day 22-23: Mobile Integration

**Priority:** HIGH
**Time:** 3-4 hours

**Part 1: Mobile App Setup** (1.5 hours)

1. **Install Immich mobile app**
   - iOS: App Store
   - Android: Google Play

2. **Configure server connection**
   - Server URL: https://photos.patriark.org
   - Login with Authelia credentials

3. **Test manual upload**
   - Upload test photo from phone
   - Verify appears in web UI
   - Check thumbnail generation

4. **Enable automatic backup**
   - Configure backup settings
   - Select albums to backup
   - Test background upload

**Part 2: Optimization** (1.5 hours)

1. **ML Performance tuning**
   ```bash
   # Monitor ML container resource usage
   podman stats immich-machine-learning

   # Adjust memory if needed
   ```

2. **Database optimization**
   ```bash
   # Check database size
   podman exec postgresql psql -U immich -c "\l+"

   # Run VACUUM if needed
   podman exec postgresql psql -U immich -c "VACUUM ANALYZE;"
   ```

3. **Upload performance testing**
   - Test upload speed for large batches
   - Monitor CPU/GPU during transcoding
   - Adjust worker settings if needed

**Part 3: User Experience Polish** (1 hour)

1. **Configure Immich settings**
   - Set default upload quality
   - Configure ML features
   - Set thumbnail quality

2. **Create albums and organize**
   - Test album creation
   - Test sharing features
   - Configure permissions

**Success Criteria:**
- ✅ Mobile app connected and uploading
- ✅ Automatic backup functional
- ✅ Performance acceptable (< 5s per photo)
- ✅ ML features working smoothly

---

### Day 24-25: Comprehensive Documentation

**Priority:** HIGH
**Time:** 3-4 hours
**Why:** Capture everything learned

**Part 1: Create Immich Operation Guide** (2 hours)

Create: `docs/10-services/guides/immich.md`

Template structure:
```markdown
# Immich Photo Management - Operation Guide

**Last Updated:** YYYY-MM-DD
**Status:** Production
**Version:** [Immich version]

## Quick Reference

### Service URLs
- Web UI: https://photos.patriark.org
- Admin: https://photos.patriark.org/admin

### Management Commands
[Common operations]

## Architecture

### Components
[Diagram and explanation of all 6 components]

### Network Topology
[How containers communicate]

### Storage Layout
[Where photos are stored, database location]

## Configuration

### Environment Variables
[Key settings]

### Quadlet Files
[Location and key parameters]

### Traefik Integration
[Routing and middleware setup]

## Operations

### Adding Users
[How to create accounts]

### Backup and Restore
[Procedures for database and photos]

### Upgrading
[How to update Immich]

### Performance Tuning
[ML settings, worker configuration]

## Troubleshooting

### Common Issues
[Problems you encountered and solutions]

### Logs
[Where to find logs, what to look for]

### Health Checks
[How to verify everything is working]

## Mobile App

### Setup Instructions
[Step-by-step for iOS/Android]

### Configuration
[Optimal settings]

## Monitoring

### Key Metrics
[What to watch in Grafana]

### Alerts
[What alerts are configured]

## Security

### Authentication
[Authelia integration]

### Access Control
[Who can access what]

### Network Security
[Network isolation, firewall rules]

## Maintenance

### Daily
[Automated tasks]

### Weekly
[Regular checks]

### Monthly
[Maintenance tasks]

## Performance Baselines

### Upload Speed
[Metrics from testing]

### ML Inference
[Face detection time, etc]

### Storage Growth
[Estimated growth rate]
```

**Part 2: Update Database Deployment Guide** (1 hour)

Update: `docs/00-foundation/guides/database-deployment.md`

Add:
- PostgreSQL + pgvector pattern
- Redis configuration
- Backup strategies
- Monitoring integration

Make it reusable for future services.

**Part 3: Create Journey Retrospective** (1 hour)

Create: `docs/40-monitoring-and-documentation/journal/YYYY-MM-DD-immich-journey-complete.md`

```markdown
# Immich Deployment Journey - Retrospective

**Duration:** 4 weeks
**Proposal:** C (Balanced Expansion)
**Status:** Complete

## Summary

Successfully deployed Immich with complete database infrastructure...

## What Went Well

### Technical Wins
- [What worked smoothly]

### Learning Highlights
- [Key concepts mastered]

### Process Successes
- [What made the journey effective]

## Challenges Overcome

### Technical Challenges
1. [Challenge] - Solution: [How resolved]
2. [Challenge] - Solution: [How resolved]

### Learning Challenges
- [Concepts that were difficult]
- [How you worked through them]

## Key Decisions

### Architecture
- [Major decisions and rationale]

### Trade-offs
- [What you chose and why]

## Metrics

### Timeline
- Planned: 4 weeks
- Actual: X weeks
- Deviation: [analysis]

### Effort
- Estimated: 20-25 hours
- Actual: X hours

### Learning Objectives
- [X/10] achieved

## Skills Acquired

### Technical
- PostgreSQL containerization
- Multi-container orchestration
- ML workload management
- Hardware acceleration
- Mobile app integration

### Operational
- Database backup strategies
- Performance optimization
- Security hardening (Authelia SSO)

### Documentation
- ADR writing
- Operation guide creation
- Journey tracking

## What's Next

### Immediate Improvements
- [Things to refine in next 2 weeks]

### Future Services
- [What's now possible with database layer]

### Long-term Vision
- [How this fits into homelab evolution]

## Advice for Future Self

### If Deploying Similar Service
- [Lessons for next database-backed service]

### If Teaching Someone
- [What to emphasize]

## Conclusion

[Reflection on the journey]
```

---

### Day 26-27: Final Testing & Celebration

**Priority:** MEDIUM
**Time:** 2 hours

**Part 1: Disaster Recovery Test** (1 hour)

1. **Simulate failure scenarios**
   - Stop PostgreSQL, verify Immich handles gracefully
   - Stop Redis, verify job queue recovers
   - Test photo restore from backup

2. **Document recovery procedures**

**Part 2: System State Report** (30 minutes)

Create: `docs/99-reports/YYYY-MM-DD-system-state-immich-complete.md`

Update with:
- All Immich services
- Database layer
- Performance metrics
- Storage usage
- Security posture

**Part 3: Commit and Celebrate** (30 minutes)

```bash
git add .
git commit -m "Complete Immich deployment - 4 week journey

Immich Stack (6 containers):
- immich-server (API backend)
- immich-web (frontend)
- immich-machine-learning (ML inference)
- immich-microservices (background jobs)
- PostgreSQL 16 + pgvector
- Redis 7

Features:
- ML-powered face detection and object recognition
- Hardware acceleration (AMD GPU)
- Mobile app integration (iOS/Android)
- Automatic photo backup from phone
- SSO via Authelia with YubiKey 2FA
- Complete monitoring in Prometheus/Grafana
- Automated BTRFS backups

Infrastructure Improvements:
- Database layer established (PostgreSQL + Redis)
- BTRFS backup automation active
- CrowdSec threat protection active
- Authelia SSO fully deployed
- System SSD cleaned (94% → X%)

Documentation:
- Immich operation guide created
- Database deployment guide updated
- Journey retrospective written
- ADRs for all decisions
- Comprehensive troubleshooting guides

Learning Outcomes:
- Multi-container orchestration
- Database management (PostgreSQL + Redis)
- ML workload integration
- Hardware acceleration
- Mobile app deployment
- Performance optimization

Next: Nextcloud, Vaultwarden, or other database-backed services"

git push origin claude/project-state-review-011CUtcDYRAwPvgHvjja4r2R
```

**Part 4: Celebrate! 🎉**

You've successfully:
- ✅ Deployed a complex 6-container application
- ✅ Established reusable database infrastructure
- ✅ Integrated ML workloads
- ✅ Set up mobile app sync
- ✅ Enhanced security with Authelia SSO
- ✅ Documented everything comprehensively

**Take a moment to:**
- Upload your first real photos
- Share with family/friends (if desired)
- Write a blog post (optional)
- Plan next service (Nextcloud? Vaultwarden?)

---

## 📊 Success Metrics

By the end of 4 weeks, you should have:

### Technical Achievements
- [ ] 6 Immich containers running healthy
- [ ] PostgreSQL database with pgvector
- [ ] Redis for caching and jobs
- [ ] Mobile app backing up photos automatically
- [ ] ML face detection functional
- [ ] Hardware acceleration working
- [ ] All services using Authelia SSO
- [ ] BTRFS backups running automatically
- [ ] CrowdSec actively protecting

### Documentation Achievements
- [ ] Immich operation guide complete
- [ ] Database deployment guide created
- [ ] Journey retrospective written
- [ ] ADRs for all major decisions
- [ ] Troubleshooting guides for issues encountered
- [ ] Updated system state report

### Learning Achievements
- [ ] Understand multi-container dependencies
- [ ] Can deploy PostgreSQL with extensions
- [ ] Know how to configure Redis
- [ ] Understand ML container requirements
- [ ] Can integrate mobile apps with homelab
- [ ] Confident with hardware passthrough
- [ ] Can optimize performance based on metrics

### Operational Achievements
- [ ] Disaster recovery tested and documented
- [ ] Backup strategy validated
- [ ] Performance baseline established
- [ ] Monitoring dashboards created
- [ ] Security audit passed

---

## 🎓 Learning Objectives Checklist

### Database Management
- [ ] Deploy PostgreSQL in container
- [ ] Install and use PostgreSQL extensions (pgvector)
- [ ] Configure Redis for persistence and caching
- [ ] Implement database backup strategies
- [ ] Understand database networking and isolation
- [ ] Monitor database performance

### Container Orchestration
- [ ] Deploy multi-container application (6 containers)
- [ ] Manage container dependencies with systemd
- [ ] Configure inter-container networking
- [ ] Implement health checks for all containers
- [ ] Handle startup ordering
- [ ] Manage resource limits

### Machine Learning Infrastructure
- [ ] Deploy ML workload container
- [ ] Understand ML model caching
- [ ] Configure ML inference settings
- [ ] Monitor ML performance
- [ ] Optimize ML resource usage

### Hardware Integration
- [ ] Pass GPU to containers
- [ ] Configure VAAPI for video transcoding
- [ ] Test hardware acceleration
- [ ] Monitor GPU usage

### Mobile Integration
- [ ] Configure mobile app with homelab
- [ ] Set up automatic background sync
- [ ] Troubleshoot mobile connectivity
- [ ] Optimize for mobile data usage

### Security
- [ ] Implement Authelia SSO
- [ ] Configure YubiKey 2FA
- [ ] Migrate multiple services to SSO
- [ ] Understand authentication flow
- [ ] Implement proper network segmentation

### Performance Optimization
- [ ] Establish performance baselines
- [ ] Monitor with Prometheus/Grafana
- [ ] Identify bottlenecks
- [ ] Tune resource allocation
- [ ] Optimize database queries

### Documentation
- [ ] Write comprehensive operation guides
- [ ] Create ADRs for decisions
- [ ] Document journey in journal
- [ ] Write troubleshooting guides
- [ ] Create system state reports

---

## 🚧 Common Challenges & Solutions

### Challenge: PostgreSQL won't start with pgvector

**Symptoms:** Container crashes on startup, logs show extension error

**Solution:**
```bash
# Ensure using correct PostgreSQL image with pgvector support
# Or install extension manually:
podman exec -it postgresql psql -U immich -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

### Challenge: ML container using too much memory

**Symptoms:** OOM kills, slow inference

**Solution:**
- Increase memory limit in Quadlet
- Configure ML cache size
- Limit concurrent jobs in Immich settings

### Challenge: Slow photo upload from mobile

**Symptoms:** Photos take minutes to upload

**Solution:**
- Check network bandwidth
- Adjust upload quality in mobile app
- Enable cellular upload (if desired)
- Check Traefik rate limits

### Challenge: Face detection not working

**Symptoms:** ML models not running, no faces detected

**Solution:**
- Check ML container logs
- Verify models downloaded (check volume)
- Ensure ML container can reach server
- Check ML settings in Immich admin

### Challenge: Hardware acceleration not working

**Symptoms:** High CPU during transcoding, no GPU usage

**Solution:**
- Verify GPU device passed to container
- Check /dev/dri permissions
- Ensure user in render group
- Test VAAPI with test video

---

## 📚 Resources & References

### Official Documentation
- [Immich Documentation](https://immich.app/docs)
- [PostgreSQL 16 Docs](https://www.postgresql.org/docs/16/)
- [Redis Documentation](https://redis.io/documentation)
- [Podman Documentation](https://docs.podman.io/)

### Community Resources
- Immich GitHub Issues (for troubleshooting)
- r/selfhosted subreddit
- Immich Discord community

### Your Documentation
- `docs/10-services/guides/immich.md` - Operation guide
- `docs/00-foundation/guides/database-deployment.md` - Database pattern
- `docs/10-services/decisions/*-immich-*.md` - Architecture decisions
- `docs/10-services/journal/*-immich-*.md` - Journey log

---

## 🎯 What Makes This Journey Memorable

### You're Not Just Deploying Software

You're building:
- **Real-world skills** that transfer to any infrastructure role
- **A portfolio piece** demonstrating complex orchestration
- **Practical value** (replace Google Photos, save $60+/year)
- **Knowledge base** through comprehensive documentation
- **Confidence** to tackle even more complex services

### You're Learning by Doing

Every week builds on the last:
- Week 1: Foundation and planning (delayed gratification)
- Week 2: Database layer (seeing infrastructure take shape)
- Week 3: Service deployment (excitement of working product)
- Week 4: Polish and perfection (pride in quality)

### You're Documenting Everything

Your future self will thank you:
- When deploying Nextcloud (reuse database pattern)
- When troubleshooting (search your own docs)
- When teaching others (comprehensive guides)
- When updating resume (concrete accomplishments)

### You're Building for Scale

This isn't just Immich:
- Database layer enables 10+ future services
- Authelia SSO simplifies all future auth
- Monitoring catches issues before they cascade
- Documentation makes onboarding others trivial

---

## 🚀 After Immich: What's Possible

With database infrastructure in place, you can now deploy:

**Immediate Candidates:**
- **Nextcloud** - File sync, calendars, contacts (PostgreSQL)
- **Vaultwarden** - Password manager (SQLite or PostgreSQL)
- **Paperless-NGX** - Document management (PostgreSQL)
- **Audiobookshelf** - Audiobook/podcast server

**Medium-term:**
- **GitTea/Forgejo** - Self-hosted Git (PostgreSQL)
- **Tandoor Recipes** - Recipe management (PostgreSQL)
- **Linkding** - Bookmark manager
- **FreshRSS** - RSS feed reader

**Each new service will be faster because:**
- Database pattern established
- Quadlet patterns known
- Network topology understood
- Monitoring integration standard
- Backup strategy proven

---

## 💭 Reflection Prompts

Throughout the journey, consider:

**Week 1:**
- How does having backups change your comfort with experimentation?
- What surprised you about BTRFS snapshot behavior?

**Week 2:**
- How does PostgreSQL in containers differ from expectations?
- What was most challenging about multi-container networking?

**Week 3:**
- How does SSO change the user experience?
- What trade-offs did you make for YubiKey 2FA?

**Week 4:**
- How does mobile integration change the value of the service?
- What would you do differently next time?

**Overall:**
- What skill are you most proud of acquiring?
- What documentation will be most valuable long-term?
- What service are you excited to deploy next?

---

## 📝 Final Checklist

Before marking journey complete:

**Technical:**
- [ ] All 6 containers running and healthy
- [ ] Mobile app uploading photos automatically
- [ ] Face detection functional
- [ ] Hardware acceleration verified
- [ ] Backups tested (database + photos)
- [ ] Disaster recovery procedures documented
- [ ] Performance baseline established
- [ ] Monitoring dashboards created
- [ ] Security audit passed

**Documentation:**
- [ ] Operation guide complete and tested
- [ ] ADRs written for all decisions
- [ ] Journey retrospective published
- [ ] Troubleshooting guide covers issues encountered
- [ ] Database deployment guide reusable
- [ ] System state report updated

**Learning:**
- [ ] Can explain architecture to someone else
- [ ] Understand all container dependencies
- [ ] Confident deploying next database service
- [ ] Know how to troubleshoot common issues
- [ ] Can optimize based on metrics

**Operational:**
- [ ] Backup automation validated
- [ ] Recovery procedures tested
- [ ] Maintenance scheduled
- [ ] Alerts configured
- [ ] Documentation index updated

---

## 🎉 Congratulations!

When you complete this journey, you'll have:

**Deployed:**
- A production-grade photo management system
- Complete database infrastructure
- ML-powered features
- Mobile app integration
- Enterprise-grade authentication

**Learned:**
- Multi-container orchestration
- Database management
- ML workload deployment
- Hardware acceleration
- Performance optimization
- Security hardening

**Created:**
- Comprehensive documentation
- Reusable deployment patterns
- Troubleshooting guides
- Operation procedures
- Learning journal

**Enabled:**
- 10+ future database-backed services
- SSO for all future services
- Confidence to tackle complex deployments
- Portfolio showcase
- Real-world practical value

**This isn't just a deployment - it's a transformation of your homelab from good to great.**

---

**Now, let's begin Week 1!**

Are you ready to activate those backups? 🚀
