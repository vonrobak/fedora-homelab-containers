# Egress Observatory — Baseline Index (Auto-Generated)

**Generated:** 2026-07-17 05:03:29 UTC
**Implements:** ADR-030 P7 (Tier 4) — egress detection. **Mode:** live (alerting)

Host-side `/proc/<pid>/net/{tcp,tcp6}` sampling of reverse_proxy-tier containers (attributable, rootless, scratch-safe, DNS-method-agnostic). Detection, not prevention. See `config/supply-chain/known-egress.md` for method and residual/evasion scope.

## Pipeline health

| Component | Last run | Detail |
|---|---|---|
| Collector (`egress-collector.service`) | 0s ago | 22 services sampled |
| Classifier (`egress-detect.timer`) | 2m ago | mode=live (alerting); last window 7 dest(s) |

## Per-service egress

| Service | Mode | Public dests | Unexpected | Peers (swarm) |
|---|---|---|---|---|
| alert-discord-relay | classify | 5 | ✅ 0 | — |
| alertmanager | classify | — | — | — |
| audiobookshelf | classify | — | — | — |
| authelia | classify | — | — | — |
| blackbox-exporter | classify | — | — | — |
| crowdsec | classify | 265 | ✅ 0 | — |
| forgejo | classify | — | — | — |
| gathio | classify | 4 | ✅ 0 | — |
| gluetun | classify | — | — | — |
| grafana | classify | 4 | ✅ 0 | — |
| home-assistant | classify | 57 | ✅ 0 | — |
| immich-server | classify | 2 | ✅ 0 | — |
| jellyfin | classify | 17 | ✅ 0 | — |
| loki | classify | 2 | ✅ 0 | — |
| navidrome | classify | 8 | ✅ 0 | — |
| nextcloud | classify | 5 | ⚠️ 1 | — |
| pihole-exporter | classify | — | — | — |
| prometheus | classify | — | — | — |
| proton-bridge | classify | 2 | ✅ 0 | — |
| qbittorrent | peer-swarm (count-only) | — | — | 154 |
| traefik | classify | 7 | ✅ 0 | — |
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
| `162.159.128.233` | 443 | ✅ expected | 50d ago | 3d ago | 190 |
| `162.159.135.232` | 443 | ✅ expected | 53d ago | 2d ago | 197 |
| `162.159.136.232` | 443 | ✅ expected | 46d ago | 2d ago | 159 |
| `162.159.137.232` | 443 | ✅ expected | 42d ago | 2d ago | 147 |
| `162.159.138.232` | 443 | ✅ expected | 52d ago | 2d ago | 191 |

### crowdsec

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `108.128.100.255` | 443 | ✅ expected | 14d ago | 12d ago | 20 |
| `108.128.5.151` | 443 | ✅ expected | 10d ago | 9d ago | 11 |
| `108.128.75.34` | 443 | ✅ expected | 12d ago | 12d ago | 5 |
| `108.129.14.254` | 443 | ✅ expected | 20d ago | 14d ago | 190 |
| `108.131.181.25` | 443 | ✅ expected | 14d ago | 9d ago | 10 |
| `108.132.121.20` | 443 | ✅ expected | 11d ago | 10d ago | 10 |
| `108.132.122.254` | 443 | ✅ expected | 14d ago | 9d ago | 25 |
| `108.132.137.184` | 443 | ✅ expected | 12d ago | 12d ago | 10 |
| `108.132.143.133` | 443 | ✅ expected | 33d ago | 27d ago | 29 |
| `108.132.165.84` | 443 | ✅ expected | 11d ago | 11d ago | 5 |
| `108.132.168.183` | 443 | ✅ expected | 28d ago | 25d ago | 20 |
| `108.132.183.8` | 443 | ✅ expected | 8d ago | 8d ago | 5 |
| `108.132.189.51` | 443 | ✅ expected | 22d ago | 18d ago | 59 |
| `108.132.205.103` | 443 | ✅ expected | 14d ago | 8d ago | 30 |
| `108.132.205.140` | 443 | ✅ expected | 3d ago | 2d ago | 53 |
| `108.132.213.83` | 443 | ✅ expected | 5d ago | 4d ago | 20 |
| `108.132.219.253` | 443 | ✅ expected | 30d ago | 28d ago | 20 |
| `108.132.221.3` | 443 | ✅ expected | 8d ago | 5d ago | 15 |
| `108.132.234.82` | 443 | ✅ expected | 22d ago | 20d ago | 15 |
| `108.132.246.192` | 443 | ✅ expected | 32d ago | 26d ago | 362 |
| `108.132.37.191` | 443 | ✅ expected | 15d ago | 12d ago | 14 |
| `108.132.53.78` | 443 | ✅ expected | 22d ago | 18d ago | 74 |
| `108.132.71.88` | 443 | ✅ expected | 15d ago | 14d ago | 15 |
| `108.132.92.167` | 443 | ✅ expected | 6d ago | 5d ago | 10 |
| `108.132.99.107` | 443 | ✅ expected | 15d ago | 15d ago | 5 |
| `108.133.21.137` | 443 | ✅ expected | 10d ago | 8d ago | 115 |
| `108.133.25.161` | 443 | ✅ expected | 16d ago | 13d ago | 19 |
| `108.133.25.40` | 443 | ✅ expected | 33d ago | 28d ago | 39 |
| `108.133.29.186` | 443 | ✅ expected | 11d ago | 9d ago | 20 |
| `108.133.3.16` | 443 | ✅ expected | 11d ago | 11d ago | 5 |
| `108.133.30.139` | 443 | ✅ expected | 28d ago | 27d ago | 74 |
| `108.133.31.148` | 443 | ✅ expected | 14d ago | 8d ago | 30 |
| `108.133.5.78` | 443 | ✅ expected | 15d ago | 11d ago | 19 |
| `108.133.51.235` | 443 | ✅ expected | 15d ago | 14d ago | 10 |
| `176.34.181.119` | 443 | ✅ expected | 8d ago | 8d ago | 5 |
| `18.200.110.20` | 443 | ✅ expected | 14h ago | 43m ago | 63 |
| `18.200.123.226` | 443 | ✅ expected | 11d ago | 3d ago | 485 |
| `18.200.39.45` | 443 | ✅ expected | 15d ago | 13d ago | 15 |
| `18.202.146.153` | 443 | ✅ expected | 34d ago | 28d ago | 30 |
| `18.202.164.218` | 443 | ✅ expected | 10d ago | 3d ago | 478 |
| `18.202.172.107` | 443 | ✅ expected | 26d ago | 25d ago | 25 |
| `18.202.182.46` | 443 | ✅ expected | 12d ago | 12d ago | 5 |
| `18.202.70.248` | 443 | ✅ expected | 8d ago | 6d ago | 25 |
| `18.203.121.198` | 443 | ✅ expected | 33d ago | 29d ago | 40 |
| `18.203.183.142` | 443 | ✅ expected | 13d ago | 13d ago | 4 |
| `3.248.159.68` | 443 | ✅ expected | 14d ago | 5d ago | 539 |
| `3.248.169.249` | 443 | ✅ expected | 22d ago | 20d ago | 25 |
| `3.250.250.65` | 443 | ✅ expected | 21d ago | 20d ago | 20 |
| `3.253.202.159` | 443 | ✅ expected | 15d ago | 12d ago | 10 |
| `34.240.192.79` | 443 | ✅ expected | 14d ago | 14d ago | 5 |
| `34.240.248.6` | 443 | ✅ expected | 24d ago | 11d ago | 772 |
| `34.240.99.65` | 443 | ✅ expected | 5d ago | 44h ago | 64 |
| `34.241.148.96` | 443 | ✅ expected | 15d ago | 15d ago | 5 |
| `34.241.216.41` | 443 | ✅ expected | 34d ago | 29d ago | 39 |
| `34.241.218.127` | 443 | ✅ expected | 6d ago | 3d ago | 45 |
| `34.241.33.70` | 443 | ✅ expected | 13h ago | 3h ago | 35 |
| `34.241.45.245` | 443 | ✅ expected | 6d ago | 6d ago | 5 |
| `34.241.56.54` | 443 | ✅ expected | 29d ago | 26d ago | 30 |
| `34.242.110.163` | 443 | ✅ expected | 8d ago | 6d ago | 15 |
| `34.242.13.27` | 443 | ✅ expected | 9d ago | 3d ago | 37 |
| `34.243.209.239` | 443 | ✅ expected | 12d ago | 9d ago | 25 |
| `34.243.213.166` | 443 | ✅ expected | 21d ago | 16d ago | 175 |
| `34.246.147.139` | 443 | ✅ expected | 18d ago | 10d ago | 556 |
| `34.246.188.122` | 443 | ✅ expected | 28d ago | 28d ago | 10 |
| `34.246.232.161` | 443 | ✅ expected | 7d ago | 5d ago | 15 |
| `34.246.54.177` | 443 | ✅ expected | 7d ago | 5d ago | 163 |
| `34.247.101.158` | 443 | ✅ expected | 29d ago | 23d ago | 59 |
| `34.247.127.233` | 443 | ✅ expected | 19d ago | 12d ago | 370 |
| `34.247.193.23` | 443 | ✅ expected | 12d ago | 12d ago | 10 |
| `34.248.135.223` | 443 | ✅ expected | 11d ago | 11d ago | 5 |
| `34.248.252.15` | 443 | ✅ expected | 11d ago | 8d ago | 224 |
| `34.249.156.29` | 443 | ✅ expected | 22d ago | 19d ago | 39 |
| `34.249.175.76` | 443 | ✅ expected | 11d ago | 10d ago | 20 |
| `34.249.35.132` | 443 | ✅ expected | 22d ago | 22d ago | 30 |
| `34.249.38.225` | 443 | ✅ expected | 14d ago | 14d ago | 10 |
| `34.249.74.158` | 443 | ✅ expected | 7d ago | 4d ago | 25 |
| `34.250.219.167` | 443 | ✅ expected | 3d ago | 2h ago | 188 |
| `34.250.246.103` | 443 | ✅ expected | 7d ago | 6d ago | 10 |
| `34.250.94.23` | 443 | ✅ expected | 5d ago | 75m ago | 336 |
| `34.251.4.204` | 443 | ✅ expected | 12d ago | 12d ago | 5 |
| `34.251.48.106` | 443 | ✅ expected | 8d ago | 18h ago | 471 |
| `34.251.85.31` | 443 | ✅ expected | 23d ago | 22d ago | 45 |
| `34.252.105.132` | 443 | ✅ expected | 8d ago | 6d ago | 10 |
| `34.252.238.164` | 443 | ✅ expected | 29d ago | 24d ago | 80 |
| `34.252.249.34` | 443 | ✅ expected | 6d ago | 2d ago | 57 |
| `34.252.67.120` | 443 | ✅ expected | 29d ago | 24d ago | 59 |
| `34.252.99.143` | 443 | ✅ expected | 15d ago | 12d ago | 20 |
| `34.253.250.27` | 443 | ✅ expected | 15d ago | 14d ago | 10 |
| `34.253.80.226` | 443 | ✅ expected | 8d ago | 2d ago | 33 |
| `34.253.95.189` | 443 | ✅ expected | 10d ago | 10d ago | 25 |
| `34.254.128.0` | 443 | ✅ expected | 7d ago | 7d ago | 5 |
| `34.254.31.214` | 443 | ✅ expected | 7d ago | 7d ago | 10 |
| `34.254.5.251` | 443 | ✅ expected | 7d ago | 7d ago | 5 |
| `34.255.101.228` | 443 | ✅ expected | 7d ago | 6d ago | 10 |
| `34.255.13.211` | 443 | ✅ expected | 22d ago | 20d ago | 25 |
| `34.255.171.152` | 443 | ✅ expected | 9h ago | 12m ago | 25 |
| `34.255.187.129` | 443 | ✅ expected | 15d ago | 15d ago | 10 |
| `34.255.211.7` | 443 | ✅ expected | 15d ago | 9d ago | 19 |
| `34.255.33.254` | 443 | ✅ expected | 8d ago | 5d ago | 8 |
| `46.137.116.145` | 443 | ✅ expected | 30d ago | 26d ago | 15 |
| `46.137.119.216` | 443 | ✅ expected | 14d ago | 10d ago | 35 |
| `46.137.166.0` | 443 | ✅ expected | 12d ago | 12d ago | 5 |
| `46.137.35.14` | 443 | ✅ expected | 31d ago | 29d ago | 20 |
| `52.16.143.245` | 443 | ✅ expected | 7d ago | 5d ago | 15 |
| `52.16.181.166` | 443 | ✅ expected | 8d ago | 4d ago | 15 |
| `52.16.198.105` | 443 | ✅ expected | 26d ago | 26d ago | 12 |
| `52.16.198.79` | 443 | ✅ expected | 14d ago | 12d ago | 20 |
| `52.16.239.210` | 443 | ✅ expected | 15d ago | 15d ago | 5 |
| `52.16.97.104` | 443 | ✅ expected | 6d ago | 6d ago | 5 |
| `52.17.118.72` | 443 | ✅ expected | 28d ago | 26d ago | 15 |
| `52.17.173.66` | 443 | ✅ expected | 30d ago | 27d ago | 20 |
| `52.17.182.227` | 443 | ✅ expected | 16d ago | 14d ago | 14 |
| `52.17.27.193` | 443 | ✅ expected | 15d ago | 11d ago | 25 |
| `52.17.91.120` | 443 | ✅ expected | 22d ago | 20d ago | 30 |
| `52.18.160.54` | 443 | ✅ expected | 14d ago | 9d ago | 30 |
| `52.18.248.216` | 443 | ✅ expected | 13d ago | 13d ago | 5 |
| `52.18.50.168` | 443 | ✅ expected | 6d ago | 5d ago | 20 |
| `52.18.95.48` | 443 | ✅ expected | 22d ago | 22d ago | 25 |
| `52.19.134.40` | 443 | ✅ expected | 32d ago | 18d ago | 794 |
| `52.19.210.92` | 443 | ✅ expected | 8d ago | 6d ago | 20 |
| `52.19.255.174` | 443 | ✅ expected | 22d ago | 21d ago | 40 |
| `52.19.31.182` | 443 | ✅ expected | 30d ago | 28d ago | 159 |
| `52.19.97.17` | 443 | ✅ expected | 15d ago | 12d ago | 10 |
| `52.208.44.16` | 443 | ✅ expected | 16d ago | 16d ago | 5 |
| `52.208.53.18` | 443 | ✅ expected | 14d ago | 9d ago | 14 |
| `52.209.0.64` | 443 | ✅ expected | 30d ago | 23d ago | 97 |
| `52.209.111.217` | 443 | ✅ expected | 6d ago | 6d ago | 5 |
| `52.209.173.58` | 443 | ✅ expected | 27d ago | 25d ago | 139 |
| `52.209.205.217` | 443 | ✅ expected | 3d ago | 17h ago | 73 |
| `52.210.122.225` | 443 | ✅ expected | 29d ago | 28d ago | 44 |
| `52.211.111.6` | 443 | ✅ expected | 23d ago | 23d ago | 45 |
| `52.211.142.180` | 443 | ✅ expected | 12d ago | 12d ago | 5 |
| `52.211.195.171` | 443 | ✅ expected | 10d ago | 35h ago | 582 |
| `52.211.29.30` | 443 | ✅ expected | 24d ago | 19d ago | 305 |
| `52.211.56.189` | 443 | ✅ expected | 16d ago | 14d ago | 9 |
| `52.212.47.49` | 443 | ✅ expected | 31d ago | 27d ago | 49 |
| `52.212.98.6` | 443 | ✅ expected | 15d ago | 11d ago | 18 |
| `52.213.226.37` | 443 | ✅ expected | 28d ago | 26d ago | 25 |
| `52.214.21.105` | 443 | ✅ expected | 26d ago | 26d ago | 5 |
| `52.214.255.194` | 443 | ✅ expected | 13d ago | 10d ago | 15 |
| `52.214.54.249` | 443 | ✅ expected | 30d ago | 27d ago | 15 |
| `52.215.162.174` | 443 | ✅ expected | 6d ago | 6d ago | 5 |
| `52.215.173.209` | 443 | ✅ expected | 25d ago | 11d ago | 809 |
| `52.215.19.191` | 443 | ✅ expected | 8d ago | 6d ago | 15 |
| `52.215.215.102` | 443 | ✅ expected | 8d ago | 3d ago | 35 |
| `52.30.165.11` | 443 | ✅ expected | 29d ago | 25d ago | 25 |
| `52.30.169.249` | 443 | ✅ expected | 5d ago | 3d ago | 10 |
| `52.30.176.43` | 443 | ✅ expected | 7d ago | 2d ago | 31 |
| `52.30.212.227` | 443 | ✅ expected | 16d ago | 12d ago | 20 |
| `52.30.231.178` | 443 | ✅ expected | 30d ago | 24d ago | 63 |
| `52.31.121.137` | 443 | ✅ expected | 8d ago | 5d ago | 10 |
| `52.31.252.131` | 443 | ✅ expected | 28d ago | 25d ago | 64 |
| `52.31.58.24` | 443 | ✅ expected | 28d ago | 27d ago | 74 |
| `52.31.76.36` | 443 | ✅ expected | 8d ago | 8d ago | 5 |
| `52.31.8.86` | 443 | ✅ expected | 14d ago | 11d ago | 15 |
| `52.48.115.130` | 443 | ✅ expected | 12d ago | 10d ago | 126 |
| `52.48.142.125` | 443 | ✅ expected | 21d ago | 18d ago | 89 |
| `52.48.65.76` | 443 | ✅ expected | 34d ago | 25d ago | 598 |
| `52.48.90.106` | 443 | ✅ expected | 29d ago | 28d ago | 15 |
| `52.49.1.39` | 443 | ✅ expected | 9d ago | 5d ago | 20 |
| `52.49.140.16` | 443 | ✅ expected | 32d ago | 28d ago | 30 |
| `52.49.67.224` | 443 | ✅ expected | 6d ago | 6d ago | 5 |
| `52.50.153.113` | 443 | ✅ expected | 13d ago | 9d ago | 29 |
| `52.50.163.172` | 443 | ✅ expected | 15d ago | 14d ago | 10 |
| `52.50.177.36` | 443 | ✅ expected | 7d ago | 6d ago | 10 |
| `52.51.137.54` | 443 | ✅ expected | 22d ago | 16d ago | 193 |
| `52.51.148.109` | 443 | ✅ expected | 26d ago | 24d ago | 81 |
| `52.51.193.26` | 443 | ✅ expected | 6d ago | 19h ago | 134 |
| `52.51.224.28` | 443 | ✅ expected | 7d ago | 3d ago | 24 |
| `52.51.30.23` | 443 | ✅ expected | 4d ago | 4d ago | 5 |
| `52.51.31.247` | 443 | ✅ expected | 15d ago | 15d ago | 5 |
| `52.51.5.37` | 443 | ✅ expected | 21d ago | 21d ago | 10 |
| `52.51.57.14` | 443 | ✅ expected | 16d ago | 13d ago | 15 |
| `54.154.137.37` | 443 | ✅ expected | 5d ago | 4d ago | 9 |
| `54.154.143.162` | 443 | ✅ expected | 9d ago | 5d ago | 25 |
| `54.154.67.102` | 443 | ✅ expected | 13d ago | 11d ago | 135 |
| `54.154.68.208` | 443 | ✅ expected | 5d ago | 4d ago | 10 |
| `54.155.120.106` | 443 | ✅ expected | 12d ago | 10d ago | 15 |
| `54.155.184.143` | 443 | ✅ expected | 6d ago | 6d ago | 5 |
| `54.155.206.188` | 443 | ✅ expected | 14d ago | 14d ago | 5 |
| `54.155.54.37` | 443 | ✅ expected | 14d ago | 11d ago | 15 |
| `54.171.2.48` | 443 | ✅ expected | 14d ago | 14d ago | 5 |
| `54.171.238.201` | 443 | ✅ expected | 7d ago | 5d ago | 23 |
| `54.171.33.36` | 443 | ✅ expected | 3d ago | 19h ago | 117 |
| `54.171.78.236` | 443 | ✅ expected | 30d ago | 25d ago | 40 |
| `54.194.125.196` | 443 | ✅ expected | 16d ago | 16d ago | 5 |
| `54.194.161.226` | 443 | ✅ expected | 9d ago | 6d ago | 20 |
| `54.194.168.166` | 443 | ✅ expected | 14d ago | 10d ago | 20 |
| `54.194.218.193` | 443 | ✅ expected | 27d ago | 27d ago | 5 |
| `54.194.222.175` | 443 | ✅ expected | 29d ago | 29d ago | 5 |
| `54.194.85.107` | 443 | ✅ expected | 28d ago | 23d ago | 94 |
| `54.195.147.237` | 443 | ✅ expected | 30d ago | 24d ago | 60 |
| `54.195.255.109` | 443 | ✅ expected | 21d ago | 21d ago | 5 |
| `54.195.58.94` | 443 | ✅ expected | 15d ago | 13d ago | 10 |
| `54.216.174.169` | 443 | ✅ expected | 2d ago | 43m ago | 120 |
| `54.216.223.16` | 443 | ✅ expected | 22d ago | 20d ago | 29 |
| `54.216.63.170` | 443 | ✅ expected | 14d ago | 14d ago | 5 |
| `54.217.73.238` | 443 | ✅ expected | 8d ago | 8d ago | 5 |
| `54.220.106.227` | 443 | ✅ expected | 7d ago | 4d ago | 25 |
| `54.220.110.244` | 443 | ✅ expected | 21d ago | 21d ago | 9 |
| `54.220.129.146` | 443 | ✅ expected | 7d ago | 6d ago | 15 |
| `54.220.232.45` | 443 | ✅ expected | 14d ago | 9d ago | 50 |
| `54.220.4.25` | 443 | ✅ expected | 22d ago | 19d ago | 39 |
| `54.228.169.234` | 443 | ✅ expected | 23d ago | 22d ago | 30 |
| `54.228.72.44` | 443 | ✅ expected | 13d ago | 11d ago | 10 |
| `54.229.234.23` | 443 | ✅ expected | 30d ago | 27d ago | 30 |
| `54.246.87.25` | 443 | ✅ expected | 7d ago | 7d ago | 5 |
| `54.247.128.112` | 443 | ✅ expected | 26d ago | 14d ago | 772 |
| `54.247.91.245` | 443 | ✅ expected | 10d ago | 10d ago | 5 |
| `54.72.105.85` | 443 | ✅ expected | 11d ago | 10d ago | 23 |
| `54.72.42.56` | 443 | ✅ expected | 22d ago | 22d ago | 33 |
| `54.73.182.236` | 443 | ✅ expected | 15d ago | 13d ago | 15 |
| `54.73.186.227` | 443 | ✅ expected | 12d ago | 12d ago | 5 |
| `54.73.47.207` | 443 | ✅ expected | 13d ago | 13d ago | 10 |
| `54.73.72.206` | 443 | ✅ expected | 8d ago | 46h ago | 53 |
| `54.74.43.116` | 443 | ✅ expected | 29d ago | 26d ago | 30 |
| `54.75.140.194` | 443 | ✅ expected | 7d ago | 5d ago | 10 |
| `54.75.182.87` | 443 | ✅ expected | 27d ago | 25d ago | 25 |
| `54.75.8.192` | 443 | ✅ expected | 14d ago | 10d ago | 24 |
| `54.75.92.29` | 443 | ✅ expected | 14d ago | 11d ago | 20 |
| `54.76.118.150` | 443 | ✅ expected | 27d ago | 27d ago | 5 |
| `54.76.150.103` | 443 | ✅ expected | 21d ago | 21d ago | 10 |
| `54.76.164.80` | 443 | ✅ expected | 9d ago | 6d ago | 15 |
| `54.76.217.37` | 443 | ✅ expected | 30d ago | 28d ago | 19 |
| `54.76.23.94` | 443 | ✅ expected | 8d ago | 6d ago | 15 |
| `54.77.106.61` | 443 | ✅ expected | 32d ago | 27d ago | 20 |
| `54.77.155.168` | 443 | ✅ expected | 15d ago | 11d ago | 20 |
| `54.77.193.254` | 443 | ✅ expected | 13d ago | 10d ago | 20 |
| `54.77.221.81` | 443 | ✅ expected | 29d ago | 26d ago | 30 |
| `54.77.231.123` | 443 | ✅ expected | 21d ago | 20d ago | 25 |
| `54.77.236.172` | 443 | ✅ expected | 33h ago | 3h ago | 84 |
| `54.77.253.10` | 443 | ✅ expected | 12d ago | 12d ago | 10 |
| `54.77.6.216` | 443 | ✅ expected | 10d ago | 10d ago | 5 |
| `54.78.108.19` | 443 | ✅ expected | 15d ago | 15d ago | 5 |
| `54.78.116.49` | 443 | ✅ expected | 15d ago | 11d ago | 10 |
| `54.78.124.255` | 443 | ✅ expected | 7d ago | 4d ago | 19 |
| `54.78.137.34` | 443 | ✅ expected | 8d ago | 4d ago | 33 |
| `54.78.186.64` | 443 | ✅ expected | 14d ago | 11d ago | 25 |
| `54.78.193.70` | 443 | ✅ expected | 28d ago | 24d ago | 49 |
| `54.78.26.191` | 443 | ✅ expected | 7d ago | 7d ago | 5 |
| `63.32.11.219` | 443 | ✅ expected | 14d ago | 12d ago | 15 |
| `63.32.184.247` | 443 | ✅ expected | 16d ago | 9d ago | 44 |
| `63.32.213.125` | 443 | ✅ expected | 9d ago | 9d ago | 5 |
| `63.32.217.27` | 443 | ✅ expected | 30d ago | 27d ago | 19 |
| `63.33.187.119` | 443 | ✅ expected | 15d ago | 14d ago | 10 |
| `63.33.229.19` | 443 | ✅ expected | 7d ago | 5d ago | 15 |
| `63.33.5.76` | 443 | ✅ expected | 33d ago | 29d ago | 232 |
| `63.34.17.221` | 443 | ✅ expected | 9d ago | 7d ago | 15 |
| `63.34.177.147` | 443 | ✅ expected | 31d ago | 13d ago | 1035 |
| `63.34.189.230` | 443 | ✅ expected | 4d ago | 2d ago | 53 |
| `63.34.43.204` | 443 | ✅ expected | 7d ago | 7d ago | 10 |
| `63.34.48.116` | 443 | ✅ expected | 5d ago | 12m ago | 278 |
| `63.34.64.15` | 443 | ✅ expected | 14h ago | 2h ago | 44 |
| `63.34.86.48` | 443 | ✅ expected | 8d ago | 8d ago | 5 |
| `63.35.34.90` | 443 | ✅ expected | 29d ago | 22d ago | 53 |
| `63.35.47.18` | 443 | ✅ expected | 8d ago | 8d ago | 5 |
| `63.35.7.115` | 443 | ✅ expected | 12d ago | 12d ago | 5 |
| `99.80.153.48` | 443 | ✅ expected | 15d ago | 15d ago | 10 |
| `99.80.188.173` | 443 | ✅ expected | 9d ago | 6d ago | 15 |
| `99.80.39.243` | 443 | ✅ expected | 30d ago | 27d ago | 40 |
| `99.81.112.7` | 443 | ✅ expected | 14d ago | 14d ago | 5 |
| `99.81.142.82` | 443 | ✅ expected | 15d ago | 15d ago | 5 |
| `99.81.28.139` | 443 | ✅ expected | 21d ago | 21d ago | 9 |
| `99.81.76.162` | 443 | ✅ expected | 7d ago | 6d ago | 10 |
| `99.81.77.108` | 443 | ✅ expected | 6d ago | 6d ago | 9 |

### gathio

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.16.11.34` | 443 | ✅ expected | 23d ago | 23d ago | 4 |
| `104.16.7.34` | 443 | ✅ expected | 3d ago | 3d ago | 16 |
| `104.16.8.34` | 443 | ✅ expected | 23d ago | 23d ago | 14 |
| `104.16.9.34` | 443 | ✅ expected | 3d ago | 3d ago | 4 |

### grafana

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `34.49.170.206` | 443 | 🕒 retained | 6d ago | 3d ago | 20 |
| `192.0.73.2` | 443 | ✅ expected | 52d ago | 11h ago | 34 |
| `34.120.177.193` | 443 | ✅ expected | 53d ago | 3d ago | 35691 |
| `34.96.126.106` | 443 | ✅ expected | 52d ago | 7d ago | 224 |

### home-assistant

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.26.4.238` | 443 | ✅ expected | 53d ago | 11h ago | 97 |
| `104.26.5.238` | 443 | ✅ expected | 53d ago | 2h ago | 102 |
| `151.101.1.195` | 443 | ✅ expected | 53d ago | 8h ago | 69 |
| `151.101.65.195` | 443 | ✅ expected | 51d ago | 2d ago | 36 |
| `157.249.81.141` | 443 | ✅ expected | 53d ago | 2h ago | 702 |
| `172.67.68.90` | 443 | ✅ expected | 52d ago | 8h ago | 109 |
| `18.156.61.178` | 443 | ✅ expected | 4d ago | 2m ago | 601 |
| `18.156.89.194` | 443 | ✅ expected | 41d ago | 19d ago | 2066 |
| `18.157.239.155` | 8883 | ✅ expected | 6d ago | 5d ago | 2789 |
| `18.158.114.127` | 8883 | ✅ expected | 5d ago | 3d ago | 3088 |
| `18.158.226.141` | 443 | ✅ expected | 9d ago | 5d ago | 381 |
| `18.159.150.123` | 8883 | ✅ expected | 15d ago | 14d ago | 2872 |
| `18.159.166.33` | 8883 | ✅ expected | 23d ago | 22d ago | 2774 |
| `18.159.63.103` | 8883 | ✅ expected | 11d ago | 10d ago | 711 |
| `18.184.121.56` | 8883 | ✅ expected | 23d ago | 23d ago | 1224 |
| `18.184.176.116` | 443 | ✅ expected | 12h ago | 2m ago | 79 |
| `18.184.210.149` | 8883 | ✅ expected | 13d ago | 12d ago | 4827 |
| `18.185.10.145` | 8883 | ✅ expected | 27d ago | 23d ago | 9731 |
| `18.185.208.158` | 443 | ✅ expected | 23d ago | 23d ago | 1 |
| `18.185.51.38` | 8883 | ✅ expected | 22d ago | 20d ago | 3631 |
| `18.192.191.83` | 8883 | ✅ expected | 8d ago | 6d ago | 3626 |
| `18.193.176.220` | 8883 | ✅ expected | 16d ago | 15d ago | 2775 |
| `18.193.191.4` | 8883 | ✅ expected | 14d ago | 13d ago | 756 |
| `18.194.113.144` | 8883 | ✅ expected | 10d ago | 9d ago | 2818 |
| `18.194.246.231` | 8883 | ✅ expected | 3d ago | 3d ago | 126 |
| `18.195.182.246` | 8883 | ✅ expected | 29d ago | 27d ago | 3620 |
| `18.195.195.66` | 443 | ✅ expected | 5d ago | 2m ago | 763 |
| `18.196.186.252` | 8883 | ✅ expected | 3d ago | 2d ago | 3162 |
| `18.197.183.115` | 8883 | ✅ expected | 3d ago | 2m ago | 1931 |
| `18.197.42.5` | 8883 | ✅ expected | 4d ago | 4d ago | 354 |
| `18.197.66.183` | 8883 | ✅ expected | 27d ago | 27d ago | 1 |
| `18.198.121.88` | 8883 | ✅ expected | 19d ago | 18d ago | 2734 |
| `18.198.144.131` | 8883 | ✅ expected | 20d ago | 11d ago | 3089 |
| `18.198.169.78` | 8883 | ✅ expected | 27d ago | 27d ago | 357 |
| `18.198.177.41` | 8883 | ✅ expected | 27d ago | 27d ago | 1795 |
| `18.198.200.175` | 8883 | ✅ expected | 30d ago | 29d ago | 2777 |
| `3.120.114.20` | 8883 | ✅ expected | 10d ago | 6d ago | 2838 |
| `3.121.91.88` | 8883 | ✅ expected | 9d ago | 8d ago | 2774 |
| `3.64.157.17` | 8883 | ✅ expected | 18d ago | 16d ago | 5594 |
| `3.65.85.145` | 8883 | ✅ expected | 2d ago | 3h ago | 5650 |
| `3.70.88.116` | 443 | ✅ expected | 10d ago | 12m ago | 1212 |
| `3.72.199.54` | 443 | ✅ expected | 30d ago | 18d ago | 1156 |
| `3.74.79.125` | 443 | ✅ expected | 19d ago | 8d ago | 999 |
| `3.76.164.97` | 443 | ✅ expected | 33d ago | 11d ago | 2060 |
| `3.78.82.168` | 443 | ✅ expected | 35h ago | 2m ago | 225 |
| `35.156.210.53` | 8883 | ✅ expected | 20d ago | 19d ago | 4480 |
| `51.102.149.208` | 443 | ✅ expected | 8d ago | 4d ago | 417 |
| `51.102.84.196` | 443 | ✅ expected | 13d ago | 35h ago | 1258 |
| `52.58.62.182` | 443 | ✅ expected | 8d ago | 5d ago | 312 |
| `52.59.138.18` | 443 | ✅ expected | 33d ago | 21d ago | 1142 |
| `63.181.101.136` | 443 | ✅ expected | 21d ago | 10d ago | 985 |
| `63.181.21.188` | 443 | ✅ expected | 40d ago | 18d ago | 1972 |
| `63.182.123.150` | 443 | ✅ expected | 36d ago | 13d ago | 2053 |
| `63.182.206.75` | 443 | ✅ expected | 18d ago | 10d ago | 828 |
| `63.186.5.221` | 443 | ✅ expected | 5d ago | 2m ago | 714 |
| `63.186.71.169` | 443 | ✅ expected | 11d ago | 12h ago | 1205 |
| `63.186.78.77` | 443 | ✅ expected | 18d ago | 8d ago | 978 |

### immich-server

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.21.71.92` | 443 | ✅ expected | 53d ago | 117m ago | 1439 |
| `172.67.170.79` | 443 | ✅ expected | 53d ago | 54m ago | 1308 |

### jellyfin

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.17.207.5` | 443 | ✅ expected | 53d ago | 5d ago | 39 |
| `104.17.208.5` | 443 | ✅ expected | 52d ago | 41h ago | 80 |
| `139.59.139.28` | 443 | ✅ expected | 50d ago | 2d ago | 45 |
| `140.82.121.3` | 443 | ✅ expected | 23d ago | 11d ago | 2 |
| `146.190.237.6` | 443 | ✅ expected | 48d ago | 11d ago | 38 |
| `151.101.1.229` | 443 | ✅ expected | 48d ago | 26d ago | 12 |
| `151.101.129.229` | 443 | ✅ expected | 47d ago | 4d ago | 22 |
| `151.101.193.229` | 443 | ✅ expected | 51d ago | 17h ago | 22 |
| `151.101.65.229` | 443 | ✅ expected | 38d ago | 19d ago | 10 |
| `157.245.38.19` | 443 | ✅ expected | 49d ago | 6d ago | 36 |
| `161.35.245.42` | 443 | ✅ expected | 47d ago | 17h ago | 38 |
| `165.227.169.147` | 443 | ✅ expected | 53d ago | 17h ago | 63 |
| `165.227.244.161` | 443 | ✅ expected | 52d ago | 2d ago | 55 |
| `178.105.98.131` | 443 | ✅ expected | 53d ago | 4d ago | 40 |
| `185.199.109.133` | 443 | ✅ expected | 23d ago | 11d ago | 4 |
| `206.189.97.173` | 443 | ✅ expected | 46d ago | 3d ago | 60 |
| `68.183.204.194` | 443 | ✅ expected | 53d ago | 17h ago | 32 |

### loki

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `34.49.170.206` | 443 | ✅ expected | 7d ago | 2h ago | 189 |
| `34.96.126.106` | 443 | ✅ expected | 53d ago | 42h ago | 1389 |

### navidrome

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.21.43.229` | 443 | ✅ expected | 3d ago | 3d ago | 5 |
| `130.211.19.189` | 443 | ✅ expected | 18d ago | 18d ago | 31 |
| `151.101.237.188` | 443 | ✅ expected | 18d ago | 18d ago | 7 |
| `151.101.238.53` | 443 | ✅ expected | 18d ago | 18d ago | 7 |
| `151.101.238.79` | 443 | ✅ expected | 18d ago | 18d ago | 18 |
| `172.67.186.189` | 443 | ✅ expected | 34d ago | 3d ago | 35 |
| `209.141.42.198` | 443 | ✅ expected | 53d ago | 16h ago | 164 |
| `23.0.161.107` | 443 | ✅ expected | 18d ago | 18d ago | 8 |

### nextcloud

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `5.9.202.145` | 443 | ⚠️ active | 3h ago | 3h ago | 1 |
| `65.108.197.113` | 443 | ✅ expected | 50d ago | 18h ago | 30 |
| `65.109.114.179` | 443 | ✅ expected | 52d ago | 3d ago | 48 |
| `65.21.231.50` | 443 | ✅ expected | 4d ago | 2d ago | 6 |
| `95.217.53.153` | 443 | ✅ expected | 51d ago | 18h ago | 53 |

### proton-bridge

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `185.70.42.41` | 443 | ✅ expected | 53d ago | 2m ago | 44024 |
| `185.70.42.45` | 443 | ✅ expected | 53d ago | 23m ago | 1373 |

### traefik

| Destination | Port | Class | First seen | Last seen | Obs |
|---|---|---|---|---|---|
| `104.19.192.174` | 443 | ✅ expected | 9d ago | 9d ago | 5 |
| `104.19.192.176` | 443 | ✅ expected | 7d ago | 7d ago | 6 |
| `104.19.192.177` | 443 | ✅ expected | 11d ago | 4d ago | 18 |
| `104.19.192.29` | 443 | ✅ expected | 41h ago | 41h ago | 6 |
| `104.19.193.29` | 443 | ✅ expected | 16d ago | 16d ago | 10 |
| `172.65.32.248` | 443 | ✅ expected | 16d ago | 41h ago | 87 |
| `172.67.75.8` | 443 | ✅ expected | 38d ago | 23d ago | 13 |

---

*Auto-generated by `scripts/generate-egress-index.sh`. Allow-list: `config/supply-chain/egress-baseline.yaml` (frozen prefixes; re-seed with `scripts/egress-baseline.sh`). Anomaly trail: `data/egress/anomalies.jsonl`. Alerts armed by renaming `config/prometheus/alerts/egress-alerts.yml.disabled` → `.yml` after the baseline window (shadow-first).*
