# Monitoring Stack Deployment - In Progress
**Date:** 2025-11-05
**Status:** Fixing existing architecture issues before adding Grafana

## Current Session Context

### What We're Doing
Deploying a monitoring stack (Grafana → Prometheus → Loki → Alertmanager) on fedora-htpc with proper architecture alignment.

### Progress So Far

#### ✅ Completed
1. Audited existing quadlet configurations
2. Identified architecture issues (TinyAuth network isolation, missing storage)
3. Fixed TinyAuth configuration:
   - Added `systemd-auth_services` network
   - Added persistent volume: `~/containers/data/tinyauth:/app/data:Z`
   - Created data directory
   - Service restarted successfully
4. Verified Jellyfin middleware already correct in `routers.yml`

#### ⚠️ Current Issue
- **Traefik dashboard inaccessible** after TinyAuth login
- **Likely cause:** Traefik not on `auth_services` network, can't reach TinyAuth
- **Fix:** Connect Traefik to auth_services network

#### 📋 Next Steps
1. Fix Traefik network connectivity
2. Create `monitoring.network` quadlet (10.89.4.0/24)
3. Add Grafana router to `~/containers/config/traefik/dynamic/routers.yml`
4. Create `grafana.container` quadlet
5. Deploy Grafana

---

## Architecture Design

### Network Topology
```
10.89.1.0/24 - media_services (Jellyfin)
10.89.2.0/24 - reverse_proxy (Traefik, exposed services)
10.89.3.0/24 - auth_services (TinyAuth)
10.89.4.0/24 - monitoring (Grafana, Prometheus, Loki) ← NEW
```

### Monitoring Stack Plan
1. **Step 1 (Today):** Grafana + monitoring network
2. **Step 2:** Prometheus + node_exporter
3. **Step 3:** Loki + Grafana Alloy
4. **Step 4:** Alertmanager + basic alerts
5. **Step 5:** Extend to fedora-jern + pihole
6. **Step 6 (Optional):** Tempo for tracing

---

## Files to Create/Edit

### 1. monitoring.network
**Location:** `~/.config/containers/systemd/monitoring.network`
```ini
[Unit]
Description=Monitoring Stack Network

[Network]
Subnet=10.89.4.0/24
Gateway=10.89.4.1
DNS=192.168.1.69
```

### 2. Grafana Router Entry
**Location:** `~/containers/config/traefik/dynamic/routers.yml`
**Add to routers section:**
```yaml
grafana-secure:
  rule: "Host(`grafana.patriark.org`)"
  service: "grafana"
  entryPoints:
    - websecure
  middlewares:
    - crowdsec-bouncer
    - rate-limit
    - tinyauth@file
  tls:
    certResolver: letsencrypt
```

**Add to services section:**
```yaml
grafana:
  loadBalancer:
    servers:
      - url: "http://grafana:3000"
```

### 3. grafana.container
**Location:** `~/.config/containers/systemd/grafana.container`
```ini
[Unit]
Description=Grafana Monitoring Dashboard
After=network-online.target monitoring-network.service
Wants=network-online.target
Requires=monitoring-network.service

[Container]
Image=docker.io/grafana/grafana:11.3.0
ContainerName=grafana
HostName=grafana
Network=systemd-reverse_proxy
Network=systemd-monitoring
Environment=GF_SERVER_ROOT_URL=https://grafana.patriark.org
Environment=GF_SERVER_DOMAIN=grafana.patriark.org
Environment=GF_SECURITY_ADMIN_USER=patriark
Environment=GF_SECURITY_ADMIN_PASSWORD=ChangeThisSecurePassword123!
Environment=GF_AUTH_DISABLE_LOGIN_FORM=false
Environment=GF_AUTH_PROXY_ENABLED=true
Environment=GF_AUTH_PROXY_HEADER_NAME=X-Forwarded-User
Environment=GF_AUTH_PROXY_HEADER_PROPERTY=username
Environment=GF_AUTH_PROXY_AUTO_SIGN_UP=true
Volume=%h/containers/data/grafana:/var/lib/grafana:Z
Volume=%h/containers/config/grafana/provisioning:/etc/grafana/provisioning:ro,Z
DNS=192.168.1.69

HealthCmd=wget --no-verbose --tries=1 --spider http://localhost:3000/api/health || exit 1
HealthInterval=30s
HealthTimeout=10s
HealthRetries=3
AutoUpdate=registry

[Service]
Restart=on-failure
TimeoutStartSec=300

[Install]
WantedBy=default.target
```

---

## Current System State

### Running Services
- ✅ Traefik (reverse proxy)
- ✅ CrowdSec (security engine)
- ✅ TinyAuth (authentication) - JUST FIXED
- ✅ Jellyfin (media server)

### Traefik Routing (File-based)
**Config location:** `~/containers/config/traefik/dynamic/`
- `routers.yml` - Service routing
- `middleware.yml` - CrowdSec, rate limiting, auth, headers
- `tls.yml` - TLS 1.2+, modern ciphers
- `security-headers-strict.yml` - HSTS, CSP, etc

### Working Directory
- Quadlets: `~/.config/containers/systemd/`
- Container data: `~/containers/data/`
- Container config: `~/containers/config/`
- Project docs: `~/fedora-homelab-containers/docs/`

---

## Immediate Actions on fedora-htpc

### 1. Fix Traefik Dashboard Access
```bash
# Check if Traefik is on auth_services network
podman network inspect systemd-auth_services | grep -i traefik

# If not, connect it
podman network connect systemd-auth_services traefik
systemctl --user restart container-traefik.service

# Test dashboard
curl -I https://traefik.patriark.org
```

### 2. Verify Current State
```bash
# List all networks
podman network ls

# List running containers
podman ps

# Check which networks each service is on
for svc in traefik tinyauth jellyfin crowdsec; do
  echo "=== $svc ==="
  podman inspect $svc | grep -A 3 '"Networks"'
done
```

### 3. Create Monitoring Network
```bash
cd ~/.config/containers/systemd/
nano monitoring.network
# (paste content from above)

systemctl --user daemon-reload
podman network ls | grep monitoring
```

---

## Reference: Design Principles (from docs)

1. **Configuration ordering** - Services depend on networks
2. **Least privilege** - Internal services on monitoring network only
3. **Defense in depth** - CrowdSec → Rate Limit → TinyAuth → Service
4. **Fail-fast** - Cheapest checks first (CrowdSec is fastest)
5. **Network segmentation** - Isolated networks by function
6. **Consistent patterns** - Follow existing quadlet structure

---

## Questions to Resolve

1. **Grafana admin password** - Use secure random or specific password?
2. **Retention policies** - Prometheus (15d?), Loki (7d?), Grafana (forever?)
3. **Version pinning** - Keep AutoUpdate=registry or pin specific versions?

---

## Git Status

**Last commit:** SSH infrastructure milestone (ee90e3a → 12f7a83)
**Working directory:** `/home/patriark/fedora-homelab-containers/` (if different on htpc)
**Branch:** main
**Pushed:** Yes, synced with GitHub

---

## MacBook → fedora-htpc Handoff

**From:** Claude Code on MacBook Air
**To:** Claude Code on fedora-htpc
**Reason:** Direct filesystem/terminal access for deployment
**Context preserved in:** This document + git repository

Continue with Traefik fix, then monitoring network creation, then Grafana deployment.
