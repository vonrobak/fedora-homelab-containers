# Samba & OCIS Cleanup - Session Summary

**Date:** 2025-12-29
**Duration:** ~1.5 hours
**Status:** ✅ Complete

## Issues Addressed

### 1. Immich iOS App Errors ✅ RESOLVED
**Problem:** Permission denied errors preventing thumbnail loading and video playback
**Root Cause:** Stale volume mount state after container updates
**Solution:** Restarted immich-server service to re-establish volume mounts
**Verification:** All Immich containers healthy, thumbnails loading, no permission errors

### 2. Immich Rate Limiting ✅ RESOLVED
**Problem:** Users hitting rate limits when browsing photo library
**Root Cause:** Generic rate limit (200 req/min, 100 burst) insufficient for thumbnail loading
**Solution:** Created custom `rate-limit-immich` middleware (500 req/min, 2000 burst)
**Files Modified:**
- `config/traefik/dynamic/middleware.yml` - Added rate-limit-immich
- `config/traefik/dynamic/routers.yml` - Applied to immich-secure router

### 3. Samba Server Decommissioning ✅ COMPLETE
**Objective:** Archive Samba config and prepare for shutdown
**Actions Taken:**
- Archived all Samba configuration to `/mnt/btrfs-pool/subvol6-tmp/99-outbound/samba/`
- Created archival metadata with timestamp and reason
- Documented manual shutdown commands (requires sudo)

**Manual Steps Required:**
```bash
sudo systemctl stop smbd.service
sudo systemctl disable smbd.service
sudo systemctl stop nmbd.service 2>/dev/null || true
sudo systemctl disable nmbd.service 2>/dev/null || true
```

**Archive Contents:**
- smb.conf (main configuration)
- smb.conf.bak (backup)
- smb.conf.example (reference)
- smb.conf.rpmnew (package update)
- lmhosts (NetBIOS hosts file)
- ARCHIVED_DATE.txt (metadata)

### 4. Permission Optimization Analysis ✅ COMPLETE
**Objective:** Evaluate if `samba` group should be removed from subvolumes
**Recommendation:** **Keep current permissions** (no changes needed)

**Rationale:**
- Current `patriark:samba` ownership is functionally harmless
- All containers run as UID 1000 outside (patriark) via rootless podman
- Owner (patriark) has full rwx access regardless of group
- Changing permissions is risky, time-consuming, and provides no benefit
- Allows easy Samba re-enablement if needed

**Documentation:** `docs/20-operations/guides/permission-optimization-nextcloud.md`

### 5. OCIS Remnant Removal ✅ COMPLETE
**Objective:** Complete decommissioning started 2025-12-20
**Actions Taken:**

#### Files Removed/Archived:
- ✅ `quadlets/ocis.container` → Archived to `/mnt/btrfs-pool/subvol6-tmp/99-outbound/ocis-archive/`
- ✅ `config/ocis/` → Removed via `podman unshare` (user-namespaced files)
- ✅ Podman image `docker.io/owncloud/ocis:7.1.3` → Removed (195 MB freed)
- ✅ Podman secrets → Removed (ocis_jwt_secret, ocis_transfer_secret, ocis_machine_auth_api_key)

#### Traefik Configuration Updates:
- ✅ Renamed `rate-limit-ocis` → `rate-limit-webdav` (config/traefik/dynamic/middleware.yml)
- ✅ Updated Collabora router to use `rate-limit-webdav@file` (config/traefik/dynamic/routers.yml)

#### Architecture Cleanup (Traefik Label Removal):
**Problem:** Inconsistent Traefik configuration - labels in quadlets AND file provider
**Solution:** Removed ALL Traefik labels from quadlets, standardized on file provider

**Files Modified:**
- `/home/patriark/.config/containers/systemd/nextcloud.container`
- `/home/patriark/.config/containers/systemd/collabora.container`

**Before:**
```ini
# Traefik labels in quadlet (Docker provider)
Label=traefik.enable=true
Label=traefik.http.routers.nextcloud.rule=Host(`nextcloud.patriark.org`)
# ... 10+ more labels
```

**After:**
```ini
# Traefik routing configured via file provider (config/traefik/dynamic/routers.yml)
# No labels needed - cleaner separation of concerns
```

**Benefits:**
- Single source of truth (file provider only)
- Easier maintenance (all routing in one place)
- Consistent with homelab design philosophy
- No more Docker provider errors in logs

#### Verification:
- ✅ No OCIS references in `podman images`
- ✅ No OCIS quadlets in `~/.config/containers/systemd/`
- ✅ No OCIS secrets in `podman secret ls`
- ✅ File provider routers working (nextcloud-secure, collabora-secure)
- ✅ Services accessible (Nextcloud, Collabora responding on HTTP)
- ✅ No Traefik labels on containers (verified with podman inspect)

## Files Created/Modified

### Created:
1. `scripts/cleanup-samba-and-ocis.sh` - Automated cleanup script
2. `docs/20-operations/guides/permission-optimization-nextcloud.md` - Permission analysis
3. `docs/99-reports/cleanup-summary-20251229.md` - This document
4. `/mnt/btrfs-pool/subvol6-tmp/99-outbound/samba/ARCHIVED_DATE.txt` - Samba archive metadata
5. `/mnt/btrfs-pool/subvol6-tmp/99-outbound/ocis-archive/ARCHIVED_DATE.txt` - OCIS archive metadata

### Modified:
1. `config/traefik/dynamic/middleware.yml`:
   - Added `rate-limit-immich` (500/min, 2000 burst)
   - Renamed `rate-limit-ocis` → `rate-limit-webdav`

2. `config/traefik/dynamic/routers.yml`:
   - Updated `immich-secure` router to use `rate-limit-immich@file`
   - Updated `collabora-secure` router to use `rate-limit-webdav@file`

3. `.config/containers/systemd/nextcloud.container`:
   - Removed all Traefik labels (now file provider only)

4. `.config/containers/systemd/collabora.container`:
   - Removed all Traefik labels (now file provider only)

## Current Subvolume Permissions

| Subvolume | Ownership | Permissions | Services | Status |
|-----------|-----------|-------------|----------|--------|
| subvol1-docs | patriark:samba | 2775 | Nextcloud | ✅ Working |
| subvol2-pics | patriark:samba | 2775 | Nextcloud | ✅ Working |
| subvol3-opptak | patriark:samba | 2775 | Immich + Nextcloud | ✅ Working |
| subvol4-multimedia | patriark:patriark | 755 | Jellyfin + Nextcloud | ✅ Working |
| subvol5-music | patriark:patriark | 755 | (Future) | N/A |
| subvol6-tmp | patriark:patriark | 755 | Host/Archives | ✅ Working |
| subvol7-containers | patriark:patriark | 755 | All containers | ✅ Working |

## Service Health Status

All services verified healthy:
- ✅ Immich (server, ML, Redis, PostgreSQL)
- ✅ Nextcloud (web, database, Redis, Collabora)
- ✅ Jellyfin
- ✅ Traefik
- ✅ Authelia
- ✅ Prometheus/Grafana/Loki

## Disk Space Recovered

- OCIS image removal: **195 MB**
- Update script efficiency: Images no longer pulled for OCIS

## Testing Performed

1. ✅ Immich iOS app - thumbnails loading, videos playing
2. ✅ Immich web - rapid photo browsing without rate limiting
3. ✅ Nextcloud - HTTP connectivity verified
4. ✅ Collabora - HTTP connectivity verified
5. ✅ Traefik - No Docker provider errors for Nextcloud/Collabora
6. ✅ File provider routers - Active and routing correctly

## Outstanding Manual Tasks

### Required:
1. **Stop Samba** (requires sudo):
   ```bash
   sudo systemctl stop smbd.service
   sudo systemctl disable smbd.service
   ```

### Optional:
1. Monitor services for 1 week to ensure stability
2. Remove `samba` group from system if confirmed unused:
   ```bash
   # After confirming no other services use it
   sudo groupdel samba
   ```

## Archive Locations

All archived materials preserved in:
```
/mnt/btrfs-pool/subvol6-tmp/99-outbound/
├── samba/                  (Samba configuration files)
│   ├── smb.conf
│   ├── smb.conf.bak
│   ├── smb.conf.example
│   ├── smb.conf.rpmnew
│   ├── lmhosts
│   └── ARCHIVED_DATE.txt
└── ocis-archive/          (OCIS quadlet + metadata)
    ├── ocis.container
    └── ARCHIVED_DATE.txt
```

## Lessons Learned

1. **Traefik Architecture:** Mixing Docker provider labels and file provider creates confusion. File provider is cleaner and more maintainable.

2. **Permission Changes:** Cosmetic permission "cleanup" is rarely worth the risk/effort. If it works, leave it alone.

3. **Container Restarts:** Volume mount issues often resolve with a simple service restart.

4. **Rate Limiting:** Photo/file management apps need higher burst capacity than general web services.

5. **Decommissioning:** Always verify with `podman images`, `podman secret ls`, and grep searches - don't trust previous "complete" removal claims.

## References

- ADR-001: Rootless Containers
- ADR-013: Nextcloud Native Authentication
- Journal: 2025-12-20-nextcloud-deployment-and-ocis-decommission.md
- Guide: docs/20-operations/guides/permission-optimization-nextcloud.md
- Script: scripts/cleanup-samba-and-ocis.sh
