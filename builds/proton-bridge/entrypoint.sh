#!/bin/bash
# Forward port 25 → 1025 (Authelia v4.39 hardcodes port 25 for smtp:// scheme)
socat TCP-LISTEN:25,fork,reuseaddr TCP:127.0.0.1:1025 &

# Start Proton Mail Bridge
exec /usr/lib/protonmail/bridge/proton-bridge --noninteractive --log-level info "$@"
