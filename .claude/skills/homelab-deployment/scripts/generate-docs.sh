#!/usr/bin/env bash
# Documentation generator
# Auto-generates service documentation from templates

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATE_DIR="$SKILL_DIR/templates/documentation"

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

usage() {
    cat << 'USAGE'
Usage: generate-docs.sh [OPTIONS]

Options:
  --service NAME          Service name (required)
  --type TYPE             Document type: guide, journal (required)
  --output PATH           Output file path (required)
  
  # Service configuration
  --description TEXT      Service description
  --purpose TEXT          Service purpose
  --image TEXT            Container image
  --memory TEXT           Memory limit
  --networks TEXT         Comma-separated networks
  --config-dir PATH       Configuration directory
  --data-dir PATH         Data directory
  
  # Traefik configuration
  --hostname TEXT         External hostname
  --middleware TEXT       Traefik middleware chain
  --public                Service is public (no auth)
  
  # Monitoring
  --metrics-port PORT     Prometheus metrics port
  --metrics-path PATH     Prometheus metrics path
  
  --help                  Show this help message

Examples:
  # Generate service guide
  generate-docs.sh \
    --service jellyfin \
    --type guide \
    --output docs/10-services/guides/jellyfin.md \
    --description "Media server for movies and TV shows" \
    --image "docker.io/jellyfin/jellyfin:latest" \
    --hostname "jellyfin.patriark.org"

  # Generate deployment journal
  generate-docs.sh \
    --service vaultwarden \
    --type journal \
    --output docs/10-services/journal/2025-11-14-vaultwarden-deployment.md \
    --description "Password manager"

USAGE
    exit 0
}

# Parse arguments
SERVICE_NAME=""
DOC_TYPE=""
OUTPUT_PATH=""
DESCRIPTION=""
PURPOSE=""
IMAGE=""
MEMORY="1G"
NETWORKS=""
CONFIG_DIR=""
DATA_DIR=""
HOSTNAME=""
MIDDLEWARE=""
PUBLIC=false
METRICS_PORT=""
METRICS_PATH="/metrics"

while [[ $# -gt 0 ]]; do
    case $1 in
        --service) SERVICE_NAME="$2"; shift 2 ;;
        --type) DOC_TYPE="$2"; shift 2 ;;
        --output) OUTPUT_PATH="$2"; shift 2 ;;
        --description) DESCRIPTION="$2"; shift 2 ;;
        --purpose) PURPOSE="$2"; shift 2 ;;
        --image) IMAGE="$2"; shift 2 ;;
        --memory) MEMORY="$2"; shift 2 ;;
        --networks) NETWORKS="$2"; shift 2 ;;
        --config-dir) CONFIG_DIR="$2"; shift 2 ;;
        --data-dir) DATA_DIR="$2"; shift 2 ;;
        --hostname) HOSTNAME="$2"; shift 2 ;;
        --middleware) MIDDLEWARE="$2"; shift 2 ;;
        --public) PUBLIC=true; shift ;;
        --metrics-port) METRICS_PORT="$2"; shift 2 ;;
        --metrics-path) METRICS_PATH="$2"; shift 2 ;;
        --help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

# Validate required arguments
if [[ -z "$SERVICE_NAME" || -z "$DOC_TYPE" || -z "$OUTPUT_PATH" ]]; then
    log_error "Missing required arguments"
    usage
fi

# Set defaults
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
DEPLOYMENT_DATE=$(date '+%Y-%m-%d')
[[ -z "$CONFIG_DIR" ]] && CONFIG_DIR="~/containers/config/${SERVICE_NAME}"
[[ -z "$DATA_DIR" ]] && DATA_DIR="~/containers/data/${SERVICE_NAME}"
[[ -z "$DESCRIPTION" ]] && DESCRIPTION="Service: $SERVICE_NAME"
[[ -z "$PURPOSE" ]] && PURPOSE="$DESCRIPTION"

# Determine auth requirement
AUTH_REQUIRED=true
if [[ "$PUBLIC" == true ]]; then
    AUTH_REQUIRED=false
fi

# Determine monitoring
MONITORING=false
if [[ -n "$METRICS_PORT" ]]; then
    MONITORING=true
fi

# Determine Traefik enablement
TRAEFIK_ENABLED=false
if [[ -n "$HOSTNAME" ]]; then
    TRAEFIK_ENABLED=true
fi

echo ""
echo "========================================"
echo "Generating Documentation: $SERVICE_NAME"
echo "========================================"
echo ""

log_info "Type: $DOC_TYPE"
log_info "Output: $OUTPUT_PATH"
echo ""

# Select template
case "$DOC_TYPE" in
    guide)
        TEMPLATE_FILE="$TEMPLATE_DIR/service-guide.md"
        ;;
    journal)
        TEMPLATE_FILE="$TEMPLATE_DIR/deployment-journal.md"
        ;;
    *)
        log_error "Invalid document type: $DOC_TYPE"
        log_error "Must be: guide, journal"
        exit 1
        ;;
esac

if [[ ! -f "$TEMPLATE_FILE" ]]; then
    log_error "Template not found: $TEMPLATE_FILE"
    exit 1
fi

log_success "Template found: $TEMPLATE_FILE"

# Create output directory
OUTPUT_DIR=$(dirname "$OUTPUT_PATH")
if [[ ! -d "$OUTPUT_DIR" ]]; then
    log_info "Creating directory: $OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"
fi

# Simple template substitution (no Mustache, just sed replacements)
log_info "Generating document..."

sed -e "s|{{SERVICE_NAME}}|$SERVICE_NAME|g" \
    -e "s|{{SERVICE_DESCRIPTION}}|$DESCRIPTION|g" \
    -e "s|{{SERVICE_PURPOSE}}|$PURPOSE|g" \
    -e "s|{{TIMESTAMP}}|$TIMESTAMP|g" \
    -e "s|{{DEPLOYMENT_DATE}}|$DEPLOYMENT_DATE|g" \
    -e "s|{{IMAGE}}|$IMAGE|g" \
    -e "s|{{MEMORY_LIMIT}}|$MEMORY|g" \
    -e "s|{{NETWORKS}}|$NETWORKS|g" \
    -e "s|{{CONFIG_DIR}}|$CONFIG_DIR|g" \
    -e "s|{{DATA_DIR}}|$DATA_DIR|g" \
    -e "s|{{HOSTNAME}}|$HOSTNAME|g" \
    -e "s|{{MIDDLEWARE_CHAIN}}|$MIDDLEWARE|g" \
    -e "s|{{PORT}}|${METRICS_PORT:-8080}|g" \
    -e "s|{{METRICS_PATH}}|$METRICS_PATH|g" \
    -e "s|{{PRIMARY_NETWORK}}|${NETWORKS%%,*}|g" \
    "$TEMPLATE_FILE" > "$OUTPUT_PATH"

# Handle conditional sections (simplified - remove lines with unused conditions)
# Remove {{#TRAEFIK_ENABLED}} sections if not enabled
if [[ "$TRAEFIK_ENABLED" == false ]]; then
    sed -i '/{{#TRAEFIK_ENABLED}}/,/{{\/TRAEFIK_ENABLED}}/d' "$OUTPUT_PATH"
else
    sed -i 's/{{#TRAEFIK_ENABLED}}//g; s/{{\/TRAEFIK_ENABLED}}//g' "$OUTPUT_PATH"
fi

# Remove {{^TRAEFIK_ENABLED}} sections if enabled
if [[ "$TRAEFIK_ENABLED" == true ]]; then
    sed -i '/{{^TRAEFIK_ENABLED}}/,/{{\/TRAEFIK_ENABLED}}/d' "$OUTPUT_PATH"
else
    sed -i 's/{{^TRAEFIK_ENABLED}}//g; s/{{\/TRAEFIK_ENABLED}}//g' "$OUTPUT_PATH"
fi

# Handle {{#PUBLIC}} sections
if [[ "$PUBLIC" == false ]]; then
    sed -i '/{{#PUBLIC}}/,/{{\/PUBLIC}}/d' "$OUTPUT_PATH"
else
    sed -i 's/{{#PUBLIC}}//g; s/{{\/PUBLIC}}//g' "$OUTPUT_PATH"
fi

# Remove {{^PUBLIC}} sections if public
if [[ "$PUBLIC" == true ]]; then
    sed -i '/{{^PUBLIC}}/,/{{\/PUBLIC}}/d' "$OUTPUT_PATH"
else
    sed -i 's/{{^PUBLIC}}//g; s/{{\/PUBLIC}}//g' "$OUTPUT_PATH"
fi

# Handle {{#AUTH_REQUIRED}} sections
if [[ "$AUTH_REQUIRED" == false ]]; then
    sed -i '/{{#AUTH_REQUIRED}}/,/{{\/AUTH_REQUIRED}}/d' "$OUTPUT_PATH"
else
    sed -i 's/{{#AUTH_REQUIRED}}//g; s/{{\/AUTH_REQUIRED}}//g' "$OUTPUT_PATH"
fi

# Remove {{^AUTH_REQUIRED}} sections if auth required
if [[ "$AUTH_REQUIRED" == true ]]; then
    sed -i '/{{^AUTH_REQUIRED}}/,/{{\/AUTH_REQUIRED}}/d' "$OUTPUT_PATH"
else
    sed -i 's/{{^AUTH_REQUIRED}}//g; s/{{\/AUTH_REQUIRED}}//g' "$OUTPUT_PATH"
fi

# Handle {{#MONITORING}} sections
if [[ "$MONITORING" == false ]]; then
    sed -i '/{{#MONITORING}}/,/{{\/MONITORING}}/d' "$OUTPUT_PATH"
else
    sed -i 's/{{#MONITORING}}//g; s/{{\/MONITORING}}//g' "$OUTPUT_PATH"
fi

# Clean up any remaining template markers
sed -i 's/{{[^}]*}}//g' "$OUTPUT_PATH"

log_success "Documentation generated"
log_info "Location: $OUTPUT_PATH"

# File size check
FILE_SIZE=$(wc -l < "$OUTPUT_PATH")
log_info "Lines: $FILE_SIZE"

echo ""
echo "========================================"
echo "Documentation Generation Complete"
echo "========================================"
echo ""
echo "Next steps:"
echo "  1. Review generated documentation:"
echo "     cat $OUTPUT_PATH"
echo ""
echo "  2. Edit as needed (add details, troubleshooting, etc.)"
echo ""
echo "  3. Commit to Git:"
echo "     git add $OUTPUT_PATH"
echo "     git commit -m \"docs: Add $DOC_TYPE for $SERVICE_NAME\""
echo ""

log_success "Documentation ready for review and commit"
exit 0
