# Nextcloud Upgrade, Device Testing, and Collabora Debugging

**Date:** 2026-02-05 (evening session)
**Author:** Claude Opus 4.6
**Status:** Partially complete - Collabora integration unresolved, testing paused

---

## Context

Systematic Nextcloud verification session following the 6-phase plan: server-side health checks, multi-device testing, sharing, on-demand file access, rate limiting, and documentation. The session expanded to include a Nextcloud major version upgrade (v31 → v32.0.5) and extensive Collabora debugging.

## What Was Achieved

### Phase 1: Server-Side Verification (Complete)

All 4 containers healthy (nextcloud, nextcloud-db, nextcloud-redis, collabora). Key findings:

- **Missing database index auto-fixed:** `systag_objecttype` index added by `occ db:add-missing-indices`
- **All endpoints verified:** HTTPS, status.php, CalDAV redirect, CardDAV redirect, WebDAV, TLS cert
- **MariaDB NOCOW:** Correctly configured
- **Redis:** 104 keys, 1.46MB, healthy
- **Loki analysis:** 94,260 requests/7d, 0.16% error rate, zero CrowdSec blocks, zero auth failures

### Nextcloud Upgrade: v31 → v32.0.5

- Updated quadlet image tag to `:latest` (resolves to 32.0.5)
- Migration ran automatically, added 2 new DB indices (`properties_name_path_user`, `calobjects_by_uid_index`)
- Full `maintenance:repair --include-expensive` ran clean
- richdocuments updated to 9.0.2

### Rate Limit Fix

**Problem:** 2,079 PROPFIND 429 responses from desktop sync client. The Nextcloud desktop client (mirall/4.0.6) performs aggressive tree-walking on large directories (Music library: 2,080+ directories) that exceeded the 1,400 burst limit in ~30 seconds.

**Fix:** Increased Nextcloud-specific rate limits in `config/traefik/dynamic/middleware.yml`:
- Average: 400 → 600 requests/min
- Burst: 1,400 → 3,000

**Result:** Zero 429s after the fix. Sync completes cleanly.

### Multi-Device Testing (Partial)

All devices tested successfully for basic sync:
- **File sync:** Upload/download works across iPhone, iPad Pro, MacBook Air, Gaming PC, Fedora HTPC
- **Special characters:** `test-æøå-spesial.txt` syncs correctly
- **Folder sync:** Nested directories propagate to all clients
- **CalDAV/CardDAV:** App password configured and stored in Bitwarden

### External Storage Permission Fix

**Problem:** Multimedia, Music, and Opptak external storage mounts were configured as read-write in Nextcloud admin settings but mounted read-only at the container level (`:ro`).

**Fix:** Set `readonly=true` in Nextcloud external storage config via `occ files_external:option <id> readonly true` for all three mounts. Container-level and Nextcloud-level permissions now aligned.

### WebAuthn/FIDO2 Dual Registration

After the NC32 upgrade, the user noticed empty WebAuthn 2FA entries and re-registered YubiKeys. They had existing FIDO2 passwordless registrations. Analysis: dual registration is harmless - WebAuthn 2FA and FIDO2 passwordless are separate ceremonies using different Nextcloud API endpoints.

### Documentation Update

Updated `docs/10-services/guides/nextcloud.md` (v1.0 → v2.0):
- Corrected version: 32.0.5 (Hub 11)
- Rate limits: 600/min, 3,000 burst
- Added Client Setup section (desktop VFS, mobile, CalDAV/CardDAV)
- Added Sharing Best Practices section
- Fixed Collabora admin URL references
- Added ADR-013/014/016/018 cross-references

## What Remains Unresolved: Collabora Integration

### Symptom
"Document loading failed - failed to load Nextcloud Office" when opening any .docx file from any browser (tested on Fedora HTPC Firefox and MacBook Air).

### Root Cause Analysis

The WOPI flow for Collabora document editing:
1. Browser requests token from Nextcloud (`/apps/richdocuments/token`)
2. Nextcloud generates WOPI token and returns iframe URL (from discovery cache)
3. Browser loads Collabora iframe using the URL
4. Collabora fetches document from Nextcloud via WOPI callback

**The problem is in step 2-3:** The discovery XML from Collabora returns internal URLs (`http://collabora:9980/browser/.../cool.html?`). The richdocuments app is supposed to replace these with the public URL (`https://collabora.patriark.org/...`) using the `public_wopi_url` config. However:

1. **`activate-config` resets `public_wopi_url`:** The `autoConfigurePublicUrl()` method in `ConnectivityService.php` extracts the domain from discovery URLs and overwrites the `public_wopi_url` database setting. Any manual setting gets destroyed.

2. **Collabora's `server_name` was not configured:** Without `server_name`, Collabora uses its container hostname in discovery URLs. The internal fetch (`http://collabora:9980`) produces `http://collabora:9980/browser/...` URLs.

3. **Protocol mismatch:** Even after adding `server_name=collabora.patriark.org`, the discovery returns `http://collabora.patriark.org/...` (correct hostname, wrong protocol). The `ssl.termination=true` setting doesn't affect the scheme for internally-fetched discovery.

### What Was Tried (in order)

1. Set `public_wopi_url` to `https://collabora.patriark.org` via `occ config:app:set` → Worked until `activate-config` reset it
2. Removed `public_wopi_url` for proxy mode → richdocuments 9.0.2 proxy mode doesn't work (requests never reach Collabora)
3. Added public Traefik route for `collabora.patriark.org` with `hsts-only@file` middleware → Route works (200 on capabilities), but didn't solve the document loading
4. Found `security-headers@file` middleware was blocking iframe with `frame-ancestors 'self'` → Switched to `hsts-only@file`
5. Discovered `activate-config` resets `public_wopi_url` → Stopped using activate-config for URL configuration
6. Added `server_name=collabora.patriark.org` to Collabora quadlet → Discovery now returns correct hostname but `http://` instead of `https://`
7. Manually set `public_wopi_url` to `https://collabora.patriark.org` after activate-config → Currently set correctly, untested

### Current State (as of session end)

- `server_name=collabora.patriark.org` added to `collabora.container` quadlet
- `public_wopi_url` set to `https://collabora.patriark.org` in database
- Discovery returns `http://collabora.patriark.org/browser/...` (correct hostname, http protocol)
- Collabora public route exists and works via Traefik
- All infrastructure connectivity verified (Nextcloud ↔ Collabora bidirectional)

### Likely Remaining Fix

The JavaScript in richdocuments should use `public_wopi_url` from the Capabilities API to replace the internal URL in `urlsrc`. With the current config (`public_wopi_url=https://collabora.patriark.org`), this *should* work. The user has not tested after the final `server_name` + `activate-config` + manual `public_wopi_url` fix sequence.

If it still fails after testing:
- Check browser developer console for mixed-content or CSP errors
- Verify the Capabilities API returns `https://collabora.patriark.org` for `public_wopi_url`
- Consider making Collabora advertise `https://` by adjusting `extra_params` (e.g., `--o:net.proto=https`)
- As a last resort, use a reverse proxy configuration that sets `X-Forwarded-Proto: https` for the internal discovery fetch

## Files Modified

| File | Change |
|------|--------|
| `quadlets/nextcloud.container` | Image tag → `:latest` (NC 32.0.5) |
| `quadlets/collabora.container` | Added `server_name=collabora.patriark.org` |
| `config/traefik/dynamic/middleware.yml` | Nextcloud rate limit: 600/min, 3000 burst |
| `config/traefik/dynamic/routers.yml` | Added Collabora public route, `hsts-only@file` middleware |
| `docs/10-services/guides/nextcloud.md` | Version, rate limits, client setup, sharing sections |

## Remaining Plan Phases

- **Phase 2 (partial):** Conflict test, delete, rename, large file, offline edit untested
- **Phase 3:** Sharing & external access testing not started
- **Phase 4:** VFS/On-Demand configuration not started
- **Phase 5:** Rate limit remediation done (600/min, 3000 burst)
- **Phase 6 (partial):** Documentation updated, journal written

## Lessons Learned

1. **`richdocuments:activate-config` is destructive** - it resets `public_wopi_url` by auto-detecting from discovery URLs. Never use it to "fix" a manually configured public URL.
2. **Collabora `server_name` is essential** for reverse proxy setups where the public hostname differs from the container hostname. Without it, WOPI discovery advertises internal URLs.
3. **Traefik access logs only capture 400-599** - this is by design for storage efficiency, but makes debugging 200-response-with-error-body issues invisible from the proxy layer.
4. **Rate limit burst capacity matters for WebDAV** - desktop sync clients perform aggressive tree-walking (PROPFIND) that can exhaust burst limits in seconds for large directory trees.
