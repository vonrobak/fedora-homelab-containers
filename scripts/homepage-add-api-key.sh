#!/bin/bash
###############################################################
# Homepage Widget API Key Configuration Helper
# Adds API keys to Podman secrets and updates Homepage
###############################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_usage() {
    cat <<EOF
Usage: $(basename "$0") <service> <api-key>

Add API keys for Homepage widgets using Podman secrets.

Available services:
  jellyfin    - Jellyfin media server API key
  immich      - Immich photo management API key
  openweather - OpenWeather API key

Examples:
  $(basename "$0") jellyfin abc123def456
  $(basename "$0") immich xyz789uvw012
  $(basename "$0") openweather your-api-key-here

How to generate API keys:

  Jellyfin:
    1. Visit https://jellyfin.patriark.org
    2. Login → Settings → API Keys
    3. Click "+" to create new key
    4. Name it "Homepage Dashboard"
    5. Copy the generated key

  Immich:
    1. Visit https://photos.patriark.org
    2. Login → Account Settings → API Keys
    3. Click "New API Key"
    4. Name it "Homepage Dashboard"
    5. Copy the generated key

  OpenWeather:
    1. Visit https://openweathermap.org/api
    2. Sign up for free account
    3. Go to API Keys section
    4. Copy your API key

EOF
}

if [[ $# -ne 2 ]]; then
    show_usage
    exit 1
fi

SERVICE="$1"
API_KEY="$2"
SECRET_NAME="homepage_${SERVICE}_api_key"
ENV_VAR_NAME="HOMEPAGE_VAR_$(echo "$SERVICE" | tr '[:lower:]' '[:upper:]')_API_KEY"

# Validate service
case "$SERVICE" in
    jellyfin|immich|openweather)
        ;;
    *)
        print_error "Unknown service: $SERVICE"
        show_usage
        exit 1
        ;;
esac

print_info "Adding API key for $SERVICE..."

# Check if secret already exists
if podman secret inspect "$SECRET_NAME" &>/dev/null; then
    print_warning "Secret $SECRET_NAME already exists. Removing old secret..."
    podman secret rm "$SECRET_NAME"
fi

# Create new secret
echo -n "$API_KEY" | podman secret create "$SECRET_NAME" -
print_success "Created Podman secret: $SECRET_NAME"

# Check if secret is already in quadlet (uncommented)
QUADLET_FILE="$HOME/.config/containers/systemd/homepage.container"
if grep -q "^Secret=$SECRET_NAME" "$QUADLET_FILE"; then
    print_info "Secret already configured in homepage.container"
else
    print_info "Adding secret to homepage.container..."
    # Uncomment the secret line (if commented) or add it
    if grep -q "^# Secret=$SECRET_NAME" "$QUADLET_FILE"; then
        # Line exists but is commented - uncomment it
        sed -i "s|^# Secret=$SECRET_NAME,type=env,target=$ENV_VAR_NAME|Secret=$SECRET_NAME,type=env,target=$ENV_VAR_NAME|" "$QUADLET_FILE"
        print_success "Uncommented secret in homepage.container"
    else
        print_warning "Secret line not found in quadlet - you may need to add it manually"
        print_info "Add this line: Secret=$SECRET_NAME,type=env,target=$ENV_VAR_NAME"
    fi
fi

# Reload and restart Homepage
print_info "Restarting Homepage service..."
systemctl --user daemon-reload
systemctl --user restart homepage.service

# Wait for service to be ready
sleep 5

if systemctl --user is-active --quiet homepage.service; then
    print_success "Homepage service restarted successfully"
    print_info "Widget for $SERVICE should now display data"
else
    print_error "Homepage service failed to start"
    print_info "Check logs: journalctl --user -u homepage.service -n 50"
    exit 1
fi

print_success "Done! API key for $SERVICE configured."
