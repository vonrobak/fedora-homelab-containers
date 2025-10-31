#!/bin/bash
# Jellyfin Management Script

# Auto-detect which service name is active
if systemctl --user list-units --full --all | grep -q "jellyfin.service"; then
    SERVICE_NAME="jellyfin.service"
elif systemctl --user list-units --full --all | grep -q "container-jellyfin.service"; then
    SERVICE_NAME="container-jellyfin.service"
else
    SERVICE_NAME="jellyfin.service"  # default
fi

COMMAND=${1:-help}

case $COMMAND in
    start)
        echo "Starting Jellyfin..."
        systemctl --user start $SERVICE_NAME
        sleep 3
        echo ""
        systemctl --user status $SERVICE_NAME --no-pager | head -10
        echo ""
        echo "✓ Jellyfin started"
        echo "Access: http://jellyfin.lokal:8096"
        ;;
    
    stop)
        echo "Stopping Jellyfin..."
        systemctl --user stop $SERVICE_NAME
        sleep 2
        echo "✓ Jellyfin stopped"
        ;;
    
    restart)
        echo "Restarting Jellyfin..."
        systemctl --user restart $SERVICE_NAME
        sleep 3
        echo ""
        systemctl --user status $SERVICE_NAME --no-pager | head -10
        echo ""
        echo "✓ Jellyfin restarted"
        ;;
    
    status)
        if [ -x ~/containers/scripts/jellyfin-status.sh ]; then
            ~/containers/scripts/jellyfin-status.sh
        else
            echo "Status script not found, showing basic status:"
            systemctl --user status $SERVICE_NAME
        fi
        ;;
    
    logs)
        echo "Jellyfin logs (last 50 lines):"
        echo "═══════════════════════════════════════════════"
        journalctl --user -u $SERVICE_NAME -n 50 --no-pager 2>/dev/null || \
            podman logs jellyfin --tail 50 2>/dev/null || \
            echo "No logs available"
        ;;
    
    follow)
        echo "Following Jellyfin logs (Ctrl+C to exit):"
        echo "═══════════════════════════════════════════════"
        journalctl --user -u $SERVICE_NAME -f 2>/dev/null || \
            podman logs -f jellyfin 2>/dev/null || \
            echo "Cannot follow logs"
        ;;
    
    scan)
        echo "Triggering library scan..."
        echo "Use the web UI for library management:"
        echo "  Dashboard → Libraries → Scan All Libraries"
        echo ""
        echo "Access: http://jellyfin.lokal:8096"
        ;;
    
    clean-cache)
        echo "Cleaning Jellyfin cache..."
        if [ -d /mnt/btrfs-pool/subvol6-tmp/jellyfin-cache ]; then
            SIZE_BEFORE=$(du -sh /mnt/btrfs-pool/subvol6-tmp/jellyfin-cache 2>/dev/null | cut -f1)
            echo "Cache size before: $SIZE_BEFORE"
            
            rm -rf /mnt/btrfs-pool/subvol6-tmp/jellyfin-cache/*
            
            SIZE_AFTER=$(du -sh /mnt/btrfs-pool/subvol6-tmp/jellyfin-cache 2>/dev/null | cut -f1)
            echo "Cache size after: $SIZE_AFTER"
            echo "✓ Cache cleaned"
        else
            echo "Cache directory not found"
        fi
        ;;
    
    clean-transcodes)
        echo "Cleaning transcode directory..."
        if [ -d /mnt/btrfs-pool/subvol6-tmp/jellyfin-transcodes ]; then
            SIZE_BEFORE=$(du -sh /mnt/btrfs-pool/subvol6-tmp/jellyfin-transcodes 2>/dev/null | cut -f1)
            echo "Transcodes size before: $SIZE_BEFORE"
            
            rm -rf /mnt/btrfs-pool/subvol6-tmp/jellyfin-transcodes/*
            
            SIZE_AFTER=$(du -sh /mnt/btrfs-pool/subvol6-tmp/jellyfin-transcodes 2>/dev/null | cut -f1)
            echo "Transcodes size after: $SIZE_AFTER"
            echo "✓ Transcodes cleaned"
        else
            echo "Transcodes directory not found"
        fi
        ;;
    
    url)
        echo "Jellyfin Access URLs:"
        echo "═══════════════════════════════════════════════"
        echo "Local:          http://localhost:8096"
        echo "Network (DNS):  http://jellyfin.lokal:8096"
        echo "Network (Host): http://fedora-htpc.lokal:8096"
        echo "Network (IP):   http://192.168.1.70:8096"
        echo ""
        echo "Admin Dashboard: Menu → Dashboard"
        ;;
    
    help|*)
        echo "Jellyfin Management Script"
        echo "═══════════════════════════════════════════════"
        echo ""
        echo "Usage: $0 {command}"
        echo ""
        echo "Commands:"
        echo "  start          - Start Jellyfin service"
        echo "  stop           - Stop Jellyfin service"
        echo "  restart        - Restart Jellyfin service"
        echo "  status         - Show detailed status"
        echo "  logs           - Show recent logs (last 50 lines)"
        echo "  follow         - Follow logs in real-time"
        echo "  scan           - Library scan info"
        echo "  clean-cache    - Clean cache directory"
        echo "  clean-transcodes - Clean transcode directory"
        echo "  url            - Show access URLs"
        echo "  help           - Show this help message"
        echo ""
        echo "Current service: $SERVICE_NAME"
        echo ""
        echo "Examples:"
        echo "  $0 status      # Check if Jellyfin is running"
        echo "  $0 restart     # Restart after config changes"
        echo "  $0 logs        # View recent activity"
        ;;
esac
