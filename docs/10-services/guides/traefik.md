# Traefik Reverse Proxy

**Last Updated:** 2025-11-07
**Version:** v3.2
**Status:** Production
**Networks:** reverse_proxy, auth_services, monitoring

---

## Overview

Traefik is the **gateway to all homelab services**, providing:
- Reverse proxy with automatic HTTPS
- Let's Encrypt certificate management
- Multi-layer security middleware
- Service auto-discovery via Podman socket
- Prometheus metrics export

**External access:** All internet-facing services go through Traefik on ports 80 (HTTP) → 443 (HTTPS)

---

## Quick Reference

### Access Points

- **Dashboard:** http://localhost:8080/dashboard/ (host only, no auth)
- **API:** http://localhost:8080/api
- **Metrics:** http://traefik:8080/metrics (Prometheus scrape target)

### Service Management

```bash
# Status
systemctl --user status traefik.service

# Restart (picks up config changes)
systemctl --user restart traefik.service

# Logs
journalctl --user -u traefik.service -f
podman logs -f traefik
```

### Configuration Locations

```
~/containers/config/traefik/
├── traefik.yml              # Static configuration
├── dynamic/                 # Dynamic configuration (watched)
│   ├── routers.yml         # Service routing
│   ├── middleware.yml      # Security layers
│   ├── tls.yml             # TLS configuration
│   ├── rate-limit.yml      # Rate limiting rules
│   └── security-headers-strict.yml
├── letsencrypt/            # Certificate storage
│   └── acme.json           # Let's Encrypt data
└── [safe templates in git]
```

---

## Architecture

### Network Topology

Traefik connects to **three networks** for different purposes:

```
systemd-reverse_proxy (10.89.2.0/24)
├── Traefik (gateway)
├── Jellyfin
└── TinyAuth

systemd-auth_services (10.89.3.0/24)
├── Traefik (can reach TinyAuth)
└── TinyAuth (authentication backend)

systemd-monitoring (10.89.4.0/24)
├── Traefik (exports metrics)
├── Prometheus (scrapes Traefik)
└── Grafana
```

**Why multiple networks?**
- `reverse_proxy`: Front services to internet
- `auth_services`: Communicate with TinyAuth for authentication
- `monitoring`: Export metrics to Prometheus

### Security Layers (Middleware Ordering)

**All routes flow through ordered middleware:**

```
Internet Request
  ↓
[1] CrowdSec Bouncer (block malicious IPs)
  ↓
[2] Rate Limiting (prevent abuse)
  ↓
[3] TinyAuth (authentication)
  ↓
[4] Security Headers (CSP, HSTS, X-Frame-Options)
  ↓
Backend Service
```

**Why this order?** Fail fast at cheapest layer:
- CrowdSec lookup is fastest (cache)
- Rate limiting is memory-based (fast)
- Authentication is slowest (database + bcrypt)

Never waste CPU on expensive auth for blocked IPs!

---

## Configuration

### Static Configuration (traefik.yml)

**Entry Points:**
- `:80` (web) - HTTP, auto-redirects to HTTPS
- `:443` (websecure) - HTTPS with Let's Encrypt
- `:8080` (traefik) - Dashboard and metrics (internal only)

**Providers:**
- **Docker/Podman:** Auto-discover containers via socket
  - Only exposes containers with `traefik.enable=true` label
  - Uses `systemd-reverse_proxy` network by default
- **File:** Watch `dynamic/` directory for routing changes
  - Reloads automatically on file change
  - No restart required

**Certificate Management:**
- Let's Encrypt production endpoint
- TLS challenge (port 443)
- Certificates stored in `letsencrypt/acme.json`
- Auto-renewal ~30 days before expiry

**Metrics:**
- Prometheus format on `:8080/metrics`
- Includes entrypoints, routers, services, response times
- Histogram buckets: 0.1s, 0.3s, 1.0s, 3.0s, 10.0s

### Dynamic Configuration (dynamic/)

#### Routers (routers.yml)

Define which hostnames route to which services:

```yaml
http:
  routers:
    jellyfin-secure:
      rule: "Host(`jellyfin.patriark.org`)"
      entryPoints:
        - websecure
      middlewares:
        - crowdsec-bouncer@file
        - rate-limit@file
        - tinyauth@file
        - security-headers@file
      service: jellyfin
      tls:
        certResolver: letsencrypt

  services:
    jellyfin:
      loadBalancer:
        servers:
          - url: "http://jellyfin:8096"
```

**Key components:**
- `rule`: Hostname matching
- `entryPoints`: Which port (websecure = 443)
- `middlewares`: Security layers (in order!)
- `service`: Backend service definition
- `tls.certResolver`: Use Let's Encrypt

#### Middleware (middleware.yml, *.yml)

**CrowdSec Bouncer:**
```yaml
crowdsec-bouncer:
  plugin:
    bouncer:
      enabled: true
      crowdsecLapiKey: "${CROWDSEC_API_KEY}"  # Injected by entrypoint script
```

**Rate Limiting:**
```yaml
rate-limit:
  rateLimit:
    average: 50
    period: 1m
    burst: 100
```

**TinyAuth:**
```yaml
tinyauth:
  forwardAuth:
    address: "http://tinyauth:3000/auth"
    trustForwardHeader: true
    authResponseHeaders:
      - X-Forwarded-User
```

**Security Headers:**
```yaml
security-headers:
  headers:
    stsSeconds: 31536000
    stsIncludeSubdomains: true
    stsPreload: true
    contentTypeNosniff: true
    browserXssFilter: true
    frameDeny: true
```

---

## Operations

### Adding a New Service

**1. Container must be on reverse_proxy network:**
```ini
# In service.container
Network=systemd-reverse_proxy
```

**2. Option A: Auto-discovery (Docker provider)**

Add labels to container:
```ini
Label=traefik.enable=true
Label=traefik.http.routers.myservice.rule=Host(`myservice.patriark.org`)
Label=traefik.http.routers.myservice.entrypoints=websecure
Label=traefik.http.routers.myservice.tls.certresolver=letsencrypt
Label=traefik.http.services.myservice.loadbalancer.server.port=8080
```

**2. Option B: File-based routing (static services)**

Edit `config/traefik/dynamic/routers.yml`:
```yaml
http:
  routers:
    myservice-secure:
      rule: "Host(`myservice.patriark.org`)"
      entryPoints: [websecure]
      middlewares:
        - crowdsec-bouncer@file
        - rate-limit@file
        - tinyauth@file
        - security-headers@file
      service: myservice
      tls:
        certResolver: letsencrypt

  services:
    myservice:
      loadBalancer:
        servers:
          - url: "http://myservice:8080"
```

**3. Verify routing:**
```bash
# Check Traefik dashboard: http://localhost:8080
# Or check logs:
podman logs traefik | grep myservice
```

### Updating Middleware

**File-based middleware** (recommended for consistency):

1. Edit `config/traefik/dynamic/middleware.yml`
2. Save file
3. Traefik auto-reloads (watch enabled)
4. Verify: `podman logs -f traefik`

**No restart needed!** Traefik watches dynamic config directory.

### Certificate Renewal

**Automatic:**
- Let's Encrypt renews ~30 days before expiry
- Traefik handles renewal automatically
- No manual intervention required

**Check certificate status:**
```bash
# View acme.json modification time
ls -lh ~/containers/config/traefik/letsencrypt/acme.json

# Check certificate expiry in Traefik dashboard
curl -k https://jellyfin.patriark.org 2>&1 | grep 'expire'
```

### Viewing Routing Table

**Traefik Dashboard:**
```
http://localhost:8080/dashboard/
```

Shows:
- All routers (HTTP and HTTPS)
- All middlewares and their chains
- All services and health status
- Active connections
- Metrics

---

## Troubleshooting

### Service Not Accessible

**1. Check if Traefik can reach backend:**
```bash
# From Traefik container
podman exec traefik wget -O- http://service:port/

# If fails: check networks
podman inspect traefik | grep -A 10 Networks
podman inspect service | grep -A 10 Networks
```

**2. Check routing configuration:**
```bash
# View Traefik dashboard
curl http://localhost:8080/api/http/routers | python3 -m json.tool

# Check for router by name
curl http://localhost:8080/api/http/routers/servicename@file
```

**3. Check middleware chain:**
```bash
# View all middlewares
curl http://localhost:8080/api/http/middlewares | python3 -m json.tool

# Common issue: middleware name typo
# Should be: crowdsec-bouncer@file
# Not: crowdsec-bouncer (missing @file)
```

### Certificate Issues

**Certificate not issued:**
```bash
# Check Let's Encrypt rate limits (5 per week per domain)
cat ~/containers/config/traefik/letsencrypt/acme.json

# Check Traefik logs for ACME errors
podman logs traefik | grep -i acme

# Common issue: Port 443 not accessible from internet
# Verify firewall: sudo firewall-cmd --list-ports
```

**Certificate expired:**
- Should never happen (auto-renewal)
- Check Traefik has been running continuously
- Check acme.json file permissions (should be readable by container)

### Middleware Not Applied

**Symptoms:**
- Service accessible without authentication
- No rate limiting
- Security headers missing

**Diagnosis:**
```bash
# Check router configuration
curl http://localhost:8080/api/http/routers/servicename@file | grep middlewares

# Verify middleware exists
curl http://localhost:8080/api/http/middlewares/tinyauth@file
```

**Common causes:**
1. Wrong middleware name (typo)
2. Missing `@file` suffix for file-based middleware
3. Middleware not defined in middleware.yml
4. Incorrect middleware ordering

### Dashboard 404 After Login

**Problem:** TinyAuth login succeeds but dashboard returns 404

**Cause:** Traefik not on `systemd-auth_services` network

**Solution:**
```bash
# Traefik quadlet must have:
Network=systemd-auth_services

# Verify:
podman inspect traefik | grep -A 10 Networks
```

---

## Monitoring

### Metrics Exported

**Available at:** `http://traefik:8080/metrics`

**Key metrics:**
- `traefik_entrypoint_requests_total` - Total requests per entrypoint
- `traefik_entrypoint_request_duration_seconds` - Response time histograms
- `traefik_router_requests_total` - Requests per router
- `traefik_service_requests_total` - Requests per backend service
- `traefik_entrypoint_open_connections` - Active connections

**Prometheus scrape config:**
```yaml
- job_name: 'traefik'
  static_configs:
    - targets: ['traefik:8080']
```

### Health Check

**Built-in ping endpoint:**
```bash
curl http://localhost:8080/ping
# Should return: OK
```

**Service status:**
```bash
systemctl --user status traefik.service
# Should show: active (running)

podman healthcheck run traefik  # If health check defined
```

---

## Security Considerations

### Secrets Management

**CrowdSec API Key:**
- Stored in Podman secret: `crowdsec_api_key`
- Injected by entrypoint script: `/traefik-entrypoint.sh`
- Environment variable: `$CROWDSEC_API_KEY`
- **Never commit to git!**

**Create/update secret:**
```bash
# Create
echo "your-api-key" | podman secret create crowdsec_api_key -

# Update (must recreate)
podman secret rm crowdsec_api_key
echo "new-api-key" | podman secret create crowdsec_api_key -
systemctl --user restart traefik.service
```

### Dashboard Access

**Currently:** Internal only (localhost:8080)
- No authentication required
- Only accessible from host machine
- Not exposed via entrypoints

**If exposing externally:**
1. Add BasicAuth middleware
2. Create secure password hash
3. Apply middleware to dashboard router
4. Consider IP whitelisting

**Not recommended** unless absolutely necessary (dashboard contains sensitive routing info).

### TLS Configuration

**Current setup:**
- TLS 1.2 minimum (configured in tls.yml)
- Modern cipher suites only
- HSTS enabled (31536000 seconds = 1 year)
- Automatic HTTP → HTTPS redirect

**Certificate storage:**
- `acme.json` should be mode 600 (readable only by user)
- Contains private keys - protect carefully!
- Backed up with container config

---

## Backup and Recovery

### What to Backup

**Essential:**
- `config/traefik/` (all configuration)
- `config/traefik/letsencrypt/acme.json` (certificates)

**Not needed:**
- Container itself (recreate from quadlet)
- Logs (in journald)

### Restore Procedure

```bash
# 1. Restore config directory
cp -r backup/traefik ~/containers/config/

# 2. Ensure acme.json permissions
chmod 600 ~/containers/config/traefik/letsencrypt/acme.json

# 3. Restart service
systemctl --user restart traefik.service

# 4. Verify certificates loaded
curl http://localhost:8080/api/http/routers | grep tls
```

### Disaster Recovery

**If acme.json lost:**
1. Traefik will request new certificates from Let's Encrypt
2. May hit rate limits if done frequently (5/week per domain)
3. Downtime during certificate issuance (~2 minutes)

**Prevention:** Regularly backup `letsencrypt/acme.json`

---

## Performance Tuning

### Connection Limits

**Current:** Defaults (unlimited connections)

**If needed:**
```yaml
# In traefik.yml
entryPoints:
  websecure:
    address: ":443"
    transport:
      respondingTimeouts:
        readTimeout: 60s
        writeTimeout: 60s
```

### Rate Limiting Adjustment

**Global rate limit** (all services):
- Current: 50 requests/minute per IP
- Burst: 100 requests
- Location: `dynamic/rate-limit.yml`

**Per-service rate limits:**
- Create separate middleware: `rate-limit-api`, `rate-limit-auth`
- Apply to specific routers
- Useful for expensive endpoints

---

## Related Documentation

- **Deployment:** `docs/10-services/journal/2025-10-25-day06-traefik-quadlet-deployment.md`
- **Routing details:** `docs/10-services/journal/2025-10-25-day06-traefik-routing-config.md`
- **Middleware patterns:** `docs/00-foundation/guides/middleware-configuration.md`
- **ADR:** `docs/00-foundation/decisions/2025-10-25-decision-002-systemd-quadlets-over-compose.md`

---

## Common Commands

```bash
# Status
systemctl --user status traefik.service
podman ps | grep traefik

# Restart
systemctl --user restart traefik.service

# Logs (follow)
journalctl --user -u traefik.service -f
podman logs -f traefik

# Configuration test (dry-run)
podman run --rm -v ~/containers/config/traefik:/etc/traefik:ro,Z \
  traefik:v3.2 traefik --configFile=/etc/traefik/traefik.yml --dry-run

# View routing table
curl http://localhost:8080/api/http/routers | python3 -m json.tool

# Check specific service
curl http://localhost:8080/api/http/services/jellyfin@file

# Metrics
curl http://localhost:8080/metrics | grep traefik_entrypoint
```

---

**Maintainer:** patriark
**Last Service Restart:** (check `systemctl --user status traefik.service`)
**Configuration Version:** v3.2
