# {{SERVICE_NAME}} Deployment

**Date:** {{DEPLOYMENT_DATE}}
**Service:** {{SERVICE_NAME}}
**Status:** {{DEPLOYMENT_STATUS}}

## Deployment Summary

**Service Type:** {{SERVICE_TYPE}}
**Image:** {{IMAGE}}
**Networks:** {{NETWORKS}}
**External Access:** {{EXTERNAL_URL}}

## Configuration Used

### Quadlet Configuration

```ini
[Unit]
Description={{SERVICE_DESCRIPTION}}

[Container]
Image={{IMAGE}}
Networks={{NETWORKS}}
Volumes={{VOLUMES}}
Memory={{MEMORY_LIMIT}}
```

### Traefik Route

```yaml
Router: {{SERVICE_NAME}}-secure
Hostname: {{HOSTNAME}}
Middleware: {{MIDDLEWARE_CHAIN}}
```

## Deployment Steps

1. **Pre-deployment Validation**
   - ✓ Image available: {{IMAGE}}
   - ✓ Networks exist: {{NETWORKS}}
   - ✓ Ports available: {{PORTS}}
   - ✓ Disk space sufficient
   - ✓ No conflicts detected

2. **Configuration Generation**
   - ✓ Quadlet created from template: {{TEMPLATE_USED}}
   - ✓ Traefik route configured
   - ✓ Prometheus scrape target added (if applicable)

3. **Deployment Execution**
   - ✓ systemd daemon reloaded
   - ✓ Service enabled for auto-start
   - ✓ Service started successfully
   - ✓ Health check passed after {{HEALTH_WAIT_TIME}}

4. **Post-Deployment Verification**
   - ✓ Service running: {{SERVICE_STATUS}}
   - ✓ Internal endpoint accessible
   - ✓ External URL accessible: https://{{HOSTNAME}}
   - ✓ Authentication working (if applicable)
   - ✓ Monitoring configured
   - ✓ Logs clean (no errors)

## Issues Encountered

{{ISSUES_SECTION}}

## Resolution Steps

{{RESOLUTION_SECTION}}

## Verification Results

```
Service Status: {{SERVICE_STATUS}}
Health Check: {{HEALTH_STATUS}}
External Access: {{EXTERNAL_ACCESS_STATUS}}
Monitoring: {{MONITORING_STATUS}}
```

## Next Steps

{{NEXT_STEPS}}

## Related Files

- Quadlet: `~/.config/containers/systemd/{{SERVICE_NAME}}.container`
- Traefik Route: `~/containers/config/traefik/dynamic/{{SERVICE_NAME}}-router.yml`
- Service Guide: `docs/10-services/guides/{{SERVICE_NAME}}.md`

---

**Deployment Tool:** homelab-deployment skill
**Deployment Time:** {{DEPLOYMENT_DURATION}}
**Claude Code Version:** v1.0
