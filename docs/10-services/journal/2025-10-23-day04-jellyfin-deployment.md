# Day 4: Jellyfin Media Server - Final Documentation

**Deployment Date:** $(date +"%Y-%m-%d")
**Status:** Production - Fully Operational ✓

## Quick Reference

### Access URLs
- **Primary:** http://jellyfin.lokal:8096
- **Alternate:** http://fedora-htpc.lokal:8096
- **Direct IP:** http://192.168.1.70:8096
- **Localhost:** http://localhost:8096

### Management Commands
```bash
# Quick status
~/containers/scripts/jellyfin-manage.sh status

# Start/Stop/Restart
~/containers/scripts/jellyfin-manage.sh start
~/containers/scripts/jellyfin-manage.sh stop
~/containers/scripts/jellyfin-manage.sh restart

# View logs
~/containers/scripts/jellyfin-manage.sh logs
~/containers/scripts/jellyfin-manage.sh follow

# Maintenance
~/containers/scripts/jellyfin-manage.sh clean-cache
~/containers/scripts/jellyfin-manage.sh clean-transcodes

# Show URLs
~/containers/scripts/jellyfin-manage.sh url
```

### Systemd Commands
```bash
# Service management
systemctl --user status jellyfin.service
systemctl --user restart jellyfin.service
systemctl --user stop jellyfin.service
systemctl --user start jellyfin.service

# View logs
journalctl --user -u jellyfin.service -f
journalctl --user -u jellyfin.service -n 100
```

---

## Service Configuration

### Service Name
**Current:** `jellyfin.service` (migrated from `container-jellyfin.service`)

### Service Type
**Generated systemd service** (not Quadlet - that's optional for future)

### Service Files
- **Active:** `~/.config/systemd/user/jellyfin.service`
- **Old (can be removed):** `~/.config/systemd/user/container-jellyfin.service`

### Auto-Start Configuration
- **Enabled:** Yes ✓
- **User linger:** Enabled ✓
- **Starts on boot:** Yes ✓
- **Runs when logged out:** Yes ✓

### Restart Policy
- **Policy:** `Restart=on-failure`
- **Tested:** Yes ✓ (auto-restarts within 5-10 seconds)

---

## Container Configuration

### Basic Info
- **Container Name:** jellyfin
- **Image:** docker.io/jellyfin/jellyfin:latest
- **Network:** media_services (10.89.1.0/24)
- **Hostname:** jellyfin

### Published Ports
- **8096/tcp** - Web interface (HTTP)
- **7359/udp** - Service discovery (DLNA)

### Environment Variables
- `TZ=Europe/Oslo`
- `JELLYFIN_PublishedServerUrl=http://jellyfin.lokal:8096`

### DNS Configuration
- **DNS Server:** 192.168.1.69 (Pi-hole)
- **Search Domain:** lokal

---

## Storage Configuration

### Volume Mounts

#### Config (Fast SSD)
```
Host: ~/containers/config/jellyfin
Container: /config
SELinux: :Z
```
**Contents:**
- Server configuration
- User accounts and preferences
- Library metadata and artwork
- Watch history
- Plugins

**Size:** ~200-500 MB (grows with library)
**Backup Priority:** CRITICAL ⭐⭐⭐

#### Cache (BTRFS Pool)
```
Host: /mnt/btrfs-pool/subvol6-tmp/jellyfin-cache
Container: /cache
SELinux: :Z
```
**Contents:**
- Image cache
- Download cache
- Temporary files

**Size:** ~1-5 GB
**Backup Priority:** Not needed (regenerates)

#### Transcodes (BTRFS Pool)
```
Host: /mnt/btrfs-pool/subvol6-tmp/jellyfin-transcodes
Container: /config/transcodes
SELinux: :Z
```
**Contents:**
- Active transcoding files
- Temporary video conversions

**Size:** 0-20 GB (during active transcoding)
**Backup Priority:** Not needed (temporary)

#### Media - Multimedia (BTRFS Pool, Read-Only)
```
Host: /mnt/btrfs-pool/subvol4-multimedia
Container: /media/multimedia
Permissions: :ro,Z (read-only)
```
**Contents:** Movies, TV shows, videos
**Backup:** Via BTRFS snapshots (separate system)

#### Media - Music (BTRFS Pool, Read-Only)
```
Host: /mnt/btrfs-pool/subvol5-music
Container: /media/music
Permissions: :ro,Z (read-only)
```
**Contents:** Music library
**Backup:** Via BTRFS snapshots (separate system)

---

## Hardware Acceleration

### GPU Configuration
- **Hardware:** AMD Ryzen 5 5600G (Radeon Graphics)
- **Method:** VA-API (Video Acceleration API)
- **Device:** /dev/dri/renderD128
- **Status:** Enabled and working ✓

### Jellyfin Configuration
**Location:** Dashboard → Playback → Hardware Acceleration

**Settings:**
- Hardware acceleration: **Video Acceleration API (VAAPI)**
- VA-API Device: **/dev/dri/renderD128**
- Enable hardware decoding for:
  - ✓ H264
  - ✓ HEVC
  - ✓ VP9
  - (others as needed)

### Performance Impact
- **CPU usage (transcoding):** 10-20% (vs 80-100% software)
- **Transcoding speed:** Real-time or faster
- **Simultaneous streams:** 3-5+ depending on resolution
- **Power consumption:** Lower (GPU is more efficient)

---

## Network Configuration

### Firewall Rules
```bash
# Ports opened
sudo firewall-cmd --list-ports | grep -E '8096|7359'

# Should show:
# 8096/tcp 7359/udp
```

**Service group:** homelab-containers (ports 8080-8099/tcp already covered 8096)

### DNS Records (Pi-hole @ 192.168.1.69)
```
jellyfin.lokal → 192.168.1.70
media.lokal → 192.168.1.70 (alias)
fedora-htpc.lokal → 192.168.1.70
```

### Network Access Matrix
| From | To | Method | Works |
|------|----|---------| ------|
| Host | Jellyfin | localhost:8096 | ✓ |
| LAN (MacBook) | Jellyfin | jellyfin.lokal:8096 | ✓ |
| LAN (iPad) | Jellyfin | jellyfin.lokal:8096 | ✓ |
| Container (same network) | Jellyfin | jellyfin:8096 | ✓ |
| Internet | Jellyfin | Not configured | ✗ |

---

## Management Scripts

### jellyfin-status.sh
**Location:** `~/containers/scripts/jellyfin-status.sh`

**Purpose:** Comprehensive status report

**Output includes:**
- Systemd service status
- Container status and uptime
- Resource usage (CPU, memory)
- Storage usage (config, cache, transcodes)
- Media library item counts
- Access URLs
- Health check (HTTP response)
- Hardware acceleration status
- Recent log entries

**Usage:**
```bash
~/containers/scripts/jellyfin-status.sh
```

### jellyfin-manage.sh
**Location:** `~/containers/scripts/jellyfin-manage.sh`

**Purpose:** Service management and maintenance

**Commands:**
- `start` - Start Jellyfin service
- `stop` - Stop Jellyfin service
- `restart` - Restart Jellyfin service
- `status` - Show detailed status (calls jellyfin-status.sh)
- `logs` - Show recent logs (last 50 lines)
- `follow` - Follow logs in real-time
- `scan` - Info about library scanning
- `clean-cache` - Clean cache directory
- `clean-transcodes` - Clean transcode directory
- `url` - Show access URLs
- `help` - Show help message

**Features:**
- Auto-detects service name (jellyfin.service or container-jellyfin.service)
- Error handling for missing directories
- Shows before/after sizes for cleanup operations

**Usage:**
```bash
# Examples
~/containers/scripts/jellyfin-manage.sh status
~/containers/scripts/jellyfin-manage.sh restart
~/containers/scripts/jellyfin-manage.sh logs
~/containers/scripts/jellyfin-manage.sh clean-cache
```

---

## Backup Strategy

### What to Backup

#### Critical (Must Backup)
✅ **~/containers/config/jellyfin**
- Contains: All user data, settings, metadata, watch history
- Frequency: Daily
- Method: Automated backup script (Week 7)
- Backup size: ~500 MB

#### Optional (Can Regenerate)
❌ Cache directory - Regenerates automatically
❌ Transcode directory - Temporary files only

#### Separate Backup System
❌ Media files - Handled by BTRFS snapshots to external drive

### Backup Commands
```bash
# Manual backup
tar -czf ~/containers/backups/jellyfin-config-$(date +%Y%m%d).tar.gz \
  ~/containers/config/jellyfin

# Automated backup (will be set up in Week 7)
```

### Restore Procedure
```bash
# Stop service
systemctl --user stop jellyfin.service

# Restore config
tar -xzf ~/containers/backups/jellyfin-config-YYYYMMDD.tar.gz -C ~/

# Start service
systemctl --user start jellyfin.service

# Verify
~/containers/scripts/jellyfin-manage.sh status
```

---

## Troubleshooting

### Service Won't Start

**Check service status:**
```bash
systemctl --user status jellyfin.service
journalctl --user -u jellyfin.service -n 50
```

**Common causes:**
- Container failed to start (check: `podman ps -a`)
- Port already in use (check: `ss -tlnp | grep 8096`)
- Volume permission issues (check: `ls -la ~/containers/config/jellyfin`)
- SELinux blocking (check: `sudo ausearch -m avc -ts recent`)

**Fix:**
```bash
# Restart service
systemctl --user restart jellyfin.service

# If still failing, check container logs
podman logs jellyfin

# Nuclear option: recreate container
systemctl --user stop jellyfin.service
podman rm -f jellyfin
systemctl --user start jellyfin.service
```

### Hardware Acceleration Not Working

**Symptoms:**
- High CPU usage during playback
- Slow transcoding
- Stuttering video

**Diagnosis:**
```bash
# Check GPU is accessible
ls -la /dev/dri/renderD128

# Check container can see GPU
podman exec jellyfin ls -la /dev/dri/

# Check user is in video group
groups | grep video
```

**Fix:**
```bash
# Add user to video group
sudo usermod -aG video $USER

# Logout and login again, then restart service
systemctl --user restart jellyfin.service

# Verify in Jellyfin Dashboard → Playback → Hardware Acceleration
```

### Web UI Not Accessible

**Diagnosis:**
```bash
# Check service is running
systemctl --user is-active jellyfin.service

# Check container is running
podman ps | grep jellyfin

# Check port is listening
podman exec jellyfin ss -tlnp | grep 8096

# Check firewall
sudo firewall-cmd --list-ports | grep 8096

# Check DNS
nslookup jellyfin.lokal
```

**Fix:**
```bash
# Ensure firewall allows port
sudo firewall-cmd --add-port=8096/tcp --permanent
sudo firewall-cmd --reload

# Test locally first
curl -I http://localhost:8096

# If works locally but not remotely, it's a network/firewall issue
```

### High CPU Usage (Idle)

**Causes:**
- Library scanning in progress
- Generating thumbnails
- Plugin running background task

**Check:**
```bash
# View what Jellyfin is doing
podman logs jellyfin --tail 100 | grep -i "scan\|task\|thumbnail"

# Check in web UI
# Dashboard → Dashboard → Active Tasks
```

### Storage Full

**Check storage:**
```bash
~/containers/scripts/jellyfin-manage.sh status

# Or manually
du -sh ~/containers/config/jellyfin
du -sh /mnt/btrfs-pool/subvol6-tmp/jellyfin-cache
du -sh /mnt/btrfs-pool/subvol6-tmp/jellyfin-transcodes
```

**Clean up:**
```bash
# Clean cache
~/containers/scripts/jellyfin-manage.sh clean-cache

# Clean transcodes
~/containers/scripts/jellyfin-manage.sh clean-transcodes

# If config directory is huge, check for old logs
du -sh ~/containers/config/jellyfin/log
rm ~/containers/config/jellyfin/log/*.log.*  # Keep only current logs
```

---

## Performance Tuning

### Resource Usage Targets

**Idle:**
- CPU: 1-3%
- Memory: 200-400 MB
- Disk I/O: Minimal

**Active Streaming (with GPU):**
- CPU: 10-20%
- Memory: 400-800 MB
- GPU: 40-80%

**Active Streaming (without GPU):**
- CPU: 60-90%
- Memory: 800-1200 MB

### Optimization Tips

1. **Enable hardware acceleration** (already done ✓)
2. **Disable unused plugins** (Dashboard → Plugins)
3. **Limit library scan frequency** (Dashboard → Scheduled Tasks)
4. **Use appropriate transcoding settings** (Dashboard → Playback)
5. **Clean cache regularly** (monthly)

---

## Migration Notes (Day 4)

### What Was Migrated
- Service name: `container-jellyfin.service` → `jellyfin.service`
- Service file: Copied and renamed
- Old service: Disabled
- New service: Enabled

### What Was NOT Changed
- Container (kept running throughout)
- All data and configuration (fully preserved)
- Library metadata and scans (100% intact)
- Network configuration (unchanged)
- Volume mounts (unchanged)

### Migration Result
✅ Zero downtime
✅ All data preserved
✅ Library scan intact
✅ Watch history preserved
✅ User accounts unchanged
✅ Settings maintained

---

## Future Enhancements (Week 2+)

### Week 2: Secure Access
- [ ] Deploy Caddy reverse proxy
- [ ] Enable HTTPS with SSL certificates
- [ ] Add Authelia with YubiKey 2FA
- [ ] Access via: https://jellyfin.yourhomelab.com

### Later Improvements
- [ ] Remote access via WireGuard VPN
- [ ] Automated library updates
- [ ] Webhook notifications (Discord/Slack)
- [ ] Advanced monitoring (Prometheus/Grafana)
- [ ] Content request system (Overseerr)

---

## Systems Design Concepts Applied

✅ **Stateful Service Management** - Persistent config, ephemeral cache
✅ **Storage Tiering** - Fast SSD for config, large pool for cache, separate media
✅ **Hardware Passthrough** - GPU device for transcoding acceleration
✅ **Process Supervision** - Systemd manages container lifecycle
✅ **Service Isolation** - Rootless container, dedicated network
✅ **DNS Integration** - Pi-hole for local name resolution
✅ **Security Layers** - SELinux contexts, read-only mounts, firewall rules, rootless
✅ **Observability** - Comprehensive logging and status monitoring
✅ **Maintainability** - Management scripts, documentation, backup strategy
✅ **Reliability** - Auto-restart on failure, tested disaster recovery

---

## Lessons Learned

### What Worked Well
- Separating config (SSD) from cache (HDD) improved performance
- Hardware transcoding made a huge difference (80% CPU reduction)
- Read-only media mounts prevent accidental deletion
- Management scripts make daily operations simple
- Migration with zero downtime preserved all user data

### What to Remember
- Library scans are CPU/network intensive (normal, one-time cost)
- GPU must be accessible to container (device passthrough)
- SELinux contexts (:Z flag) are critical for volume mounts
- Service naming matters for clarity and future maintenance
- Always test auto-restart functionality

### Best Practices Established
- Document everything as you build
- Create management scripts early
- Test failure scenarios before declaring "done"
- Keep data separate from application (containers are disposable)
- Use meaningful DNS names (jellyfin.lokal vs IP addresses)

---

## Admin Account

**Username:** patriark
**Access:** Dashboard via menu → Dashboard

---

**Last Updated:** $(date +"%Y-%m-%d %H:%M:%S")
**Status:** Production ✓
**Uptime Target:** 99.9% (monitored from Week 5)
