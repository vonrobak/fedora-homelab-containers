# DNS Probe Cadence + Pi-hole Exporter Session Leak

**Date:** 2026-05-28
**Context:** Started as a network-anomaly investigation — operator noticed periodic `doubleclick.net` queries from fedora-htpc in Pi-hole logs even with browsers closed. Ended with two shipped PRs and a closed issue. Shipped as PR #247 (probe cadence) and PR #248 (session-leak mitigation). #246 filed and closed-as-mitigated in the same session.

## What Happened

### Frame 1 — the doubleclick.net mystery

Operator opened the session asking who was making `A doubleclick.net` queries from `192.168.1.70` (fedora-htpc) at 08:11 local, with no browser windows open. The queries were getting blocked correctly (`status=GRAVITY`) but the operator uses the Pi-hole query log as a forensics surface for network-side anomalies — the steady stream of "blocked ads with no apparent source" was getting in the way.

Initial leads I chased — all dead ends:

- **Firefox in dbus-service mode.** PID 26118 was still alive after the user "closed" the window, running as a GNOME-search backend. Plausible candidate (Pocket recommendations, sponsored top-sites on `about:home`). Killed it. **The queries continued.**
- **`pasta.avx2` (PID 15565)** — Podman's rootless DNS forwarder — was generating heavy traffic to 192.168.1.69:53. But that's the aggregate of all 38 containers; none of their logs contained ad-related strings. False signal.
- **Containers' recent logs** — nothing.

The decisive observation: querying Pi-hole's API directly (via the `pihole_api_token` Podman secret) showed `doubleclick.net` queries arriving on a perfect **15-second cadence**, like clockwork. That's not browser-shaped — that's a daemon-shaped pattern.

15 seconds is the Prometheus default `scrape_interval`. `grep -r doubleclick config/` found `config/blackbox-exporter/blackbox.yml` defining a `dns_blocked` probe module that resolves `doubleclick.net` to verify Pi-hole's gravity blocklist is still sinkholing it. **The culprit was our own monitoring** — exactly what ADR-031 Phase 2 (PR #241) intended: a canary that detects the silent gravity-stale failure class from the 2026-05-21 Pi-hole investigation.

### Frame 2 — probe cadence as a design question

The probe worked as designed, but `dns_blocked` is a **configuration-drift canary**, not a liveness check. Gravity stops working because someone changed config, broke an upstream, or DoH-bypass kicked in — none of those happen on a 15-second timescale. Probing every 15s gave **zero faster detection of any real failure mode** and dirtied the Pi-hole query log the operator uses for live network forensics.

Alert thresholds confirmed there was margin: `DnsResolverFunctionalFail` uses `for: 3m`, `DnsResolverBlocklistRegression` uses `for: 10m`. Stretching the scrape intervals fit comfortably:

- `blackbox-dns-functional`: 15s → **30s** (liveness; outages also surface immediately via failing user queries)
- `blackbox-dns-blocked`: 15s → **5m** (config-drift canary; gravity regressions are slow signals)

Net effect on Pi-hole query log: **8/min → 2.2/min** of blackbox-induced canary noise (-72%). Shipped as PR #247.

### Frame 3 — the second symptom emerges

While checking Pi-hole's rate-limit config (1000 queries/60s per client, easy headroom), I noticed `api.max_sessions: 16` and queried `/api/auth/sessions`. **9 of 16 sessions were active.** Two were from `Go-http-client/1.1` — i.e. `pihole-exporter`. One had been created 16h ago and was *still listed* as active, well past its 30-minute timeout. Sessions weren't being cleaned up.

This matched a separate operator complaint mentioned in passing: "Pi-hole admin panel sometimes returns 'too many requests'." That had been previously assumed to be DNS rate-limiting; it wasn't. It was **API session pool exhaustion**. Filed as #246.

Two distinct issues, surfacing in one investigation:
- **PR #247** — probe cadence tune-down. Independent of the session pool issue (canary DNS load was 8/min, well under DNS rate limits). Justification: respect the operator's use of Pi-hole logs as a forensics tool.
- **#246** — exporter session leak. Real bug, real operational pain.

### Frame 4 — root-causing the session leak

`ekofr/pihole-exporter` (digest-pinned, the only Pi-hole metrics path) re-authenticates when its session expires. I read `internal/pihole/api_client.go`:

```go
func (c *APIClient) ensureAuth() error {
    c.mu.Lock()
    needsAuth := time.Now().After(c.validity)
    c.mu.Unlock()
    if needsAuth {
        return c.Authenticate()  // creates new session, abandons old SID
    }
    return nil
}
```

No `DELETE /api/auth`. `Close()` only releases idle HTTP transports. **Every session-timeout cycle leaks one slot.** Pi-hole v6 sessions expire absolutely from `login_at` (not on inactivity, verified via `valid_until` math), so the exporter creates a fresh session every 30 minutes regardless of activity. Pi-hole doesn't garbage-collect expired sessions from the visible pool either — confirmed by seeing a session from yesterday 21:14 still listed at 09:00 the next morning, well past its `valid_until`.

Searched the upstream repo: **no issue mentions "logout" or "leak"** — the bug is unreported in current form. But upstream #318 ("pihole-exporter endpoint gets slow until it stalls", open since Dec 2025, 10 comments) is the *same root cause* manifesting downstream: once the session pool fills, the exporter's calls back up. Community workarounds are periodic container restarts. Useful confirmation we weren't wrong about the diagnosis; not useful as a path to a fix.

### Frame 5 — choosing the mitigation shape

Five options surfaced. Trade-off summary in #246; the call landed on **A + B**:

- **A: bump `webserver.session.timeout` 1800 → 86400.** Cuts the leak rate 48×. Doesn't fix the bug; just makes it churn less.
- **B: hourly sweeper** — DELETEs expired sessions. Doesn't fix the bug; makes the pool self-healing.
- *(C — fork the exporter and PR upstream — deferred. Right long-term move; not blocking.)*

A required `PATCH /api/config/...` which the app-password session can't do (`app_sudo: false`). Operator applied it manually via the admin UI. New sessions then showed a 24h `valid_until`, confirming the change took.

B was scripted as `pihole-session-sweeper.sh` + a systemd timer. Two design constraints worth noting:

- **The sweeper never adds to the leak it solves.** `trap cleanup EXIT` always calls `DELETE /api/auth` on its own session. Idempotent on every exit path including signal-kill.
- **`PrivateTmp=yes` had to come off the service unit.** Rootless podman's pause-process can't be re-entered from a sandboxed /tmp — fails with `cannot re-exec process to join the existing user namespace`. The script worked manually and failed via systemd until the flag was removed. New entry in `[[project_platform_gotchas]]`.

Added two alerts (`PiHoleSessionPoolNearExhaustion`, `PiHoleSessionSweeperStale`) — the metric alone, without an alert, is incomplete because a silent sweeper failure is invisible until the pool fills. The alerts catch exactly the failure modes the sweeper does not self-heal.

Shipped as PR #248. First sweep cleaned 1 expired session; ratio ended at 4/16 = 0.25; both alerts inactive.

## Decisions Made + Trade-offs

### Stretching probe cadence vs accepting log noise

**Decision:** stretch `dns_blocked` 15s → 5m (the wide one) and `dns_functional` 15s → 30s (the conservative one), via per-job overrides rather than a global change.

**Trade-off:** in the worst case, a gravity regression is detected 5 minutes later than before. Within the alert's `for: 10m` window — i.e. **no detection-latency change in practice**. The operator gains a usable forensics log.

**Alternative considered:** keep cadence, document the noise as "expected." Rejected because the operator's use of the log surface is itself a non-trivial system requirement, even if it isn't in any spec.

### Operator-facing observability as a first-class concern

This is the meta-decision behind PR #247. Probe-cadence choices got framed as "what does Prometheus need" not "what does the Pi-hole query log look like to a human reading it." The latter is also a system surface. **Two operator-visible observability tools (Pi-hole log + Grafana) compete for the same probe budget.** Cadence chosen for the higher-resolution tool (Pi-hole log) wins because it's also the cheaper one (just less Prometheus data, not less detection).

### Mitigation vs upstream fix for the session leak

**Decision:** ship local mitigation (A+B) now; defer upstream PR.

**Trade-off:** we maintain a ~130-line shell script + a timer that wouldn't exist if the exporter were fixed at source. In exchange: time-to-resolution measured in hours instead of weeks-to-months (upstream fork → PR → maintainer review → release → digest re-pin in our repo).

**The trade-off works because the sweeper is small, self-contained, and its existence isn't load-bearing on anything else.** If upstream ships a fix tomorrow, we delete four files and move on. If they don't, the sweeper is bounded maintenance — a one-page script with two alerts is not technical debt of the kind that compounds.

This is a recurring pattern in self-hosted infrastructure: **ship-the-workaround, then revisit upstream**. The alternative (block on upstream) externalizes your operational health to people who don't share your incident pressure.

### Applying A vs skipping it

Initially proposed both A and B because they're independently good. After hitting the `app_sudo: false` permission boundary, paused to ask: is A actually needed if B exists?

**Decision:** apply both anyway.

**Rationale:** B (hourly sweeper) is sufficient to prevent pool exhaustion. A (24h timeout) shifts the auth churn from 48/day to 1/day — that's a 48× drop in entries the operator sees in their forensics log, again the same observability surface PR #247 was protecting. A is operationally redundant *if and only if* B works flawlessly. Layering them costs nothing and provides a second line of defense.

### Bundling the alerts with the sweeper PR

**Decision:** include `pihole-session-alerts.yml` in PR #248 rather than splitting.

**Trade-off:** slightly wider PR scope. The two are tightly coupled though — the metric exists *because* the sweeper writes it; the alert exists *because* the metric exists. Splitting would have meant a metric in production with no alerting on it, which is the silent-failure shape we already deal with elsewhere in the repo (see `project_platform_gotchas` entry on dead `.prom` metrics).

### Sacrificing `PrivateTmp` for podman compatibility

**Decision:** drop `PrivateTmp=yes` from the service unit, document the reason in a comment.

**Trade-off:** the script can technically see `/tmp`. The script writes nothing to `/tmp` and reads nothing from it, so the security delta is theoretical. The alternative was either (a) running as a system service (loses rootless), (b) shelling out via `XDG_RUNTIME_DIR`-aware env-passing (more brittle), or (c) reading the secret via a different mechanism. None were worth the complexity for this script's blast radius.

## Lessons Learned

### On hunting periodic queries

- **The pattern's shape carries diagnostic information.** A perfect 15-second clockwork interval ruled out browsers immediately — even idle Firefox jitters its DNS prefetch. Daemons don't. **First filter on "what shape of process can emit exactly this cadence" before chasing individual processes.**
- **Multiple visibility layers were necessary because Podman's `pasta` NAT blinds the upstream resolver.** Pi-hole sees all 38 containers' DNS as coming from the host IP, with no per-container attribution. So the investigation had to combine: (1) host process state, (2) host open sockets, (3) container-level grep over recent logs, (4) Pi-hole's own query log via API, (5) source code reading. No single layer would have closed it.
- **Search upstream for the *symptom* not the *cause*.** I found upstream `eko/pihole-exporter#318` by searching for "session"; the issue title is "endpoint gets slow until it stalls" — same root cause expressed downstream. **If you've named the cause, the upstream may not have yet.** Search both vocabularies.

### On observability serving humans

- **Pi-hole's query log is a forensics tool, not just a metric source.** It's read by the operator during anomaly investigation. Probe noise pollutes it. This kind of *operator-visible* observability surface needs its own design budget, separate from "what does Prometheus need."
- **Probe cadence should match the SLI denominator, not a default.** Liveness probes deserve fast cadence; config-drift canaries deserve slow cadence. They got conflated under the global 15s scrape_interval. Per-job overrides fix it without touching the global default.
- **A metric without an alert is silent failure.** Decided this is a hard rule for the repo: if a `.prom` is written, an alert exists that catches a stuck or absent value. Bundled into PR #248 rather than being deferred.

### On root-causing third-party bugs

- **Read the source.** Behavior alone (sessions cycling every 30 minutes) suggested re-auth without logout, but it took finding `ensureAuth()` in `internal/pihole/api_client.go` to *prove* it. Behavior could have been a Pi-hole-side bug, a network race, a Go HTTP client quirk — only source confirmed which.
- **An upstream "active" project is not the same as "responsive to fixes."** `eko/pihole-exporter` had a commit 2026-05-03 — three weeks before this session. The issue tracker shows #318 unresolved since December despite ten comments. Active development ≠ active triage. Plan around the maintainer bandwidth you observe, not the badge you wish for.
- **Mitigations should never re-introduce the problem they're mitigating.** The sweeper authenticates to delete expired sessions; if it didn't log itself out, it would *be* the leak. The `trap cleanup EXIT` line is small but load-bearing — review noticed it; the absence would have been a silent regression introducing the same bug it fixes.

### On systemd user services + rootless podman

- **`PrivateTmp=yes` breaks rootless-podman calls inside user services.** Hit cleanly this session; documented in `[[project_platform_gotchas]]`. Default for any new user-service that touches podman should be: omit `PrivateTmp`, keep `NoNewPrivileges`. System services are unaffected.
- **`podman restart <name>` of a quadlet-managed container terminates without restart.** Hit while refreshing the bind mount in PR #247 — container vanished. The quadlet's generated systemd unit is the supervisor; `podman restart` is opaque to it. Recovery: `systemctl --user daemon-reload && systemctl --user start <unit>.service`. **Always use `systemctl --user restart`, never `podman restart`, for quadlets.** Added to memory.
- **Single-file bind mounts + atomic-replace edits = stale view inside container.** Recurred for the third time in three months (Loki in March, Prometheus twice in May). The fix is always the same (`systemctl --user restart`); the real fix is to convert single-file mounts to directory mounts where possible. Worth a future cleanup pass.

### On Pi-hole v6 API constraints

- **App-password sessions can't modify config** (`api.app_sudo: false` by default). `PATCH /api/config/...` returns 403. The `pihole_api_token` Podman secret is an app password — so the exporter, the sweeper, and any future config-as-code tooling using that secret are **read-only**. Three workaround paths exist (main admin password as a separate secret, enable `app_sudo: true`, or SSH-edit `pihole.toml`). Relevant for any future ADR-031 Phase 3+ work that wants to drive Pi-hole settings from this repo. Added to `[[project_dns_resolver_ha]]`.
- **Two rate-limit systems coexist.** DNS-side rate-limiting (1000 queries / 60s per client) and HTTP-side session pool (`max_sessions: 16`). The "too many requests" admin-UI error came from the HTTP side. Easy to misdiagnose if you only check the DNS side.

### On working through this session

- **Two related but independent improvements deserve two PRs.** The probe-cadence change (#247) and the session sweeper (#248) both reduce Pi-hole admin-UI symptoms but address different root causes (canary noise vs session pool). Bundling would have made bisecting a future regression harder. Two PRs, two CI runs, two clean revert paths.
- **The operator's use of an observability tool is itself a system requirement.** Discovered mid-session. Reshaped the probe-cadence decision. **Periodically ask the operator what they actually look at, and design around that, not around what Prometheus consumes.**
- **Closing an issue as "mitigated" with deferred follow-up is honest.** #246 isn't "fixed" — the upstream bug still exists. But operationally it's resolved. The closing comment documents what shipped and what's deferred (upstream fork PR), so a future reader can pick up the thread without having to re-derive the context.

## Outputs

| Artifact | Notes |
|---|---|
| **PR #247** (`52287ed`) | Per-job scrape_interval overrides: `dns_functional` 30s, `dns_blocked` 5m. -72% Pi-hole query-log noise from blackbox. |
| **PR #248** (`b3aee38`) | Pi-hole session sweeper: script + systemd timer + 2 alerts. Self-healing pool. |
| **Manual change on Pi-hole** | `webserver.session.timeout` 1800 → 86400. Applied via admin UI by operator (app-password sessions lack `app_sudo`). |
| **Issue #246** | Filed mid-session; closed-as-mitigated end-of-session with deferred upstream-PR follow-up. |
| **Memory updates** | `project_platform_gotchas` +2 entries (PrivateTmp+podman, `podman restart` quadlet-kill); `project_dns_resolver_ha` +1 entry (app-password read-only constraint). |

## See Also

- ADR-031 (`docs/00-foundation/decisions/2026-05-25-ADR-031-dns-resolver-first-class-and-ha.md`) — Phase 2 introduced the probes whose cadence we tuned here.
- `[[project_platform_gotchas]]` — new entries for the two podman+systemd gotchas hit in this session.
- `[[project_dns_resolver_ha]]` — added the Pi-hole `app_sudo: false` constraint.
- Upstream `eko/pihole-exporter#318` — same root cause manifesting as exporter slowness; useful reference if the upstream PR happens.
