# Jellyfin Media Server

**Last Updated:** 2025-11-07
**Version:** Latest (auto-update enabled)
**Status:** Production
**Networks:** reverse_proxy, media_services

---

## Overview

Jellyfin is the **self-hosted media server** providing Netflix-like streaming of personal media libraries.

**Features enabled:**
- Hardware-accelerated transcoding (AMD GPU)
- HTTPS access via Traefik reverse proxy
- Automatic DNS (jellyfin.patriark.org)
- Health monitoring
- Organized media libraries (movies, music)

**External access:** https://jellyfin.patriark.org

---

## Quick Reference

### Access Points

- **Web UI:** https://jellyfin.patriark.org (external)
- **Local Access:** http://fedora-htpc.lokal:8096 or http://192.168.1.70:8096
- **Health Check:** http://localhost:8096/health

### Service Management

```bash
# Status
systemctl --user status jellyfin.service
podman ps | grep jellyfin

# Control
systemctl --user start jellyfin.service
systemctl --user stop jellyfin.service
systemctl --user restart jellyfin.service

# Logs
journalctl --user -u jellyfin.service -f
podman logs -f jellyfin

# Health check
podman healthcheck run jellyfin
curl http://localhost:8096/health
```

### Configuration Locations

```
~/containers/config/jellyfin/        # Configuration & metadata
/mnt/btrfs-pool/subvol7-containers/jellyfin/  # Library database
/mnt/btrfs-pool/subvol6-tmp/jellyfin-cache/   # Image cache
/mnt/btrfs-pool/subvol6-tmp/jellyfin-transcodes/  # Transcode temp files

# Media libraries (read-only)
/mnt/btrfs-pool/subvol4-multimedia/  # Movies, TV shows
/mnt/btrfs-pool/subvol5-music/       # Music library
```

---

## Architecture

### Storage Layout

**System Design:** Tiered storage for performance and capacity

```
System SSD (Fast, Limited)
├── config/jellyfin/           # Small config files (~200MB)
└── [No media here]

BTRFS Pool (Large, Archival)
├── subvol7-containers/jellyfin/  # Library database (~500MB)
├── subvol6-tmp/
│   ├── jellyfin-cache/           # Image cache (1-5GB)
│   └── jellyfin-transcodes/      # Temporary transcodes (0-20GB)
└── Media (Read-Only)
    ├── subvol4-multimedia/       # Video library (4+TB)
    └── subvol5-music/            # Music library (500+GB)
```

**Why this layout?**
- **Config on SSD:** Fast access to metadata and settings
- **Data on BTRFS:** Large library database doesn't fill system SSD
- **Cache on BTRFS:** Transcode temp files can be large
- **Media read-only:** Prevents accidental deletion/modification

### Network Topology

```
systemd-reverse_proxy (10.89.2.0/24)
├── Traefik (routes jellyfin.patriark.org → jellyfin:8096)
└── Jellyfin (exposed to internet via Traefik)

systemd-media_services (10.89.1.0/24)
└── Jellyfin (isolated network for future media services)
```

**Why two networks?**
- `reverse_proxy`: Required for Traefik to route traffic
- `media_services`: Isolated environment for media processing

### Hardware Transcoding

**GPU:** AMD integrated graphics `/dev/dri/renderD128`

**Benefits:**
- **Dramatically lower CPU usage** during transcoding
- **Faster transcoding** (real-time 4K → 1080p)
- **Multiple concurrent streams** without performance degradation

**Configuration:**
- Device passed through: `AddDevice=/dev/dri/renderD128`
- Enabled in Jellyfin: Dashboard → Playback → Hardware Acceleration
- Transcoding backend: VA-API (AMD/Intel)

---

## Configuration

### Initial Setup

**First-time access:**
1. Navigate to https://jellyfin.patriark.org
2. Create administrator account
3. Skip wizard (libraries added manually)

**Add media libraries:**
1. Dashboard → Libraries → Add Media Library
2. Content type: Movies / Music / TV Shows
3. Folders:
   - Movies: `/media/multimedia/`
   - Music: `/media/music/`
4. Save and scan

### Hardware Transcoding Setup

**Enable VA-API transcoding:**

1. Dashboard → Playback
2. Transcoding section:
   - Hardware acceleration: **Video Acceleration API (VA-API)**
   - VA-API Device: `/dev/dri/renderD128`
   - Enable hardware encoding: **✓**
   - Enable hardware decoding:
     - H264: ✓
     - HEVC: ✓
     - VP9: ✓
3. Save

**Verify transcoding:**
```bash
# During playback, check GPU usage
intel_gpu_top   # For Intel iGPU
radeontop       # For AMD GPU

# Check transcode logs
podman logs jellyfin | grep -i transcode
```

### Library Organization

**Recommended structure:**

```
/media/multimedia/
├── Movies/
│   ├── Movie Title (Year)/
│   │   └── Movie Title (Year).mkv
│   └── ...
└── TV Shows/
    ├── Show Name/
    │   ├── Season 01/
    │   │   ├── S01E01.mkv
    │   │   └── S01E02.mkv
    │   └── Season 02/
    └── ...

/media/music/
├── Artist/
│   └── Album/
│       └── 01 Track.flac
└── ...
```

**Jellyfin recognizes:**
- Movie naming: `Movie Title (Year).mkv`
- TV naming: `ShowName - S01E01.mkv` or `ShowName/Season 01/S01E01.mkv`
- Music: Standard `Artist/Album/Track` structure

---

## Operations

### Adding New Media

**1. Copy media to appropriate location:**
```bash
# Movies
cp "New Movie (2024).mkv" /mnt/btrfs-pool/subvol4-multimedia/Movies/

# TV Shows
mkdir -p "/mnt/btrfs-pool/subvol4-multimedia/TV Shows/Show Name/Season 01/"
cp S01E01.mkv "/mnt/btrfs-pool/subvol4-multimedia/TV Shows/Show Name/Season 01/"
```

**2. Trigger library scan:**
- Dashboard → Libraries → Click library → Scan Library
- Or wait for scheduled scan (can configure interval)

**3. Verify:**
- Browse library, new content should appear
- Check metadata fetched correctly
- Play to verify file works

### Managing Cache

**Cache grows over time** (image thumbnails, chapter images, etc.)

**Current size:**
```bash
du -sh /mnt/btrfs-pool/subvol6-tmp/jellyfin-cache/
```

**Clear cache:**
```bash
# Stop Jellyfin first
systemctl --user stop jellyfin.service

# Clear cache
rm -rf /mnt/btrfs-pool/subvol6-tmp/jellyfin-cache/*

# Restart
systemctl --user start jellyfin.service
```

**Jellyfin will rebuild cache** as content is accessed.

### Managing Transcodes

**Transcodes are temporary files** created during streaming.

**Location:** `/mnt/btrfs-pool/subvol6-tmp/jellyfin-transcodes/`

**Cleanup:**
- Jellyfin cleans up automatically after stream ends
- Old temp files may accumulate if streams interrupted

**Manual cleanup:**
```bash
# Safe to delete while Jellyfin running (only deletes old files)
find /mnt/btrfs-pool/subvol6-tmp/jellyfin-transcodes/ -type f -mtime +1 -delete
```

---

## Troubleshooting

### Playback Issues

**Video won't play:**

1. **Check codec support:**
   ```bash
   # View file info
   ffprobe "/path/to/video.mkv"

   # Common unsupported codecs: HEVC 10-bit, AV1
   # Solution: Enable transcoding or re-encode media
   ```

2. **Check transcode logs:**
   ```bash
   podman logs jellyfin | grep -i transcode | tail -20

   # Look for errors like:
   # - FFmpeg errors
   # - GPU initialization failures
   # - Permission denied on /dev/dri/renderD128
   ```

3. **Verify GPU access:**
   ```bash
   # From inside container
   podman exec jellyfin ls -la /dev/dri/
   # Should show renderD128 with appropriate permissions
   ```

**Buffering/stuttering:**

- Check network speed (Dashboard → Activity)
- Reduce streaming quality (Player settings)
- Verify hardware transcoding enabled and working
- Check server CPU usage: `htop`

### Hardware Transcoding Not Working

**Symptoms:**
- High CPU usage during playback
- Slow transcoding
- Player says "Transcoding..." for long time

**Diagnosis:**
```bash
# 1. Check GPU device accessible
podman exec jellyfin ls -la /dev/dri/renderD128

# 2. Check FFmpeg sees GPU
podman exec jellyfin /usr/lib/jellyfin-ffmpeg/ffmpeg -hwaccels
# Should list: vaapi

# 3. Check Jellyfin logs for VA-API errors
podman logs jellyfin | grep -i vaapi
```

**Solutions:**
- Verify `AddDevice=/dev/dri/renderD128` in quadlet
- Check SELinux context: `ls -lZ /dev/dri/renderD128`
- Restart container: `systemctl --user restart jellyfin.service`

### Library Scan Not Finding Media

**Check file permissions:**
```bash
# Jellyfin runs as UID 1000 inside container (maps to your user)
ls -la /mnt/btrfs-pool/subvol4-multimedia/
# Files should be readable by your user
```

**Check volume mounts:**
```bash
podman inspect jellyfin | grep -A 20 Mounts
# Verify /media/multimedia and /media/music mounted
```

**Force re-scan:**
1. Dashboard → Libraries → [Library] → Scan Library
2. Enable "Replace all metadata" if metadata corrupted

### Can't Access Externally

**Check Traefik routing:**
```bash
# 1. Verify Traefik sees Jellyfin
curl http://localhost:8080/api/http/services | grep jellyfin

# 2. Check Jellyfin network
podman inspect jellyfin | grep -A 5 Networks
# Must be on systemd-reverse_proxy

# 3. Test internal access
curl http://jellyfin:8096/health  # From another container
```

**Check DNS:**
```bash
# Verify domain resolves
nslookup jellyfin.patriark.org
# Should point to your public IP

# Check port forwarding
# Ports 80 and 443 must be forwarded to fedora-htpc
```

---

## Monitoring

### Health Checks

**Built-in health endpoint:**
```bash
curl http://localhost:8096/health
# Returns: {"status":"Healthy"}

# Podman health check (automatic)
podman healthcheck run jellyfin
# Returns: healthy
```

**Health check fails if:**
- Jellyfin web server not responding
- Application crashed
- Startup taking longer than 15 minutes

### Performance Monitoring

**Active streams:**
- Dashboard → Activity
- Shows all active playback sessions
- Displays transcode status, bandwidth, client info

**Resource usage:**
```bash
# Container stats
podman stats jellyfin

# Detailed metrics
curl http://localhost:8096/System/Info
```

**Metrics available:**
- Active streams count
- Transcode count
- Server CPU/RAM usage
- Library item counts

---

## Backup and Recovery

### What to Backup

**Critical (must backup):**
- `~/containers/config/jellyfin/` - Configuration and library database
- `/mnt/btrfs-pool/subvol7-containers/jellyfin/` - Library metadata

**Optional (can rebuild):**
- Cache and transcodes (regenerated automatically)
- Media files (presumably backed up separately)

**Not needed:**
- Container itself (recreate from quadlet)
- Logs (in journald)

### Backup Procedure

```bash
# 1. Stop Jellyfin (ensures consistent state)
systemctl --user stop jellyfin.service

# 2. Backup configuration
tar czf jellyfin-config-$(date +%Y%m%d).tar.gz \
  ~/containers/config/jellyfin/ \
  /mnt/btrfs-pool/subvol7-containers/jellyfin/

# 3. Restart Jellyfin
systemctl --user start jellyfin.service

# 4. Store backup off-host
rsync jellyfin-config-*.tar.gz backup-server:/backups/
```

**Automated:** Use `scripts/btrfs-snapshot-backup.sh` (backs up relevant subvolumes)

### Restore Procedure

```bash
# 1. Restore configuration
tar xzf jellyfin-config-YYYYMMDD.tar.gz -C /

# 2. Fix permissions if needed
chown -R $(id -u):$(id -g) ~/containers/config/jellyfin/
chown -R $(id -u):$(id -g) /mnt/btrfs-pool/subvol7-containers/jellyfin/

# 3. Restart service
systemctl --user restart jellyfin.service

# 4. Verify
curl http://localhost:8096/health
```

### Disaster Recovery

**Complete data loss scenario:**

1. **Restore quadlet:** `jellyfin.container` from git
2. **Restore config:** From backup
3. **Media files:** Restore from backup or re-add
4. **Restart service:**
   ```bash
   systemctl --user daemon-reload
   systemctl --user enable --now jellyfin.service
   ```
5. **Re-scan libraries:** Dashboard → Libraries → Scan All

**Metadata loss but media intact:**
- Just re-scan libraries
- Jellyfin will re-fetch metadata from online databases
- Watched status and custom metadata will be lost (unless backed up)

---

## Performance Tuning

### Transcoding Settings

**Optimize for your hardware:**

Dashboard → Playback:
- Thread count: Leave at 0 (auto-detect)
- Transcoding temp path: Current (`/config/transcodes` on BTRFS)
- H264 encoding preset: `medium` or `fast`
- Hardware acceleration: VA-API (already enabled)

**Throttle transcoding if CPU maxes out:**
- Encoding preset: `veryfast` (lower quality but less CPU)
- Max parallel transcodes: Limit to 2-3

### Cache Optimization

**Current:** Cache on BTRFS pool (plenty of space)

**If cache grows too large:**
1. Dashboard → Scheduled Tasks → "Scan Media Library"
2. Set image extraction options:
   - Extract chapter images: Disabled (saves space)
   - Save chapter images as jpg: Enabled (smaller than PNG)

### Library Scan Performance

**Large libraries take time to scan**

**Optimize:**
1. Dashboard → Libraries → [Library] → Library Options
2. Disable unnecessary features:
   - Extract chapter images during scan: No (do in background)
   - Download images in advance: No (fetch on demand)
3. Set scan interval appropriately:
   - Daily for actively updated libraries
   - Weekly for static libraries

---

## Security Considerations

### Authentication

**Currently:** Jellyfin's built-in authentication
- Create users in Dashboard → Users
- Set passwords (strong passwords recommended)
- Enable/disable guest access

**Future:** TinyAuth integration for SSO

### Network Exposure

**Current setup:**
- External access via HTTPS only (Traefik)
- Direct port 8096 exposed on LAN only
- No authentication on Traefik layer (Jellyfin handles auth)

**Considerations:**
- Add Traefik middleware authentication if sharing with untrusted users
- Use VPN for remote access (more secure than exposing to internet)

### User Permissions

**Jellyfin user types:**
- **Administrator:** Full access (you)
- **User:** Standard access (family/friends)
- **Guest:** Limited access

**Best practice:**
- Create separate users for each person
- Don't share administrator account
- Regular users can't change settings or access admin dashboard

---

## Upgrade Procedure

**Auto-update enabled** (`AutoUpdate=registry` in quadlet)

**Automatic upgrades:**
- Podman auto-update.timer checks daily
- Pulls new `jellyfin/jellyfin:latest` image
- Restarts container if new version available

**Manual upgrade:**
```bash
# 1. Pull latest image
podman pull docker.io/jellyfin/jellyfin:latest

# 2. Restart service
systemctl --user restart jellyfin.service

# 3. Verify new version
curl http://localhost:8096/System/Info/Public | grep Version
```

**Rollback if issues:**
```bash
# 1. Find previous image
podman images | grep jellyfin

# 2. Update quadlet to specific version
# Change: Image=docker.io/jellyfin/jellyfin:latest
# To: Image=docker.io/jellyfin/jellyfin:10.8.13

# 3. Restart
systemctl --user daemon-reload
systemctl --user restart jellyfin.service
```

---

## Related Documentation

- **Deployment log:** `docs/10-services/journal/2025-10-23-day04-jellyfin-deployment.md`
- **Traefik integration:** `docs/10-services/guides/traefik.md`
- **Storage architecture:** `docs/20-operations/guides/storage-layout.md`
- **Backup strategy:** `docs/20-operations/guides/backup-strategy.md`

---

## Common Commands

```bash
# Status and health
systemctl --user status jellyfin.service
podman healthcheck run jellyfin
curl http://localhost:8096/health

# Control
systemctl --user restart jellyfin.service
systemctl --user stop jellyfin.service
systemctl --user start jellyfin.service

# Logs
journalctl --user -u jellyfin.service -f
podman logs -f jellyfin | grep -i error

# Resource usage
podman stats jellyfin
htop  # Filter by 'jellyfin'

# Configuration
cd ~/containers/config/jellyfin/
cat config/system.xml  # Core configuration

# Library management
curl http://localhost:8096/Library/Refresh  # Trigger scan

# Clear cache
rm -rf /mnt/btrfs-pool/subvol6-tmp/jellyfin-cache/*
systemctl --user restart jellyfin.service

# Check GPU usage (during transcoding)
radeontop  # For AMD
intel_gpu_top  # For Intel
```

---

**Maintainer:** patriark
**Media Libraries:** Movies, TV Shows, Music
**Hardware Acceleration:** AMD VA-API enabled
**External URL:** https://jellyfin.patriark.org
