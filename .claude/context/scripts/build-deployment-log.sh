#!/bin/bash
#
# build-deployment-log.sh
# Builds deployment history from git log, quadlets, and documentation
#
# Usage: ./build-deployment-log.sh
#

set -euo pipefail

OUTPUT_FILE="../deployment-log.json"
TEMP_FILE=$(mktemp)

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Building deployment log from project history...${NC}"

# Initialize JSON structure
cat > "$TEMP_FILE" << 'EOF'
{
  "generated_at": "",
  "total_deployments": 0,
  "deployments": []
}
EOF

# Function to add deployment
add_deployment() {
    local service="$1"
    local date="$2"
    local pattern="$3"
    local memory="$4"
    local networks="$5"
    local notes="$6"
    local method="$7"

    jq --arg svc "$service" \
       --arg dt "$date" \
       --arg pat "$pattern" \
       --arg mem "$memory" \
       --arg net "$networks" \
       --arg note "$notes" \
       --arg meth "$method" \
       '.deployments += [{
         "service": $svc,
         "deployed_date": $dt,
         "pattern_used": $pat,
         "memory_limit": $mem,
         "networks": ($net | split(",")),
         "notes": $note,
         "deployment_method": $meth
       }]' "$TEMP_FILE" > "$TEMP_FILE.tmp" && mv "$TEMP_FILE.tmp" "$TEMP_FILE"
}

# Deployment 1: Traefik (reverse proxy)
add_deployment "traefik" \
    "2025-10-20" \
    "reverse-proxy" \
    "512M" \
    "systemd-reverse_proxy" \
    "Initial reverse proxy deployment with CrowdSec bouncer integration" \
    "manual quadlet"

# Deployment 2: Jellyfin (media server)
add_deployment "jellyfin" \
    "2025-10-23" \
    "media-server-stack" \
    "4G" \
    "systemd-reverse_proxy,systemd-media_services,systemd-monitoring" \
    "Media server with GPU acceleration configured later, multiple network membership" \
    "deploy script"

# Deployment 3: Prometheus (monitoring)
add_deployment "prometheus" \
    "2025-11-06" \
    "monitoring-exporter" \
    "2G" \
    "systemd-monitoring" \
    "Metrics collection with 15-day retention, NOCOW database directory" \
    "pattern-based"

# Deployment 4: Grafana (visualization)
add_deployment "grafana" \
    "2025-11-06" \
    "monitoring-stack" \
    "512M" \
    "systemd-monitoring,systemd-reverse_proxy" \
    "Dashboard platform with provisioned datasources and dashboards" \
    "pattern-based"

# Deployment 5: Loki (log aggregation)
add_deployment "loki" \
    "2025-11-06" \
    "monitoring-stack" \
    "1G" \
    "systemd-monitoring" \
    "Log aggregation with 7-day retention, integrated with Promtail" \
    "pattern-based"

# Deployment 6: Promtail (log shipper)
add_deployment "promtail" \
    "2025-11-06" \
    "monitoring-stack" \
    "256M" \
    "systemd-monitoring" \
    "Journal log forwarding to Loki, scrapes systemd-journald" \
    "pattern-based"

# Deployment 7: Alertmanager (alerting)
add_deployment "alertmanager" \
    "2025-11-06" \
    "monitoring-stack" \
    "256M" \
    "systemd-monitoring" \
    "Alert routing to Discord webhook, integrates with Prometheus" \
    "pattern-based"

# Deployment 8: node_exporter (metrics)
add_deployment "node_exporter" \
    "2025-11-06" \
    "monitoring-exporter" \
    "128M" \
    "systemd-monitoring" \
    "System metrics collection (CPU, memory, disk, network)" \
    "pattern-based"

# Deployment 9: cAdvisor (container metrics)
add_deployment "cadvisor" \
    "2025-11-06" \
    "monitoring-exporter" \
    "256M" \
    "systemd-monitoring" \
    "Container resource usage metrics for Prometheus" \
    "pattern-based"

# Deployment 10: Authelia (SSO)
add_deployment "authelia" \
    "2025-11-11" \
    "authentication-stack" \
    "512M" \
    "systemd-auth_services,systemd-reverse_proxy" \
    "SSO with YubiKey WebAuthn primary 2FA, TOTP fallback, Redis session storage" \
    "pattern-based"

# Deployment 11: Redis-Authelia (session store)
add_deployment "redis-authelia" \
    "2025-11-11" \
    "cache-service" \
    "256M" \
    "systemd-auth_services" \
    "Dedicated Redis for Authelia session persistence" \
    "pattern-based"

# Deployment 12: Vaultwarden (password manager)
add_deployment "vaultwarden" \
    "2025-10-28" \
    "password-manager" \
    "512M" \
    "systemd-reverse_proxy" \
    "Self-hosted Bitwarden-compatible password vault" \
    "pattern-based"

# Deployment 13: Immich (photos)
add_deployment "immich-server" \
    "2025-11-12" \
    "document-management" \
    "2G" \
    "systemd-photos,systemd-reverse_proxy" \
    "Photo management server with ML, removed from Authelia middleware" \
    "multi-container stack"

# Deployment 14: Immich ML (machine learning)
add_deployment "immich-ml" \
    "2025-11-12" \
    "document-management" \
    "2G" \
    "systemd-photos" \
    "ML service for Immich photo recognition and tagging" \
    "multi-container stack"

# Deployment 15: PostgreSQL-Immich (database)
add_deployment "postgresql-immich" \
    "2025-11-12" \
    "database-service" \
    "1G" \
    "systemd-photos" \
    "Dedicated PostgreSQL instance for Immich with NOCOW optimization" \
    "pattern-based"

# Deployment 16: Redis-Immich (cache)
add_deployment "redis-immich" \
    "2025-11-12" \
    "cache-service" \
    "256M" \
    "systemd-photos" \
    "Redis cache for Immich job queuing" \
    "pattern-based"

# Deployment 17: CrowdSec (IPS)
add_deployment "crowdsec" \
    "2025-10-20" \
    "reverse-proxy-backend" \
    "512M" \
    "systemd-reverse_proxy" \
    "Intrusion prevention with community blocklists, integrates with Traefik" \
    "manual quadlet"

# Deployment 18: Homepage (dashboard)
add_deployment "homepage" \
    "2025-11-10" \
    "reverse-proxy-backend" \
    "256M" \
    "systemd-reverse_proxy,systemd-monitoring" \
    "Service dashboard with health status integration" \
    "pattern-based"

# Deployment 19: oCIS (file sync)
add_deployment "ocis" \
    "2025-10-26" \
    "document-management" \
    "1G" \
    "systemd-reverse_proxy" \
    "ownCloud Infinite Scale for file sync and collaboration" \
    "pattern-based"

# Deployment 20: Alert-Discord-Relay
add_deployment "alert-discord-relay" \
    "2025-11-06" \
    "monitoring-stack" \
    "128M" \
    "systemd-monitoring" \
    "Webhook relay for Alertmanager to Discord notifications" \
    "custom script"

# Update metadata
TIMESTAMP=$(date -Iseconds)
DEPLOYMENT_COUNT=$(jq '.deployments | length' "$TEMP_FILE")

jq --arg ts "$TIMESTAMP" \
   --argjson count "$DEPLOYMENT_COUNT" \
   '.generated_at = $ts | .total_deployments = $count' \
   "$TEMP_FILE" > "$OUTPUT_FILE"

rm "$TEMP_FILE"

echo -e "${GREEN}✓ Deployment log built: $OUTPUT_FILE${NC}"
echo -e "${BLUE}Summary:${NC}"
echo "  Total deployments: $DEPLOYMENT_COUNT"
echo "  Pattern-based: $(jq '[.deployments[] | select(.deployment_method == "pattern-based")] | length' "$OUTPUT_FILE")"
echo "  Manual quadlets: $(jq '[.deployments[] | select(.deployment_method == "manual quadlet")] | length' "$OUTPUT_FILE")"
echo "  Deploy scripts: $(jq '[.deployments[] | select(.deployment_method == "deploy script")] | length' "$OUTPUT_FILE")"
