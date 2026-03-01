# Network Architecture & Security Review - March 2026

**Date:** 2026-03-01
**Evaluator:** Claude Code (Opus 4.6) + live system inspection
**Scope:** Comprehensive review of homelab network architecture with security focus
**System State:** 29 containers, 8 Podman networks, 3 VLANs, 15 Traefik routers
**Health Score Baseline:** 95/100

---

## Executive Summary

The homelab's network architecture demonstrates a mature, layered security posture that rivals small-enterprise deployments. Eight purpose-scoped Podman networks enforce trust boundaries at the container level, while a defense-in-depth middleware chain processes every inbound request through four progressive cost-ordered filters. The recent migration to static IPs (.69+ convention) and DNS-01 ACME challenges resolved the last two significant operational issues (aardvark-dns ordering and geo-blocked certificate validation).

This review evaluates the architecture "as is" across six dimensions: network segmentation, traffic flow and middleware, cryptographic posture, authentication architecture, observability coverage, and attack surface analysis. It concludes with future enhancement proposals ranging from incremental improvements to a full architectural redesign.

**Overall Assessment: 9/10** -- Robust, well-documented, and operationally proven. The remaining gap is network-layer observability (UDM Pro security events), which is a known limitation acknowledged by the operator.

---

## Part 1: Architecture As-Is

### 1.1 Physical Network Topology

Traffic enters the homelab through a well-defined path with multiple filtering stages:

```
Internet (Global)
  │
  ▼
UDM Pro (fw 4.4.6)
  ├─ Geo-IP filter: Norway-only inbound
  ├─ IPS/IDS: Active (20-30 blocks/day via notifications)
  ├─ Port forwards: 80/tcp, 443/tcp → 192.168.1.70
  ├─ Firewall: Default deny WAN→LAN
  │
  ├─ VLAN: patriark-lan (192.168.1.0/24) ← Homelab host + clients
  ├─ VLAN: IoT (192.168.2.0/24)          ← Smart home devices
  └─ VLAN: WireGuard (192.168.100.0/24)  ← 3 VPN tunnels (mobile/laptop)

fedora-htpc (192.168.1.70)
  ├─ SSH: Ed25519, no password auth
  ├─ Firewall (firewalld): 80, 443, 8096, 7359/udp, SSH, mDNS
  └─ Podman (rootless, UID 1000)
      └─ 8 container networks (10.89.x.0/24)
```

**Strengths:**

- **Geo-IP filtering at the edge** is a powerful first gate. By restricting inbound connections to Norwegian IP addresses, the UDM Pro eliminates the vast majority of automated scanning, botnet traffic, and opportunistic attacks originating from global botnets. This is reflected in CrowdSec's bouncer metrics showing **zero dropped requests** since 2026-02-22 -- the firewall pre-filters effectively.
- **VLAN segmentation** separates IoT devices (which often have poor security posture) from the homelab LAN. IoT devices on 192.168.2.0/24 cannot reach container services on 192.168.1.70 without explicit firewall rules.
- **WireGuard VPN** provides encrypted remote access for three devices, avoiding the need to expose additional services or ports.

**Observations:**

- The `admin-whitelist` middleware in Traefik correctly includes 192.168.100.0/24 (WireGuard), ensuring VPN clients receive the same administrative access as LAN clients. This is a thoughtful detail.
- Port 8096 (Jellyfin) and 7359/udp (Jellyfin discovery) are open in firewalld beyond ports 80/443. Jellyfin direct-play benefits from this (clients on the LAN can bypass Traefik), but it also means Jellyfin is reachable directly from any device on the LAN without middleware protection. This is an accepted trade-off for local streaming performance.
- Port 8080 (Traefik dashboard/API) is bound to all interfaces (`0.0.0.0:8080`). While this is behind the UDM Pro's firewall (not port-forwarded), any device on the LAN can reach the Traefik API and metrics endpoint without authentication. This is discussed further in section 1.6.
- Port 8123 (Home Assistant) is similarly bound to all interfaces, reachable from the LAN directly. This is likely intentional for local automation access and mDNS discovery.
- Port 9093 (Alertmanager) is exposed on all interfaces. Alertmanager's HTTP API allows silencing alerts, which could be abused by a compromised LAN device.
- Ports 27500 and 30069 (qBittorrent) are listening on the host, with 30069 bound to both the LAN interface and localhost. These are outside the containerized infrastructure and represent an additional attack surface managed outside this stack.

### 1.2 Container Network Segmentation

Eight Podman networks enforce trust boundaries. Each uses a /24 subnet with a split allocation strategy:

| Network | Subnet | Internal | Members | Purpose |
|---------|--------|----------|---------|---------|
| **reverse_proxy** | 10.89.2.0/24 | No | 16 | Internet-facing gateway |
| **monitoring** | 10.89.4.0/24 | No | 18 | Cross-service observability |
| **auth_services** | 10.89.3.0/24 | **Yes** | 3 | Authentication backend |
| **nextcloud** | 10.89.10.0/24 | **Yes** | 3 | File sync stack isolation |
| **photos** | 10.89.5.0/24 | **Yes** | 3 | Photo processing isolation |
| **gathio** | 10.89.0.0/24 | **Yes** | 2 | Event management isolation |
| **media_services** | 10.89.1.0/24 | No | 1 | Media streaming |
| **home_automation** | 10.89.6.0/24 | No | 2 | Smart home |

**IP Allocation Convention (ADR-018, amended 2026-03-01):**

- **Dynamic range:** .2-.68 -- Podman IPAM auto-allocation, enforced via `IPRange=` on all 8 networks
- **Static range:** .69-.254 -- Manually assigned in quadlet files, consistent last octet per service across all networks
- **Why .69?** A 7-hour outage on 2026-03-01 caused by IPAM collision between a dynamically assigned IP and a static IP prompted the migration from the previous .8-.16 range to .69+, with hard IPAM boundaries

**Segmentation Analysis:**

*What works well:*

1. **Database isolation.** Every database (PostgreSQL-Immich, MariaDB-Nextcloud, MongoDB-Gathio, Redis-Authelia, Redis-Immich, Redis-Nextcloud) is confined to its application-specific internal network. No database is directly reachable from the reverse_proxy network. An attacker who compromises Traefik cannot reach any database directly.

2. **Backend service isolation.** Immich-ML, Matter Server, and all Redis/DB instances sit exclusively on internal networks. They have no route to the internet and cannot be probed from outside.

3. **Auth isolation.** The auth_services network (marked `internal: true`) contains only Authelia, Redis-Authelia, and Traefik. This is a minimal trust zone: only the components that *must* communicate for SSO are present.

4. **Static IP + hosts override.** The Traefik `/etc/hosts` override (13 entries mapping service names to reverse_proxy network IPs) eliminates the aardvark-dns undefined ordering problem. Traefik always routes through the correct network interface, preserving trusted_proxies integrity.

*Points of note:*

5. **The monitoring network is the largest trust zone (18 members).** This is inherent to the observability pattern -- Prometheus needs to scrape metrics from services across all application networks. However, it creates a broad lateral movement surface: a compromised monitoring container (e.g., cAdvisor, which runs with privileged host access for container metrics) could reach 17 other containers on this network. This is a well-known trade-off in monitoring architecture and is discussed further in section 2.5.

6. **The monitoring network is not marked `internal: true`.** It has `internal: false`, meaning containers on this network have outbound internet access. While the monitoring containers generally don't need internet (Prometheus scrapes locally, Grafana serves dashboards), some may benefit from it (Grafana plugin updates, alert-discord-relay reaching Discord's API). The trade-off is that a compromised monitoring container could exfiltrate data over the internet. Explicitly marking monitoring as internal and routing only specific containers (like alert-discord-relay) through reverse_proxy would tighten this.

7. **media_services has only one member (Jellyfin).** This network exists for future expansion (additional media services) but currently provides minimal isolation benefit since Jellyfin is also on reverse_proxy and monitoring. It demonstrates forward-thinking design.

8. **home_automation is not internal.** Home Assistant needs internet access for integrations (weather, firmware updates, cloud services), so `internal: false` is correct. Matter Server, its only companion, communicates via mDNS on the LAN side.

### 1.3 Traffic Flow and Middleware Architecture

Every external request traverses Traefik's middleware chain in a carefully ordered sequence. The architecture implements the **fail-fast cost pyramid** principle: reject invalid traffic as cheaply as possible before investing expensive resources.

```
Internet → UDM Pro (geo-filter, IPS/IDS)
  → Traefik (TLS termination on :443)
    → [1] CrowdSec Bouncer    (cache lookup, ~0.1ms)
    → [2] Rate Limiting        (memory counter, ~0.01ms)
    → [3] Authelia ForwardAuth (Redis session + crypto, ~5-50ms)
    → [4] Security Headers     (applied on response, ~0ms)
    → Backend Service
```

**Middleware inventory (24+ definitions in middleware.yml):**

The middleware configuration is notably well-organized with tiered policies for different service categories:

| Category | Middleware | Purpose |
|----------|-----------|---------|
| IP Reputation | `crowdsec-bouncer` | CAPI-enrolled community blocklist + local bans |
| Rate Limiting | 9 tiers (5/min → 600/min) | Service-appropriate traffic shaping |
| Authentication | `authelia` | ForwardAuth SSO with YubiKey MFA |
| IP Whitelisting | `admin-whitelist`, `internal-only`, `monitoring-api-whitelist` | Network-based access control |
| Security Headers | 7 variants (strict → public → service-specific) | Browser security directives |
| Reliability | `circuit-breaker`, `retry` | Fault tolerance |
| Performance | `compression`, `buffering` | Response optimization |
| Redirect | `https-redirect`, `redirect-non-www` | Canonical URL enforcement |

**Service-specific middleware chains (from routers.yml):**

| Service | Chain | Rationale |
|---------|-------|-----------|
| Vaultwarden | crowdsec → rate-limit-vaultwarden-auth → security-headers | Strictest rate limiting (5/min). No Authelia -- native auth with YubiKey |
| Traefik Dashboard | crowdsec → admin-whitelist → rate-limit-strict → authelia → security-headers-strict | Admin tier: IP whitelist + SSO + strict headers |
| Grafana | crowdsec → rate-limit → authelia → security-headers | Standard admin service |
| Jellyfin | crowdsec → rate-limit-public → compression → security-headers-jellyfin | Native auth, media-optimized CSP |
| Immich | crowdsec → rate-limit-immich → compression → security-headers | High-rate limit (500/min) for thumbnails. No circuit-breaker (breaks uploads) |
| Nextcloud | crowdsec → rate-limit-nextcloud → circuit-breaker → retry → hsts-only | CalDAV redirects, 600/min for WebDAV tree-walks |
| Authelia SSO | crowdsec → rate-limit-auth → circuit-breaker → retry → security-headers-strict | Self-protecting: strict rate limit on login endpoint |
| Navidrome | crowdsec → rate-limit-public → compression → security-headers | Public-facing with `/metrics` blocked by path rule |

**Strengths:**

- The middleware ordering is **correct and consistently enforced** across all 15 routers. CrowdSec is always first, headers always last.
- Rate limiting is exceptionally granular. Vaultwarden's 5/min limit makes brute-force mathematically infeasible when combined with PBKDF2 600k iterations.
- The Immich and Nextcloud rate limits demonstrate operational wisdom: bulk photo uploads and WebDAV directory listings generate legitimately high request volumes that would be falsely throttled by standard limits.
- Navidrome's router includes a path-based rule that blocks `/metrics` from public access, preventing Prometheus metric data leakage through the public endpoint.

**Observations:**

- The `circuit-breaker` expression (`NetworkErrorRatio() > 0.50 || ResponseCodeRatio(500, 600, 0, 600) > 0.30`) has been tuned for low-traffic homelabs. The 50% network error threshold is appropriate -- at low request volumes, a single failed healthcheck could trip a lower threshold. This tuning reflects operational experience documented in the MEMORY.md notes about circuit breaker issues.
- CrowdSec's `clientTrustedIPs` includes five network ranges (reverse_proxy, auth_services, media_services, photos, and LAN). This ensures X-Forwarded-For headers are trusted from these sources, and the real client IP is correctly identified for banning decisions. This is critical -- without it, CrowdSec would ban Traefik's container IP instead of the attacker's.

### 1.4 Cryptographic Posture

**TLS Configuration:**

```yaml
tls:
  options:
    default:
      minVersion: VersionTLS12
      cipherSuites:
        - TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
        - TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
        - TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305
```

**Analysis:**

- **TLS 1.2 minimum** is appropriate. TLS 1.0/1.1 are disabled, eliminating BEAST, POODLE, and other legacy vulnerabilities.
- All three cipher suites use **ECDHE key exchange** (forward secrecy), **AES-GCM or ChaCha20-Poly1305** authenticated encryption, and **SHA-256/384** hashing. These are NIST-recommended and represent the current best practice.
- **Missing: TLS 1.3 cipher suites.** TLS 1.3 is not explicitly listed, though Traefik supports it by default when `minVersion` is TLS 1.2. TLS 1.3 negotiation may still occur, but the explicit cipher list only contains TLS 1.2 suites. The TLS 1.3 cipher suites (`TLS_AES_128_GCM_SHA256`, `TLS_AES_256_GCM_SHA384`, `TLS_CHACHA20_POLY1305_SHA256`) are fixed in the protocol and not configurable per-server, so this is not a vulnerability -- just a documentation clarity point.

**Certificate Management (DNS-01 via Cloudflare):**

- Switched from HTTP-01 to DNS-01 challenge as of PR #107 (2026-03-01)
- **Rationale:** The UDM Pro's Norway-only geo-IP filter blocks Let's Encrypt validation servers (which originate from US/global IPs). DNS-01 bypasses this entirely by validating domain ownership through Cloudflare's API.
- The Cloudflare API token is stored as a Podman secret (`cloudflare_dns_token`) and injected as the `CF_DNS_API_TOKEN` environment variable.
- **Note on secret creation:** The MEMORY.md correctly documents that `echo` adds a trailing newline to Podman secrets -- `printf '%s'` must be used instead. This is a subtle but important operational detail.

**HSTS Configuration:**

- `max-age=31536000` (1 year), `includeSubDomains`, `preload` enabled
- `forceSTSHeader: true` -- forces HSTS even on HTTP responses (belt-and-suspenders)
- This configuration qualifies for HSTS preload list submission if desired

**Assessment:** The cryptographic posture is strong. The cipher suite selection is minimal and modern, forward secrecy is guaranteed, and certificate management is automated with a firewall-compatible challenge method.

### 1.5 Authentication Architecture

The homelab uses a **dual authentication model**: Authelia SSO for administrative services and native authentication for user-facing applications.

**Authelia SSO (protecting 8 services):**

- **MFA:** WebAuthn/FIDO2 (YubiKey-first) with TOTP fallback
- **Session storage:** Redis with AOF persistence, 128MB max, LRU eviction
- **Session policy:** 1h expiration, 15m inactivity timeout, 1-month "remember me"
- **Brute-force regulation:** 5 retries in 2 minutes → 5-minute ban
- **Default access policy:** DENY (Authelia denies all unmatched requests)
- **Password reset:** Disabled (no self-service, reducing account takeover risk)

**Native auth services (4 services):**

| Service | Auth Method | ADR | Rationale |
|---------|-------------|-----|-----------|
| Vaultwarden | Master password + YubiKey/TOTP | ADR-007 | Bitwarden client compatibility requires direct auth |
| Nextcloud | WebAuthn passwordless + TOTP | ADR-013/014 | CalDAV/CardDAV clients require direct auth |
| Jellyfin | Username + password | -- | Media player client support (Infuse, etc.) |
| Immich | Username + password | -- | Mobile app compatibility |

**Security analysis:**

- The decision to bypass Authelia for these four services is well-reasoned and documented in ADRs. Each has a legitimate technical requirement for native authentication (client app compatibility).
- Vaultwarden and Nextcloud both implement strong 2FA natively, compensating for the Authelia bypass.
- Jellyfin and Immich rely on username+password alone. While this is standard for media applications, they represent the weakest authentication links in the chain. CrowdSec + rate limiting provide the compensating controls.
- Authelia's `default_policy: deny` is the correct fail-safe configuration. Any new route that forgets to configure auth will be denied by default, rather than accidentally exposed.

### 1.6 Attack Surface Analysis

**External attack surface (internet-reachable):**

| Port | Service | Protection Layers |
|------|---------|-------------------|
| 443 | Traefik → 15 services | Geo-IP → IPS/IDS → CrowdSec → Rate Limit → [Auth] → Headers |
| 80 | Traefik (HTTP→HTTPS redirect) | Geo-IP → IPS/IDS → immediate 301 redirect |

The external attack surface is minimal: only ports 80 and 443 are forwarded through the UDM Pro. Every request must survive six layers of filtering.

**LAN attack surface (192.168.1.0/24 reachable):**

| Port | Service | Authentication | Risk |
|------|---------|----------------|------|
| 22 | SSH | Ed25519 keys only | Low |
| 8080 | Traefik Dashboard/API | **None** | Medium |
| 8096 | Jellyfin (direct) | Native auth | Low |
| 8123 | Home Assistant | Native auth | Low |
| 9093 | Alertmanager | **None** | Medium |
| 30069 | qBittorrent | Unknown | Low-Medium |

**Notable findings:**

1. **Traefik API on port 8080 without authentication on LAN.** The Traefik API endpoint (bound to `0.0.0.0:8080`) serves the dashboard, health checks, and Prometheus metrics. While not internet-exposed, any device on the LAN can access `http://192.168.1.70:8080/api/rawdata` to enumerate all routes, middleware configurations, and backend service URLs. This constitutes an information disclosure risk in a compromised-LAN scenario. The Traefik dashboard is additionally protected via Traefik's own routing (traefik.patriark.org → Authelia), but the raw API port bypasses all middleware.

2. **Alertmanager on port 9093 without authentication on LAN.** Alertmanager's HTTP API is bound to all interfaces. Its API allows creating and deleting silences, which could be used to suppress alerts during an attack. The external route through Traefik (alertmanager.patriark.org) is protected by CrowdSec + rate limiting, but the direct port bypasses all middleware.

3. **Host services outside the container stack.** qBittorrent (port 30069), CUPS (port 631, localhost-only), and a Python process (port 9096, localhost-only) are running outside the containerized infrastructure. These operate under different security controls and should be inventoried separately.

**Container-to-container lateral movement:**

The monitoring network is the primary lateral movement concern. If an attacker compromises any of the 18 containers on this network, they can reach all other monitoring network members. The most sensitive targets on this network are:

- **Prometheus (10.89.4.79):** Contains all metrics data, scrape configurations (which enumerate all services), and potentially sensitive metric labels
- **Grafana (10.89.4.77):** Contains dashboards, datasource credentials, and user sessions
- **Loki (10.89.4.83):** Contains all ingested logs, which may include sensitive operational data
- **nextcloud-db (10.89.4.2):** The Nextcloud MariaDB instance is on the monitoring network (likely for Prometheus MySQL exporter scraping). A compromised monitoring container could attempt to connect to MariaDB on port 3306.

The nextcloud-db presence on the monitoring network warrants attention. If this is for exporter access, consider whether a dedicated exporter container that bridges only the necessary networks would be more appropriate.

### 1.7 CrowdSec Threat Intelligence

**Enrollment status:** CAPI connected, sharing signals enabled, community blocklist enabled.

**Installed collections (6):**

| Collection | Coverage |
|------------|----------|
| `crowdsecurity/traefik` | Traefik access log parsing |
| `crowdsecurity/http-cve` | 20 CVE-specific detection scenarios (Log4Shell, Spring4Shell, etc.) |
| `crowdsecurity/base-http-scenarios` | SQL injection, XSS, path traversal, bad user agents |
| `crowdsecurity/linux` | Linux system-level attacks |
| `crowdsecurity/sshd` | SSH brute force (regular, slow, time-based, regreSSHion CVE) |
| `crowdsecurity/whitelist-good-actors` | Prevent false positives on known legitimate bots |

**52 active scenarios** -- this is comprehensive coverage for a homelab.

**Bouncer metrics:** Zero requests dropped since 2026-02-22. This is a positive indicator: the UDM Pro's geo-filtering is so effective that almost no malicious traffic reaches CrowdSec. This validates the defense-in-depth model -- the cheapest filter (geo-IP at the firewall) catches the bulk of attacks, and CrowdSec serves as a safety net for sophisticated threats originating from Norwegian IPs or those that bypass geo-filtering.

**Stale bouncer registrations:** 33 bouncer entries exist, 32 of which are stale (from previous Traefik instances before static IP migration). Only one bouncer is actively polling (at 10.89.2.69). The stale entries should be cleaned up for hygiene, though they pose no security risk.

### 1.8 Secrets Management

**27 Podman secrets** managed via the file driver, covering:

- Authentication secrets (Authelia JWT, session, storage keys)
- Database credentials (Nextcloud, Immich, Gathio)
- Service API keys (CrowdSec, Cloudflare, Grafana, Immich, Jellyfin)
- External integrations (Last.fm, Discord, SMTP, UnPoller)

**Assessment:**

- Secrets are encrypted at rest via Podman's secret store
- No plaintext secrets in Git (verified via .gitignore patterns)
- The CrowdSec API key is injected via an entrypoint wrapper script rather than directly in middleware.yml -- this is a good practice that keeps the key out of the Git-tracked config file
- Secret rotation follows a documented procedure (delete, recreate, restart)

### 1.9 DNS Architecture

**Pi-hole (192.168.1.69)** serves as the LAN DNS resolver. All 8 Podman networks configure Pi-hole as their DNS server via `DNS=192.168.1.69` in network quadlets.

**Implications:**

- Container DNS queries (for external domains) flow through Pi-hole, benefiting from ad/tracker blocking
- Container-to-container DNS within the same Podman network uses aardvark-dns (Podman's built-in resolver), which is overridden by `/etc/hosts` for Traefik's connections
- If Pi-hole goes down, containers lose external DNS resolution. Pi-hole runs on the Raspberry Pi (192.168.1.69), which is a separate host. This creates a cross-host dependency for container DNS resolution.

---

## Part 2: Observability and Monitoring Coverage

### 2.1 What Is Monitored

| Layer | Tool | Coverage |
|-------|------|----------|
| Network hardware | UnPoller → Prometheus | 609 metrics: WAN/LAN traffic, WiFi, client stats, system health |
| Container runtime | cAdvisor → Prometheus | CPU, memory, network, disk per container |
| Host OS | Node Exporter → Prometheus | System CPU, memory, disk, network, filesystem |
| Reverse proxy | Traefik → Prometheus | Request rates, latencies, error rates, TLS metrics |
| Application logs | Promtail → Loki | Container stdout/stderr, Traefik access logs |
| IP reputation | CrowdSec → Prometheus | Ban decisions, scenario triggers, bouncer metrics |
| Service health | SLO framework | 13 SLOs across 8 services (availability + latency) |

### 2.2 What Is NOT Monitored

| Gap | Impact | Workaround |
|-----|--------|------------|
| UDM Pro firewall block events | Cannot correlate network-layer blocks with app-layer events | Manual console review |
| UDM Pro IPS/IDS detections | No visibility into network-layer threat intelligence | Push notifications only |
| UDM Pro DPI security categories | Cannot track blocked content categories | None |
| Loki container health | Loki has no healthcheck (distroless image, no shell) | `up{job="loki"}` query |
| qBittorrent / host services | Not in container monitoring stack | Manual |
| Certificate expiry metrics | No Prometheus metric for days-until-expiry | `security-audit.sh` script |
| Inter-container traffic flows | No NetFlow/sFlow within Podman networks | None |

### 2.3 Alerting Coverage

Alertmanager routes to Discord via alert-discord-relay. The autonomous operations OODA loop runs daily (06:00 predictive, 06:30 assessment). SLO monitoring covers 8 services with budget-based alerting.

**Gap:** No alert fires if the UDM Pro's IPS/IDS blocks a sustained attack campaign. The operator learns about this through push notifications, which are not correlated with the homelab's monitoring stack.

---

## Part 3: Summary of Strengths

1. **Defense in depth is genuine, not theatrical.** Seven distinct security layers, each with a clear purpose and correct ordering. The fail-fast cost pyramid is correctly implemented.

2. **Network segmentation is principled.** Eight networks follow clear trust boundaries. Databases are isolated. Auth services are isolated. The segmentation isn't arbitrary -- each network boundary represents a deliberate security decision.

3. **Documentation and ADRs are exceptional.** Every significant architectural decision is recorded in an ADR with rationale, alternatives considered, and consequences acknowledged. This is rare even in professional environments.

4. **Operational maturity is high.** The IP collision outage on 2026-03-01 was responded to with a systematic fix (ADR-018 amendment), not a workaround. The circuit breaker issues with Immich uploads were diagnosed and documented. Problems are resolved at the root cause level.

5. **Secrets management follows platform primitives.** 27 Podman secrets, encrypted at rest, with documented rotation procedures. No plaintext secrets in Git.

6. **Rate limiting is service-aware.** Nine distinct rate limit tiers demonstrate deep understanding of each service's traffic patterns. Vaultwarden's 5/min limit is mathematically justified against brute-force attacks.

7. **Configuration as code with centralized routing.** 100% Traefik label compliance (zero labels across all quadlets). All routing in a single auditable `routers.yml` file. This is a strong architectural choice validated by 5 months of production operation.

8. **Geo-IP filtering is highly effective.** The zero CrowdSec drops since February 22 suggest that Norway-only filtering eliminates effectively all automated attack traffic at the edge, before it consumes any homelab resources.

---

## Part 4: Future Enhancement Proposals

The following proposals are organized from incremental improvements to a comprehensive redesign. The current architecture is strong; these are ideas to consider for moving from "excellent" to "best in class."

### 4.1 Incremental Improvements (Low Effort, High Value)

**4.1.1 Bind Traefik API and Alertmanager to localhost**

Currently, ports 8080 (Traefik API) and 9093 (Alertmanager) are bound to `0.0.0.0`, making them reachable from any LAN device without authentication. Binding these to `127.0.0.1` (or removing the host port entirely since Traefik routes to them internally via container DNS) would eliminate the LAN-side information disclosure and alert-silencing risks.

For Traefik, the API/dashboard is already accessible via `traefik.patriark.org` with full middleware protection. The only reason to keep 8080 open is for the Prometheus scrape target and the health check ping, both of which work via the container network.

**4.1.2 Clean up stale CrowdSec bouncer registrations**

32 stale bouncer entries from pre-static-IP Traefik instances should be removed:
```bash
podman exec crowdsec cscli bouncers list
# Delete all except the active one at 10.89.2.69
podman exec crowdsec cscli bouncers delete <stale-bouncer-name>
```

**4.1.3 Mark the monitoring network as internal**

Setting `internal: true` on the monitoring network would prevent monitoring containers from reaching the internet. The only container that needs internet access on this network is `alert-discord-relay` (to reach Discord's API). This container could be additionally placed on the `reverse_proxy` network for outbound access while keeping the monitoring network isolated.

Containers that need internet for plugin/update downloads (Grafana) are already on the reverse_proxy network and would be unaffected.

**4.1.4 Add TLS 1.3 documentation clarity**

While TLS 1.3 likely negotiates correctly (Traefik supports it by default), explicitly documenting this in the TLS config would improve auditability:
```yaml
tls:
  options:
    default:
      minVersion: VersionTLS12
      # TLS 1.3 cipher suites are fixed by the protocol spec
      # and automatically negotiated when supported by client
```

**4.1.5 Add certificate expiry monitoring**

A Prometheus metric for days-until-certificate-expiry would enable proactive alerting before the 30-day auto-renewal window. Traefik exposes this via its Prometheus metrics endpoint as `traefik_tls_certs_not_after`. Creating a Grafana panel and alert rule for this would close a monitoring gap.

### 4.2 Medium-Effort Improvements (Operational Excellence)

**4.2.1 UDM Pro syslog forwarding to Loki**

This is the single highest-value improvement for closing the network-layer observability gap. By enabling syslog forwarding from the UDM Pro to Promtail:

```
UDM Pro → Syslog (UDP 514) → Promtail → Loki → Grafana
```

This would provide:
- Real-time firewall block logs with source IPs
- IDS/IPS threat detections searchable via LogQL
- Correlation with Traefik access logs and CrowdSec decisions
- Geographic attack pattern analysis
- Time-series trend analysis of network-layer threats

This was already recommended in the February security posture evaluation and remains the top priority for network security visibility.

**4.2.2 Network policy enforcement via Podman labels**

Currently, network membership is enforced at the quadlet level but not auditable at runtime beyond `podman network inspect`. A periodic drift detection check could verify that:
- No container has joined unexpected networks
- All `internal: true` networks remain internal
- Static IP assignments match the allocation table in ADR-018
- The Traefik hosts file is synchronized with actual container IPs

This could be integrated into the existing `check-drift.sh` script.

**4.2.3 Nextcloud-db on monitoring network audit**

The Nextcloud MariaDB container (`nextcloud-db`) is on the monitoring network (10.89.4.2). If this is for Prometheus MySQL exporter scraping, consider whether the exporter could run as a sidecar within the nextcloud network and expose metrics to Prometheus via a dedicated bridge, reducing the blast radius if the monitoring network is compromised.

### 4.3 Significant Improvements (Security Hardening)

**4.3.1 mTLS for internal service communication**

Currently, all inter-container communication within Podman networks uses plaintext HTTP. While the network isolation provides confidentiality at the network layer, mutual TLS (mTLS) between Traefik and backend services would provide:

- **Authentication:** Each service cryptographically proves its identity
- **Confidentiality:** Traffic encrypted even within the container network
- **Integrity:** Protection against container-to-container MITM (unlikely but possible via ARP spoofing in container networks)

This is a significant effort increase for marginal security gain in a single-host homelab, but it aligns with zero-trust principles if the goal is "best in class."

**4.3.2 Network flow monitoring**

Currently, there is no visibility into inter-container traffic patterns. If a compromised container starts scanning other containers on its network, no alert fires. Options:

- **Podman network plugins** with flow logging
- **eBPF-based monitoring** (e.g., Cilium Hubble, though this requires Kubernetes)
- **tcpdump sampling** on container network bridges (lightweight but manual)

For a homelab, the most practical approach would be periodic `conntrack` analysis on the Podman bridge interfaces, alerting on unexpected connection patterns.

**4.3.3 WAF integration (Coraza/ModSecurity)**

The middleware configuration guide already documents a future WAF phase using the Traefik ModSecurity plugin. A WAF would provide application-layer attack detection (SQL injection, XSS, command injection) that CrowdSec's pattern-based approach may miss in novel attacks. The Coraza project (OWASP ModSecurity successor) integrates with Traefik via plugin and would slot between CrowdSec and rate limiting in the middleware chain.

### 4.4 Architectural Redesign Proposal: Explicit Security Zones

This section presents an alternative network architecture that could replace the current eight-network model. It is offered as a thought experiment for consideration, not a criticism of the current design.

**Motivation:**

The current architecture groups networks by *application function* (photos, nextcloud, media, etc.). This is intuitive and operationally clear. However, from a pure security perspective, networks can also be grouped by *trust level and data sensitivity*. This creates a model where security policy flows directly from network membership, reducing the cognitive overhead of reasoning about which security controls apply where.

**Proposed Security Zone Model:**

```
┌─────────────────────────────────────────────────────────────────┐
│                        ZONE 0: DMZ                              │
│  Trust: NONE    Exposure: Internet-facing                       │
│  Policy: Maximum filtering, TLS termination                     │
│  Members: traefik, crowdsec                                     │
│  Subnet: 10.89.0.0/24                                          │
│                                                                 │
│  Rationale: Only components that MUST touch internet traffic.   │
│  These are the most likely to be targeted. Compromise here      │
│  should not grant access to any backend service directly.       │
└────────────────────────────┬────────────────────────────────────┘
                             │ (controlled gateway)
┌────────────────────────────▼────────────────────────────────────┐
│                     ZONE 1: APPLICATION                         │
│  Trust: AUTHENTICATED    Exposure: Via Traefik only             │
│  Policy: Service-specific middleware, auth required             │
│  Members: jellyfin, nextcloud, immich-server, gathio,           │
│           home-assistant, audiobookshelf, navidrome,             │
│           homepage, vaultwarden, grafana, authelia               │
│  Subnet: 10.89.1.0/24                                          │
│                                                                 │
│  Rationale: All services that serve end-user requests.          │
│  Traefik connects here to forward authenticated requests.      │
│  Services can communicate with each other (session sharing,     │
│  SSO redirects) but cannot reach databases directly.            │
└────────────────────────────┬────────────────────────────────────┘
                             │ (database connections only)
┌────────────────────────────▼────────────────────────────────────┐
│                      ZONE 2: DATA                               │
│  Trust: INTERNAL    Exposure: Application zone only             │
│  Policy: No internet, no external access, encrypted at rest     │
│  Members: postgresql-immich, mariadb-nextcloud, redis-*,        │
│           mongodb-gathio, immich-ml                              │
│  Subnet: 10.89.2.0/24 (internal: true)                         │
│                                                                 │
│  Rationale: All persistent data stores. Compromise of an        │
│  application container allows database access (necessary),      │
│  but compromise of the DMZ does NOT reach databases.            │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                   ZONE 3: OBSERVABILITY                          │
│  Trust: INTERNAL    Exposure: Read-only access to all zones     │
│  Policy: No internet, scrape-only access, minimal attack surface│
│  Members: prometheus, grafana, loki, alertmanager, promtail,    │
│           cadvisor, node_exporter, unpoller, alert-discord-relay │
│  Subnet: 10.89.3.0/24 (internal: true, except discord relay)   │
│                                                                 │
│  Rationale: Monitoring needs broad visibility but should not    │
│  participate in any application traffic flow. Read-only access  │
│  to metrics endpoints across all zones.                         │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    ZONE 4: MANAGEMENT                            │
│  Trust: MAXIMUM    Exposure: LAN/VPN only                       │
│  Policy: IP whitelist + MFA required, audit logging             │
│  Members: authelia, redis-authelia                               │
│  Subnet: 10.89.4.0/24 (internal: true)                         │
│                                                                 │
│  Rationale: Authentication infrastructure is the highest-value  │
│  target. Compromise here means compromise of everything.        │
│  Deserves its own zone with maximum isolation.                  │
└─────────────────────────────────────────────────────────────────┘
```

**Pedagogic rationale:**

The current architecture asks: *"What application does this container belong to?"* The zone model asks: *"What is this container's trust level and blast radius?"*

Both questions are valid. The current model is more intuitive for day-to-day operations ("where is Nextcloud's database?"). The zone model is more intuitive for security reasoning ("if the DMZ is compromised, what can the attacker reach?").

**Trade-offs of the zone model:**

| Aspect | Current Model | Zone Model |
|--------|--------------|------------|
| Operational clarity | Each app's components are grouped | Must know which zone each component lives in |
| Security reasoning | Must trace connections across networks | Trust flows naturally from zone membership |
| Number of networks | 8 | 5 (simpler) |
| Database isolation | Per-app (Immich DB separate from Nextcloud DB) | All databases share a zone (can see each other) |
| Lateral movement | Contained within app boundaries | Contained within trust levels |
| Multi-network containers | Many services on 3 networks | Most services on 1-2 zones |
| Complexity | More networks, clearer app boundaries | Fewer networks, clearer security boundaries |

**Key concern with the zone model:** Placing all databases in a single zone means postgresql-immich could theoretically reach mariadb-nextcloud. The current model prevents this by isolating them in separate app-specific networks. This is a real trade-off: fewer networks with broader trust vs. more networks with narrower trust.

**Hybrid alternative:** Keep the current app-specific database networks but overlay them with zone-based access control. Traefik connects to Zone 1 (application) only. Application containers connect to their database network AND Zone 1. This gives the security clarity of zones while preserving database isolation. However, this increases the total number of networks.

**Recommendation:** The current architecture is well-suited to the homelab's scale and operational model. The zone model is presented here as a conceptual framework for evaluating future changes, not as a replacement recommendation. If the homelab grows significantly (40+ containers, multiple operators), the zone model's clearer security semantics may become more valuable than the current model's operational clarity.

### 4.5 Stretch Goals (Best-in-Class Aspirations)

**4.5.1 DNSSEC validation**

Currently, container DNS queries go to Pi-hole, which queries upstream DNS. Adding DNSSEC validation (either at Pi-hole or via a local Unbound resolver) would protect against DNS spoofing attacks. This is mostly relevant for external DNS resolution (e.g., Traefik resolving backend URLs, containers fetching updates).

**4.5.2 Signed container images**

Podman supports `sigstore` and `cosign` for verifying container image signatures. Enabling signature verification would ensure that only images signed by trusted publishers (Docker Hub, GitHub Container Registry) are pulled, protecting against supply-chain attacks on container images.

**4.5.3 Runtime security monitoring (Falco/Tetragon)**

eBPF-based runtime security tools can detect anomalous container behavior (unexpected syscalls, file access, network connections) without modifying containers. This represents the cutting edge of container security observability but adds significant operational complexity.

**4.5.4 Immutable infrastructure pattern**

The current quadlet files are mutable -- changes are applied via `daemon-reload` and service restart. An immutable infrastructure approach would treat the entire container deployment as a versioned artifact: each change produces a new "release" that is deployed atomically and can be rolled back atomically. This aligns with the existing Git-based config-as-code approach but adds automated deployment verification.

---

## Appendix: Live System State Snapshot (2026-03-01)

**Container status:** 29 running, 27 with passing healthchecks, 2 without healthcheck status (UnPoller, Loki)

**Podman secrets:** 27 secrets via file driver

**CrowdSec status:** CAPI enrolled, 6 collections, 52 scenarios, 0 active bans, 0 dropped requests since 2026-02-22

**Firewall (firewalld):** FedoraWorkstation zone, services: SSH, DHCP, mDNS, homelab-containers; ports: 80, 443, 8096/tcp, 7359/udp

**Host listening ports:** 22, 80, 443, 631 (localhost), 8080, 8096, 8123, 9093, 9096 (localhost), 27500, 30069

**Network state:** 8 custom networks + 1 default podman bridge, all operational, IPAM ranges enforced

---

*Journal entry by Claude Code (Opus 4.6). All findings based on live system inspection and configuration analysis.*

