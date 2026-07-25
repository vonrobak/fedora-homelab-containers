# Egress Observatory — Baseline Index (Auto-Generated)

**Generated:** 2026-07-25 10:13:02 UTC
**Implements:** ADR-030 P7 (Tier 4) — egress detection. **Mode:** live (alerting)

Host-side `/proc/<pid>/net/{tcp,tcp6}` sampling of reverse_proxy-tier containers (attributable, rootless, scratch-safe, DNS-method-agnostic). Detection, not prevention. See `config/supply-chain/known-egress.md` for method and residual/evasion scope.

## Pipeline health

| Component | Last run | Detail |
|---|---|---|
| Collector (`egress-collector.service`) | 26s ago | 15 services sampled |
| Classifier (`egress-detect.timer`) | 9m ago | mode=live (alerting); last window 14 dest(s) |

## Per-service egress

| Service | Mode | Public dests | Unexpected | Peers (swarm) |
|---|---|---|---|---|
| alert-discord-relay | classify | 5 | ✅ 0 | — |
| alertmanager | classify | — | — | — |
| crowdsec | classify | 215 | ✅ 0 | — |
| gathio | classify | 4 | ✅ 0 | — |
| grafana | classify | 4 | ✅ 0 | — |
| home-assistant | classify | 63 | ✅ 0 | — |
| immich-server | classify | 3 | ✅ 0 | — |
| jellyfin | classify | 17 | ✅ 0 | — |
| loki | classify | 2 | ✅ 0 | — |
| navidrome | classify | 8 | ✅ 0 | — |
| nextcloud | classify | 5 | ✅ 0 | — |
| proton-bridge | classify | 2 | ✅ 0 | — |
| qbittorrent | peer-swarm (count-only) | — | — | 144 |
| traefik | classify | 9 | ✅ 0 | — |
| vaultwarden | peer-swarm (count-only) | — | — | — |

## Zero-egress candidates — blast-radius reduction (REPORT ONLY)

Egress-tier services with **no observed public destination** over the window. Each is a candidate to move to an `Internal=true` network (shrinking the surface Tier 4 watches). **Not an automated change** — manual, per-service review (Feb-2026 21-container outage precedent). A short window will list services that simply hadn't egressed yet (e.g. proton-bridge in `TIME_WAIT`); confirm against a full ≥7-day baseline before acting.

> alertmanager

## Observed destinations (durable state)

Class legend: **✅ expected** (in allow-list) · **⚠️ active** (unexpected, seen within 24h — counts toward the live metric) · **🔴 sustained** (unexpected and recurring across >=1h — trips the critical alert) · **🕒 retained** (unexpected but last seen >24h ago — kept for forensics until the 30d retention prunes it; NOT in the live metric and NOT alerting).

### alert-discord-relay

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `162.159.128.233` | 443 | ✅ expected | 58d ago | 9m ago | 200 |
| `162.159.135.232` | 443 | ✅ expected | 61d ago | 3d ago | 204 |
| `162.159.136.232` | 443 | ✅ expected | 54d ago | 5d ago | 161 |
| `162.159.137.232` | 443 | ✅ expected | 50d ago | 5d ago | 152 |
| `162.159.138.232` | 443 | ✅ expected | 60d ago | 9m ago | 209 |

### crowdsec

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `108.128.100.255` | 443 | ✅ expected | 22d ago | 20d ago | 20 |
| `108.128.5.151` | 443 | ✅ expected | 19d ago | 17d ago | 11 |
| `108.128.75.34` | 443 | ✅ expected | 20d ago | 20d ago | 5 |
| `108.129.14.254` | 443 | ✅ expected | 28d ago | 22d ago | 190 |
| `108.131.181.25` | 443 | ✅ expected | 22d ago | 18d ago | 10 |
| `108.132.121.20` | 443 | ✅ expected | 19d ago | 18d ago | 10 |
| `108.132.122.254` | 443 | ✅ expected | 22d ago | 17d ago | 25 |
| `108.132.137.184` | 443 | ✅ expected | 20d ago | 20d ago | 10 |
| `108.132.165.84` | 443 | ✅ expected | 19d ago | 19d ago | 5 |
| `108.132.183.8` | 443 | ✅ expected | 17d ago | 17d ago | 5 |
| `108.132.189.51` | 443 | ✅ expected | 30d ago | 27d ago | 59 |
| `108.132.205.103` | 443 | ✅ expected | 22d ago | 16d ago | 30 |
| `108.132.205.140` | 443 | ✅ expected | 11d ago | 11d ago | 53 |
| `108.132.213.83` | 443 | ✅ expected | 13d ago | 13d ago | 20 |
| `108.132.221.3` | 443 | ✅ expected | 17d ago | 13d ago | 15 |
| `108.132.234.82` | 443 | ✅ expected | 30d ago | 29d ago | 15 |
| `108.132.37.191` | 443 | ✅ expected | 23d ago | 21d ago | 14 |
| `108.132.53.78` | 443 | ✅ expected | 30d ago | 27d ago | 74 |
| `108.132.71.88` | 443 | ✅ expected | 23d ago | 22d ago | 15 |
| `108.132.92.167` | 443 | ✅ expected | 14d ago | 14d ago | 10 |
| `108.132.99.107` | 443 | ✅ expected | 23d ago | 23d ago | 5 |
| `108.133.112.227` | 443 | ✅ expected | 7d ago | 6d ago | 52 |
| `108.133.21.137` | 443 | ✅ expected | 18d ago | 16d ago | 115 |
| `108.133.25.161` | 443 | ✅ expected | 24d ago | 21d ago | 19 |
| `108.133.29.186` | 443 | ✅ expected | 19d ago | 17d ago | 20 |
| `108.133.3.16` | 443 | ✅ expected | 19d ago | 19d ago | 5 |
| `108.133.31.148` | 443 | ✅ expected | 23d ago | 16d ago | 30 |
| `108.133.5.78` | 443 | ✅ expected | 23d ago | 20d ago | 19 |
| `108.133.51.235` | 443 | ✅ expected | 23d ago | 22d ago | 10 |
| `108.133.79.98` | 443 | ✅ expected | 7d ago | 6d ago | 55 |
| `176.34.181.119` | 443 | ✅ expected | 16d ago | 16d ago | 5 |
| `176.34.198.243` | 443 | ✅ expected | 6d ago | 8h ago | 373 |
| `18.200.110.20` | 443 | ✅ expected | 8d ago | 8d ago | 68 |
| `18.200.123.226` | 443 | ✅ expected | 19d ago | 12d ago | 485 |
| `18.200.39.45` | 443 | ✅ expected | 23d ago | 21d ago | 15 |
| `18.202.164.218` | 443 | ✅ expected | 18d ago | 11d ago | 478 |
| `18.202.182.46` | 443 | ✅ expected | 20d ago | 20d ago | 5 |
| `18.202.70.248` | 443 | ✅ expected | 16d ago | 14d ago | 25 |
| `18.203.183.142` | 443 | ✅ expected | 22d ago | 22d ago | 4 |
| `3.248.159.68` | 443 | ✅ expected | 22d ago | 13d ago | 539 |
| `3.248.169.249` | 443 | ✅ expected | 30d ago | 28d ago | 25 |
| `3.250.250.65` | 443 | ✅ expected | 30d ago | 28d ago | 20 |
| `3.251.31.92` | 443 | ✅ expected | 7d ago | 7d ago | 55 |
| `3.253.202.159` | 443 | ✅ expected | 23d ago | 20d ago | 10 |
| `34.240.192.79` | 443 | ✅ expected | 22d ago | 22d ago | 5 |
| `34.240.248.6` | 443 | ✅ expected | 33d ago | 19d ago | 772 |
| `34.240.99.65` | 443 | ✅ expected | 13d ago | 10d ago | 64 |
| `34.241.148.96` | 443 | ✅ expected | 23d ago | 23d ago | 5 |
| `34.241.218.127` | 443 | ✅ expected | 15d ago | 11d ago | 45 |
| `34.241.33.70` | 443 | ✅ expected | 8d ago | 7d ago | 70 |
| `34.241.45.245` | 443 | ✅ expected | 14d ago | 14d ago | 5 |
| `34.242.110.163` | 443 | ✅ expected | 16d ago | 14d ago | 15 |
| `34.242.13.27` | 443 | ✅ expected | 17d ago | 11d ago | 37 |
| `34.243.209.239` | 443 | ✅ expected | 20d ago | 18d ago | 25 |
| `34.243.213.166` | 443 | ✅ expected | 29d ago | 24d ago | 175 |
| `34.246.147.139` | 443 | ✅ expected | 26d ago | 18d ago | 556 |
| `34.246.232.161` | 443 | ✅ expected | 15d ago | 13d ago | 15 |
| `34.246.54.177` | 443 | ✅ expected | 16d ago | 13d ago | 163 |
| `34.247.127.233` | 443 | ✅ expected | 27d ago | 20d ago | 370 |
| `34.247.193.23` | 443 | ✅ expected | 20d ago | 20d ago | 10 |
| `34.248.135.223` | 443 | ✅ expected | 20d ago | 20d ago | 5 |
| `34.248.252.15` | 443 | ✅ expected | 19d ago | 16d ago | 224 |
| `34.249.156.29` | 443 | ✅ expected | 30d ago | 27d ago | 39 |
| `34.249.175.76` | 443 | ✅ expected | 19d ago | 18d ago | 20 |
| `34.249.180.157` | 443 | ✅ expected | 4d ago | 7h ago | 207 |
| `34.249.38.225` | 443 | ✅ expected | 23d ago | 22d ago | 10 |
| `34.249.74.158` | 443 | ✅ expected | 15d ago | 12d ago | 25 |
| `34.250.219.167` | 443 | ✅ expected | 11d ago | 37h ago | 612 |
| `34.250.246.103` | 443 | ✅ expected | 16d ago | 15d ago | 10 |
| `34.250.94.23` | 443 | ✅ expected | 13d ago | 4d ago | 585 |
| `34.251.4.204` | 443 | ✅ expected | 21d ago | 21d ago | 5 |
| `34.251.48.106` | 443 | ✅ expected | 16d ago | 8d ago | 471 |
| `34.252.105.132` | 443 | ✅ expected | 16d ago | 15d ago | 10 |
| `34.252.249.34` | 443 | ✅ expected | 14d ago | 10d ago | 57 |
| `34.252.99.143` | 443 | ✅ expected | 23d ago | 21d ago | 20 |
| `34.253.250.27` | 443 | ✅ expected | 24d ago | 23d ago | 10 |
| `34.253.80.226` | 443 | ✅ expected | 17d ago | 10d ago | 33 |
| `34.253.95.189` | 443 | ✅ expected | 19d ago | 18d ago | 25 |
| `34.254.128.0` | 443 | ✅ expected | 15d ago | 15d ago | 5 |
| `34.254.31.214` | 443 | ✅ expected | 15d ago | 15d ago | 10 |
| `34.254.5.251` | 443 | ✅ expected | 16d ago | 16d ago | 5 |
| `34.255.101.228` | 443 | ✅ expected | 16d ago | 15d ago | 10 |
| `34.255.13.211` | 443 | ✅ expected | 30d ago | 28d ago | 25 |
| `34.255.171.152` | 443 | ✅ expected | 8d ago | 20m ago | 474 |
| `34.255.187.129` | 443 | ✅ expected | 24d ago | 23d ago | 10 |
| `34.255.211.7` | 443 | ✅ expected | 23d ago | 17d ago | 19 |
| `34.255.33.254` | 443 | ✅ expected | 16d ago | 13d ago | 8 |
| `46.137.119.216` | 443 | ✅ expected | 23d ago | 18d ago | 35 |
| `46.137.166.0` | 443 | ✅ expected | 20d ago | 20d ago | 5 |
| `52.16.143.245` | 443 | ✅ expected | 15d ago | 13d ago | 15 |
| `52.16.181.166` | 443 | ✅ expected | 17d ago | 12d ago | 15 |
| `52.16.198.79` | 443 | ✅ expected | 23d ago | 20d ago | 20 |
| `52.16.239.210` | 443 | ✅ expected | 23d ago | 23d ago | 5 |
| `52.16.97.104` | 443 | ✅ expected | 14d ago | 14d ago | 5 |
| `52.17.182.227` | 443 | ✅ expected | 24d ago | 22d ago | 14 |
| `52.17.27.193` | 443 | ✅ expected | 23d ago | 19d ago | 25 |
| `52.17.91.120` | 443 | ✅ expected | 30d ago | 28d ago | 30 |
| `52.18.160.54` | 443 | ✅ expected | 22d ago | 17d ago | 30 |
| `52.18.248.216` | 443 | ✅ expected | 21d ago | 21d ago | 5 |
| `52.18.50.168` | 443 | ✅ expected | 15d ago | 13d ago | 20 |
| `52.19.134.40` | 443 | ✅ expected | 41d ago | 27d ago | 794 |
| `52.19.210.92` | 443 | ✅ expected | 16d ago | 14d ago | 20 |
| `52.19.255.174` | 443 | ✅ expected | 30d ago | 29d ago | 40 |
| `52.19.97.17` | 443 | ✅ expected | 24d ago | 20d ago | 10 |
| `52.208.44.16` | 443 | ✅ expected | 24d ago | 24d ago | 5 |
| `52.208.53.18` | 443 | ✅ expected | 22d ago | 18d ago | 14 |
| `52.209.111.217` | 443 | ✅ expected | 14d ago | 14d ago | 5 |
| `52.209.205.217` | 443 | ✅ expected | 11d ago | 8d ago | 73 |
| `52.211.142.180` | 443 | ✅ expected | 21d ago | 21d ago | 5 |
| `52.211.195.171` | 443 | ✅ expected | 18d ago | 9d ago | 582 |
| `52.211.29.30` | 443 | ✅ expected | 33d ago | 27d ago | 305 |
| `52.211.36.162` | 443 | ✅ expected | 6d ago | 3h ago | 341 |
| `52.211.56.189` | 443 | ✅ expected | 24d ago | 23d ago | 9 |
| `52.212.105.63` | 443 | ✅ expected | 4d ago | 3h ago | 193 |
| `52.212.98.6` | 443 | ✅ expected | 23d ago | 19d ago | 18 |
| `52.214.255.194` | 443 | ✅ expected | 21d ago | 18d ago | 15 |
| `52.215.162.174` | 443 | ✅ expected | 14d ago | 14d ago | 5 |
| `52.215.173.209` | 443 | ✅ expected | 33d ago | 20d ago | 809 |
| `52.215.19.191` | 443 | ✅ expected | 16d ago | 14d ago | 15 |
| `52.215.215.102` | 443 | ✅ expected | 16d ago | 12d ago | 35 |
| `52.30.169.249` | 443 | ✅ expected | 13d ago | 11d ago | 10 |
| `52.30.176.43` | 443 | ✅ expected | 15d ago | 11d ago | 31 |
| `52.30.212.227` | 443 | ✅ expected | 24d ago | 20d ago | 20 |
| `52.31.121.137` | 443 | ✅ expected | 17d ago | 13d ago | 10 |
| `52.31.76.36` | 443 | ✅ expected | 17d ago | 17d ago | 5 |
| `52.31.8.86` | 443 | ✅ expected | 22d ago | 20d ago | 15 |
| `52.48.115.130` | 443 | ✅ expected | 20d ago | 18d ago | 126 |
| `52.48.142.125` | 443 | ✅ expected | 29d ago | 27d ago | 89 |
| `52.49.1.39` | 443 | ✅ expected | 17d ago | 13d ago | 20 |
| `52.49.67.224` | 443 | ✅ expected | 14d ago | 14d ago | 5 |
| `52.50.153.113` | 443 | ✅ expected | 21d ago | 17d ago | 29 |
| `52.50.163.172` | 443 | ✅ expected | 24d ago | 22d ago | 10 |
| `52.50.177.36` | 443 | ✅ expected | 15d ago | 14d ago | 10 |
| `52.51.137.54` | 443 | ✅ expected | 30d ago | 24d ago | 193 |
| `52.51.193.26` | 443 | ✅ expected | 14d ago | 9d ago | 134 |
| `52.51.224.28` | 443 | ✅ expected | 15d ago | 11d ago | 24 |
| `52.51.30.23` | 443 | ✅ expected | 12d ago | 12d ago | 5 |
| `52.51.31.247` | 443 | ✅ expected | 23d ago | 23d ago | 5 |
| `52.51.57.14` | 443 | ✅ expected | 24d ago | 21d ago | 15 |
| `52.51.66.237` | 443 | ✅ expected | 6d ago | 52m ago | 295 |
| `54.154.137.37` | 443 | ✅ expected | 13d ago | 12d ago | 9 |
| `54.154.143.162` | 443 | ✅ expected | 17d ago | 13d ago | 25 |
| `54.154.207.37` | 443 | ✅ expected | 41h ago | 6h ago | 94 |
| `54.154.67.102` | 443 | ✅ expected | 21d ago | 19d ago | 135 |
| `54.154.68.208` | 443 | ✅ expected | 13d ago | 12d ago | 10 |
| `54.155.120.106` | 443 | ✅ expected | 21d ago | 18d ago | 15 |
| `54.155.184.143` | 443 | ✅ expected | 14d ago | 14d ago | 5 |
| `54.155.206.188` | 443 | ✅ expected | 22d ago | 22d ago | 5 |
| `54.155.54.37` | 443 | ✅ expected | 22d ago | 19d ago | 15 |
| `54.170.92.13` | 443 | ✅ expected | 34h ago | 31m ago | 78 |
| `54.171.2.48` | 443 | ✅ expected | 22d ago | 22d ago | 5 |
| `54.171.238.201` | 443 | ✅ expected | 15d ago | 13d ago | 23 |
| `54.171.33.36` | 443 | ✅ expected | 11d ago | 9d ago | 117 |
| `54.194.125.196` | 443 | ✅ expected | 24d ago | 24d ago | 5 |
| `54.194.161.226` | 443 | ✅ expected | 17d ago | 14d ago | 20 |
| `54.194.168.166` | 443 | ✅ expected | 22d ago | 19d ago | 20 |
| `54.195.255.109` | 443 | ✅ expected | 29d ago | 29d ago | 5 |
| `54.195.58.94` | 443 | ✅ expected | 23d ago | 21d ago | 10 |
| `54.216.174.169` | 443 | ✅ expected | 11d ago | 2d ago | 507 |
| `54.216.223.16` | 443 | ✅ expected | 30d ago | 28d ago | 29 |
| `54.216.63.170` | 443 | ✅ expected | 22d ago | 22d ago | 5 |
| `54.217.73.238` | 443 | ✅ expected | 16d ago | 16d ago | 5 |
| `54.220.106.227` | 443 | ✅ expected | 15d ago | 12d ago | 25 |
| `54.220.110.244` | 443 | ✅ expected | 29d ago | 29d ago | 9 |
| `54.220.129.146` | 443 | ✅ expected | 15d ago | 14d ago | 15 |
| `54.220.232.45` | 443 | ✅ expected | 23d ago | 18d ago | 50 |
| `54.220.4.25` | 443 | ✅ expected | 30d ago | 27d ago | 39 |
| `54.228.72.44` | 443 | ✅ expected | 21d ago | 20d ago | 10 |
| `54.246.87.25` | 443 | ✅ expected | 16d ago | 16d ago | 5 |
| `54.247.128.112` | 443 | ✅ expected | 34d ago | 22d ago | 772 |
| `54.247.91.245` | 443 | ✅ expected | 19d ago | 19d ago | 5 |
| `54.72.105.85` | 443 | ✅ expected | 20d ago | 18d ago | 23 |
| `54.73.182.236` | 443 | ✅ expected | 23d ago | 22d ago | 15 |
| `54.73.186.227` | 443 | ✅ expected | 20d ago | 20d ago | 5 |
| `54.73.47.207` | 443 | ✅ expected | 21d ago | 21d ago | 10 |
| `54.73.72.206` | 443 | ✅ expected | 16d ago | 10d ago | 53 |
| `54.75.140.194` | 443 | ✅ expected | 15d ago | 13d ago | 10 |
| `54.75.8.192` | 443 | ✅ expected | 22d ago | 19d ago | 24 |
| `54.75.92.29` | 443 | ✅ expected | 22d ago | 19d ago | 20 |
| `54.76.150.103` | 443 | ✅ expected | 29d ago | 29d ago | 10 |
| `54.76.164.80` | 443 | ✅ expected | 17d ago | 14d ago | 15 |
| `54.76.23.94` | 443 | ✅ expected | 17d ago | 14d ago | 15 |
| `54.77.155.168` | 443 | ✅ expected | 24d ago | 19d ago | 20 |
| `54.77.193.254` | 443 | ✅ expected | 22d ago | 18d ago | 20 |
| `54.77.231.123` | 443 | ✅ expected | 29d ago | 28d ago | 25 |
| `54.77.236.172` | 443 | ✅ expected | 9d ago | 5h ago | 568 |
| `54.77.253.10` | 443 | ✅ expected | 20d ago | 20d ago | 10 |
| `54.77.6.216` | 443 | ✅ expected | 18d ago | 18d ago | 5 |
| `54.78.108.19` | 443 | ✅ expected | 23d ago | 23d ago | 5 |
| `54.78.116.49` | 443 | ✅ expected | 24d ago | 19d ago | 10 |
| `54.78.124.255` | 443 | ✅ expected | 16d ago | 12d ago | 19 |
| `54.78.137.34` | 443 | ✅ expected | 16d ago | 12d ago | 33 |
| `54.78.186.64` | 443 | ✅ expected | 22d ago | 19d ago | 25 |
| `54.78.26.191` | 443 | ✅ expected | 15d ago | 15d ago | 5 |
| `63.32.11.219` | 443 | ✅ expected | 22d ago | 20d ago | 15 |
| `63.32.184.247` | 443 | ✅ expected | 24d ago | 17d ago | 44 |
| `63.32.213.125` | 443 | ✅ expected | 17d ago | 17d ago | 5 |
| `63.33.187.119` | 443 | ✅ expected | 23d ago | 23d ago | 10 |
| `63.33.229.19` | 443 | ✅ expected | 16d ago | 14d ago | 15 |
| `63.34.17.221` | 443 | ✅ expected | 17d ago | 15d ago | 15 |
| `63.34.177.147` | 443 | ✅ expected | 39d ago | 22d ago | 1035 |
| `63.34.189.230` | 443 | ✅ expected | 13d ago | 10d ago | 53 |
| `63.34.43.204` | 443 | ✅ expected | 15d ago | 15d ago | 10 |
| `63.34.48.116` | 443 | ✅ expected | 13d ago | 4d ago | 492 |
| `63.34.64.15` | 443 | ✅ expected | 8d ago | 7d ago | 64 |
| `63.34.86.48` | 443 | ✅ expected | 16d ago | 16d ago | 5 |
| `63.35.47.18` | 443 | ✅ expected | 16d ago | 16d ago | 5 |
| `63.35.7.115` | 443 | ✅ expected | 20d ago | 20d ago | 5 |
| `99.80.153.48` | 443 | ✅ expected | 23d ago | 23d ago | 10 |
| `99.80.188.173` | 443 | ✅ expected | 17d ago | 14d ago | 15 |
| `99.81.112.7` | 443 | ✅ expected | 22d ago | 22d ago | 5 |
| `99.81.142.82` | 443 | ✅ expected | 23d ago | 23d ago | 5 |
| `99.81.28.139` | 443 | ✅ expected | 29d ago | 29d ago | 9 |
| `99.81.76.162` | 443 | ✅ expected | 15d ago | 14d ago | 10 |
| `99.81.77.108` | 443 | ✅ expected | 14d ago | 14d ago | 9 |

### gathio

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.16.3.34` | 443 | ✅ expected | 9m ago | 9m ago | 8 |
| `104.16.4.34` | 443 | ✅ expected | 52m ago | 9m ago | 14 |
| `104.16.7.34` | 443 | ✅ expected | 11d ago | 11d ago | 16 |
| `104.16.9.34` | 443 | ✅ expected | 11d ago | 11d ago | 4 |

### grafana

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `34.49.170.206` | 443 | 🕒 retained | 15d ago | 12d ago | 20 |
| `192.0.73.2` | 443 | ✅ expected | 60d ago | 33h ago | 42 |
| `34.120.177.193` | 443 | ✅ expected | 61d ago | 20m ago | 35703 |
| `34.96.126.106` | 443 | ✅ expected | 61d ago | 15d ago | 224 |

### home-assistant

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.26.4.238` | 443 | ✅ expected | 61d ago | 7h ago | 106 |
| `104.26.5.238` | 443 | ✅ expected | 61d ago | 4h ago | 116 |
| `151.101.1.195` | 443 | ✅ expected | 61d ago | 37h ago | 78 |
| `151.101.65.195` | 443 | ✅ expected | 59d ago | 12h ago | 41 |
| `157.249.81.141` | 443 | ✅ expected | 61d ago | 2h ago | 802 |
| `172.67.68.90` | 443 | ✅ expected | 61d ago | 83m ago | 126 |
| `18.156.61.178` | 443 | ✅ expected | 12d ago | 3d ago | 1078 |
| `18.156.89.194` | 443 | ✅ expected | 49d ago | 27d ago | 2066 |
| `18.157.239.155` | 8883 | ✅ expected | 14d ago | 13d ago | 2789 |
| `18.158.101.185` | 8883 | ✅ expected | 22h ago | 8h ago | 1701 |
| `18.158.114.127` | 8883 | ✅ expected | 13d ago | 12d ago | 3088 |
| `18.158.226.141` | 443 | ✅ expected | 18d ago | 13d ago | 381 |
| `18.159.150.123` | 8883 | ✅ expected | 23d ago | 22d ago | 2872 |
| `18.159.3.91` | 8883 | ✅ expected | 2d ago | 25h ago | 3667 |
| `18.159.63.103` | 8883 | ✅ expected | 19d ago | 19d ago | 711 |
| `18.184.176.116` | 443 | ✅ expected | 8d ago | 9m ago | 791 |
| `18.184.210.149` | 8883 | ✅ expected | 22d ago | 20d ago | 4827 |
| `18.185.51.38` | 8883 | ✅ expected | 30d ago | 29d ago | 3631 |
| `18.192.191.83` | 8883 | ✅ expected | 16d ago | 15d ago | 3626 |
| `18.193.136.178` | 443 | ✅ expected | 4d ago | 62m ago | 399 |
| `18.193.176.220` | 8883 | ✅ expected | 24d ago | 23d ago | 2775 |
| `18.193.191.4` | 8883 | ✅ expected | 22d ago | 22d ago | 756 |
| `18.194.113.144` | 8883 | ✅ expected | 18d ago | 17d ago | 2818 |
| `18.194.246.231` | 8883 | ✅ expected | 11d ago | 11d ago | 126 |
| `18.195.195.66` | 443 | ✅ expected | 13d ago | 4d ago | 1082 |
| `18.195.224.30` | 8883 | ✅ expected | 25h ago | 22h ago | 359 |
| `18.196.186.252` | 8883 | ✅ expected | 12d ago | 10d ago | 3162 |
| `18.196.210.199` | 8883 | ✅ expected | 3d ago | 2d ago | 2802 |
| `18.197.183.115` | 8883 | ✅ expected | 11d ago | 8d ago | 2310 |
| `18.197.40.225` | 8883 | ✅ expected | 8d ago | 6d ago | 4877 |
| `18.197.42.5` | 8883 | ✅ expected | 12d ago | 12d ago | 354 |
| `18.198.121.88` | 8883 | ✅ expected | 27d ago | 26d ago | 2734 |
| `18.198.144.131` | 8883 | ✅ expected | 29d ago | 19d ago | 3089 |
| `3.120.114.20` | 8883 | ✅ expected | 19d ago | 14d ago | 2838 |
| `3.121.91.88` | 8883 | ✅ expected | 17d ago | 16d ago | 2774 |
| `3.124.149.207` | 8883 | ✅ expected | 8h ago | 31m ago | 911 |
| `3.64.157.17` | 8883 | ✅ expected | 26d ago | 24d ago | 5594 |
| `3.64.27.40` | 443 | ✅ expected | 16h ago | 20m ago | 59 |
| `3.65.85.145` | 8883 | ✅ expected | 10d ago | 8d ago | 5650 |
| `3.67.131.85` | 443 | ✅ expected | 3d ago | 9m ago | 311 |
| `3.68.50.95` | 8883 | ✅ expected | 5d ago | 3d ago | 5640 |
| `3.70.88.116` | 443 | ✅ expected | 18d ago | 7d ago | 1255 |
| `3.72.199.54` | 443 | ✅ expected | 39d ago | 26d ago | 1156 |
| `3.74.79.125` | 443 | ✅ expected | 27d ago | 16d ago | 999 |
| `3.76.164.97` | 443 | ✅ expected | 42d ago | 19d ago | 2060 |
| `3.78.82.168` | 443 | ✅ expected | 9d ago | 17h ago | 871 |
| `35.156.210.53` | 8883 | ✅ expected | 28d ago | 27d ago | 4480 |
| `35.156.86.141` | 8883 | ✅ expected | 6d ago | 5d ago | 2754 |
| `35.157.55.145` | 8883 | ✅ expected | 31m ago | 9m ago | 47 |
| `51.102.121.58` | 443 | ✅ expected | 7d ago | 62m ago | 757 |
| `51.102.149.208` | 443 | ✅ expected | 16d ago | 12d ago | 417 |
| `51.102.84.196` | 443 | ✅ expected | 21d ago | 9d ago | 1258 |
| `52.58.62.182` | 443 | ✅ expected | 16d ago | 13d ago | 312 |
| `52.59.138.18` | 443 | ✅ expected | 42d ago | 29d ago | 1142 |
| `63.180.118.226` | 443 | ✅ expected | 4d ago | 41m ago | 462 |
| `63.181.101.136` | 443 | ✅ expected | 29d ago | 18d ago | 985 |
| `63.181.154.124` | 443 | ✅ expected | 31m ago | 31m ago | 1 |
| `63.181.21.188` | 443 | ✅ expected | 49d ago | 27d ago | 1972 |
| `63.182.123.150` | 443 | ✅ expected | 44d ago | 21d ago | 2053 |
| `63.182.206.75` | 443 | ✅ expected | 26d ago | 18d ago | 828 |
| `63.186.5.221` | 443 | ✅ expected | 13d ago | 4d ago | 1076 |
| `63.186.71.169` | 443 | ✅ expected | 19d ago | 8d ago | 1205 |
| `63.186.78.77` | 443 | ✅ expected | 27d ago | 16d ago | 978 |

### immich-server

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `188.114.96.1` | 443 | 🕒 retained | 2d ago | 2d ago | 2 |
| `104.21.71.92` | 443 | ✅ expected | 61d ago | 31m ago | 1644 |
| `172.67.170.79` | 443 | ✅ expected | 61d ago | 9m ago | 1523 |

### jellyfin

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.17.207.5` | 443 | ✅ expected | 61d ago | 46h ago | 52 |
| `104.17.208.5` | 443 | ✅ expected | 60d ago | 22h ago | 93 |
| `139.59.139.28` | 443 | ✅ expected | 58d ago | 10d ago | 45 |
| `140.82.121.3` | 443 | ✅ expected | 31d ago | 19d ago | 2 |
| `146.190.237.6` | 443 | ✅ expected | 56d ago | 22h ago | 51 |
| `151.101.1.229` | 443 | ✅ expected | 56d ago | 6d ago | 14 |
| `151.101.129.229` | 443 | ✅ expected | 55d ago | 7d ago | 24 |
| `151.101.193.229` | 443 | ✅ expected | 59d ago | 8d ago | 22 |
| `151.101.65.229` | 443 | ✅ expected | 46d ago | 27d ago | 10 |
| `157.245.38.19` | 443 | ✅ expected | 57d ago | 46h ago | 49 |
| `161.35.245.42` | 443 | ✅ expected | 55d ago | 22h ago | 44 |
| `165.227.169.147` | 443 | ✅ expected | 61d ago | 5d ago | 67 |
| `165.227.244.161` | 443 | ✅ expected | 60d ago | 46h ago | 62 |
| `178.105.98.131` | 443 | ✅ expected | 61d ago | 2d ago | 45 |
| `185.199.109.133` | 443 | ✅ expected | 31d ago | 19d ago | 4 |
| `206.189.97.173` | 443 | ✅ expected | 54d ago | 6d ago | 64 |
| `68.183.204.194` | 443 | ✅ expected | 61d ago | 46h ago | 34 |

### loki

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `34.49.170.206` | 443 | ✅ expected | 15d ago | 3h ago | 433 |
| `34.96.126.106` | 443 | ✅ expected | 61d ago | 9d ago | 1389 |

### navidrome

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.21.43.229` | 443 | ✅ expected | 11d ago | 41m ago | 10 |
| `130.211.19.189` | 443 | ✅ expected | 26d ago | 26d ago | 31 |
| `151.101.237.188` | 443 | ✅ expected | 26d ago | 26d ago | 7 |
| `151.101.238.53` | 443 | ✅ expected | 26d ago | 26d ago | 7 |
| `151.101.238.79` | 443 | ✅ expected | 26d ago | 26d ago | 18 |
| `172.67.186.189` | 443 | ✅ expected | 42d ago | 11d ago | 35 |
| `209.141.42.198` | 443 | ✅ expected | 61d ago | 9m ago | 188 |
| `23.0.161.107` | 443 | ✅ expected | 26d ago | 26d ago | 8 |

### nextcloud

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `5.9.202.145` | 443 | 🕒 retained | 8d ago | 8d ago | 1 |
| `65.108.197.113` | 443 | ✅ expected | 59d ago | 31m ago | 44 |
| `65.109.114.179` | 443 | ✅ expected | 61d ago | 14h ago | 58 |
| `65.21.231.50` | 443 | ✅ expected | 12d ago | 31m ago | 10 |
| `95.217.53.153` | 443 | ✅ expected | 60d ago | 9m ago | 68 |

### proton-bridge

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `185.70.42.41` | 443 | ✅ expected | 61d ago | 9m ago | 50900 |
| `185.70.42.45` | 443 | ✅ expected | 61d ago | 94m ago | 1581 |

### traefik

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.19.192.174` | 443 | ✅ expected | 17d ago | 17d ago | 5 |
| `104.19.192.175` | 443 | ✅ expected | 3d ago | 3d ago | 5 |
| `104.19.192.176` | 443 | ✅ expected | 15d ago | 15d ago | 6 |
| `104.19.192.177` | 443 | ✅ expected | 19d ago | 12d ago | 18 |
| `104.19.192.29` | 443 | ✅ expected | 9d ago | 9m ago | 12 |
| `104.19.193.29` | 443 | ✅ expected | 24d ago | 24d ago | 10 |
| `104.26.2.101` | 443 | ✅ expected | 7d ago | 7d ago | 15 |
| `172.65.32.248` | 443 | ✅ expected | 24d ago | 9m ago | 105 |
| `172.67.75.8` | 443 | ✅ expected | 9m ago | 9m ago | 5 |

---

*Auto-generated by `scripts/generate-egress-index.sh`. Allow-list: `config/supply-chain/egress-baseline.yaml` (frozen prefixes; re-seed with `scripts/egress-baseline.sh`). Anomaly trail: `data/egress/anomalies.jsonl`. Alerts armed by renaming `config/prometheus/alerts/egress-alerts.yml.disabled` → `.yml` after the baseline window (shadow-first).*
