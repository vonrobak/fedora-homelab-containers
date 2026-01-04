# Unpoller Configuration

**Status:** Ready for deployment - requires UniFi controller credentials

## Overview

Unpoller is a Prometheus metrics exporter for UniFi Network Application (formerly UniFi Controller). It polls your UniFi controller and exposes network device metrics, client statistics, and performance data.

## Prerequisites

- UniFi Network Application (Cloud Key, Dream Machine, or self-hosted controller)
- Local user account on UniFi controller (read-only access sufficient)
- Controller accessible from this host

## Configuration Required

**Before starting the service, update the environment variables in:**

`~/.config/containers/systemd/unpoller.container`

### Step 1: Set UniFi Controller Credentials

Edit the quadlet file and replace the placeholder values:

```bash
nano ~/.config/containers/systemd/unpoller.container
```

Update these lines:

```ini
Environment=UP_UNIFI_DEFAULT_URL=https://unifi.patriark.org
Environment=UP_UNIFI_DEFAULT_USER=unifipoller
Environment=UP_UNIFI_DEFAULT_PASS=CHANGE_ME
```

**URL Examples:**
- Cloud Key Gen2: `https://192.168.1.1:8443`
- Dream Machine Pro: `https://192.168.1.1`
- Self-hosted: `https://unifi.patriark.org`

**User Setup:**
1. Log into UniFi Network Application
2. Go to Settings → Admins
3. Create new local admin user (e.g., "unifipoller")
4. Grant "Read Only" role
5. Use this username/password in the config

### Step 2: Verify SSL Settings

If your controller uses a self-signed certificate, the config already has:

```toml
verify_ssl = false
```

For production controllers with valid certificates, change this to `true`.

## Deployment

After configuring credentials:

```bash
# Reload systemd to recognize changes
systemctl --user daemon-reload

# Start unpoller
systemctl --user enable --now unpoller.service

# Check status
systemctl --user status unpoller.service

# View logs
journalctl --user -u unpoller.service -f

# Verify health check
podman healthcheck run unpoller
```

## Verification

**Metrics Endpoint:**

```bash
curl http://localhost:9130/metrics
```

You should see metrics like:
- `unpoller_device_info` - Device information
- `unpoller_device_uptime_seconds` - Device uptime
- `unpoller_client_receive_bytes_total` - Client RX traffic
- `unpoller_client_transmit_bytes_total` - Client TX traffic

**Prometheus Integration:**

Prometheus is already configured to scrape unpoller at `unpoller:9130`.

Check Prometheus targets:
```bash
# Open in browser:
http://localhost:9090/targets

# Or check via API:
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="unpoller")'
```

**Grafana Dashboards:**

Import official UniFi dashboards from Grafana.com:

1. Go to https://grafana.patriark.org
2. Dashboards → Import
3. Enter dashboard ID:
   - **11315**: UniFi Poller: Client Insights - Prometheus
   - **11314**: UniFi Poller: USW Insights - Prometheus
   - **11313**: UniFi Poller: UAP Insights - Prometheus
4. Select Prometheus datasource
5. Import

## Troubleshooting

**Service fails to start:**

```bash
# Check logs for specific error
journalctl --user -u unpoller.service -n 50

# Common issues:
# - Invalid credentials: Check username/password
# - Controller unreachable: Verify URL and network connectivity
# - Invalid config syntax: Check /config/unpoller/up.conf
```

**No metrics appearing:**

```bash
# Verify unpoller can reach controller
podman exec unpoller curl -k https://YOUR_CONTROLLER_URL

# Check unpoller logs
podman logs unpoller --tail 50
```

**Prometheus not scraping:**

```bash
# Verify unpoller is on systemd-monitoring network
podman inspect unpoller | grep -i network

# Test from Prometheus container
podman exec prometheus wget -O- http://unpoller:9130/metrics
```

## Architecture

**Network:** `systemd-monitoring` (internal only)
**Port:** 9130 (Prometheus metrics)
**Memory:** 256MB limit
**Storage:** Minimal (~10MB for cache)

**Security:** Internal service, not exposed via Traefik. Metrics accessible only to Prometheus on the monitoring network.

## References

- Official Docs: https://unpoller.com/docs/
- GitHub: https://github.com/unpoller/unpoller
- Grafana Dashboards: https://grafana.com/grafana/dashboards/?search=unpoller
- Prometheus Config: `~/containers/config/prometheus/prometheus.yml`
