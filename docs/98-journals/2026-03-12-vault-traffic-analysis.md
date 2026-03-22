# Vault.patriark.org Traffic Analysis

**Date:** 2026-03-12
**Source:** Traefik access logs (`/mnt/btrfs-pool/subvol7-containers/traefik-logs/`)
**Period:** 2025-12-26 to 2026-03-12 (77 days)
**Total requests:** 714

## Summary

Analysis of all HTTP traffic to `vault.patriark.org` (Vaultwarden) as seen through Traefik's access logs. All source IPs are Podman container network addresses (10.89.x.x) due to rootless NAT -- real external IPs are not preserved. Traffic is categorized as legitimate Bitwarden client usage, scanner/bot probes, and service outage events.

### Key Numbers

| Metric | Value |
|--------|-------|
| Total requests | 714 |
| Unique container IPs | 15 |
| Scanner probes | ~620 (87%) |
| Legitimate Bitwarden client | ~45 (6%) |
| Service outages (502) | 18 (2 incidents) |
| Rate-limited (429) | 52 |
| Auth attempts (401) | 44 |

### Status Code Distribution

| Status | Count | Meaning |
|--------|-------|---------|
| 404 | 375 | Not found (scanner probes for non-existent paths) |
| 422 | 206 | Unprocessable (invalid Vaultwarden API requests) |
| 429 | 52 | Rate limited |
| 401 | 44 | Unauthorized (failed auth -- mix of legitimate + scanner) |
| 502 | 18 | Bad gateway (Vaultwarden down) |
| 499 | 16 | Client closed connection (mostly Bitwarden icon fetches) |
| 400 | 3 | Bad request |

## Chronological Timeline

### Phase 1: Early Scanning (Dec 26 - Dec 30, 2025)

Low-volume reconnaissance. First contact 5 days after Vaultwarden went live.

| Timestamp (UTC) | IP | Status | Path | User-Agent |
|-----------------|-----|--------|------|------------|
| 2025-12-26 19:32 | 10.89.3.12 | 422 | `/.env` | Chrome/Win10 |
| 2025-12-27 07:47 | 10.89.3.12 | 404 | `/robots.txt` | Safari/macOS |
| 2025-12-27 09:21 | 10.89.3.12 | 404 | `/robots.txt` | Safari/macOS |
| 2025-12-27 14:01 | 10.89.3.12 | 404 | `/` | facebookexternalhit |
| 2025-12-28 00:57 | 10.89.3.12 | 404 | `/robots.txt` | Safari/macOS |
| 2025-12-28 07:41 | 10.89.3.12 | 404 | `/robots.txt` | Safari/macOS |
| 2025-12-28 09:01 | 10.89.3.12 | 404 | `/robots.txt` | Safari/macOS |
| 2025-12-28 20:24 | 10.89.3.3 | 401 | `/identity/connect/token` | Chrome/Linux |
| 2025-12-28 23:22 | 10.89.3.3 | 404 | `/robots.txt` | Safari/macOS |
| 2025-12-29 11:21 | 10.89.3.3 | 404 | `/` | facebookexternalhit |
| 2025-12-29 13:22 | 10.89.3.3 | 401 | `/identity/connect/token` | Chrome/Win10 (x3 rapid) |
| **2025-12-29 13:30** | **10.89.3.3** | **401** | **`/identity/connect/token`** | **Bitwarden_Mobile/2025.12.0 (iPadOS)** |
| **2025-12-29 15:25** | **10.89.3.3** | **401** | **`/identity/connect/token`** | **Bitwarden_Mobile/2025.12.0 (iOS)** |
| 2025-12-29 18:54 | 10.89.3.3 | 401 | `/identity/connect/token` | Firefox/146 Linux |
| 2025-12-30 10:00 | 10.89.3.3 | 404 | `/robots.txt` | facebookexternalhit |
| 2025-12-30 20:46 | 10.89.3.3 | 401 | `/identity/connect/token` | Firefox/146 Linux |
| 2025-12-30 20:53 | 10.89.3.3 | 404 | `/` | Chrome/Win10 |

**Note:** Bold entries are confirmed legitimate Bitwarden mobile clients. The 401s from browser UAs on Dec 28-30 could be legitimate web vault login attempts or scanner probes -- ambiguous because the container NAT IP is the same.

### Phase 2: Major Scan Campaign #1 (Dec 31, 2025)

**164 requests in a single day** from IP `10.89.3.3`. Systematic .env enumeration and path fuzzing.

| Timestamp (UTC) | Status | Path | User-Agent |
|-----------------|--------|------|------------|
| 2025-12-31 02:11 - 23:34 | 422/404 | `/.env`, `/.env.bak`, `/.env.save`, `/admin/.env`, `/backend/.env`, `/vendor/.env`, `/lib/.env`, `/api/.env`, `/config/.env`, `/wp-config.php`, `/.git/config`, etc. | Firefox/15.0 (Linux x86_64) -- spoofed ancient UA |

**Attack pattern:** Classic web app .env file enumeration looking for exposed secrets. 83 returned 422 (Vaultwarden's default for unknown paths), 79 returned 404. One 401 auth attempt and one 400 bad request mixed in.

### Phase 3: Transition & Continued Scanning (Jan 1 - Jan 10, 2026)

Scanner IP rotates from `10.89.3.3` to `10.89.2.76` to `10.89.2.83` (likely same actor, new Podman NAT mappings after container restarts).

| Date | IP | Hits | Notable Activity |
|------|-----|------|-----------------|
| Jan 1 | 10.89.3.3 + 10.89.2.76 | 29 | Continued .env enumeration |
| Jan 2 | 10.89.2.76 | 2 | robots.txt + facebookexternalhit |
| Jan 3 | 10.89.2.76 | 3 | facebookexternalhit + 2 auth attempts (Firefox/Gecko) |
| Jan 4-5 | 10.89.2.83 | 14 | robots.txt + facebookexternalhit + Chrome/Win10 probes |
| **Jan 7** | **10.89.2.83** | **40** | **Mixed: 7 legitimate Bitwarden_Mobile/iOS auth + LeakIx scanner + icon fetches** |
| Jan 8 | 10.89.2.83 | 1 | CensysInspect |
| Jan 9-10 | 10.89.2.83 + 10.89.2.104 | 3 | Low-volume probes |

**Jan 7 detail -- legitimate Bitwarden Mobile (iPhone) activity:**
```
15:30:00  401  POST /identity/connect/token  Bitwarden_Mobile/2025.12.0 (iOS 26.2; Model iPhone)
15:30:01  401  POST /identity/connect/token  (x4 rapid retries)
15:31:03  401  POST /identity/connect/token  (retry)
15:31:10  401  POST /identity/connect/token  (retry)
19:19:30  499  GET  /icons/mentimeter.com/icon.png  Bitwarden/2787 CFNetwork
19:19:30  499  GET  /icons/kbin.social/icon.png
19:19:30  499  GET  /icons/clasohlson.com/icon.png
20:20:48  499  GET  /icons/login.vend.no/icon.png
20:20:48  499  GET  /icons/nexusmods.com/icon.png
```

The 401s are the iPhone trying to sync but failing auth (possibly expired session or wrong master password). The 499 icon fetches are Bitwarden iOS fetching favicons for vault entries -- client cancelled before completion.

### Phase 4: Major Scan Campaign #2 (Jan 11-15, 2026)

**248 requests over 5 days** from IP `10.89.2.104`. The heaviest scanning period.

| Date | Hits | Pattern |
|------|------|---------|
| Jan 11 | 59 | Path enumeration (`.env` variants, `/robots.txt`, random paths) |
| **Jan 12** | **189** | **Massive automated scan: python-httpx/0.28.1 (155 hits) + Chrome-spoofed UA** |
| Jan 13 | 5 | Googlebot-spoofed UA + Samsung Android UA + Bitwarden icon fetches |
| Jan 14 | 3 | Low-volume probes |
| Jan 15 | 12 | CensysInspect + wpbot |

**Jan 12 attack detail:** 189 requests in 22.5 hours. User-agent `python-httpx/0.28.1` indicates automated tooling. Systematic path fuzzing with 80 returning 422 and 107 returning 404. This was the single busiest day for vault scanning.

### Phase 5: LeakIx Scanner Period (Jan 15 - Jan 27, 2026)

IP `10.89.4.45` with consistent `l9scan/2.0` user-agent (LeakIx security scanner).

| Date | Hits | Activity |
|------|------|----------|
| Jan 15 | 1 | First appearance |
| Jan 18 | 4 | robots.txt + path probes |
| Jan 19 | 15 | Systematic scanning |
| Jan 20-27 | 9 | Low-volume daily probes |

### Phase 6: Legitimate Mobile Sync Issues (Jan 29 - Jan 30, 2026)

**Bitwarden mobile clients struggling to authenticate** -- 33 auth attempts, all returning 401.

**Jan 29 (iPad, Bitwarden_Mobile/2025.12.1):**
```
23:11:18  401  POST /identity/connect/token  iPadOS 26.2
23:11:19  401  (x4 rapid retries over 2 seconds)
23:16:03  401  (x2 retries after 5 min)
23:16:27  401  (x2 more)
23:21:29  401  (x2 more -- 10 min total of retrying)
23:21:32  499  GET /icons/bugzilla.redhat.com/icon.png  (icon fetch cancelled)
23:21:32  499  GET /icons/booking.com/icon.png
```

**Jan 30 (iPad, Bitwarden_Mobile/2026.1.0 -- upgraded version):**
```
00:32:54  401  POST /identity/connect/token  iPadOS 26.2
00:32:55  401  (x3 rapid retries)
00:38:46  401  (x2 retries after 6 min)
00:38:48  401  (x2 more)
00:45:48  401  (x2 more after 7 min)
00:48:22  401  (final attempt)
```

**Analysis:** iPad was persistently trying to sync but failing auth. The client upgraded from 2025.12.1 to 2026.1.0 between attempts. All 401s indicate the server received the request but rejected credentials. Likely cause: master password change, session expiry, or account lockout.

### Phase 7: Service Outage #1 (Feb 2, 2026)

**Vaultwarden was down for at least 20 minutes.** 8 requests returned 502 Bad Gateway.

```
16:04:13  502  POST /identity/connect/token  10.89.4.69  Chrome/Linux
16:04:13  502  GET  /api/config              10.89.4.69  Chrome/Linux
16:04:14  502  POST /identity/connect/token  10.89.4.69  Chrome/Linux
16:04:43  502  POST /identity/connect/token  10.89.4.69  Chrome/Linux
16:09:43  502  POST /identity/connect/token  10.89.4.69  Chrome/Linux (5 min retry)
16:14:43  502  POST /identity/connect/token  10.89.4.69  Chrome/Linux (5 min retry)
16:19:43  502  POST /identity/connect/token  10.89.4.73  Chrome/Linux (5 min retry)
16:24:43  502  POST /identity/connect/token  10.89.3.10  Chrome/Linux (5 min retry)
```

**Pattern:** Exact 5-minute retry intervals suggest a Bitwarden browser extension auto-retrying. The IP changed across retries (10.89.4.69 -> 10.89.4.73 -> 10.89.3.10) due to Podman NAT reassignment. This was legitimate traffic hitting a down service.

### Phase 8: Low-Volume Scanning (Feb 3 - Feb 15, 2026)

Quiet period. 1-3 hits per day from misc scanners.

| Date | IP | Hits | Notable |
|------|-----|------|---------|
| Feb 3 | 10.89.2.134 | 2 | Bitwarden/2847 CFNetwork icon fetches (legitimate iOS) |
| Feb 5 | 10.89.2.69 | 3 | Chrome/Win10 + Safari/macOS probes |
| Feb 6 | 10.89.2.69 | 2 | Netcraft Web Server Survey + CensysInspect |
| Feb 8-15 | 10.89.4.69 | ~14 | Sporadic scanner probes (wpbot, CensysInspect, Go-http-client) |

### Phase 9: Service Outage #2 (Feb 21, 2026)

**Vaultwarden down again.** 10 requests returned 502 over ~13 minutes. More severe than outage #1 -- multiple browsers affected and WebSocket connections dropped.

```
17:10:38  502  POST /identity/connect/token   Chrome/Linux
17:10:42  502  GET  /api/config               Chrome/Win10
17:10:43  502  GET  /notifications/hub?access_token=...  Chrome/Win10 (WebSocket)
17:11:58  502  POST /identity/connect/token   Firefox/147 Linux
17:11:58  502  GET  /api/config               Firefox/147 Linux
17:15:45  502  GET  /notifications/hub?access_token=...  Chrome/Win10 (WebSocket)
17:17:03  502  POST /identity/connect/token   Firefox/147 Linux
17:22:03  502  POST /identity/connect/token   Firefox/147 Linux
17:23:02  502  GET  /                          Firefox/147 Linux (manual browser check)
17:23:05  502  GET  /favicon.ico               Firefox/147 Linux
```

**Analysis:** Both Chrome and Firefox on Linux hitting 502. The `access_token` in WebSocket URLs confirms these were authenticated sessions that lost connection. The manual `/` hit at 17:23 looks like someone checking "is it even up?" via the browser. Service recovered by Feb 22.

### Phase 10: Quiet Period (Feb 22 - Mar 6, 2026)

No vault traffic logged for 14 days. Service running normally but no external access attempts.

### Phase 11: Current Activity (Mar 7 - Mar 12, 2026)

Recent traffic dominated by rate limiting (429) affecting legitimate access.

**Mar 7 -- scanner probe:**
```
13:00:07  401  POST /identity/connect/token  10.89.4.69  Chrome/Win10
13:00:22  400  POST /identity/connect/token  10.89.4.69  Chrome/Win10
```

**Mar 9 -- legitimate access + rate limiting:**
```
10:56:06  404  GET  /robots.txt              10.89.3.69  Firefox/148 Linux
20:11:16  429  GET  /api/accounts/revision-date  (rate limited!)
20:11:16  429  GET  /notifications/hub?...   (WebSocket rate limited!)
20:14:44  429  GET  /css/vaultwarden.css     (27 assets rate limited in burst)
20:15:03  429  GET  /api/accounts/profile    (x5 profile requests limited)
20:15:04  429  GET  /icons/photos.patriark.org/icon.png  (icon fetches limited)
```

**Mar 10 -- browser extension icon sync rate limited:**
```
18:52:23  429  GET  /notifications/hub?...
18:53:11  429  GET  /api/auth-requests/pending
18:53:11  429  GET  /icons/ableton.com/icon.png  (22 icon fetches rate limited)
18:54:33  429  GET  /api/accounts/revision-date
```

**Mar 11-12 -- ongoing WebSocket rate limiting:**
```
2026-03-11 09:13  429  /notifications/hub?...
2026-03-12 11:58  429  /notifications/hub?...
2026-03-12 14:29  429  /notifications/hub?...
```

## Source IP Summary

All IPs are Podman container network addresses (rootless NAT). Real external IPs are not preserved in Traefik headers -- a known limitation of the rootless architecture.

| Container IP | Hits | Period | Primary Activity |
|-------------|------|--------|-----------------|
| 10.89.2.104 | 269 | Jan 9-15 | python-httpx scanner (heaviest single actor) |
| 10.89.3.3 | 201 | Dec 26 - Jan 1 | .env enumeration + spoofed UAs + some legitimate |
| 10.89.2.83 | 56 | Jan 4-9 | LeakIx scanner + legitimate Bitwarden Mobile/iOS |
| 10.89.3.69 | 55 | Mar 9-12 | Legitimate browser + rate-limited icon syncs |
| 10.89.4.45 | 29 | Jan 15-27 | LeakIx l9scan/2.0 scanner |
| 10.89.4.57 | 24 | Jan 28-29 | Bitwarden_Mobile/iPad auth retries |
| 10.89.4.69 | 23 | Feb 2 - Mar 7 | Mix: outage 502s + scanner probes |
| 10.89.4.73 | 18 | Jan 30 - Feb 2 | Bitwarden_Mobile/iPad auth + outage 502 |
| 10.89.2.69 | 15 | Feb 5-21 | Outage #2 (502s) + Netcraft + probes |
| 10.89.2.76 | 10 | Jan 1-3 | Scanner probes + facebookexternalhit |
| 10.89.3.12 | 8 | Dec 26-28 | First scanner (robots.txt + .env) |
| Others | 6 | Various | CensysInspect, one-offs |

## Top Scanned Paths

| Path | Hits | What they're looking for |
|------|------|-------------------------|
| `/identity/connect/token` | 58 | Bitwarden auth endpoint (mix legit + scanner) |
| `/robots.txt` | 45 | Standard recon |
| `/` | 38 | Landing page check |
| `/.env` | 30 | Exposed environment variables/secrets |
| `/.git/config` | 15 | Exposed git repository |
| `/admin/.env` | 6 | Admin panel secrets |
| `/.env.save` | 5 | Editor backup of .env |
| `/api/accounts/profile` | 5 | Bitwarden API (legitimate) |
| `/wp-config.php` | 4 | WordPress config (wrong CMS) |
| `/wp-config.php.old` | 4 | WordPress backup |
| `/.env.bak` | 4 | Backup .env file |
| `/backend/.env` | 4 | Backend secrets |
| `/icons/*/icon.png` | ~20 | Bitwarden favicon proxy (legitimate) |

## Scanner User-Agents Identified

| User-Agent | Hits | Type |
|-----------|------|------|
| `python-httpx/0.28.1` | 155 | Automated scanner (Jan 12 campaign) |
| Firefox/15.0 (spoofed ancient version) | 153 | Scanner masquerading as Firefox |
| `l9scan/2.0` (LeakIx) | 53 | Security research scanner |
| `facebookexternalhit/1.1` | ~10 | Facebook link preview (possibly legitimate) |
| `CensysInspect/1.1` | ~5 | Internet census project |
| `wpbot/1.4` | ~3 | WordPress vulnerability scanner |
| `Netcraft Web Server Survey` | 1 | Netcraft |
| `Go-http-client/1.1` | 1 | Generic Go scanner |
| `Googlebot/2.1` (spoofed) | 1 | Fake Googlebot |
| `SonyEricssonW580i` (spoofed) | 1 | Deliberately absurd UA |

## Observations & Concerns

### Rate Limiting Affecting Legitimate Use (Active Issue)

Since March 9, the Bitwarden browser extension's icon sync is being rate-limited (429). When the extension opens, it fetches favicons for all vault entries simultaneously -- this burst triggers the rate limit and also blocks critical API calls (`/api/accounts/revision-date`, `/notifications/hub`). The WebSocket connection for live sync notifications is being rate-limited on every reconnect (Mar 11-12).

**Potential fix:** Vaultwarden's icon proxy and API endpoints may need a higher rate limit or a separate rate limit tier from general web traffic.

### No Successful (200) Responses in Logs

Zero 200 status codes across 714 requests. Legitimate Bitwarden sync traffic (which does work) likely uses long-lived WebSocket connections and API calls that return 200 but are not captured in these log entries, or the successful auth flow returns different status codes (e.g., the `/identity/connect/token` endpoint returns a JWT token with a non-200 success code).

### IP Visibility Gap

All source IPs are container network addresses. The rootless Podman NAT makes it impossible to:
- Distinguish multiple external attackers
- Correlate with CrowdSec IP reputation
- Implement IP-based rate limiting per real client
- Build useful fail2ban-style blocking rules

This is a fundamental limitation of the rootless architecture and applies to all services, not just Vaultwarden.

### Two Service Outages

Vaultwarden was unreachable on Feb 2 (20 min) and Feb 21 (13 min). Both during afternoons. Root cause unknown from access logs alone -- would need container logs or systemd journal for that period.

## Raw Data

Full JSON export: `~/containers/vault-access-log-export.jsonl` (714 entries, 688K)

Fields per entry: `StartUTC`, `RequestMethod`, `RequestPath`, `DownstreamStatus`, `ClientHost`, `request_X-Real-Ip`, `request_User-Agent`, `RouterName`, `ServiceName`, `Duration`, `TLSVersion`, `TLSCipher`.
