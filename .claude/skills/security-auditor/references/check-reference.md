# Security Audit Check Reference

Complete catalog of all 53 checks in `security-audit.sh`. Organized by category with scoring, rationale, and investigation pointers.

**Scoring:** Start at 100. L1 FAIL: -15, L2 FAIL: -5, L3 FAIL: -2. WARN: half penalty.

---

## Table of Contents

- [AUTH — Authentication & Access Control (7 checks)](#auth--authentication--access-control)
- [NETWORK — CrowdSec & Network Security (9 checks)](#network--crowdsec--network-security)
- [TRAEFIK — Reverse Proxy & TLS (9 checks)](#traefik--reverse-proxy--tls)
- [CONTAINERS — Container Security (11 checks)](#containers--container-security)
- [MONITORING — Observability Stack (7 checks)](#monitoring--observability-stack)
- [SECRETS — Secrets Management (5 checks)](#secrets--secrets-management)
- [COMPLIANCE — Configuration Drift & Standards (5 checks)](#compliance--configuration-drift--standards)

---

## AUTH — Authentication & Access Control

### SA-AUTH-01 | L1 | Authelia service running
- **Checks:** `systemctl --user is-active authelia.service`
- **Why:** Authelia protects 7 routers (patriark.org, home, traefik, grafana, prometheus, loki, events, torrent). If down, Traefik returns 401/502 to all protected services — effectively an outage.
- **FAIL penalty:** -15
- **False positives:** None. Service must be running.
- **Investigation:** See [playbooks.md — AUTH category](investigation-playbooks.md#auth--authentication--access-control)

### SA-AUTH-02 | L1 | Authelia health endpoint OK
- **Checks:** `podman exec authelia wget -q -O- http://localhost:9091/api/health` returns "OK"
- **Why:** Service can be "running" but unhealthy (database connection lost, config error). Health endpoint validates end-to-end functionality.
- **FAIL penalty:** -15
- **False positives:** Transient during container restart (< 30s). If persistent, indicates real issue.
- **Investigation:** See [playbooks.md — AUTH category](investigation-playbooks.md#auth--authentication--access-control)

### SA-AUTH-03 | L1 | Redis-authelia running
- **Checks:** `systemctl --user is-active redis-authelia.service`
- **Why:** Redis stores Authelia sessions. If down, all authenticated users get logged out and can't re-authenticate. Combined with SA-AUTH-01 failure = complete auth cascade failure.
- **FAIL penalty:** -15
- **False positives:** None.
- **Investigation:** See [playbooks.md — AUTH category](investigation-playbooks.md#auth--authentication--access-control)

### SA-AUTH-04 | L2 | Default policy is deny
- **Checks:** `grep "default_policy: deny"` in Authelia configuration.yml
- **Why:** Default deny ensures new/unconfigured domains are blocked. If changed to `bypass` or `one_factor`, all services become accessible without MFA.
- **FAIL penalty:** -5
- **False positives:** None. This is a critical security invariant.
- **Investigation:** Check for accidental config edits. Review git diff on `config/authelia/configuration.yml`.

### SA-AUTH-05 | L2 | All routed domains have access_control rules
- **Checks:** Cross-references domains from `routers.yml` against Authelia `access_control` rules. Handles wildcard `*.patriark.org`.
- **Why:** New Authelia domains require explicit `access_control` rules (default_policy is deny). Missing rules = 403 Forbidden for legitimate users.
- **WARN penalty:** -3
- **False positives:** Services with native auth (Jellyfin, Immich, Nextcloud, etc.) don't use Authelia middleware but may still appear in Authelia config for completeness. Wildcard `*.patriark.org` covers all subdomains.
- **Investigation:** Verify the flagged domain actually uses `authelia@file` middleware in its router. If not, the domain doesn't need an access_control rule.

### SA-AUTH-06 | L2 | Redis not exposed on host ports
- **Checks:** `ss -tlnp | grep ":6379"`
- **Why:** Redis has no authentication by default. Exposed on host = anyone on the network can read/write session data, potentially forging Authelia sessions.
- **FAIL penalty:** -5
- **False positives:** None. Redis should only be accessible via container networks.
- **Investigation:** Check which quadlet publishes the port. Remove `PublishPort=` directive.

### SA-AUTH-07 | L3 | Auth failure count (24h)
- **Checks:** `journalctl --user -u authelia.service --since "24 hours ago"` grep for unsuccessful/failed/denied. WARN if > 50.
- **Why:** High failure count may indicate brute force attempts, credential stuffing, or misconfigured clients. Informational — context determines severity.
- **WARN penalty:** -1 (if > 50)
- **False positives:** Legitimate typos, expired sessions causing re-auth, mobile app reconnections. Bot scanners typically produce consistent patterns.
- **Investigation:** See [playbooks.md — AUTH category](investigation-playbooks.md#auth--authentication--access-control). Cross-reference with CrowdSec alerts (SA-NET-09) and Traefik access logs.

---

## NETWORK — CrowdSec & Network Security

### SA-NET-01 | L1 | CrowdSec running
- **Checks:** `systemctl --user is-active crowdsec.service`
- **Why:** CrowdSec is the first defense layer (cheapest check). If down, rate limiting becomes the only defense against known malicious IPs.
- **FAIL penalty:** -15
- **False positives:** None.
- **Investigation:** See [playbooks.md — NETWORK category](investigation-playbooks.md#network--crowdsec--network-security)

### SA-NET-02 | L1 | CrowdSec CAPI connected
- **Checks:** `cscli capi status` shows "successfully interact"
- **Why:** CAPI provides community threat intelligence. Disconnected = only local decisions, no global blocklists. Significantly reduced protection.
- **FAIL penalty:** -15
- **False positives:** Transient network issues (< 5 min). Persistent disconnection is a real problem.
- **Investigation:** Check internet connectivity from CrowdSec container. Verify CAPI credentials.

### SA-NET-03 | L1 | Active bouncers registered
- **Checks:** `cscli bouncers list -o json | jq 'length'` > 0
- **Why:** Without a bouncer, CrowdSec detects threats but can't enforce decisions. Traefik bouncer plugin must be registered and active.
- **FAIL penalty:** -15
- **False positives:** None. At least 1 bouncer (Traefik plugin) is required.
- **Known gotcha:** `cscli bouncers delete` does prefix matching — deleting "traefik-bouncer" deletes ALL bouncers matching that prefix.
- **Investigation:** Check Traefik CrowdSec plugin configuration in `middleware.yml`. Re-register bouncer if needed.

### SA-NET-04 | L2 | CrowdSec scenarios loaded (>= 10)
- **Checks:** `cscli scenarios list -o json | jq '.scenarios | length'`
- **Why:** Scenarios define what CrowdSec detects (HTTP scanners, brute force, etc.). < 10 suggests incomplete installation or failed hub update.
- **WARN penalty:** -3
- **False positives:** Fresh installation may have fewer. Should stabilize after first hub update.
- **Investigation:** Run `cscli hub update && cscli hub upgrade`.

### SA-NET-05 | L2 | No unexpected low ports (< 1024)
- **Checks:** `ss -tlnp` for listening ports < 1024. Expected: 22 (SSH), 53 (DNS), 80/443 (HTTP/S), 631 (CUPS).
- **Why:** Unexpected low ports may indicate unauthorized services or compromised daemons.
- **WARN penalty:** -3
- **False positives:** Port 27500 is passimd (Passim firmware distribution daemon from fwupd/LVFS) — legitimate Fedora system service. Other unexpected ports require investigation.
- **Investigation:** `ss -tlnp | grep :<port>` to identify the process. Cross-reference with `systemctl list-units`.

### SA-NET-06 | L2 | Monitoring network is Internal=true
- **Checks:** `podman network inspect systemd-monitoring | jq '.[0].internal'`
- **Why:** Internal network prevents monitoring containers from reaching the internet. Limits blast radius if a monitoring component is compromised.
- **FAIL penalty:** -5
- **False positives:** None. This is an intentional security design (hardened 2026-03-01).
- **Investigation:** Check `quadlets/monitoring.network` for `Internal=true`.

### SA-NET-07 | L2 | No Samba ports (139/445)
- **Checks:** `ss -tlnp | grep ":139\|:445"`
- **Why:** Samba was decommissioned (ADR-019, 2026-02-22). These ports should remain closed.
- **FAIL penalty:** -5
- **False positives:** None. Samba is decommissioned.
- **Investigation:** Check if `smb.service` or `nmb.service` was accidentally re-enabled.

### SA-NET-08 | L3 | CrowdSec active decisions count
- **Checks:** `cscli decisions list -o json | jq 'length'`
- **Why:** Informational — shows how many IPs/ranges are currently blocked. Zero decisions after extended runtime may indicate CrowdSec isn't processing logs.
- **Always PASS** (informational metric)
- **False positives:** N/A — purely informational.
- **Investigation:** If consistently 0, verify Traefik access log acquisition. Check `cscli metrics`.

### SA-NET-09 | L3 | CrowdSec alerts (24h)
- **Checks:** `cscli alerts list --since 24h -o json | jq 'length'`. WARN if > 100.
- **Why:** High alert volume may indicate active attack, misconfigured scenario, or noisy log source.
- **WARN penalty:** -1 (if > 100)
- **False positives:** Automated scanners generate steady alert volume. Spikes correlated with SA-AUTH-07 may indicate targeted attack.
- **Investigation:** See [playbooks.md — NETWORK category](investigation-playbooks.md#network--crowdsec--network-security). Check alert type breakdown.

---

## TRAEFIK — Reverse Proxy & TLS

### SA-TRF-01 | L1 | Traefik running
- **Checks:** `systemctl --user is-active traefik.service`
- **Why:** Traefik is the gateway to all services. If down, nothing is accessible externally.
- **FAIL penalty:** -15
- **False positives:** None.
- **Investigation:** `journalctl --user -u traefik.service -n 50`.

### SA-TRF-02 | L1 | TLS certificates valid > 7 days
- **Checks:** Parses `acme.json` inside Traefik container, checks certificate expiry dates.
- **Why:** Expired certificates break HTTPS for all services. 7-day threshold gives time for Let's Encrypt renewal issues.
- **FAIL penalty:** -15 (any cert < 7 days)
- **WARN:** Could not read acme.json (-8)
- **False positives:** None. Certificates are managed by Let's Encrypt DNS-01 challenge via Cloudflare API.
- **Investigation:** Check `podman logs traefik | grep -i acme` for renewal errors. Verify Cloudflare DNS token is valid.

### SA-TRF-03 | L1 | CrowdSec bouncer in all public routers
- **Checks:** All websecure routers have `crowdsec-bouncer@file` in their middleware list.
- **Why:** Missing CrowdSec on a router = that endpoint has no IP reputation filtering. Attackers will discover and target it.
- **FAIL penalty:** -15
- **False positives:** None. All internet-facing routers must have CrowdSec.
- **Investigation:** Check `routers.yml` for the specific router missing the middleware.

### SA-TRF-04 | L2 | Rate limiting in all public routers
- **Checks:** All websecure routers have a middleware matching `rate-limit` pattern.
- **Why:** Rate limiting prevents resource exhaustion and brute force. Multiple rate limit tiers exist (standard, public, strict, per-service).
- **WARN penalty:** -3
- **False positives:** None. All routers should have some form of rate limiting.
- **Investigation:** Check which router is missing rate limiting. Add appropriate tier.

### SA-TRF-05 | L2 | Middleware ordering correct (CrowdSec first)
- **Checks:** `crowdsec-bouncer@file` is the first middleware in all router middleware chains.
- **Why:** Fail-fast principle — CrowdSec (IP cache lookup) is the cheapest check. Running auth before CrowdSec wastes resources on known-bad IPs.
- **WARN/FAIL penalty:** -3/-5
- **False positives:** None. CrowdSec must always be first.
- **Investigation:** Reorder middleware in `routers.yml`. Correct order: crowdsec → rate-limit → authelia → security-headers.

### SA-TRF-06 | L2 | No Traefik labels in quadlets (ADR-016)
- **Checks:** No `^Label=traefik.` lines in any `.container` quadlet file.
- **Why:** ADR-016 mandates all routing in dynamic config files. Labels create sync issues, bypass centralized audit, and violate separation of concerns.
- **FAIL penalty:** -5
- **False positives:** Only checks lines starting with `Label=traefik.`. Comments, dependencies (`After=traefik.service`), and CrowdSec scenario names are excluded.
- **Investigation:** Move routing from container labels to `config/traefik/dynamic/routers.yml`.

### SA-TRF-07 | L2 | Security headers on all routers
- **Checks:** Websecure routers have `security-headers` or `hsts-only` middleware. Allows up to 2 exceptions (SSO portal sets own headers, plus one).
- **Why:** Security headers (CSP, HSTS, X-Frame-Options, etc.) mitigate XSS, clickjacking, and MIME sniffing attacks.
- **WARN penalty:** -3
- **Known acceptable exceptions:** SSO portal (Authelia sets own headers). Streaming services and native-auth services use service-specific header variants (security-headers-jellyfin, security-headers-ha, security-headers-gathio).
- **Investigation:** See [playbooks.md — TRAEFIK category](investigation-playbooks.md#traefik--reverse-proxy--tls). Check which routers lack headers.

### SA-TRF-08 | L2 | Dashboard not on host port 8080
- **Checks:** `ss -tlnp | grep ":8080"`
- **Why:** Traefik dashboard exposes routing configuration, middleware chains, and backend addresses. Was hardened 2026-03-01 to only be accessible via Authelia at traefik.patriark.org.
- **FAIL penalty:** -5
- **False positives:** Other services on port 8080 would trigger this. Check process with `ss -tlnp`.
- **Investigation:** Remove `PublishPort=8080:8080` from Traefik quadlet.

### SA-TRF-09 | L3 | TLS 1.2 minimum configured
- **Checks:** `grep "minVersion.*VersionTLS12\|minVersion.*1.2"` in `tls.yml`
- **Why:** TLS 1.0/1.1 have known vulnerabilities. TLS 1.2 is the minimum acceptable version.
- **WARN penalty:** -1
- **False positives:** Traefik defaults to TLS 1.2 even without explicit config, but explicit is preferred for auditability.
- **Investigation:** Add `minVersion: VersionTLS12` to `config/traefik/dynamic/tls.yml`.

---

## CONTAINERS — Container Security

### SA-CTR-01 | L1 | SELinux enforcing
- **Checks:** `getenforce` returns "Enforcing"
- **Why:** SELinux provides mandatory access control that prevents container escapes. Disabling it removes a critical defense layer.
- **FAIL penalty:** -15
- **False positives:** None. SELinux must be enforcing on Fedora.
- **Investigation:** `getenforce`, `sestatus`. Check if someone ran `setenforce 0` or modified `/etc/selinux/config`.

### SA-CTR-02 | L2 | All containers have memory limits
- **Checks:** Running containers have `MemoryMax=` or `MemoryHigh=` in their quadlet files.
- **Why:** Without memory limits, a single container can consume all system RAM, causing OOM kills across all services.
- **WARN penalty:** -3
- **False positives:** None. All containers should have memory limits via systemd cgroup controls.
- **Investigation:** Add `MemoryHigh=` and `MemoryMax=` to the quadlet's `[Service]` section. See existing containers for baseline values.

### SA-CTR-03 | L2 | Database images pinned
- **Checks:** Database quadlets (postgresql-*, nextcloud-db, gathio-db) use pinned version tags, not `:latest`.
- **Why:** Database major version upgrades require migration. Auto-pulling `:latest` can break data compatibility silently.
- **FAIL penalty:** -5
- **False positives:** None. Databases must be pinned (ADR-015).
- **Investigation:** Pin to current major version (e.g., `:17` for PostgreSQL, `:11` for MariaDB).

### SA-CTR-04 | L2 | Volume mounts have SELinux labels
- **Checks:** Bind mounts to user paths (`/home`, `/mnt`, `~`) have `:Z` or `:z` SELinux label.
- **Why:** Without SELinux labels, rootless containers can't access bind-mounted files (permission denied). Also indicates the mount isn't being relabeled for container access isolation.
- **WARN penalty:** -3
- **False positives:** System paths and Podman internals (`%h/.local`) are excluded. Some mounts intentionally use `:ro,z` (lowercase z for shared access).
- **Investigation:** Add `:Z` (private) or `:z` (shared) to the Volume= directive.

### SA-CTR-05 | L2 | No OOM kills (24h)
- **Checks:** `journalctl --user --since "24 hours ago"` for OOM kill patterns.
- **Why:** OOM kills indicate memory limits are too low or memory leaks. Repeated OOM kills degrade service availability.
- **WARN penalty:** -3
- **False positives:** cAdvisor monitoring logs may contain informational OOM mentions that aren't actual kills. Check the specific journal entries.
- **Investigation:** See [playbooks.md — CONTAINERS category](investigation-playbooks.md#containers--container-security). Identify which container was killed.

### SA-CTR-06 | L2 | Network ordering correct
- **Checks:** Multi-network containers with `reverse_proxy` have it as their first `Network=` line.
- **Why:** First network gets default route. If monitoring (internal, no internet) is first, the container can't reach the internet even though it's on reverse_proxy.
- **WARN penalty:** -3
- **False positives:** Containers that intentionally don't need internet access (backend-only databases). These typically aren't on reverse_proxy anyway.
- **Investigation:** Reorder `Network=` lines in the quadlet file. Put `reverse_proxy` first.

### SA-CTR-07 | L2 | Healthchecks defined
- **Checks:** Running containers have `HealthCmd=` in their quadlet files.
- **Why:** Without healthchecks, container failures go undetected by systemd and Prometheus. Autonomous operations can't detect and remediate unhealthy services.
- **WARN penalty:** -3
- **Known exception:** Loki uses a distroless image with no shell — external monitoring via `up{job="loki"}` only.
- **Investigation:** Add appropriate healthcheck. See existing containers for patterns (wget, curl, or native health endpoints).

### SA-CTR-08 | L2 | Podman secrets resolve
- **Checks:** All `Secret=` directives in quadlets reference secrets that exist in `podman secret ls`.
- **Why:** Missing secrets cause container startup failures. This is a deployment-time check.
- **FAIL penalty:** -5
- **False positives:** None. If a secret is declared, it must exist.
- **Investigation:** Create the missing secret with `printf '%s' 'value' | podman secret create name -`. Note: always use `printf '%s'` (not `echo`) to avoid trailing newlines.

### SA-CTR-09 | L2 | Static IPs for multi-network containers (ADR-018)
- **Checks:** Containers on reverse_proxy + other networks have `ip=10.` in their Network= lines.
- **Why:** Podman's aardvark-dns returns container IPs in undefined order across networks. Without static IPs, Traefik may route through the wrong network, causing untrusted proxy errors.
- **WARN penalty:** -3
- **False positives:** Backend-only containers (e.g., nextcloud-db on nextcloud+monitoring) don't need static IPs since Traefik doesn't route to them directly.
- **Convention:** Static IPs use .69+ to avoid IPAM collisions. Same last octet per service across networks.
- **Investigation:** Add static IP assignments. See ADR-018 and existing multi-network containers for examples.

### SA-CTR-10 | L3 | Container images < 30 days old
- **Checks:** `podman images --format json` — image creation timestamps.
- **Why:** Old images may have known vulnerabilities. 30 days is the threshold for staleness.
- **WARN penalty:** -1
- **False positives:** Pinned database images (SA-CTR-03) may be older by design. Immich is pinned to specific versions. Focus on `:latest` images that should auto-update.
- **Investigation:** Run `podman pull <image>` or use `scripts/update-before-reboot.sh`.

### SA-CTR-11 | L3 | Slice directive in all quadlets
- **Checks:** All `.container` files have a `Slice=` directive.
- **Why:** Slice groups containers under a systemd cgroup slice for unified resource accounting and limits.
- **WARN penalty:** -1
- **False positives:** None. All containers should use `Slice=container.slice`.
- **Investigation:** Add `Slice=container.slice` to the quadlet's `[Service]` section.

---

## MONITORING — Observability Stack

### SA-MON-01 | L1 | Prometheus running
- **Checks:** `systemctl --user is-active prometheus.service`
- **Why:** Prometheus collects all metrics. If down, SLO monitoring, alerting, and capacity planning are blind. Autonomous operations lose their primary data source.
- **FAIL penalty:** -15
- **False positives:** None.
- **Investigation:** `journalctl --user -u prometheus.service -n 50`.

### SA-MON-02 | L1 | Alertmanager running
- **Checks:** `systemctl --user is-active alertmanager.service`
- **Why:** Alertmanager routes alerts to Discord. If down, critical alerts (disk full, service down) go unnoticed.
- **FAIL penalty:** -15
- **False positives:** None.
- **Investigation:** Check journal, verify configuration at `config/alertmanager/alertmanager.yml`.

### SA-MON-03 | L1 | Grafana running
- **Checks:** `systemctl --user is-active grafana.service`
- **Why:** Grafana provides dashboard visualization and Loki log exploration. Key for incident investigation and SLO monitoring.
- **FAIL penalty:** -15
- **False positives:** None.
- **Investigation:** `podman logs grafana --tail 50`.

### SA-MON-04 | L2 | No Prometheus scrape targets down
- **Checks:** Prometheus `/api/v1/targets` API — any targets with `health=="down"`.
- **Why:** Down scrape targets = missing metrics for that service. SLOs become unreliable, alerts may not fire.
- **WARN penalty:** -3
- **False positives:** Targets may be briefly down during service restarts. Persistent downs require investigation.
- **Investigation:** See [playbooks.md — MONITORING category](investigation-playbooks.md#monitoring--observability-stack). Check the specific target's health.

### SA-MON-05 | L2 | Promtail running
- **Checks:** `systemctl --user is-active promtail.service`
- **Why:** Promtail ships logs to Loki. If down, log analysis, Traefik access log queries, and remediation decision tracking stop.
- **WARN penalty:** -3
- **False positives:** None.
- **Investigation:** `journalctl --user -u promtail.service -n 50`.

### SA-MON-06 | L2 | Alertmanager not on host port
- **Checks:** `ss -tlnp | grep ":9093"`
- **Why:** Alertmanager exposes alert silencing/inhibition APIs. Host exposure allows unauthorized alert suppression. Hardened 2026-03-01 to monitoring network only.
- **FAIL penalty:** -5
- **False positives:** None. Access via monitoring network (10.89.4.72) only.
- **Investigation:** Remove `PublishPort=` from Alertmanager quadlet.

### SA-MON-07 | L3 | Alert rules loaded
- **Checks:** Prometheus `/api/v1/rules` API — rule group count > 0.
- **Why:** Without alert rules, Prometheus collects metrics but never fires alerts. Complete monitoring blindness.
- **WARN penalty:** -1
- **False positives:** None. At least 1 rule group should be loaded.
- **Investigation:** Check `config/prometheus/rules/` directory. Verify rules are included in `prometheus.yml`.

---

## SECRETS — Secrets Management

### SA-SEC-01 | L1 | .gitignore covers secret patterns
- **Checks:** `.gitignore` contains patterns for `*.key`, `*.pem`, `*secret*`, `*.env`, `acme.json`.
- **Why:** Missing patterns risk accidental commit of secrets. First line of defense for secrets management.
- **FAIL penalty:** -15
- **False positives:** None. These patterns are essential.
- **Investigation:** Add missing patterns to `.gitignore`.

### SA-SEC-02 | L1 | No secrets in recent git history
- **Checks:** `git log --oneline -20 --diff-filter=A --name-only` for files matching secret-like names.
- **Why:** Even if .gitignore is correct now, secrets may have been committed in the past. Git history is permanent unless rewritten.
- **WARN penalty:** -8
- **False positives:** Files with "secret" in their name that aren't actually secrets (e.g., documentation about secrets management). Review the specific files.
- **Investigation:** If a real secret was committed, use `git filter-repo` to remove it and rotate the credential immediately.

### SA-SEC-03 | L2 | Secret files have restrictive permissions
- **Checks:** Files in `secrets/` and `config/**/secret*` have permissions 600 or 400.
- **Why:** World-readable secrets can be accessed by any process on the system.
- **WARN penalty:** -3
- **False positives:** None. Secret files should always be 600 (owner read/write) or 400 (owner read-only).
- **Investigation:** `chmod 600 <file>`.

### SA-SEC-04 | L2 | GPG commit signing enabled
- **Checks:** `git config --get commit.gpgsign` is "true"
- **Why:** GPG signing provides commit authenticity. Without it, commit authorship can be trivially spoofed.
- **WARN penalty:** -3
- **Known acceptable:** This is a user preference, not a security deficiency. Some environments don't require GPG signing.
- **Investigation:** `git config --global commit.gpgsign true`.

### SA-SEC-05 | L3 | Podman secrets count >= 3
- **Checks:** `podman secret ls | wc -l` >= 3
- **Why:** Expected secrets: Authelia JWT, session, storage encryption, plus Cloudflare DNS token. Fewer suggests missing secrets or misconfiguration.
- **WARN penalty:** -1
- **False positives:** None with current infrastructure. Minimum 3 is conservative.
- **Investigation:** `podman secret ls` to see what's registered. Compare with quadlet `Secret=` directives.

---

## COMPLIANCE — Configuration Drift & Standards

### SA-CMP-01 | L2 | No uncommitted changes
- **Checks:** `git status --porcelain | wc -l` is 0
- **Why:** Uncommitted changes indicate configuration drift from the versioned state. In an emergency, restoring from git would lose these changes.
- **WARN penalty:** -3
- **False positives:** Active development produces uncommitted changes. This is expected during work sessions but should be resolved before audits.
- **Investigation:** Review changes with `git diff`. Commit or stash as appropriate.

### SA-CMP-02 | L2 | BTRFS NOCOW on database directories
- **Checks:** `lsattr -d` shows 'C' flag on Prometheus, Loki, and PostgreSQL-Immich data directories.
- **Why:** BTRFS Copy-on-Write causes severe fragmentation with database write patterns, degrading performance by 10-100x.
- **WARN penalty:** -3
- **Known acceptable:** Fixing requires empty directory recreation (stop service, backup, recreate with `chattr +C`, restore). Tracked as accepted risk.
- **Investigation:** See [remediation-catalog.md — SA-CMP-02](remediation-catalog.md#sa-cmp-02-btrfs-nocow-missing).

### SA-CMP-03 | L2 | Filesystem permissions intact
- **Checks:** Runs `scripts/verify-permissions.sh` which validates the ADR-019 permission model.
- **Why:** `chmod` resets ACL masks. System updates or manual operations can silently break the permission model, causing Nextcloud write failures to external storage.
- **WARN penalty:** -3
- **False positives:** Script not found (prints WARN with different message). Verify `scripts/verify-permissions.sh` exists and is executable.
- **Investigation:** Run `scripts/verify-permissions.sh` manually to see which permissions drifted. Re-apply with `setfacl`.

### SA-CMP-04 | L3 | Container names match quadlet filenames
- **Checks:** `ContainerName=` value in each quadlet matches the quadlet filename (minus `.container`).
- **Why:** Naming consistency enables reliable scripting, documentation references, and network DNS resolution.
- **WARN penalty:** -1
- **False positives:** None in current setup. All names should match.
- **Investigation:** Rename `ContainerName=` or the quadlet file to match.

### SA-CMP-05 | L3 | Database dependencies declared
- **Checks:** App containers on database networks (nextcloud, photos, gathio, auth_services) have `Requires=` or `After=` directives.
- **Why:** Without dependency declarations, database containers may not be started before the app, causing startup failures and data corruption risk.
- **WARN penalty:** -1
- **False positives:** Database/cache containers themselves (nextcloud-db, redis-*, postgresql-*) and infrastructure (traefik, crowdsec) are excluded from this check.
- **Investigation:** Add `Requires=<db>.service` and `After=<db>.service` to the quadlet's `[Unit]` section.
