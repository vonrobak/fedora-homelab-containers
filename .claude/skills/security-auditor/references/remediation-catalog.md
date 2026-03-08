# Remediation Catalog

Tested fixes with effort estimates for all common findings. Referenced by SKILL.md Phase 4 (Risk Assessment).

Effort levels: **Quick** (< 5 min), **Medium** (< 1 hour), **Significant** (requires planning/downtime).

---

## Table of Contents

- [AUTH Remediations](#auth-remediations)
- [NETWORK Remediations](#network-remediations)
- [TRAEFIK Remediations](#traefik-remediations)
- [CONTAINERS Remediations](#containers-remediations)
- [MONITORING Remediations](#monitoring-remediations)
- [SECRETS Remediations](#secrets-remediations)
- [COMPLIANCE Remediations](#compliance-remediations)

---

## AUTH Remediations

### SA-AUTH-01: Authelia service not running
**Root cause:** Service crash, config error, or system restart without lingering enabled.
**Fix:**
```bash
systemctl --user start authelia.service
systemctl --user enable authelia.service  # Ensure auto-start
```
**Effort:** Quick
**Verify:** `systemctl --user is-active authelia.service && podman exec authelia wget -q -O- http://localhost:9091/api/health`
**Prevent:** Ensure `WantedBy=default.target` in quadlet. Check journal for crash cause.

### SA-AUTH-02: Authelia health endpoint not responding
**Root cause:** Internal error (database connection, config parse failure, Redis connectivity).
**Fix:**
```bash
# Check what's wrong
podman logs authelia --tail 30
# Restart if transient
systemctl --user restart authelia.service
# If config error, fix config then restart
nano ~/containers/config/authelia/configuration.yml
```
**Effort:** Quick (restart) / Medium (config fix)
**Verify:** `podman exec authelia wget -q -O- http://localhost:9091/api/health`
**Prevent:** Config validation before restart. Test changes with `podman exec authelia authelia validate-config`.

### SA-AUTH-03: Redis-authelia not running
**Root cause:** Service crash or system restart.
**Fix:**
```bash
systemctl --user start redis-authelia.service
```
**Effort:** Quick
**Verify:** `systemctl --user is-active redis-authelia.service`
**Prevent:** Authelia quadlet should have `Requires=redis-authelia.service` and `After=redis-authelia.service`.
**Side effect:** Restarting Redis clears all Authelia sessions — all users will be logged out.

### SA-AUTH-04: Default policy not deny
**Root cause:** Accidental config edit.
**Fix:**
```bash
# In config/authelia/configuration.yml, ensure:
# access_control:
#   default_policy: deny
nano ~/containers/config/authelia/configuration.yml
systemctl --user restart authelia.service
```
**Effort:** Quick
**Verify:** `grep "default_policy: deny" ~/containers/config/authelia/configuration.yml`
**Prevent:** Git diff review before committing Authelia config changes.

### SA-AUTH-05: Domain missing access_control rule
**Root cause:** New service deployed without adding Authelia access_control entry. Default policy (deny) blocks access.
**Fix:**
```bash
# Add rule to config/authelia/configuration.yml under access_control.rules:
# - domain: "newservice.patriark.org"
#   policy: two_factor
#   subject: "group:admins"
nano ~/containers/config/authelia/configuration.yml
systemctl --user restart authelia.service
```
**Effort:** Quick
**Verify:** Access the domain in browser — should get Authelia login, not 403.
**Prevent:** Always add access_control rules when adding new Authelia-protected routers.

### SA-AUTH-06: Redis exposed on host port
**Root cause:** `PublishPort=6379:6379` in Redis quadlet.
**Fix:**
```bash
# Remove PublishPort line from quadlet
nano ~/containers/quadlets/redis-authelia.container
systemctl --user daemon-reload
systemctl --user restart redis-authelia.service
```
**Effort:** Quick
**Verify:** `ss -tlnp | grep ":6379"` — should return nothing.
**Prevent:** Never publish Redis ports. Container network access is sufficient.

---

## NETWORK Remediations

### SA-NET-01: CrowdSec not running
**Root cause:** Service crash, container image pull failure, or system restart.
**Fix:**
```bash
systemctl --user start crowdsec.service
```
**Effort:** Quick
**Verify:** `systemctl --user is-active crowdsec.service && podman exec crowdsec cscli capi status`
**Prevent:** Check journal for crash reason. Ensure auto-start enabled.

### SA-NET-02: CrowdSec CAPI disconnected
**Root cause:** Network connectivity issue, CAPI credential expiry, or Cloudflare/CDN blocking.
**Fix:**
```bash
# Check connectivity
podman exec crowdsec curl -s https://api.crowdsec.net/v2/watchers/login
# Re-register if credentials expired
podman exec crowdsec cscli capi register
systemctl --user restart crowdsec.service
```
**Effort:** Quick (restart) / Medium (re-register)
**Verify:** `podman exec crowdsec cscli capi status` — should show "successfully interact"
**Prevent:** Monitor with Prometheus alert on CrowdSec CAPI status.

### SA-NET-03: No active bouncers
**Root cause:** Bouncer deleted accidentally (watch out — `cscli bouncers delete` does prefix matching!), or Traefik plugin misconfigured.
**Fix:**
```bash
# Register new bouncer
podman exec crowdsec cscli bouncers add traefik-bouncer -o raw
# Update the API key in middleware.yml or Traefik env
# Then restart Traefik
systemctl --user restart traefik.service
```
**Effort:** Medium (requires updating Traefik config with new API key)
**Verify:** `podman exec crowdsec cscli bouncers list` — should show 1+ bouncers
**Prevent:** Never delete bouncers by partial name. Always use exact full name.

### SA-NET-04: Low CrowdSec scenario count
**Root cause:** Hub not updated, incomplete installation.
**Fix:**
```bash
podman exec crowdsec cscli hub update
podman exec crowdsec cscli hub upgrade
podman exec crowdsec cscli scenarios list
```
**Effort:** Quick
**Verify:** `podman exec crowdsec cscli scenarios list -o json | jq '.scenarios | length'` — should be >= 10

### SA-NET-06: Monitoring network not internal
**Root cause:** `Internal=true` missing from monitoring network definition.
**Fix:**
```bash
# In quadlets/monitoring.network, add under [Network]:
# Internal=true
nano ~/containers/quadlets/monitoring.network
systemctl --user daemon-reload
# Recreate network (requires restarting all monitoring containers)
podman network rm systemd-monitoring
systemctl --user restart prometheus.service alertmanager.service grafana.service loki.service promtail.service cadvisor.service node-exporter.service
```
**Effort:** Medium (requires restarting monitoring stack)
**Verify:** `podman network inspect systemd-monitoring | jq '.[0].internal'` — should be `true`
**Prevent:** Network definition in git, validated by security audit.

---

## TRAEFIK Remediations

### SA-TRF-02: TLS certificate expiring
**Root cause:** Let's Encrypt renewal failure (DNS-01 challenge issue, Cloudflare token expired).
**Fix:**
```bash
# Check Traefik ACME logs
podman logs traefik 2>&1 | grep -i "acme\|certificate\|renew" | tail -10

# If Cloudflare token expired, recreate:
printf '%s' '<new-token>' | podman secret create cloudflare_dns_token_new -
# Update quadlet to reference new secret, then restart

# Force renewal by removing and restarting
# (Traefik will request new certs on startup)
systemctl --user restart traefik.service
```
**Effort:** Quick (restart) / Medium (token rotation)
**Verify:** `echo | openssl s_client -connect patriark.org:443 -servername patriark.org 2>/dev/null | openssl x509 -noout -dates`
**Prevent:** Monitor cert expiry with Prometheus. Alertmanager rule on days remaining.

### SA-TRF-03: CrowdSec bouncer missing from router
**Root cause:** New router added without CrowdSec middleware.
**Fix:**
```bash
# Edit routers.yml, add crowdsec-bouncer@file as FIRST middleware
nano ~/containers/config/traefik/dynamic/routers.yml
# Traefik auto-reloads in ~60s, or:
podman exec traefik kill -SIGHUP 1
```
**Effort:** Quick
**Verify:** `yq '.http.routers["<router>"].middlewares[0]' config/traefik/dynamic/routers.yml` — should be "crowdsec-bouncer@file"
**Prevent:** Always include CrowdSec as first middleware when adding routers. Use deployment patterns.

### SA-TRF-05: Middleware ordering wrong
**Root cause:** Router has CrowdSec not as first middleware.
**Fix:** Reorder middleware in `routers.yml`. Correct order:
```yaml
middlewares:
  - crowdsec-bouncer@file      # 1. IP reputation (cheapest)
  - rate-limit@file            # 2. Rate limiting
  - authelia@file              # 3. Authentication (most expensive)
  - security-headers@file      # 4. Response headers
```
**Effort:** Quick
**Verify:** `yq '.http.routers | to_entries[] | {key: .key, first: .value.middlewares[0]}' config/traefik/dynamic/routers.yml`

### SA-TRF-06: Traefik labels in quadlets
**Root cause:** ADR-016 violation — routing defined in container labels instead of dynamic config.
**Fix:**
1. Extract routing info from the label
2. Add equivalent router + service to `config/traefik/dynamic/routers.yml`
3. Remove `Label=traefik.*` lines from the quadlet
4. `systemctl --user daemon-reload && systemctl --user restart <service>`
**Effort:** Medium
**Verify:** `grep "^Label=traefik\." ~/containers/quadlets/<service>.container` — should return nothing
**Prevent:** Always define routing in dynamic config. Never use labels.

### SA-TRF-07: Security headers missing
**Root cause:** Router added without security-headers middleware.
**Fix:**
```bash
# Add appropriate header middleware to routers.yml
# Use security-headers@file for most services
# Use hsts-only@file for services that set their own CSP (Nextcloud)
# Use service-specific variants for special requirements (Jellyfin, HA, Gathio)
nano ~/containers/config/traefik/dynamic/routers.yml
```
**Effort:** Quick
**Verify:** `curl -sI https://<domain> | grep -i "strict-transport\|x-frame\|x-content-type"`

### SA-TRF-08: Dashboard exposed on port 8080
**Root cause:** `PublishPort=8080:8080` still in Traefik quadlet.
**Fix:**
```bash
# Remove PublishPort=8080:8080 from traefik.container
nano ~/containers/quadlets/traefik.container
systemctl --user daemon-reload
systemctl --user restart traefik.service
```
**Effort:** Quick
**Verify:** `ss -tlnp | grep ":8080"` — should return nothing. Access via traefik.patriark.org instead.

---

## CONTAINERS Remediations

### SA-CTR-01: SELinux not enforcing
**Root cause:** Someone ran `setenforce 0` or modified `/etc/selinux/config`.
**Fix:**
```bash
# Temporary (immediate effect, lost on reboot)
sudo setenforce 1

# Permanent
sudo sed -i 's/SELINUX=permissive/SELINUX=enforcing/' /etc/selinux/config
```
**Effort:** Quick (setenforce) — but investigate WHY it was disabled first
**Verify:** `getenforce` — should return "Enforcing"
**Prevent:** Never disable SELinux. Fix AVC denials with proper labels instead.

### SA-CTR-02: Missing memory limits
**Root cause:** Quadlet deployed without MemoryHigh/MemoryMax directives.
**Fix:**
```bash
# Add to quadlet [Service] section:
# MemoryHigh=512M
# MemoryMax=768M
nano ~/containers/quadlets/<service>.container
systemctl --user daemon-reload
systemctl --user restart <service>.service
```
**Effort:** Quick
**Verify:** `systemctl --user show <service>.service -p MemoryMax`
**Prevent:** Use deployment patterns which include memory limits by default.
**Reference values:** Jellyfin ~200MB idle/1GB transcoding, Prometheus ~300MB, Traefik ~80MB, most services ~100-200MB.

### SA-CTR-03: Database images not pinned
**Root cause:** Using `:latest` tag for database images.
**Fix:**
```bash
# Change Image= in quadlet to specific version:
# Image=docker.io/library/postgres:17
# Image=docker.io/library/mariadb:11
nano ~/containers/quadlets/<db>.container
systemctl --user daemon-reload
systemctl --user restart <db>.service
```
**Effort:** Quick
**Verify:** `podman inspect <db> | jq -r '.[0].ImageName'`
**Prevent:** ADR-015 mandates pinning database images. Never use `:latest` for databases.

### SA-CTR-05: OOM kills detected
**Root cause:** Memory limit too low or memory leak.
**Fix:**
```bash
# Identify which container was killed
journalctl --user --since "24 hours ago" | grep -i "oom_kill\|memory\.max" | head -5

# Increase memory limit (add ~50% headroom)
# MemoryHigh=768M  (soft limit, allows burst)
# MemoryMax=1G     (hard limit, kills if exceeded)
nano ~/containers/quadlets/<service>.container
systemctl --user daemon-reload
systemctl --user restart <service>.service
```
**Effort:** Quick (limit increase) / Medium (investigating leak)
**Verify:** Monitor `podman stats <service>` — memory usage should stay below new MemoryHigh.

### SA-CTR-07: Missing healthcheck
**Root cause:** Quadlet deployed without HealthCmd directive.
**Fix:**
```bash
# Add to quadlet [Container] section. Common patterns:
# HealthCmd=curl -f http://localhost:<port>/health || exit 1
# HealthCmd=wget --spider http://127.0.0.1:<port>/healthcheck || exit 1
# HealthCmd=wget -q -O- http://localhost:<port>/api/health || exit 1
```
**Effort:** Quick
**Verify:** `podman healthcheck run <service>`
**Known exception:** Loki uses distroless image (no shell/curl/wget). Monitor via `up{job="loki"}` only.
**Note:** Audiobookshelf and Navidrome don't have curl — use `wget --spider`.

### SA-CTR-08: Missing Podman secrets
**Root cause:** Secret not created or name mismatch between quadlet and `podman secret ls`.
**Fix:**
```bash
# Create the missing secret (ALWAYS use printf, not echo, to avoid trailing newline)
printf '%s' 'secret-value' | podman secret create <name> -
```
**Effort:** Quick
**Verify:** `podman secret ls | grep <name>`
**Prevent:** Document required secrets per service. Verify after deployment.

### SA-CTR-09: Missing static IPs for multi-network containers
**Root cause:** Multi-network container on reverse_proxy without static IP assignment (ADR-018).
**Fix:**
```bash
# Add static IP to each Network= line in quadlet:
# Network=systemd-reverse_proxy.network:ip=10.89.2.XX
# Network=systemd-monitoring.network:ip=10.89.4.XX
# Use .69+ to avoid IPAM collisions. Same last octet across networks.
nano ~/containers/quadlets/<service>.container

# Update Traefik hosts file if needed
# Add entry mapping service name to its reverse_proxy IP
systemctl --user daemon-reload
systemctl --user restart <service>.service
```
**Effort:** Medium (need to choose IPs, update multiple places)
**Verify:** `podman inspect <service> | jq '.[0].NetworkSettings.Networks | to_entries[] | "\(.key): \(.value.IPAddress)"'`
**Prevent:** Always assign static IPs for multi-network services on reverse_proxy. Next available: .88.

---

## MONITORING Remediations

### SA-MON-01/02/03: Monitoring service not running
**Root cause:** Service crash, system restart, config error.
**Fix:**
```bash
systemctl --user start <service>.service
# If config error:
podman logs <service> --tail 30
```
**Effort:** Quick
**Verify:** `systemctl --user is-active <service>.service`

### SA-MON-04: Prometheus scrape targets down
**Root cause:** Target service down, network misconfigured, or port mismatch.
**Fix:**
```bash
# 1. Check if target service is running
systemctl --user is-active <target>.service

# 2. Check network connectivity
podman exec prometheus wget -q --spider -T 5 http://<target>:<port>/metrics

# 3. Verify target is on monitoring network
grep "monitoring" ~/containers/quadlets/<target>.container
```
**Effort:** Quick (restart) / Medium (network reconfiguration)
**Verify:** Prometheus targets page shows target as "up"

### SA-MON-06: Alertmanager on host port
**Root cause:** `PublishPort=9093:9093` still in Alertmanager quadlet.
**Fix:**
```bash
# Remove PublishPort line
nano ~/containers/quadlets/alertmanager.container
systemctl --user daemon-reload
systemctl --user restart alertmanager.service
```
**Effort:** Quick
**Verify:** `ss -tlnp | grep ":9093"` — should return nothing

---

## SECRETS Remediations

### SA-SEC-01: .gitignore missing patterns
**Root cause:** Incomplete .gitignore.
**Fix:**
```bash
# Add missing patterns
cat >> ~/containers/.gitignore << 'EOF'
# (add missing patterns from: *.key, *.pem, *secret*, *.env, acme.json)
EOF
```
**Effort:** Quick
**Verify:** `grep -c "\.key\|\.pem\|secret\|\.env\|acme.json" ~/containers/.gitignore` — should be >= 5

### SA-SEC-02: Secrets in git history
**Root cause:** Secret committed before .gitignore was set up, or accidental commit.
**Fix:**
```bash
# 1. IMMEDIATELY rotate the credential
# 2. Remove from history (DESTRUCTIVE — requires force push)
pip install git-filter-repo
git filter-repo --path <secret-file> --invert-paths
git push --force-with-lease
```
**Effort:** Significant (credential rotation + history rewrite)
**Verify:** `git log --all --oneline -- <secret-file>` — should return nothing
**Prevent:** Pre-commit hooks, .gitignore review. Reference **IR-002** runbook.

### SA-SEC-03: Loose file permissions
**Root cause:** File created with default umask or permissions changed accidentally.
**Fix:**
```bash
chmod 600 <secret-file>
```
**Effort:** Quick
**Verify:** `stat -c %a <secret-file>` — should be 600 or 400

---

## COMPLIANCE Remediations

### SA-CMP-01: Uncommitted changes
**Root cause:** Work in progress or forgotten changes.
**Fix:**
```bash
cd ~/containers
git status
git diff
# Then either commit or stash
git add <files> && git commit -m "description"
# or
git stash
```
**Effort:** Quick
**Verify:** `git status --porcelain | wc -l` — should be 0

### SA-CMP-02: BTRFS NOCOW missing
**Root cause:** Database directory created without `chattr +C`. NOCOW must be set on empty directory.
**Fix:**
```bash
# REQUIRES DOWNTIME — service must be stopped
systemctl --user stop <service>.service

# Backup data
cp -a /mnt/btrfs-pool/subvol7-containers/<service> /mnt/btrfs-pool/subvol7-containers/<service>.bak

# Recreate with NOCOW
rm -rf /mnt/btrfs-pool/subvol7-containers/<service>
mkdir /mnt/btrfs-pool/subvol7-containers/<service>
chattr +C /mnt/btrfs-pool/subvol7-containers/<service>

# Restore data
cp -a /mnt/btrfs-pool/subvol7-containers/<service>.bak/* /mnt/btrfs-pool/subvol7-containers/<service>/

# Restart
systemctl --user start <service>.service

# Verify
lsattr -d /mnt/btrfs-pool/subvol7-containers/<service>
```
**Effort:** Significant (requires downtime, data backup/restore)
**Verify:** `lsattr -d /mnt/btrfs-pool/subvol7-containers/<service>` — should show 'C' flag
**Prevent:** Always `chattr +C` before first data write to database directories.

### SA-CMP-03: Filesystem permission drift
**Root cause:** `chmod` resets ACL mask, system update changed permissions, manual operation.
**Fix:**
```bash
# Check what drifted
~/containers/scripts/verify-permissions.sh

# Re-apply ACLs (example for Nextcloud external storage)
setfacl -m u:100032:rwx /mnt/btrfs-pool/subvol1-docs
setfacl -d -m u:100032:rwx /mnt/btrfs-pool/subvol1-docs

# If chmod was used, re-apply after:
chmod 0755 /mnt/btrfs-pool/subvol1-docs
setfacl -m u:100032:rwx /mnt/btrfs-pool/subvol1-docs  # Must come AFTER chmod
```
**Effort:** Medium
**Verify:** `~/containers/scripts/verify-permissions.sh` — should exit 0
**Prevent:** Never use `chmod` on directories with ACLs without re-applying ACLs afterward. See ADR-019.

### SA-CMP-04: Container name mismatch
**Root cause:** ContainerName= in quadlet doesn't match filename.
**Fix:**
```bash
# Either rename the file or update ContainerName=
# Preferred: match ContainerName to filename
nano ~/containers/quadlets/<service>.container
# Set ContainerName=<service>
systemctl --user daemon-reload
systemctl --user restart <service>.service
```
**Effort:** Quick
**Verify:** `podman ps --format '{{.Names}}' | grep <service>`

### SA-CMP-05: Missing dependency declarations
**Root cause:** App container on database network without Requires/After directives.
**Fix:**
```bash
# Add to quadlet [Unit] section:
# Requires=<database>.service
# After=<database>.service
nano ~/containers/quadlets/<service>.container
systemctl --user daemon-reload
```
**Effort:** Quick
**Verify:** `systemctl --user show <service>.service -p Requires,After`
**Prevent:** Use deployment patterns which include dependency declarations.
