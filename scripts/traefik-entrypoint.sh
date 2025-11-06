#!/bin/sh
# Traefik entrypoint wrapper - loads secrets into environment variables
# This script reads Podman secrets and exports them for Traefik's use

# Load CrowdSec API key from secret file
if [ -f /run/secrets/crowdsec_api_key ]; then
    export CROWDSEC_API_KEY=$(cat /run/secrets/crowdsec_api_key)
fi

# Execute Traefik with original arguments
exec /entrypoint.sh "$@"
