# ADR-022: Systemd Socket Activation for Rootless Traefik

**Date:** 2026-04-16
**Status:** Proposed — prototype verified on branch `prototype/traefik-socket-activation` (2026-04-16 21:09 CEST). Awaiting operator decision on merge + the two environmental verifications (organic CrowdSec drops, independent per-IP rate-limit buckets) that cannot be forced in-session.
**Related:** Supersedes NAT remediation Track A1/A2 as framed in the 2026-04-12 launchpad; restores operational assumptions behind **ADR-008** (CrowdSec fail-fast ordering) and leaves **ADR-018** (static-IP multi-network routing) unchanged.

## Context

The homelab's documented five-layer edge defense (CrowdSec IP rep → rate-limit → Authelia MFA → headers → app) depends on Traefik seeing the real client source IP. Since the move to multi-network rootless Traefik (ADR-018), every external connection traverses Podman's `rootlessport` which SNATs the source to a single private address (currently `10.89.2.69`). Consequences:

- CrowdSec bouncer cannot reject external IPs at the edge — every external client appears as the same trusted internal IP.
- Per-IP rate limiting collapses into a single global bucket. Rate-limit buckets for HA, Immich, qBittorrent etc. had to be oversized to accommodate "all external users" as one source (see comments in `config/traefik/dynamic/middleware.yml:141-151`).
- Forensic IP attribution is impossible from Traefik access logs.

Upstream won't fix it: `containers/podman#12850` (rootless source-NAT by design). Detailed evidence chain: `docs/98-journals/2026-03-17-pasta-source-nat-investigation.md`. Full problem statement and launchpad: `docs/99-reports/2026-04-12-nat-security-model-violation.md`. Vaultwarden forensic audit (MFA held): `docs/99-reports/2026-04-14-authelia-credential-exposure-forensic-review.md` and follow-up 2026-04-16.

### Options considered

The launchpad's original ranking prioritized "architectural elegance." Research on 2026-04-16 (`docs/99-reports/2026-04-16-nat-remediation-research.md`) added **blast radius** and **reversibility** as equally-weighted criteria and surfaced a path the launchpad had missed entirely.

| # | Option | Rootless | Reversibility | Blast radius | Notes |
|---|--------|----------|---------------|--------------|-------|
| **1** | **Systemd socket activation** (chosen) | ✓ | Trivial | Minimal | Homelab already ~80% pre-configured |
| 2 | Rootful Traefik | Limited (Traefik only) | Moderate | Elevated — Traefik gains host privileges | SELinux + systemd unit surgery |
| 3 | Host-networked rootless Traefik | ✓ (degraded) | Moderate | Loses Traefik network isolation | |
| 4 | UDM Pro HAProxy sidecar | ✓ | Hard | External dependency on UDM filesystem | Not supported by Ubiquiti; firmware-update fragility |
| 5 | UDM Pro PROXY protocol (original Track A1) | — | — | — | **Dead end**: no native UDM support on UniFi OS 5.x |
| 6 | Cloudflare Tunnel | ✓ | Moderate | Cloud dependency violates sovereignty | |
| 7 | Accept & compensate | ✓ | N/A | Leaves edge defense non-functional | Status quo |

## Decision

**Adopt systemd socket activation for Traefik's `web` (80) and `websecure` (443) entrypoints.** Systemd binds the host listener, `accept()`s incoming connections with the real peer address, and hands the connected file descriptor to the container process via `LISTEN_FDS`. `rootlessport` never participates, so no SNAT happens. Traefik ≥ v3.1 matches the inherited FD by name to its configured entrypoint and uses it directly.

### Implementation (prototype, on branch `prototype/traefik-socket-activation`)

Two new **native systemd user units** (not quadlets — quadlet only processes `.container`, `.network`, `.volume`, `.pod`, `.build`, `.kube`, `.image`, `.artifact`). They live alongside the existing timer/service sources in `systemd/` and are installed by copy to `~/.config/systemd/user/`:

- `systemd/http.socket` — `ListenStream=0.0.0.0:80`, `FileDescriptorName=web`, `Service=traefik.service`
- `systemd/https.socket` — `ListenStream=0.0.0.0:443`, `FileDescriptorName=websecure`, `Service=traefik.service`

Modifications to `quadlets/traefik.container`:

- Remove `PublishPort=80:80` and `PublishPort=443:443`.
- Add `Notify=true` in `[Container]` (switches `--sdnotify=conmon` → `--sdnotify=container`; Traefik v2+ calls `sd_notify(READY=1)` natively).
- Add `Sockets=http.socket` and `Sockets=https.socket` lines in the `[Service]` section (quadlet passthrough to the generated service unit).
- Add `Requires=http.socket https.socket` and `After=… http.socket https.socket` in `[Unit]`.

No change to `config/traefik/traefik.yml` — entrypoint names (`web`, `websecure`) already match the socket `FileDescriptorName` values.

### Known caveat — HTTP→HTTPS redirect

Traefik issue [#12469](https://github.com/traefik/traefik/issues/12469): when an entrypoint's address is replaced by an inherited FD, the `redirections.entryPoint` construct in `traefik.yml:48-54` may emit URLs with no port. **Mitigation path if the issue reproduces:** drop the entrypoint-level redirect and attach the existing `https-redirect@file` middleware (already defined in `middleware.yml:375-380`) to a catchall HTTP router. Verified as part of the prototype's verification step #5.

### Pre-conditions (all satisfied)

| Pre-condition | State |
|---|---|
| `net.ipv4.ip_unprivileged_port_start ≤ 80` | ✓ set to 80 |
| Podman supports `Sockets=` in quadlets | ✓ 5.8.1 |
| Traefik native systemd FD support | ✓ v3.1+ (homelab runs `:latest`) |
| `SecurityLabelDisable=true` on Traefik | ✓ already set (needed for podman.sock) |
| Entrypoint names match expected FD names | ✓ `web`, `websecure` |

### Rollback

Trivial. Revert the quadlet edits, remove (or `systemctl --user stop`) the two `.socket` units, `daemon-reload`, restart Traefik. No data is migrated. No external config (UDM, DNS, certificates) changes.

## Consequences

### Positive

- **Real source IPs restored.** CrowdSec bouncer functions at the edge again. Per-IP rate-limit buckets become meaningful.
- **Rootless preserved.** No move to `/etc/containers/systemd/` or rootful operation. No SELinux surgery.
- **Network segmentation preserved.** ADR-018 (static-IP multi-network routing, `/etc/hosts` override) stays correct.
- **No UDM-side work.** Skips the entire Track A1 SSH-sidecar / firmware-persistence rabbit hole.
- **Graceful reloads get slightly cleaner.** The listening socket survives Traefik restarts (systemd owns it), so in-flight connections are less disruptive during config reloads.

### Negative

- **Lifecycle shift.** The service's effective "started" moment becomes first-connection rather than unit activation. For Traefik this is benign (it idles until a connection arrives anyway), but any existing ordering expectations need review.
- **Rate-limit configs are now oversized.** Values like `rate-limit-home-assistant: burst=600` were sized for "all external users share one bucket." After this change they can and should be retuned downward — but that is follow-up work, out of scope for this ADR.
- **New failure surface.** A misconfigured `.socket` unit could cause ports 80/443 to be bound without Traefik ever starting. Mitigated by `Requires=`/`After=` and by the verification plan below.

### Risks

- **Traefik redirect regression (#12469)** — mitigation documented above; verified as part of prototype acceptance.
- **Image upgrades.** Traefik's socket-activation path is still relatively young (merged in v3.1 via PR #10399). A future regression would manifest as Traefik ignoring the inherited FD. Mitigation: the rollback path is trivial, and `:latest` is pinned only to the minor Traefik line this homelab already tracks.

## Verification plan (prototype acceptance criteria)

Executed on branch `prototype/traefik-socket-activation` before any merge to `main`:

1. **Source IP preservation.** `podman exec traefik cat /var/log/traefik/access.log | jq -r .ClientHost | sort -u | head` — must return multiple real external IPs for internet-origin traffic, not `10.89.2.69`.
2. **CrowdSec bouncer activity.** `cscli metrics` inside the CrowdSec container — expect non-zero bouncer drops within minutes under normal internet hostility.
3. **Independent rate-limit buckets.** Two simultaneous external clients from distinct networks — expect each to be rate-limited against its own bucket, not a shared one.
4. **HA iOS app cold-start.** Should no longer exhibit shared-bucket exhaustion signatures.
5. **HTTP→HTTPS redirect functional.** `curl -v http://patriark.org/` returns 301 to `https://patriark.org/` with a correct port. If broken, switch to `https-redirect@file` middleware on a catchall router.

## Follow-up work (not part of this ADR)

- **Retune rate-limit middlewares.** Drop oversized `burst=` values once per-IP buckets are meaningful again. See comments in `config/traefik/dynamic/middleware.yml`.
- **Refresh CLAUDE.md "Security Architecture" section** — the five-layer model becomes accurate again.
- **Close out Track B** — re-run `security-auditor` against the post-remediation fixture.
- **Independent of this ADR:** enable Vaultwarden event log (`EVENTS_DAYS_RETAIN=90`). Listed in the 2026-04-16 research as a forensic-readiness gap.

## Related

- **ADR-008:** CrowdSec security architecture — functionally restored by this change; no textual change to ADR-008 needed.
- **ADR-018:** Static-IP multi-network services — unchanged; socket activation is orthogonal to backend network topology.
- **Launchpad:** `docs/99-reports/2026-04-12-nat-security-model-violation.md` (gitignored).
- **Research:** `docs/99-reports/2026-04-16-nat-remediation-research.md` (gitignored).
- **Evidence chain:** `docs/98-journals/2026-03-17-pasta-source-nat-investigation.md`.
- **Forensic review:** `docs/99-reports/2026-04-14-authelia-credential-exposure-forensic-review.md`.
- **Upstream references:**
  - `containers/podman#12850` — rootless source-NAT, WONT_FIX.
  - `traefik/traefik#10399` — systemd socket-activation support (merged, v3.1).
  - `traefik/traefik#12469` — redirect regression under socket activation.
  - `eriksjolund/podman-traefik-socket-activation` — working quadlet reference.
