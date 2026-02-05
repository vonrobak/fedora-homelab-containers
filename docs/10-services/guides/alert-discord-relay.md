# Alert Discord Relay

**Last Updated:** 2026-02-05
**Version:** Custom-built (localhost/alert-discord-relay:latest)
**Status:** Production
**Networks:** monitoring

---

## Overview

Alert Discord Relay is a **custom-built Python service** that bridges Alertmanager webhooks to Discord, transforming raw alert payloads into formatted rich embeds with color-coded severity, structured fields, and timestamps.

**Key features:**
- Converts Alertmanager webhook payloads to Discord embed format
- Color-coded alerts: red (critical), orange (warning), green (resolved)
- Structured fields for severity, instance, service, job, and timestamps
- Health check endpoint for container monitoring
- Lightweight Flask/Gunicorn application (~128MB memory limit)

**Integration:** Receives webhooks from Alertmanager on port 9095, forwards formatted embeds to Discord

---

## Quick Reference

### Service Management

```bash
# Status
systemctl --user status alert-discord-relay.service
podman ps | grep alert-discord-relay

# Control
systemctl --user restart alert-discord-relay.service

# Logs
journalctl --user -u alert-discord-relay.service -f
podman logs -f alert-discord-relay
```

### Health Checks

```bash
# Container health check (built-in)
podman healthcheck run alert-discord-relay

# Manual health check
podman exec alert-discord-relay python3 -c \
  "import urllib.request; urllib.request.urlopen('http://localhost:9095/health', timeout=5)"

# From the host (via monitoring network)
podman exec alertmanager wget -qO- http://alert-discord-relay:9095/health
```

---

## Architecture

### Data Flow

```
Prometheus evaluates alert rules (every 15s)
  |
  v
Alertmanager receives firing/resolved alerts
  |
  v
Alertmanager routes to webhook receivers
  |
  +--> discord-critical  (send_resolved: true)
  +--> discord-warnings  (send_resolved: false, waking hours only)
  +--> discord-default   (send_resolved: true, fallback)
  +--> discord-info      (send_resolved: false, repeat: 1 week)
  |
  v
alert-discord-relay:9095/webhook
  |
  v
Transforms payload to Discord embed format
  |  - Color: red=critical, orange=warning, green=resolved
  |  - Fields: severity, instance, service, job, timestamps
  |  - Footer: "Homelab Monitoring" + Alertmanager URL
  |
  v
Discord Webhook API --> Discord channel
```

### Alertmanager Receivers

The relay serves four Alertmanager receivers, all pointing to the same endpoint (`http://alert-discord-relay:9095/webhook`) with different routing behavior:

| Receiver | Severity | Resolved | Timing | Repeat |
|----------|----------|----------|--------|--------|
| `discord-critical` | critical | Yes | Always | 1h |
| `discord-warnings` | warning | No | Waking hours (07:00-23:00) | 4h |
| `discord-info` | info | No | Always | 168h (1 week) |
| `discord-default` | fallback | Yes | Always | 4h |

**Configuration:** `~/containers/config/alertmanager/alertmanager.yml`

---

## Custom-Built Image

The relay is a custom container image built locally, not pulled from a registry.

### Source Files

All source files are in `~/containers/config/alert-discord-relay/`:

| File | Purpose |
|------|---------|
| `Dockerfile` | Python 3.11-slim base, non-root user (UID 1000) |
| `relay.py` | Flask application with webhook and health endpoints |
| `requirements.txt` | Dependencies: Flask 3.0.0, requests 2.31.0, gunicorn 21.2.0 |

### Building the Image

```bash
# Build the container image
podman build -t localhost/alert-discord-relay:latest \
  ~/containers/config/alert-discord-relay/

# Verify the image
podman images | grep alert-discord-relay
```

### Runtime Details

- **WSGI server:** Gunicorn with 2 workers, 30s timeout
- **Listen port:** 9095
- **Endpoints:**
  - `POST /webhook` -- receives Alertmanager payloads
  - `GET /health` -- returns `{"status": "healthy"}`
- **Runs as:** Non-root user (UID 1000) inside the container

---

## Network Configuration

The relay runs exclusively on the **monitoring** network. It does not need internet access or reverse proxy exposure.

```
Quadlet: Network=systemd-monitoring

Alertmanager (monitoring network)
  --> http://alert-discord-relay:9095/webhook

alert-discord-relay (monitoring network)
  --> Discord Webhook URL (via container networking)
```

**Note:** The container does require outbound internet access to reach the Discord API. The monitoring network provides this through Podman's default gateway.

---

## Secrets

The Discord webhook URL is injected via Podman secret:

```bash
# View existing secret
podman secret ls | grep discord

# Update the webhook URL
echo "https://discord.com/api/webhooks/..." | podman secret create discord_webhook_url -

# If updating, remove old secret first
podman secret rm discord_webhook_url
echo "https://discord.com/api/webhooks/..." | podman secret create discord_webhook_url -
systemctl --user restart alert-discord-relay.service
```

**Quadlet directive:** `Secret=discord_webhook_url,type=env,target=DISCORD_WEBHOOK_URL`

---

## Resource Limits

| Resource | Limit | Notes |
|----------|-------|-------|
| Memory (max) | 128M | Hard ceiling, container killed if exceeded |
| Memory (high) | 115M | Pressure applied above this threshold |
| CPU | Unrestricted | Negligible usage under normal load |

---

## Troubleshooting

### Alerts Not Appearing in Discord

1. **Check relay is running:**
   ```bash
   systemctl --user status alert-discord-relay.service
   podman healthcheck run alert-discord-relay
   ```

2. **Check relay logs for errors:**
   ```bash
   podman logs --tail 50 alert-discord-relay | grep -i error
   ```

3. **Check Alertmanager can reach the relay:**
   ```bash
   podman exec alertmanager wget -qO- http://alert-discord-relay:9095/health
   ```

4. **Send a test webhook manually:**
   ```bash
   podman exec alertmanager wget -qO- --post-data='{"status":"firing","alerts":[{"labels":{"alertname":"TestAlert","severity":"warning"},"annotations":{"summary":"Test alert from manual check"},"startsAt":"2026-01-01T00:00:00Z"}]}' \
     --header='Content-Type: application/json' \
     http://alert-discord-relay:9095/webhook
   ```

5. **Check Discord webhook URL is valid:**
   ```bash
   # Verify the secret exists
   podman secret ls | grep discord_webhook_url

   # Check relay startup logs for the URL validation
   podman logs alert-discord-relay 2>&1 | head -5
   ```

### Discord Returns Non-200 Status

**Symptom:** Relay logs show `Discord returned 4xx/5xx`

**Common causes:**
- **429 (Rate Limited):** Too many alerts firing simultaneously. Alertmanager group_wait (30s) and group_interval (5m) should throttle this.
- **400 (Bad Request):** Embed format issue, usually from very long alert descriptions exceeding Discord's 6000-character embed limit.
- **401/403 (Unauthorized):** Webhook URL is invalid or the webhook was deleted from Discord.

**Fix:** Verify the webhook URL is still active in Discord Server Settings > Integrations > Webhooks.

### Container Fails to Start

1. **Check image exists:**
   ```bash
   podman images | grep alert-discord-relay
   ```

2. **Rebuild if missing:**
   ```bash
   podman build -t localhost/alert-discord-relay:latest \
     ~/containers/config/alert-discord-relay/
   ```

3. **Check secret exists:**
   ```bash
   podman secret ls | grep discord_webhook_url
   ```

4. **Check monitoring network exists:**
   ```bash
   podman network ls | grep monitoring
   ```

### Health Check Failing

**Symptom:** `podman healthcheck run alert-discord-relay` returns unhealthy

The health check uses Python's `urllib` since `wget`/`curl` are not available in the slim image. If the Flask/Gunicorn process has crashed, the health check will fail.

```bash
# Check if the process is running inside the container
podman exec alert-discord-relay ps aux

# Check Gunicorn worker status
podman logs --tail 20 alert-discord-relay
```

---

## Related Documentation

- **Monitoring stack:** `docs/40-monitoring-and-documentation/guides/monitoring-stack.md`
- **Alertmanager config:** `config/alertmanager/alertmanager.yml`
- **Relay source code:** `config/alert-discord-relay/`
- **Quadlet file:** `quadlets/alert-discord-relay.container`

---

**Maintainer:** patriark
**Image:** localhost/alert-discord-relay:latest (custom-built)
**Port:** 9095 (internal only, no external exposure)
