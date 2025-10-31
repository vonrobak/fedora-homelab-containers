#!/bin/bash
# Cloudflare Dynamic DNS Updater
set -euo pipefail

# Configuration
ZONE_ID=$(cat ~/containers/secrets/cloudflare_zone_id)
API_TOKEN=$(cat ~/containers/secrets/cloudflare_token)
DOMAIN="patriark.org"
RECORDS=("@" "*")  # Update both root and wildcard

# Get current public IP
CURRENT_IP=$(curl -s -4 ifconfig.me)

if [ -z "$CURRENT_IP" ]; then
    echo "ERROR: Could not determine public IP"
    exit 1
fi

# Function to update DNS record
update_record() {
    local record_name=$1
    local display_name="${record_name}"
    [ "$record_name" = "@" ] && display_name="$DOMAIN"
    [ "$record_name" = "*" ] && display_name="*.${DOMAIN}"
    
    # Get record ID
    RECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?type=A&name=${display_name}" \
        -H "Authorization: Bearer ${API_TOKEN}" \
        -H "Content-Type: application/json" | jq -r '.result[0].id')
    
    if [ "$RECORD_ID" = "null" ] || [ -z "$RECORD_ID" ]; then
        echo "ERROR: Could not find DNS record for ${display_name}"
        return 1
    fi
    
    # Update record
    RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${RECORD_ID}" \
        -H "Authorization: Bearer ${API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"A\",\"name\":\"${display_name}\",\"content\":\"${CURRENT_IP}\",\"ttl\":120,\"proxied\":false}")
    
    SUCCESS=$(echo $RESPONSE | jq -r '.success')
    
    if [ "$SUCCESS" = "true" ]; then
        echo "✓ Updated ${display_name} to ${CURRENT_IP}"
    else
        echo "✗ Failed to update ${display_name}"
        echo "$RESPONSE" | jq
    fi
}

# Update all records
for RECORD in "${RECORDS[@]}"; do
    update_record "$RECORD"
done

echo "DDNS update complete: $(date)"
