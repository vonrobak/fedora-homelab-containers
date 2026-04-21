# CrowdSec Acquisition Wiring + Post-ADR-022 Rate-Limit Retune

**Date:** 2026-04-21
**Session type:** Focused security hardening — closing the loop ADR-022 opened
**Scope:** (1) Wire real CrowdSec log acquisition, (2) retune three NAT-era rate-limits, (3) commit pending working-tree drift
**Outcome:** CrowdSec now tails Traefik access logs; three rate-limits returned to per-IP semantics; acquisition pipeline verified end-to-end except for final decision creation (blocked by needing an external IP for empirical verification)

---

## Why this session

ADR-022 (merged 2026-04-17) restored real client source IPs at Traefik by moving from the rootless-pasta NAT model to a socket-activated listener that preserves `X-Forwarded-For`. That fix unblocked two things that had been silently degraded since the NAT collapse:

1. **CrowdSec was effectively blind.** Only the CAPI community blocklist was producing decisions — local acquisition had been deferred because every request previously appeared to come from pasta's NAT address (`10.89.x.x`), so log-derived scenarios would either see every request as "one source" or fire on the local-only NAT address. No point wiring acquisition until source IPs were real again.
2. **Rate-limits were bucketed by NAT source.** All external traffic shared a single bucket post-NAT, forcing limits to be sized for the entire internet rather than per-client. Three services (qBittorrent, Immich, Nextcloud) were running inflated burst/average values that made the rate-limit layer nearly inert against abusive single sources.

Both items were waiting on ADR-022. The fix shipped four days ago; this session closes the loop.

---

## Step 1 — CrowdSec acquisition wiring

### State before

- `config/crowdsec/acquis.yaml` was a placeholder (empty frontmatter only, per issue #137)
- No log sources were being tailed; CrowdSec relied entirely on the CAPI community blocklist for decisions
- `cscli metrics show acquisition` returned "no source configured"

### Scope decision

Narrowed to **Traefik access logs only** this session. Two other candidate sources were evaluated and explicitly deferred with rationale:

- **sshd journald** — SSH is not internet-exposed. The UDM Pro port-forwards only 80/443/8096/7359; port 22 is not forwarded and is restricted to LAN. Brute-force against LAN-only SSH is low-value, and we already have other defenses (fail2ban via the base Fedora install). Revisit if SSH exposure ever changes.
- **Authelia journald** — blocked by an image constraint: the `crowdsec:latest` image does not ship `journalctl`, so journald acquisition isn't possible without either (a) switching to a debian-based image variant, (b) deploying a systemd journal-to-file bridge, or (c) enabling the `LePresidente/authelia` collection after wiring a file-based log path in `authelia.container`. None of those are cheap, and this session was scoped to "get real signal flowing" rather than full coverage. Separate ADR when prioritized.

### Changes

**`quadlets/crowdsec.container`** — added read-only mount of the Traefik log directory:

```
Volume=/mnt/btrfs-pool/subvol7-containers/traefik-logs:/var/log/traefik:ro,z
```

Using `:z` (shared SELinux label) rather than `:Z` because the same directory is bind-mounted into Traefik writeable. CrowdSec only reads.

**`data/crowdsec/config/acquis.yaml`** — rewritten as a documented pointer: clarifies that per-source configs live in `acquis.d/` and lists the active sources + deferred sources with rationale. This file is the first thing anyone touching CrowdSec acquisition will open; making it a readable map saves future time.

**`data/crowdsec/config/acquis.d/traefik.yaml`** (new, gitignored under `data/`):

```yaml
filenames:
  - /var/log/traefik/access.log
labels:
  type: traefik
force_inotify: true
```

`force_inotify: true` is important — the log rotates via logrotate, and without inotify CrowdSec's default polling can miss the rotation and read from a stale fd.

Traefik already filters access logs to `statusCodes 400-599`, so CrowdSec only sees error traffic. That's exactly what the `crowdsecurity/base-http-scenarios` and `crowdsecurity/http-cve` scenarios want — no signal in 2xx traffic for those rules.

### Verification

After quadlet reload + service restart:

```
+----------------------------------+------------+--------------+----------------+------------------------+-------------------+
| Source                           | Lines read | Lines parsed | Lines unparsed | Lines poured to bucket | Lines whitelisted |
+----------------------------------+------------+--------------+----------------+------------------------+-------------------+
| file:/var/log/traefik/access.log | 12         | 12           | -              | -                      | 23                |
+----------------------------------+------------+--------------+----------------+------------------------+-------------------+
```

Read = parsed (good — parser is matching the JSON schema). `Lines whitelisted > Lines read` is expected: the `crowdsecurity/whitelists` collection plus the local `crowdsecurity/local-whitelist` (which explicitly contains `192.168.1.0/24`, `192.168.100.0/24`, and `10.89.*`) each whitelist the same line, so a single request from a LAN client can trigger multiple whitelist hits.

### What remains unverified

The end-to-end pipeline — "bad request → scenario fires → decision created → bouncer enforces" — cannot be fully verified from inside the LAN. Every LAN-origin probe is whitelisted before it reaches a scenario. Confirming decision creation requires either (a) traffic from an external IP (passive — wait), or (b) a temporary whitelist bypass (active — invasive, not worth it for this).

Accepted as a passive observation window: the next time an abusive source hits the edge, we should see the decision ledger populate. Task #7 tracks this as a pending observation.

---

## Step 2 — Rate-limit retune

### Context

Rate-limits at `config/traefik/dynamic/middleware.yml` use `sourceCriterion.ipStrategy.depth: 1` — they bucket by the first hop behind Traefik. Under the NAT collapse, that hop was `10.89.x.x` for every external request, so a single bucket absorbed all internet traffic. The limits were inflated to avoid blocking legitimate users.

Post-ADR-022, `depth: 1` resolves to the real client IP. Previous limits are now far too generous — a single abusive source gets the budget originally intended for "all external traffic combined."

### Retune

| Middleware | `average` (before → after) | `burst` (before → after) | Rationale |
|------------|----------------------------|---------------------------|-----------|
| `rate-limit-nextcloud` | 600 → 300 | 3000 → 1500 | Nextcloud desktop sync bursts hard on large file sets. 300 rpm sustained comfortably absorbs sync catchup for 1–2 clients; 1500 burst covers initial sync storms. Halved across the board since per-IP attribution returned. |
| `rate-limit-qbittorrent` | 300 → 100 | 600 (unchanged) | qBittorrent WebUI is single-user. 100 rpm is plenty for active browsing; burst retained at 600 for occasional bulk operations (e.g., moving a whole category). |
| `rate-limit-immich` | 500 → 200 | 2000 → 1500 | Immich mobile upload is the worst case — bulk photo uploads hit the API in parallel. 200 rpm sustained handles steady upload + browsing; 1500 burst handles bulk upload window. |

All three kept `period: 1m` and `sourceCriterion.ipStrategy.depth: 1`.

### What remains unverified

Rate-limit behavior under real 429 conditions cannot be reliably tested from LAN — my burst probes hit TCP shedding from ephemeral-port / SYN pressure rather than the Traefik rate-limiter. Traefik's reload log showed no parse errors at apply time, which is the only deterministic signal available from inside. Empirical 429 verification needs an external source; passive observation over the next week will surface any over-tight limits via legitimate-user complaints or alert noise.

---

## Step 3 — Commit drift + this journal

The working tree had accumulated drift from several prior sessions that hadn't been committed — notably the 2026-03-31 Authelia SSO debugging, the 2026-03-31 Proton Bridge SMTP attempt (failed — kept as documented attempt), the 2026-04-18 Podman storage migration, and the Immich v2.5.6 → v2.6.3 version bump (already running on host, config had not been committed).

Split into logical commits to keep history navigable. This journal ships with commit #1 (the CrowdSec + rate-limit work) so the investigation is paired with the change that caused it.

---

## Follow-ups

- **Observation window** (passive, 24–48h): watch `cscli decisions list` for the first local-origin decision. If none appear after a week of real external traffic, re-examine scenario enablement.
- **Authelia acquisition** (deferred): needs either an image swap or a journal-to-file bridge + `LePresidente/authelia` collection + Authelia config change to write login failures to a file. Own ADR when prioritized.
- **sshd acquisition** (deferred): not worth it until SSH is internet-exposed, which it shouldn't be.
- **Nextcloud circuit-breaker + retry reconciliation** (issue #146): the same class of middleware-interaction problem Immich had. Same logic applies; separate session.
- **Orphaned rate-limit.yml** (issue #136): `config/traefik/dynamic/rate-limit.yml` is referenced nowhere after middleware consolidation; delete.
- **Middleware pruning** (issue #156): audit which middlewares are actually referenced and drop the dead ones.

---

## Lessons

1. **ADR-022 had more downstream debt than I realized.** The socket-activation fix unblocked two separate pieces of security work that had been quietly deferred. Worth re-auditing the other "waiting on source IPs" items I might have forgotten about.
2. **Acquisition doesn't require full coverage to be useful.** Traefik alone covers the entire internet-facing surface — which is where 99% of the interesting threat signal actually lives. sshd and Authelia are defense-in-depth, not primary signal sources.
3. **Whitelist behavior is confusing and worth documenting.** The "lines whitelisted > lines read" metric surprised me until I traced through the three overlapping whitelist sources. Future me will thank present me for the `acquis.yaml` header comment.
4. **"Verified end-to-end" from inside the LAN is a lie.** Any security layer that filters on source IP cannot be empirically verified without an external source. Accept that and plan for passive observation rather than trying to force synthetic verification that lies about reality.
