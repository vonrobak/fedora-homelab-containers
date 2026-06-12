# Egress Observatory — Baseline Index (Auto-Generated)

**Generated:** 2026-06-12 22:25:11 UTC
**Implements:** ADR-030 P7 (Tier 4) — egress detection. **Mode:** live (alerting)

Host-side `/proc/<pid>/net/{tcp,tcp6}` sampling of reverse_proxy-tier containers (attributable, rootless, scratch-safe, DNS-method-agnostic). Detection, not prevention. See `config/supply-chain/known-egress.md` for method and residual/evasion scope.

## Pipeline health

| Component | Last run | Detail |
|---|---|---|
| Collector (`egress-collector.service`) | 18s ago | 22 services sampled |
| Classifier (`egress-detect.timer`) | 24s ago | mode=live (alerting); last window 8 dest(s) |

## Per-service egress

| Service | Mode | Public dests | Unexpected | Peers (swarm) |
|---|---|---|---|---|
| alert-discord-relay | classify | 5 | ✅ 0 | — |
| alertmanager | classify | 2 | ✅ 0 | — |
| audiobookshelf | classify | — | — | — |
| authelia | classify | — | — | — |
| blackbox-exporter | classify | — | — | — |
| crowdsec | classify | 54 | ✅ 0 | — |
| forgejo | classify | — | — | — |
| gathio | classify | 3 | ✅ 0 | — |
| grafana | classify | 3 | ✅ 0 | — |
| home-assistant | classify | 50 | ✅ 0 | — |
| immich-server | classify | 3 | ✅ 0 | — |
| jellyfin | classify | 15 | ✅ 0 | — |
| loki | classify | 1 | ✅ 0 | — |
| navidrome | classify | 9 | ✅ 0 | — |
| nextcloud | classify | 4 | ✅ 0 | — |
| pihole-exporter | classify | — | — | — |
| prometheus | classify | — | — | — |
| proton-bridge | classify | 2 | ✅ 0 | — |
| qbittorrent | peer-swarm (count-only) | — | — | 131 |
| traefik | classify | 7 | ✅ 0 | — |
| unpoller | classify | — | — | — |
| vaultwarden | peer-swarm (count-only) | — | — | — |

## Zero-egress candidates — blast-radius reduction (REPORT ONLY)

Egress-tier services with **no observed public destination** over the window. Each is a candidate to move to an `Internal=true` network (shrinking the surface Tier 4 watches). **Not an automated change** — manual, per-service review (Feb-2026 21-container outage precedent). A short window will list services that simply hadn't egressed yet (e.g. proton-bridge in `TIME_WAIT`); confirm against a full ≥7-day baseline before acting.

> audiobookshelf, authelia, blackbox-exporter, forgejo, pihole-exporter, prometheus, unpoller

## Observed destinations (durable state)

### alert-discord-relay

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `162.159.128.233` | 443 | ✅ expected | 16d ago | 3h ago | 38 |
| `162.159.135.232` | 443 | ✅ expected | 19d ago | 53m ago | 51 |
| `162.159.136.232` | 443 | ✅ expected | 11d ago | 26h ago | 39 |
| `162.159.137.232` | 443 | ✅ expected | 7d ago | 3d ago | 40 |
| `162.159.138.232` | 443 | ✅ expected | 18d ago | 108m ago | 53 |

### alertmanager

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `162.159.135.232` | 443 | ✅ expected | 18d ago | 18d ago | 2 |
| `162.159.138.232` | 80 | ✅ expected | 18d ago | 18d ago | 2 |

### crowdsec

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.20.41.3` | 443 | ✅ expected | 4h ago | 4h ago | 2 |
| `108.128.137.208` | 443 | ✅ expected | 14d ago | 6d ago | 486 |
| `108.128.190.179` | 443 | ✅ expected | 16d ago | 7d ago | 515 |
| `108.128.222.234` | 443 | ✅ expected | 19d ago | 11d ago | 472 |
| `108.132.135.16` | 443 | ✅ expected | 4d ago | 3d ago | 68 |
| `108.132.165.136` | 443 | ✅ expected | 10d ago | 5d ago | 237 |
| `172.66.154.109` | 443 | ✅ expected | 4h ago | 4h ago | 2 |
| `176.34.92.0` | 443 | ✅ expected | 28h ago | 11h ago | 43 |
| `18.200.183.204` | 443 | ✅ expected | 19d ago | 13d ago | 362 |
| `34.240.98.252` | 443 | ✅ expected | 8d ago | 4d ago | 252 |
| `34.242.194.148` | 443 | ✅ expected | 12d ago | 6d ago | 406 |
| `34.248.190.12` | 443 | ✅ expected | 20h ago | 5h ago | 56 |
| `34.249.149.68` | 443 | ✅ expected | 9d ago | 4d ago | 277 |
| `34.249.172.50` | 443 | ✅ expected | 119m ago | 119m ago | 5 |
| `34.250.39.237` | 443 | ✅ expected | 6d ago | 28h ago | 255 |
| `34.250.77.39` | 443 | ✅ expected | 19d ago | 9d ago | 582 |
| `34.251.83.134` | 443 | ✅ expected | 2d ago | 41h ago | 42 |
| `34.254.73.132` | 443 | ✅ expected | 6d ago | 19h ago | 421 |
| `34.255.101.100` | 443 | ✅ expected | 5h ago | 5h ago | 5 |
| `34.255.143.231` | 443 | ✅ expected | 3d ago | 2d ago | 73 |
| `34.255.59.56` | 443 | ✅ expected | 19d ago | 9d ago | 512 |
| `52.16.64.132` | 443 | ✅ expected | 2h ago | 2h ago | 5 |
| `52.17.17.55` | 443 | ✅ expected | 39h ago | 33h ago | 20 |
| `52.17.58.50` | 443 | ✅ expected | 18d ago | 16d ago | 181 |
| `52.18.68.74` | 443 | ✅ expected | 16d ago | 9d ago | 458 |
| `52.19.64.236` | 443 | ✅ expected | 5d ago | 26h ago | 191 |
| `52.210.229.63` | 443 | ✅ expected | 10d ago | 4d ago | 370 |
| `52.213.228.152` | 443 | ✅ expected | 4d ago | 3h ago | 269 |
| `52.213.66.10` | 443 | ✅ expected | 2d ago | 24s ago | 129 |
| `52.30.5.78` | 443 | ✅ expected | 19d ago | 16d ago | 157 |
| `52.48.23.149` | 443 | ✅ expected | 7d ago | 4d ago | 232 |
| `52.48.238.219` | 443 | ✅ expected | 4d ago | 119m ago | 259 |
| `52.48.65.76` | 443 | ✅ expected | 11h ago | 10m ago | 41 |
| `52.48.93.17` | 443 | ✅ expected | 25h ago | 10h ago | 35 |
| `52.49.4.206` | 443 | ✅ expected | 98m ago | 87m ago | 5 |
| `52.50.224.74` | 443 | ✅ expected | 2d ago | 45h ago | 29 |
| `52.84.50.42` | 443 | ✅ expected | 4h ago | 4h ago | 2 |
| `54.170.104.57` | 443 | ✅ expected | 40h ago | 35h ago | 15 |
| `54.195.186.68` | 443 | ✅ expected | 7d ago | 4d ago | 249 |
| `54.228.220.78` | 443 | ✅ expected | 40h ago | 29h ago | 30 |
| `54.246.207.199` | 443 | ✅ expected | 9d ago | 8d ago | 113 |
| `54.75.245.133` | 443 | ✅ expected | 14h ago | 32m ago | 40 |
| `54.76.169.38` | 443 | ✅ expected | 3d ago | 2d ago | 64 |
| `54.76.192.134` | 443 | ✅ expected | 11d ago | 6d ago | 337 |
| `54.77.24.165` | 443 | ✅ expected | 2d ago | 2d ago | 23 |
| `54.77.8.107` | 443 | ✅ expected | 19d ago | 11d ago | 533 |
| `63.34.141.128` | 443 | ✅ expected | 19d ago | 15d ago | 196 |
| `63.35.170.229` | 443 | ✅ expected | 6d ago | 2d ago | 228 |
| `63.35.22.155` | 443 | ✅ expected | 19d ago | 19d ago | 15 |
| `79.125.15.38` | 443 | ✅ expected | 19d ago | 14d ago | 232 |
| `99.80.124.24` | 443 | ✅ expected | 26h ago | 7h ago | 49 |
| `99.80.129.27` | 443 | ✅ expected | 15d ago | 10d ago | 263 |
| `99.80.232.1` | 443 | ✅ expected | 87m ago | 87m ago | 5 |
| `99.81.12.92` | 443 | ✅ expected | 3d ago | 2d ago | 67 |

### gathio

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.16.1.34` | 443 | ✅ expected | 4h ago | 4h ago | 6 |
| `104.16.4.34` | 443 | ✅ expected | 16d ago | 2d ago | 34 |
| `104.16.7.34` | 443 | ✅ expected | 3d ago | 3d ago | 4 |

### grafana

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `192.0.73.2` | 443 | ✅ expected | 18d ago | 6d ago | 8 |
| `34.120.177.193` | 443 | ✅ expected | 19d ago | 24s ago | 13760 |
| `34.96.126.106` | 443 | ✅ expected | 18d ago | 12h ago | 92 |

### home-assistant

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.26.4.238` | 443 | ✅ expected | 19d ago | 5h ago | 27 |
| `104.26.5.238` | 443 | ✅ expected | 19d ago | 17h ago | 40 |
| `151.101.1.195` | 443 | ✅ expected | 19d ago | 32m ago | 28 |
| `151.101.65.195` | 443 | ✅ expected | 17d ago | 3d ago | 14 |
| `157.249.81.141` | 443 | ✅ expected | 19d ago | 4h ago | 225 |
| `172.67.68.90` | 443 | ✅ expected | 18d ago | 66m ago | 35 |
| `18.156.89.194` | 443 | ✅ expected | 6d ago | 10m ago | 684 |
| `18.158.11.29` | 8883 | ✅ expected | 2d ago | 20h ago | 5654 |
| `18.158.133.191` | 8883 | ✅ expected | 4h ago | 24s ago | 492 |
| `18.158.136.104` | 8883 | ✅ expected | 14h ago | 4h ago | 1129 |
| `18.158.217.49` | 8883 | ✅ expected | 5d ago | 4d ago | 2668 |
| `18.158.22.138` | 8883 | ✅ expected | 16d ago | 16d ago | 1702 |
| `18.158.224.141` | 8883 | ✅ expected | 9d ago | 7d ago | 5641 |
| `18.159.77.159` | 8883 | ✅ expected | 7d ago | 7d ago | 755 |
| `18.159.79.242` | 8883 | ✅ expected | 11d ago | 10d ago | 2777 |
| `18.184.210.208` | 8883 | ✅ expected | 19d ago | 18d ago | 1297 |
| `18.184.241.150` | 8883 | ✅ expected | 5d ago | 5d ago | 58 |
| `18.193.19.139` | 8883 | ✅ expected | 12h ago | 12h ago | 1 |
| `18.194.113.141` | 8883 | ✅ expected | 14d ago | 14d ago | 356 |
| `18.194.166.209` | 8883 | ✅ expected | 3d ago | 2d ago | 3094 |
| `18.195.53.77` | 8883 | ✅ expected | 20h ago | 14h ago | 760 |
| `18.196.104.106` | 8883 | ✅ expected | 12d ago | 11d ago | 2729 |
| `18.198.195.194` | 8883 | ✅ expected | 18d ago | 16d ago | 5585 |
| `3.120.211.84` | 8883 | ✅ expected | 7d ago | 5d ago | 4832 |
| `3.120.216.195` | 443 | ✅ expected | 15d ago | 6d ago | 800 |
| `3.120.53.2` | 8883 | ✅ expected | 16d ago | 14d ago | 3923 |
| `3.121.10.31` | 8883 | ✅ expected | 14d ago | 14d ago | 759 |
| `3.121.101.237` | 8883 | ✅ expected | 4d ago | 4d ago | 2420 |
| `3.121.111.53` | 443 | ✅ expected | 10d ago | 4d ago | 599 |
| `3.121.169.115` | 8883 | ✅ expected | 14d ago | 12d ago | 4472 |
| `3.122.171.67` | 443 | ✅ expected | 14d ago | 6d ago | 708 |
| `3.122.70.209` | 8883 | ✅ expected | 10d ago | 9d ago | 2815 |
| `3.124.29.182` | 443 | ✅ expected | 19d ago | 10d ago | 810 |
| `3.125.16.42` | 443 | ✅ expected | 6d ago | 4d ago | 239 |
| `3.125.66.145` | 443 | ✅ expected | 19d ago | 14d ago | 491 |
| `3.67.142.130` | 443 | ✅ expected | 19d ago | 9d ago | 907 |
| `3.71.130.230` | 443 | ✅ expected | 4h ago | 4h ago | 1 |
| `35.156.5.143` | 443 | ✅ expected | 9d ago | 6d ago | 254 |
| `35.158.64.12` | 443 | ✅ expected | 9d ago | 2d ago | 693 |
| `52.28.32.0` | 443 | ✅ expected | 5d ago | 24s ago | 476 |
| `52.29.1.243` | 443 | ✅ expected | 4d ago | 24s ago | 421 |
| `52.29.210.73` | 443 | ✅ expected | 19d ago | 9d ago | 926 |
| `52.57.174.242` | 443 | ✅ expected | 19d ago | 15d ago | 429 |
| `52.58.153.107` | 443 | ✅ expected | 11d ago | 5d ago | 542 |
| `52.58.33.43` | 443 | ✅ expected | 4d ago | 10m ago | 481 |
| `63.181.21.188` | 443 | ✅ expected | 6d ago | 24s ago | 674 |
| `63.181.74.73` | 443 | ✅ expected | 19d ago | 11d ago | 789 |
| `63.182.123.150` | 443 | ✅ expected | 2d ago | 21m ago | 221 |
| `63.185.122.149` | 443 | ✅ expected | 4h ago | 4h ago | 1 |
| `91.98.4.78` | 443 | ✅ expected | 4h ago | 4h ago | 1 |

### immich-server

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.21.71.92` | 443 | ✅ expected | 19d ago | 32m ago | 503 |
| `172.67.170.79` | 443 | ✅ expected | 19d ago | 87m ago | 490 |
| `188.114.97.4` | 443 | ✅ expected | 46h ago | 46h ago | 2 |

### jellyfin

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.17.207.5` | 443 | ✅ expected | 19d ago | 4d ago | 9 |
| `104.17.208.5` | 443 | ✅ expected | 18d ago | 47h ago | 23 |
| `139.59.139.28` | 443 | ✅ expected | 16d ago | 23h ago | 13 |
| `146.190.237.6` | 443 | ✅ expected | 14d ago | 4h ago | 20 |
| `151.101.1.229` | 443 | ✅ expected | 14d ago | 5d ago | 10 |
| `151.101.129.229` | 443 | ✅ expected | 13d ago | 2d ago | 10 |
| `151.101.193.229` | 443 | ✅ expected | 17d ago | 8d ago | 6 |
| `151.101.65.229` | 443 | ✅ expected | 3d ago | 23h ago | 3 |
| `157.245.38.19` | 443 | ✅ expected | 15d ago | 15d ago | 5 |
| `161.35.245.42` | 443 | ✅ expected | 13d ago | 23h ago | 12 |
| `165.227.169.147` | 443 | ✅ expected | 19d ago | 3d ago | 32 |
| `165.227.244.161` | 443 | ✅ expected | 18d ago | 3d ago | 19 |
| `178.105.98.131` | 443 | ✅ expected | 19d ago | 2d ago | 17 |
| `206.189.97.173` | 443 | ✅ expected | 12d ago | 47h ago | 19 |
| `68.183.204.194` | 443 | ✅ expected | 19d ago | 47h ago | 11 |

### loki

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `34.96.126.106` | 443 | ✅ expected | 19d ago | 24s ago | 570 |

### navidrome

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.21.43.229` | 443 | ✅ expected | 3d ago | 3d ago | 1 |
| `130.211.19.189` | 443 | ✅ expected | 18d ago | 15d ago | 13 |
| `151.101.237.188` | 443 | ✅ expected | 18d ago | 15d ago | 7 |
| `151.101.238.53` | 443 | ✅ expected | 18d ago | 15d ago | 6 |
| `151.101.238.79` | 443 | ✅ expected | 18d ago | 15d ago | 6 |
| `172.67.186.189` | 443 | ✅ expected | 4h ago | 4h ago | 3 |
| `2.22.225.107` | 443 | ✅ expected | 15d ago | 15d ago | 3 |
| `2.22.225.83` | 443 | ✅ expected | 18d ago | 18d ago | 4 |
| `209.141.42.198` | 443 | ✅ expected | 19d ago | 3h ago | 63 |

### nextcloud

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `65.108.197.113` | 443 | ✅ expected | 16d ago | 2d ago | 10 |
| `65.109.114.179` | 443 | ✅ expected | 18d ago | 13h ago | 17 |
| `65.21.231.50` | 443 | ✅ expected | 10d ago | 13h ago | 3 |
| `95.217.53.153` | 443 | ✅ expected | 17d ago | 2d ago | 18 |

### proton-bridge

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `185.70.42.41` | 443 | ✅ expected | 19d ago | 24s ago | 15562 |
| `185.70.42.45` | 443 | ✅ expected | 19d ago | 10m ago | 503 |

### traefik

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.19.192.29` | 443 | ✅ expected | 15d ago | 15d ago | 5 |
| `104.19.193.29` | 443 | ✅ expected | 18d ago | 18d ago | 6 |
| `104.26.3.101` | 443 | ✅ expected | 18d ago | 4h ago | 24 |
| `140.82.121.5` | 443 | ✅ expected | 18d ago | 47h ago | 13 |
| `140.82.121.6` | 443 | ✅ expected | 19d ago | 2d ago | 11 |
| `172.65.32.248` | 443 | ✅ expected | 18d ago | 15d ago | 25 |
| `172.67.75.8` | 443 | ✅ expected | 4d ago | 4d ago | 5 |

---

*Auto-generated by `scripts/generate-egress-index.sh`. Allow-list: `config/supply-chain/egress-baseline.yaml` (frozen prefixes; re-seed with `scripts/egress-baseline.sh`). Anomaly trail: `data/egress/anomalies.jsonl`. Alerts armed by renaming `config/prometheus/alerts/egress-alerts.yml.disabled` → `.yml` after the baseline window (shadow-first).*
