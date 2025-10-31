#!/bin/bash
set -euo pipefail

echo "🎬 Deploying Jellyfin with Traefik integration..."

# Stop existing service
echo "📦 Stopping existing Jellyfin..."
systemctl --user stop jellyfin.service 2>/dev/null || true

# Remove old container (data is safe on host)
podman rm -f jellyfin 2>/dev/null || true

# Ensure Jellyfin is on both networks
# media_services: for potential future media processing containers
# reverse_proxy: for Traefik communication
if ! podman network exists media_services; then
    podman network create media_services \
        --subnet 10.89.1.0/24 \
        --dns 192.168.1.69
fi

if ! podman network exists reverse_proxy; then
    podman network create reverse_proxy \
        --subnet 10.89.2.0/24 \
        --dns 192.168.1.69
fi

echo "✓ Networks verified"

# Deploy Jellyfin with Traefik labels
echo "🚀 Creating new Jellyfin container..."
podman run -d \
  --name jellyfin \
  --hostname jellyfin \
  --network media_services \
  --network reverse_proxy \
  --publish 8096:8096 \
  --publish 7359:7359/udp \
  --device /dev/dri/renderD128:/dev/dri/renderD128 \
  --env TZ=Europe/Oslo \
  --env JELLYFIN_PublishedServerUrl=https://jellyfin.lokal \
  --volume ~/containers/config/jellyfin:/config:Z \
  --volume /mnt/btrfs-pool/subvol6-tmp/jellyfin-cache:/cache:Z \
  --volume /mnt/btrfs-pool/subvol6-tmp/jellyfin-transcodes:/config/transcodes:Z \
  --volume /mnt/btrfs-pool/subvol4-multimedia:/media/multimedia:ro,Z \
  --volume /mnt/btrfs-pool/subvol5-music:/media/music:ro,Z \
  --dns 192.168.1.69 \
  --dns-search lokal \
  --label "traefik.enable=true" \
  --label "traefik.http.routers.jellyfin.rule=Host(\`jellyfin.lokal\`)" \
  --label "traefik.http.routers.jellyfin.entrypoints=websecure" \
  --label "traefik.http.routers.jellyfin.tls=true" \
  --label "traefik.http.services.jellyfin.loadbalancer.server.port=8096" \
  --label "traefik.http.routers.jellyfin.middlewares=security-headers@file" \
  --label "traefik.docker.network=reverse_proxy" \
  --restart unless-stopped \
  docker.io/jellyfin/jellyfin:latest

echo "✓ Jellyfin container created"

# Regenerate systemd service
echo "📝 Generating systemd service..."
cd ~/.config/systemd/user
podman generate systemd --name jellyfin --files --new --restart-policy=on-failure

# Reload systemd
systemctl --user daemon-reload
echo "✓ Systemd service updated"

# Enable and start
systemctl --user enable jellyfin.service
systemctl --user start jellyfin.service
echo "✓ Service enabled and started"

# Wait for healthy
echo "⏳ Waiting for Jellyfin to be healthy..."
for i in {1..30}; do
    if podman healthcheck run jellyfin > /dev/null 2>&1; then
        echo "✓ Jellyfin is healthy!"
        break
    fi
    sleep 2
done

# Show status
echo ""
echo "📊 Status:"
podman ps | grep jellyfin
echo ""

echo "🌐 Access URLs:"
echo "  Direct:  http://jellyfin.lokal:8096"
echo "  Traefik: https://jellyfin.lokal (⚠️  Self-signed cert warning)"
echo ""

echo "🔍 Traefik Dashboard:"
echo "  http://traefik.lokal:8080/dashboard/"
echo "  Look for 'jellyfin@docker' router"
echo ""

echo "✅ Deployment complete!"
