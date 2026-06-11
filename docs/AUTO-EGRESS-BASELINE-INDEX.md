# Egress Observatory — Baseline Index (Auto-Generated)

**Generated:** 2026-06-11 05:00:36 UTC
**Implements:** ADR-030 P7 (Tier 4) — egress detection. **Mode:** shadow (observe-only)

Host-side `/proc/<pid>/net/{tcp,tcp6}` sampling of reverse_proxy-tier containers (attributable, rootless, scratch-safe, DNS-method-agnostic). Detection, not prevention. See `config/supply-chain/known-egress.md` for method and residual/evasion scope.

## Pipeline health

| Component | Last run | Detail |
|---|---|---|
| Collector (`egress-collector.service`) | 28s ago | 22 services sampled |
| Classifier (`egress-detect.timer`) | 70s ago | mode=shadow (observe-only); last window 7 dest(s) |

## Per-service egress

| Service | Mode | Public dests | Unexpected | Peers (swarm) |
|---|---|---|---|---|
| alert-discord-relay | classify | 5 | 5 (unarmed) | — |
| alertmanager | classify | 2 | 2 (unarmed) | — |
| audiobookshelf | classify | — | — | — |
| authelia | classify | — | — | — |
| blackbox-exporter | classify | — | — | — |
| crowdsec | classify | 37 | 37 (unarmed) | — |
| forgejo | classify | — | — | — |
| gathio | classify | 2 | 2 (unarmed) | — |
| grafana | classify | 3 | 3 (unarmed) | — |
| home-assistant | classify | 43 | 43 (unarmed) | — |
| immich-server | classify | 3 | 3 (unarmed) | — |
| jellyfin | classify | 15 | 15 (unarmed) | — |
| loki | classify | 1 | 1 (unarmed) | — |
| navidrome | classify | 8 | 8 (unarmed) | — |
| nextcloud | classify | 4 | 4 (unarmed) | — |
| pihole-exporter | classify | — | — | — |
| prometheus | classify | — | — | — |
| proton-bridge | classify | 2 | 2 (unarmed) | — |
| qbittorrent | peer-swarm (count-only) | — | — | 140 |
| traefik | classify | 8 | 8 (unarmed) | — |
| unpoller | classify | — | — | — |
| vaultwarden | classify | 80 | 80 (unarmed) | — |

## Zero-egress candidates — blast-radius reduction (REPORT ONLY)

Egress-tier services with **no observed public destination** over the window. Each is a candidate to move to an `Internal=true` network (shrinking the surface Tier 4 watches). **Not an automated change** — manual, per-service review (Feb-2026 21-container outage precedent). A short window will list services that simply hadn't egressed yet (e.g. proton-bridge in `TIME_WAIT`); confirm against a full ≥7-day baseline before acting.

> audiobookshelf, authelia, blackbox-exporter, forgejo, pihole-exporter, prometheus, unpoller

## Observed destinations (durable state)

### alert-discord-relay

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `162.159.128.233` | 443 | ⚠️ unexpected | 14d ago | 2d ago | 32 |
| `162.159.135.232` | 443 | ⚠️ unexpected | 17d ago | 2d ago | 41 |
| `162.159.136.232` | 443 | ⚠️ unexpected | 10d ago | 2d ago | 37 |
| `162.159.137.232` | 443 | ⚠️ unexpected | 6d ago | 2d ago | 40 |
| `162.159.138.232` | 443 | ⚠️ unexpected | 16d ago | 2d ago | 44 |

### alertmanager

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `162.159.135.232` | 443 | ⚠️ unexpected | 16d ago | 16d ago | 2 |
| `162.159.138.232` | 80 | ⚠️ unexpected | 16d ago | 16d ago | 2 |

### crowdsec

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `108.128.137.208` | 443 | ⚠️ unexpected | 12d ago | 4d ago | 486 |
| `108.128.190.179` | 443 | ⚠️ unexpected | 14d ago | 5d ago | 515 |
| `108.128.222.234` | 443 | ⚠️ unexpected | 17d ago | 10d ago | 472 |
| `108.132.135.16` | 443 | ⚠️ unexpected | 2d ago | 2d ago | 68 |
| `108.132.165.136` | 443 | ⚠️ unexpected | 8d ago | 3d ago | 237 |
| `18.200.183.204` | 443 | ⚠️ unexpected | 17d ago | 11d ago | 362 |
| `34.240.98.252` | 443 | ⚠️ unexpected | 6d ago | 3d ago | 252 |
| `34.242.194.148` | 443 | ⚠️ unexpected | 11d ago | 5d ago | 406 |
| `34.249.149.68` | 443 | ⚠️ unexpected | 7d ago | 2d ago | 277 |
| `34.250.39.237` | 443 | ⚠️ unexpected | 4d ago | 8h ago | 226 |
| `34.250.77.39` | 443 | ⚠️ unexpected | 17d ago | 7d ago | 582 |
| `34.251.83.134` | 443 | ⚠️ unexpected | 11h ago | 22m ago | 42 |
| `34.254.73.132` | 443 | ⚠️ unexpected | 4d ago | 11m ago | 357 |
| `34.255.143.231` | 443 | ⚠️ unexpected | 2d ago | 15h ago | 73 |
| `34.255.59.56` | 443 | ⚠️ unexpected | 17d ago | 8d ago | 512 |
| `52.17.58.50` | 443 | ⚠️ unexpected | 17d ago | 14d ago | 181 |
| `52.18.68.74` | 443 | ⚠️ unexpected | 14d ago | 7d ago | 458 |
| `52.19.64.236` | 443 | ⚠️ unexpected | 3d ago | 3h ago | 171 |
| `52.210.229.63` | 443 | ⚠️ unexpected | 9d ago | 3d ago | 370 |
| `52.213.228.152` | 443 | ⚠️ unexpected | 2d ago | 44m ago | 155 |
| `52.213.66.10` | 443 | ⚠️ unexpected | 9h ago | 75m ago | 24 |
| `52.30.5.78` | 443 | ⚠️ unexpected | 17d ago | 14d ago | 157 |
| `52.48.23.149` | 443 | ⚠️ unexpected | 5d ago | 2d ago | 232 |
| `52.48.238.219` | 443 | ⚠️ unexpected | 2d ago | 44m ago | 116 |
| `52.50.224.74` | 443 | ⚠️ unexpected | 11h ago | 3h ago | 29 |
| `54.195.186.68` | 443 | ⚠️ unexpected | 6d ago | 2d ago | 249 |
| `54.246.207.199` | 443 | ⚠️ unexpected | 7d ago | 6d ago | 113 |
| `54.76.169.38` | 443 | ⚠️ unexpected | 46h ago | 21h ago | 64 |
| `54.76.192.134` | 443 | ⚠️ unexpected | 9d ago | 4d ago | 337 |
| `54.77.24.165` | 443 | ⚠️ unexpected | 12h ago | 9h ago | 23 |
| `54.77.8.107` | 443 | ⚠️ unexpected | 17d ago | 9d ago | 533 |
| `63.34.141.128` | 443 | ⚠️ unexpected | 17d ago | 13d ago | 196 |
| `63.35.170.229` | 443 | ⚠️ unexpected | 4d ago | 15h ago | 228 |
| `63.35.22.155` | 443 | ⚠️ unexpected | 17d ago | 17d ago | 15 |
| `79.125.15.38` | 443 | ⚠️ unexpected | 17d ago | 13d ago | 232 |
| `99.80.129.27` | 443 | ⚠️ unexpected | 13d ago | 8d ago | 263 |
| `99.81.12.92` | 443 | ⚠️ unexpected | 2d ago | 26h ago | 67 |

### gathio

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.16.4.34` | 443 | ⚠️ unexpected | 14d ago | 7h ago | 34 |
| `104.16.7.34` | 443 | ⚠️ unexpected | 2d ago | 2d ago | 4 |

### grafana

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `192.0.73.2` | 443 | ⚠️ unexpected | 16d ago | 4d ago | 8 |
| `34.120.177.193` | 443 | ⚠️ unexpected | 17d ago | 70s ago | 12532 |
| `34.96.126.106` | 443 | ⚠️ unexpected | 16d ago | 18h ago | 82 |

### home-assistant

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.26.4.238` | 443 | ⚠️ unexpected | 17d ago | 11m ago | 25 |
| `104.26.5.238` | 443 | ⚠️ unexpected | 17d ago | 9h ago | 38 |
| `151.101.1.195` | 443 | ⚠️ unexpected | 17d ago | 8h ago | 22 |
| `151.101.65.195` | 443 | ⚠️ unexpected | 15d ago | 32h ago | 14 |
| `157.249.81.141` | 443 | ⚠️ unexpected | 17d ago | 70s ago | 202 |
| `172.67.68.90` | 443 | ⚠️ unexpected | 16d ago | 2d ago | 32 |
| `18.156.89.194` | 443 | ⚠️ unexpected | 5d ago | 22m ago | 504 |
| `18.158.11.29` | 8883 | ⚠️ unexpected | 27h ago | 70s ago | 3228 |
| `18.158.217.49` | 8883 | ⚠️ unexpected | 4d ago | 3d ago | 2668 |
| `18.158.22.138` | 8883 | ⚠️ unexpected | 15d ago | 14d ago | 1702 |
| `18.158.224.141` | 8883 | ⚠️ unexpected | 8d ago | 6d ago | 5641 |
| `18.159.77.159` | 8883 | ⚠️ unexpected | 6d ago | 5d ago | 755 |
| `18.159.79.242` | 8883 | ⚠️ unexpected | 10d ago | 9d ago | 2777 |
| `18.184.210.208` | 8883 | ⚠️ unexpected | 17d ago | 17d ago | 1297 |
| `18.184.241.150` | 8883 | ⚠️ unexpected | 4d ago | 4d ago | 58 |
| `18.194.113.141` | 8883 | ⚠️ unexpected | 12d ago | 12d ago | 356 |
| `18.194.166.209` | 8883 | ⚠️ unexpected | 2d ago | 27h ago | 3094 |
| `18.196.104.106` | 8883 | ⚠️ unexpected | 11d ago | 10d ago | 2729 |
| `18.198.195.194` | 8883 | ⚠️ unexpected | 17d ago | 15d ago | 5585 |
| `3.120.211.84` | 8883 | ⚠️ unexpected | 5d ago | 4d ago | 4832 |
| `3.120.216.195` | 443 | ⚠️ unexpected | 14d ago | 5d ago | 800 |
| `3.120.53.2` | 8883 | ⚠️ unexpected | 14d ago | 13d ago | 3923 |
| `3.121.10.31` | 8883 | ⚠️ unexpected | 13d ago | 12d ago | 759 |
| `3.121.101.237` | 8883 | ⚠️ unexpected | 3d ago | 2d ago | 2420 |
| `3.121.111.53` | 443 | ⚠️ unexpected | 9d ago | 3d ago | 599 |
| `3.121.169.115` | 8883 | ⚠️ unexpected | 12d ago | 11d ago | 4472 |
| `3.122.171.67` | 443 | ⚠️ unexpected | 13d ago | 4d ago | 708 |
| `3.122.70.209` | 8883 | ⚠️ unexpected | 9d ago | 8d ago | 2815 |
| `3.124.29.182` | 443 | ⚠️ unexpected | 17d ago | 9d ago | 810 |
| `3.125.16.42` | 443 | ⚠️ unexpected | 4d ago | 2d ago | 239 |
| `3.125.66.145` | 443 | ⚠️ unexpected | 17d ago | 13d ago | 491 |
| `3.67.142.130` | 443 | ⚠️ unexpected | 17d ago | 7d ago | 907 |
| `35.156.5.143` | 443 | ⚠️ unexpected | 7d ago | 4d ago | 254 |
| `35.158.64.12` | 443 | ⚠️ unexpected | 7d ago | 14h ago | 693 |
| `52.28.32.0` | 443 | ⚠️ unexpected | 3d ago | 70s ago | 308 |
| `52.29.1.243` | 443 | ⚠️ unexpected | 2d ago | 70s ago | 264 |
| `52.29.210.73` | 443 | ⚠️ unexpected | 17d ago | 7d ago | 926 |
| `52.57.174.242` | 443 | ⚠️ unexpected | 17d ago | 14d ago | 429 |
| `52.58.153.107` | 443 | ⚠️ unexpected | 9d ago | 3d ago | 542 |
| `52.58.33.43` | 443 | ⚠️ unexpected | 3d ago | 11m ago | 293 |
| `63.181.21.188` | 443 | ⚠️ unexpected | 4d ago | 54m ago | 515 |
| `63.181.74.73` | 443 | ⚠️ unexpected | 17d ago | 9d ago | 789 |
| `63.182.123.150` | 443 | ⚠️ unexpected | 14h ago | 70s ago | 45 |

### immich-server

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.21.71.92` | 443 | ⚠️ unexpected | 17d ago | 2h ago | 463 |
| `172.67.170.79` | 443 | ⚠️ unexpected | 17d ago | 11m ago | 438 |
| `188.114.97.4` | 443 | ⚠️ unexpected | 5h ago | 5h ago | 2 |

### jellyfin

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.17.207.5` | 443 | ⚠️ unexpected | 17d ago | 2d ago | 9 |
| `104.17.208.5` | 443 | ⚠️ unexpected | 16d ago | 6h ago | 23 |
| `139.59.139.28` | 443 | ⚠️ unexpected | 14d ago | 9d ago | 9 |
| `146.190.237.6` | 443 | ⚠️ unexpected | 12d ago | 5d ago | 18 |
| `151.101.1.229` | 443 | ⚠️ unexpected | 12d ago | 3d ago | 10 |
| `151.101.129.229` | 443 | ⚠️ unexpected | 11d ago | 30h ago | 10 |
| `151.101.193.229` | 443 | ⚠️ unexpected | 15d ago | 6d ago | 6 |
| `151.101.65.229` | 443 | ⚠️ unexpected | 2d ago | 2d ago | 1 |
| `157.245.38.19` | 443 | ⚠️ unexpected | 13d ago | 13d ago | 5 |
| `161.35.245.42` | 443 | ⚠️ unexpected | 11d ago | 6h ago | 10 |
| `165.227.169.147` | 443 | ⚠️ unexpected | 17d ago | 2d ago | 32 |
| `165.227.244.161` | 443 | ⚠️ unexpected | 16d ago | 2d ago | 19 |
| `178.105.98.131` | 443 | ⚠️ unexpected | 17d ago | 30h ago | 17 |
| `206.189.97.173` | 443 | ⚠️ unexpected | 10d ago | 6h ago | 19 |
| `68.183.204.194` | 443 | ⚠️ unexpected | 17d ago | 6h ago | 11 |

### loki

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `34.96.126.106` | 443 | ⚠️ unexpected | 17d ago | 2h ago | 516 |

### navidrome

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.21.43.229` | 443 | ⚠️ unexpected | 2d ago | 2d ago | 1 |
| `130.211.19.189` | 443 | ⚠️ unexpected | 16d ago | 13d ago | 13 |
| `151.101.237.188` | 443 | ⚠️ unexpected | 16d ago | 13d ago | 7 |
| `151.101.238.53` | 443 | ⚠️ unexpected | 16d ago | 13d ago | 6 |
| `151.101.238.79` | 443 | ⚠️ unexpected | 16d ago | 13d ago | 6 |
| `2.22.225.107` | 443 | ⚠️ unexpected | 13d ago | 13d ago | 3 |
| `2.22.225.83` | 443 | ⚠️ unexpected | 16d ago | 16d ago | 4 |
| `209.141.42.198` | 443 | ⚠️ unexpected | 17d ago | 5h ago | 57 |

### nextcloud

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `65.108.197.113` | 443 | ⚠️ unexpected | 14d ago | 20h ago | 10 |
| `65.109.114.179` | 443 | ⚠️ unexpected | 16d ago | 2d ago | 14 |
| `65.21.231.50` | 443 | ⚠️ unexpected | 8d ago | 8d ago | 2 |
| `95.217.53.153` | 443 | ⚠️ unexpected | 15d ago | 20h ago | 18 |

### proton-bridge

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `185.70.42.41` | 443 | ⚠️ unexpected | 17d ago | 70s ago | 14163 |
| `185.70.42.45` | 443 | ⚠️ unexpected | 17d ago | 11m ago | 469 |

### traefik

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.19.192.29` | 443 | ⚠️ unexpected | 13d ago | 13d ago | 5 |
| `104.19.193.29` | 443 | ⚠️ unexpected | 16d ago | 16d ago | 6 |
| `104.26.3.101` | 443 | ⚠️ unexpected | 16d ago | 14d ago | 15 |
| `13.39.208.199` | 443 | ⚠️ unexpected | 17d ago | 6h ago | 62 |
| `140.82.121.5` | 443 | ⚠️ unexpected | 16d ago | 6h ago | 13 |
| `140.82.121.6` | 443 | ⚠️ unexpected | 17d ago | 30h ago | 11 |
| `172.65.32.248` | 443 | ⚠️ unexpected | 16d ago | 13d ago | 25 |
| `172.67.75.8` | 443 | ⚠️ unexpected | 2d ago | 2d ago | 5 |

### vaultwarden

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.16.123.96` | 443 | ⚠️ unexpected | 8d ago | 8d ago | 3 |
| `104.16.132.229` | 443 | ⚠️ unexpected | 8d ago | 8d ago | 3 |
| `104.16.99.29` | 443 | ⚠️ unexpected | 8d ago | 8d ago | 3 |
| `104.17.17.78` | 443 | ⚠️ unexpected | 10d ago | 4d ago | 5 |
| `104.17.17.78` | 80 | ⚠️ unexpected | 10d ago | 4d ago | 5 |
| `104.18.14.13` | 443 | ⚠️ unexpected | 8d ago | 8d ago | 3 |
| `104.18.161.117` | 443 | ⚠️ unexpected | 8d ago | 8d ago | 3 |
| `104.18.179.120` | 443 | ⚠️ unexpected | 16d ago | 16d ago | 3 |
| `104.18.193.106` | 443 | ⚠️ unexpected | 10d ago | 4d ago | 5 |
| `104.18.27.69` | 443 | ⚠️ unexpected | 8d ago | 8d ago | 3 |
| `104.18.35.237` | 443 | ⚠️ unexpected | 8d ago | 8d ago | 3 |
| `104.19.171.101` | 80 | ⚠️ unexpected | 4d ago | 4d ago | 3 |
| `104.19.171.101` | 443 | ⚠️ unexpected | 4d ago | 4d ago | 3 |
| `104.19.172.101` | 443 | ⚠️ unexpected | 4d ago | 4d ago | 3 |
| `104.19.172.101` | 80 | ⚠️ unexpected | 4d ago | 4d ago | 3 |
| `104.20.7.63` | 443 | ⚠️ unexpected | 16d ago | 16d ago | 3 |
| `104.26.1.18` | 443 | ⚠️ unexpected | 10d ago | 10d ago | 2 |
| `13.107.6.156` | 443 | ⚠️ unexpected | 4d ago | 4d ago | 3 |
| `135.181.128.221` | 443 | ⚠️ unexpected | 4d ago | 4d ago | 2 |
| `138.199.37.230` | 443 | ⚠️ unexpected | 4d ago | 4d ago | 3 |
| `150.171.109.200` | 443 | ⚠️ unexpected | 4d ago | 4d ago | 2 |
| `151.101.129.91` | 443 | ⚠️ unexpected | 16d ago | 16d ago | 1 |
| `151.101.237.91` | 443 | ⚠️ unexpected | 16d ago | 16d ago | 1 |
| `151.101.239.52` | 443 | ⚠️ unexpected | 10d ago | 8d ago | 2 |
| `151.101.67.52` | 443 | ⚠️ unexpected | 10d ago | 10d ago | 1 |
| `162.125.248.18` | 443 | ⚠️ unexpected | 8d ago | 8d ago | 1 |
| `162.125.71.18` | 443 | ⚠️ unexpected | 8d ago | 8d ago | 1 |
| `162.159.137.232` | 443 | ⚠️ unexpected | 8d ago | 8d ago | 3 |
| `172.66.137.109` | 443 | ⚠️ unexpected | 4d ago | 4d ago | 2 |
| `172.67.74.138` | 443 | ⚠️ unexpected | 8d ago | 8d ago | 3 |
| `18.195.2.2` | 443 | ⚠️ unexpected | 16d ago | 16d ago | 3 |
| `18.224.126.143` | 443 | ⚠️ unexpected | 4d ago | 4d ago | 3 |
| `185.109.198.109` | 80 | ⚠️ unexpected | 4d ago | 4d ago | 3 |
| `185.31.213.113` | 443 | ⚠️ unexpected | 16d ago | 16d ago | 3 |
| `193.212.190.216` | 443 | ⚠️ unexpected | 16d ago | 16d ago | 1 |
| `194.132.66.34` | 443 | ⚠️ unexpected | 8d ago | 8d ago | 2 |
| `194.242.11.186` | 443 | ⚠️ unexpected | 4d ago | 4d ago | 2 |
| `198.252.206.1` | 80 | ⚠️ unexpected | 4d ago | 4d ago | 3 |
| `198.252.206.1` | 443 | ⚠️ unexpected | 4d ago | 4d ago | 3 |
| `20.190.147.4` | 443 | ⚠️ unexpected | 4d ago | 4d ago | 3 |
| `20.190.177.20` | 443 | ⚠️ unexpected | 4d ago | 4d ago | 3 |
| `217.114.94.2` | 443 | ⚠️ unexpected | 8d ago | 8d ago | 3 |
| `3.167.1.165` | 443 | ⚠️ unexpected | 16d ago | 16d ago | 3 |
| `3.167.2.39` | 443 | ⚠️ unexpected | 16d ago | 16d ago | 2 |
| `3.167.2.44` | 443 | ⚠️ unexpected | 8d ago | 8d ago | 3 |
| `3.167.2.45` | 443 | ⚠️ unexpected | 8d ago | 8d ago | 3 |
| `3.167.2.93` | 443 | ⚠️ unexpected | 16d ago | 16d ago | 2 |
| `3.167.2.97` | 443 | ⚠️ unexpected | 8d ago | 8d ago | 3 |
| `3.33.186.135` | 443 | ⚠️ unexpected | 8d ago | 8d ago | 3 |
| `34.110.155.89` | 443 | ⚠️ unexpected | 8d ago | 8d ago | 3 |
| `34.95.108.49` | 443 | ⚠️ unexpected | 4d ago | 4d ago | 2 |
| `35.186.224.24` | 443 | ⚠️ unexpected | 8d ago | 8d ago | 2 |
| `35.231.208.158` | 443 | ⚠️ unexpected | 4d ago | 4d ago | 2 |
| `52.195.100.115` | 443 | ⚠️ unexpected | 10d ago | 10d ago | 2 |
| `52.196.64.126` | 443 | ⚠️ unexpected | 6d ago | 6d ago | 3 |
| `52.198.57.38` | 443 | ⚠️ unexpected | 16d ago | 16d ago | 1 |
| `52.222.187.52` | 443 | ⚠️ unexpected | 16d ago | 16d ago | 3 |
| `52.84.50.103` | 443 | ⚠️ unexpected | 16d ago | 32h ago | 4 |
| `52.84.50.115` | 443 | ⚠️ unexpected | 6d ago | 6d ago | 3 |
| `52.84.50.125` | 443 | ⚠️ unexpected | 8d ago | 8d ago | 3 |
| `52.84.50.126` | 443 | ⚠️ unexpected | 8d ago | 8d ago | 3 |
| `52.84.50.128` | 443 | ⚠️ unexpected | 8d ago | 8d ago | 2 |
| `52.84.50.128` | 80 | ⚠️ unexpected | 8d ago | 8d ago | 2 |
| `52.84.50.14` | 443 | ⚠️ unexpected | 10d ago | 10d ago | 2 |
| `52.84.50.16` | 443 | ⚠️ unexpected | 8d ago | 8d ago | 3 |
| `52.84.50.2` | 443 | ⚠️ unexpected | 3d ago | 3d ago | 2 |
| `52.84.50.22` | 443 | ⚠️ unexpected | 8d ago | 8d ago | 3 |
| `52.84.50.4` | 443 | ⚠️ unexpected | 16d ago | 16d ago | 2 |
| `52.84.50.61` | 443 | ⚠️ unexpected | 8d ago | 8d ago | 3 |
| `54.178.185.42` | 443 | ⚠️ unexpected | 32h ago | 32h ago | 2 |
| `54.240.174.10` | 443 | ⚠️ unexpected | 4d ago | 4d ago | 2 |
| `54.240.174.91` | 443 | ⚠️ unexpected | 4d ago | 4d ago | 2 |
| `62.249.184.112` | 443 | ⚠️ unexpected | 8d ago | 8d ago | 1 |
| `66.33.60.34` | 443 | ⚠️ unexpected | 16d ago | 16d ago | 3 |
| `76.76.21.21` | 443 | ⚠️ unexpected | 16d ago | 10d ago | 5 |
| `76.76.21.22` | 443 | ⚠️ unexpected | 10d ago | 10d ago | 2 |
| `95.101.10.146` | 443 | ⚠️ unexpected | 8d ago | 8d ago | 1 |
| `95.101.10.154` | 443 | ⚠️ unexpected | 8d ago | 8d ago | 1 |
| `95.101.10.97` | 443 | ⚠️ unexpected | 4d ago | 4d ago | 1 |
| `98.82.155.134` | 443 | ⚠️ unexpected | 16d ago | 16d ago | 3 |

---

*Auto-generated by `scripts/generate-egress-index.sh`. Allow-list: `config/supply-chain/egress-baseline.yaml` (frozen prefixes; re-seed with `scripts/egress-baseline.sh`). Anomaly trail: `data/egress/anomalies.jsonl`. Alerts armed by renaming `config/prometheus/alerts/egress-alerts.yml.disabled` → `.yml` after the baseline window (shadow-first).*
