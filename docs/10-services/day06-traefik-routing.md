# Traefik Routing Architecture

## Current Setup

### EntryPoints
- `web` (port 80) → Redirects to websecure
- `websecure` (port 443) → Main HTTPS entry
- `traefik` (port 8080) → Dashboard/API

### Routers (to be configured)
- `jellyfin` → Matches Host(`jellyfin.lokal`) → jellyfin:8096

### How a Request Flows
```
Client → https://jellyfin.lokal
    ↓
UDM Pro (forwards to 192.168.1.70:443)
    ↓
Traefik Container (:443)
    ↓
Check: Host header == "jellyfin.lokal"? ✓
    ↓
Router: jellyfin (matched!)
    ↓
Service: jellyfin (backend)
    ↓
Container: jellyfin:8096
```

### Key Concepts
- **Matcher:** Rule that identifies requests (Host, Path, Headers)
- **Middleware:** Modifies request/response (headers, auth, rate limit)
- **Service:** Backend destination (container, IP, etc.)
- **TLS Termination:** Traefik handles HTTPS, talks HTTP to container
