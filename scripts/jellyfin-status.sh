#!/bin/bash
echo "═══════════════════════════════════════════════"
echo "           JELLYFIN STATUS REPORT"
echo "═══════════════════════════════════════════════"
echo "Generated: $(date)"
echo ""

# Auto-detect service name
if systemctl --user is-active jellyfin.service >/dev/null 2>&1; then
    SERVICE_NAME="jellyfin.service"
elif systemctl --user is-active container-jellyfin.service >/dev/null 2>&1; then
    SERVICE_NAME="container-jellyfin.service"
else
    SERVICE_NAME="jellyfin.service"  # default
fi

echo "━━━ SYSTEMD SERVICE ━━━"
systemctl --user status $SERVICE_NAME --no-pager 2>/dev/null | head -12 || echo "Service not found"

echo ""
echo "━━━ CONTAINER INFO ━━━"
if podman ps 2>/dev/null | grep -q jellyfin; then
    echo "Status: Running ✓"
    podman ps --filter name=jellyfin --format "Uptime: {{.Status}}"
    podman ps --filter name=jellyfin --format "Ports: {{.Ports}}"
    
    # Get IP address
    IP=$(podman inspect jellyfin 2>/dev/null | jq -r '.[].NetworkSettings.Networks.media_services.IPAddress')
    echo "IP Address: $IP"
    
    # Resource usage
    echo ""
    echo "Resource Usage:"
    podman stats jellyfin --no-stream --format "  CPU: {{.CPUPerc}}\t Memory: {{.MemUsage}}" 2>/dev/null || echo "  (stats unavailable)"
else
    echo "Status: NOT RUNNING ✗"
fi

echo ""
echo "━━━ STORAGE USAGE ━━━"
if [ -d ~/containers/config/jellyfin ]; then
    echo "Config: $(du -sh ~/containers/config/jellyfin 2>/dev/null | cut -f1)"
else
    echo "Config: Not found"
fi

if [ -d /mnt/btrfs-pool/subvol6-tmp/jellyfin-cache ]; then
    echo "Cache: $(du -sh /mnt/btrfs-pool/subvol6-tmp/jellyfin-cache 2>/dev/null | cut -f1)"
else
    echo "Cache: Not found"
fi

if [ -d /mnt/btrfs-pool/subvol6-tmp/jellyfin-transcodes ]; then
    echo "Transcodes: $(du -sh /mnt/btrfs-pool/subvol6-tmp/jellyfin-transcodes 2>/dev/null | cut -f1)"
else
    echo "Transcodes: Not found"
fi

echo ""
echo "━━━ MEDIA LIBRARIES ━━━"
if [ -d /mnt/btrfs-pool/subvol4-multimedia ]; then
    echo "Multimedia: /mnt/btrfs-pool/subvol4-multimedia"
    echo "  Items: $(find /mnt/btrfs-pool/subvol4-multimedia -type f 2>/dev/null | wc -l)"
else
    echo "Multimedia: Not found"
fi

if [ -d /mnt/btrfs-pool/subvol5-music ]; then
    echo "Music: /mnt/btrfs-pool/subvol5-music"
    echo "  Items: $(find /mnt/btrfs-pool/subvol5-music -type f 2>/dev/null | wc -l)"
else
    echo "Music: Not found"
fi

echo ""
echo "━━━ ACCESS URLs ━━━"
echo "Local:     http://localhost:8096"
echo "LAN:       http://jellyfin.lokal:8096"
echo "           http://fedora-htpc.lokal:8096"
echo "           http://192.168.1.70:8096"

echo ""
echo "━━━ HEALTH CHECK ━━━"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8096 2>/dev/null)
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
    echo "✓ Jellyfin is responding (HTTP $HTTP_CODE)"
else
    echo "✗ Jellyfin is not responding (HTTP ${HTTP_CODE:-000})"
fi

echo ""
echo "━━━ HARDWARE ACCELERATION ━━━"
if [ -e /dev/dri/renderD128 ]; then
    echo "✓ AMD GPU available: /dev/dri/renderD128"
    
    if podman exec jellyfin ls /dev/dri/renderD128 >/dev/null 2>&1; then
        echo "✓ GPU accessible from container"
    else
        echo "✗ GPU not accessible from container"
    fi
else
    echo "✗ GPU device not found"
fi

echo ""
echo "━━━ RECENT ACTIVITY (Last 5 log lines) ━━━"
if podman ps | grep -q jellyfin; then
    podman logs jellyfin --tail 5 2>/dev/null | sed 's/^/  /' || echo "  (logs unavailable)"
else
    echo "  Container not running"
fi

echo ""
echo "═══════════════════════════════════════════════"
