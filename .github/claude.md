# GitHub Claude Code Review Instructions

You are reviewing PRs for a self-hosted homelab running 30 Podman containers on Fedora 43.
Keep reviews concise. Focus on correctness, security, and convention violations.

## Critical Conventions (flag violations)

### Traefik Routing (ADR-016)
- **ALL routing in `config/traefik/dynamic/routers.yml`** — NEVER in container labels
- Middleware ordering: CrowdSec -> rate-limit -> auth -> security-headers (fail-fast, cheapest first)
- New public services MUST have CrowdSec + rate-limit + security-headers at minimum

### Container Quadlets
- **`:Z` SELinux label** required on all bind mounts (rootless containers + SELinux enforcing)
- **First `Network=` line gets default route** — put `reverse_proxy` first if internet access needed
- **Static IPs for multi-network containers** use `.69+` convention (last octet consistent across networks)
- Quadlet files live in `~/containers/quadlets/` symlinked to `~/.config/containers/systemd/`
- Resource limits: use `MemoryHigh`/`MemoryMax` (systemd cgroup), NOT container `Memory=`
- All containers need `Slice=container.slice`

### Security
- Services with native auth (Jellyfin, Nextcloud, Immich, Vaultwarden, HA, Navidrome, Audiobookshelf) bypass Authelia — this is intentional
- New Authelia-protected subdomains need `access_control` rules in Authelia config (default_policy=deny)
- Never commit secrets (`.env`, `*.key`, `*.pem`, passwords, tokens)
- SSO portal uses standard rate-limit (100/min) NOT rate-limit-auth — Authelia's SPA makes 5-8 requests per page load; built-in regulation handles brute-force

### Filesystem & Storage
- Database directories (Prometheus, Loki, PostgreSQL) need NOCOW (`chattr +C`)
- Filesystem permission model (ADR-019): POSIX ACLs for container access, `chmod` resets ACL mask — re-apply ACLs after chmod

## Common Mistakes to Flag

- Missing `:Z` on volume mounts
- Traefik labels in quadlet files (should be in `routers.yml`)
- `Network=systemd-monitoring.network` listed before `systemd-reverse_proxy.network` (breaks internet)
- Rate limits too strict for SPA services (need burst headroom for multiple XHR calls per page load)
- `chmod` without re-applying ACLs (resets mask)
- Port bindings below 1024 (rootless containers can't bind privileged ports)

## What NOT to Flag

- Changes to `docs/AUTO-*.md` files — these are auto-generated daily
- `:latest` tags on most images — intentional update strategy (except databases and Immich which are pinned)
- Large YAML files in `config/traefik/dynamic/` — centralized config is by design
- Missing Authelia on services listed as native-auth above

## PR Description Expectations

- Deployment PRs should reference the deployment pattern used
- Config changes should note which services need restart
- Security changes should reference the relevant assessment or ADR
