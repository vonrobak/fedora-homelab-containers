# Nextcloud Security, Performance & Observability Enhancement Plan

**Date:** 2025-12-30
**Status:** Approved - Ready for Implementation
**Scope:** Security hardening, performance optimization, observability enhancement
**Approach:** Phased rollout (5 phases over 2-3 weeks)

---

## Executive Summary

**Objective:** Enhance Nextcloud deployment with critical security fixes, proactive performance optimization, and comprehensive observability aligned with homelab standards.

**User Decisions:**
- ✅ External Storage Web UI: Already configured - SKIP
- ✅ Security Hardening: **Immediate migration + change ALL plaintext credentials**
- ✅ Performance Optimization: **Proactive NOCOW migration**
- ✅ Observability Scope: **Health checks + SLO monitoring + Loki log aggregation**
- ✅ Implementation Approach: **Phased rollout**

**Timeline:** 2-3 weeks (1-2 hours per phase)
**Total Effort:** ~6-8 hours
**Downtime Required:** Phase 3 only (10-15 minutes)

---

## Phase Overview

| Phase | Focus | Effort | Downtime | Risk |
|-------|-------|--------|----------|------|
| **Phase 1** | Security Hardening | 2-3 hours | ~5 min | Low |
| **Phase 2** | Reliability (Health Checks) | 30 min | None | None |
| **Phase 3** | Performance (NOCOW) | 1 hour | 10-15 min | Low |
| **Phase 4** | Observability (SLO + Loki) | 2 hours | None | None |
| **Phase 5** | Validation & Documentation | 1 hour | None | None |

---

## Phase 1: Security Hardening - Credential Migration

**Goal:** Eliminate ALL plaintext credentials from quadlet files and configuration

**Priority:** CRITICAL - Security violation
**Effort:** 2-3 hours
**Downtime:** ~5 minutes (service restarts)
**Risk:** Low (backup before changes, test before cleanup)

### Affected Services

**Nextcloud Stack:**
- nextcloud-db.container (MYSQL_ROOT_PASSWORD, MYSQL_PASSWORD)
- nextcloud-redis.container (REDIS_PASSWORD)
- nextcloud.container (may reference Redis password)

**Other Services to Audit:**
- Check ALL quadlet files in `~/.config/containers/systemd/` for plaintext credentials
- Identify any Environment= lines with PASSWORD, SECRET, KEY, TOKEN

### Step-by-Step Procedure

#### Step 1.1: Backup Current Configuration (5 minutes)

```bash
# Backup all quadlet files
cd ~/.config/containers/systemd
tar -czf ~/containers/backups/quadlets-backup-$(date +%Y%m%d-%H%M%S).tar.gz *.container

# Backup Nextcloud config.php
podman exec nextcloud cat /var/www/html/config/config.php > \
  ~/containers/backups/nextcloud-config-$(date +%Y%m%d-%H%M%S).php

# Verify backups
ls -lh ~/containers/backups/ | tail -5
```

#### Step 1.2: Audit All Quadlets for Plaintext Credentials (10 minutes)

```bash
# Search for plaintext credentials
cd ~/.config/containers/systemd
grep -n "Environment=.*PASSWORD" *.container
grep -n "Environment=.*SECRET" *.container
grep -n "Environment=.*TOKEN" *.container
grep -n "Environment=.*KEY" *.container

# Document findings in audit log
cat > ~/containers/docs/99-reports/credential-audit-$(date +%Y%m%d).md <<'EOF'
# Credential Audit Report

Date: $(date)
Auditor: Claude (automated)

## Plaintext Credentials Found:

[PASTE grep output here]

## Migration Status:
- [ ] Nextcloud MariaDB credentials
- [ ] Nextcloud Redis password
- [ ] [Other services found]

EOF
```

#### Step 1.3: Create Podman Secrets (15 minutes)

**For Nextcloud (confirmed):**

```bash
# Extract current passwords from quadlets BEFORE creating secrets
MYSQL_ROOT_PASS=$(grep "MYSQL_ROOT_PASSWORD=" ~/.config/containers/systemd/nextcloud-db.container | cut -d'=' -f3)
MYSQL_USER_PASS=$(grep "MYSQL_PASSWORD=" ~/.config/containers/systemd/nextcloud-db.container | cut -d'=' -f3)
REDIS_PASS=$(grep "REDIS_PASSWORD=" ~/.config/containers/systemd/nextcloud-redis.container | cut -d'=' -f2)

# Create podman secrets
echo -n "$MYSQL_ROOT_PASS" | podman secret create nextcloud_db_root_password -
echo -n "$MYSQL_USER_PASS" | podman secret create nextcloud_db_password -
echo -n "$REDIS_PASS" | podman secret create nextcloud_redis_password -

# Verify secrets created
podman secret ls | grep nextcloud

# SECURITY: Clear bash history of password variables
unset MYSQL_ROOT_PASS MYSQL_USER_PASS REDIS_PASS
history -c
```

**For Any Other Services Found:**

```bash
# Template for additional services
echo -n "ACTUAL_PASSWORD" | podman secret create SERVICE_secret_name -
```

**CRITICAL:** Generate NEW passwords for ALL services, don't reuse old ones:

```bash
# Generate strong passwords (save to Vaultwarden)
openssl rand -base64 32  # For each service

# Create secrets with NEW passwords
echo -n "NEW_SECURE_PASSWORD" | podman secret create nextcloud_db_root_password -
```

#### Step 1.4: Update Quadlet Files (30 minutes)

**File:** `~/.config/containers/systemd/nextcloud-db.container`

```ini
# BEFORE (Lines 25-30):
Environment=MYSQL_ROOT_PASSWORD=REDACTED
Environment=MYSQL_PASSWORD=REDACTED
Environment=MYSQL_USER=nextcloud
Environment=MYSQL_DATABASE=nextcloud

# AFTER:
Secret=nextcloud_db_root_password,type=env,target=MYSQL_ROOT_PASSWORD
Secret=nextcloud_db_password,type=env,target=MYSQL_PASSWORD
Environment=MYSQL_USER=nextcloud
Environment=MYSQL_DATABASE=nextcloud
```

**File:** `~/.config/containers/systemd/nextcloud-redis.container`

```ini
# BEFORE (Line 16):
Environment=REDIS_PASSWORD=REDACTED

# AFTER:
Secret=nextcloud_redis_password,type=env,target=REDIS_PASSWORD
```

**File:** `~/.config/containers/systemd/nextcloud.container`

Check if Redis password is referenced. If yes, add:

```ini
Secret=nextcloud_redis_password,type=env,target=REDIS_PASSWORD
```

**Repeat for ALL services found in audit.**

#### Step 1.5: Update Nextcloud config.php for Redis Password (15 minutes)

**Method 1: Direct edit (if Redis password is hardcoded)**

```bash
# BACKUP FIRST (already done in Step 1.1)

# Check if Redis password is hardcoded in config.php
podman exec nextcloud grep "redis.*password" /var/www/html/config/config.php

# If hardcoded, need to update config.php to read from environment
# This is complex - may need to keep Environment= in quadlet for config.php
```

**Method 2: Keep Environment= in nextcloud.container for config.php compatibility**

```ini
# In nextcloud.container:
Secret=nextcloud_redis_password,type=env,target=REDIS_PASSWORD
# config.php will read from environment variable
```

**Verify config.php references environment variable:**

```php
'redis' => array(
  'host' => 'nextcloud-redis',
  'port' => 6379,
  'password' => getenv('REDIS_PASSWORD'),  // Must use getenv()
),
```

**If config.php has hardcoded password, update it:**

```bash
# Enter container
podman exec -it nextcloud bash

# Edit config.php
vi /var/www/html/config/config.php

# Change:
'password' => 'HARDCODED_PASSWORD',
# To:
'password' => getenv('REDIS_PASSWORD'),

# Exit and verify
exit
podman exec nextcloud cat /var/www/html/config/config.php | grep -A5 redis
```

#### Step 1.6: Test with Single Service First (20 minutes)

```bash
# Test nextcloud-redis first (smallest service)
systemctl --user daemon-reload
systemctl --user restart nextcloud-redis.service

# Verify it started with secret
systemctl --user status nextcloud-redis.service
podman logs nextcloud-redis --tail 20

# Test Redis connection with password
podman exec nextcloud-redis redis-cli -a $(podman secret inspect nextcloud_redis_password --format '{{.SecretData}}') PING
# Expected: PONG

# If successful, proceed to database
systemctl --user restart nextcloud-db.service
systemctl --user status nextcloud-db.service
podman logs nextcloud-db --tail 20

# Test database connection
podman exec nextcloud-db mysql -uroot -p$(podman secret inspect nextcloud_db_root_password --format '{{.SecretData}}') -e "SELECT 1;"
# Expected: 1

# Finally restart Nextcloud
systemctl --user restart nextcloud.service
systemctl --user status nextcloud.service
```

#### Step 1.7: Verify Nextcloud Functionality (15 minutes)

```bash
# Check Nextcloud status endpoint
curl -f http://localhost:80/status.php
# Expected: {"installed":true,"maintenance":false,...}

# Check Redis caching
podman exec nextcloud php occ config:system:get redis host
# Expected: nextcloud-redis

# Check database connection
podman exec nextcloud php occ db:convert-type --dry-run
# Expected: Should not error

# Test Web UI
curl -I https://nextcloud.patriark.org
# Expected: 200 OK

# Test login via browser
# Navigate to https://nextcloud.patriark.org
# Login with FIDO2/WebAuthn
# Verify files accessible
```

#### Step 1.8: Remove Plaintext Credentials (10 minutes)

**ONLY AFTER SUCCESSFUL VERIFICATION**

```bash
# Verify secrets are working
systemctl --user status nextcloud-db.service | grep active
systemctl --user status nextcloud-redis.service | grep active
systemctl --user status nextcloud.service | grep active

# Document secret names
cat > ~/containers/docs/30-security/secrets-inventory.md <<'EOF'
# Podman Secrets Inventory

## Nextcloud Stack
- nextcloud_db_root_password (MariaDB root)
- nextcloud_db_password (MariaDB nextcloud user)
- nextcloud_redis_password (Redis authentication)

## Other Services
[Add as migrated]

Last Updated: $(date)
EOF

# Secrets are now the source of truth
# Old plaintext values in quadlets have been replaced with Secret= directives
```

#### Step 1.9: Security Verification (10 minutes)

```bash
# Verify no plaintext credentials remain
cd ~/.config/containers/systemd
grep -n "Environment=.*PASSWORD" *.container | grep -v "Secret="
grep -n "Environment=.*SECRET" *.container | grep -v "Secret="
# Expected: No matches (or only non-sensitive environment variables)

# Verify secrets are not visible in systemd units
systemctl --user cat nextcloud-db.service | grep PASSWORD
# Expected: Should NOT show actual password, only "Secret=" directive

# Verify secrets exist
podman secret ls | grep nextcloud
# Expected: 3 secrets listed

# Attempt to inspect secret (should show metadata only)
podman secret inspect nextcloud_db_root_password
# Expected: Shows ID, timestamps, but NOT the actual password
```

### Phase 1 Success Criteria

- [ ] All plaintext credentials removed from quadlet files
- [ ] Podman secrets created for all credentials
- [ ] Nextcloud stack restarts successfully with secrets
- [ ] Web UI accessible (https://nextcloud.patriark.org)
- [ ] Login works (FIDO2/WebAuthn)
- [ ] Files accessible
- [ ] Redis caching functional
- [ ] Database connection working
- [ ] No plaintext credentials in systemctl output
- [ ] Backup of old configuration preserved

### Phase 1 Rollback Procedure

**If anything fails:**

```bash
# Stop services
systemctl --user stop nextcloud.service nextcloud-db.service nextcloud-redis.service

# Restore original quadlets
cd ~/.config/containers/systemd
tar -xzf ~/containers/backups/quadlets-backup-TIMESTAMP.tar.gz

# Reload and restart
systemctl --user daemon-reload
systemctl --user start nextcloud-db.service
systemctl --user start nextcloud-redis.service
systemctl --user start nextcloud.service

# Verify original functionality restored
curl -I https://nextcloud.patriark.org
```

---

## Phase 2: Reliability Enhancement - Health Checks

**Goal:** Add health checks to enable systemd auto-restart and autonomous operations

**Priority:** HIGH
**Effort:** 30 minutes
**Downtime:** None (daemon-reload only)
**Risk:** None (read-only health checks)

### Step-by-Step Procedure

#### Step 2.1: Add Health Checks to Quadlets (20 minutes)

**File:** `~/.config/containers/systemd/nextcloud.container`

Add health check section:

```ini
[Container]
# ... existing configuration ...

# Health check
HealthCmd=curl -f http://localhost:80/status.php || exit 1
HealthInterval=30s
HealthTimeout=10s
HealthRetries=3
HealthStartPeriod=60s
```

**File:** `~/.config/containers/systemd/nextcloud-db.container`

```ini
[Container]
# ... existing configuration ...

# Health check
HealthCmd=mysqladmin ping -h localhost || exit 1
HealthInterval=30s
HealthTimeout=10s
HealthRetries=3
HealthStartPeriod=30s
```

**File:** `~/.config/containers/systemd/nextcloud-redis.container`

```ini
[Container]
# ... existing configuration ...

# Health check
HealthCmd=redis-cli ping || exit 1
HealthInterval=30s
HealthTimeout=10s
HealthRetries=3
HealthStartPeriod=10s
```

**File:** `~/.config/containers/systemd/collabora.container`

```ini
[Container]
# ... existing configuration ...

# Health check
HealthCmd=curl -f http://localhost:9980/ || exit 1
HealthInterval=30s
HealthTimeout=10s
HealthRetries=3
HealthStartPeriod=60s
```

#### Step 2.2: Apply Health Checks (5 minutes)

```bash
# Reload systemd to pick up quadlet changes
systemctl --user daemon-reload

# Restart services to apply health checks
systemctl --user restart nextcloud-db.service
systemctl --user restart nextcloud-redis.service
systemctl --user restart nextcloud.service
systemctl --user restart collabora.service

# Wait for health checks to initialize
sleep 60
```

#### Step 2.3: Verify Health Checks (5 minutes)

```bash
# Check health status
podman healthcheck run nextcloud
podman healthcheck run nextcloud-db
podman healthcheck run nextcloud-redis
podman healthcheck run collabora
# Expected: "healthy" for all

# Check systemd status includes health
systemctl --user status nextcloud.service | grep -i health
# Expected: Shows health check status

# Verify auto-restart on failure (optional test)
# DO NOT run in production without planning
# podman exec nextcloud killall php-fpm
# systemctl --user status nextcloud.service
# Expected: Should auto-restart after 3 failed health checks
```

### Phase 2 Success Criteria

- [ ] Health checks defined in all 4 Nextcloud quadlets
- [ ] All services restart successfully
- [ ] `podman healthcheck run` returns "healthy" for all services
- [ ] Systemd status shows health check information
- [ ] Services auto-restart on health check failure (verified in test)

---

## Phase 3: Performance Optimization - NOCOW Migration

**Goal:** Enable BTRFS NOCOW on MariaDB database to prevent fragmentation

**Priority:** PROACTIVE (prevent future degradation)
**Effort:** 1 hour
**Downtime:** 10-15 minutes
**Risk:** Low (full backup before migration)

### Prerequisites

- Nextcloud stack healthy (Phase 1 & 2 complete)
- Maintenance window scheduled
- Users notified of brief downtime

### Step-by-Step Procedure

#### Step 3.1: Pre-Migration Backup (15 minutes)

```bash
# Stop Nextcloud to ensure consistent backup
systemctl --user stop nextcloud.service
systemctl --user stop nextcloud-db.service

# Dump MariaDB database
podman run --rm \
  --network systemd-nextcloud \
  -v /mnt/btrfs-pool/subvol7-containers/nextcloud-db:/var/lib/mysql:Z \
  -e MYSQL_ROOT_PASSWORD=$(podman secret inspect nextcloud_db_root_password --format '{{.SecretData}}') \
  mariadb:11 \
  mysqldump -h nextcloud-db -uroot -p"$MYSQL_ROOT_PASSWORD" --all-databases \
  > ~/containers/backups/nextcloud-db-$(date +%Y%m%d-%H%M%S).sql

# Verify backup size
ls -lh ~/containers/backups/nextcloud-db-*.sql | tail -1
# Expected: Should be non-zero size

# Also create BTRFS snapshot of current database (instant)
sudo btrfs subvolume snapshot \
  /mnt/btrfs-pool/subvol7-containers/nextcloud-db \
  /mnt/btrfs-pool/subvol7-containers/nextcloud-db-snapshot-$(date +%Y%m%d-%H%M%S)
```

#### Step 3.2: Create NOCOW Directory (5 minutes)

```bash
# Create new directory for database with NOCOW
sudo mkdir -p /mnt/btrfs-pool/subvol7-containers/nextcloud-db-nocow

# CRITICAL: Set NOCOW BEFORE copying data
sudo chattr +C /mnt/btrfs-pool/subvol7-containers/nextcloud-db-nocow

# Verify NOCOW attribute set
lsattr -d /mnt/btrfs-pool/subvol7-containers/nextcloud-db-nocow
# Expected: Should show 'C' flag (like: ---------------C-- /path)

# Set ownership (patriark:patriark for rootless container)
sudo chown -R patriark:patriark /mnt/btrfs-pool/subvol7-containers/nextcloud-db-nocow
```

#### Step 3.3: Copy Database to NOCOW Directory (10 minutes)

```bash
# Copy all database files to NOCOW directory
cp -a /mnt/btrfs-pool/subvol7-containers/nextcloud-db/* \
     /mnt/btrfs-pool/subvol7-containers/nextcloud-db-nocow/

# Verify copy completed
du -sh /mnt/btrfs-pool/subvol7-containers/nextcloud-db
du -sh /mnt/btrfs-pool/subvol7-containers/nextcloud-db-nocow
# Expected: Same size

# Verify file count matches
find /mnt/btrfs-pool/subvol7-containers/nextcloud-db -type f | wc -l
find /mnt/btrfs-pool/subvol7-containers/nextcloud-db-nocow -type f | wc -l
# Expected: Same count
```

#### Step 3.4: Update Quadlet to Use NOCOW Directory (5 minutes)

**File:** `~/.config/containers/systemd/nextcloud-db.container`

```ini
# BEFORE:
Volume=/mnt/btrfs-pool/subvol7-containers/nextcloud-db:/var/lib/mysql:Z

# AFTER:
Volume=/mnt/btrfs-pool/subvol7-containers/nextcloud-db-nocow:/var/lib/mysql:Z
```

#### Step 3.5: Start Services and Verify (10 minutes)

```bash
# Reload systemd
systemctl --user daemon-reload

# Start database
systemctl --user start nextcloud-db.service

# Wait for database to be ready
sleep 15

# Check database health
podman healthcheck run nextcloud-db
# Expected: healthy

# Verify MariaDB started
podman logs nextcloud-db --tail 20 | grep "ready for connections"
# Expected: Should show MariaDB ready

# Start Nextcloud
systemctl --user start nextcloud.service

# Wait for Nextcloud to initialize
sleep 30

# Check Nextcloud health
podman healthcheck run nextcloud
# Expected: healthy
```

#### Step 3.6: Verify Functionality (10 minutes)

```bash
# Test database connection
podman exec nextcloud-db mysql -uroot -p$(podman secret inspect nextcloud_db_root_password --format '{{.SecretData}}') -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='nextcloud';"
# Expected: Shows table count

# Test Nextcloud Web UI
curl -I https://nextcloud.patriark.org
# Expected: 200 OK

# Test file operations via Web UI
# 1. Login via browser
# 2. Upload a test file
# 3. Download the file
# 4. Delete the file
# Expected: All operations successful

# Check occ status
podman exec nextcloud php occ status
# Expected: installed: true, maintenance: false
```

#### Step 3.7: Verify NOCOW Performance (5 minutes)

```bash
# Check NOCOW attribute on database files
lsattr /mnt/btrfs-pool/subvol7-containers/nextcloud-db-nocow/nextcloud/*.ibd | head -5
# Expected: All files should show 'C' flag

# Monitor fragmentation over time (baseline measurement)
sudo filefrag /mnt/btrfs-pool/subvol7-containers/nextcloud-db-nocow/nextcloud/oc_filecache.ibd
# Expected: Low fragmentation (extent count)
# Document this baseline for future comparison

# Performance test (optional)
time podman exec nextcloud-db mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SELECT COUNT(*) FROM nextcloud.oc_filecache;"
# Document execution time for baseline
```

#### Step 3.8: Cleanup Old Database Directory (After 1 Week Verification)

**DO NOT EXECUTE IMMEDIATELY - Wait 1 week to ensure stability**

```bash
# After 1 week of successful operation:
# Rename old directory (don't delete immediately)
sudo mv /mnt/btrfs-pool/subvol7-containers/nextcloud-db \
        /mnt/btrfs-pool/subvol7-containers/nextcloud-db-old-$(date +%Y%m%d)

# After 1 month: Delete old directory
sudo rm -rf /mnt/btrfs-pool/subvol7-containers/nextcloud-db-old-YYYYMMDD

# Delete BTRFS snapshot (after 1 month)
sudo btrfs subvolume delete /mnt/btrfs-pool/subvol7-containers/nextcloud-db-snapshot-TIMESTAMP
```

### Phase 3 Success Criteria

- [ ] MariaDB database running from NOCOW directory
- [ ] `lsattr` shows 'C' flag on database files
- [ ] All health checks passing
- [ ] Web UI accessible and functional
- [ ] File upload/download working
- [ ] No database errors in logs
- [ ] Backup of old database preserved
- [ ] Performance baseline documented

### Phase 3 Rollback Procedure

**If database fails to start from NOCOW directory:**

```bash
# Stop database
systemctl --user stop nextcloud-db.service

# Restore original quadlet
# Edit ~/.config/containers/systemd/nextcloud-db.container
# Change Volume= back to original path

# Reload and restart
systemctl --user daemon-reload
systemctl --user start nextcloud-db.service
systemctl --user start nextcloud.service

# Verify functionality restored
curl -I https://nextcloud.patriark.org
```

---

## Phase 4: Observability Enhancement - SLO Monitoring & Loki Integration

**Goal:** Add comprehensive observability (SLO tracking, Loki log aggregation)

**Priority:** OPERATIONAL EXCELLENCE
**Effort:** 2 hours
**Downtime:** None
**Risk:** None (monitoring only)

### Part A: SLO Monitoring (1 hour)

#### Step 4A.1: Create SLO Recording Rules (20 minutes)

**File:** `~/containers/config/prometheus/rules/nextcloud-slos.yml` (NEW)

```yaml
groups:
  - name: nextcloud_slo_recording
    interval: 30s
    rules:
      # Availability SLO (target: 99.5%)
      - record: slo:nextcloud:availability:target
        expr: 0.995

      - record: slo:nextcloud:availability:actual
        expr: avg_over_time(up{job="nextcloud"}[5m])

      # Error budget (216 minutes/month for 99.5%)
      - record: slo:nextcloud:error_budget:total
        expr: 216 * 60  # 216 minutes in seconds

      - record: slo:nextcloud:error_budget:remaining
        expr: |
          slo:nextcloud:error_budget:total -
          (1 - avg_over_time(up{job="nextcloud"}[30d])) * 30 * 24 * 3600

      # Latency SLO (95% of requests < 1s)
      - record: slo:nextcloud:latency:target
        expr: 0.95

      # Calculate burn rate (how fast we're consuming error budget)
      - record: slo:nextcloud:burn_rate:1h
        expr: |
          (1 - avg_over_time(up{job="nextcloud"}[1h])) /
          (1 - slo:nextcloud:availability:target)
```

#### Step 4A.2: Create SLO Alerts (15 minutes)

**File:** `~/containers/config/prometheus/alerts/nextcloud-alerts.yml` (NEW)

```yaml
groups:
  - name: nextcloud_slo_alerts
    rules:
      # SLO breach alert
      - alert: NextcloudSLOBreach
        expr: slo:nextcloud:availability:actual < 0.995
        for: 5m
        labels:
          severity: warning
          service: nextcloud
        annotations:
          summary: "Nextcloud SLO breached ({{ $value | humanizePercentage }})"
          description: "Nextcloud availability is {{ $value | humanizePercentage }}, below 99.5% SLO target"

      # Fast burn rate (error budget exhausting quickly)
      - alert: NextcloudFastBurnRate
        expr: slo:nextcloud:burn_rate:1h > 10
        for: 10m
        labels:
          severity: critical
          service: nextcloud
        annotations:
          summary: "Nextcloud error budget burning fast ({{ $value }}x)"
          description: "Error budget consumption rate is {{ $value }}x normal, budget will exhaust in {{ $value | humanizeDuration }}"

      # Health check failing
      - alert: NextcloudUnhealthy
        expr: container_health_status{name="nextcloud"} != 1
        for: 5m
        labels:
          severity: critical
          service: nextcloud
        annotations:
          summary: "Nextcloud health check failing"
          description: "Nextcloud container health check has failed for 5 minutes"

      # Database health
      - alert: NextcloudDatabaseUnhealthy
        expr: container_health_status{name="nextcloud-db"} != 1
        for: 3m
        labels:
          severity: critical
          service: nextcloud
        annotations:
          summary: "Nextcloud database unhealthy"
          description: "MariaDB health check failing"

      # Redis health
      - alert: NextcloudRedisUnhealthy
        expr: container_health_status{name="nextcloud-redis"} != 1
        for: 3m
        labels:
          severity: warning
          service: nextcloud
        annotations:
          summary: "Nextcloud Redis unhealthy"
          description: "Redis cache unavailable, performance degraded"
```

#### Step 4A.3: Add Prometheus Scrape Target (10 minutes)

**File:** `~/containers/config/prometheus/prometheus.yml`

Add to `scrape_configs` section:

```yaml
  - job_name: 'nextcloud'
    static_configs:
      - targets: ['nextcloud:80']
        labels:
          service: 'nextcloud'
    # Scrape /metrics if Nextcloud metrics exporter installed
    # Otherwise, just monitor container health via cAdvisor
    scrape_interval: 30s
    scrape_timeout: 10s
```

#### Step 4A.4: Reload Prometheus (5 minutes)

```bash
# Validate Prometheus configuration
podman exec prometheus promtool check config /etc/prometheus/prometheus.yml
# Expected: SUCCESS

# Reload Prometheus
systemctl --user reload prometheus.service

# Verify new job appeared
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.job=="nextcloud")'
# Expected: Shows nextcloud target

# Verify recording rules active
curl http://localhost:9090/api/v1/query?query=slo:nextcloud:availability:actual | jq
# Expected: Returns SLO value
```

#### Step 4A.5: Create Grafana Dashboard (10 minutes)

**Option 1: Import existing dashboard**

```bash
# Download Nextcloud SLO dashboard template (if available)
# Or create custom dashboard in Grafana UI
```

**Option 2: Manual creation in Grafana UI**

1. Navigate to https://grafana.patriark.org
2. Create New Dashboard
3. Add panels:
   - Availability SLO (gauge: `slo:nextcloud:availability:actual`)
   - Error Budget Remaining (gauge: `slo:nextcloud:error_budget:remaining`)
   - Burn Rate (graph: `slo:nextcloud:burn_rate:1h`)
   - Health Status (stat: `container_health_status{name=~"nextcloud.*"}`)
   - Uptime (stat: `up{job="nextcloud"}`)

4. Save as "Nextcloud SLO Dashboard"

### Part B: Loki Log Aggregation (1 hour)

#### Step 4B.1: Configure Promtail for Nextcloud Logs (20 minutes)

**File:** `~/containers/config/promtail/promtail.yml`

Add new scrape job:

```yaml
scrape_configs:
  # ... existing jobs ...

  - job_name: nextcloud
    static_configs:
      - targets:
          - localhost
        labels:
          job: nextcloud
          __path__: /var/lib/containers/storage/volumes/nextcloud-logs/_data/*.log

  - job_name: nextcloud-access
    static_configs:
      - targets:
          - localhost
        labels:
          job: nextcloud-access
          __path__: /mnt/btrfs-pool/subvol7-containers/nextcloud/data/data/nextcloud.log

  - job_name: nextcloud-audit
    static_configs:
      - targets:
          - localhost
        labels:
          job: nextcloud-audit
          __path__: /mnt/btrfs-pool/subvol7-containers/nextcloud/data/data/audit.log
```

**Note:** May need to adjust paths based on actual Nextcloud log location:

```bash
# Find Nextcloud log paths
podman exec nextcloud ls -la /var/www/html/data/
podman exec nextcloud cat /var/www/html/config/config.php | grep logfile
```

#### Step 4B.2: Add Nextcloud Log Volume to Promtail (if needed)

**File:** `~/.config/containers/systemd/promtail.container`

Add volume mount if Nextcloud logs are in container volume:

```ini
Volume=/mnt/btrfs-pool/subvol7-containers/nextcloud/data:/nextcloud-data:ro,Z
```

#### Step 4B.3: Restart Promtail (5 minutes)

```bash
# Reload systemd
systemctl --user daemon-reload

# Restart Promtail
systemctl --user restart promtail.service

# Verify Promtail started
systemctl --user status promtail.service

# Check Promtail targets
podman logs promtail --tail 50 | grep nextcloud
# Expected: Should show nextcloud jobs being scraped
```

#### Step 4B.4: Verify Logs in Loki (10 minutes)

```bash
# Query Loki for Nextcloud logs
curl -G http://localhost:3100/loki/api/v1/query_range \
  --data-urlencode 'query={job="nextcloud"}' \
  --data-urlencode 'limit=10' | jq

# Expected: Returns Nextcloud log entries
```

**Via Grafana Explore:**

1. Navigate to https://grafana.patriark.org/explore
2. Select Loki datasource
3. Query: `{job="nextcloud"}`
4. Verify logs appear

#### Step 4B.5: Create LogQL Queries (25 minutes)

**File:** `~/containers/docs/40-monitoring-and-documentation/guides/loki-nextcloud-queries.md` (NEW)

```markdown
# Loki Queries for Nextcloud

## Common Queries

### All Nextcloud logs (last 1 hour)
\`\`\`logql
{job="nextcloud"}
\`\`\`

### Errors only
\`\`\`logql
{job="nextcloud"} |= "error" or "Error" or "ERROR"
\`\`\`

### Failed login attempts
\`\`\`logql
{job="nextcloud"} |= "Login failed"
\`\`\`

### Database errors
\`\`\`logql
{job="nextcloud"} |~ "(?i)database.*error|mysql.*error"
\`\`\`

### File upload failures
\`\`\`logql
{job="nextcloud"} |= "upload" |= "failed"
\`\`\`

### Performance: Slow queries
\`\`\`logql
{job="nextcloud"} |~ "Doctrine.*took.*[5-9][0-9]{3,}ms"
\`\`\`

### Rate of errors (errors per minute)
\`\`\`logql
sum(rate({job="nextcloud"} |= "error" [5m]))
\`\`\`

### Top 10 error types
\`\`\`logql
topk(10, sum by (error_type) (count_over_time({job="nextcloud"} | json | error_type != "" [24h])))
\`\`\`

## Audit Queries

### File access audit
\`\`\`logql
{job="nextcloud-audit"} | json | action="file_accessed"
\`\`\`

### User activity summary
\`\`\`logql
sum by (user) (count_over_time({job="nextcloud-audit"}[24h]))
\`\`\`

## Troubleshooting Queries

### Recent crashes or fatal errors
\`\`\`logql
{job="nextcloud"} |~ "(?i)fatal|crash|panic|segfault"
\`\`\`

### Memory issues
\`\`\`logql
{job="nextcloud"} |~ "(?i)out of memory|memory exhausted|memory limit"
\`\`\`

### External storage errors
\`\`\`logql
{job="nextcloud"} |= "external storage" |= "error"
\`\`\`
\`\`\`

Save these queries in Grafana for quick access.
```

### Phase 4 Success Criteria

**SLO Monitoring:**
- [ ] Recording rules active in Prometheus
- [ ] Alert rules loaded in Alertmanager
- [ ] Grafana dashboard created
- [ ] SLO metrics queryable (`slo:nextcloud:availability:actual`)
- [ ] Alerts configured for SLO breaches

**Loki Integration:**
- [ ] Promtail scraping Nextcloud logs
- [ ] Logs visible in Grafana Explore
- [ ] LogQL queries documented
- [ ] Error patterns detectable
- [ ] Audit logs accessible

---

## Phase 5: Validation & Documentation

**Goal:** Comprehensive testing and documentation updates

**Priority:** QUALITY ASSURANCE
**Effort:** 1 hour
**Downtime:** None
**Risk:** None

### Step-by-Step Procedure

#### Step 5.1: End-to-End Functionality Test (20 minutes)

```bash
# Test suite checklist

# 1. Nextcloud Web UI
curl -I https://nextcloud.patriark.org
# Expected: 200 OK

# 2. Authentication (manual browser test)
# - Navigate to https://nextcloud.patriark.org
# - Login with FIDO2/WebAuthn
# - Expected: Successful login

# 3. File Operations (manual)
# - Upload file to Documents
# - Download file
# - Delete file
# - Expected: All operations successful

# 4. External Storage (manual)
# - Navigate to /external/downloads in Nextcloud UI
# - Upload test file
# - Verify file appears on host: ls /mnt/btrfs-pool/subvol6-tmp/Downloads/
# - Delete file
# - Expected: Cross-device sync working

# 5. CalDAV/CardDAV
curl -I https://nextcloud.patriark.org/remote.php/dav/
# Expected: 401 Unauthorized (auth required - correct)

# 6. Collabora Office
# - Create new document in Nextcloud
# - Open with Collabora
# - Edit and save
# - Expected: Office editing works

# 7. Health Checks
podman healthcheck run nextcloud
podman healthcheck run nextcloud-db
podman healthcheck run nextcloud-redis
podman healthcheck run collabora
# Expected: All healthy

# 8. SLO Metrics
curl http://localhost:9090/api/v1/query?query=slo:nextcloud:availability:actual | jq '.data.result[0].value[1]'
# Expected: >0.995 (99.5%)

# 9. Loki Logs
curl -G http://localhost:3100/loki/api/v1/query_range \
  --data-urlencode 'query={job="nextcloud"}' \
  --data-urlencode 'limit=5' | jq '.data.result | length'
# Expected: >0 (logs present)

# 10. No Plaintext Credentials
cd ~/.config/containers/systemd
grep -r "PASSWORD=" *.container | grep -v Secret=
# Expected: No matches (or only non-sensitive vars)
```

#### Step 5.2: Performance Baseline (15 minutes)

```bash
# Document baseline metrics for future comparison

# Database performance
time podman exec nextcloud-db mysql -uroot -p"$(podman secret inspect nextcloud_db_root_password --format '{{.SecretData}}')" -e "SELECT COUNT(*) FROM nextcloud.oc_filecache;"
# Document execution time

# NOCOW fragmentation
sudo filefrag /mnt/btrfs-pool/subvol7-containers/nextcloud-db-nocow/nextcloud/*.ibd | head -5
# Document extent counts

# Response time
time curl -I https://nextcloud.patriark.org
# Document response time

# Resource usage
podman stats --no-stream nextcloud nextcloud-db nextcloud-redis
# Document memory/CPU usage

# Save baseline report
cat > ~/containers/docs/99-reports/nextcloud-performance-baseline-$(date +%Y%m%d).md <<EOF
# Nextcloud Performance Baseline

Date: $(date)

## Database Performance
[PASTE database query time]

## File Fragmentation
[PASTE filefrag output]

## Response Times
[PASTE curl time]

## Resource Usage
[PASTE podman stats]

## Notes
- NOCOW enabled: YES
- Health checks: ACTIVE
- SLO target: 99.5%
- Current availability: [CHECK slo:nextcloud:availability:actual]
EOF
```

#### Step 5.3: Update Documentation (25 minutes)

**1. Update Service Guide** (`docs/10-services/guides/nextcloud.md`)

Add sections:
- Security: Podman secrets migration (completed)
- Performance: NOCOW optimization (completed)
- Monitoring: SLO targets and dashboards
- Observability: Loki log queries

**2. Update Operations Runbook** (`docs/20-operations/runbooks/nextcloud-operations.md`)

Add procedures:
- Credential rotation procedure
- Health check troubleshooting
- SLO breach response
- NOCOW verification steps

**3. Create Security Documentation** (`docs/30-security/guides/nextcloud-security-hardening.md`)

Document:
- Podman secrets usage
- Credential rotation schedule
- Security audit procedures
- Secret management best practices

**4. Update BTRFS Guide** (`docs/20-operations/guides/storage-layout.md`)

Document:
- Nextcloud database NOCOW optimization
- Performance baseline
- Fragmentation monitoring procedure

**5. Create ADR** (`docs/10-services/decisions/2025-12-30-ADR-017-nextcloud-security-performance-optimization.md`)

```markdown
# ADR-017: Nextcloud Security, Performance & Observability Enhancement

Date: 2025-12-30
Status: Implemented

## Context
Nextcloud deployment had three improvement opportunities:
1. Plaintext credentials in quadlet files (security violation)
2. MariaDB lacking NOCOW optimization (performance risk)
3. No health checks or SLO monitoring (observability gap)

## Decision
Implemented comprehensive enhancement across security, performance, and observability:

1. **Security:** Migrated all credentials to podman secrets
2. **Performance:** Enabled BTRFS NOCOW on MariaDB database
3. **Observability:** Added health checks, SLO monitoring, Loki integration

## Implementation
- Phase 1: Security hardening (podman secrets)
- Phase 2: Health checks (systemd auto-restart)
- Phase 3: NOCOW migration (database optimization)
- Phase 4: SLO + Loki (comprehensive observability)
- Phase 5: Validation and documentation

## Consequences
**Positive:**
- Credentials encrypted at rest, not visible in systemd units
- Database performance protected against BTRFS fragmentation
- Systemd auto-restart on health check failures
- SLO tracking aligned with homelab patterns (99.5% target)
- Centralized log aggregation for troubleshooting

**Negative:**
- Credential rotation now requires podman secret management
- NOCOW cannot be toggled without data migration
- 10-15 minutes downtime required for NOCOW migration

## Metrics
- Availability SLO: 99.5% (216 min/month error budget)
- Database fragmentation: Baseline documented
- Security posture: No plaintext credentials
- Health checks: 30s interval, 3 retries

## References
- Service Guide: `docs/10-services/guides/nextcloud.md`
- Operations Runbook: `docs/20-operations/runbooks/nextcloud-operations.md`
- Implementation Plan: `docs/97-plans/2025-12-30-nextcloud-security-performance-observability-plan.md`
```

### Phase 5 Success Criteria

- [ ] All functionality tests passing
- [ ] Performance baseline documented
- [ ] Service guide updated
- [ ] Operations runbook updated
- [ ] Security documentation created
- [ ] BTRFS guide updated
- [ ] ADR-017 created
- [ ] No regressions detected

---

## Summary: Expected Outcomes

### Security Improvements

**Before:**
- 6 plaintext credentials in quadlet files
- Passwords visible in systemd units
- Inconsistent with homelab security standards

**After:**
- ✅ ALL credentials migrated to podman secrets
- ✅ Secrets encrypted at rest
- ✅ Passwords not visible in systemctl output
- ✅ Aligned with Immich/Authelia patterns
- ✅ Security audit passing

### Performance Improvements

**Before:**
- MariaDB database on standard BTRFS (COW enabled)
- Risk of 5-10x performance degradation over time
- No fragmentation monitoring

**After:**
- ✅ Database on NOCOW-enabled BTRFS directory
- ✅ Protection against fragmentation
- ✅ Performance baseline documented
- ✅ Fragmentation monitoring established

### Reliability Improvements

**Before:**
- No health checks
- Manual intervention required for failures
- No autonomous operations integration

**After:**
- ✅ Health checks on all 4 services
- ✅ Systemd auto-restart on failure
- ✅ Autonomous operations integration ready
- ✅ PHP-FPM crash detection

### Observability Improvements

**Before:**
- No SLO tracking
- No availability monitoring
- No centralized logging
- No operational dashboards

**After:**
- ✅ 99.5% availability SLO defined
- ✅ Error budget tracking (216 min/month)
- ✅ SLO breach alerts configured
- ✅ Loki log aggregation
- ✅ Grafana SLO dashboard
- ✅ LogQL queries documented
- ✅ Aligned with homelab monitoring patterns

---

## Timeline & Effort Summary

| Phase | Duration | Downtime | When |
|-------|----------|----------|------|
| Phase 1: Security | 2-3 hours | 5 min | Week 1, Day 1-2 |
| Phase 2: Health Checks | 30 min | None | Week 1, Day 3 |
| Phase 3: NOCOW | 1 hour | 10-15 min | Week 2, Day 1 (maintenance window) |
| Phase 4: Observability | 2 hours | None | Week 2, Day 2-3 |
| Phase 5: Validation | 1 hour | None | Week 2, Day 4 |

**Total:** 6.5-7.5 hours over 2-3 weeks (sustainable 1-2 hour sessions)

---

## Support & Rollback

### Getting Help

- **Service Guide:** `docs/10-services/guides/nextcloud.md`
- **Operations Runbook:** `docs/20-operations/runbooks/nextcloud-operations.md`
- **This Plan:** `docs/97-plans/2025-12-30-nextcloud-security-performance-observability-plan.md`

### Emergency Contacts

- Homelab operator (you)
- Backup location: `~/containers/backups/`
- BTRFS snapshots: `/mnt/btrfs-pool/subvol7-containers/nextcloud-db-snapshot-*`

### Rollback Procedures

Each phase includes detailed rollback steps. Key backups:

1. **Quadlet files:** `~/containers/backups/quadlets-backup-TIMESTAMP.tar.gz`
2. **Database dump:** `~/containers/backups/nextcloud-db-TIMESTAMP.sql`
3. **BTRFS snapshot:** `/mnt/btrfs-pool/subvol7-containers/nextcloud-db-snapshot-TIMESTAMP`
4. **Config.php:** `~/containers/backups/nextcloud-config-TIMESTAMP.php`

---

## Appendix: Quick Reference Commands

### Check Service Health

```bash
# All Nextcloud services
systemctl --user status nextcloud.service nextcloud-db.service nextcloud-redis.service collabora.service

# Health checks
podman healthcheck run nextcloud
podman healthcheck run nextcloud-db
podman healthcheck run nextcloud-redis
podman healthcheck run collabora
```

### Check SLO Status

```bash
# Current availability
curl -s http://localhost:9090/api/v1/query?query=slo:nextcloud:availability:actual | jq '.data.result[0].value[1]'

# Error budget remaining
curl -s http://localhost:9090/api/v1/query?query=slo:nextcloud:error_budget:remaining | jq '.data.result[0].value[1]'
```

### Check Logs in Loki

```bash
# Recent errors
curl -G http://localhost:3100/loki/api/v1/query_range \
  --data-urlencode 'query={job="nextcloud"} |= "error"' \
  --data-urlencode 'limit=10' | jq
```

### Verify No Plaintext Credentials

```bash
cd ~/.config/containers/systemd
grep -i "PASSWORD\|SECRET\|TOKEN\|KEY" *.container | grep -v "^#" | grep -v "Secret="
# Expected: No matches
```

### Check NOCOW Status

```bash
lsattr -d /mnt/btrfs-pool/subvol7-containers/nextcloud-db-nocow
# Expected: Shows 'C' flag
```

---

**Plan Status:** APPROVED - Ready for Implementation
**Created:** 2025-12-30
**Last Updated:** 2025-12-30
**Next Review:** After Phase 5 completion
