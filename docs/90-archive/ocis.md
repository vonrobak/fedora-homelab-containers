# OCIS (ownCloud Infinite Scale) Deployment Guide

**Service:** OCIS v7.1.3 - Modern cloud platform with calendar and contacts
**URL:** https://cloud.patriark.org
**Status:** ✅ Production (deployed 2025-11-13)
**Storage:** BTRFS subvol7-containers/ocis (selective NOCOW for databases)

---

## Overview

OCIS is a modern, Go-based rewrite of ownCloud providing:
- **File sync and share** - WebDAV-based file management
- **Calendar** - CalDAV support with standard calendar apps
- **Contacts** - CardDAV support with standard contact apps
- **Spaces** - Collaborative workspaces
- **Built-in authentication** - OpenID Connect / LibreGraph IDM

**Why OCIS over Nextcloud:**
- 2-3x faster performance (Go vs PHP)
- Lower resource footprint (500MB-1GB vs 2-4GB)
- Modern microservices architecture
- No overlap with Immich (photos/videos)

---

## Architecture

### Service Dependencies

```
OCIS → Traefik → Internet
  ↓
BTRFS subvol7 (user files + databases)
```

**Network:** `systemd-reverse_proxy` (shares network with Traefik)

**No Authelia SSO:** OCIS handles its own authentication (similar to Immich per ADR-005)

### Storage Layout

```
/mnt/btrfs-pool/subvol7-containers/ocis/
├── data/
│   ├── storage/        ← User files (COW enabled for snapshot efficiency)
│   ├── spaces/         ← Shared spaces (COW enabled)
│   ├── uploads/        ← Temp uploads (COW enabled)
│   ├── idm/            ← User database (NOCOW for performance)
│   ├── nats/           ← Message queue (NOCOW for performance)
│   ├── search/         ← Search indexes (NOCOW for performance)
│   └── indexes/        ← Various indexes (NOCOW for performance)
└── config/ → ~/containers/config/ocis/ocis.yaml
```

**BTRFS Optimization:**
- User data: COW enabled → space-efficient snapshots
- Databases: NOCOW enabled → better I/O performance
- Trade-off accepted: Database snapshots less efficient but consistent

---

## Deployment Configuration

### Quadlet: `~/.config/containers/systemd/ocis.container`

**Key Settings:**
- **Image:** `docker.io/owncloud/ocis:7.1.3` (pinned version)
- **Memory Limits:** 2GB max, 1.5GB high (prevents OOM)
- **Secrets:** JWT, transfer secret, machine auth API key (Podman secrets)
- **Health Check:** HTTP check on port 9200

**Initialization:** Ran `ocis init` once to generate configuration with secure defaults

### Traefik Routing: `~/containers/config/traefik/dynamic/ocis-router.yml`

**Middleware Chain:**
```yaml
middlewares:
  - crowdsec-bouncer@file   # IP reputation (fail-fast)
  - rate-limit@file          # Request throttling
```

**Why no Authelia:** OCIS manages its own authentication (WebDAV/CalDAV clients need direct auth)
**Why no security-headers:** OCIS sets its own CSP (needs `unsafe-eval` for JS modules)

**Health Check:** Changed from `/status.php` (Nextcloud) to `/` (OCIS)

---

## CalDAV / CardDAV Configuration

### Connection URLs

**CalDAV (Calendar):**
```
https://cloud.patriark.org/remote.php/dav/calendars/USERNAME/
```

**CardDAV (Contacts):**
```
https://cloud.patriark.org/remote.php/dav/addressbooks/users/USERNAME/
```

**WebDAV (Files):**
```
https://cloud.patriark.org/remote.php/dav/files/USERNAME/
```

### Client Setup Examples

**Thunderbird:**
1. Calendar: New Calendar → On the Network → CalDAV → Enter URL above
2. Contacts: New Address Book → CardDAV → Enter URL above
3. Use OCIS username and password for authentication

**iOS/iPadOS:**
1. Settings → Calendar/Contacts → Accounts → Add Account → Other
2. Add CalDAV/CardDAV Account
3. Server: `cloud.patriark.org`
4. Username: OCIS username
5. Password: OCIS password

**Android (DAVx⁵):**
1. Install DAVx⁵ from F-Droid or Play Store
2. Add Account → Login with URL and credentials
3. Base URL: `https://cloud.patriark.org/remote.php/dav`

---

## Secrets Management

OCIS uses Podman secrets (not environment variables in plaintext):

```bash
# Secrets created during deployment
podman secret ls | grep ocis
ocis_jwt_secret              # JWT token signing
ocis_transfer_secret         # File transfer encryption
ocis_machine_auth_api_key    # Service-to-service auth
```

**Security:** Secrets are stored encrypted in Podman's secret storage, not in Git

---

## Common Operations

### Service Management

```bash
# Status
systemctl --user status ocis.service
podman ps --filter name=ocis

# Restart (applies config changes)
systemctl --user restart ocis.service

# Logs
journalctl --user -u ocis.service -f
podman logs -f ocis

# Health check
podman healthcheck run ocis
curl -I https://cloud.patriark.org
```

### User Management

**Admin Interface:** https://cloud.patriark.org/admin-settings
(Requires admin login)

**CLI User Management:**
```bash
# List users
podman exec ocis ocis accounts list

# Add user (if needed in future)
podman exec ocis ocis accounts add \
  --username newuser \
  --email newuser@example.com \
  --display-name "New User"
```

### Storage Management

**Check disk usage:**
```bash
du -sh /mnt/btrfs-pool/subvol7-containers/ocis/data/*
```

**BTRFS snapshot (backup):**
```bash
# Stop service for consistency (optional but recommended)
systemctl --user stop ocis.service

# Create snapshot
sudo btrfs subvolume snapshot \
  /mnt/btrfs-pool/subvol7-containers/ocis \
  /mnt/btrfs-pool/.snapshots/ocis-$(date +%F)

# Restart service
systemctl --user start ocis.service
```

---

## Troubleshooting

### White Page / Blank Screen

**Symptom:** OCIS loads but shows white page with no content

**Cause:** Security headers middleware blocking JavaScript execution

**Fix:** Remove `security-headers@file` from middleware chain (OCIS sets its own CSP)

**Verification:**
```bash
curl -I https://cloud.patriark.org | grep content-security-policy
# Should include: script-src 'self' 'unsafe-inline'
```

### Permission Errors on Startup

**Symptom:** `permission denied` errors in logs for `/var/lib/ocis/nats` or similar

**Cause:** Container UID (1000) doesn't have write permissions to data directory

**Fix:**
```bash
systemctl --user stop ocis.service
chmod 777 /mnt/btrfs-pool/subvol7-containers/ocis/data
systemctl --user start ocis.service
```

### CalDAV/CardDAV Authentication Fails

**Symptom:** 401 Unauthorized when configuring calendar/contacts

**Cause:** Using wrong username or password

**Fix:**
1. Verify credentials by logging into web interface
2. Use full username (not email unless that's the username)
3. Check for typos in server URL (`https://` required, no trailing slash)

### OCIS Not Accessible Through Traefik

**Symptom:** 503 Service Unavailable or connection refused

**Causes:**
1. OCIS container not on `systemd-reverse_proxy` network
2. Health check endpoint wrong
3. Backend URL misconfigured

**Check:**
```bash
# Verify OCIS is on correct network
podman network inspect systemd-reverse_proxy | grep -A5 ocis

# Test backend directly from Traefik
podman exec traefik wget -O- http://ocis:9200 | head -20

# Check Traefik logs for OCIS errors
podman logs traefik 2>&1 | grep -i ocis | tail -20
```

---

## Performance Tuning

### NOCOW Selective Application

**Current configuration** (optimized for snapshots + performance):
- User files: COW enabled → snapshot deduplication works
- Databases: NOCOW enabled → random write performance

**Verify:**
```bash
lsattr -d /mnt/btrfs-pool/subvol7-containers/ocis/data/*
# Storage/spaces/uploads: no 'C' flag (COW)
# idm/nats/search: 'C' flag (NOCOW)
```

**If snapshots are slow or too large:**
- Database NOCOW is working as intended
- Consider application-level backups for databases
- Use `btrfs filesystem du` to check snapshot overhead

### Memory Tuning

**Current limits:**
- MemoryMax=2G (hard limit, OOM kill if exceeded)
- MemoryHigh=1.5G (soft limit, throttling starts)

**Check actual usage:**
```bash
systemctl --user status ocis.service | grep Memory
podman stats ocis --no-stream
```

**Adjust if needed** (edit quadlet and reload):
```bash
nano ~/.config/containers/systemd/ocis.container
systemctl --user daemon-reload
systemctl --user restart ocis.service
```

---

## Security Considerations

### Authentication Model

**OCIS handles its own authentication** - no Authelia SSO integration

**Why:**
- CalDAV/CardDAV clients need direct authentication
- Mobile apps can't use web-based SSO flow
- OCIS includes LibreGraph IDM (full identity provider)
- Avoids dual-authentication UX issues (see Immich ADR-005)

**Protection Layers:**
1. CrowdSec IP reputation (blocks known attackers)
2. Rate limiting (prevents brute force)
3. OCIS internal auth (password + optional 2FA in OCIS settings)

### Secrets Management

**Good:**
- ✅ Secrets stored in Podman secrets (encrypted)
- ✅ Not in environment variables
- ✅ Not committed to Git

**Improvement opportunity:**
- Generated admin password saved in init output
- **Action:** Admin password already changed to secure value

### Network Exposure

**Public endpoints:**
- `/` - Web interface (public, requires login)
- `/remote.php/dav` - WebDAV/CalDAV/CardDAV (requires auth)

**Internal only:**
- Port 9100 (metrics/debug, if enabled) - localhost only

---

## Future Enhancements

### Prometheus Metrics

**Status:** ✅ Configured (2025-11-13)

OCIS exposes Prometheus metrics via the proxy debug endpoint:
- **Endpoint:** `http://ocis:9205/metrics`
- **Configuration:** `PROXY_DEBUG_ADDR=0.0.0.0:9205` in quadlet
- **Network:** OCIS joined `systemd-monitoring` network for Prometheus access

**Key Metrics Available:**
- `ocis_proxy_requests_total` - HTTP requests through proxy
- `ocis_proxy_duration_seconds` - Request duration histogram
- `ocis_proxy_errors_total` - Failed requests (status >= 500)
- `ocis_proxy_build_info` - Version information
- Service-specific metrics: `ocis_<service>_*` (gateway, graph, frontend, etc.)

**Prometheus Scrape Config:**
```yaml
- job_name: 'ocis'
  static_configs:
    - targets: ['ocis:9205']
      labels:
        instance: 'fedora-htpc'
        service: 'ocis'
```

**Verification:**
```bash
# Query OCIS target status
podman exec prometheus wget -qO- 'http://localhost:9090/api/v1/query?query=up{job="ocis"}'

# Check OCIS version metric
podman exec prometheus wget -qO- 'http://localhost:9090/api/v1/query?query=ocis_proxy_build_info'
```

### External Storage Integration

Current approach: Native OCIS storage (decomposedfs)

**Considered but not implemented:**
- Mounting subvol1-docs and subvol2-pics directly
- **Decision:** Import files into OCIS instead
- **Reason:** Better performance, all features work, simpler backups

**If needed in future:**
- OCIS supports external storage mounts
- Trade-offs: Limited features, permission complexity

### User Provisioning

Current: Manual user creation via admin interface or CLI

**Future options:**
- LDAP integration (OCIS has built-in LibreGraph LDAP)
- OAuth/OIDC federation (OCIS can be identity provider)
- User self-registration (if enabled in config)

---

## References

- **Official Docs:** https://doc.owncloud.com/ocis/
- **GitHub:** https://github.com/owncloud/ocis
- **ADR-005:** Immich authentication decisions (similar reasoning for OCIS)
- **CLAUDE.md:** Secrets management and security principles

---

**Last Updated:** 2025-11-13
**Deployed By:** Claude Code
**Review Date:** 2026-01-13 (or when upgrading OCIS)
