# Nextcloud Service Guide

**Service:** Nextcloud File Sync and Collaboration
**Version:** Nextcloud 32.0.5 (Hub 11) + MariaDB 11 + Redis 7
**Deployment:** Systemd Quadlets (Rootless Podman)
**Status:** ✅ Production
**Last Updated:** 2026-02-05

---

## Quick Reference

**Access Points:**
- **Web UI:** https://nextcloud.patriark.org
- **CalDAV:** https://nextcloud.patriark.org/remote.php/dav/calendars/USERNAME/
- **CardDAV:** https://nextcloud.patriark.org/remote.php/dav/addressbooks/users/USERNAME/
- **WebDAV:** https://nextcloud.patriark.org/remote.php/dav/files/USERNAME/
**Service Management:**
```bash
# Status
systemctl --user status nextcloud.service nextcloud-db.service nextcloud-redis.service

# Start
systemctl --user start nextcloud.service

# Stop
systemctl --user stop nextcloud.service

# Restart
systemctl --user restart nextcloud.service

# Logs
journalctl --user -u nextcloud.service -f
podman logs -f nextcloud
```

**Health Checks:**
```bash
# All services
podman healthcheck run nextcloud-db
podman healthcheck run nextcloud-redis
podman healthcheck run nextcloud

# Web status
curl -f https://nextcloud.patriark.org/status.php
# Expected: {"installed":true,"maintenance":false,"needsDbUpgrade":false}
```

**Critical Files:**
- Container: `~/.config/containers/systemd/nextcloud.container`
- Config: `/mnt/btrfs-pool/subvol7-containers/nextcloud/data/config/config.php`
- Data: `/mnt/btrfs-pool/subvol7-containers/nextcloud/data/data/`
- Secrets: `podman secret ls | grep nextcloud`

---

## Architecture Overview

### Container Stack

```
┌─────────────────────────────────────────────────────┐
│                    Internet                         │
│                       ↓                             │
│              Traefik (Port 443)                     │
│                       ↓                             │
│    ┌──────────────────────────────────────┐        │
│    │  Middleware Stack (layered)          │        │
│    │  1. CrowdSec Bouncer (IP reputation) │        │
│    │  2. Rate Limit (600/min, 3000 burst)  │        │
│    │  3. Circuit Breaker                  │        │
│    │  4. Retry                            │        │
│    │  5. CalDAV Redirects                 │        │
│    └──────────────────────────────────────┘        │
│                       ↓                             │
│              Nextcloud (Port 80)                    │
│         FIDO2/WebAuthn Passwordless Auth           │
└─────────────────────────────────────────────────────┘
                       ↓
        ┌──────────────┴──────────────┐
        │                             │
   ┌────▼─────┐                  ┌────▼────┐
   │ MariaDB  │                  │  Redis  │
   │  11.8.5  │                  │    7    │
   │ (NOCOW)  │                  │ Session │
   └──────────┘                  └─────────┘
```

### Network Topology

```
systemd-reverse_proxy (10.89.2.0/24)
    ├── Nextcloud (10.89.2.X)
    └── Traefik (10.89.2.40)

systemd-nextcloud (10.89.10.0/24) - Internal
    ├── Nextcloud
    ├── MariaDB
    └── Redis

systemd-monitoring (10.89.5.0/24)
    └── Nextcloud (Prometheus scraping)
```

**Network Order:** `reverse_proxy` MUST be first for internet access.

### Storage Layout

```
/mnt/btrfs-pool/
├── subvol7-containers/nextcloud/
│   └── data/                      # Nextcloud data (SELinux: :Z)
│       ├── config/config.php      # Main configuration
│       ├── data/admin/files/      # User files
│       ├── apps/                  # Installed apps
│       └── custom_apps/           # User-installed apps
│
├── subvol7-containers/nextcloud-db/
│   └── data/                      # MariaDB data (NOCOW enabled!)
│
├── subvol7-containers/nextcloud-redis/
│   └── data/                      # Redis persistence
│
├── subvol1-docs/                  # External storage (read-write)
│   → mounted as /external/user-documents in container
│
├── subvol2-pics/                  # External storage (read-write)
│   → mounted as /external/user-photos in container
│
├── subvol3-opptak/                # External storage (read-only)
├── subvol4-multimedia/            # External storage (read-only)
├── subvol5-music/                 # External storage (read-only)
└── subvol3-opptak/immich/         # External storage (read-only)
```

---

## Service Management

### Systemd Services

**Service Dependencies:**
```
nextcloud.service
    ├── Requires: nextcloud-db.service
    ├── Requires: nextcloud-redis.service
    └── After: network-online.target
```

**Start Order:**
1. `nextcloud-db.service` (MariaDB)
2. `nextcloud-redis.service` (Redis)
3. `nextcloud.service` (Nextcloud app)
**Common Operations:**

```bash
# Start all services
systemctl --user start nextcloud-db.service
systemctl --user start nextcloud-redis.service
systemctl --user start nextcloud.service

# Stop all services (reverse order)
systemctl --user stop nextcloud.service
systemctl --user stop nextcloud-redis.service
systemctl --user stop nextcloud-db.service

# Restart Nextcloud only
systemctl --user restart nextcloud.service

# Enable on boot
systemctl --user enable nextcloud.service nextcloud-db.service nextcloud-redis.service

# Check status
systemctl --user status nextcloud.service --no-pager
```

### Container Management

**List Containers:**
```bash
podman ps | grep nextcloud
```

**Inspect Container:**
```bash
podman inspect nextcloud | jq '.[0].Config.Env'  # Environment variables
podman inspect nextcloud | jq '.[0].Mounts'      # Volume mounts
podman inspect nextcloud | jq '.[0].NetworkSettings.Networks'  # Networks
```

**Resource Usage:**
```bash
podman stats --no-stream nextcloud nextcloud-db nextcloud-redis

# Expected:
# nextcloud:       ~1.2GB RAM (idle) / ~1.5GB (active)
# nextcloud-db:    ~250MB RAM
# nextcloud-redis: ~12MB RAM
```

**Logs:**
```bash
# Live logs (all services)
podman logs -f nextcloud
podman logs -f nextcloud-db
podman logs -f nextcloud-redis

# Systemd logs
journalctl --user -u nextcloud.service -f
journalctl --user -u nextcloud.service --since "1 hour ago"
journalctl --user -u nextcloud.service -n 100
```

---

## Configuration Management

### Main Configuration File

**Location:** `/mnt/btrfs-pool/subvol7-containers/nextcloud/data/config/config.php`

**Read Config (from inside container):**
```bash
podman exec nextcloud cat /var/www/html/config/config.php
```

**Key Settings:**
```php
'trusted_domains' => ['nextcloud.patriark.org', 'localhost'],
'overwriteprotocol' => 'https',
'overwritehost' => 'nextcloud.patriark.org',
'dbhost' => 'nextcloud-db',
'dbname' => 'nextcloud',
'dbuser' => 'nextcloud',
'redis' => [
  'host' => 'nextcloud-redis',
  'port' => 6379,
],
'trusted_proxies' => ['10.89.2.0/24'],
'default_phone_region' => 'NO',
'maintenance_window_start' => 6,  // 6 AM daily
```

### OCC Command-Line Tool

**Nextcloud's CLI admin tool** (some commands may fail due to Redis auth issues, use web UI as fallback):

```bash
# Basic commands
podman exec -u www-data nextcloud php occ status
podman exec -u www-data nextcloud php occ check
podman exec -u www-data nextcloud php occ app:list

# System configuration
podman exec -u www-data nextcloud php occ config:system:get trusted_domains
podman exec -u www-data nextcloud php occ config:system:set maintenance --value=true --type=boolean

# User management
podman exec -u www-data nextcloud php occ user:list
podman exec -u www-data nextcloud php occ user:add newuser
podman exec -u www-data nextcloud php occ user:resetpassword admin

# Maintenance
podman exec -u www-data nextcloud php occ maintenance:mode --on
podman exec -u www-data nextcloud php occ db:add-missing-indices
podman exec -u www-data nextcloud php occ maintenance:mode --off

# File scanning (if OCC Redis auth works)
podman exec -u www-data nextcloud php occ files:scan --all
podman exec -u www-data nextcloud php occ files:scan admin
```

**Note:** If OCC commands fail with "NOAUTH Authentication required", use the web UI instead (Settings → Administration).

### Podman Secrets Management

**List Secrets:**
```bash
podman secret ls | grep nextcloud
# nextcloud_db_password
# nextcloud_redis_password
```

**Inspect Secret (metadata only):**
```bash
podman secret inspect nextcloud_db_password
```

**Rotate Secret:**
```bash
# 1. Generate new password
NEW_PASSWORD=$(openssl rand -base64 32)

# 2. Remove old secret
systemctl --user stop nextcloud.service
podman secret rm nextcloud_db_password

# 3. Create new secret
echo -n "${NEW_PASSWORD}" | podman secret create nextcloud_db_password -

# 4. Update database password
podman exec nextcloud-db mysql -u root -e "ALTER USER 'nextcloud'@'%' IDENTIFIED BY '${NEW_PASSWORD}';"

# 5. Restart services
systemctl --user daemon-reload
systemctl --user start nextcloud.service
```

---

## Common Operations

### Adding External Storage (via Web UI)

**Recommended Method** (OCC has Redis auth issues):

1. Go to: https://nextcloud.patriark.org
2. Settings → Administration → External storage
3. Click "Add storage" → **Local**
4. Configuration:
   - **Folder name:** Display name (e.g., "Documents")
   - **Configuration → External Storage:** `/external/user-documents`
   - **Available for:** Select users/groups
5. Click checkmark to save
6. Verify green checkmark appears (connection successful)

**Existing External Storage:**
- `/external/user-documents` → subvol1-docs (read-write)
- `/external/user-photos` → subvol2-pics (read-write)
- `/external/downloads` → Downloads (read-write)
- `/external/immich-photos` → Immich library (read-only)
- `/external/multimedia` → Media files (read-only)
- `/external/music` → Music library (read-only)
- `/external/opptak` → Recordings (read-only)

### User Management (via Web UI)

**Create User:**
1. Settings → Users
2. Click "New user"
3. Username, Display name, Password
4. Assign to groups (e.g., "family", "admin")
5. Set quota (e.g., 100GB)
6. Send email invitation (if email configured)

**Modify User:**
1. Settings → Users
2. Click user row
3. Edit quota, groups, disable user, etc.

**Delete User:**
1. Settings → Users
2. Click trash icon next to user
3. Confirm deletion (files are deleted!)

### Backup Procedures

**Manual Backup:**
```bash
# 1. Enable maintenance mode
podman exec -u www-data nextcloud php occ maintenance:mode --on

# 2. Backup data directory
sudo btrfs subvolume snapshot -r \
  /mnt/btrfs-pool/subvol7-containers \
  /mnt/btrfs-pool/snapshots/nextcloud-$(date +%Y%m%d-%H%M%S)

# 3. Backup database
podman exec nextcloud-db mysqldump -u nextcloud -p nextcloud > \
  ~/containers/backups/nextcloud-db-$(date +%Y%m%d-%H%M%S).sql

# 4. Disable maintenance mode
podman exec -u www-data nextcloud php occ maintenance:mode --off
```

**Automated Backup (Recommended):**
See: `docs/20-operations/guides/backup-strategy.md`

### Restore Procedures

**Restore from BTRFS Snapshot:**
```bash
# 1. Stop services
systemctl --user stop nextcloud.service nextcloud-db.service nextcloud-redis.service

# 2. Restore snapshot
sudo btrfs subvolume delete /mnt/btrfs-pool/subvol7-containers/nextcloud
sudo btrfs subvolume snapshot \
  /mnt/btrfs-pool/snapshots/nextcloud-20251220-140000 \
  /mnt/btrfs-pool/subvol7-containers/nextcloud

# 3. Restart services
systemctl --user start nextcloud-db.service nextcloud-redis.service nextcloud.service

# 4. Verify
curl -f https://nextcloud.patriark.org/status.php
```

**Restore Database from SQL Dump:**
```bash
# 1. Stop Nextcloud
systemctl --user stop nextcloud.service

# 2. Drop and recreate database
podman exec nextcloud-db mysql -u root -e "DROP DATABASE nextcloud;"
podman exec nextcloud-db mysql -u root -e "CREATE DATABASE nextcloud CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"

# 3. Restore from dump
cat ~/containers/backups/nextcloud-db-20251220-140000.sql | \
  podman exec -i nextcloud-db mysql -u nextcloud -p nextcloud

# 4. Restart
systemctl --user start nextcloud.service
```

---

## Troubleshooting Guide

### Service Won't Start

**Symptoms:** `systemctl --user status nextcloud.service` shows failed

**Diagnosis:**
```bash
# Check logs
journalctl --user -u nextcloud.service -n 50
podman logs nextcloud --tail 50

# Check dependencies
systemctl --user status nextcloud-db.service
systemctl --user status nextcloud-redis.service

# Check networks
podman network ls | grep -E "reverse_proxy|nextcloud|monitoring"

# Check volume mounts
podman inspect nextcloud | jq '.[0].Mounts'
```

**Common Causes:**
1. **Database not running:** `systemctl --user start nextcloud-db.service`
2. **Redis not running:** `systemctl --user start nextcloud-redis.service`
3. **Volume permission issues:** Check SELinux contexts (`:Z` labels)
4. **Network missing:** `podman network create systemd-nextcloud --subnet 10.89.10.0/24`
5. **Port conflict:** `ss -tulnp | grep 80`

### Cannot Access Web UI

**Symptoms:** https://nextcloud.patriark.org returns error

**Diagnosis:**
```bash
# 1. Check Nextcloud running
podman ps | grep nextcloud

# 2. Check Traefik routing
curl -I https://nextcloud.patriark.org
# Should return HTTP/2 200 or 302/308

# 3. Check Traefik router
podman logs traefik | grep nextcloud

# 4. Check health
podman healthcheck run nextcloud
curl -f http://localhost:80/status.php  # From host, if accessible
```

**Common Causes:**
1. **Traefik not running:** `systemctl --user status traefik.service`
2. **DNS not resolving:** `dig nextcloud.patriark.org` (should return public IP)
3. **Firewall blocking:** `sudo firewall-cmd --list-all` (ports 80/443 open?)
4. **Maintenance mode on:** Check maintenance_mode in config.php

### CalDAV/CardDAV Sync Not Working

**Symptoms:** iOS Calendar/Contacts won't sync

**Diagnosis:**
```bash
# 1. Test CalDAV redirect
curl -I https://nextcloud.patriark.org/.well-known/caldav
# Expected: HTTP/2 308 → Location: /remote.php/dav/

# 2. Test CardDAV redirect
curl -I https://nextcloud.patriark.org/.well-known/carddav
# Expected: HTTP/2 308 → Location: /remote.php/dav/

# 3. Test DAV endpoint with auth
curl -u admin:PASSWORD https://nextcloud.patriark.org/remote.php/dav/
# Expected: HTTP/2 207 Multi-Status (WebDAV)

# 4. Check Traefik middleware
grep -A5 "nextcloud-caldav" /home/patriark/containers/config/traefik/dynamic/routers.yml
```

**Common Causes:**
1. **CalDAV redirect missing:** Check Traefik `nextcloud-caldav` middleware
2. **Wrong credentials:** Test login via web UI first
3. **FIDO2 vs password:** CalDAV requires app password if using passwordless web login
4. **Network restrictions:** Check if device is on VPN or restricted network

### High Memory Usage

**Symptoms:** Nextcloud container using >2GB RAM

**Diagnosis:**
```bash
# Check current usage
podman stats --no-stream nextcloud

# Check PHP processes
podman exec nextcloud ps aux | grep php

# Check PHP memory limit
podman exec nextcloud php -i | grep memory_limit
# Should be: 1G (from container env)

# Check active sessions
podman exec nextcloud-redis redis-cli KEYS "nextcloud:session:*" | wc -l
```

**Solutions:**
1. **Restart service:** `systemctl --user restart nextcloud.service`
2. **Increase memory limit:** Edit nextcloud.container `Memory=2048M`
3. **Check for memory leaks:** Review Nextcloud logs for errors
4. **Optimize PHP:** Add opcache, APCu settings in config.php

### Database Performance Issues

**Symptoms:** Slow queries, high CPU on nextcloud-db

**Diagnosis:**
```bash
# Check MariaDB process list
podman exec nextcloud-db mysql -u root -e "SHOW PROCESSLIST;"

# Check slow queries
podman logs nextcloud-db | grep -i "slow query"

# Verify NOCOW attribute
lsattr -d /mnt/btrfs-pool/subvol7-containers/nextcloud-db/data
# Should show: ---------------C------
```

**Solutions:**
1. **Add missing indices:** `podman exec -u www-data nextcloud php occ db:add-missing-indices`
2. **Optimize tables:** `podman exec nextcloud-db mysql -u root -e "OPTIMIZE TABLE nextcloud.oc_filecache;"`
3. **Check NOCOW:** If missing 'C' flag, rebuild database with NOCOW
4. **Increase resources:** Edit nextcloud-db.container `Memory=512M`

---

## Performance Optimization

### Redis Object Cache

**Enable in config.php:**
```php
'memcache.local' => '\OC\Memcache\APCu',
'memcache.distributed' => '\OC\Memcache\Redis',
'memcache.locking' => '\OC\Memcache\Redis',
'redis' => [
  'host' => 'nextcloud-redis',
  'port' => 6379,
  'password' => 'REDACTED',
],
```

### PHP Optimization

**Tune in nextcloud.container:**
```ini
Environment=PHP_MEMORY_LIMIT=1G
Environment=PHP_UPLOAD_LIMIT=10G
Environment=PHP_MAX_EXECUTION_TIME=3600
```

### Background Jobs

**Switch from AJAX to Cron:**
```bash
# Preferred method (systemd timer)
podman exec -u www-data nextcloud php occ background:cron

# Or create systemd timer (better)
# See: docs/20-operations/runbooks/nextcloud-cron.md
```

---

## Security Hardening

### FIDO2/WebAuthn Passwordless

**See:** `docs/10-services/decisions/2025-12-20-decision-008-nextcloud-passwordless-authentication.md`

**Current Setup:**
- 3 YubiKeys registered
- Vaultwarden passkey
- MacBook Air Touch ID
- Backup codes generated

**Manage Devices:**
- Settings → Personal → Security → FIDO2/WebAuthn devices
- Add, remove, rename devices

### Brute Force Protection

**Enabled by Default:**
- Nextcloud built-in throttling (3 failed attempts → delay)
- CrowdSec perimeter defense (18 HTTP attack scenarios)
- Rate limiting (600 req/min, 3000 burst via Traefik)

**Check Ban Status:**
```bash
podman exec crowdsec cscli decisions list
```

### Security Scan

**Run Security Scan:**
1. Settings → Administration → Overview
2. Review "Security & setup warnings"
3. Address any HIGH/CRITICAL warnings

**Automated Scans:**
```bash
# Vulnerability scanning
~/containers/scripts/scan-vulnerabilities.sh --severity CRITICAL,HIGH

# Check for updates
podman auto-update --dry-run
```

---

## Monitoring & Metrics

### Prometheus Metrics

**Endpoint:** `http://nextcloud:80/ocs/v2.php/apps/serverinfo/api/v1/info`

**Key Metrics:**
- Active users (last 5 minutes, last hour, last 24h)
- Storage usage (total, free, used)
- Database size
- Number of files
- Number of shares

### Health Monitoring

**Manual Health Check:**
```bash
~/containers/scripts/homelab-intel.sh | grep -i nextcloud
~/containers/scripts/query-homelab.sh "is nextcloud healthy?"
```

**SLO Targets** (see `docs/40-monitoring-and-documentation/guides/slo-framework.md`):
- **Availability:** 99.5% (3.65 hours/month downtime budget)
- **Latency (p95):** <500ms for status.php
- **Sync Success:** 99% CalDAV/CardDAV operations

### Grafana Dashboard

**Access:** https://grafana.patriark.org → Nextcloud Overview

**Panels:**
- Service uptime
- Response time (p50, p95, p99)
- Active users
- Storage usage trend
- Error rate

---

## Client Setup

### Desktop Clients (macOS / Windows / Linux)

**Download:** https://nextcloud.com/install/#install-clients

**Initial Setup:**
1. Open Nextcloud desktop client
2. Server URL: `https://nextcloud.patriark.org`
3. Authenticate via browser (FIDO2/WebAuthn or password)
4. Choose sync folder location

**Virtual Files (Files On-Demand):**
- Enable "Virtual file support" during setup or in Settings → Account
- Files appear as placeholders locally (no disk space used)
- Download on first access, pin for offline availability
- Particularly valuable for large external storage (Multimedia, Music, Opptak)
- Similar to OneDrive "Files On-Demand" or iCloud "Optimized Storage"

**Recommended Configuration:**
- Enable VFS for all sync connections
- Pin frequently-used folders for offline access
- Leave large media directories (Multimedia, Music, Opptak) as virtual

### Mobile Clients (iOS / Android)

**Download:** App Store / Google Play → "Nextcloud"

**Initial Setup:**
1. Server URL: `https://nextcloud.patriark.org`
2. Authenticate via browser
3. Grant photo upload permission (optional)

**Configuration:**
- **Auto-upload photos:** Settings → Auto Upload (optional)
- **Offline files:** Long-press → "Available offline" for specific files/folders
- Do NOT set large directories (Multimedia, Music) as offline

### CalDAV / CardDAV Setup

**iOS / macOS:**
1. Settings → Calendar → Accounts → Add Account → Other
2. CalDAV: Server `https://nextcloud.patriark.org`
3. Username + app password (generate in Nextcloud → Settings → Security → Devices & sessions)
4. Auto-discovery via `/.well-known/caldav` handles the rest
5. Repeat for Contacts (CardDAV)

**Note:** If using FIDO2 passwordless login, CalDAV/CardDAV requires an app-specific password.

---

## Sharing Best Practices

### Public Link Sharing
- Share files/folders via "Share link" in Nextcloud
- Shared links pass through full middleware chain (CrowdSec → rate limit → circuit breaker)
- Always set expiration dates on public shares
- Use password protection for sensitive content
- Read-only by default; enable editing only when needed

### Security Notes
- Shared links use HTTPS with HSTS preload
- CrowdSec IP reputation applies to all shared link access
- Rate limiting (400/min) protects against abuse
- External storage shares respect underlying read-only permissions

---

## Related Documentation

- **ADR-013:** Native Authentication Strategy
- **ADR-014:** Passwordless Authentication (FIDO2/WebAuthn)
- **ADR-016:** Configuration Design Principles (routing in dynamic config)
- **ADR-018:** Static IP Multi-Network Services
- **Runbook:** Nextcloud Operations (`docs/20-operations/runbooks/nextcloud-operations.md`)
- **CLAUDE.md:** Quick reference and best practices

---

**Guide Version:** 2.0
**Last Updated:** 2026-02-05
**Maintained By:** patriark + Claude Code
