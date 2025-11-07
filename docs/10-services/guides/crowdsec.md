# CrowdSec Security Engine

**Last Updated:** 2025-11-07
**Version:** Latest
**Status:** Production
**Networks:** (standalone)

---

## Overview

CrowdSec is a **collaborative security engine** that detects and blocks malicious behavior using crowdsourced threat intelligence.

**Key features:**
- Real-time attack detection
- Crowdsourced threat intelligence
- IP reputation blocking
- Traefik bouncer integration
- Low resource usage

**Integration:** Traefik bouncer plugin blocks bad IPs before they reach services

---

## Quick Reference

### Service Management

```bash
# Status
systemctl --user status crowdsec.service
podman ps | grep crowdsec

# Control
systemctl --user restart crowdsec.service

# Logs
journalctl --user -u crowdsec.service -f
podman logs -f crowdsec
```

### CLI Tools

```bash
# View decisions (blocked IPs)
podman exec crowdsec cscli decisions list

# View active scenarios
podman exec crowdsec cscli scenarios list

# View metrics
podman exec crowdsec cscli metrics

# Check bouncer status
podman exec crowdsec cscli bouncers list
```

---

## Architecture

### How It Works

```
Traefik receives request
  ↓
CrowdSec bouncer middleware checks IP
  ↓
Queries CrowdSec local API
  │
  ├─ IP is clean → Allow request
  └─ IP is banned → Return 403 Forbidden
```

### Integration with Traefik

**Middleware** (`config/traefik/dynamic/middleware.yml`):

```yaml
http:
  middlewares:
    crowdsec-bouncer:
      plugin:
        bouncer:
          enabled: true
          crowdsecLapiKey: "${CROWDSEC_API_KEY}"  # Injected by entrypoint
          crowdsecLapiHost: "http://crowdsec:8080"
```

**Applied to all routes** (first middleware in chain):

```yaml
middlewares:
  - crowdsec-bouncer@file  # FIRST - fastest check
  - rate-limit@file
  - tinyauth@file
```

---

## Operations

### View Blocked IPs

```bash
podman exec crowdsec cscli decisions list
```

### Unblock IP (Whitelist)

```bash
# Temporary unblock
podman exec crowdsec cscli decisions delete --ip <IP_ADDRESS>

# Permanent whitelist
podman exec crowdsec cscli decisions add --ip <IP_ADDRESS> --type whitelist --duration 999h
```

### Check Attack Scenarios

```bash
# View all scenarios
podman exec crowdsec cscli scenarios list

# View active alerts
podman exec crowdsec cscli alerts list
```

### Update Threat Intelligence

```bash
# Update scenarios and parsers
podman exec crowdsec cscli hub update
podman exec crowdsec cscli hub upgrade

# Restart to apply
systemctl --user restart crowdsec.service
```

---

## Monitoring

### Metrics

```bash
# Overall metrics
podman exec crowdsec cscli metrics

# Per-scenario breakdown
podman exec crowdsec cscli metrics --scenarios
```

### Logs

```bash
# Recent blocks
podman logs crowdsec | grep -i "ban\|block"

# Scenario triggers
podman logs crowdsec | grep -i "scenario"
```

---

## Configuration

### Scenarios Enabled

Default scenarios include:
- HTTP brute force detection
- Port scanning detection
- SSH brute force
- Web vulnerability scanning

**List scenarios:**
```bash
podman exec crowdsec cscli scenarios list
```

### Bouncer API Key

**Stored:** Podman secret `crowdsec_api_key`

**Create/update:**
```bash
# Inside CrowdSec
podman exec crowdsec cscli bouncers add traefik-bouncer

# Returns API key - store in secret
echo "KEY" | podman secret create crowdsec_api_key -

# Restart Traefik to pick up new key
systemctl --user restart traefik.service
```

---

## Troubleshooting

### Bouncer Not Working

**Check bouncer registered:**
```bash
podman exec crowdsec cscli bouncers list
# Should show traefik-bouncer as active
```

**Check API key:**
```bash
# Verify key in Traefik
podman exec traefik env | grep CROWDSEC
```

### False Positives

**Unblock yourself:**
```bash
podman exec crowdsec cscli decisions delete --ip YOUR_IP
```

**Whitelist permanently:**
```bash
podman exec crowdsec cscli parsers add whitelist-myip \
  --type whitelist --source YOUR_IP --duration 999h
```

---

## Related Documentation

- **Traefik integration:** `docs/10-services/guides/traefik.md`
- **Middleware guide:** `docs/00-foundation/guides/middleware-configuration.md`

---

## Common Commands

```bash
# View blocked IPs
podman exec crowdsec cscli decisions list

# View metrics
podman exec crowdsec cscli metrics

# Unblock IP
podman exec crowdsec cscli decisions delete --ip <IP>

# Update threat intelligence
podman exec crowdsec cscli hub update
podman exec crowdsec cscli hub upgrade
systemctl --user restart crowdsec.service
```

---

**Maintainer:** patriark
**Bouncer:** Traefik plugin
**Threat Intelligence:** Crowdsourced + local scenarios
