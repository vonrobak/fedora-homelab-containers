# Collabora Online: Post-Mortem and Decommission

**Date:** 2026-02-06
**Author:** Claude Opus 4.6
**Status:** Complete - Collabora decommissioned

---

## Summary

Collabora Online was decommissioned from the homelab after persistent, unresolvable WOPI integration issues with Nextcloud richdocuments. The service had been broken since at least 2026-02-05, and extensive debugging across two sessions failed to produce a working document editing flow. The decision was made to remove it entirely rather than leave a broken, internet-facing service in the stack.

**Impact:** Document editing (DOCX, ODT, spreadsheets) is no longer available through Nextcloud. File sync, sharing, CalDAV, CardDAV, and all other Nextcloud features remain fully operational.

---

## Timeline

| Date | Event |
|------|-------|
| ~2025-12 | Collabora initially deployed and working |
| 2026-02-02 | Kernel 6.18.7 upgrade triggers aardvark-dns ordering change; multiple services affected |
| 2026-02-02 | Root cause confirmed: Podman DNS returns IPs in undefined order (ADR-018 created) |
| 2026-02-04 | Static IPs + /etc/hosts fix deployed for all multi-network services |
| 2026-02-05 | Nextcloud upgraded v31 → v32.0.5; richdocuments updated to 9.0.2 |
| 2026-02-05 | "Document loading failed" when opening any document; extensive debugging session |
| 2026-02-05 | Identified: `activate-config` destructively resets `public_wopi_url`; `server_name` added |
| 2026-02-05 | Session ended with config believed correct but untested |
| 2026-02-06 | Resumed debugging with systematic approach |
| 2026-02-06 | Discovered OCS capabilities API returns empty `{}` for richdocuments |
| 2026-02-06 | Root cause narrowed but fix uncertain; decision made to decommission |
| 2026-02-06 | Clean decommission completed |

---

## Root Cause Analysis

The failure was a compound issue with multiple contributing factors, none of which had a clean fix:

### Factor 1: WOPI Discovery Protocol Mismatch

Collabora's discovery XML advertises URLs with `http://` even when `ssl.termination=true` is set and `server_name` is configured correctly. The URLs looked like:

```
http://collabora.patriark.org/browser/859e0275c7/cool.html?
```

The richdocuments app is supposed to replace these with `https://` using the `public_wopi_url` config value, but this replacement happens client-side via the Capabilities API.

### Factor 2: `activate-config` Destructively Resets `public_wopi_url`

The `richdocuments:activate-config` OCC command calls `autoConfigurePublicUrl()` which extracts the hostname from the discovery XML and overwrites `public_wopi_url` in the database. Since discovery returns `http://`, the manually-set `https://` value gets destroyed every time activate-config runs. This is a known design issue in richdocuments.

### Factor 3: Capabilities API Not Exposing richdocuments Data

The OCS capabilities endpoint (`/ocs/v2.php/cloud/capabilities`) returned an empty object for richdocuments when called via HTTP, despite:
- The app being enabled (v9.0.2)
- The capability class being properly registered
- The cached capabilities file containing valid Collabora data
- Direct PHP invocation of the Capabilities class returning correct results

**Root cause discovered:** The richdocuments `Capabilities` class implements `ICapability` but NOT `IPublicCapability`. The OCS controller calls `getCapabilities(true)` (public mode) for unauthenticated requests, which filters out non-public capabilities. For authenticated browser sessions this should work, but the inconsistency made debugging misleading and raised questions about whether the browser JavaScript would reliably receive the `public_wopi_url` needed for URL replacement.

### Factor 4: Uncertain Callback URL

The WOPI callback URL (how Collabora reaches back to Nextcloud to fetch documents) was set to "autodetected," meaning Collabora would use the browser's URL. While connectivity tests showed Collabora could reach Nextcloud both internally (`http://nextcloud:80`) and externally (`https://nextcloud.patriark.org`), the autodetection path introduced another variable in an already fragile flow.

### Why It Worked Before

The original deployment likely predated:
1. The Nextcloud v31 → v32 upgrade (and richdocuments 9.0.2)
2. The aardvark-dns ordering change from kernel 6.18.7
3. The ADR-018 static IP changes

Any of these changes could have disrupted the delicate WOPI handshake that relies on correct URLs, protocols, and network routing across four components (browser, Traefik, Nextcloud, Collabora).

---

## What Was Tried

### Session 1 (2026-02-05)
1. Set `public_wopi_url` to `https://collabora.patriark.org` via OCC
2. Removed `public_wopi_url` for proxy mode (didn't work with richdocuments 9.0.2)
3. Added public Traefik route for `collabora.patriark.org`
4. Fixed iframe blocking: switched from `security-headers@file` to `hsts-only@file`
5. Discovered `activate-config` resets `public_wopi_url`
6. Added `server_name=collabora.patriark.org` environment variable
7. Manually restored `public_wopi_url` after activate-config

### Session 2 (2026-02-06)
1. Verified all container health, static IPs, DNS resolution
2. Confirmed bidirectional connectivity (Nextcloud ↔ Collabora)
3. Confirmed discovery XML returns correct hostname (but `http://`)
4. Confirmed `public_wopi_url` is correctly set to `https://`
5. Discovered OCS capabilities API returns empty for richdocuments
6. Traced through richdocuments source code (Capabilities.php, CapabilitiesService.php, CachedRequestService.php, PermissionManager.php, Application.php)
7. Identified IPublicCapability vs ICapability distinction
8. Verified direct PHP invocation works correctly
9. Confirmed cache files contain valid data
10. Accidentally ran `activate-config` which destroyed `public_wopi_url` again (restored)

---

## Decision to Decommission

The decision was based on:

1. **Fragility:** The WOPI integration involves a 4-step protocol across 4 components, with multiple points of silent failure (HTTP vs HTTPS replacement, capability caching, callback URL autodetection, discovery URL parsing).

2. **Destructive tooling:** The primary configuration tool (`activate-config`) actively destroys the manual fix needed to work around the protocol mismatch.

3. **Low value vs. effort:** Document editing in Nextcloud is a convenience feature, not a core workflow for this homelab. The user's document editing needs are served by native applications.

4. **Security principle:** The user's stated principle is to not leave services on the internet that are not optimally configured. A broken Collabora with a public route violates this.

5. **Time investment:** Two debugging sessions (combined ~3+ hours) without reaching a working state, with no clear path to resolution.

---

## Decommission Steps Executed

1. Backed up to `/mnt/btrfs-pool/subvol6-tmp/99-outbound/collabora-decommission-20260206/`:
   - `collabora.container` quadlet
   - `routers.yml.before-decommission`
   - `richdocuments-config.txt` (all app config values)

2. Disabled and removed `richdocuments` app from Nextcloud

3. Stopped and disabled `collabora.service`

4. Removed quadlet file and systemd symlink, daemon-reloaded

5. Removed Collabora router and service from `config/traefik/dynamic/routers.yml`

6. Removed `collabora_admin_password` podman secret

7. Removed Collabora container image (`docker.io/collabora/code:latest`)

8. Restored Nextcloud log level to warning (was set to debug during investigation)

9. Updated documentation:
   - README.md: 27 containers, 13 groups
   - `docs/10-services/guides/nextcloud.md`: removed all Collabora references
   - `.claude/skills/homelab-deployment/stacks/nextcloud.yml`: removed Collabora service
   - Archived `collabora.md` to `docs/90-archive/collabora-guide-archived-20260206.md`
   - Regenerated all auto-docs

---

## Post-Decommission State

| Metric | Before | After |
|--------|--------|-------|
| Containers | 28 | 27 |
| Service groups | 14 | 13 |
| Nextcloud containers | 4 | 3 |
| Traefik routes | 13 | 12 |
| Estimated memory savings | - | ~80MB idle, up to 2GB during editing |

All 27 remaining containers healthy. Nextcloud fully operational for file sync, sharing, CalDAV, CardDAV, and external storage.

---

## Lessons Learned

1. **Collabora/richdocuments WOPI integration is inherently fragile** in reverse proxy setups. The protocol (HTTP vs HTTPS) handling relies on client-side JavaScript URL replacement guided by a config value that the app's own CLI tool destroys.

2. **`activate-config` is a trap.** It appears to be the canonical way to configure richdocuments, but it silently overwrites manual URL fixes. The fix for this would require patching the richdocuments source.

3. **The OCS capabilities API behaves differently for authenticated vs unauthenticated requests.** The `IPublicCapability` interface distinction is not documented prominently, making debugging misleading when testing with curl.

4. **Compound failures are the hardest to debug.** The Collabora issue involved protocol mismatches, destructive tooling, capability API filtering, and potentially stale caches - all interacting. No single fix addressed all factors.

5. **Know when to cut losses.** Two sessions of deep debugging with diminishing returns on a non-critical service is the right time to decommission rather than invest further.

---

## Artifacts

| Item | Location |
|------|----------|
| Quadlet backup | `/mnt/btrfs-pool/subvol6-tmp/99-outbound/collabora-decommission-20260206/collabora.container` |
| Routing backup | `/mnt/btrfs-pool/subvol6-tmp/99-outbound/collabora-decommission-20260206/routers.yml.before-decommission` |
| richdocuments config | `/mnt/btrfs-pool/subvol6-tmp/99-outbound/collabora-decommission-20260206/richdocuments-config.txt` |
| Archived guide | `docs/90-archive/collabora-guide-archived-20260206.md` |
| Debug session 1 | `docs/98-journals/2026-02-05-nextcloud-upgrade-testing-and-collabora-debugging.md` |
| DNS root cause | `docs/98-journals/2026-02-02-ROOT-CAUSE-CONFIRMED-dns-resolution-order.md` |
