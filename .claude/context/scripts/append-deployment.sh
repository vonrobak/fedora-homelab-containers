#!/bin/bash
#
# append-deployment.sh
# Append a single deployment to deployment-log.json
#
# Usage: ./append-deployment.sh <service> <date> <pattern> <memory> <networks> <notes> <method>
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_LOG="$SCRIPT_DIR/../deployment-log.json"
BACKUP_LOG="${DEPLOYMENT_LOG}.backup"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Validate arguments
if [ $# -lt 7 ]; then
    echo -e "${RED}Error: Insufficient arguments${NC}"
    echo "Usage: $0 <service> <date> <pattern> <memory> <networks> <notes> <method>"
    echo ""
    echo "Example:"
    echo "  $0 'jellyfin' '2025-11-30' 'media-server-stack' '4G' 'reverse_proxy,media_services' 'Auto-logged deployment' 'pattern-based'"
    exit 1
fi

SERVICE="$1"
DATE="$2"
PATTERN="$3"
MEMORY="$4"
NETWORKS="$5"
NOTES="$6"
METHOD="$7"

# Validate deployment log exists
if [ ! -f "$DEPLOYMENT_LOG" ]; then
    echo -e "${RED}Error: deployment-log.json not found at $DEPLOYMENT_LOG${NC}"
    exit 1
fi

# Create backup
cp "$DEPLOYMENT_LOG" "$BACKUP_LOG"

# Check if service already exists in log (within last 24 hours to prevent duplicates)
EXISTING=$(jq -r --arg svc "$SERVICE" --arg date "$DATE" '
  .deployments[] |
  select(.service == $svc and .deployed_date == $date) |
  .service
' "$DEPLOYMENT_LOG" | head -1)

if [ -n "$EXISTING" ]; then
    echo -e "${YELLOW}⚠ Deployment for '$SERVICE' on '$DATE' already exists, skipping duplicate${NC}"
    rm "$BACKUP_LOG"
    exit 0
fi

# Append deployment entry
jq --arg svc "$SERVICE" \
   --arg dt "$DATE" \
   --arg pat "$PATTERN" \
   --arg mem "$MEMORY" \
   --arg net "$NETWORKS" \
   --arg note "$NOTES" \
   --arg meth "$METHOD" \
   '
   .deployments += [{
     "service": $svc,
     "deployed_date": $dt,
     "pattern_used": $pat,
     "memory_limit": $mem,
     "networks": ($net | split(",")),
     "notes": $note,
     "deployment_method": $meth
   }] |
   .total_deployments = (.deployments | length) |
   .generated_at = (now | todate)
   ' "$DEPLOYMENT_LOG" > "${DEPLOYMENT_LOG}.tmp"

# Verify the output is valid JSON
if jq empty "${DEPLOYMENT_LOG}.tmp" 2>/dev/null; then
    mv "${DEPLOYMENT_LOG}.tmp" "$DEPLOYMENT_LOG"
    rm "$BACKUP_LOG"
    echo -e "${GREEN}✓ Added deployment: $SERVICE ($METHOD)${NC}"
    echo -e "  Date: $DATE"
    echo -e "  Pattern: $PATTERN"
    echo -e "  Memory: $MEMORY"
    echo -e "  Networks: $NETWORKS"
else
    echo -e "${RED}Error: Generated invalid JSON, restoring backup${NC}"
    mv "$BACKUP_LOG" "$DEPLOYMENT_LOG"
    rm -f "${DEPLOYMENT_LOG}.tmp"
    exit 1
fi
