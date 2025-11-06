# Prometheus Configuration

## Quick Start

- **Targets**: See `prometheus.yml` for all scraped services
- **Alert Rules**: See `alerts/rules.yml` for all alert definitions
- **Reload Config**: `systemctl --user restart prometheus.service`

## Current Monitoring

- **8 services** being scraped every 15 seconds
- **15 alert rules** (6 critical, 9 warnings)
- **15 day** metric retention
- **Discord notifications** via custom relay

## Common Tasks

**Add new service:**
```yaml
# Edit prometheus.yml
- job_name: 'myservice'
  static_configs:
    - targets: ['myservice:9999']
      labels:
        instance: 'fedora-htpc'
        service: 'myservice'
```

**Add new alert:**
```yaml
# Edit alerts/rules.yml
- alert: MyAlert
  expr: metric > threshold
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Description here"
```

**Reload:**
```bash
systemctl --user restart prometheus.service
```

## Documentation

See `/home/patriark/containers/docs/monitoring-stack-guide.md` for complete documentation.
