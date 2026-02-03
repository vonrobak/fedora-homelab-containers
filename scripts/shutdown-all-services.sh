#!/bin/bash
# Complete shutdown of all homelab services

set -euo pipefail

echo "=== Shutting down all homelab services ==="
echo

# Stop all container services
SERVICES=(
    traefik
    home-assistant
    jellyfin
    immich-server
    immich-ml
    nextcloud
    nextcloud-db
    nextcloud-redis
    grafana
    prometheus
    alertmanager
    loki
    promtail
    authelia
    redis-authelia
    vaultwarden
    crowdsec
    homepage
    gathio
    gathio-db
    collabora
    postgresql-immich
    redis-immich
    node_exporter
    cadvisor
    unpoller
    matter-server
    alert-discord-relay
)

for svc in "${SERVICES[@]}"; do
    echo "Stopping $svc..."
    systemctl --user stop "$svc.service" 2>/dev/null || echo "  (already stopped or not found)"
done

echo
echo "=== All services stopped ==="
echo "Containers will not auto-restart until you manually start them"
echo
echo "To restart everything later:"
echo "  systemctl --user start traefik.service"
echo "  (other services will auto-start via dependencies)"
