# Egress Observatory — Baseline Index (Auto-Generated)

**Generated:** 2026-05-25 05:01:01 UTC
**Implements:** ADR-030 P7 (Tier 4) — egress detection. **Mode:** shadow (observe-only)

Host-side `/proc/<pid>/net/{tcp,tcp6}` sampling of reverse_proxy-tier containers (attributable, rootless, scratch-safe, DNS-method-agnostic). Detection, not prevention. See `config/supply-chain/known-egress.md` for method and residual/evasion scope.

## Pipeline health

| Component | Last run | Detail |
|---|---|---|
| Collector (`egress-collector.service`) | 28s ago | 21 services sampled |
| Classifier (`egress-detect.timer`) | 8m ago | mode=shadow (observe-only); last window 9 dest(s) |

## Per-service egress

| Service | Mode | Public dests | Unexpected | Peers (swarm) |
|---|---|---|---|---|
| alert-discord-relay | classify | 1 | 1 (unarmed) | — |
| alertmanager | classify | — | — | — |
| audiobookshelf | classify | — | — | — |
| authelia | classify | — | — | — |
| crowdsec | classify | 10 | 10 (unarmed) | — |
| forgejo | classify | — | — | — |
| gathio | classify | — | — | — |
| grafana | classify | 1 | 1 (unarmed) | — |
| home-assistant | classify | 12 | 12 (unarmed) | — |
| homepage | classify | — | — | — |
| immich-server | classify | 2 | 2 (unarmed) | — |
| jellyfin | classify | 4 | 4 (unarmed) | — |
| loki | classify | 1 | 1 (unarmed) | — |
| navidrome | classify | 1 | 1 (unarmed) | — |
| nextcloud | classify | — | — | — |
| prometheus | classify | — | — | — |
| proton-bridge | classify | 2 | 2 (unarmed) | — |
| qbittorrent | peer-swarm (count-only) | — | — | 137 |
| traefik | classify | 2 | 2 (unarmed) | — |
| unpoller | classify | — | — | — |
| vaultwarden | classify | — | — | — |

## Zero-egress candidates — blast-radius reduction (REPORT ONLY)

Egress-tier services with **no observed public destination** over the window. Each is a candidate to move to an `Internal=true` network (shrinking the surface Tier 4 watches). **Not an automated change** — manual, per-service review (Feb-2026 21-container outage precedent). A short window will list services that simply hadn't egressed yet (e.g. proton-bridge in `TIME_WAIT`); confirm against a full ≥7-day baseline before acting.

> alertmanager, audiobookshelf, authelia, forgejo, gathio, homepage, nextcloud, prometheus, unpoller, vaultwarden

## Observed destinations (durable state)

### alert-discord-relay

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `162.159.135.232` | 443 | ⚠️ unexpected | 13h ago | 9h ago | 4 |

### crowdsec

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `108.128.222.234` | 443 | ⚠️ unexpected | 12h ago | 8m ago | 48 |
| `18.200.183.204` | 443 | ⚠️ unexpected | 14h ago | 92m ago | 56 |
| `34.250.77.39` | 443 | ⚠️ unexpected | 13h ago | 3h ago | 47 |
| `34.255.59.56` | 443 | ⚠️ unexpected | 9h ago | 2h ago | 20 |
| `52.17.58.50` | 443 | ⚠️ unexpected | 71m ago | 71m ago | 5 |
| `52.30.5.78` | 443 | ⚠️ unexpected | 8h ago | 2h ago | 27 |
| `54.77.8.107` | 443 | ⚠️ unexpected | 10h ago | 29m ago | 44 |
| `63.34.141.128` | 443 | ⚠️ unexpected | 10h ago | 2h ago | 12 |
| `63.35.22.155` | 443 | ⚠️ unexpected | 14h ago | 8h ago | 15 |
| `79.125.15.38` | 443 | ⚠️ unexpected | 13h ago | 2h ago | 30 |

### grafana

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `34.120.177.193` | 443 | ⚠️ unexpected | 14h ago | 8m ago | 439 |

### home-assistant

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.26.4.238` | 443 | ⚠️ unexpected | 11h ago | 5h ago | 2 |
| `104.26.5.238` | 443 | ⚠️ unexpected | 14h ago | 2h ago | 3 |
| `151.101.1.195` | 443 | ⚠️ unexpected | 8h ago | 8h ago | 3 |
| `157.249.81.141` | 443 | ⚠️ unexpected | 10h ago | 29m ago | 5 |
| `18.184.210.208` | 8883 | ⚠️ unexpected | 14h ago | 3h ago | 1297 |
| `18.198.195.194` | 8883 | ⚠️ unexpected | 3h ago | 8m ago | 419 |
| `3.124.29.182` | 443 | ⚠️ unexpected | 14h ago | 8m ago | 61 |
| `3.125.66.145` | 443 | ⚠️ unexpected | 14h ago | 8m ago | 70 |
| `3.67.142.130` | 443 | ⚠️ unexpected | 14h ago | 8m ago | 56 |
| `52.29.210.73` | 443 | ⚠️ unexpected | 14h ago | 8m ago | 68 |
| `52.57.174.242` | 443 | ⚠️ unexpected | 14h ago | 19m ago | 70 |
| `63.181.74.73` | 443 | ⚠️ unexpected | 14h ago | 19m ago | 65 |

### immich-server

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.21.71.92` | 443 | ⚠️ unexpected | 12h ago | 8m ago | 14 |
| `172.67.170.79` | 443 | ⚠️ unexpected | 14h ago | 71m ago | 19 |

### jellyfin

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.17.207.5` | 443 | ⚠️ unexpected | 13h ago | 13h ago | 5 |
| `165.227.169.147` | 443 | ⚠️ unexpected | 13h ago | 13h ago | 5 |
| `178.105.98.131` | 443 | ⚠️ unexpected | 13h ago | 13h ago | 3 |
| `68.183.204.194` | 443 | ⚠️ unexpected | 13h ago | 13h ago | 1 |

### loki

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `34.96.126.106` | 443 | ⚠️ unexpected | 14h ago | 2h ago | 19 |

### navidrome

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `209.141.42.198` | 443 | ⚠️ unexpected | 13h ago | 13h ago | 3 |

### proton-bridge

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `185.70.42.41` | 443 | ⚠️ unexpected | 14h ago | 8m ago | 468 |
| `185.70.42.45` | 443 | ⚠️ unexpected | 13h ago | 5h ago | 13 |

### traefik

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `13.39.208.199` | 443 | ⚠️ unexpected | 14h ago | 14h ago | 3 |
| `140.82.121.6` | 443 | ⚠️ unexpected | 14h ago | 14h ago | 1 |

---

*Auto-generated by `scripts/generate-egress-index.sh`. Allow-list: `config/supply-chain/egress-baseline.yaml` (frozen prefixes; re-seed with `scripts/egress-baseline.sh`). Anomaly trail: `data/egress/anomalies.jsonl`. Alerts armed by renaming `config/prometheus/alerts/egress-alerts.yml.disabled` → `.yml` after the baseline window (shadow-first).*
