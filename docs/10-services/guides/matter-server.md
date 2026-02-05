# Matter Server - Service Guide

**Status:** Production
**Version:** Stable (auto-update enabled)
**Image:** `ghcr.io/home-assistant-libs/python-matter-server:stable`
**Network:** home_automation only (internal service)
**Quadlet:** `~/containers/quadlets/matter-server.container`

---

## Quick Reference

### Service Management

```bash
# Status
systemctl --user status matter-server.service
podman ps | grep matter-server

# Control
systemctl --user start matter-server.service
systemctl --user stop matter-server.service
systemctl --user restart matter-server.service

# Logs
journalctl --user -u matter-server.service -f
podman logs -f matter-server
```

### Health Checks

```bash
# Podman health check (runs every 30s automatically)
podman healthcheck run matter-server

# Manual WebSocket port check
podman exec matter-server python3 -c \
  "import socket; s=socket.socket(); s.settimeout(5); s.connect(('localhost', 5580)); s.close()"
```

### Critical Files

```
~/containers/quadlets/matter-server.container   # Quadlet definition
~/containers/data/matter-server/                # Runtime data (certificates, vendor info, node config)
```

### Resource Usage

- **Memory:** ~99MB typical / 512MB max
- **CPU:** Minimal (<1% idle)

---

## Architecture

### Role

Matter Server (`python-matter-server`) is a standalone WebSocket server that acts as a protocol bridge between Matter/Thread smart home devices and Home Assistant. It implements the Matter controller stack, handling device commissioning, communication, and state management.

Home Assistant connects to it as a WebSocket client. The server runs independently so it can maintain persistent connections to commissioned devices regardless of Home Assistant restarts.

### Communication Flow

```
Matter Device (Thread/WiFi)
  |
  v
Matter Server (python-matter-server)
  Port 5580 (WebSocket)
  |
  v
Home Assistant (Matter integration)
  ws://matter-server:5580/ws
```

### Why a Separate Container

- **Independent lifecycle:** Matter Server stays up during Home Assistant restarts, maintaining device connections
- **Resource isolation:** Dedicated memory limits (512MB) separate from Home Assistant (2GB)
- **Future flexibility:** Multiple Home Assistant instances could connect to the same Matter Server

---

## Network Configuration

Matter Server runs on the `home_automation` network only (10.89.6.0/24). It does not need internet access -- device commissioning and certificate operations are handled through Home Assistant.

```
systemd-home_automation (10.89.6.0/24)
├── Home Assistant  (10.89.6.3)  -- WebSocket client
└── Matter Server   (internal)   -- WebSocket server on port 5580
```

No ports are published to the host. All communication happens container-to-container over the home_automation network.

No Traefik routing is configured -- this is a purely internal service with no external access.

---

## Integration with Home Assistant

### Adding the Matter Integration

1. Open https://ha.patriark.org
2. Navigate to **Settings > Devices & Services**
3. Click **"+ ADD INTEGRATION"**
4. Search for **"Matter"** and select **"Matter (BETA)"**
5. Enter server URL: `ws://matter-server:5580/ws`
6. Click **Submit**

The integration should connect successfully and show 0 devices initially. Devices appear after commissioning through the Home Assistant UI.

### Commissioning Matter Devices

1. In Home Assistant, go to **Settings > Devices & Services > Matter**
2. Click **"Add Device"** (or use the Companion App for phone-based commissioning)
3. Follow the on-screen pairing flow (scan QR code or enter setup code)
4. The Matter Server handles the CHIP protocol handshake and stores the device credentials in `/data`

### Dependency Chain

```
home_automation-network.service
  └── matter-server.service
        └── home-assistant.service (connects via WebSocket)
```

The quadlet declares `Requires=home_automation-network.service` so the network is created before the container starts. Home Assistant does not have an explicit systemd dependency on Matter Server -- the Matter integration reconnects automatically if the server restarts.

---

## Data and Storage

All persistent state is stored in `~/containers/data/matter-server/`:

- **Certificates:** CHIP fabric credentials and PAA root certificates (72+ fetched from DCL)
- **Vendor info:** Cached vendor database (387+ entries)
- **Node config:** Commissioned device data (node credentials, fabric assignments)

This directory is bind-mounted as `/data` inside the container with the `:Z` SELinux label.

### Backup

```bash
# Stop service for consistent state
systemctl --user stop matter-server.service

# Backup data directory
tar czf matter-server-data-$(date +%Y%m%d).tar.gz \
  ~/containers/data/matter-server/

# Restart
systemctl --user start matter-server.service
```

Losing this data means all commissioned Matter devices must be re-paired.

---

## Troubleshooting

### Matter Server Won't Start

**Check service status:**
```bash
systemctl --user status matter-server.service
journalctl --user -u matter-server.service --no-pager -n 30
```

**Verify network exists:**
```bash
podman network ls | grep home_automation
```

**Reload and restart:**
```bash
systemctl --user daemon-reload
systemctl --user restart matter-server.service
```

### Health Check Failing

The health check uses a Python socket connection to port 5580. A 90-second start period is configured to allow for initial certificate fetching.

**Check if the WebSocket port is listening:**
```bash
podman exec matter-server python3 -c \
  "import socket; s=socket.socket(); s.settimeout(5); s.connect(('localhost', 5580)); s.close()"
```

**Check container logs for errors:**
```bash
podman logs matter-server --tail 50
```

**Common startup messages (normal):**
```
INFO [chip.CertificateAuthority] Loading certificate authorities from storage...
INFO [matter_server.server.stack] CHIP Controller Stack initialized
INFO [matter_server.server.helpers.paa_certificates] Fetched 72 PAA root certificates from DCL
INFO [matter_server.server.server] Matter Server successfully initialized
```

### Home Assistant Cannot Connect

**Verify Matter Server is running and healthy:**
```bash
podman healthcheck run matter-server
```

**Verify both containers are on the same network:**
```bash
podman inspect matter-server --format '{{range .NetworkSettings.Networks}}{{.NetworkID}}{{end}}'
podman inspect home-assistant --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}'
```

Both should include the `systemd-home_automation` network.

**Test connectivity from Home Assistant container:**
```bash
podman exec home-assistant python3 -c \
  "import socket; s=socket.socket(); s.settimeout(5); s.connect(('matter-server', 5580)); s.close(); print('OK')"
```

**Check the Matter integration in Home Assistant:**
1. **Settings > Devices & Services > Matter**
2. If showing "Setup Error", click the three-dot menu and select **Reload**
3. Verify the URL is `ws://matter-server:5580/ws`

### Device Commissioning Fails

**Check Matter Server logs during commissioning:**
```bash
podman logs -f matter-server
```

**Common issues:**
- Device not in pairing mode (reset the device and try again)
- Device too far from the network (bring closer during initial commissioning)
- Thread border router not available (for Thread devices, ensure a border router is on the network)

### Resource Limits Hit

The container is limited to 512MB. If memory pressure triggers, check for runaway processes:

```bash
podman stats --no-stream matter-server
```

Normal usage is around 99MB. If significantly higher, restart the service:
```bash
systemctl --user restart matter-server.service
```

---

## Related Documentation

- **Deployment journal:** `docs/98-journals/2026-01-28-matter-hybrid-week2-matter-server-deployment.md`
- **Implementation plan:** `docs/97-plans/2025-12-30-matter-home-automation-implementation-plan.md`
- **Home Assistant guide:** `docs/10-services/guides/home-assistant.md`
- **Network topology:** `docs/AUTO-NETWORK-TOPOLOGY.md`
