# Egress Observatory — Baseline Index (Auto-Generated)

**Generated:** 2026-05-27 18:52:39 UTC
**Implements:** ADR-030 P7 (Tier 4) — egress detection. **Mode:** shadow (observe-only)

Host-side `/proc/<pid>/net/{tcp,tcp6}` sampling of reverse_proxy-tier containers (attributable, rootless, scratch-safe, DNS-method-agnostic). Detection, not prevention. See `config/supply-chain/known-egress.md` for method and residual/evasion scope.

## Pipeline health

| Component | Last run | Detail |
|---|---|---|
| Collector (`egress-collector.service`) | 11s ago | 22 services sampled |
| Classifier (`egress-detect.timer`) | 7m ago | mode=shadow (observe-only); last window 5 dest(s) |

## Per-service egress

| Service | Mode | Public dests | Unexpected | Peers (swarm) |
|---|---|---|---|---|
| alert-discord-relay | classify | 3 | 3 (unarmed) | — |
| alertmanager | classify | 2 | 2 (unarmed) | — |
| audiobookshelf | classify | — | — | — |
| authelia | classify | — | — | — |
| blackbox-exporter | classify | — | — | — |
| crowdsec | classify | 11 | 11 (unarmed) | — |
| forgejo | classify | — | — | — |
| gathio | classify | 1 | 1 (unarmed) | — |
| grafana | classify | 3 | 3 (unarmed) | — |
| home-assistant | classify | 16 | 16 (unarmed) | — |
| immich-server | classify | 2 | 2 (unarmed) | — |
| jellyfin | classify | 8 | 8 (unarmed) | — |
| loki | classify | 1 | 1 (unarmed) | — |
| navidrome | classify | 6 | 6 (unarmed) | — |
| nextcloud | classify | 3 | 3 (unarmed) | — |
| pihole-exporter | classify | — | — | — |
| prometheus | classify | — | — | — |
| proton-bridge | classify | 2 | 2 (unarmed) | — |
| qbittorrent | peer-swarm (count-only) | — | — | 138 |
| traefik | classify | 6 | 6 (unarmed) | — |
| unpoller | classify | — | — | — |
| vaultwarden | classify | 17 | 17 (unarmed) | — |

## Zero-egress candidates — blast-radius reduction (REPORT ONLY)

Egress-tier services with **no observed public destination** over the window. Each is a candidate to move to an `Internal=true` network (shrinking the surface Tier 4 watches). **Not an automated change** — manual, per-service review (Feb-2026 21-container outage precedent). A short window will list services that simply hadn't egressed yet (e.g. proton-bridge in `TIME_WAIT`); confirm against a full ≥7-day baseline before acting.

> audiobookshelf, authelia, blackbox-exporter, forgejo, pihole-exporter, prometheus, unpoller

## Observed destinations (durable state)

### alert-discord-relay

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `162.159.128.233` | 443 | ⚠️ unexpected | 4h ago | 49m ago | 6 |
| `162.159.135.232` | 443 | ⚠️ unexpected | 3d ago | 2d ago | 6 |
| `162.159.138.232` | 443 | ⚠️ unexpected | 2d ago | 44h ago | 4 |

### alertmanager

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `162.159.135.232` | 443 | ⚠️ unexpected | 2d ago | 2d ago | 2 |
| `162.159.138.232` | 80 | ⚠️ unexpected | 2d ago | 2d ago | 2 |

### crowdsec

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `108.128.222.234` | 443 | ⚠️ unexpected | 3d ago | 5h ago | 180 |
| `18.200.183.204` | 443 | ⚠️ unexpected | 3d ago | 49m ago | 190 |
| `34.250.77.39` | 443 | ⚠️ unexpected | 3d ago | 4h ago | 172 |
| `34.255.59.56` | 443 | ⚠️ unexpected | 2d ago | 39m ago | 168 |
| `52.17.58.50` | 443 | ⚠️ unexpected | 2d ago | 8h ago | 181 |
| `52.18.68.74` | 443 | ⚠️ unexpected | 4h ago | 18m ago | 11 |
| `52.30.5.78` | 443 | ⚠️ unexpected | 2d ago | 82m ago | 157 |
| `54.77.8.107` | 443 | ⚠️ unexpected | 3d ago | 7m ago | 179 |
| `63.34.141.128` | 443 | ⚠️ unexpected | 3d ago | 113m ago | 137 |
| `63.35.22.155` | 443 | ⚠️ unexpected | 3d ago | 2d ago | 15 |
| `79.125.15.38` | 443 | ⚠️ unexpected | 3d ago | 71m ago | 173 |

### gathio

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.16.4.34` | 443 | ⚠️ unexpected | 2h ago | 2h ago | 9 |

### grafana

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `192.0.73.2` | 443 | ⚠️ unexpected | 46h ago | 20h ago | 3 |
| `34.120.177.193` | 443 | ⚠️ unexpected | 3d ago | 7m ago | 2262 |
| `34.96.126.106` | 443 | ⚠️ unexpected | 2d ago | 8h ago | 15 |

### home-assistant

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.26.4.238` | 443 | ⚠️ unexpected | 3d ago | 28h ago | 8 |
| `104.26.5.238` | 443 | ⚠️ unexpected | 3d ago | 4h ago | 9 |
| `151.101.1.195` | 443 | ⚠️ unexpected | 2d ago | 45h ago | 6 |
| `151.101.65.195` | 443 | ⚠️ unexpected | 21h ago | 21h ago | 2 |
| `157.249.81.141` | 443 | ⚠️ unexpected | 3d ago | 5h ago | 48 |
| `172.67.68.90` | 443 | ⚠️ unexpected | 2d ago | 7h ago | 3 |
| `18.158.22.138` | 8883 | ⚠️ unexpected | 17h ago | 2h ago | 1702 |
| `18.184.210.208` | 8883 | ⚠️ unexpected | 3d ago | 2d ago | 1297 |
| `18.198.195.194` | 8883 | ⚠️ unexpected | 2d ago | 17h ago | 5585 |
| `3.120.53.2` | 8883 | ⚠️ unexpected | 2h ago | 7m ago | 298 |
| `3.124.29.182` | 443 | ⚠️ unexpected | 3d ago | 18m ago | 391 |
| `3.125.66.145` | 443 | ⚠️ unexpected | 3d ago | 7m ago | 367 |
| `3.67.142.130` | 443 | ⚠️ unexpected | 3d ago | 49m ago | 330 |
| `52.29.210.73` | 443 | ⚠️ unexpected | 3d ago | 18m ago | 342 |
| `52.57.174.242` | 443 | ⚠️ unexpected | 3d ago | 18m ago | 413 |
| `63.181.74.73` | 443 | ⚠️ unexpected | 3d ago | 28m ago | 350 |

### immich-server

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.21.71.92` | 443 | ⚠️ unexpected | 3d ago | 2h ago | 68 |
| `172.67.170.79` | 443 | ⚠️ unexpected | 3d ago | 28m ago | 94 |

### jellyfin

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.17.207.5` | 443 | ⚠️ unexpected | 3d ago | 3d ago | 5 |
| `104.17.208.5` | 443 | ⚠️ unexpected | 2d ago | 2d ago | 5 |
| `139.59.139.28` | 443 | ⚠️ unexpected | 3h ago | 3h ago | 5 |
| `151.101.193.229` | 443 | ⚠️ unexpected | 27h ago | 3h ago | 4 |
| `165.227.169.147` | 443 | ⚠️ unexpected | 3d ago | 27h ago | 14 |
| `165.227.244.161` | 443 | ⚠️ unexpected | 2d ago | 3h ago | 6 |
| `178.105.98.131` | 443 | ⚠️ unexpected | 3d ago | 27h ago | 5 |
| `68.183.204.194` | 443 | ⚠️ unexpected | 3d ago | 3h ago | 3 |

### loki

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `34.96.126.106` | 443 | ⚠️ unexpected | 3d ago | 28m ago | 98 |

### navidrome

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `130.211.19.189` | 443 | ⚠️ unexpected | 2d ago | 2d ago | 6 |
| `151.101.237.188` | 443 | ⚠️ unexpected | 2d ago | 2d ago | 4 |
| `151.101.238.53` | 443 | ⚠️ unexpected | 2d ago | 2d ago | 3 |
| `151.101.238.79` | 443 | ⚠️ unexpected | 2d ago | 2d ago | 3 |
| `2.22.225.83` | 443 | ⚠️ unexpected | 2d ago | 2d ago | 4 |
| `209.141.42.198` | 443 | ⚠️ unexpected | 3d ago | 2h ago | 15 |

### nextcloud

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `65.108.197.113` | 443 | ⚠️ unexpected | 11h ago | 11h ago | 2 |
| `65.109.114.179` | 443 | ⚠️ unexpected | 2d ago | 2d ago | 2 |
| `95.217.53.153` | 443 | ⚠️ unexpected | 35h ago | 4h ago | 8 |

### proton-bridge

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `185.70.42.41` | 443 | ⚠️ unexpected | 3d ago | 7m ago | 2588 |
| `185.70.42.45` | 443 | ⚠️ unexpected | 3d ago | 103m ago | 82 |

### traefik

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.19.193.29` | 443 | ⚠️ unexpected | 45h ago | 45h ago | 6 |
| `104.26.3.101` | 443 | ⚠️ unexpected | 44h ago | 2h ago | 15 |
| `13.39.208.199` | 443 | ⚠️ unexpected | 3d ago | 2h ago | 14 |
| `140.82.121.5` | 443 | ⚠️ unexpected | 44h ago | 20h ago | 2 |
| `140.82.121.6` | 443 | ⚠️ unexpected | 3d ago | 2h ago | 3 |
| `172.65.32.248` | 443 | ⚠️ unexpected | 45h ago | 45h ago | 13 |

### vaultwarden

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.18.179.120` | 443 | ⚠️ unexpected | 2d ago | 2d ago | 3 |
| `104.20.7.63` | 443 | ⚠️ unexpected | 2d ago | 2d ago | 3 |
| `151.101.129.91` | 443 | ⚠️ unexpected | 2d ago | 2d ago | 1 |
| `151.101.237.91` | 443 | ⚠️ unexpected | 2d ago | 2d ago | 1 |
| `18.195.2.2` | 443 | ⚠️ unexpected | 2d ago | 2d ago | 3 |
| `185.31.213.113` | 443 | ⚠️ unexpected | 2d ago | 2d ago | 3 |
| `193.212.190.216` | 443 | ⚠️ unexpected | 2d ago | 2d ago | 1 |
| `3.167.1.165` | 443 | ⚠️ unexpected | 2d ago | 2d ago | 3 |
| `3.167.2.39` | 443 | ⚠️ unexpected | 2d ago | 2d ago | 2 |
| `3.167.2.93` | 443 | ⚠️ unexpected | 2d ago | 2d ago | 2 |
| `52.198.57.38` | 443 | ⚠️ unexpected | 2d ago | 2d ago | 1 |
| `52.222.187.52` | 443 | ⚠️ unexpected | 2d ago | 2d ago | 3 |
| `52.84.50.103` | 443 | ⚠️ unexpected | 2d ago | 2d ago | 2 |
| `52.84.50.4` | 443 | ⚠️ unexpected | 2d ago | 2d ago | 2 |
| `66.33.60.34` | 443 | ⚠️ unexpected | 2d ago | 2d ago | 3 |
| `76.76.21.21` | 443 | ⚠️ unexpected | 2d ago | 2d ago | 3 |
| `98.82.155.134` | 443 | ⚠️ unexpected | 2d ago | 2d ago | 3 |

---

*Auto-generated by `scripts/generate-egress-index.sh`. Allow-list: `config/supply-chain/egress-baseline.yaml` (frozen prefixes; re-seed with `scripts/egress-baseline.sh`). Anomaly trail: `data/egress/anomalies.jsonl`. Alerts armed by renaming `config/prometheus/alerts/egress-alerts.yml.disabled` → `.yml` after the baseline window (shadow-first).*
