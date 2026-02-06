# Collabora Online Service Guide

**Service:** Collabora Online (LibreOffice-based document editing)
**Image:** `docker.io/collabora/code:latest`
**Deployment:** Systemd Quadlet (Rootless Podman)
**Status:** Production
**Last Updated:** 2026-02-05

---

## Quick Reference

**Access Points:**
- **WOPI Discovery:** `http://collabora:9980/hosting/discovery` (internal only)
- **Admin Console:** `http://collabora:9980/browser/dist/admin/admin.html` (internal only)

Collabora has no public Traefik route. It is an internal-only service accessed exclusively by Nextcloud over the shared `systemd-nextcloud` network. This reduces attack surface and follows the least-privilege principle.

**Service Management:**
```bash
# Status
systemctl --user status collabora.service

# Start / Stop / Restart
systemctl --user start collabora.service
systemctl --user stop collabora.service
systemctl --user restart collabora.service

# Logs
journalctl --user -u collabora.service -f
podman logs -f collabora
```

**Health Checks:**
```bash
# Container health check
podman healthcheck run collabora

# Manual WOPI discovery test (from any container on the nextcloud network)
podman exec nextcloud curl -f http://collabora:9980/hosting/discovery
# Expected: XML response with <wopi-discovery>
```

**Critical Files:**
- Quadlet: `~/containers/quadlets/collabora.container` (symlinked to `~/.config/containers/systemd/`)
- Secret: `podman secret ls | grep collabora` (`collabora_admin_password`)
- Traefik: No route -- internal-only service (confirmed in `config/traefik/dynamic/routers.yml`)

---

## Architecture Overview

### Role in the Nextcloud Stack

Collabora Online provides browser-based document editing (Word, Excel, PowerPoint, ODF) for files stored in Nextcloud, via the WOPI protocol. Nextcloud's "Nextcloud Office" app (`richdocuments`) connects to Collabora as a backend.

```
User Browser
     |
     v
Nextcloud (nextcloud.patriark.org)
     |  WOPI protocol (internal)
     v
Collabora (collabora:9980)
     |
     v
LibreOffice engine
```

Collabora does not serve end users directly. All document editing sessions are initiated through Nextcloud, which proxies the Collabora iframe to the user's browser.

### Network Topology

```
systemd-reverse_proxy (10.89.2.0/24) -- listed FIRST for default route
    +-- Collabora  (10.89.2.74)
    +-- Nextcloud   (10.89.2.X)
    +-- Traefik     (10.89.2.40)

systemd-nextcloud (10.89.10.0/24) -- internal communication
    +-- Collabora       (10.89.10.74)
    +-- Nextcloud
    +-- nextcloud-db
    +-- nextcloud-redis
```

**Network order matters:** `reverse_proxy` is listed first in the quadlet so that Collabora gets a default route with internet access. The `nextcloud` network provides the internal path for WOPI communication.

### Static IP Assignment

Collabora uses static IPs on both networks (per ADR-018):
- `10.89.2.74` on `systemd-reverse_proxy`
- `10.89.10.74` on `systemd-nextcloud`

This avoids Podman's undefined DNS ordering issues for multi-network containers.

---

## Deployment Details

### Quadlet Configuration

Key settings from `~/containers/quadlets/collabora.container`:

| Directive | Value | Purpose |
|-----------|-------|---------|
| `Image` | `collabora/code:latest` | Collabora Online Development Edition |
| `AutoUpdate` | `registry` | Automatic image updates via `podman auto-update` |
| `aliasgroup1` | `https://nextcloud.patriark.org` | Whitelist Nextcloud as allowed WOPI client |
| `extra_params` | `--o:ssl.enable=false --o:ssl.termination=true` | SSL terminated at Traefik/Nextcloud, not Collabora |
| `dictionaries` | `en_US no_NO` | Spellcheck languages |
| `AddCapability` | `MKNOD` | Required by LibreOffice for device node creation |
| `MemoryMax` | `2G` | Hard memory ceiling |
| `MemoryHigh` | `1.8G` | Soft memory pressure threshold |
| `TimeoutStartSec` | `300` | LibreOffice initialization can be slow |

### Secrets

| Secret Name | Target | Purpose |
|-------------|--------|---------|
| `collabora_admin_password` | `password` env var | Admin console credentials |

The admin username is set directly as `admin` in the quadlet environment.

### Resource Usage

```bash
podman stats --no-stream collabora

# Expected:
# Idle:    ~80MB RAM
# Editing: up to ~2GB RAM (one or more documents open)
```

### Dependencies

```
collabora.service
    +-- After: nextcloud.service
    +-- After: network-online.target
    +-- Wants: network-online.target
```

Collabora starts after Nextcloud. It does not have a hard `Requires` dependency -- if Nextcloud is down, Collabora will still run but document editing will be unavailable.

---

## Configuration

### Nextcloud Integration

The Nextcloud Office app (`richdocuments`) must be configured to point at the Collabora server. Since Collabora is internal-only (no public route), Nextcloud reaches it via the internal container hostname.

**Check current WOPI URL:**
```bash
podman exec -u www-data nextcloud php occ config:app:get richdocuments wopi_url
```

**Set WOPI URL (if needed):**
```bash
podman exec -u www-data nextcloud php occ config:app:set richdocuments wopi_url --value="http://collabora:9980"
```

Alternatively, configure via the Nextcloud web UI: Settings -> Administration -> Office -> "Use your own server" and enter the Collabora URL.

**Verify the richdocuments app is enabled:**
```bash
podman exec -u www-data nextcloud php occ app:list | grep richdocuments
```

### Domain Whitelist

The `aliasgroup1` environment variable controls which Nextcloud instances are allowed to use this Collabora server. Currently set to `https://nextcloud.patriark.org`. If additional Nextcloud instances are added, use `aliasgroup2`, `aliasgroup3`, etc.

### SSL Configuration

Collabora runs with SSL disabled internally (`ssl.enable=false`) and SSL termination awareness enabled (`ssl.termination=true`). This means:
- Nextcloud communicates with Collabora over plain HTTP on the internal network
- Collabora knows the end-user connection is HTTPS (for correct URL generation)
- No certificate management needed inside the Collabora container

---

## Common Operations

### Rotate Admin Password

```bash
# 1. Stop Collabora
systemctl --user stop collabora.service

# 2. Remove and recreate secret
podman secret rm collabora_admin_password
echo -n "NEW_PASSWORD_HERE" | podman secret create collabora_admin_password -

# 3. Restart
systemctl --user daemon-reload
systemctl --user start collabora.service
```

### Check Supported File Formats

```bash
# Query WOPI discovery for supported MIME types
podman exec nextcloud curl -s http://collabora:9980/hosting/discovery | grep -o 'ext="[^"]*"' | sort -u
```

### Force Container Update

```bash
# Check for new image
podman auto-update --dry-run | grep collabora

# Pull and restart
podman pull docker.io/collabora/code:latest
systemctl --user restart collabora.service
```

---

## Troubleshooting

### Documents Won't Open in Nextcloud

**Symptoms:** Clicking a document in Nextcloud shows an error or infinite loading spinner.

**Diagnosis:**
```bash
# 1. Is Collabora running?
podman ps | grep collabora
systemctl --user status collabora.service

# 2. Health check passing?
podman healthcheck run collabora

# 3. Can Nextcloud reach Collabora?
podman exec nextcloud curl -f http://collabora:9980/hosting/discovery

# 4. Is the richdocuments app enabled?
podman exec -u www-data nextcloud php occ app:list | grep richdocuments

# 5. What is the configured WOPI URL?
podman exec -u www-data nextcloud php occ config:app:get richdocuments wopi_url
```

**Common Causes:**
1. **Collabora not running:** `systemctl --user start collabora.service`
2. **Wrong WOPI URL:** Must be `http://collabora:9980` (internal hostname, not a public URL)
3. **Domain whitelist mismatch:** `aliasgroup1` must match the Nextcloud domain exactly (`https://nextcloud.patriark.org`)
4. **Network issue:** Verify both containers are on the `systemd-nextcloud` network
5. **richdocuments app disabled:** Enable via `podman exec -u www-data nextcloud php occ app:enable richdocuments`

### Collabora Won't Start

**Symptoms:** Service fails or container exits immediately.

**Diagnosis:**
```bash
# Check logs for startup errors
journalctl --user -u collabora.service -n 50
podman logs collabora --tail 50

# Check if MKNOD capability is applied
podman inspect collabora | jq '.[0].HostConfig.CapAdd'

# Check networks exist
podman network ls | grep -E "reverse_proxy|nextcloud"
```

**Common Causes:**
1. **Missing MKNOD capability:** Ensure `AddCapability=MKNOD` is in the quadlet
2. **Network missing:** Create with `podman network create systemd-nextcloud --subnet 10.89.10.0/24`
3. **Secret missing:** `podman secret ls | grep collabora` -- recreate if absent
4. **IP conflict:** Another container may hold `10.89.2.74` or `10.89.10.74`

### High Memory Usage

**Symptoms:** Collabora consuming close to or exceeding its 2G limit.

**Diagnosis:**
```bash
podman stats --no-stream collabora
```

**Context:** Memory usage scales with the number of concurrent document editing sessions. Each open document consumes additional memory for the LibreOffice rendering process. Under the `MemoryMax=2G` / `MemoryHigh=1.8G` limits, the system will apply memory pressure at 1.8G and OOM-kill at 2G.

**Solutions:**
1. **Normal behavior:** Memory drops when editing sessions close. No action needed.
2. **Persistent high usage:** Restart the service to reclaim memory: `systemctl --user restart collabora.service`
3. **Frequent OOM kills:** Increase `MemoryMax` in the quadlet if concurrent editing is a regular use case.

### Admin Console Not Accessible

The admin console at `http://collabora:9980/browser/dist/admin/admin.html` is only reachable from within the container network. To access it:

```bash
# From the host (if port is not published)
podman exec collabora curl -u admin:PASSWORD http://localhost:9980/browser/dist/admin/admin.html
```

There is no public route to the admin console by design.

---

## Why Internal-Only?

Collabora was previously configured with a public Traefik route (`collabora.patriark.org`). This was removed because:

1. **No direct user access needed:** Users interact with Collabora exclusively through Nextcloud's web UI. The WOPI protocol handles all communication between Nextcloud and Collabora internally.
2. **Reduced attack surface:** One fewer public endpoint to defend with CrowdSec, rate limiting, and TLS.
3. **Simpler architecture:** No need for a separate TLS certificate, Traefik router, or middleware chain.
4. **Least-privilege principle:** Collabora only needs to be reachable by Nextcloud, not the entire internet.

The `reverse_proxy` network is still assigned (listed first) to provide Collabora with a default route for outbound internet access, which it may need for fetching remote resources or fonts.

---

## Related Documentation

- **Nextcloud Guide:** `docs/10-services/guides/nextcloud.md`
- **ADR-016:** Configuration Design Principles (routing in dynamic config, not labels)
- **ADR-018:** Static IP for Multi-Network Services
- **Stack Definition:** `.claude/skills/homelab-deployment/stacks/nextcloud.yml`
- **Network Topology:** `docs/AUTO-NETWORK-TOPOLOGY.md`

---

**Guide Version:** 1.0
**Last Updated:** 2026-02-05
**Maintained By:** patriark + Claude Code
