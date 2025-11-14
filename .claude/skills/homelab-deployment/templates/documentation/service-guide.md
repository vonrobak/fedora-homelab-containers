# {{SERVICE_NAME}} - {{SERVICE_DESCRIPTION}}

**Last Updated:** {{TIMESTAMP}}
**Maintainer:** Claude Code (auto-generated)

## Overview

{{SERVICE_PURPOSE}}

**Access:** {{EXTERNAL_URL}}
**Status:** Monitored via Prometheus
**Authentication:** {{AUTH_REQUIREMENT}}

## Configuration

**Container:**
- Image: `{{IMAGE}}`
- Memory: {{MEMORY_LIMIT}}
- Networks: {{NETWORKS}}

**Storage:**
- Config: `{{CONFIG_DIR}}`
- Data: `{{DATA_DIR}}`

**Traefik Route:**
- Hostname: `{{HOSTNAME}}`
- Middleware: {{MIDDLEWARE_CHAIN}}
- TLS: Let's Encrypt

## Management Commands

```bash
# Start service
systemctl --user start {{SERVICE_NAME}}.service

# Stop service
systemctl --user stop {{SERVICE_NAME}}.service

# Restart service
systemctl --user restart {{SERVICE_NAME}}.service

# View status
systemctl --user status {{SERVICE_NAME}}.service

# View logs
journalctl --user -u {{SERVICE_NAME}}.service -f

# Check health
podman healthcheck run {{SERVICE_NAME}}

# Access container shell
podman exec -it {{SERVICE_NAME}} /bin/bash
```

## Troubleshooting

### Service won't start

```bash
# Check systemd status
systemctl --user status {{SERVICE_NAME}}.service

# Check container logs
podman logs {{SERVICE_NAME}} --tail 50

# Verify configuration
cat ~/.config/containers/systemd/{{SERVICE_NAME}}.container

# Check network connectivity
podman network inspect {{PRIMARY_NETWORK}} | grep {{SERVICE_NAME}}
```

### Can't access via web

```bash
# Check Traefik routing
podman logs traefik | grep {{SERVICE_NAME}}

# Verify route exists
curl -I https://{{HOSTNAME}}

# Test internal access
curl -I http://localhost:{{PORT}}/
```

### High resource usage

```bash
# Check current resource usage
podman stats {{SERVICE_NAME}}

# View historical metrics (Grafana)
# Navigate to Service Health dashboard
```

## Related Documentation

- Deployment: `docs/10-services/journal/{{DEPLOYMENT_DATE}}-{{SERVICE_NAME}}-deployment.md`
- Architecture: `CLAUDE.md` - Services section

## Quick Reference

| Property | Value |
|----------|-------|
| Container Name | {{SERVICE_NAME}} |
| Image | {{IMAGE}} |
| Internal Port | {{PORT}} |
| External URL | https://{{HOSTNAME}} |
| Health Check | {{HEALTH_CMD}} |
| Memory Limit | {{MEMORY_LIMIT}} |
| Deployed | {{DEPLOYMENT_DATE}} |
