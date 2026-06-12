# Lessons

Distilled, hard-won lessons from the development and operation of this homelab (Oct 2025 →).
Each entry is a generalizable insight that should change future decisions — extracted from
journals (`98-journals/`), incident reports and postmortems (`99-reports/`). The journals hold
the full narratives; this document holds the conclusions.

**Audience:** both human operators and LLM sessions. Read the Index for a fast scan; read the
full entry before acting in that domain. Superseded lessons are kept at the end — they record
what we used to believe and why we stopped; do not re-recommend them.

## How to add a lesson

A lesson qualifies if **all** of these hold:
1. **Generalizable** — it transfers beyond the single incident that taught it.
2. **Non-obvious** — it contradicts a reasonable default assumption, or was learned at real cost.
3. **Decision-changing** — knowing it would alter a future design, deployment, or debugging step.
4. **Not already codified** — if a hook, script, or CLAUDE.md convention already enforces it, link the lesson that motivated the tooling but don't duplicate enforced rules.

Procedure:
1. Take the next sequential ID (`L-NNN`). IDs are permanent — never renumber.
2. Write the entry in the matching category section using the template below. Keep **Why** to 2–4 lines; the source document carries the rest.
3. Add a one-line entry to the Index.
4. When a lesson stops being true, do **not** delete it: set its status, move the entry to the *Superseded lessons* section, and add one line naming what replaced it (ADR, redesign, or newer lesson ID).

Template:
```markdown
### L-NNN — <short imperative title>
**Lesson:** <one sentence, generalizable>
**Why:** <2–4 lines: the incident or reasoning that taught it>
**Sources:** [<file>](../98-journals/<file>.md) · **Date:** YYYY-MM-DD · **Status:** Active
```

## Index

**Container & Quadlet Operations**
- L-001 Quadlet resource limits belong in `[Service]`, not `[Container]`
- L-002 Memory limits must come from observed usage and be revisited as the system grows
- L-003 A healthcheck that cannot run is worse than no healthcheck
- L-004 Healthchecks that spawn subprocesses amplify memory pressure
- L-005 `Restart=on-failure` is blind to wedged-but-running services
- L-006 Control quadlet-managed containers via systemctl, never podman commands
- L-007 Podman network flag changes need `network rm`, not a restart
- L-008 Podman storage migration: `podman unshare` and db.sql path coupling
- L-009 Stage boot with Startup weights and `After=` — zero production cost
- L-010 Single-file bind-mounts and config reloads: restart the consumer
- L-011 Health checks should target unauthenticated endpoints with GET
- L-012 Don't publish ports for internal-only services
- L-013 `podman inspect` shows secret names, not values — that is correct behavior

**Storage & Backup**
- L-014 Backups are theoretical until a restore is proven
- L-015 Restore tests must bound bytes, and a silent SKIP is a failure
- L-016 Clean up unconditionally; preserve logs, not data copies
- L-017 Independent backup layers protect against different failure modes
- L-018 Soft-delete reversibility needs detection to be useful
- L-019 Organize database storage by recovery model (ADR-029 three-tier)
- L-020 Measure backup feasibility under cold-cache production conditions
- L-021 Backup failures must alert within a day, not surface during incidents
- L-022 Retention-policy gaps between tiers force full sends — plan for them

**Security Architecture**
- L-023 Rootless port-forwarding source-NAT silently collapses IP-based security
- L-024 Defense-in-depth claims must be scoped to the paths they actually cover
- L-025 Verify routing applies the intended middleware tier on high-value targets
- L-026 Trusted-proxy header configuration is a security boundary
- L-027 Credentials go in Podman secrets, never `Environment=` lines
- L-028 Webhook endpoints need authentication even on localhost
- L-029 Bind published ports to the host LAN IP, not 0.0.0.0
- L-030 Path-based access control requires a full endpoint audit before deploy

**Monitoring & Alerting Design**
- L-031 Alert on absence of success, not presence of errors
- L-032 Prefer native metrics over log-extracted metrics
- L-033 Exporter liveness is not service liveness — and catch-all rules override design intent
- L-034 Exporters that do synchronous work need explicit scrape-timeout sizing
- L-035 Aggregate across label sets; stale TSDB series cause flapping and false alerts
- L-036 Gauge-based alerts need time-bounded conditions
- L-037 Calibrate thresholds to the actual technology and require impact conditions
- L-038 Burn rate must measure the current window, not alias a long-term average
- L-039 An SLO without a burn-rate alert is half a defense
- L-040 Multi-window, multi-tier burn-rate alerting beats static thresholds
- L-041 Distinguish "many events" from "one event re-notified"
- L-042 A single persistent known-false alert erodes trust in everything
- L-043 Drop unconsumed metrics at ingestion with an allowlist
- L-044 Route architectural-state alerts to digests, not incident channels
- L-045 Textfile metrics must avoid labels the scrape job will clobber
- L-046 Probe cadence per check type — and human-facing log surfaces are requirements too
- L-047 Failed automated remediation must escalate as loudly as the original alert

**Debugging & Forensic Methodology**
- L-048 Technical validation is not architectural suitability
- L-049 Smoke-test the real workload before declaring success
- L-050 Absence of logs is itself a diagnostic signal
- L-051 Forensic confidence requires positive evidence across three layers
- L-052 Idle-but-hot means inspect the physical environment
- L-053 Verify unexpected SSH host keys out-of-band before suspecting MITM
- L-054 Map a compound failure's full chain before attempting fixes
- L-055 Verify API/version compatibility before deploying integrations
- L-056 LAN-side defaults silently distort DNS and DHCP behavior

**Architecture & Design Process**
- L-057 Ship the reversible change first; migrate only on measured evidence
- L-058 Never build security-critical behavior on undefined ordering
- L-059 Decommissioning is a valid engineering outcome
- L-060 Decommissioning is complete only when every trace is removed
- L-061 Don't build orchestration before usage proves the need
- L-062 Predictions without validation loops are silent assumptions
- L-063 Mitigate third-party defects in independent layers
- L-064 Defaults encode someone else's context — recalibrate to your own

**Process & Collaboration**
- L-065 Document decisions while they are fresh
- L-066 Capture negative constraints explicitly
- L-067 A pre-change backup turns failures into two-minute rollbacks
- L-068 Anything not codified will eventually be lost
- L-069 Ansible check mode has blind spots for install-dependent tasks

**Superseded**
- L-070 Float tags and let AutoUpdate keep images fresh *(superseded by ADR-030/036)*
- L-071 Shell-script BTRFS backup automation with NOPASSWD sudo *(superseded by Urd, ADR-021)*
- L-072 Alert when error lines appear in logs *(superseded by L-031/L-032)*
- L-073 Static per-metric thresholds for service health *(superseded by L-040)*

---

## Container & Quadlet Operations

### L-001 — Quadlet resource limits belong in `[Service]`, not `[Container]`
**Lesson:** systemd resource directives (`MemoryMax`, `MemoryHigh`, CPU/IO weights) must be placed in the `[Service]` section of a quadlet; the `[Container]` section only accepts Podman keys.
**Why:** Adding `MemoryMax` under `[Container]` fails with "unsupported key" — resource control is a systemd cgroup feature, not a container runtime feature. House convention: `MemoryHigh` ≈ 90% of `MemoryMax` for throttle-before-OOM headroom.
**Sources:** [2026-01-09-memory-limit-standardization](../98-journals/2026-01-09-memory-limit-standardization.md) · **Date:** 2026-01-09 · **Status:** Active

### L-002 — Memory limits must come from observed usage and be revisited as the system grows
**Lesson:** A memory limit set as a round number at deploy time becomes a time bomb when the workload grows with the system; derive limits from observed steady-state plus headroom and re-check them when the fleet changes.
**Why:** cAdvisor's 256M limit was fine at deployment but, at 30 containers, the service hit it in ~10 hours of uptime — every restart just reset the countdown to an OOM death spiral.
**Sources:** [2026-03-23-cadvisor-oom-death-spiral-postmortem](../98-journals/2026-03-23-cadvisor-oom-death-spiral-postmortem.md) · **Date:** 2026-03-23 · **Status:** Active

### L-003 — A healthcheck that cannot run is worse than no healthcheck
**Lesson:** A `HealthCmd` that has no possibility of succeeding (e.g. `wget` on a distroless image) produces a permanent false "unhealthy", disables restart-based self-heal, and masks real failures behind a known-bad status.
**Why:** pihole-exporter carried a wget healthcheck on a distroless image; when the exporter actually wedged, the perpetual "unhealthy" state carried no signal and no restart fired for three days. External, metrics-based health detection replaced it.
**Sources:** [2026-06-07-pihole-false-down-postmortem-private](../99-reports/2026-06-07-pihole-false-down-postmortem-private.md) · **Date:** 2026-06-07 · **Status:** Active

### L-004 — Healthchecks that spawn subprocesses amplify memory pressure
**Lesson:** Healthchecks that fork (wget/curl) under memory pressure create a positive feedback loop: checks can't complete, zombies accumulate, pressure rises, checks slow further.
**Why:** During the cAdvisor OOM spiral, 30-second wget healthchecks left 668 zombie processes that accelerated the very exhaustion they were meant to detect.
**Sources:** [2026-03-23-cadvisor-oom-death-spiral-postmortem](../98-journals/2026-03-23-cadvisor-oom-death-spiral-postmortem.md) · **Date:** 2026-03-23 · **Status:** Active

### L-005 — `Restart=on-failure` is blind to wedged-but-running services
**Lesson:** Exit-status-based restart policies cannot heal a process that degrades without exiting; pair them with `OOMPolicy=kill` (so OOM kills produce a failed state that actually triggers restart) and external functional health detection for wedge states.
**Why:** Default `OOMPolicy=stop` leaves a unit "running" with its main PID gone. Separately, a wedged exporter (latency step-change 0.26s → >10s, process alive) served dead air for three days because nothing watched function, only lifecycle.
**Sources:** [2026-04-29-quadlet-hardening-sweep](../98-journals/2026-04-29-quadlet-hardening-sweep.md), [2026-06-07-pihole-false-down-postmortem-private](../99-reports/2026-06-07-pihole-false-down-postmortem-private.md) · **Date:** 2026-06-07 · **Status:** Active

### L-006 — Control quadlet-managed containers via systemctl, never podman commands
**Lesson:** `podman stop` on a quadlet-managed container succeeds and is immediately undone — systemd restarts the unit; use `systemctl --user stop`, and stop socket units first for socket-activated services.
**Why:** During the storage migration, `podman stop --all` returned cleanly and every container was back within seconds. Traefik additionally required stopping `http.socket`/`https.socket` first (ADR-022).
**Sources:** [2026-04-18-podman-storage-migration-execution](../98-journals/2026-04-18-podman-storage-migration-execution.md) · **Date:** 2026-04-18 · **Status:** Active

### L-007 — Podman network flag changes need `network rm`, not a restart
**Lesson:** Changing network properties (e.g. `Internal=true`) in a `.network` quadlet does not apply on service restart — the existing network is reused as-is; remove the network explicitly and let it recreate.
**Why:** After adding `Internal=true`, services restarted "active" but `podman network inspect` still showed `Internal=false`; create-with-ignore does not re-apply flags to existing networks.
**Sources:** [2026-04-21-network-ingress-egress-hardening](../98-journals/2026-04-21-network-ingress-egress-hardening.md) · **Date:** 2026-04-21 · **Status:** Active

### L-008 — Podman storage migration: `podman unshare` and db.sql path coupling
**Lesson:** Copying rootless Podman storage requires `podman unshare` (plain rsync silently misses subordinate-UID files), and Podman 5.x bakes storage paths into its SQLite db, which must be updated manually after a move.
**Why:** A plain rsync copied 99.8% of files with no error — 551 files inside subuid-owned dirs were silently skipped, caught only by exact file-count comparison. Then `podman info` failed on "database configuration mismatch" until `DBConfig` paths were UPDATEd.
**Sources:** [2026-04-18-podman-storage-migration-execution](../98-journals/2026-04-18-podman-storage-migration-execution.md) · **Date:** 2026-04-18 · **Status:** Active

### L-009 — Stage boot with Startup weights and `After=` — zero production cost
**Lesson:** When a full container fleet fans out at boot, cold-cache contention causes timeouts; graduated `StartupCPUWeight`/`StartupIOWeight` tiers plus targeted `After=` dependencies stage startup gracefully, and the Startup* weights expire at `default.target` so production behavior is untouched.
**Why:** Post-update cold boots crashed podman and the terminal (SIGABRT at 60s timeouts). Tiering keystones (weight 200) over apps (100) over exporters (50) produced timeout-free boots. See ADR-035.
**Sources:** [2026-05-27-post-update-boot-storm-and-homepage-decom](../98-journals/2026-05-27-post-update-boot-storm-and-homepage-decom.md) · **Date:** 2026-05-27 · **Status:** Active

### L-010 — Single-file bind-mounts and config reloads: restart the consumer
**Lesson:** A config change does nothing until the consuming service re-reads it — and single-file bind-mounts edited from the host keep the old inode, so SIGHUP/reload is not enough; restart the service.
**Why:** A fixed alert rule sat unloaded for 96 hours because Prometheus was never reloaded; later, an edited bind-mounted `prometheus.yml` survived `reload` untouched (inode semantics) and required a full restart.
**Sources:** [2026-01-21-alert-flapping-root-cause-fix](../98-journals/2026-01-21-alert-flapping-root-cause-fix.md), [2026-05-27-adr-031-phase2-and-dns-noise-private](../99-reports/2026-05-27-adr-031-phase2-and-dns-noise-private.md) · **Date:** 2026-05-27 · **Status:** Active

### L-011 — Health checks should target unauthenticated endpoints with GET
**Lesson:** Point healthchecks at endpoints that need no auth and no business logic, and use a real GET (`wget -O /dev/null`), not `--spider` HEAD requests that many endpoints reject.
**Why:** A check against a protected auth endpoint failed structurally; separately, `wget --spider` against Node Exporter's GET-only `/metrics` generated 339k broken-pipe errors in 24 hours.
**Sources:** [2025-11-10-force-multiplier-week-days-1-5-summary](../98-journals/2025-11-10-force-multiplier-week-days-1-5-summary.md), [2026-01-08-monitoring-alert-fatigue-fixes](../98-journals/2026-01-08-monitoring-alert-fatigue-fixes.md) · **Date:** 2026-01-08 · **Status:** Active

### L-012 — Don't publish ports for internal-only services
**Lesson:** Services reached only over container networks must not have `PublishPort` at all — published ports add host-port race conditions on restart and silently widen exposure.
**Why:** cAdvisor published 8080 despite only Prometheus (same network) consuming it, causing "address already in use" races on restart; internal DNS (`http://cadvisor:8080`) was the correct path all along.
**Sources:** [2025-11-10-force-multiplier-week-days-1-5-summary](../98-journals/2025-11-10-force-multiplier-week-days-1-5-summary.md) · **Date:** 2025-11-10 · **Status:** Active

### L-013 — `podman inspect` shows secret names, not values — that is correct behavior
**Lesson:** With `Secret=name,type=env,target=VAR`, inspect output shows the secret reference rather than the resolved value; this looks like the secret "wasn't delivered" but it was — verify by service behavior, not by expecting plaintext in inspect.
**Why:** Debugging a new exporter stalled on the assumption the token never arrived; comparing against known-working secret-using services showed identical display. The mechanism was fine.
**Sources:** [2026-05-27-adr-031-phase2-and-dns-noise-private](../99-reports/2026-05-27-adr-031-phase2-and-dns-noise-private.md) · **Date:** 2026-05-27 · **Status:** Active

## Storage & Backup

### L-014 — Backups are theoretical until a restore is proven
**Lesson:** Backup infrastructure that has never completed a restore test provides confidence, not protection; schedule the first restore test as part of shipping the backup system, not months later.
**Why:** External backups ran for two months before the first restore test. Any disaster in that window would have discovered restore defects at the worst possible moment. The later tmpfs incident (L-015) proved restore tests find real defects.
**Sources:** [2026-01-03-disaster-recovery-verification-milestone](../98-journals/2026-01-03-disaster-recovery-verification-milestone.md) · **Date:** 2026-01-03 · **Status:** Active

### L-015 — Restore tests must bound bytes, and a silent SKIP is a failure
**Lesson:** Sample-based restore validation must bound total bytes (not file count) with an explicit preflight space check, and must hard-distinguish SKIP from PASS — a test that quietly validates zero files reports false confidence.
**Why:** "50 random files" from a media subvolume exceeded the 16 GB tmpfs, exhausting RAM/swap; meanwhile three subvolumes reported green while validating 0 files because `find` failed silently under space pressure.
**Sources:** [2026-05-24-incident-restore-test-tmpfs-exhaustion](../99-reports/2026-05-24-incident-restore-test-tmpfs-exhaustion.md) · **Date:** 2026-05-24 · **Status:** Active

### L-016 — Clean up unconditionally; preserve logs, not data copies
**Lesson:** Scratch cleanup must run via `trap EXIT` regardless of outcome — cleanup-only-on-success leaves the biggest messes exactly when failures occur; keep a log/manifest of what failed, not the failed data itself.
**Why:** A failed restore test preserved 13 GB of scratch data "for debugging" that was never debugged; it sat as debris (in tmpfs!) for weeks.
**Sources:** [2026-05-24-incident-restore-test-tmpfs-exhaustion](../99-reports/2026-05-24-incident-restore-test-tmpfs-exhaustion.md) · **Date:** 2026-05-24 · **Status:** Active

### L-017 — Independent backup layers protect against different failure modes
**Lesson:** Combine mechanisms with uncorrelated failure modes — application soft-delete, database dumps, filesystem snapshots — so that any single corruption path leaves at least one recovery route.
**Why:** When 4,223 Immich photos were mass-marked deleted, three independent recovery options existed (DB UPDATE, pg_dump restore, BTRFS snapshot); recovery took minutes and the data was never truly at risk.
**Sources:** [2025-11-23-immich-data-loss-incident-report](../98-journals/2025-11-23-immich-data-loss-incident-report.md) · **Date:** 2025-11-23 · **Status:** Active

### L-018 — Soft-delete reversibility needs detection to be useful
**Lesson:** Soft-deletes make mass-deletion reversible, but only monitoring (e.g. asset-count drop alerts) makes it *recoverable in time* — reversibility without detection still means discovering the loss by accident.
**Why:** The Immich mass-deletion was trivially reversible but went unnoticed for 8+ hours until a human saw an empty library; a count-drop alert would have caught it in minutes.
**Sources:** [2025-11-23-immich-data-loss-incident-report](../98-journals/2025-11-23-immich-data-loss-incident-report.md) · **Date:** 2025-11-23 · **Status:** Active

### L-019 — Organize database storage by recovery model (ADR-029 three-tier)
**Lesson:** Classify data stores by how they are recovered — snapshot-backed (COW), dump-backed (NOCOW), or regenerable (no backup) — and let the BTRFS treatment follow the recovery model, not the data type.
**Why:** Two databases sat in a NOCOW subvolume excluded from snapshots with *zero* backup of any kind; the mismatch between filesystem treatment and recovery assumption was invisible until audited.
**Sources:** [2026-05-22-db-storage-three-tier-and-dump-backbone-phase-a](../98-journals/2026-05-22-db-storage-three-tier-and-dump-backbone-phase-a.md) · **Date:** 2026-05-22 · **Status:** Active

### L-020 — Measure backup feasibility under cold-cache production conditions
**Lesson:** Feasibility tests run warm-cache and in isolation will mislead; measure under the page-cache and I/O conditions the job will actually face in its nightly slot.
**Why:** A warm-cache test said pausing Loki for backup cost ~40s; the first real nightly run — cold cache, after a 1.5 GB Prometheus dump evicted the page cache — froze Loki for 15 minutes.
**Sources:** [2026-05-22-db-storage-three-tier-and-dump-backbone-phase-a](../98-journals/2026-05-22-db-storage-three-tier-and-dump-backbone-phase-a.md) · **Date:** 2026-05-22 · **Status:** Active

### L-021 — Backup failures must alert within a day, not surface during incidents
**Lesson:** "Last successful backup older than 24h" must be an alert; discovering backup failure by manual inspection means the observability is missing, and the gap compounds daily.
**Why:** Backup automation failed silently for four days (a sudo/terminal issue in a systemd user service — user services cannot prompt for passwords; sudoers `NOPASSWD` rules with absolute paths are required) before anyone noticed.
**Sources:** [2025-11-12-backup-automation-fix-session-report](../98-journals/2025-11-12-backup-automation-fix-session-report.md) · **Date:** 2025-11-12 · **Status:** Active

### L-022 — Retention-policy gaps between tiers force full sends — plan for them
**Lesson:** When local and external snapshot retention diverge, common ancestry periodically disappears and incremental send degrades to full send; this is an accepted cost of independent retention, so budget the time and bandwidth rather than treating it as a fault.
**Why:** 4-week local vs 6-month external retention meant ~4 full 1.1 TB sends per year (~2h15m each) — expected behavior once understood, alarming when first observed.
**Sources:** [2026-01-03-disaster-recovery-verification-milestone](../98-journals/2026-01-03-disaster-recovery-verification-milestone.md) · **Date:** 2026-01-03 · **Status:** Active

## Security Architecture

### L-023 — Rootless port-forwarding source-NAT silently collapses IP-based security
**Lesson:** Any control keyed on client IP (reputation, rate limits, lockouts) is dead if the ingress path NATs the source address — verify empirically what source IP the proxy actually sees; with rootless Podman `PublishPort`, it sees an internal Podman IP, and systemd socket activation is the fix that preserves real client IPs without going rootful.
**Why:** All external traffic arrived at Traefik as one internal IP; one phone's app cold-start exhausted the *global* rate budget, and CrowdSec/per-IP limits had been non-functional at the perimeter despite being designed in (ADR-008). Socket activation (ADR-022) restored real IPs with a trivially reversible change.
**Sources:** [2026-04-12-nat-security-model-violation](../99-reports/2026-04-12-nat-security-model-violation.md), [2026-04-16-nat-remediation-research](../99-reports/2026-04-16-nat-remediation-research.md) · **Date:** 2026-04-12 · **Status:** Active

### L-024 — Defense-in-depth claims must be scoped to the paths they actually cover
**Lesson:** A layered security model only describes the traffic that traverses all layers; services that bypass SSO with native auth operate with fewer layers, and the documentation must say so explicitly rather than implying uniform coverage.
**Why:** 7 of 16 exposed services bypass Authelia by design (client compatibility); for those, perimeter reputation plus app-layer auth is the whole defense. The trade-off is sound but invalidates blanket "five-layer" claims.
**Sources:** [2026-03-09-external-security-assessment](../99-reports/2026-03-09-external-security-assessment.md) · **Date:** 2026-03-09 · **Status:** Active

### L-025 — Verify routing applies the intended middleware tier on high-value targets
**Lesson:** Defining a strict middleware (e.g. a 5/min auth rate limit) is worthless if the router references the lenient one; audit router→middleware bindings against intent, especially for credential stores.
**Why:** Vaultwarden's router applied the general 100/min limit while the purpose-built 5/min auth limiter sat unused in middleware.yml — the intended protection was silently bypassed.
**Sources:** [2026-03-09-external-security-assessment](../99-reports/2026-03-09-external-security-assessment.md) · **Date:** 2026-03-09 · **Status:** Active

### L-026 — Trusted-proxy header configuration is a security boundary
**Lesson:** Apps behind a reverse proxy must trust forwarded headers (`X-Forwarded-For`/`-Proto`) from the proxy's IPs only; trusting everything enables IP spoofing and HTTPS-downgrade, trusting nothing breaks client-IP logic.
**Why:** Nextcloud's trusted_proxies setting was flagged critical during deployment review: mis-set in either direction it silently corrupts both security decisions and audit trails.
**Sources:** [2025-12-20-nextcloud-deployment-and-ocis-decommission](../98-journals/2025-12-20-nextcloud-deployment-and-ocis-decommission.md) · **Date:** 2025-12-20 · **Status:** Active

### L-027 — Credentials go in Podman secrets, never `Environment=` lines
**Lesson:** `Environment=VAR=password` in a quadlet is readable via `podman inspect`, `systemctl cat`, and journal output; use `Secret=name,type=env,target=VAR`, and audit for consistency — mixed practice across services signals unaudited debt.
**Why:** A credential audit found 6 plaintext passwords in two services' quadlets while three other services did it correctly; the inconsistency itself was the tell.
**Sources:** [2025-12-20-nextcloud-configuration-audit](../99-reports/2025-12-20-nextcloud-configuration-audit.md), [credential-audit-20251230](../99-reports/credential-audit-20251230.md) · **Date:** 2025-12-30 · **Status:** Active

### L-028 — Webhook endpoints need authentication even on localhost
**Lesson:** An unauthenticated command-accepting endpoint is an exploit primitive regardless of bind address; HMAC validation, per-type rate limiting, and rejection logging are baseline, and "localhost is safe" stops being true the moment the pattern is copied or the topology changes.
**Why:** The remediation webhook accepted unauthenticated alert payloads on 127.0.0.1:9096 — any local process could trigger remediation playbooks at will.
**Sources:** [2025-12-25-remediation-critical-review](../99-reports/2025-12-25-remediation-critical-review.md) · **Date:** 2025-12-25 · **Status:** Active

### L-029 — Bind published ports to the host LAN IP, not 0.0.0.0
**Lesson:** Ports that must be published should bind a specific host address so that a firewall mistake degrades to LAN exposure, not Internet exposure.
**Why:** Jellyfin and Home Assistant bound 0.0.0.0 across every interface; rebinding to the LAN IP made the firewall a second layer instead of the only layer.
**Sources:** [2026-04-21-network-ingress-egress-hardening](../98-journals/2026-04-21-network-ingress-egress-hardening.md) · **Date:** 2026-04-21 · **Status:** Active

### L-030 — Path-based access control requires a full endpoint audit before deploy
**Lesson:** When some routes are public and some protected, enumerate every route and API call the app's workflows touch *before* deployment; discovering missing bypass rules through user-facing failures is slow and risks exposure windows.
**Why:** Gathio needed five iterative Authelia-bypass additions (assets, creation POST, viewing, RSVP, comments), each found via a broken user workflow that upfront route analysis would have caught.
**Sources:** [2026-01-14-gathio-deployment-security-analysis](../99-reports/2026-01-14-gathio-deployment-security-analysis.md) · **Date:** 2026-01-14 · **Status:** Active

## Monitoring & Alerting Design

### L-031 — Alert on absence of success, not presence of errors
**Lesson:** "Error lines appeared" accumulates false positives from log rotation, re-processing, and format drift; "the success counter stopped incrementing" is self-healing and rotation-proof — prefer `changes(success_total[w]) == 0` over `rate(failure_total[w]) > x` for log-derived signals.
**Why:** Log rotation made Promtail re-process history, spiking failure counters and firing auth-attack and cron-failure alerts when real failures were zero (one counter "saw" more events in an hour than it had ever recorded — mathematically impossible, proving the artifact).
**Sources:** [alert-false-positives-analysis-2026-01-16](../99-reports/alert-false-positives-analysis-2026-01-16.md), [alert-redesign-proposal](../99-reports/alert-redesign-proposal.md) · **Date:** 2026-01-16 · **Status:** Active

### L-032 — Prefer native metrics over log-extracted metrics
**Lesson:** When infrastructure already exposes native metrics (HTTP status rates at the proxy, request latency), alert on those rather than regex-extracting application logs — less context, far more reliability.
**Why:** Auth-failure and transcoding alerts built on Promtail regex extraction were rebuilt on Traefik's native 401/403 and 5xx rates after repeated rotation-driven false positives; status codes don't change format.
**Sources:** [auth-transcoding-alert-redesign](../99-reports/auth-transcoding-alert-redesign.md) · **Date:** 2026-01-16 · **Status:** Active

### L-033 — Exporter liveness is not service liveness — and catch-all rules override design intent
**Lesson:** `up{job=X}==0` means the *collection pipeline* failed, not the service; functional probes (e.g. an actual DNS query) outrank liveness, and generic catch-all rules (HostDown over every job) silently reintroduce the conflation even after the principle is adopted.
**Why:** A wedged exporter set `up=0` for Pi-hole and a generic critical "host down" rule paged for three days while the functional DNS probe stayed green and 55k queries/day succeeded. The design principle existed (ADR-031 D5); the catch-all rule trumped it.
**Sources:** [2026-06-07-pihole-false-down-postmortem-private](../99-reports/2026-06-07-pihole-false-down-postmortem-private.md) · **Date:** 2026-06-07 · **Status:** Active

### L-034 — Exporters that do synchronous work need explicit scrape-timeout sizing
**Lesson:** An exporter that logs in, queries upstream, and transforms per scrape will eventually brush Prometheus's default 10s timeout; size `scrape_timeout` with headroom for the work it does, and let a dedicated exporter-down alert catch true stalls.
**Why:** pihole-exporter's normal latency transients (6–14s) were guillotined at exactly 10.0s by the inherited default, manufacturing a fake outage.
**Sources:** [2026-06-07-pihole-false-down-postmortem-private](../99-reports/2026-06-07-pihole-false-down-postmortem-private.md) · **Date:** 2026-06-07 · **Status:** Active

### L-035 — Aggregate across label sets; stale TSDB series cause flapping and false alerts
**Lesson:** Series persist until retention expires: alerts that evaluate per-series will flap on stale series after label changes, and metrics that retain historical instances (old certs) need aggregation selecting the relevant one (`sum(changes(...))`, `max by (cn)`).
**Why:** A Promtail restart left stale priority-label series frozen at old values, flapping an alert for days; cert-expiry alerts fired on certificates replaced years earlier because Traefik keeps metrics for every cert ever seen.
**Sources:** [2026-01-21-alert-flapping-root-cause-fix](../98-journals/2026-01-21-alert-flapping-root-cause-fix.md), [2026-01-08-monitoring-alert-fatigue-fixes](../98-journals/2026-01-08-monitoring-alert-fatigue-fixes.md) · **Date:** 2026-01-21 · **Status:** Active

### L-036 — Gauge-based alerts need time-bounded conditions
**Lesson:** A gauge that updates rarely (e.g. last-backup duration, written weekly) will hold an alarming value until its next update; gate the alert on recency (`time() - last_success < window`) so it auto-resolves.
**Why:** A "backup slow" alert fired continuously for six days because the duration gauge from one slow weekly run simply sat there until the next run overwrote it.
**Sources:** [2026-01-03-disaster-recovery-verification-milestone](../98-journals/2026-01-03-disaster-recovery-verification-milestone.md) · **Date:** 2026-01-03 · **Status:** Active

### L-037 — Calibrate thresholds to the actual technology and require impact conditions
**Lesson:** Resource thresholds inherited from generic guidance assume generic hardware — zram swap sustains rates that would mean death on disk swap; calibrate to the deployed technology and AND the metric with an impact condition (load, memory pressure) so anomalies without consequences don't page.
**Why:** A 300 pages/sec swap-thrashing threshold (disk-era guidance) sat just above the *normal* zram baseline of 230, producing chronic near-threshold noise until recalibrated with impact gating.
**Sources:** [2026-01-23-swap-thrashing-investigation-alert-recalibration](../98-journals/2026-01-23-swap-thrashing-investigation-alert-recalibration.md) · **Date:** 2026-01-23 · **Status:** Active

### L-038 — Burn rate must measure the current window, not alias a long-term average
**Lesson:** A burn-rate expression that reduces to the 30-day SLI is a constant in disguise and will never detect a fast burn; compute error rate over the alert's own window divided by error budget.
**Why:** The original burn-rate rules averaged the long-term SLI and stayed ≈constant during real incidents — the alert that existed to catch fast degradation mathematically could not fire for one.
**Sources:** [2026-01-22-burn-rate-calculation-fix](../98-journals/2026-01-22-burn-rate-calculation-fix.md) · **Date:** 2026-01-22 · **Status:** Active

### L-039 — An SLO without a burn-rate alert is half a defense
**Lesson:** Recording rules and dashboards do not page anyone; every SLO that matters needs a corresponding burn-rate alert, and the gap audit ("which SLOs have no alert?") is cheap and worth repeating.
**Why:** 169 SLO recording rules existed while the service with the *tightest* SLO (Traefik, 99.95% — a degraded gateway fails everything) had no burn-rate alert at all; latency and upload SLOs were visualized but unenforced.
**Sources:** [2026-05-25-monitoring-stack-deep-dive](../99-reports/2026-05-25-monitoring-stack-deep-dive.md) · **Date:** 2026-05-25 · **Status:** Active

### L-040 — Multi-window, multi-tier burn-rate alerting beats static thresholds
**Lesson:** SLO burn-rate alerting with paired long+short windows and severity tiers detects sustained problems quickly while ignoring transients; it replaced static thresholds here with a ~90% reduction in alert noise.
**Why:** Tiered burn-rate alerts (Dec 2025) cut ~40 alerts/day to ~3–5 while preserving detection — the short window confirms, the long window smooths, and tiers map urgency to budget-exhaustion speed.
**Sources:** [2025-12-26-monitoring-alerting-investigation](../98-journals/2025-12-26-monitoring-alerting-investigation.md), [2025-12-31-new-year-eve-strategic-assessment](../98-journals/2025-12-31-new-year-eve-strategic-assessment.md) · **Date:** 2025-12-26 · **Status:** Active

### L-041 — Distinguish "many events" from "one event re-notified"
**Lesson:** `repeat_interval` makes a single unresolved alert look like a sustained storm (~70 identical pages over 3 days); triage must first establish whether the page stream is many incidents or one re-notified — the remediations are completely different.
**Why:** The Pi-hole false-down stream was perceived as "DNS constantly breaking"; it was one alert firing once and never clearing, re-notified hourly.
**Sources:** [2026-06-07-pihole-false-down-postmortem-private](../99-reports/2026-06-07-pihole-false-down-postmortem-private.md) · **Date:** 2026-06-07 · **Status:** Active

### L-042 — A single persistent known-false alert erodes trust in everything
**Lesson:** A permanently-firing alert everyone has learned to ignore teaches the operator to ignore the channel; resolve the exception explicitly (intent flag, scoped disable, or fix) so "all green" stays meaningful.
**Why:** One subvolume's external-backup-missing alert fired indefinitely because intent ("should this even have an external copy?") was never encoded — the alert had no way to distinguish deliberate from forgotten.
**Sources:** [2026-05-25-monitoring-stack-deep-dive](../99-reports/2026-05-25-monitoring-stack-deep-dive.md) · **Date:** 2026-05-25 · **Status:** Active

### L-043 — Drop unconsumed metrics at ingestion with an allowlist
**Lesson:** Collecting every metric every exporter emits is not observability; `metric_relabel_configs` allowlists keyed to what dashboards and rules actually consume cut cardinality (and TSDB/dump size) with zero visibility loss.
**Why:** cAdvisor alone was 52% of all active series (17.6k), dominated by metrics with no dashboard or rule consumer; TSDB was 4 GB where ~2.2 GB carried all actual value.
**Sources:** [2026-05-25-monitoring-stack-deep-dive](../99-reports/2026-05-25-monitoring-stack-deep-dive.md) · **Date:** 2026-05-25 · **Status:** Active

### L-044 — Route architectural-state alerts to digests, not incident channels
**Lesson:** Alerts describing slow-moving architectural state (snapshot counts, retention posture) belong in periodic digests; routing them through incident channels trains alarm fatigue without improving response.
**Why:** A snapshot-count alert re-fired every 4 hours on normal retention-cleanup fluctuation — accurate information, wrong channel, pure noise.
**Sources:** [2025-12-26-monitoring-alerting-investigation](../98-journals/2025-12-26-monitoring-alerting-investigation.md) · **Date:** 2025-12-26 · **Status:** Active

### L-045 — Textfile metrics must avoid labels the scrape job will clobber
**Lesson:** Labels set by the scrape pipeline (notably `service` under `honor_labels: false`) overwrite identical labels in textfile metrics, silently collapsing distinct series; choose label names the pipeline doesn't own (`database=`, not `service=`).
**Why:** Per-database dump metrics labeled `service="<db>"` all collapsed into `service="node_exporter"` — per-engine visibility vanished without an error anywhere.
**Sources:** [2026-05-22-db-storage-three-tier-and-dump-backbone-phase-a](../98-journals/2026-05-22-db-storage-three-tier-and-dump-backbone-phase-a.md) · **Date:** 2026-05-22 · **Status:** Active

### L-046 — Probe cadence per check type — and human-facing log surfaces are requirements too
**Lesson:** Liveness checks and config-drift canaries have different latency needs; cadence each to its purpose rather than the global scrape interval, and treat operator-facing log surfaces (which probes pollute) as first-class design constraints alongside Prometheus's needs.
**Why:** Two DNS probes at 15s flooded the Pi-hole query log the operator uses for network forensics; re-cadencing (liveness 30s, drift canary 5m) cut that noise 72% with detection still inside the alert's window.
**Sources:** [2026-05-28-dns-probe-cadence-and-pihole-session-leak](../98-journals/2026-05-28-dns-probe-cadence-and-pihole-session-leak.md) · **Date:** 2026-05-28 · **Status:** Active

### L-047 — Failed automated remediation must escalate as loudly as the original alert
**Lesson:** When automation attempts a fix and fails, that failure must reach the same channel at equal or higher severity — a remediation failure logged quietly to disk creates the worst state: a problem everyone believes is being handled.
**Why:** The remediation webhook logged failures only to a local decision log; the operator saw "problem detected" with no signal that the automated response had failed.
**Sources:** [2025-12-26-monitoring-alerting-investigation](../98-journals/2025-12-26-monitoring-alerting-investigation.md), [2025-12-25-remediation-critical-review](../99-reports/2025-12-25-remediation-critical-review.md) · **Date:** 2025-12-26 · **Status:** Active

## Debugging & Forensic Methodology

### L-048 — Technical validation is not architectural suitability
**Lesson:** "The device exists, the driver loads, permissions are correct" answers *can I access it*, not *will this workload succeed on it*; assess architectural fit (memory model, workload class) before deploying, not after.
**Why:** GPU acceleration for ML passed every access-level check and failed on first inference: ROCm requires exclusive VRAM, and an integrated APU sharing system RAM can never provide it. No amount of configuration could fix an architectural mismatch.
**Sources:** [2025-11-10-gpu-acceleration-failure-postmortem](../98-journals/2025-11-10-gpu-acceleration-failure-postmortem.md) · **Date:** 2025-11-10 · **Status:** Active

### L-049 — Smoke-test the real workload before declaring success
**Lesson:** "Service started" is not "service works"; every deployment declaration of success must include one end-to-end exercise of the actual workload (one inference, one upload, one login).
**Why:** The GPU deployment script reported success on service start; the first real inference crashed seconds later. A single-photo smoke test would have caught it inside the deployment session.
**Sources:** [2025-11-10-gpu-acceleration-failure-postmortem](../98-journals/2025-11-10-gpu-acceleration-failure-postmortem.md) · **Date:** 2025-11-10 · **Status:** Active

### L-050 — Absence of logs is itself a diagnostic signal
**Lesson:** When a major state change leaves no application log trail, stop grepping logs and interrogate the data store directly — the silence narrows the suspect list to background jobs and bugs, excluding user actions.
**Why:** 4,223 assets were soft-deleted with identical timestamps and zero log events; the missing logs pointed away from user action and toward an internal job, which database inspection confirmed.
**Sources:** [2025-11-23-immich-data-loss-incident-report](../98-journals/2025-11-23-immich-data-loss-incident-report.md) · **Date:** 2025-11-23 · **Status:** Active

### L-051 — Forensic confidence requires positive evidence across three layers
**Lesson:** To conclude "no compromise occurred," verify policy (configuration history), enforcement (the middleware actually applied), and events (logs consistent with only known activity) — "no alerts fired" is absence of evidence, not evidence.
**Why:** The leaked-credential review reached confidence only when config history showed MFA always required, router chains showed Authelia always in path, and auth logs showed every 1FA paired with 2FA except two operator-attributable events.
**Sources:** [2026-04-14-authelia-credential-exposure-forensic-review](../99-reports/2026-04-14-authelia-credential-exposure-forensic-review.md) · **Date:** 2026-04-14 · **Status:** Active

### L-052 — Idle-but-hot means inspect the physical environment
**Lesson:** A component that is thermally hot while computationally idle cannot be explained by on-host metrics; go look at the hardware — neighbors, stacking, airflow — before tuning software.
**Why:** A Pi at 80–86°C with <1% CPU was being heat-soaked by an ISP modem stacked beneath it; de-stacking dropped 19°C in 25 minutes. Software inspection alone would have been an unwinnable rabbit hole.
**Sources:** [2026-06-07-pihole-false-down-postmortem-private](../99-reports/2026-06-07-pihole-false-down-postmortem-private.md) · **Date:** 2026-06-07 · **Status:** Active

### L-053 — Verify unexpected SSH host keys out-of-band before suspecting MITM
**Lesson:** A changed host key warrants out-of-band verification (on-device fingerprint, MAC/OUI cross-check via the network controller), not blind acceptance and not automatic MITM panic — early-boot regeneration (pre-NTP, pre-hostname) is a common benign cause.
**Why:** A Pi presented all-new host keys with 1970 mtimes and `root@(none)` comments — classic pre-NTP regeneration, confirmed benign by on-device fingerprint and controller MAC match.
**Sources:** [2026-05-26-adr031-phase1-pihole-resolver-first-class-private](../99-reports/2026-05-26-adr031-phase1-pihole-resolver-first-class-private.md) · **Date:** 2026-05-26 · **Status:** Active

### L-054 — Map a compound failure's full chain before attempting fixes
**Lesson:** When several defects interact (protocol mismatch + destructive tooling + API filtering), point fixes get undone by the layer you haven't found yet; map the whole chain first, and recognize when accumulated cost justifies decommissioning over further debugging.
**Why:** Collabora's WOPI breakage involved a discovery-protocol mismatch, a config tool that destroyed manual fixes, and capability-API filtering — each fix was eaten by another layer across two 3-hour sessions before decommissioning became the rational call.
**Sources:** [2026-02-06-collabora-post-mortem-and-decommission](../98-journals/2026-02-06-collabora-post-mortem-and-decommission.md) · **Date:** 2026-02-06 · **Status:** Active

### L-055 — Verify API/version compatibility before deploying integrations
**Lesson:** Exporters and integrations built for one major version often fail silently against the next (endpoints moved, auth changed); verify the integration's expected API against the actual deployed service version before debugging "mysterious" failures.
**Why:** Pi-hole v6 removed the v5 `/admin/api.php` API entirely; an exporter mismatch would hang without a clear error, and the debugging session initially chased phantom causes.
**Sources:** [2026-05-27-adr-031-phase2-and-dns-noise-private](../99-reports/2026-05-27-adr-031-phase2-and-dns-noise-private.md) · **Date:** 2026-05-27 · **Status:** Active

### L-056 — LAN-side defaults silently distort DNS and DHCP behavior
**Lesson:** When DNS logs or reservations look wrong, check what the LAN equipment injects: DHCP-pushed search domains propagate into containers (generating junk queries like `localhost.<suffix>`), and Apple per-SSID MAC randomization quietly defeats DHCP reservations.
**Why:** 32k bogus `localhost.lokal` queries/day traced to a UniFi DHCP search suffix entering container resolv.conf; "unknown" clients in DNS logs were family devices on rotated MACs bypassing their reservations.
**Sources:** [2026-05-27-adr-031-phase2-and-dns-noise-private](../99-reports/2026-05-27-adr-031-phase2-and-dns-noise-private.md) · **Date:** 2026-05-27 · **Status:** Active

## Architecture & Design Process

### L-057 — Ship the reversible change first; migrate only on measured evidence
**Lesson:** When a proposal bundles a high-value reversible change with a risky preemptive migration, split it: ship the reversible part, measure the problem the migration claims to solve, and migrate only if the numbers justify it.
**Why:** The DB storage redesign originally bundled dump-based backups (60% of the value, 20% of the risk) with an unmeasured NOCOW migration; the design review split them, and the eventual ADR-029 migration proceeded on actual fragmentation/latency evidence with dumps already in place as the rollback net.
**Sources:** [2026-04-18-design-review-ADR-023-btrfs-storage-architecture-databases](../99-reports/2026-04-18-design-review-ADR-023-btrfs-storage-architecture-databases.md) · **Date:** 2026-04-18 · **Status:** Active

### L-058 — Never build security-critical behavior on undefined ordering
**Lesson:** Behavior that happens to work because of unspecified ordering (DNS answer order, map iteration) is a latent failure waiting for an unrelated change; for multi-network containers, deterministic routing requires static IPs or hosts-file overrides (ADR-018), not DNS luck.
**Why:** A kernel update changed network-namespace timing; aardvark-dns began returning a different network's IP first and Traefik routed across the wrong network, violating segmentation. It had "worked" for months by coincidence.
**Sources:** [2026-02-02-ROOT-CAUSE-CONFIRMED-dns-resolution-order](../98-journals/2026-02-02-ROOT-CAUSE-CONFIRMED-dns-resolution-order.md), [2026-02-02-catastrophic-network-failure-investigation](../98-journals/2026-02-02-catastrophic-network-failure-investigation.md) · **Date:** 2026-02-02 · **Status:** Active

### L-059 — Decommissioning is a valid engineering outcome
**Lesson:** When a component's integration fragility generates recurring multi-hour debugging with no stable end-state, removing it is a rational cost-benefit decision, not a failure — write the postmortem and reclaim the complexity budget.
**Why:** Collabora (fragile WOPI stack) and later Homepage were decommissioned after honest accounting of maintenance cost vs. delivered value; both removals simplified the system with no regret recorded since.
**Sources:** [2026-02-06-collabora-post-mortem-and-decommission](../98-journals/2026-02-06-collabora-post-mortem-and-decommission.md), [2026-05-27-post-update-boot-storm-and-homepage-decom](../98-journals/2026-05-27-post-update-boot-storm-and-homepage-decom.md) · **Date:** 2026-02-06 · **Status:** Active

### L-060 — Decommissioning is complete only when every trace is removed
**Lesson:** Removing a service means removing its container, quadlet, routes, middleware, scrape targets, recording rules, SLO definitions, and data — leftovers create stale metrics, dead config, and audit confusion.
**Why:** The OCIS decommission required cleanup across 6 distinct surfaces (including 9 SLO recording rules and a dedicated rate-limit middleware); any one missed would have lingered as monitoring noise or config debt.
**Sources:** [2025-12-20-nextcloud-deployment-and-ocis-decommission](../98-journals/2025-12-20-nextcloud-deployment-and-ocis-decommission.md) · **Date:** 2025-12-20 · **Status:** Active

### L-061 — Don't build orchestration before usage proves the need
**Lesson:** Generalized machinery (chain execution, state management, resume logic) built from "sounds useful" rather than a recurring concrete pain ends up unused; ship the minimal manual path, observe what actually recurs, then automate that.
**Why:** 756 lines of remediation chain-orchestration code saw zero production executions while two simple playbooks did all the real work; the chains it enabled were trivially expressible as two-line shell commands.
**Sources:** [2025-12-25-remediation-critical-review](../99-reports/2025-12-25-remediation-critical-review.md) · **Date:** 2025-12-25 · **Status:** Active

### L-062 — Predictions without validation loops are silent assumptions
**Lesson:** Any predictive feature (resource-exhaustion forecasts, trend projections) needs a feedback loop comparing prediction to outcome; an unvalidated predictor running for months is an assumption wearing a dashboard.
**Why:** Linear-regression exhaustion forecasts ran for five months with no tracking of whether any predicted date came true — accuracy was simply unknown, and unknown accuracy in autonomous tooling is worse than no prediction.
**Sources:** [2025-12-25-remediation-critical-review](../99-reports/2025-12-25-remediation-critical-review.md) · **Date:** 2025-12-25 · **Status:** Active

### L-063 — Mitigate third-party defects in independent layers
**Lesson:** When an upstream bug can't be fixed on your timeline, stack independent mitigations — reduce the defect's rate, add a cleanup mechanism, and alert on the failure mode — rather than betting on any single workaround or on upstream.
**Why:** A session-leaking exporter (upstream issue unanswered for months) was contained with a 48× leak-rate reduction, an hourly session sweeper, and exhaustion alerts; each layer survives the others failing.
**Sources:** [2026-05-28-dns-probe-cadence-and-pihole-session-leak](../98-journals/2026-05-28-dns-probe-cadence-and-pihole-session-leak.md) · **Date:** 2026-05-28 · **Status:** Active

### L-064 — Defaults encode someone else's context — recalibrate to your own
**Lesson:** Upstream defaults are tuned for the author's environment (cAdvisor for Kubernetes autoscaling, scrape timeouts for instant exporters, audit guides for 4-core boxes); inventory which defaults you inherited and re-derive them from your hardware and workload.
**Why:** Recurring incident pattern: cAdvisor's 1s housekeeping OOM-killed a homelab node (L-002), the 10s scrape default manufactured an outage (L-034), zram-inappropriate swap thresholds paged chronically (L-037), and copy-pasted 4-core CPU quotas would have throttled a 12-core machine to 16%.
**Sources:** [2026-03-23-cadvisor-oom-death-spiral-postmortem](../98-journals/2026-03-23-cadvisor-oom-death-spiral-postmortem.md), [2026-04-29-quadlet-hardening-sweep](../98-journals/2026-04-29-quadlet-hardening-sweep.md) · **Date:** 2026-04-29 · **Status:** Active

## Process & Collaboration

### L-065 — Document decisions while they are fresh
**Lesson:** ADRs, runbooks, and guides written in the same session as the deployment capture the *why* that is unrecoverable later; documentation deferred is rationale lost.
**Why:** The Nextcloud deployment produced its ADRs and runbooks in-session, preserving non-obvious choices (why native auth, why external-storage mounts) that would otherwise resurface as "why did we do this?" archaeology.
**Sources:** [2025-12-20-nextcloud-deployment-and-ocis-decommission](../98-journals/2025-12-20-nextcloud-deployment-and-ocis-decommission.md) · **Date:** 2025-12-20 · **Status:** Active

### L-066 — Capture negative constraints explicitly
**Lesson:** Documentation must state what does **not** work and why ("integrated APUs unsupported: shared-memory architecture"), not just generic positive requirements; negative constraints are what prevent the next person from repeating the experiment.
**Why:** "AMD GPU with ROCm support" was technically accurate documentation that still allowed a doomed deployment; the missing sentence was the warning about integrated GPUs. This document's Superseded section exists for the same reason.
**Sources:** [2025-11-10-gpu-acceleration-failure-postmortem](../98-journals/2025-11-10-gpu-acceleration-failure-postmortem.md) · **Date:** 2025-11-10 · **Status:** Active

### L-067 — A pre-change backup turns failures into two-minute rollbacks
**Lesson:** Every risky change starts with a timestamped backup of what it will touch (plus git state); the cost is seconds and it converts catastrophic failure into a calm two-minute revert.
**Why:** The failed GPU deployment was fully rolled back in ~2 minutes from its pre-change backup — no manual reconstruction, no extended downtime, no panic.
**Sources:** [2025-11-10-gpu-acceleration-failure-postmortem](../98-journals/2025-11-10-gpu-acceleration-failure-postmortem.md) · **Date:** 2025-11-10 · **Status:** Active

### L-068 — Anything not codified will eventually be lost
**Lesson:** Manual host configuration (firewall rules, resolver settings, service tweaks) silently evaporates on reprovision, firmware update, or memory fade; the config-as-code artifact (Ansible role, quadlet, committed config) is the source of truth — current state is just a cache of it.
**Why:** Remote-host provisioning codified every fix (ufw rules, exporter setup, resolver config) into Ansible roles precisely because earlier hand-applied changes had no survivability story.
**Sources:** [2026-05-26-adr031-phase1-pihole-resolver-first-class-private](../99-reports/2026-05-26-adr031-phase1-pihole-resolver-first-class-private.md) · **Date:** 2026-05-26 · **Status:** Active

### L-069 — Ansible check mode has blind spots for install-dependent tasks
**Lesson:** `--check` cannot simulate install-then-configure flows: tasks depending on artifacts created by earlier tasks fail spuriously; gate them with `when: not ansible_check_mode` and mark read-only validations `check_mode: false`.
**Why:** A playbook's check run failed on service/validation tasks for software that the (simulated) earlier tasks would have installed — false failures that erode trust in dry runs unless explicitly handled.
**Sources:** [2026-05-26-adr031-phase1-pihole-resolver-first-class-private](../99-reports/2026-05-26-adr031-phase1-pihole-resolver-first-class-private.md) · **Date:** 2026-05-26 · **Status:** Active

## Superseded lessons

Kept as negative knowledge: these were genuinely believed and acted on. Do not re-recommend them.

### L-070 — Float tags and let AutoUpdate keep images fresh
**Lesson (former):** Pin services to version/`:latest` tags with `AutoUpdate=registry` so images stay current with minimal effort.
**Superseded by:** ADR-030 / ADR-036 (2026-05/06) — every image is digest-pinned, `AutoUpdate` is stripped, and updates flow through a deliberate discover→bake→adopt loop (`monthly-update.sh`). Auto-updating registry images is now a supply-chain trust violation here, enforced by pre-commit hook.
**Sources:** [ADR-015](../00-foundation/decisions/2025-12-22-ADR-015-container-update-strategy.md) · **Date:** 2025-12-22 · **Status:** Superseded

### L-071 — Shell-script BTRFS backup automation with NOPASSWD sudo
**Lesson (former):** A systemd-user-timer shell script driving `btrfs send` with `/etc/sudoers.d/` NOPASSWD rules is the backup backbone.
**Superseded by:** Urd (ADR-021), the Rust backup tool — sole backup system since 2026-03-25. The durable residue survives in L-021 (backup failures must alert) and the platform fact that systemd user services cannot prompt for sudo passwords.
**Sources:** [2025-11-12-backup-automation-fix-session-report](../98-journals/2025-11-12-backup-automation-fix-session-report.md) · **Date:** 2025-11-12 · **Status:** Superseded

### L-072 — Alert when error lines appear in logs
**Lesson (former):** Extract error patterns from logs via Promtail regex and alert when the failure counter rises.
**Superseded by:** L-031/L-032 (Jan 2026) — log rotation made these counters structurally false-positive-prone; alerting moved to absence-of-success and native proxy metrics.
**Sources:** [alert-false-positives-analysis-2026-01-16](../99-reports/alert-false-positives-analysis-2026-01-16.md) · **Date:** 2026-01-16 · **Status:** Superseded

### L-073 — Static per-metric thresholds for service health
**Lesson (former):** Define a fixed threshold per metric (CPU %, error count, response time) and alert on breach.
**Superseded by:** L-040 (Dec 2025) — multi-window, multi-tier SLO burn-rate alerting replaced static thresholds for service health, cutting noise ~90% while improving detection. Static thresholds remain appropriate only for hard physical limits (disk full, cert expiry).
**Sources:** [2025-12-26-monitoring-alerting-investigation](../98-journals/2025-12-26-monitoring-alerting-investigation.md) · **Date:** 2025-12-26 · **Status:** Superseded
