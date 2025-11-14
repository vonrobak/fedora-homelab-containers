# Network Selection Guide

Use this decision tree to determine which networks a service needs.

## Decision Tree

### 1. Does the service need external access (web UI/API)?

**YES** → Add `systemd-reverse_proxy`
**NO** → Skip (internal only)

**Examples:**
- Jellyfin (web UI) → YES
- Database (PostgreSQL) → NO
- Monitoring exporter → NO
- Traefik (already on this network) → YES

### 2. Does the service need database access?

**YES** → Add `systemd-database` (if exists) or service-specific network
**NO** → Skip

**Examples:**
- Nextcloud (uses PostgreSQL) → YES
- Wiki.js (uses PostgreSQL) → YES
- Jellyfin (no database) → NO

### 3. Does the service provide or consume metrics?

**YES** → Add `systemd-monitoring`
**NO** → Skip

**Examples:**
- Prometheus (consumes metrics) → YES
- Node Exporter (provides metrics) → YES
- Grafana (queries Prometheus) → YES
- Vaultwarden (no metrics) → NO

### 4. Does the service handle authentication?

**YES** → Add `systemd-auth_services`
**NO** → Skip

**Examples:**
- Authelia (authentication service) → YES
- Redis (session storage for Authelia) → YES
- Jellyfin (not an auth service) → NO

### 5. Does the service process media?

**YES** → Add `systemd-media_services`
**NO** → Skip

**Examples:**
- Jellyfin (media streaming) → YES
- Plex (media streaming) → YES
- Nextcloud (file storage) → NO

### 6. Does the service manage photos?

**YES** → Add `systemd-photos`
**NO** → Skip

**Examples:**
- Immich (photo management) → YES
- Immich-ML (photo ML processing) → YES
- Jellyfin (not photos) → NO

## Network Order Matters!

**CRITICAL:** The FIRST network in the list gets the default route (internet access).

### Correct Example:

```ini
Network=systemd-reverse_proxy  # FIRST - has internet
Network=systemd-monitoring     # Second - internal only
```

Service CAN reach the internet ✓

### Incorrect Example:

```ini
Network=systemd-monitoring     # FIRST - internal only
Network=systemd-reverse_proxy  # Second
```

Service CANNOT reach the internet ✗

## Common Network Combinations

### Web Application

```ini
Network=systemd-reverse_proxy  # External access
Network=systemd-monitoring     # Metrics
```

### Web App + Database

```ini
# Database:
Network=systemd-database

# Web App:
Network=systemd-reverse_proxy  # External access (must be first!)
Network=systemd-database       # Database access
Network=systemd-monitoring     # Metrics
```

### Media Server

```ini
Network=systemd-reverse_proxy  # External access
Network=systemd-media_services # Media isolation
Network=systemd-monitoring     # Metrics
```

### Authentication Service

```ini
Network=systemd-reverse_proxy  # SSO portal access
Network=systemd-auth_services  # Auth network
Network=systemd-monitoring     # Metrics
```

### Monitoring Exporter

```ini
Network=systemd-monitoring     # Metrics only (no internet needed)
```

### Internal Worker

```ini
Network=systemd-database       # Database access (if needed)
Network=systemd-monitoring     # Metrics
# NO reverse_proxy - internal only
```

## Network Naming

**All network names MUST have `systemd-` prefix in quadlets:**

✓ Correct: `Network=systemd-reverse_proxy`
✗ Wrong: `Network=reverse_proxy`
✗ Wrong: `Network=systemd-reverse_proxy.network`

## Troubleshooting

### Service can't reach internet

**Problem:** Wrong network order
**Solution:** Put `systemd-reverse_proxy` FIRST

### Service can't connect to database

**Problem:** Not on same network
**Solution:** Add `systemd-database` to both services

### Prometheus can't scrape service

**Problem:** Service not on systemd-monitoring
**Solution:** Add `systemd-monitoring` network

### Traefik returns 502 Bad Gateway

**Problem:** Service not on systemd-reverse_proxy
**Solution:** Add `systemd-reverse_proxy` network
