# Homelab Threat Model

Security posture from an adversary's perspective. Referenced by SKILL.md Phase 2 (correlation) and Phase 4 (risk assessment).

---

## Table of Contents

- [Attack Surface Map](#attack-surface-map)
- [Adversary Profiles](#adversary-profiles)
- [Attack Chains](#attack-chains)
- [Defense-in-Depth Map](#defense-in-depth-map)

---

## Attack Surface Map

### Internet-Facing Entry Points

**Ports:** 80 (HTTP redirect), 443 (HTTPS), 22 (SSH)

### Public Routers (16 routers via Traefik)

**Authelia-protected (8 routers)** — require YubiKey/WebAuthn or TOTP:
| Router | Domain | Service | High-Value Target? |
|--------|--------|---------|-------------------|
| root-redirect | patriark.org | Homepage | Low — dashboard only |
| homepage-dashboard | home.patriark.org | Homepage | Low |
| traefik-dashboard | traefik.patriark.org | Traefik API | **HIGH** — exposes routing config, middleware chains, backend addresses |
| grafana-secure | grafana.patriark.org | Grafana | **HIGH** — exposes infrastructure metrics, service topology, log queries |
| prometheus-secure | prometheus.patriark.org | Prometheus | **HIGH** — exposes all metrics, scrape targets, alert rules |
| loki-secure | loki.patriark.org | Loki | **HIGH** — exposes all logs including auth attempts, access patterns |
| gathio-secure | events.patriark.org | Gathio | Low — event management |
| qbittorrent-secure | torrent.patriark.org | qBittorrent | Medium — download management |

**Native auth (8 routers)** — services handle their own authentication:
| Router | Domain | Service | Auth Type | High-Value? |
|--------|--------|---------|-----------|-------------|
| authelia-portal | sso.patriark.org | Authelia | Self (login portal) | **CRITICAL** — SSO gateway |
| vaultwarden-secure | vault.patriark.org | Vaultwarden | Built-in | **CRITICAL** — all passwords |
| jellyfin-secure | jellyfin.patriark.org | Jellyfin | Built-in | Low — media |
| immich-secure | photos.patriark.org | Immich | Built-in | Medium — personal photos |
| nextcloud-secure | nextcloud.patriark.org | Nextcloud | Built-in | **HIGH** — documents, calendar, contacts |
| home-assistant-secure | ha.patriark.org | Home Assistant | Built-in | Medium — smart home control |
| audiobookshelf-secure | audiobookshelf.patriark.org | Audiobookshelf | Built-in | Low — media |
| navidrome-secure | musikk.patriark.org | Navidrome | Built-in | Low — music |

### Internal-Only Services (no public router)

These are only accessible via container networks — not reachable from the internet:
- **Databases:** nextcloud-db (MariaDB), postgresql-immich, gathio-db (MongoDB)
- **Caches:** redis-authelia, redis-nextcloud, redis-immich
- **ML:** immich-ml (CPU inference)
- **Monitoring:** Alertmanager (10.89.4.72 only), Prometheus (monitoring network), cAdvisor, Node Exporter, UnPoller
- **Infrastructure:** CrowdSec LAPI (8080 internal), Matter Server
- **Log pipeline:** Promtail, Loki (internal push endpoint)

---

## Adversary Profiles

### 1. Automated Scanners (Most Common)
- **Indicators:** Rapid port scanning, common CVE probes, random User-Agent strings, multiple source IPs
- **Mitigated by:** CrowdSec community blocklists (CAPI), rate limiting
- **Detection:** SA-NET-08 (decisions count), SA-NET-09 (alert volume), Traefik access logs showing 4xx spikes
- **Residual risk:** Low — CrowdSec blocks most before they reach services

### 2. Targeted Attacks
- **Indicators:** Consistent source IP across multiple subdomains, methodical probing of specific endpoints, reconnaissance of exposed services
- **Mitigated by:** CrowdSec local detection, Authelia MFA (YubiKey), rate limiting per-IP
- **Detection:** Loki query for single source IP hitting multiple subdomains: `{job="traefik-access"} | json | line_format "{{.ClientHost}} {{.RequestHost}}" | pattern "<ip> <host>" | count by (ip) > 5`
- **Residual risk:** Medium — native-auth services (Vaultwarden, Nextcloud) depend entirely on their own auth strength

### 3. Credential Stuffing
- **Indicators:** SA-AUTH-07 spike (auth failures > 50/24h), consistent failure patterns from few IPs, targeting specific services
- **Mitigated by:** CrowdSec brute-force scenarios, Authelia rate limiting (rate-limit-auth: 10/min), YubiKey MFA (phishing-resistant)
- **Detection:** SA-AUTH-07 correlation with SA-NET-09. Authelia journal: `journalctl --user -u authelia.service | grep "unsuccessful"`
- **Residual risk:** Low for Authelia (YubiKey), Medium for native-auth services without hardware MFA

### 4. Insider / Local Network
- **Indicators:** Traffic from 192.168.1.0/24 or 192.168.100.0/24 (WireGuard), unusual hours, targeting internal-only services
- **Mitigated by:** Individual service authentication, SELinux, container network isolation
- **Detection:** Limited — local traffic bypasses CrowdSec if not routed through Traefik
- **Residual risk:** Medium — local traffic is implicitly trusted for monitoring APIs
- **Note:** admin-whitelist middleware is ineffective in rootless Podman (NATs all client IPs to container network IPs)

---

## Attack Chains

Five attack chains with defense layers, blast radius, and detection points.

### Chain 1: Defense Layer Bypass (CrowdSec Down)

```
CrowdSec fails (SA-NET-01)
  → Rate limiting is only defense (SA-TRF-04)
  → Known malicious IPs reach services unchecked
  → Brute force becomes viable against native-auth services
  → Credential stuffing at scale
```

**Defense layers remaining:** Rate limiting, Authelia MFA, native service auth, SELinux
**Blast radius:** All 16 public routers lose IP reputation filtering
**Detection:** SA-NET-01 (CrowdSec down), SA-NET-03 (no bouncers), Prometheus alert `up{job="crowdsec"}==0`
**Compensating control:** Rate limiting still applies. Authelia services still require MFA.

### Chain 2: Auth Cascade Failure

```
Authelia fails (SA-AUTH-01) + Redis fails (SA-AUTH-03)
  → All Authelia-protected services return 401/502
  → 8 routers become inaccessible (denial of service)
  → If Authelia middleware is removed as "fix" → all protected services become unauthenticated
```

**Defense layers remaining:** CrowdSec, rate limiting, security headers
**Blast radius:** 8 Authelia-protected routers (including monitoring: Grafana, Prometheus, Loki)
**Detection:** SA-AUTH-01, SA-AUTH-02, SA-AUTH-03. Prometheus alert for Authelia health.
**Critical warning:** Never remove `authelia@file` middleware to "restore access" — this exposes monitoring stack (Grafana, Prometheus, Loki) to unauthenticated access.

### Chain 3: Container Escape Path

```
SELinux disabled (SA-CTR-01)
  → Missing SELinux labels on mounts (SA-CTR-04)
  → Container process gains host filesystem access
  → Lateral movement to host (UID 1000 = full user access)
  → Access to all container configs, secrets, data
```

**Defense layers remaining:** Rootless containers (limited capabilities), host firewall
**Blast radius:** Complete host compromise, all 30 containers, all data
**Detection:** SA-CTR-01 (SELinux not enforcing), `ausearch -m AVC` for SELinux denials
**Note:** Rootless containers provide some containment even without SELinux — no root on host, limited capabilities. But SELinux is the primary mandatory access control.

### Chain 4: Lateral Movement via Container Network

```
Service on reverse_proxy compromised (e.g., vulnerable app)
  → Attacker has network access to all services on reverse_proxy
  → Can probe Authelia (9091), Traefik API, other services
  → If monitoring network is not Internal (SA-NET-06) → monitoring also reachable
```

**Defense layers remaining:** Individual service auth, SELinux, network segmentation (8 networks)
**Blast radius:** All containers sharing the reverse_proxy network (most services)
**Detection:** Unusual container-to-container traffic patterns, unexpected connections in `podman exec <container> ss -tnp`
**Mitigation:** Network segmentation limits lateral movement. Databases are on separate networks (nextcloud, photos, gathio, auth_services). Monitoring is Internal=true.

### Chain 5: Monitoring Blindness

```
Prometheus fails (SA-MON-01) + Alertmanager fails (SA-MON-02)
  → No metrics collection, no alert routing
  → SLO monitoring blind, capacity planning impossible
  → Autonomous operations lose primary data source
  → Security events (disk full, OOM kills, service down) go undetected
  → If combined with CrowdSec down → attacks proceed completely unmonitored
```

**Defense layers remaining:** Manual observation, systemd journal (still logging), Loki (if Promtail running)
**Blast radius:** Total loss of observability — attacks and failures go unnoticed
**Detection:** Ironically hard to detect — the detection system itself is down. Manual `systemctl --user status` checks are the fallback.
**Compensating control:** Discord webhook from Alertmanager is the primary notification channel. Without it, schedule manual health checks.

---

## Defense-in-Depth Map

What compensates when each layer fails:

| Layer | If It Fails | Compensating Controls | Checks |
|-------|-------------|----------------------|--------|
| CrowdSec | Known-bad IPs reach services | Rate limiting, Authelia MFA, native auth | SA-NET-01..03 |
| Rate Limiting | Resource exhaustion, brute force viable | CrowdSec (blocks before rate limit), Authelia lockout | SA-TRF-04 |
| Authelia | Protected services return 401/502 | Native service auth (unaffected), CrowdSec still blocks | SA-AUTH-01..03 |
| Security Headers | XSS/clickjacking attacks possible | CSP from native apps (Nextcloud, Jellyfin), HTTPS still enforced | SA-TRF-07 |
| SELinux | Container escape possible | Rootless containers (no host root), user namespace isolation | SA-CTR-01 |
| TLS | Traffic interception possible | DNS-01 challenge (no HTTP validation needed), HSTS preload | SA-TRF-02, SA-TRF-09 |
| Prometheus | Metrics blind | Loki (logs), manual checks, systemd journal | SA-MON-01 |
| Alertmanager | Alerts not delivered | Manual health checks, Grafana dashboards (if accessible) | SA-MON-02 |
| Git (.gitignore) | Secrets committed | Pre-commit hooks, git history scanning (SA-SEC-02) | SA-SEC-01, SA-SEC-02 |
| Network segmentation | Lateral movement possible | SELinux, individual service auth, Internal=true on monitoring | SA-NET-06, SA-CTR-06 |

### Critical Combinations (Multiple Failures)

These combinations represent severe security degradation:

1. **SA-NET-01 + SA-AUTH-01** — No IP filtering AND no SSO → monitoring stack (Grafana, Prometheus, Loki) exposed to internet without authentication
2. **SA-CTR-01 + SA-CTR-04** — SELinux disabled AND missing labels → container escape path open
3. **SA-MON-01 + SA-MON-02 + SA-NET-01** — No monitoring AND no CrowdSec → attacks proceed undetected and unblocked
4. **SA-TRF-01 + SA-AUTH-01** — Traefik AND Authelia down → total service outage for all internet-facing services
5. **SA-SEC-01 + SA-CMP-01** — Gitignore gaps AND uncommitted changes → high risk of secret exposure in next commit
