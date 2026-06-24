# Egress Observatory — Baseline Index (Auto-Generated)

**Generated:** 2026-06-24 16:45:21 UTC
**Implements:** ADR-030 P7 (Tier 4) — egress detection. **Mode:** live (alerting)

Host-side `/proc/<pid>/net/{tcp,tcp6}` sampling of reverse_proxy-tier containers (attributable, rootless, scratch-safe, DNS-method-agnostic). Detection, not prevention. See `config/supply-chain/known-egress.md` for method and residual/evasion scope.

## Pipeline health

| Component | Last run | Detail |
|---|---|---|
| Collector (`egress-collector.service`) | 12s ago | 22 services sampled |
| Classifier (`egress-detect.timer`) | 2s ago | mode=live (alerting); last window 1 dest(s) |

## Per-service egress

| Service | Mode | Public dests | Unexpected | Peers (swarm) |
|---|---|---|---|---|
| alert-discord-relay | classify | 5 | ✅ 0 | — |
| alertmanager | classify | — | — | — |
| audiobookshelf | classify | — | — | — |
| authelia | classify | — | — | — |
| blackbox-exporter | classify | — | — | — |
| crowdsec | classify | 148 | ✅ 0 | — |
| forgejo | classify | — | — | — |
| gathio | classify | 5 | ✅ 0 | — |
| grafana | classify | 3 | ✅ 0 | — |
| home-assistant | classify | 64 | ✅ 0 | — |
| immich-server | classify | 3 | ✅ 0 | — |
| jellyfin | classify | 17 | ✅ 0 | — |
| loki | classify | 1 | ✅ 0 | — |
| navidrome | classify | 8 | ✅ 0 | — |
| nextcloud | classify | 4 | ✅ 0 | — |
| pihole-exporter | classify | — | — | — |
| prometheus | classify | — | — | — |
| proton-bridge | classify | 2 | ✅ 0 | — |
| qbittorrent | peer-swarm (count-only) | — | — | 127 |
| traefik | classify | 7 | ✅ 0 | — |
| unpoller | classify | — | — | — |
| vaultwarden | peer-swarm (count-only) | — | — | — |

## Zero-egress candidates — blast-radius reduction (REPORT ONLY)

Egress-tier services with **no observed public destination** over the window. Each is a candidate to move to an `Internal=true` network (shrinking the surface Tier 4 watches). **Not an automated change** — manual, per-service review (Feb-2026 21-container outage precedent). A short window will list services that simply hadn't egressed yet (e.g. proton-bridge in `TIME_WAIT`); confirm against a full ≥7-day baseline before acting.

> alertmanager, audiobookshelf, authelia, blackbox-exporter, forgejo, pihole-exporter, prometheus, unpoller

## Observed destinations (durable state)

Class legend: **✅ expected** (in allow-list) · **⚠️ active** (unexpected, seen within 24h — counts toward the live metric) · **🔴 sustained** (unexpected and recurring across >=1h — trips the critical alert) · **🕒 retained** (unexpected but last seen >24h ago — kept for forensics until the 30d retention prunes it; NOT in the live metric and NOT alerting).

### alert-discord-relay

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `162.159.128.233` | 443 | ✅ expected | 28d ago | 2h ago | 120 |
| `162.159.135.232` | 443 | ✅ expected | 31d ago | 85m ago | 122 |
| `162.159.136.232` | 443 | ✅ expected | 23d ago | 4h ago | 103 |
| `162.159.137.232` | 443 | ✅ expected | 19d ago | 6h ago | 103 |
| `162.159.138.232` | 443 | ✅ expected | 30d ago | 14h ago | 123 |

### crowdsec

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.20.41.3` | 443 | ✅ expected | 11d ago | 11d ago | 2 |
| `108.128.137.208` | 443 | ✅ expected | 26d ago | 18d ago | 486 |
| `108.128.190.179` | 443 | ✅ expected | 27d ago | 18d ago | 515 |
| `108.128.222.234` | 443 | ✅ expected | 30d ago | 23d ago | 472 |
| `108.131.237.209` | 443 | ✅ expected | 10d ago | 7d ago | 45 |
| `108.132.135.16` | 443 | ✅ expected | 16d ago | 15d ago | 68 |
| `108.132.143.133` | 443 | ✅ expected | 10d ago | 5d ago | 29 |
| `108.132.165.101` | 443 | ✅ expected | 9d ago | 9d ago | 10 |
| `108.132.165.136` | 443 | ✅ expected | 22d ago | 17d ago | 237 |
| `108.132.168.183` | 443 | ✅ expected | 5d ago | 2d ago | 20 |
| `108.132.178.68` | 443 | ✅ expected | 10d ago | 10d ago | 5 |
| `108.132.219.253` | 443 | ✅ expected | 7d ago | 5d ago | 20 |
| `108.132.246.192` | 443 | ✅ expected | 10d ago | 3d ago | 362 |
| `108.132.72.65` | 443 | ✅ expected | 11d ago | 9d ago | 10 |
| `108.133.21.194` | 443 | ✅ expected | 11d ago | 8d ago | 35 |
| `108.133.25.40` | 443 | ✅ expected | 11d ago | 5d ago | 39 |
| `108.133.30.139` | 443 | ✅ expected | 5d ago | 4d ago | 74 |
| `172.66.154.109` | 443 | ✅ expected | 11d ago | 11d ago | 2 |
| `176.34.92.0` | 443 | ✅ expected | 12d ago | 12d ago | 43 |
| `18.200.183.204` | 443 | ✅ expected | 31d ago | 24d ago | 362 |
| `18.200.43.102` | 443 | ✅ expected | 11d ago | 11d ago | 5 |
| `18.202.146.153` | 443 | ✅ expected | 11d ago | 6d ago | 30 |
| `18.202.172.107` | 443 | ✅ expected | 3d ago | 3d ago | 25 |
| `18.203.121.198` | 443 | ✅ expected | 11d ago | 7d ago | 40 |
| `34.240.248.6` | 443 | ✅ expected | 2d ago | 5h ago | 138 |
| `34.240.98.252` | 443 | ✅ expected | 20d ago | 16d ago | 252 |
| `34.241.216.41` | 443 | ✅ expected | 11d ago | 6d ago | 39 |
| `34.241.56.54` | 443 | ✅ expected | 6d ago | 4d ago | 30 |
| `34.242.107.114` | 443 | ✅ expected | 11d ago | 10d ago | 8 |
| `34.242.194.148` | 443 | ✅ expected | 24d ago | 18d ago | 406 |
| `34.246.166.99` | 443 | ✅ expected | 11d ago | 8d ago | 30 |
| `34.246.188.122` | 443 | ✅ expected | 5d ago | 5d ago | 10 |
| `34.247.101.158` | 443 | ✅ expected | 7d ago | 24h ago | 59 |
| `34.248.190.12` | 443 | ✅ expected | 12d ago | 11d ago | 71 |
| `34.249.149.68` | 443 | ✅ expected | 21d ago | 16d ago | 277 |
| `34.249.172.50` | 443 | ✅ expected | 11d ago | 10d ago | 20 |
| `34.249.35.132` | 443 | ✅ expected | 7h ago | 11m ago | 25 |
| `34.250.187.53` | 443 | ✅ expected | 11d ago | 8d ago | 15 |
| `34.250.233.53` | 443 | ✅ expected | 9d ago | 9d ago | 5 |
| `34.250.39.237` | 443 | ✅ expected | 18d ago | 12d ago | 255 |
| `34.250.77.39` | 443 | ✅ expected | 31d ago | 20d ago | 582 |
| `34.251.83.134` | 443 | ✅ expected | 13d ago | 13d ago | 42 |
| `34.251.85.31` | 443 | ✅ expected | 23h ago | 8h ago | 45 |
| `34.252.238.164` | 443 | ✅ expected | 7d ago | 43h ago | 80 |
| `34.252.67.120` | 443 | ✅ expected | 6d ago | 38h ago | 59 |
| `34.253.20.222` | 443 | ✅ expected | 8d ago | 8d ago | 15 |
| `34.254.73.132` | 443 | ✅ expected | 18d ago | 12d ago | 421 |
| `34.255.101.100` | 443 | ✅ expected | 11d ago | 10d ago | 20 |
| `34.255.143.231` | 443 | ✅ expected | 15d ago | 14d ago | 73 |
| `34.255.59.56` | 443 | ✅ expected | 30d ago | 21d ago | 512 |
| `46.137.116.145` | 443 | ✅ expected | 7d ago | 4d ago | 15 |
| `46.137.188.185` | 443 | ✅ expected | 9d ago | 8d ago | 10 |
| `46.137.35.14` | 443 | ✅ expected | 8d ago | 6d ago | 20 |
| `52.16.198.105` | 443 | ✅ expected | 4d ago | 3d ago | 12 |
| `52.16.244.133` | 443 | ✅ expected | 10d ago | 8d ago | 35 |
| `52.16.64.132` | 443 | ✅ expected | 11d ago | 9d ago | 15 |
| `52.17.118.72` | 443 | ✅ expected | 5d ago | 3d ago | 15 |
| `52.17.17.55` | 443 | ✅ expected | 13d ago | 13d ago | 20 |
| `52.17.173.66` | 443 | ✅ expected | 7d ago | 5d ago | 20 |
| `52.17.58.50` | 443 | ✅ expected | 30d ago | 28d ago | 181 |
| `52.18.68.74` | 443 | ✅ expected | 28d ago | 21d ago | 458 |
| `52.18.95.48` | 443 | ✅ expected | 5h ago | 42m ago | 25 |
| `52.19.134.40` | 443 | ✅ expected | 10d ago | 4h ago | 610 |
| `52.19.31.182` | 443 | ✅ expected | 8d ago | 5d ago | 159 |
| `52.19.64.236` | 443 | ✅ expected | 17d ago | 12d ago | 191 |
| `52.19.72.100` | 443 | ✅ expected | 10d ago | 10d ago | 5 |
| `52.209.0.64` | 443 | ✅ expected | 7d ago | 24h ago | 97 |
| `52.209.173.58` | 443 | ✅ expected | 4d ago | 2d ago | 139 |
| `52.210.122.225` | 443 | ✅ expected | 7d ago | 5d ago | 44 |
| `52.210.147.72` | 443 | ✅ expected | 11d ago | 9d ago | 10 |
| `52.210.229.63` | 443 | ✅ expected | 22d ago | 16d ago | 370 |
| `52.211.111.6` | 443 | ✅ expected | 23h ago | 14h ago | 45 |
| `52.211.152.103` | 443 | ✅ expected | 11d ago | 9d ago | 20 |
| `52.211.29.30` | 443 | ✅ expected | 2d ago | 74m ago | 129 |
| `52.212.199.20` | 443 | ✅ expected | 10d ago | 10d ago | 5 |
| `52.212.47.49` | 443 | ✅ expected | 9d ago | 5d ago | 49 |
| `52.213.226.37` | 443 | ✅ expected | 6d ago | 3d ago | 25 |
| `52.213.228.152` | 443 | ✅ expected | 16d ago | 9d ago | 408 |
| `52.213.66.10` | 443 | ✅ expected | 13d ago | 11d ago | 154 |
| `52.214.21.105` | 443 | ✅ expected | 3d ago | 3d ago | 5 |
| `52.214.54.249` | 443 | ✅ expected | 7d ago | 5d ago | 15 |
| `52.215.173.209` | 443 | ✅ expected | 3d ago | 2h ago | 153 |
| `52.30.165.11` | 443 | ✅ expected | 7d ago | 2d ago | 25 |
| `52.30.231.178` | 443 | ✅ expected | 7d ago | 44h ago | 63 |
| `52.30.5.78` | 443 | ✅ expected | 30d ago | 27d ago | 157 |
| `52.30.63.171` | 443 | ✅ expected | 11d ago | 8d ago | 20 |
| `52.31.252.131` | 443 | ✅ expected | 6d ago | 3d ago | 64 |
| `52.31.58.24` | 443 | ✅ expected | 5d ago | 4d ago | 74 |
| `52.48.23.149` | 443 | ✅ expected | 18d ago | 15d ago | 232 |
| `52.48.238.219` | 443 | ✅ expected | 15d ago | 10d ago | 349 |
| `52.48.65.76` | 443 | ✅ expected | 12d ago | 3d ago | 598 |
| `52.48.90.106` | 443 | ✅ expected | 7d ago | 6d ago | 15 |
| `52.48.93.17` | 443 | ✅ expected | 12d ago | 12d ago | 35 |
| `52.49.140.16` | 443 | ✅ expected | 9d ago | 5d ago | 30 |
| `52.49.212.201` | 443 | ✅ expected | 11d ago | 9d ago | 24 |
| `52.49.3.35` | 443 | ✅ expected | 10d ago | 10d ago | 10 |
| `52.49.4.206` | 443 | ✅ expected | 11d ago | 10d ago | 10 |
| `52.50.224.74` | 443 | ✅ expected | 13d ago | 13d ago | 29 |
| `52.51.148.109` | 443 | ✅ expected | 3d ago | 2d ago | 81 |
| `52.84.50.42` | 443 | ✅ expected | 11d ago | 11d ago | 2 |
| `54.154.135.155` | 443 | ✅ expected | 10d ago | 10d ago | 5 |
| `54.170.104.57` | 443 | ✅ expected | 13d ago | 13d ago | 15 |
| `54.170.163.78` | 443 | ✅ expected | 9d ago | 8d ago | 115 |
| `54.171.78.236` | 443 | ✅ expected | 7d ago | 2d ago | 40 |
| `54.194.218.193` | 443 | ✅ expected | 5d ago | 5d ago | 5 |
| `54.194.222.175` | 443 | ✅ expected | 6d ago | 6d ago | 5 |
| `54.194.85.107` | 443 | ✅ expected | 5d ago | 26h ago | 94 |
| `54.195.147.237` | 443 | ✅ expected | 7d ago | 2d ago | 60 |
| `54.195.186.68` | 443 | ✅ expected | 19d ago | 16d ago | 249 |
| `54.228.169.234` | 443 | ✅ expected | 21h ago | 9h ago | 30 |
| `54.228.220.78` | 443 | ✅ expected | 13d ago | 12d ago | 30 |
| `54.228.49.194` | 443 | ✅ expected | 11d ago | 11d ago | 5 |
| `54.229.184.213` | 443 | ✅ expected | 11d ago | 8d ago | 20 |
| `54.229.234.23` | 443 | ✅ expected | 7d ago | 4d ago | 30 |
| `54.246.207.199` | 443 | ✅ expected | 21d ago | 20d ago | 113 |
| `54.247.128.112` | 443 | ✅ expected | 3d ago | 32s ago | 225 |
| `54.72.135.60` | 443 | ✅ expected | 11d ago | 8d ago | 23 |
| `54.72.222.86` | 443 | ✅ expected | 10d ago | 9d ago | 9 |
| `54.72.42.56` | 443 | ✅ expected | 8h ago | 3h ago | 24 |
| `54.72.47.167` | 443 | ✅ expected | 10d ago | 9d ago | 15 |
| `54.73.67.52` | 443 | ✅ expected | 11d ago | 8d ago | 30 |
| `54.74.43.116` | 443 | ✅ expected | 7d ago | 4d ago | 30 |
| `54.75.182.87` | 443 | ✅ expected | 5d ago | 3d ago | 25 |
| `54.75.245.133` | 443 | ✅ expected | 12d ago | 10d ago | 140 |
| `54.76.118.150` | 443 | ✅ expected | 4d ago | 4d ago | 5 |
| `54.76.169.38` | 443 | ✅ expected | 15d ago | 14d ago | 64 |
| `54.76.192.134` | 443 | ✅ expected | 23d ago | 18d ago | 337 |
| `54.76.217.37` | 443 | ✅ expected | 7d ago | 5d ago | 19 |
| `54.76.82.20` | 443 | ✅ expected | 11d ago | 10d ago | 54 |
| `54.77.106.61` | 443 | ✅ expected | 9d ago | 5d ago | 20 |
| `54.77.130.113` | 443 | ✅ expected | 10d ago | 10d ago | 5 |
| `54.77.221.81` | 443 | ✅ expected | 7d ago | 4d ago | 30 |
| `54.77.24.165` | 443 | ✅ expected | 14d ago | 13d ago | 23 |
| `54.77.8.107` | 443 | ✅ expected | 30d ago | 22d ago | 533 |
| `54.78.193.70` | 443 | ✅ expected | 6d ago | 2d ago | 49 |
| `63.32.217.27` | 443 | ✅ expected | 7d ago | 4d ago | 19 |
| `63.33.5.76` | 443 | ✅ expected | 11d ago | 7d ago | 232 |
| `63.34.141.128` | 443 | ✅ expected | 30d ago | 26d ago | 196 |
| `63.34.177.147` | 443 | ✅ expected | 9d ago | 2h ago | 551 |
| `63.35.170.229` | 443 | ✅ expected | 18d ago | 14d ago | 228 |
| `63.35.34.90` | 443 | ✅ expected | 6d ago | 2d ago | 44 |
| `79.125.15.38` | 443 | ✅ expected | 31d ago | 26d ago | 232 |
| `79.125.93.93` | 443 | ✅ expected | 11d ago | 8d ago | 30 |
| `99.80.124.24` | 443 | ✅ expected | 12d ago | 12d ago | 49 |
| `99.80.129.27` | 443 | ✅ expected | 26d ago | 22d ago | 263 |
| `99.80.232.1` | 443 | ✅ expected | 11d ago | 8d ago | 19 |
| `99.80.39.243` | 443 | ✅ expected | 7d ago | 4d ago | 40 |
| `99.81.12.92` | 443 | ✅ expected | 15d ago | 14d ago | 67 |

### gathio

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.16.1.34` | 443 | ✅ expected | 11d ago | 11d ago | 6 |
| `104.16.11.34` | 443 | ✅ expected | 25h ago | 25h ago | 4 |
| `104.16.4.34` | 443 | ✅ expected | 28d ago | 13d ago | 34 |
| `104.16.7.34` | 443 | ✅ expected | 15d ago | 15d ago | 4 |
| `104.16.8.34` | 443 | ✅ expected | 26h ago | 26h ago | 14 |

### grafana

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `192.0.73.2` | 443 | ✅ expected | 29d ago | 3d ago | 10 |
| `34.120.177.193` | 443 | ✅ expected | 31d ago | 32s ago | 22147 |
| `34.96.126.106` | 443 | ✅ expected | 30d ago | 6h ago | 151 |

### home-assistant

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.26.4.238` | 443 | ✅ expected | 30d ago | 25h ago | 50 |
| `104.26.5.238` | 443 | ✅ expected | 31d ago | 4h ago | 63 |
| `151.101.1.195` | 443 | ✅ expected | 30d ago | 43h ago | 41 |
| `151.101.65.195` | 443 | ✅ expected | 28d ago | 19h ago | 20 |
| `157.249.81.141` | 443 | ✅ expected | 30d ago | 32s ago | 344 |
| `172.67.68.90` | 443 | ✅ expected | 30d ago | 116m ago | 56 |
| `18.156.89.194` | 443 | ✅ expected | 18d ago | 22m ago | 1737 |
| `18.157.213.101` | 8883 | ✅ expected | 9d ago | 8d ago | 2771 |
| `18.158.11.29` | 8883 | ✅ expected | 14d ago | 12d ago | 5654 |
| `18.158.133.191` | 8883 | ✅ expected | 11d ago | 10d ago | 3683 |
| `18.158.136.104` | 8883 | ✅ expected | 12d ago | 11d ago | 1129 |
| `18.158.217.49` | 8883 | ✅ expected | 17d ago | 16d ago | 2668 |
| `18.158.22.138` | 8883 | ✅ expected | 28d ago | 28d ago | 1702 |
| `18.158.224.141` | 8883 | ✅ expected | 21d ago | 19d ago | 5641 |
| `18.159.166.33` | 8883 | ✅ expected | 15h ago | 2s ago | 1805 |
| `18.159.77.159` | 8883 | ✅ expected | 19d ago | 19d ago | 755 |
| `18.159.79.242` | 8883 | ✅ expected | 23d ago | 22d ago | 2777 |
| `18.184.121.56` | 8883 | ✅ expected | 25h ago | 15h ago | 1224 |
| `18.184.241.150` | 8883 | ✅ expected | 17d ago | 17d ago | 58 |
| `18.184.90.143` | 8883 | ✅ expected | 8d ago | 7d ago | 2820 |
| `18.185.10.145` | 8883 | ✅ expected | 4d ago | 26h ago | 9731 |
| `18.185.208.158` | 443 | ✅ expected | 25h ago | 25h ago | 1 |
| `18.193.19.139` | 8883 | ✅ expected | 12d ago | 12d ago | 1 |
| `18.194.113.141` | 8883 | ✅ expected | 26d ago | 26d ago | 356 |
| `18.194.166.209` | 8883 | ✅ expected | 15d ago | 14d ago | 3094 |
| `18.195.182.246` | 8883 | ✅ expected | 6d ago | 5d ago | 3620 |
| `18.195.53.77` | 8883 | ✅ expected | 12d ago | 12d ago | 760 |
| `18.196.104.106` | 8883 | ✅ expected | 24d ago | 23d ago | 2729 |
| `18.197.66.183` | 8883 | ✅ expected | 4d ago | 4d ago | 1 |
| `18.198.169.78` | 8883 | ✅ expected | 5d ago | 5d ago | 357 |
| `18.198.177.41` | 8883 | ✅ expected | 5d ago | 4d ago | 1795 |
| `18.198.195.194` | 8883 | ✅ expected | 30d ago | 28d ago | 5585 |
| `18.198.200.175` | 8883 | ✅ expected | 7d ago | 6d ago | 2777 |
| `3.120.211.84` | 8883 | ✅ expected | 19d ago | 17d ago | 4832 |
| `3.120.216.195` | 443 | ✅ expected | 27d ago | 18d ago | 800 |
| `3.120.53.2` | 8883 | ✅ expected | 28d ago | 26d ago | 3923 |
| `3.121.10.31` | 8883 | ✅ expected | 26d ago | 26d ago | 759 |
| `3.121.101.237` | 8883 | ✅ expected | 16d ago | 15d ago | 2420 |
| `3.121.111.53` | 443 | ✅ expected | 22d ago | 16d ago | 599 |
| `3.121.169.115` | 8883 | ✅ expected | 26d ago | 24d ago | 4472 |
| `3.122.171.67` | 443 | ✅ expected | 26d ago | 18d ago | 708 |
| `3.122.70.209` | 8883 | ✅ expected | 22d ago | 21d ago | 2815 |
| `3.124.29.182` | 443 | ✅ expected | 31d ago | 22d ago | 810 |
| `3.125.16.42` | 443 | ✅ expected | 18d ago | 16d ago | 239 |
| `3.125.66.145` | 443 | ✅ expected | 31d ago | 26d ago | 491 |
| `3.64.241.12` | 8883 | ✅ expected | 10d ago | 9d ago | 2709 |
| `3.67.142.130` | 443 | ✅ expected | 31d ago | 21d ago | 907 |
| `3.71.130.230` | 443 | ✅ expected | 11d ago | 11d ago | 1 |
| `3.72.199.54` | 443 | ✅ expected | 8d ago | 32s ago | 781 |
| `3.76.164.97` | 443 | ✅ expected | 11d ago | 32s ago | 1018 |
| `35.156.5.143` | 443 | ✅ expected | 21d ago | 18d ago | 254 |
| `35.158.64.12` | 443 | ✅ expected | 21d ago | 14d ago | 693 |
| `52.28.32.0` | 443 | ✅ expected | 16d ago | 11d ago | 500 |
| `52.29.1.243` | 443 | ✅ expected | 16d ago | 8d ago | 702 |
| `52.29.210.73` | 443 | ✅ expected | 31d ago | 21d ago | 926 |
| `52.57.174.242` | 443 | ✅ expected | 31d ago | 27d ago | 429 |
| `52.58.153.107` | 443 | ✅ expected | 22d ago | 16d ago | 542 |
| `52.58.33.43` | 443 | ✅ expected | 16d ago | 11d ago | 507 |
| `52.59.138.18` | 443 | ✅ expected | 11d ago | 11m ago | 1018 |
| `63.181.21.188` | 443 | ✅ expected | 18d ago | 11m ago | 1645 |
| `63.181.74.73` | 443 | ✅ expected | 31d ago | 22d ago | 789 |
| `63.182.123.150` | 443 | ✅ expected | 14d ago | 32s ago | 1225 |
| `63.185.122.149` | 443 | ✅ expected | 11d ago | 11d ago | 1 |
| `91.98.4.78` | 443 | ✅ expected | 11d ago | 11d ago | 1 |

### immich-server

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.21.71.92` | 443 | ✅ expected | 30d ago | 11m ago | 863 |
| `172.67.170.79` | 443 | ✅ expected | 31d ago | 74m ago | 736 |
| `188.114.97.4` | 443 | ✅ expected | 13d ago | 13d ago | 2 |

### jellyfin

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.17.207.5` | 443 | ✅ expected | 31d ago | 25h ago | 16 |
| `104.17.208.5` | 443 | ✅ expected | 30d ago | 116m ago | 41 |
| `139.59.139.28` | 443 | ✅ expected | 28d ago | 116m ago | 22 |
| `140.82.121.3` | 443 | ✅ expected | 26h ago | 26h ago | 1 |
| `146.190.237.6` | 443 | ✅ expected | 26d ago | 26h ago | 24 |
| `151.101.1.229` | 443 | ✅ expected | 26d ago | 3d ago | 12 |
| `151.101.129.229` | 443 | ✅ expected | 25d ago | 5d ago | 13 |
| `151.101.193.229` | 443 | ✅ expected | 29d ago | 7d ago | 13 |
| `151.101.65.229` | 443 | ✅ expected | 15d ago | 2d ago | 8 |
| `157.245.38.19` | 443 | ✅ expected | 27d ago | 5d ago | 19 |
| `161.35.245.42` | 443 | ✅ expected | 25d ago | 4d ago | 15 |
| `165.227.169.147` | 443 | ✅ expected | 31d ago | 15d ago | 32 |
| `165.227.244.161` | 443 | ✅ expected | 30d ago | 116m ago | 38 |
| `178.105.98.131` | 443 | ✅ expected | 31d ago | 5d ago | 25 |
| `185.199.109.133` | 443 | ✅ expected | 26h ago | 26h ago | 2 |
| `206.189.97.173` | 443 | ✅ expected | 24d ago | 25h ago | 48 |
| `68.183.204.194` | 443 | ✅ expected | 31d ago | 46h ago | 18 |

### loki

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `34.96.126.106` | 443 | ✅ expected | 31d ago | 2h ago | 915 |

### navidrome

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.21.43.229` | 443 | ✅ expected | 15d ago | 15d ago | 1 |
| `130.211.19.189` | 443 | ✅ expected | 30d ago | 26d ago | 13 |
| `151.101.237.188` | 443 | ✅ expected | 30d ago | 26d ago | 7 |
| `151.101.238.53` | 443 | ✅ expected | 30d ago | 26d ago | 6 |
| `151.101.238.79` | 443 | ✅ expected | 30d ago | 26d ago | 6 |
| `172.67.186.189` | 443 | ✅ expected | 11d ago | 25h ago | 10 |
| `2.22.225.107` | 443 | ✅ expected | 26d ago | 26d ago | 3 |
| `209.141.42.198` | 443 | ✅ expected | 31d ago | 85m ago | 99 |

### nextcloud

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `65.108.197.113` | 443 | ✅ expected | 28d ago | 26h ago | 18 |
| `65.109.114.179` | 443 | ✅ expected | 30d ago | 31h ago | 29 |
| `65.21.231.50` | 443 | ✅ expected | 22d ago | 12d ago | 3 |
| `95.217.53.153` | 443 | ✅ expected | 29d ago | 19h ago | 28 |

### proton-bridge

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `185.70.42.41` | 443 | ✅ expected | 31d ago | 32s ago | 25006 |
| `185.70.42.45` | 443 | ✅ expected | 31d ago | 2h ago | 826 |

### traefik

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.19.192.29` | 443 | ✅ expected | 27d ago | 27d ago | 5 |
| `104.19.193.29` | 443 | ✅ expected | 29d ago | 29d ago | 6 |
| `104.26.3.101` | 443 | ✅ expected | 29d ago | 11d ago | 24 |
| `140.82.121.5` | 443 | ✅ expected | 29d ago | 13d ago | 13 |
| `140.82.121.6` | 443 | ✅ expected | 31d ago | 14d ago | 11 |
| `172.65.32.248` | 443 | ✅ expected | 29d ago | 27d ago | 25 |
| `172.67.75.8` | 443 | ✅ expected | 15d ago | 26h ago | 13 |

---

*Auto-generated by `scripts/generate-egress-index.sh`. Allow-list: `config/supply-chain/egress-baseline.yaml` (frozen prefixes; re-seed with `scripts/egress-baseline.sh`). Anomaly trail: `data/egress/anomalies.jsonl`. Alerts armed by renaming `config/prometheus/alerts/egress-alerts.yml.disabled` → `.yml` after the baseline window (shadow-first).*
