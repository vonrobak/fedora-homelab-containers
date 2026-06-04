# Egress Observatory — Baseline Index (Auto-Generated)

**Generated:** 2026-06-04 15:10:35 UTC
**Implements:** ADR-030 P7 (Tier 4) — egress detection. **Mode:** shadow (observe-only)

Host-side `/proc/<pid>/net/{tcp,tcp6}` sampling of reverse_proxy-tier containers (attributable, rootless, scratch-safe, DNS-method-agnostic). Detection, not prevention. See `config/supply-chain/known-egress.md` for method and residual/evasion scope.

## Pipeline health

| Component | Last run | Detail |
|---|---|---|
| Collector (`egress-collector.service`) | 19s ago | 22 services sampled |
| Classifier (`egress-detect.timer`) | 10m ago | mode=shadow (observe-only); last window 7 dest(s) |

## Per-service egress

| Service | Mode | Public dests | Unexpected | Peers (swarm) |
|---|---|---|---|---|
| alert-discord-relay | classify | 4 | 4 (unarmed) | — |
| alertmanager | classify | 2 | 2 (unarmed) | — |
| audiobookshelf | classify | — | — | — |
| authelia | classify | — | — | — |
| blackbox-exporter | classify | — | — | — |
| crowdsec | classify | 21 | 21 (unarmed) | — |
| forgejo | classify | — | — | — |
| gathio | classify | 1 | 1 (unarmed) | — |
| grafana | classify | 3 | 3 (unarmed) | — |
| home-assistant | classify | 29 | 29 (unarmed) | — |
| immich-server | classify | 2 | 2 (unarmed) | — |
| jellyfin | classify | 14 | 14 (unarmed) | — |
| loki | classify | 1 | 1 (unarmed) | — |
| navidrome | classify | 7 | 7 (unarmed) | — |
| nextcloud | classify | 4 | 4 (unarmed) | — |
| pihole-exporter | classify | — | — | — |
| prometheus | classify | — | — | — |
| proton-bridge | classify | 2 | 2 (unarmed) | — |
| qbittorrent | peer-swarm (count-only) | — | — | 360 |
| traefik | classify | 7 | 7 (unarmed) | — |
| unpoller | classify | — | — | — |
| vaultwarden | classify | 55 | 55 (unarmed) | — |

## Zero-egress candidates — blast-radius reduction (REPORT ONLY)

Egress-tier services with **no observed public destination** over the window. Each is a candidate to move to an `Internal=true` network (shrinking the surface Tier 4 watches). **Not an automated change** — manual, per-service review (Feb-2026 21-container outage precedent). A short window will list services that simply hadn't egressed yet (e.g. proton-bridge in `TIME_WAIT`); confirm against a full ≥7-day baseline before acting.

> audiobookshelf, authelia, blackbox-exporter, forgejo, pihole-exporter, prometheus, unpoller

## Observed destinations (durable state)

### alert-discord-relay

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `162.159.128.233` | 443 | ⚠️ unexpected | 8d ago | 3d ago | 8 |
| `162.159.135.232` | 443 | ⚠️ unexpected | 10d ago | 10d ago | 6 |
| `162.159.136.232` | 443 | ⚠️ unexpected | 3d ago | 2d ago | 4 |
| `162.159.138.232` | 443 | ⚠️ unexpected | 10d ago | 2d ago | 8 |

### alertmanager

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `162.159.135.232` | 443 | ⚠️ unexpected | 9d ago | 9d ago | 2 |
| `162.159.138.232` | 80 | ⚠️ unexpected | 9d ago | 9d ago | 2 |

### crowdsec

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `108.128.137.208` | 443 | ⚠️ unexpected | 6d ago | 71m ago | 371 |
| `108.128.190.179` | 443 | ⚠️ unexpected | 7d ago | 40m ago | 416 |
| `108.128.222.234` | 443 | ⚠️ unexpected | 10d ago | 3d ago | 472 |
| `108.132.165.136` | 443 | ⚠️ unexpected | 2d ago | 2h ago | 108 |
| `18.200.183.204` | 443 | ⚠️ unexpected | 11d ago | 4d ago | 362 |
| `34.240.98.252` | 443 | ⚠️ unexpected | 8h ago | 50m ago | 24 |
| `34.242.194.148` | 443 | ⚠️ unexpected | 4d ago | 30m ago | 313 |
| `34.249.149.68` | 443 | ⚠️ unexpected | 31h ago | 12h ago | 55 |
| `34.250.77.39` | 443 | ⚠️ unexpected | 10d ago | 22h ago | 582 |
| `34.255.59.56` | 443 | ⚠️ unexpected | 10d ago | 34h ago | 512 |
| `52.17.58.50` | 443 | ⚠️ unexpected | 10d ago | 8d ago | 181 |
| `52.18.68.74` | 443 | ⚠️ unexpected | 8d ago | 27h ago | 458 |
| `52.210.229.63` | 443 | ⚠️ unexpected | 2d ago | 61m ago | 144 |
| `52.30.5.78` | 443 | ⚠️ unexpected | 10d ago | 7d ago | 157 |
| `54.246.207.199` | 443 | ⚠️ unexpected | 27h ago | 10m ago | 109 |
| `54.76.192.134` | 443 | ⚠️ unexpected | 3d ago | 3h ago | 239 |
| `54.77.8.107` | 443 | ⚠️ unexpected | 10d ago | 2d ago | 533 |
| `63.34.141.128` | 443 | ⚠️ unexpected | 10d ago | 6d ago | 196 |
| `63.35.22.155` | 443 | ⚠️ unexpected | 11d ago | 10d ago | 15 |
| `79.125.15.38` | 443 | ⚠️ unexpected | 10d ago | 6d ago | 232 |
| `99.80.129.27` | 443 | ⚠️ unexpected | 6d ago | 2d ago | 263 |

### gathio

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.16.4.34` | 443 | ⚠️ unexpected | 7d ago | 7d ago | 9 |

### grafana

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `192.0.73.2` | 443 | ⚠️ unexpected | 9d ago | 7d ago | 4 |
| `34.120.177.193` | 443 | ⚠️ unexpected | 11d ago | 10m ago | 7859 |
| `34.96.126.106` | 443 | ⚠️ unexpected | 10d ago | 5h ago | 53 |

### home-assistant

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.26.4.238` | 443 | ⚠️ unexpected | 10d ago | 16h ago | 14 |
| `104.26.5.238` | 443 | ⚠️ unexpected | 11d ago | 4h ago | 23 |
| `151.101.1.195` | 443 | ⚠️ unexpected | 10d ago | 18h ago | 15 |
| `151.101.65.195` | 443 | ⚠️ unexpected | 8d ago | 42h ago | 8 |
| `157.249.81.141` | 443 | ⚠️ unexpected | 10d ago | 82m ago | 136 |
| `172.67.68.90` | 443 | ⚠️ unexpected | 10d ago | 114m ago | 23 |
| `18.158.22.138` | 8883 | ⚠️ unexpected | 8d ago | 7d ago | 1702 |
| `18.158.224.141` | 8883 | ⚠️ unexpected | 37h ago | 10m ago | 4389 |
| `18.159.79.242` | 8883 | ⚠️ unexpected | 3d ago | 2d ago | 2777 |
| `18.184.210.208` | 8883 | ⚠️ unexpected | 11d ago | 10d ago | 1297 |
| `18.194.113.141` | 8883 | ⚠️ unexpected | 6d ago | 6d ago | 356 |
| `18.196.104.106` | 8883 | ⚠️ unexpected | 4d ago | 3d ago | 2729 |
| `18.198.195.194` | 8883 | ⚠️ unexpected | 10d ago | 8d ago | 5585 |
| `3.120.216.195` | 443 | ⚠️ unexpected | 7d ago | 10m ago | 677 |
| `3.120.53.2` | 8883 | ⚠️ unexpected | 7d ago | 6d ago | 3923 |
| `3.121.10.31` | 8883 | ⚠️ unexpected | 6d ago | 6d ago | 759 |
| `3.121.111.53` | 443 | ⚠️ unexpected | 2d ago | 20m ago | 249 |
| `3.121.169.115` | 8883 | ⚠️ unexpected | 6d ago | 4d ago | 4472 |
| `3.122.171.67` | 443 | ⚠️ unexpected | 6d ago | 10m ago | 586 |
| `3.122.70.209` | 8883 | ⚠️ unexpected | 2d ago | 37h ago | 2815 |
| `3.124.29.182` | 443 | ⚠️ unexpected | 11d ago | 2d ago | 810 |
| `3.125.66.145` | 443 | ⚠️ unexpected | 11d ago | 6d ago | 491 |
| `3.67.142.130` | 443 | ⚠️ unexpected | 11d ago | 28h ago | 907 |
| `35.156.5.143` | 443 | ⚠️ unexpected | 27h ago | 10m ago | 94 |
| `35.158.64.12` | 443 | ⚠️ unexpected | 25h ago | 20m ago | 79 |
| `52.29.210.73` | 443 | ⚠️ unexpected | 11d ago | 25h ago | 926 |
| `52.57.174.242` | 443 | ⚠️ unexpected | 11d ago | 7d ago | 429 |
| `52.58.153.107` | 443 | ⚠️ unexpected | 2d ago | 30m ago | 247 |
| `63.181.74.73` | 443 | ⚠️ unexpected | 11d ago | 2d ago | 789 |

### immich-server

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.21.71.92` | 443 | ⚠️ unexpected | 10d ago | 50m ago | 302 |
| `172.67.170.79` | 443 | ⚠️ unexpected | 11d ago | 4h ago | 259 |

### jellyfin

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.17.207.5` | 443 | ⚠️ unexpected | 11d ago | 11d ago | 5 |
| `104.17.208.5` | 443 | ⚠️ unexpected | 10d ago | 2d ago | 14 |
| `139.59.139.28` | 443 | ⚠️ unexpected | 8d ago | 2d ago | 9 |
| `146.190.237.6` | 443 | ⚠️ unexpected | 5d ago | 22h ago | 14 |
| `151.101.1.229` | 443 | ⚠️ unexpected | 5d ago | 3d ago | 6 |
| `151.101.129.229` | 443 | ⚠️ unexpected | 4d ago | 22h ago | 7 |
| `151.101.193.229` | 443 | ⚠️ unexpected | 9d ago | 8d ago | 4 |
| `157.245.38.19` | 443 | ⚠️ unexpected | 6d ago | 6d ago | 5 |
| `161.35.245.42` | 443 | ⚠️ unexpected | 4d ago | 2d ago | 5 |
| `165.227.169.147` | 443 | ⚠️ unexpected | 11d ago | 46h ago | 18 |
| `165.227.244.161` | 443 | ⚠️ unexpected | 10d ago | 46h ago | 14 |
| `178.105.98.131` | 443 | ⚠️ unexpected | 11d ago | 22h ago | 10 |
| `206.189.97.173` | 443 | ⚠️ unexpected | 3d ago | 3d ago | 5 |
| `68.183.204.194` | 443 | ⚠️ unexpected | 11d ago | 3d ago | 7 |

### loki

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `34.96.126.106` | 443 | ⚠️ unexpected | 11d ago | 40m ago | 330 |

### navidrome

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `130.211.19.189` | 443 | ⚠️ unexpected | 10d ago | 6d ago | 13 |
| `151.101.237.188` | 443 | ⚠️ unexpected | 10d ago | 6d ago | 7 |
| `151.101.238.53` | 443 | ⚠️ unexpected | 10d ago | 6d ago | 6 |
| `151.101.238.79` | 443 | ⚠️ unexpected | 10d ago | 6d ago | 6 |
| `2.22.225.107` | 443 | ⚠️ unexpected | 6d ago | 6d ago | 3 |
| `2.22.225.83` | 443 | ⚠️ unexpected | 10d ago | 10d ago | 4 |
| `209.141.42.198` | 443 | ⚠️ unexpected | 10d ago | 22h ago | 35 |

### nextcloud

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `65.108.197.113` | 443 | ⚠️ unexpected | 8d ago | 2d ago | 8 |
| `65.109.114.179` | 443 | ⚠️ unexpected | 10d ago | 7h ago | 8 |
| `65.21.231.50` | 443 | ⚠️ unexpected | 2d ago | 2d ago | 2 |
| `95.217.53.153` | 443 | ⚠️ unexpected | 9d ago | 31h ago | 12 |

### proton-bridge

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `185.70.42.41` | 443 | ⚠️ unexpected | 11d ago | 10m ago | 8875 |
| `185.70.42.45` | 443 | ⚠️ unexpected | 10d ago | 61m ago | 281 |

### traefik

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.19.192.29` | 443 | ⚠️ unexpected | 6d ago | 6d ago | 5 |
| `104.19.193.29` | 443 | ⚠️ unexpected | 9d ago | 9d ago | 6 |
| `104.26.3.101` | 443 | ⚠️ unexpected | 9d ago | 7d ago | 15 |
| `13.39.208.199` | 443 | ⚠️ unexpected | 11d ago | 23h ago | 35 |
| `140.82.121.5` | 443 | ⚠️ unexpected | 9d ago | 23h ago | 7 |
| `140.82.121.6` | 443 | ⚠️ unexpected | 11d ago | 46h ago | 6 |
| `172.65.32.248` | 443 | ⚠️ unexpected | 9d ago | 6d ago | 25 |

### vaultwarden

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.16.123.96` | 443 | ⚠️ unexpected | 45h ago | 45h ago | 3 |
| `104.16.132.229` | 443 | ⚠️ unexpected | 45h ago | 45h ago | 3 |
| `104.16.99.29` | 443 | ⚠️ unexpected | 45h ago | 45h ago | 3 |
| `104.17.17.78` | 443 | ⚠️ unexpected | 4d ago | 4d ago | 2 |
| `104.17.17.78` | 80 | ⚠️ unexpected | 4d ago | 4d ago | 2 |
| `104.18.14.13` | 443 | ⚠️ unexpected | 45h ago | 45h ago | 3 |
| `104.18.161.117` | 443 | ⚠️ unexpected | 45h ago | 45h ago | 3 |
| `104.18.179.120` | 443 | ⚠️ unexpected | 9d ago | 9d ago | 3 |
| `104.18.193.106` | 443 | ⚠️ unexpected | 4d ago | 4d ago | 2 |
| `104.18.27.69` | 443 | ⚠️ unexpected | 45h ago | 45h ago | 3 |
| `104.18.35.237` | 443 | ⚠️ unexpected | 45h ago | 45h ago | 3 |
| `104.20.7.63` | 443 | ⚠️ unexpected | 9d ago | 9d ago | 3 |
| `104.26.1.18` | 443 | ⚠️ unexpected | 4d ago | 4d ago | 2 |
| `151.101.129.91` | 443 | ⚠️ unexpected | 9d ago | 9d ago | 1 |
| `151.101.237.91` | 443 | ⚠️ unexpected | 9d ago | 9d ago | 1 |
| `151.101.239.52` | 443 | ⚠️ unexpected | 3d ago | 45h ago | 2 |
| `151.101.67.52` | 443 | ⚠️ unexpected | 3d ago | 3d ago | 1 |
| `162.125.248.18` | 443 | ⚠️ unexpected | 45h ago | 45h ago | 1 |
| `162.125.71.18` | 443 | ⚠️ unexpected | 45h ago | 45h ago | 1 |
| `162.159.137.232` | 443 | ⚠️ unexpected | 45h ago | 45h ago | 3 |
| `172.67.74.138` | 443 | ⚠️ unexpected | 44h ago | 44h ago | 3 |
| `18.195.2.2` | 443 | ⚠️ unexpected | 9d ago | 9d ago | 3 |
| `185.31.213.113` | 443 | ⚠️ unexpected | 9d ago | 9d ago | 3 |
| `193.212.190.216` | 443 | ⚠️ unexpected | 9d ago | 9d ago | 1 |
| `194.132.66.34` | 443 | ⚠️ unexpected | 45h ago | 45h ago | 2 |
| `217.114.94.2` | 443 | ⚠️ unexpected | 45h ago | 45h ago | 3 |
| `3.167.1.165` | 443 | ⚠️ unexpected | 9d ago | 9d ago | 3 |
| `3.167.2.39` | 443 | ⚠️ unexpected | 9d ago | 9d ago | 2 |
| `3.167.2.44` | 443 | ⚠️ unexpected | 45h ago | 45h ago | 3 |
| `3.167.2.45` | 443 | ⚠️ unexpected | 45h ago | 45h ago | 3 |
| `3.167.2.93` | 443 | ⚠️ unexpected | 9d ago | 9d ago | 2 |
| `3.167.2.97` | 443 | ⚠️ unexpected | 45h ago | 45h ago | 3 |
| `3.33.186.135` | 443 | ⚠️ unexpected | 45h ago | 45h ago | 3 |
| `34.110.155.89` | 443 | ⚠️ unexpected | 45h ago | 45h ago | 3 |
| `35.186.224.24` | 443 | ⚠️ unexpected | 47h ago | 47h ago | 2 |
| `52.195.100.115` | 443 | ⚠️ unexpected | 4d ago | 4d ago | 2 |
| `52.198.57.38` | 443 | ⚠️ unexpected | 9d ago | 9d ago | 1 |
| `52.222.187.52` | 443 | ⚠️ unexpected | 9d ago | 9d ago | 3 |
| `52.84.50.103` | 443 | ⚠️ unexpected | 9d ago | 9d ago | 2 |
| `52.84.50.125` | 443 | ⚠️ unexpected | 45h ago | 45h ago | 3 |
| `52.84.50.126` | 443 | ⚠️ unexpected | 45h ago | 45h ago | 3 |
| `52.84.50.128` | 443 | ⚠️ unexpected | 47h ago | 47h ago | 2 |
| `52.84.50.128` | 80 | ⚠️ unexpected | 47h ago | 47h ago | 2 |
| `52.84.50.14` | 443 | ⚠️ unexpected | 4d ago | 4d ago | 2 |
| `52.84.50.16` | 443 | ⚠️ unexpected | 45h ago | 45h ago | 3 |
| `52.84.50.22` | 443 | ⚠️ unexpected | 45h ago | 45h ago | 3 |
| `52.84.50.4` | 443 | ⚠️ unexpected | 9d ago | 9d ago | 2 |
| `52.84.50.61` | 443 | ⚠️ unexpected | 45h ago | 45h ago | 3 |
| `62.249.184.112` | 443 | ⚠️ unexpected | 44h ago | 44h ago | 1 |
| `66.33.60.34` | 443 | ⚠️ unexpected | 9d ago | 9d ago | 3 |
| `76.76.21.21` | 443 | ⚠️ unexpected | 9d ago | 4d ago | 5 |
| `76.76.21.22` | 443 | ⚠️ unexpected | 4d ago | 4d ago | 2 |
| `95.101.10.146` | 443 | ⚠️ unexpected | 45h ago | 45h ago | 1 |
| `95.101.10.154` | 443 | ⚠️ unexpected | 45h ago | 45h ago | 1 |
| `98.82.155.134` | 443 | ⚠️ unexpected | 9d ago | 9d ago | 3 |

---

*Auto-generated by `scripts/generate-egress-index.sh`. Allow-list: `config/supply-chain/egress-baseline.yaml` (frozen prefixes; re-seed with `scripts/egress-baseline.sh`). Anomaly trail: `data/egress/anomalies.jsonl`. Alerts armed by renaming `config/prometheus/alerts/egress-alerts.yml.disabled` → `.yml` after the baseline window (shadow-first).*
