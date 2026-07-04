# Egress Observatory — Baseline Index (Auto-Generated)

**Generated:** 2026-07-04 13:57:52 UTC
**Implements:** ADR-030 P7 (Tier 4) — egress detection. **Mode:** live (alerting)

Host-side `/proc/<pid>/net/{tcp,tcp6}` sampling of reverse_proxy-tier containers (attributable, rootless, scratch-safe, DNS-method-agnostic). Detection, not prevention. See `config/supply-chain/known-egress.md` for method and residual/evasion scope.

## Pipeline health

| Component | Last run | Detail |
|---|---|---|
| Collector (`egress-collector.service`) | 10s ago | 22 services sampled |
| Classifier (`egress-detect.timer`) | 16s ago | mode=live (alerting); last window 8 dest(s) |

## Per-service egress

| Service | Mode | Public dests | Unexpected | Peers (swarm) |
|---|---|---|---|---|
| alert-discord-relay | classify | 5 | ✅ 0 | — |
| alertmanager | classify | — | — | — |
| audiobookshelf | classify | — | — | — |
| authelia | classify | — | — | — |
| blackbox-exporter | classify | — | — | — |
| crowdsec | classify | 231 | ✅ 0 | — |
| forgejo | classify | — | — | — |
| gathio | classify | 5 | ✅ 0 | — |
| gluetun | classify | — | — | — |
| grafana | classify | 3 | ✅ 0 | — |
| home-assistant | classify | 63 | ✅ 0 | — |
| immich-server | classify | 3 | ✅ 0 | — |
| jellyfin | classify | 17 | ✅ 0 | — |
| loki | classify | 1 | ✅ 0 | — |
| navidrome | classify | 8 | ✅ 0 | — |
| nextcloud | classify | 4 | ✅ 0 | — |
| pihole-exporter | classify | — | — | — |
| prometheus | classify | — | — | — |
| proton-bridge | classify | 2 | ✅ 0 | — |
| qbittorrent | peer-swarm (count-only) | — | — | 239 |
| traefik | classify | 6 | ✅ 0 | — |
| unpoller | classify | — | — | — |
| vaultwarden | peer-swarm (count-only) | — | — | — |

## Zero-egress candidates — blast-radius reduction (REPORT ONLY)

Egress-tier services with **no observed public destination** over the window. Each is a candidate to move to an `Internal=true` network (shrinking the surface Tier 4 watches). **Not an automated change** — manual, per-service review (Feb-2026 21-container outage precedent). A short window will list services that simply hadn't egressed yet (e.g. proton-bridge in `TIME_WAIT`); confirm against a full ≥7-day baseline before acting.

> alertmanager, audiobookshelf, authelia, blackbox-exporter, forgejo, gluetun, pihole-exporter, prometheus, unpoller

## Observed destinations (durable state)

Class legend: **✅ expected** (in allow-list) · **⚠️ active** (unexpected, seen within 24h — counts toward the live metric) · **🔴 sustained** (unexpected and recurring across >=1h — trips the critical alert) · **🕒 retained** (unexpected but last seen >24h ago — kept for forensics until the 30d retention prunes it; NOT in the live metric and NOT alerting).

### alert-discord-relay

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `162.159.128.233` | 443 | ✅ expected | 37d ago | 2h ago | 140 |
| `162.159.135.232` | 443 | ✅ expected | 40d ago | 21h ago | 126 |
| `162.159.136.232` | 443 | ✅ expected | 33d ago | 112m ago | 119 |
| `162.159.137.232` | 443 | ✅ expected | 29d ago | 8h ago | 111 |
| `162.159.138.232` | 443 | ✅ expected | 40d ago | 49m ago | 137 |

### crowdsec

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.20.41.3` | 443 | ✅ expected | 21d ago | 21d ago | 2 |
| `108.128.100.255` | 443 | ✅ expected | 40h ago | 15h ago | 15 |
| `108.128.137.208` | 443 | ✅ expected | 36d ago | 28d ago | 486 |
| `108.128.190.179` | 443 | ✅ expected | 37d ago | 28d ago | 515 |
| `108.129.14.254` | 443 | ✅ expected | 7d ago | 33h ago | 190 |
| `108.131.181.25` | 443 | ✅ expected | 35h ago | 35h ago | 5 |
| `108.131.237.209` | 443 | ✅ expected | 20d ago | 17d ago | 45 |
| `108.132.122.254` | 443 | ✅ expected | 36h ago | 36h ago | 5 |
| `108.132.135.16` | 443 | ✅ expected | 26d ago | 25d ago | 68 |
| `108.132.143.133` | 443 | ✅ expected | 20d ago | 15d ago | 29 |
| `108.132.165.101` | 443 | ✅ expected | 18d ago | 18d ago | 10 |
| `108.132.165.136` | 443 | ✅ expected | 32d ago | 27d ago | 237 |
| `108.132.168.183` | 443 | ✅ expected | 15d ago | 12d ago | 20 |
| `108.132.178.68` | 443 | ✅ expected | 20d ago | 20d ago | 5 |
| `108.132.189.51` | 443 | ✅ expected | 9d ago | 6d ago | 59 |
| `108.132.205.103` | 443 | ✅ expected | 2d ago | 16h ago | 15 |
| `108.132.219.253` | 443 | ✅ expected | 17d ago | 15d ago | 20 |
| `108.132.234.82` | 443 | ✅ expected | 9d ago | 8d ago | 15 |
| `108.132.246.192` | 443 | ✅ expected | 19d ago | 13d ago | 362 |
| `108.132.37.191` | 443 | ✅ expected | 2d ago | 4h ago | 14 |
| `108.132.53.78` | 443 | ✅ expected | 9d ago | 6d ago | 74 |
| `108.132.71.88` | 443 | ✅ expected | 2d ago | 33h ago | 15 |
| `108.132.72.65` | 443 | ✅ expected | 21d ago | 19d ago | 10 |
| `108.132.99.107` | 443 | ✅ expected | 2d ago | 2d ago | 5 |
| `108.133.21.194` | 443 | ✅ expected | 21d ago | 18d ago | 35 |
| `108.133.25.161` | 443 | ✅ expected | 3d ago | 26h ago | 19 |
| `108.133.25.40` | 443 | ✅ expected | 21d ago | 15d ago | 39 |
| `108.133.30.139` | 443 | ✅ expected | 15d ago | 14d ago | 74 |
| `108.133.31.148` | 443 | ✅ expected | 2d ago | 41h ago | 10 |
| `108.133.5.78` | 443 | ✅ expected | 2d ago | 37h ago | 14 |
| `108.133.51.235` | 443 | ✅ expected | 2d ago | 38h ago | 10 |
| `172.66.154.109` | 443 | ✅ expected | 21d ago | 21d ago | 2 |
| `176.34.92.0` | 443 | ✅ expected | 22d ago | 22d ago | 43 |
| `18.200.39.45` | 443 | ✅ expected | 2d ago | 24h ago | 15 |
| `18.200.43.102` | 443 | ✅ expected | 21d ago | 21d ago | 5 |
| `18.202.146.153` | 443 | ✅ expected | 21d ago | 15d ago | 30 |
| `18.202.172.107` | 443 | ✅ expected | 13d ago | 13d ago | 25 |
| `18.203.121.198` | 443 | ✅ expected | 21d ago | 16d ago | 40 |
| `18.203.183.142` | 443 | ✅ expected | 28h ago | 28h ago | 4 |
| `3.248.159.68` | 443 | ✅ expected | 33h ago | 91m ago | 94 |
| `3.248.169.249` | 443 | ✅ expected | 9d ago | 7d ago | 25 |
| `3.250.250.65` | 443 | ✅ expected | 9d ago | 7d ago | 20 |
| `3.253.202.159` | 443 | ✅ expected | 3d ago | 3d ago | 5 |
| `34.240.192.79` | 443 | ✅ expected | 46h ago | 46h ago | 5 |
| `34.240.248.6` | 443 | ✅ expected | 12d ago | 16s ago | 723 |
| `34.240.98.252` | 443 | ✅ expected | 30d ago | 26d ago | 252 |
| `34.241.148.96` | 443 | ✅ expected | 2d ago | 2d ago | 5 |
| `34.241.216.41` | 443 | ✅ expected | 21d ago | 16d ago | 39 |
| `34.241.56.54` | 443 | ✅ expected | 16d ago | 14d ago | 30 |
| `34.242.107.114` | 443 | ✅ expected | 21d ago | 20d ago | 8 |
| `34.242.194.148` | 443 | ✅ expected | 34d ago | 28d ago | 406 |
| `34.243.213.166` | 443 | ✅ expected | 8d ago | 3d ago | 175 |
| `34.246.147.139` | 443 | ✅ expected | 6d ago | 29m ago | 417 |
| `34.246.166.99` | 443 | ✅ expected | 20d ago | 18d ago | 30 |
| `34.246.188.122` | 443 | ✅ expected | 15d ago | 15d ago | 10 |
| `34.247.101.158` | 443 | ✅ expected | 17d ago | 10d ago | 59 |
| `34.247.127.233` | 443 | ✅ expected | 6d ago | 29m ago | 360 |
| `34.247.193.23` | 443 | ✅ expected | 81m ago | 70m ago | 5 |
| `34.248.190.12` | 443 | ✅ expected | 22d ago | 21d ago | 71 |
| `34.249.149.68` | 443 | ✅ expected | 31d ago | 25d ago | 277 |
| `34.249.156.29` | 443 | ✅ expected | 9d ago | 7d ago | 39 |
| `34.249.172.50` | 443 | ✅ expected | 21d ago | 20d ago | 20 |
| `34.249.35.132` | 443 | ✅ expected | 10d ago | 9d ago | 30 |
| `34.249.38.225` | 443 | ✅ expected | 2d ago | 2d ago | 10 |
| `34.250.187.53` | 443 | ✅ expected | 21d ago | 18d ago | 15 |
| `34.250.233.53` | 443 | ✅ expected | 19d ago | 19d ago | 5 |
| `34.250.39.237` | 443 | ✅ expected | 28d ago | 22d ago | 255 |
| `34.251.4.204` | 443 | ✅ expected | 6h ago | 6h ago | 5 |
| `34.251.83.134` | 443 | ✅ expected | 23d ago | 23d ago | 42 |
| `34.251.85.31` | 443 | ✅ expected | 10d ago | 10d ago | 45 |
| `34.252.238.164` | 443 | ✅ expected | 17d ago | 11d ago | 80 |
| `34.252.67.120` | 443 | ✅ expected | 16d ago | 11d ago | 59 |
| `34.252.99.143` | 443 | ✅ expected | 3d ago | 3h ago | 20 |
| `34.253.20.222` | 443 | ✅ expected | 18d ago | 17d ago | 15 |
| `34.253.250.27` | 443 | ✅ expected | 3d ago | 2d ago | 10 |
| `34.254.73.132` | 443 | ✅ expected | 28d ago | 22d ago | 421 |
| `34.255.101.100` | 443 | ✅ expected | 21d ago | 20d ago | 20 |
| `34.255.13.211` | 443 | ✅ expected | 9d ago | 7d ago | 25 |
| `34.255.143.231` | 443 | ✅ expected | 25d ago | 24d ago | 73 |
| `34.255.187.129` | 443 | ✅ expected | 3d ago | 2d ago | 10 |
| `34.255.211.7` | 443 | ✅ expected | 2d ago | 24h ago | 10 |
| `46.137.116.145` | 443 | ✅ expected | 17d ago | 14d ago | 15 |
| `46.137.119.216` | 443 | ✅ expected | 2d ago | 2d ago | 10 |
| `46.137.188.185` | 443 | ✅ expected | 19d ago | 18d ago | 10 |
| `46.137.35.14` | 443 | ✅ expected | 18d ago | 16d ago | 20 |
| `52.16.198.105` | 443 | ✅ expected | 14d ago | 13d ago | 12 |
| `52.16.198.79` | 443 | ✅ expected | 2d ago | 11h ago | 15 |
| `52.16.239.210` | 443 | ✅ expected | 2d ago | 2d ago | 5 |
| `52.16.244.133` | 443 | ✅ expected | 19d ago | 17d ago | 35 |
| `52.16.64.132` | 443 | ✅ expected | 21d ago | 19d ago | 15 |
| `52.17.118.72` | 443 | ✅ expected | 15d ago | 13d ago | 15 |
| `52.17.17.55` | 443 | ✅ expected | 23d ago | 23d ago | 20 |
| `52.17.173.66` | 443 | ✅ expected | 17d ago | 15d ago | 20 |
| `52.17.182.227` | 443 | ✅ expected | 3d ago | 37h ago | 14 |
| `52.17.27.193` | 443 | ✅ expected | 2d ago | 36h ago | 15 |
| `52.17.91.120` | 443 | ✅ expected | 9d ago | 7d ago | 30 |
| `52.18.160.54` | 443 | ✅ expected | 38h ago | 38h ago | 5 |
| `52.18.248.216` | 443 | ✅ expected | 23h ago | 23h ago | 5 |
| `52.18.95.48` | 443 | ✅ expected | 10d ago | 9d ago | 25 |
| `52.19.134.40` | 443 | ✅ expected | 20d ago | 6d ago | 794 |
| `52.19.255.174` | 443 | ✅ expected | 9d ago | 8d ago | 40 |
| `52.19.31.182` | 443 | ✅ expected | 17d ago | 15d ago | 159 |
| `52.19.64.236` | 443 | ✅ expected | 27d ago | 22d ago | 191 |
| `52.19.72.100` | 443 | ✅ expected | 20d ago | 20d ago | 5 |
| `52.19.97.17` | 443 | ✅ expected | 3d ago | 3d ago | 5 |
| `52.208.44.16` | 443 | ✅ expected | 3d ago | 3d ago | 5 |
| `52.208.53.18` | 443 | ✅ expected | 39h ago | 39h ago | 4 |
| `52.209.0.64` | 443 | ✅ expected | 17d ago | 10d ago | 97 |
| `52.209.173.58` | 443 | ✅ expected | 14d ago | 12d ago | 139 |
| `52.210.122.225` | 443 | ✅ expected | 16d ago | 15d ago | 44 |
| `52.210.147.72` | 443 | ✅ expected | 21d ago | 19d ago | 10 |
| `52.210.229.63` | 443 | ✅ expected | 32d ago | 26d ago | 370 |
| `52.211.111.6` | 443 | ✅ expected | 10d ago | 10d ago | 45 |
| `52.211.142.180` | 443 | ✅ expected | 8h ago | 8h ago | 5 |
| `52.211.152.103` | 443 | ✅ expected | 21d ago | 19d ago | 20 |
| `52.211.29.30` | 443 | ✅ expected | 12d ago | 6d ago | 305 |
| `52.211.56.189` | 443 | ✅ expected | 3d ago | 2d ago | 9 |
| `52.212.199.20` | 443 | ✅ expected | 20d ago | 20d ago | 5 |
| `52.212.47.49` | 443 | ✅ expected | 19d ago | 15d ago | 49 |
| `52.212.98.6` | 443 | ✅ expected | 2d ago | 31h ago | 13 |
| `52.213.226.37` | 443 | ✅ expected | 15d ago | 13d ago | 25 |
| `52.213.228.152` | 443 | ✅ expected | 26d ago | 19d ago | 408 |
| `52.213.66.10` | 443 | ✅ expected | 23d ago | 21d ago | 154 |
| `52.214.21.105` | 443 | ✅ expected | 13d ago | 13d ago | 5 |
| `52.214.255.194` | 443 | ✅ expected | 22h ago | 22h ago | 5 |
| `52.214.54.249` | 443 | ✅ expected | 17d ago | 14d ago | 15 |
| `52.215.173.209` | 443 | ✅ expected | 13d ago | 49m ago | 755 |
| `52.30.165.11` | 443 | ✅ expected | 16d ago | 12d ago | 25 |
| `52.30.212.227` | 443 | ✅ expected | 3d ago | 112m ago | 20 |
| `52.30.231.178` | 443 | ✅ expected | 17d ago | 11d ago | 63 |
| `52.30.63.171` | 443 | ✅ expected | 21d ago | 18d ago | 20 |
| `52.31.252.131` | 443 | ✅ expected | 16d ago | 13d ago | 64 |
| `52.31.58.24` | 443 | ✅ expected | 15d ago | 14d ago | 74 |
| `52.31.8.86` | 443 | ✅ expected | 36h ago | 19h ago | 10 |
| `52.48.142.125` | 443 | ✅ expected | 9d ago | 6d ago | 89 |
| `52.48.23.149` | 443 | ✅ expected | 28d ago | 25d ago | 232 |
| `52.48.238.219` | 443 | ✅ expected | 25d ago | 19d ago | 349 |
| `52.48.65.76` | 443 | ✅ expected | 22d ago | 13d ago | 598 |
| `52.48.90.106` | 443 | ✅ expected | 16d ago | 16d ago | 15 |
| `52.48.93.17` | 443 | ✅ expected | 22d ago | 22d ago | 35 |
| `52.49.140.16` | 443 | ✅ expected | 19d ago | 15d ago | 30 |
| `52.49.212.201` | 443 | ✅ expected | 21d ago | 19d ago | 24 |
| `52.49.3.35` | 443 | ✅ expected | 20d ago | 20d ago | 10 |
| `52.49.4.206` | 443 | ✅ expected | 21d ago | 20d ago | 10 |
| `52.50.153.113` | 443 | ✅ expected | 18h ago | 13h ago | 9 |
| `52.50.163.172` | 443 | ✅ expected | 3d ago | 44h ago | 10 |
| `52.50.224.74` | 443 | ✅ expected | 23d ago | 23d ago | 29 |
| `52.51.137.54` | 443 | ✅ expected | 9d ago | 3d ago | 193 |
| `52.51.148.109` | 443 | ✅ expected | 13d ago | 12d ago | 81 |
| `52.51.31.247` | 443 | ✅ expected | 3d ago | 3d ago | 5 |
| `52.51.5.37` | 443 | ✅ expected | 9d ago | 9d ago | 10 |
| `52.51.57.14` | 443 | ✅ expected | 3d ago | 12h ago | 15 |
| `52.84.50.42` | 443 | ✅ expected | 21d ago | 21d ago | 2 |
| `54.154.135.155` | 443 | ✅ expected | 20d ago | 20d ago | 5 |
| `54.154.67.102` | 443 | ✅ expected | 25h ago | 16s ago | 53 |
| `54.155.120.106` | 443 | ✅ expected | 6h ago | 6h ago | 5 |
| `54.155.206.188` | 443 | ✅ expected | 43h ago | 43h ago | 5 |
| `54.155.54.37` | 443 | ✅ expected | 47h ago | 47h ago | 5 |
| `54.170.104.57` | 443 | ✅ expected | 23d ago | 23d ago | 15 |
| `54.170.163.78` | 443 | ✅ expected | 19d ago | 18d ago | 115 |
| `54.171.2.48` | 443 | ✅ expected | 41h ago | 41h ago | 5 |
| `54.171.78.236` | 443 | ✅ expected | 17d ago | 12d ago | 40 |
| `54.194.125.196` | 443 | ✅ expected | 3d ago | 3d ago | 5 |
| `54.194.168.166` | 443 | ✅ expected | 2d ago | 2d ago | 5 |
| `54.194.218.193` | 443 | ✅ expected | 15d ago | 15d ago | 5 |
| `54.194.222.175` | 443 | ✅ expected | 16d ago | 16d ago | 5 |
| `54.194.85.107` | 443 | ✅ expected | 15d ago | 10d ago | 94 |
| `54.195.147.237` | 443 | ✅ expected | 17d ago | 12d ago | 60 |
| `54.195.186.68` | 443 | ✅ expected | 29d ago | 26d ago | 249 |
| `54.195.255.109` | 443 | ✅ expected | 8d ago | 8d ago | 5 |
| `54.195.58.94` | 443 | ✅ expected | 2d ago | 26h ago | 10 |
| `54.216.223.16` | 443 | ✅ expected | 9d ago | 7d ago | 29 |
| `54.216.63.170` | 443 | ✅ expected | 45h ago | 45h ago | 5 |
| `54.220.110.244` | 443 | ✅ expected | 9d ago | 8d ago | 9 |
| `54.220.232.45` | 443 | ✅ expected | 2d ago | 20h ago | 10 |
| `54.220.4.25` | 443 | ✅ expected | 9d ago | 6d ago | 39 |
| `54.228.169.234` | 443 | ✅ expected | 10d ago | 10d ago | 30 |
| `54.228.220.78` | 443 | ✅ expected | 23d ago | 22d ago | 30 |
| `54.228.49.194` | 443 | ✅ expected | 21d ago | 21d ago | 5 |
| `54.228.72.44` | 443 | ✅ expected | 24h ago | 24h ago | 5 |
| `54.229.184.213` | 443 | ✅ expected | 21d ago | 18d ago | 20 |
| `54.229.234.23` | 443 | ✅ expected | 17d ago | 14d ago | 30 |
| `54.246.207.199` | 443 | ✅ expected | 31d ago | 29d ago | 113 |
| `54.247.128.112` | 443 | ✅ expected | 13d ago | 34h ago | 772 |
| `54.72.135.60` | 443 | ✅ expected | 21d ago | 18d ago | 23 |
| `54.72.222.86` | 443 | ✅ expected | 20d ago | 19d ago | 9 |
| `54.72.42.56` | 443 | ✅ expected | 10d ago | 9d ago | 33 |
| `54.72.47.167` | 443 | ✅ expected | 20d ago | 19d ago | 15 |
| `54.73.182.236` | 443 | ✅ expected | 2d ago | 30h ago | 15 |
| `54.73.186.227` | 443 | ✅ expected | 3h ago | 3h ago | 5 |
| `54.73.47.207` | 443 | ✅ expected | 25h ago | 10h ago | 10 |
| `54.73.67.52` | 443 | ✅ expected | 21d ago | 18d ago | 30 |
| `54.74.43.116` | 443 | ✅ expected | 17d ago | 14d ago | 30 |
| `54.75.182.87` | 443 | ✅ expected | 15d ago | 13d ago | 25 |
| `54.75.245.133` | 443 | ✅ expected | 22d ago | 20d ago | 140 |
| `54.75.8.192` | 443 | ✅ expected | 2d ago | 8h ago | 15 |
| `54.75.92.29` | 443 | ✅ expected | 2d ago | 12h ago | 10 |
| `54.76.118.150` | 443 | ✅ expected | 14d ago | 14d ago | 5 |
| `54.76.150.103` | 443 | ✅ expected | 9d ago | 8d ago | 10 |
| `54.76.169.38` | 443 | ✅ expected | 25d ago | 24d ago | 64 |
| `54.76.192.134` | 443 | ✅ expected | 33d ago | 28d ago | 337 |
| `54.76.217.37` | 443 | ✅ expected | 17d ago | 15d ago | 19 |
| `54.76.82.20` | 443 | ✅ expected | 21d ago | 20d ago | 54 |
| `54.77.106.61` | 443 | ✅ expected | 19d ago | 15d ago | 20 |
| `54.77.130.113` | 443 | ✅ expected | 20d ago | 20d ago | 5 |
| `54.77.155.168` | 443 | ✅ expected | 3d ago | 3d ago | 10 |
| `54.77.193.254` | 443 | ✅ expected | 31h ago | 31h ago | 5 |
| `54.77.221.81` | 443 | ✅ expected | 17d ago | 14d ago | 30 |
| `54.77.231.123` | 443 | ✅ expected | 8d ago | 7d ago | 25 |
| `54.77.24.165` | 443 | ✅ expected | 23d ago | 23d ago | 23 |
| `54.78.108.19` | 443 | ✅ expected | 2d ago | 2d ago | 5 |
| `54.78.116.49` | 443 | ✅ expected | 3d ago | 3d ago | 5 |
| `54.78.186.64` | 443 | ✅ expected | 44h ago | 35h ago | 10 |
| `54.78.193.70` | 443 | ✅ expected | 16d ago | 12d ago | 49 |
| `63.32.11.219` | 443 | ✅ expected | 41h ago | 31h ago | 10 |
| `63.32.184.247` | 443 | ✅ expected | 3d ago | 2d ago | 15 |
| `63.32.217.27` | 443 | ✅ expected | 17d ago | 14d ago | 19 |
| `63.33.187.119` | 443 | ✅ expected | 2d ago | 2d ago | 10 |
| `63.33.5.76` | 443 | ✅ expected | 21d ago | 17d ago | 232 |
| `63.34.177.147` | 443 | ✅ expected | 18d ago | 28h ago | 1035 |
| `63.35.170.229` | 443 | ✅ expected | 28d ago | 24d ago | 228 |
| `63.35.34.90` | 443 | ✅ expected | 16d ago | 9d ago | 53 |
| `79.125.93.93` | 443 | ✅ expected | 21d ago | 17d ago | 30 |
| `99.80.124.24` | 443 | ✅ expected | 22d ago | 21d ago | 49 |
| `99.80.153.48` | 443 | ✅ expected | 3d ago | 3d ago | 10 |
| `99.80.232.1` | 443 | ✅ expected | 21d ago | 18d ago | 19 |
| `99.80.39.243` | 443 | ✅ expected | 17d ago | 14d ago | 40 |
| `99.81.112.7` | 443 | ✅ expected | 43h ago | 43h ago | 5 |
| `99.81.12.92` | 443 | ✅ expected | 25d ago | 24d ago | 67 |
| `99.81.142.82` | 443 | ✅ expected | 2d ago | 2d ago | 5 |
| `99.81.28.139` | 443 | ✅ expected | 8d ago | 8d ago | 9 |

### gathio

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.16.1.34` | 443 | ✅ expected | 21d ago | 21d ago | 6 |
| `104.16.11.34` | 443 | ✅ expected | 10d ago | 10d ago | 4 |
| `104.16.4.34` | 443 | ✅ expected | 37d ago | 23d ago | 34 |
| `104.16.7.34` | 443 | ✅ expected | 25d ago | 25d ago | 4 |
| `104.16.8.34` | 443 | ✅ expected | 10d ago | 10d ago | 14 |

### grafana

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `192.0.73.2` | 443 | ✅ expected | 39d ago | 21h ago | 14 |
| `34.120.177.193` | 443 | ✅ expected | 40d ago | 16s ago | 29184 |
| `34.96.126.106` | 443 | ✅ expected | 40d ago | 3h ago | 199 |

### home-assistant

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.26.4.238` | 443 | ✅ expected | 40d ago | 14h ago | 74 |
| `104.26.5.238` | 443 | ✅ expected | 40d ago | 5h ago | 78 |
| `151.101.1.195` | 443 | ✅ expected | 40d ago | 16h ago | 53 |
| `151.101.65.195` | 443 | ✅ expected | 38d ago | 41h ago | 24 |
| `157.249.81.141` | 443 | ✅ expected | 40d ago | 2h ago | 510 |
| `172.67.68.90` | 443 | ✅ expected | 40d ago | 8h ago | 83 |
| `18.156.89.194` | 443 | ✅ expected | 28d ago | 6d ago | 2066 |
| `18.157.213.101` | 8883 | ✅ expected | 19d ago | 18d ago | 2771 |
| `18.158.11.29` | 8883 | ✅ expected | 24d ago | 22d ago | 5654 |
| `18.158.133.191` | 8883 | ✅ expected | 21d ago | 20d ago | 3683 |
| `18.158.136.104` | 8883 | ✅ expected | 22d ago | 21d ago | 1129 |
| `18.158.217.49` | 8883 | ✅ expected | 27d ago | 26d ago | 2668 |
| `18.158.224.141` | 8883 | ✅ expected | 31d ago | 29d ago | 5641 |
| `18.159.150.123` | 8883 | ✅ expected | 2d ago | 36h ago | 2872 |
| `18.159.166.33` | 8883 | ✅ expected | 10d ago | 9d ago | 2774 |
| `18.159.77.159` | 8883 | ✅ expected | 29d ago | 29d ago | 755 |
| `18.184.121.56` | 8883 | ✅ expected | 10d ago | 10d ago | 1224 |
| `18.184.210.149` | 8883 | ✅ expected | 29h ago | 16s ago | 3453 |
| `18.184.241.150` | 8883 | ✅ expected | 27d ago | 27d ago | 58 |
| `18.184.90.143` | 8883 | ✅ expected | 18d ago | 17d ago | 2820 |
| `18.185.10.145` | 8883 | ✅ expected | 14d ago | 10d ago | 9731 |
| `18.185.208.158` | 443 | ✅ expected | 10d ago | 10d ago | 1 |
| `18.185.51.38` | 8883 | ✅ expected | 9d ago | 8d ago | 3631 |
| `18.193.176.220` | 8883 | ✅ expected | 3d ago | 2d ago | 2775 |
| `18.193.19.139` | 8883 | ✅ expected | 22d ago | 22d ago | 1 |
| `18.193.191.4` | 8883 | ✅ expected | 36h ago | 29h ago | 756 |
| `18.194.166.209` | 8883 | ✅ expected | 25d ago | 24d ago | 3094 |
| `18.195.182.246` | 8883 | ✅ expected | 16d ago | 15d ago | 3620 |
| `18.195.53.77` | 8883 | ✅ expected | 22d ago | 22d ago | 760 |
| `18.197.66.183` | 8883 | ✅ expected | 14d ago | 14d ago | 1 |
| `18.198.121.88` | 8883 | ✅ expected | 6d ago | 5d ago | 2734 |
| `18.198.144.131` | 8883 | ✅ expected | 8d ago | 8d ago | 354 |
| `18.198.169.78` | 8883 | ✅ expected | 15d ago | 15d ago | 357 |
| `18.198.177.41` | 8883 | ✅ expected | 15d ago | 14d ago | 1795 |
| `18.198.200.175` | 8883 | ✅ expected | 17d ago | 16d ago | 2777 |
| `3.120.211.84` | 8883 | ✅ expected | 29d ago | 27d ago | 4832 |
| `3.120.216.195` | 443 | ✅ expected | 37d ago | 28d ago | 800 |
| `3.121.101.237` | 8883 | ✅ expected | 26d ago | 25d ago | 2420 |
| `3.121.111.53` | 443 | ✅ expected | 32d ago | 26d ago | 599 |
| `3.122.171.67` | 443 | ✅ expected | 36d ago | 28d ago | 708 |
| `3.125.16.42` | 443 | ✅ expected | 28d ago | 26d ago | 239 |
| `3.64.157.17` | 8883 | ✅ expected | 5d ago | 3d ago | 5594 |
| `3.64.241.12` | 8883 | ✅ expected | 20d ago | 19d ago | 2709 |
| `3.71.130.230` | 443 | ✅ expected | 21d ago | 21d ago | 1 |
| `3.72.199.54` | 443 | ✅ expected | 18d ago | 5d ago | 1156 |
| `3.74.79.125` | 443 | ✅ expected | 6d ago | 7m ago | 591 |
| `3.76.164.97` | 443 | ✅ expected | 21d ago | 29m ago | 1955 |
| `35.156.210.53` | 8883 | ✅ expected | 8d ago | 6d ago | 4480 |
| `35.156.5.143` | 443 | ✅ expected | 31d ago | 28d ago | 254 |
| `35.158.64.12` | 443 | ✅ expected | 31d ago | 23d ago | 693 |
| `51.102.84.196` | 443 | ✅ expected | 22h ago | 16s ago | 76 |
| `52.28.32.0` | 443 | ✅ expected | 26d ago | 21d ago | 500 |
| `52.29.1.243` | 443 | ✅ expected | 25d ago | 18d ago | 702 |
| `52.58.153.107` | 443 | ✅ expected | 32d ago | 26d ago | 542 |
| `52.58.33.43` | 443 | ✅ expected | 26d ago | 21d ago | 507 |
| `52.59.138.18` | 443 | ✅ expected | 21d ago | 8d ago | 1142 |
| `63.181.101.136` | 443 | ✅ expected | 8d ago | 81m ago | 743 |
| `63.181.21.188` | 443 | ✅ expected | 28d ago | 6d ago | 1972 |
| `63.182.123.150` | 443 | ✅ expected | 23d ago | 22h ago | 2053 |
| `63.182.206.75` | 443 | ✅ expected | 5d ago | 16s ago | 535 |
| `63.185.122.149` | 443 | ✅ expected | 21d ago | 21d ago | 1 |
| `63.186.78.77` | 443 | ✅ expected | 6d ago | 16s ago | 562 |
| `91.98.4.78` | 443 | ✅ expected | 21d ago | 21d ago | 1 |

### immich-server

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.21.71.92` | 443 | ✅ expected | 40d ago | 29m ago | 1132 |
| `172.67.170.79` | 443 | ✅ expected | 40d ago | 3h ago | 973 |
| `188.114.97.4` | 443 | ✅ expected | 23d ago | 23d ago | 2 |

### jellyfin

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.17.207.5` | 443 | ✅ expected | 40d ago | 47h ago | 34 |
| `104.17.208.5` | 443 | ✅ expected | 39d ago | 9d ago | 41 |
| `139.59.139.28` | 443 | ✅ expected | 37d ago | 4d ago | 26 |
| `140.82.121.3` | 443 | ✅ expected | 10d ago | 10d ago | 1 |
| `146.190.237.6` | 443 | ✅ expected | 35d ago | 2d ago | 29 |
| `151.101.1.229` | 443 | ✅ expected | 35d ago | 13d ago | 12 |
| `151.101.129.229` | 443 | ✅ expected | 34d ago | 22h ago | 17 |
| `151.101.193.229` | 443 | ✅ expected | 38d ago | 5d ago | 19 |
| `151.101.65.229` | 443 | ✅ expected | 25d ago | 6d ago | 10 |
| `157.245.38.19` | 443 | ✅ expected | 36d ago | 47h ago | 32 |
| `161.35.245.42` | 443 | ✅ expected | 34d ago | 22h ago | 17 |
| `165.227.169.147` | 443 | ✅ expected | 40d ago | 5d ago | 41 |
| `165.227.244.161` | 443 | ✅ expected | 39d ago | 47h ago | 48 |
| `178.105.98.131` | 443 | ✅ expected | 40d ago | 3d ago | 35 |
| `185.199.109.133` | 443 | ✅ expected | 10d ago | 10d ago | 2 |
| `206.189.97.173` | 443 | ✅ expected | 33d ago | 22h ago | 56 |
| `68.183.204.194` | 443 | ✅ expected | 40d ago | 22h ago | 24 |

### loki

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `34.96.126.106` | 443 | ✅ expected | 40d ago | 3h ago | 1206 |

### navidrome

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.21.43.229` | 443 | ✅ expected | 25d ago | 25d ago | 1 |
| `130.211.19.189` | 443 | ✅ expected | 5d ago | 5d ago | 31 |
| `151.101.237.188` | 443 | ✅ expected | 5d ago | 5d ago | 7 |
| `151.101.238.53` | 443 | ✅ expected | 5d ago | 5d ago | 7 |
| `151.101.238.79` | 443 | ✅ expected | 5d ago | 5d ago | 18 |
| `172.67.186.189` | 443 | ✅ expected | 21d ago | 5d ago | 15 |
| `209.141.42.198` | 443 | ✅ expected | 40d ago | 22h ago | 126 |
| `23.0.161.107` | 443 | ✅ expected | 5d ago | 5d ago | 8 |

### nextcloud

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `65.108.197.113` | 443 | ✅ expected | 38d ago | 28h ago | 22 |
| `65.109.114.179` | 443 | ✅ expected | 40d ago | 4h ago | 39 |
| `65.21.231.50` | 443 | ✅ expected | 32d ago | 22d ago | 3 |
| `95.217.53.153` | 443 | ✅ expected | 39d ago | 28h ago | 39 |

### proton-bridge

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `185.70.42.41` | 443 | ✅ expected | 40d ago | 16s ago | 33257 |
| `185.70.42.45` | 443 | ✅ expected | 40d ago | 70m ago | 1076 |

### traefik

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.19.193.29` | 443 | ✅ expected | 3d ago | 3d ago | 10 |
| `104.26.3.101` | 443 | ✅ expected | 39d ago | 21d ago | 24 |
| `140.82.121.5` | 443 | ✅ expected | 39d ago | 23d ago | 13 |
| `140.82.121.6` | 443 | ✅ expected | 40d ago | 24d ago | 11 |
| `172.65.32.248` | 443 | ✅ expected | 3d ago | 3d ago | 17 |
| `172.67.75.8` | 443 | ✅ expected | 25d ago | 10d ago | 13 |

---

*Auto-generated by `scripts/generate-egress-index.sh`. Allow-list: `config/supply-chain/egress-baseline.yaml` (frozen prefixes; re-seed with `scripts/egress-baseline.sh`). Anomaly trail: `data/egress/anomalies.jsonl`. Alerts armed by renaming `config/prometheus/alerts/egress-alerts.yml.disabled` → `.yml` after the baseline window (shadow-first).*
