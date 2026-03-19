# Traefik Network Attack Surface Reduction

**Date:** 2026-03-17
**Status:** IMPLEMENTED — PR #124
**Related:** [2026-03-17-pasta-source-nat-investigation.md](2026-03-17-pasta-source-nat-investigation.md), [ADR-018](../00-foundation/decisions/2026-02-04-ADR-018-static-ip-multi-network-services.md)

---

## The Problem

The rootlessport investigation revealed that external traffic enters Traefik's network namespace via a non-deterministic IP selected by `rootlessport` from whichever Podman network happens to iterate first in a Go map. Under Podman 5.7.1, this was the monitoring network. Under 5.8.0, it is auth_services. The next Podman upgrade could shift it again.

This is not merely a logging cosmetic issue. The deeper concern:

**Traefik is currently on three networks (reverse_proxy, auth_services, monitoring), but only needs one.** Its membership on auth_services and monitoring grants a compromised Traefik container direct network access to backend services that are supposed to be shielded from the internet-facing tier. The network segmentation model is based on the principle that services exist in trust zones, with reverse_proxy as the single internet-facing boundary. Traefik's unnecessary multi-network membership punctures that boundary.

---

## Attack Surface Analysis

A compromised Traefik container currently has direct L3 access to every service on all three networks. Here is the additional attack surface beyond what reverse_proxy alone provides:

### Via auth_services (10.89.3.0/24)

| Service | Port | Risk if Directly Accessible |
|---------|------|----------------------------|
| redis-authelia | 6379/tcp | Session store. An attacker with access could dump or forge Authelia session tokens, bypassing all SSO authentication. Redis has no native authentication in this deployment. |

### Via monitoring (10.89.4.0/24)

| Service | Port | Risk if Directly Accessible |
|---------|------|----------------------------|
| nextcloud-db (MariaDB) | 3306/tcp | Full Nextcloud database — files metadata, user accounts, shares. |
| nextcloud-redis | 6379/tcp | Nextcloud session/cache store. |
| node_exporter | 9100/tcp | Host system metrics — filesystem paths, kernel version, network interfaces, mount points. Reconnaissance value. |
| cadvisor | 8080/tcp | Container metrics — resource usage, environment details, all container names. |
| promtail | — | Log aggregator — reads all container logs via journal. |

These services are not designed as front-end services. They have no authentication layer, no rate limiting, and no hardening against direct access. Their security model relies entirely on network isolation. Traefik's presence on the monitoring network breaks that isolation.

### Quantified blast radius

| Scenario | Services directly reachable |
|----------|---------------------------|
| Traefik on reverse_proxy only | 19 (all designed for external access, all behind auth/rate limits) |
| Traefik on reverse_proxy + auth_services | 19 + 1 (redis-authelia — unauthenticated session store) |
| Traefik on all three (current) | 19 + 1 + 5 (databases, exporters, log aggregator) |

Removing Traefik from auth_services and monitoring eliminates access to **6 backend services** that have no business being reachable from the internet-facing reverse proxy.

---

## Why Traefik Was on Three Networks

Historically, Traefik was placed on auth_services and monitoring for two reasons:

1. **auth_services:** So Traefik could reach Authelia for ForwardAuth middleware verification.
2. **monitoring:** So Prometheus could scrape Traefik's metrics endpoint (`:8080`).

Both reasons are now obsolete thanks to ADR-018 (static IP multi-network services):

**Authelia:** Traefik's `/etc/hosts` override pins `authelia` to `10.89.2.78` (its reverse_proxy IP). ForwardAuth requests already route via reverse_proxy. Verified: Traefik never initiates connections to auth_services IPs.

**Prometheus scraping:** Traefik listens on `[::]:8080` — all interfaces. Prometheus is on both monitoring and reverse_proxy. Verified: `wget http://10.89.2.69:8080/metrics` from Prometheus succeeds. DNS resolution from Prometheus already returns the reverse_proxy IP first.

Connection analysis of Traefik's active TCP connections confirms zero established connections using the monitoring interface. The only auth_services connections are rootlessport-to-self NAT artifacts (loopback-routed, never touching the bridge).

### Per-interface traffic counters (since last boot)

```
Interface               RX bytes    TX bytes    Packets (RX+TX)
lo (loopback)           3,814 MB    3,814 MB    4,566,512
eth0 (reverse_proxy)    229 MB      3,561 MB    986,099
eth1 (auth_services)    1.8 MB      2.5 MB      48,228
eth2 (monitoring)       1.9 MB      2.2 MB      46,646
```

eth0 carries all real traffic. eth1 and eth2 carry only bridge control plane (ARP, DNS). The rootlessport connections that use auth_services IPs are routed through loopback (src=dst=10.89.3.69), not through eth1.

---

## Does rootlessport Traffic Cross the Bridge?

No. When rootlessport-child connects from 10.89.3.69 to 10.89.3.69:443, the kernel recognizes both source and destination as local addresses and routes the packet through the loopback interface. The auth_services bridge network never carries this traffic. This is visible in the traffic counters: loopback handles 3.8 GB while eth1 handles only 1.8 MB.

However, this does not diminish the attack surface concern. The interfaces exist. A compromised process inside Traefik's network namespace can open new connections to any IP on any of the three networks. The rootlessport loopback routing is irrelevant to a post-exploitation scenario — what matters is that eth1 and eth2 exist and have routes to 21 additional services.

---

## Proposed Change: Single-Network Traefik

Remove Traefik from auth_services and monitoring. Traefik should be on reverse_proxy only.

### What changes

**Traefik quadlet (`quadlets/traefik.container`):**

```diff
-Network=systemd-reverse_proxy:ip=10.89.2.69
-Network=systemd-auth_services:ip=10.89.3.69
-Network=systemd-monitoring:ip=10.89.4.69
+Network=systemd-reverse_proxy:ip=10.89.2.69
```

**Prometheus config** — update target to use explicit IP or rely on DNS (which would only return the reverse_proxy IP):

```yaml
# No change needed if using DNS name 'traefik' — aardvark-dns will
# return only the reverse_proxy IP when that's Traefik's only network.
# Optionally pin to IP for resilience:
- job_name: 'traefik'
  static_configs:
    - targets: ['10.89.2.69:8080']
```

### What this fixes

1. **rootlessport IP selection becomes deterministic.** With only one network, `GetRootlessPortChildIP` can only return 10.89.2.69 (reverse_proxy). No more Go map randomization. Podman upgrades cannot change this.

2. **Attack surface reduced by 6 services.** A compromised Traefik loses direct access to nextcloud-db, nextcloud-redis, node_exporter, cadvisor, promtail, and redis-authelia.

3. **Traffic logging becomes meaningful.** External traffic will show `ClientHost=10.89.2.69` (reverse_proxy), while container-to-container traffic shows `10.89.2.1` (gateway) or actual container IPs. Still can't distinguish external clients from each other, but at least the network attribution will be correct.

4. **Network model restored.** reverse_proxy is the sole internet-facing boundary. auth_services is a private backend for Authelia ↔ Redis. monitoring is a private backend for the observability stack. No cross-tier leakage from the ingress point.

### What could break

**Nothing that we've been able to identify.** Traefik's current active connections use only reverse_proxy for backend routing. The `/etc/hosts` override ensures all service names resolve to reverse_proxy IPs. CrowdSec and Authelia are both reachable via reverse_proxy.

However, there is a subtlety worth verifying: **Traefik's Docker provider uses the Podman socket to discover containers.** If Traefik's Docker provider needs to resolve container names, it uses the Podman socket (not DNS), so network membership is irrelevant for service discovery.

### Risk: Prometheus scraping

The only operational dependency is Prometheus scraping Traefik metrics. Currently Prometheus resolves `traefik` via DNS and gets both IPs. After the change, DNS returns only the reverse_proxy IP. Tested: Prometheus successfully scrapes `http://10.89.2.69:8080/metrics`. Low risk, but monitor Prometheus targets after the change to confirm.

---

## Broader Audit: Other Multi-Network Services

Traefik is the most critical case because it's the ingress point. But the same principle applies to other multi-network services — each network membership should be justified.

| Service | Networks | Justified? |
|---------|----------|-----------|
| **traefik** | reverse_proxy, ~~auth_services~~, ~~monitoring~~ | **No** — remove auth_services and monitoring |
| authelia | reverse_proxy, auth_services | **Yes** — needs reverse_proxy for external access, auth_services for redis-authelia |
| grafana | reverse_proxy, monitoring | **Yes** — needs reverse_proxy for external access, monitoring for Prometheus/Loki data sources |
| prometheus | reverse_proxy, monitoring | **Yes** — needs reverse_proxy for Traefik routing, monitoring for scraping all exporters |
| loki | reverse_proxy, monitoring | **Yes** — needs reverse_proxy for Traefik routing, monitoring for receiving logs from promtail |
| alertmanager | reverse_proxy, monitoring | **Yes** — needs reverse_proxy for Traefik routing, monitoring for receiving alerts from Prometheus |
| alert-discord-relay | reverse_proxy, monitoring | **Yes** — needs reverse_proxy for internet (Discord webhook), monitoring for receiving from alertmanager |
| nextcloud | reverse_proxy, nextcloud, monitoring | Review — does nextcloud need monitoring? Only if Prometheus scrapes nextcloud directly. |
| home-assistant | reverse_proxy, home_automation, monitoring | Review — same question. |
| jellyfin | reverse_proxy, media_services, monitoring | Review — same question. |
| immich-server | reverse_proxy, photos, monitoring | Review — same question. |
| gathio | reverse_proxy, gathio, monitoring | Review — same question. |
| navidrome | reverse_proxy, monitoring | Review — does navidrome need monitoring? |
| unpoller | reverse_proxy, monitoring | **Yes** — needs reverse_proxy for UDM Pro access, monitoring for Prometheus scraping |
| nextcloud-db | nextcloud, monitoring | Review — only needs monitoring if Prometheus scrapes MariaDB directly. |
| nextcloud-redis | nextcloud, monitoring | Review — same question. |

Several application services (nextcloud, home-assistant, jellyfin, immich, gathio, navidrome) are on the monitoring network. If Prometheus doesn't scrape them directly (instead relying on their Traefik-exposed metrics or cAdvisor for container-level metrics), they could be removed from monitoring. This is a larger audit that should be done separately, but the pattern is the same: **every network membership is an extension of the attack surface and should earn its place.**

---

## Implementation Priority

1. **Immediate: Remove Traefik from auth_services and monitoring.** This is the highest-impact, lowest-risk change. One quadlet edit, one daemon-reload, one restart. Eliminates 6 backend services from the blast radius of the most exposed container.

2. **Follow-up: Audit all application services on monitoring.** Determine whether each application's monitoring network membership serves a real purpose or is historical artifact. Remove where unnecessary.

3. **Longer-term: Evaluate per-service scraping architecture.** If Prometheus needs metrics from application services, consider whether cAdvisor + Traefik metrics provide sufficient observability without requiring direct network access to every application.

---

## Follow-up: Application Services Removed from Monitoring (2026-03-19)

Completed the follow-up audit. Home Assistant and Navidrome were the last two application services on the monitoring network without justification. Prometheus (which is on both reverse_proxy and monitoring) can scrape them via their reverse_proxy IPs — no monitoring membership needed.

**Changes:**
- Removed `Network=systemd-monitoring` from `home-assistant.container` and `navidrome.container`
- Updated Prometheus target for Navidrome from `10.89.4.75:4533` → `10.89.2.75:4533`
- Updated Prometheus target for Home Assistant from `home-assistant:8123` → `10.89.2.76:8123` (ADR-018 static IP pattern — HA remains multi-network, so hostname resolution is non-deterministic)

**Verified:** Both Prometheus targets report `health=up`. Traefik backend routing unaffected.

The other services listed in the broader audit (nextcloud, immich, jellyfin, gathio) had already been removed from monitoring prior to this entry. All application service monitoring network memberships are now resolved.
