# Quadlet Files

This directory contains copies of the Podman Quadlet unit files that define the container services.

**Source Location:** `~/.config/containers/systemd/`

## What are Quadlets?

Quadlets are Podman's systemd integration format. They are simplified `.container` and `.network` files that systemd automatically converts to full systemd unit files.

## Usage

These files are **copies** for version control. The actual files used by systemd are in:
```
~/.config/containers/systemd/
```

To deploy changes:
1. Copy the modified file to `~/.config/containers/systemd/`
2. Run: `systemctl --user daemon-reload`
3. Run: `systemctl --user restart <service>.service`

## File Types

- **`.container`** - Container service definitions
- **`.network`** - Network definitions

## Currently Deployed Services

### Monitoring Stack
- `prometheus.container` - Metrics collection & alerting
- `alertmanager.container` - Alert routing
- `grafana.container` - Dashboards & visualization
- `alert-discord-relay.container` - Discord webhook relay
- `node_exporter.container` - System metrics exporter
- `loki.container` - Log aggregation
- `promtail.container` - Log collector

### Core Infrastructure
- `traefik.container` - Reverse proxy
- `tinyauth.container` - Authentication middleware
- `crowdsec.container` - Security monitoring

### Media Services
- `jellyfin.container` - Media server

### Networks
- `monitoring.network` - Monitoring services network
- `reverse_proxy.network` - Public-facing services
- `auth_services.network` - Authentication services
- `media_services.network` - Media services

## Security & Secrets Management

### Template Files (*.container.template)

Some quadlets contain sensitive credentials and are **excluded from Git**:
- `tinyauth.container` - Contains SECRET and USERS credentials
- `grafana.container` - Contains admin password

**For development/testing:**
1. Copy the `.template` file: `cp tinyauth.container.template tinyauth.container`
2. Edit the copy and replace placeholders with your credentials
3. The actual `.container` file is gitignored and stays local

**For production (Fedora server):**
Use Podman secrets instead of hardcoded values:
```bash
# Create secret
echo "your-secret-value" | podman secret create tinyauth_secret -

# Reference in quadlet
Secret=tinyauth_secret,type=env,target=SECRET
```

See `traefik.container`, `alertmanager.container`, and `alert-discord-relay.container` for examples of proper secrets usage.

## Documentation

See `/home/patriark/containers/docs/` for detailed documentation on each service.
