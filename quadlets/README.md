# Quadlet Files

This directory contains Podman Quadlet unit files that define the container services.

**Deployed Location:** `~/.config/containers/systemd/` (symlinked to this directory)

---

## Architecture

### Symlink Approach (Since 2026-01-28)

Quadlet files are tracked in git at `~/containers/quadlets/` and symlinked to systemd's expected location:

```
~/containers/quadlets/*.container     (real files, tracked in git)
            ↓ (symlink)
~/.config/containers/systemd/*.container   (systemd loads from here)
```

**Benefits:**
- **Single source of truth:** Files in `~/containers/quadlets/` are the canonical version
- **Git tracking:** All production quadlets version-controlled
- **No sync needed:** Systemd follows symlinks automatically
- **Atomic deployments:** Quadlet + config + docs committed together

### Migration Rationale

**Previous approach:** Maintained sanitized copies in `~/containers/quadlets/` separate from deployed files in `~/.config/containers/systemd/`

**Problems:**
- Out of sync (9 services deployed but not tracked)
- Manual copy overhead after every deployment
- Configuration drift risk

**Why migration was safe:**
- ✅ All production services use Podman secrets (17/29 quadlets)
- ✅ Zero hardcoded secrets in production deployments
- ✅ Pre-commit hooks validate no secret leaks
- ✅ `.gitignore` excludes test/experimental quadlets

---

## What are Quadlets?

Quadlets are Podman's systemd integration format - simplified `.container` and `.network` files that systemd automatically converts to full systemd unit files.

**Example quadlet:**
```ini
[Container]
Image=traefik:latest
ContainerName=traefik
Network=systemd-reverse_proxy
Secret=traefik_crowdsec_api_key,type=env,target=CROWDSEC_API_KEY

[Service]
Restart=always

[Install]
WantedBy=default.target
```

**Generated systemd service:**
- Quadlet: `traefik.container` (simple, declarative)
- Generated: `traefik.service` (full systemd unit)
- Location: `/run/user/1000/systemd/generator/`

---

## Deployment Workflow

### 1. Create/Edit Quadlet

Edit the quadlet file directly (no copy needed):

```bash
nano ~/containers/quadlets/service.container
# OR
nano ~/.config/containers/systemd/service.container  # Same file via symlink
```

### 2. Reload Systemd

```bash
systemctl --user daemon-reload
```

### 3. Start/Restart Service

```bash
# Enable and start
systemctl --user enable --now service.service

# Or just restart if already running
systemctl --user restart service.service
```

### 4. Verify Deployment

```bash
# Check service status
systemctl --user status service.service

# Check container health
podman ps | grep service
podman healthcheck run service  # If health check defined
```

### 5. Commit to Git

```bash
# Use automated commit workflow
/commit-push-pr

# OR manual git workflow
git add quadlets/service.container
git commit -m "deploy: service - description"
git push
```

**Note:** Pre-commit hook automatically validates quadlets for hardcoded secrets.

---

## File Types

### Container Definitions (*.container)

Define container services with Podman-specific options.

**Common directives:**
```ini
[Container]
Image=image:tag                    # Container image
ContainerName=name                 # Container name
Network=systemd-network_name       # Pod network (can repeat)
Volume=%h/path:/container:Z        # Bind mount with SELinux label
Secret=name,type=env,target=VAR    # Podman secret as environment variable
Environment=KEY=value              # Environment variable
PublishPort=8080:80               # Port mapping (use sparingly)
HealthCmd=command                  # Container health check
MemoryMax=1G                       # Memory limit

[Service]
Restart=always                     # Restart policy
TimeoutStartSec=300               # Startup timeout

[Install]
WantedBy=default.target           # Auto-start on boot
```

### Network Definitions (*.network)

Define Podman networks for service isolation.

**Example:**
```ini
[Network]
NetworkName=monitoring
Subnet=10.89.4.0/24
Gateway=10.89.4.1
DNS=192.168.1.69
Label=app=homelab
```

---

## Security & Secrets Management

### ✅ Production Pattern: Podman Secrets

**ALL production quadlets use Podman secrets for credentials.**

**Create secret:**
```bash
echo "my-secret-value" | podman secret create service_password -
```

**Reference in quadlet:**
```ini
[Container]
Secret=service_password,type=env,target=PASSWORD
```

**Verify secret:**
```bash
podman secret ls
podman secret inspect service_password
```

### ❌ NEVER: Hardcoded Secrets

**Blocked by pre-commit hook:**
```ini
# ❌ BAD - Will be rejected by git pre-commit hook
Environment=PASSWORD=hardcoded-value
Environment=API_KEY=secret-key
Environment=TOKEN=my-token
```

**Pre-commit hook checks:**
- Scans staged quadlet files for hardcoded secrets
- Blocks commit if `Environment=PASSWORD=`, `SECRET=`, `TOKEN=`, `API_KEY=` found
- Allows config values (e.g., `PASSWORD_ITERATIONS=600000`)
- Location: `.claude/hooks/pre-commit-quadlet-secrets.sh`

### Test/Experimental Quadlets

Test quadlets with placeholder credentials are **excluded from git**:

**Naming convention:**
```
*-test.container        # Excluded by .gitignore
*-experimental.container # Excluded by .gitignore
```

**Example:** `ocis-test.container` with `OCIS_ADMIN_USER_PASSWORD=CHANGE_ME_ON_FIRST_LOGIN` is not tracked.

---

## Currently Deployed Services (29 total)

### Core Infrastructure (5)
- `traefik.container` - Reverse proxy + TLS termination
- `crowdsec.container` - IP reputation & security monitoring
- `authelia.container` - SSO authentication with YubiKey MFA
- `redis-authelia.container` - Session storage for Authelia
- `cadvisor.container` - Container metrics exporter

### Monitoring Stack (5)
- `prometheus.container` - Metrics collection & storage
- `alertmanager.container` - Alert routing to Discord
- `grafana.container` - Dashboards & visualization
- `loki.container` - Log aggregation
- `promtail.container` - Log collector
- `node_exporter.container` - System metrics exporter

### Applications (11)
- `jellyfin.container` - Media server
- `nextcloud.container` - File sync & sharing
- `nextcloud-db.container` - PostgreSQL for Nextcloud
- `nextcloud-redis.container` - Redis cache for Nextcloud
- `immich-server.container` - Photo management
- `immich-ml.container` - Machine learning for Immich
- `postgresql-immich.container` - PostgreSQL for Immich
- `redis-immich.container` - Redis for Immich
- `vaultwarden.container` - Password manager
- `collabora.container` - Online office suite
- `homepage.container` - Dashboard/homepage

### Home Automation (2)
- `home-assistant.container` - Home automation hub
- `matter-server.container` - Matter smart home protocol server

### Utilities (2)
- `gathio.container` - Event management
- `gathio-db.container` - PostgreSQL for Gathio
- `alert-discord-relay.container` - Discord webhook relay
- `unpoller.container` - UniFi metrics exporter

### Networks (5)
- `reverse_proxy.network` - Public-facing services (10.89.2.0/24)
- `monitoring.network` - Monitoring stack (10.89.4.0/24)
- `auth_services.network` - Authentication services (10.89.3.0/24)
- `photos.network` - Immich photo services (10.89.5.0/24)
- `home_automation.network` - Home Assistant & Matter (10.89.6.0/24)
- `media_services.network` - Media services (deprecated, services moved to reverse_proxy)

---

## Common Operations

### List All Quadlets

```bash
ls -1 ~/containers/quadlets/*.container
ls -1 ~/containers/quadlets/*.network
```

### Find Services Using Secrets

```bash
grep -l "^Secret=" ~/containers/quadlets/*.container
```

### Find Services on a Network

```bash
grep -l "Network=systemd-monitoring" ~/containers/quadlets/*.container
```

### Validate Quadlet Syntax

```bash
# Reload daemon (validates all quadlets)
systemctl --user daemon-reload

# Check specific service
systemctl --user status service.service
```

### Check Symlinks

```bash
# Verify symlinks are intact
ls -la ~/.config/containers/systemd/*.container | head -5

# Verify they point to correct location
readlink ~/.config/containers/systemd/traefik.container
# Expected: /home/patriark/containers/quadlets/traefik.container
```

---

## Troubleshooting

### Quadlet Not Loading

**Symptom:** `systemctl --user daemon-reload` doesn't generate service

**Checks:**
1. **File extension:** Must be `.container` or `.network` (not `.conf` or `.service`)
2. **Location:** Must be in `~/.config/containers/systemd/` or symlinked there
3. **Symlink intact:** `readlink ~/.config/containers/systemd/service.container`
4. **Syntax errors:** Check systemd logs: `journalctl --user -xe`

### Service Won't Start

**Check generated unit:**
```bash
systemctl --user cat service.service
```

**Check quadlet source:**
```bash
cat ~/containers/quadlets/service.container
```

**Common issues:**
- Missing network: `Network=systemd-network_name` but network doesn't exist
- Invalid volume: SELinux label `:Z` required for rootless containers
- Missing secret: Secret referenced but not created
- Port conflict: Port already in use

### Symlink Broken

**Symptom:** Service was working, now fails after git operations

**Fix:**
```bash
# Recreate symlink
cd ~/.config/containers/systemd
rm service.container
ln -s ~/containers/quadlets/service.container service.container

# Reload
systemctl --user daemon-reload
systemctl --user restart service.service
```

### Pre-Commit Hook False Positive

**If hook incorrectly blocks commit:**

1. **Review the pattern:** Check if it's actually a config value (e.g., `PASSWORD_ITERATIONS`)
2. **Add exception:** Edit `.claude/hooks/pre-commit-quadlet-secrets.sh` and add to `SAFE_PATTERNS`
3. **Bypass (last resort):** `git commit --no-verify` (NOT RECOMMENDED)

---

## References

**Official Documentation:**
- Podman Quadlet: https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html
- Systemd Service: https://www.freedesktop.org/software/systemd/man/systemd.service.html

**Homelab Documentation:**
- ADR-002: Systemd Quadlets Over Docker Compose
- ADR-009: Config vs Data Directory Strategy
- Security Guide: `docs/30-security/guides/secrets-management.md`
- Deployment Patterns: `.claude/skills/homelab-deployment/patterns/`

**Migration Documentation:**
- Proposal: (generated 2026-01-28 during migration)
- Pre-commit Hook: `.claude/hooks/pre-commit-quadlet-secrets.sh`
- Git Integration: `.git/hooks/pre-commit`

---

## Version History

| Date | Event | Details |
|------|-------|---------|
| 2025-11-21 | Initial quadlets directory | Copied from `~/.config/containers/systemd/` for version control |
| 2026-01-28 | Migration to symlink approach | Reversed to track in git, symlink to systemd location |
| 2026-01-28 | Pre-commit hook added | Automatic secret detection before commit |
| 2026-01-28 | Security audit | Verified all 17/29 services use Podman secrets |
