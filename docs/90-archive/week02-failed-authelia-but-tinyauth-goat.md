# Tinyauth Configuration

## Credentials
- Username: patriark
- Password: [stored securely]

## Services Protected
- Traefik Dashboard (traefik.patriark.lokal)
- Jellyfin (jellyfin.patriark.lokal)

## Adding New Users
```bash
# Generate hash
podman run --rm -i ghcr.io/steveiliop56/tinyauth:v4 user create --interactive

# Edit quadlet
nano ~/.config/containers/systemd/tinyauth.container

# Add comma-separated: USERS=user1:$$hash1,user2:$$hash2

# Restart
systemctl --user daemon-reload
systemctl --user restart tinyauth.service
```

## Configuration Files
- Quadlet: ~/.config/containers/systemd/tinyauth.container
- Routers: ~/containers/config/traefik/dynamic/routers.yml
EOF

echo "✓ Documentation created"
