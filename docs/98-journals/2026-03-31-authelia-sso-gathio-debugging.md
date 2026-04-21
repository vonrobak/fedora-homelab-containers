# Authelia SSO Blank Page & Gathio 403 — Debugging Session

**Date:** 2026-03-31
**Incident:** Three interrelated issues — Gathio event creation 403, SSO portal blank page, Gathio edit token recovery
**Severity:** Medium (authentication portal degraded, event creation blocked — no data loss)
**Resolution:** Authelia access control regex fixes, WebAuthn config migration, Traefik rate-limit removal from SSO router
**Duration:** ~2 hours of systematic debugging across 4 root causes

---

## Executive Summary

A user attempting to create an event on `events.patriark.org` received 403 Forbidden. Investigating this led to discovering a second, more severe issue: `sso.patriark.org` rendering a blank white page when visited by an authenticated user. The SSO login flow still worked (redirect to Grafana succeeded), but revisiting the portal showed a broken `/2fa/webauthn` page.

The blank page took significant investigation — initial hypotheses (browser cache, circuit breaker, Authelia rate limits, CSP issues) were all eliminated before the true root cause was identified via browser Network tab inspection: Traefik's shared `rate-limit@file` middleware was returning 429 for Authelia's lazily-loaded JavaScript modules.

---

## Issues & Root Causes

### Issue 1: Gathio 403 on Event Creation

**Symptom:** User clicks "Create Event" on `events.patriark.org` → 403 Forbidden.

**Root cause:** Two gaps in Authelia's access control rules for `events.patriark.org`:

1. **Event page regex too strict.** The bypass rule `^/[A-Za-z0-9_-]{10,30}$` used `$` end anchor, but Authelia matches against the full URL path including query strings. When Gathio redirects to an event page with an edit token (`/ExjDAu4EXxt4dn6VhTdDm?e=sttlk1kkgqmq0qont36r6tgbyyb1yl7f`), the regex failed → fell through to `default_policy: deny` → 403.

2. **Missing `/known/groups` path.** Gathio uses this endpoint for group lookups. Not covered by any rule → also denied by default policy.

**Fix:** Updated `config/authelia/configuration.yml`:
- Changed event ID regex to `^/[A-Za-z0-9_-]{10,30}(\?.*)?$` (allows optional query string)
- Added `^/known/.*` to the bypass list

**Verification (Authelia logs confirmed):**
```
url https://events.patriark.org/ExjDAu4EXxt4dn6VhTdDm?e=sttlk1kkgqmq0qont36r6tgbyyb1yl7f
→ "No matching rule" → applying default policy → FORBIDDEN
```

### Issue 2: Gathio Edit Token Recovery

**Symptom:** User created an event without setting an organizer email, never saw the edit password.

**Root cause:** Gathio uses edit tokens (not visible passwords). The `editPassword` field was empty, but the `editToken` existed in MongoDB. The user created 3 duplicate events from the 403 retries.

**Fix:** Queried MongoDB directly to retrieve the edit token:
```
podman exec gathio-db mongosh --quiet --eval "..." gathio
→ editToken: 'l6cq3j9gnqt9pw2u0pfw1ihf71mpd796'
→ Edit URL: https://events.patriark.org/okfTUaCB2wVsUzSGrtbal?e=l6cq3j9gnqt9pw2u0pfw1ihf71mpd796
```

### Issue 3: SSO Portal Blank Page (Most Complex)

**Symptom:** Visiting `sso.patriark.org` while authenticated showed a white page at `/2fa/webauthn`. Login flow worked (first factor → WebAuthn → redirect to Grafana), but revisiting the portal failed. Affected all browsers including private mode.

**Investigation timeline (hypotheses tested and eliminated):**

| # | Hypothesis | Evidence | Result |
|---|-----------|----------|--------|
| 1 | Authelia `/api/configuration` returning 403 | Endpoint requires 1FA middleware — 403 is expected for unauthenticated requests (curl). Authenticated users get 200. | Eliminated |
| 2 | Stale Redis sessions | 48 sessions accumulated. Flushed all. | Did not fix |
| 3 | WebAuthn deprecation warning | `user_verification` deprecated in v4.39.0, replaced by `selection_criteria.user_verification`. Fixed config. | Did not fix |
| 4 | Browser cache | Private mode also fails. | Eliminated |
| 5 | Circuit breaker tripping | Removed `circuit-breaker@file` and `retry@file` from SSO router. | Did not fix |
| 6 | Authelia internal rate limits | Source code confirms static assets are NOT rate-limited by Authelia's endpoint rate limiter. | Eliminated |
| 7 | **Traefik `rate-limit@file` shared middleware** | **Browser Network tab showed 429 with `x-retry-in` header on JS module requests.** | **Root cause** |

**Root cause:** Traefik's `rate-limit@file` middleware (50 req/min average, 100 burst) was shared across ALL routers and was per-IP. The cascade:

```
Grafana dashboard auto-refresh (many API calls from same IP)
  → Rate limit bucket partially consumed
  → User opens sso.patriark.org in another tab
  → Authelia SPA fires ~10 parallel import() for JS modules
  → Combined request count exceeds rate limit
  → Traefik returns 429 Too Many Requests (no Content-Type header)
  → Firefox strict MIME checking for ES modules blocks responses
  → Reports "disallowed MIME type ("")"
  → SPA crashes → blank white page
```

**Why curl couldn't reproduce:** curl requests had no valid session cookie (Redis was flushed) and used separate TCP connections. The rate limit is per-IP and the combined load from Grafana + SSO was the trigger.

**Fix:** Removed `rate-limit@file` and `circuit-breaker@file` from the SSO router. Authelia has its own built-in brute-force regulation (`max_retries: 5, find_time: 2m, ban_time: 5m`), making external rate limiting redundant and harmful for SPA module loading.

### Issue 4: WebAuthn Config Deprecation

**Symptom:** Authelia startup warning about `webauthn.user_verification` being deprecated in v4.39.0.

**Fix:** Migrated from flat key to nested structure:
```yaml
# Before
webauthn:
  user_verification: preferred

# After
webauthn:
  selection_criteria:
    user_verification: preferred
```

Config now validates cleanly with no warnings.

---

## Changes Applied

| File | Change |
|------|--------|
| `config/authelia/configuration.yml` | Fixed event page bypass regex, added `/known/.*` bypass, migrated WebAuthn config |
| `config/traefik/dynamic/routers.yml` | Removed `rate-limit@file`, `circuit-breaker@file`, `retry@file` from SSO router |

---

## Post-Incident Actions

- Flushed all Authelia Redis sessions (password change + clean slate)
- User changed Authelia password after Bitwarden flagged old one
- OTP for password change retrieved from filesystem notifier (`/data/notification.txt`)

---

## Lessons Learned

1. **Shared Traefik rate limits are dangerous for SPAs.** A per-IP rate limit shared across routers means one service's background traffic (Grafana auto-refresh) can starve another service (SSO module loading). Rate limits should be per-router or SPAs should be excluded.

2. **Browser Network tab is the definitive diagnostic.** Two hours of server-side investigation (curl, logs, source code) couldn't identify the 429. Five seconds of browser F12 → Network tab revealed it immediately. When the server says "200" but the browser says "broken," always check the browser's actual received response.

3. **Circuit breakers and retry middleware amplify failures for auth servers.** The retry middleware (3 attempts) tripled the load, making the circuit breaker more likely to trip, which then blocked ALL requests. For a service with its own brute-force protection, external circuit breakers add risk without benefit.

4. **Authelia's `default_policy: deny` is strict by design.** Every path that isn't explicitly matched gets denied. When adding new services, test all paths the application uses (including API endpoints, static assets, and URLs with query strings), not just the main page.

5. **`$` in regex doesn't mean what you think when query strings exist.** Authelia matches resource regexes against the full URL path including query strings. A `$` anchor will fail to match any URL with `?parameters`.
