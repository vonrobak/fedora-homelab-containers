# Homelab Holistic Evaluation & Strategic Development Trajectories (2026 H2)

**Date:** 2026-06-12
**Status:** Report delivered — trajectories awaiting owner prioritization
**Predecessor:** [2025-01-09-strategic-development-trajectories-plan.md](2025-01-09-strategic-development-trajectories-plan.md)

## Context

Requested: a whole-stack evaluation (configs, security, automation, monitoring+alerting, systems design, digital sovereignty, efficiency, project goals) producing a comprehensive report with **three development trajectories**. Method: three parallel exploration passes (quadlets/Traefik/security; scripts/timers/Prometheus/SLO; ADRs/journals/roadmap/issues), with load-bearing claims re-verified directly against the live system. This is the predecessor of `97-plans/2025-01-09-strategic-development-trajectories-plan.md` (Jan 2026) — nearly everything that plan proposed (SLO maturation, DR validation, operational excellence) has since shipped, which itself says something about execution discipline here.

---

## Part 1 — Where the stack stands

### Verified scale facts
- **37 containers running** (37 quadlets; CLAUDE.md's "29 containers" is stale)
- 36 ADRs (4 superseded cleanly, with what-remains-valid notes), 75 distilled lessons, dated journals, a living roadmap/status under `docs/96-project-supervisor/`
- 140 Prometheus alert rules in 18 files; 12 SLOs across 7 services with Google-SRE multi-window burn rates **and a rule test suite** (`config/prometheus/rules/tests/`)
- 81 active scripts (~22,000 LOC of shell); 37 live systemd user timers
- Supply chain: every registry image digest-pinned, updates de-automated with a codified bake policy (ADR-030/036); egress observatory armed and first-fired 2026-06-12; `podman-auto-update.timer` confirmed masked

### What is genuinely excellent (top decile for a homelab, much of it top decile for small production)
1. **Decision & lesson infrastructure** — ADRs with supersession hygiene, 75 lessons with IDs cited in code comments, sequencing principles written down ("redundancy before monitoring", "validation beats features"). This is the asset that compounds; most orgs don't have it.
2. **Supply-chain trust model** — digest pinning + bake policy + CVE exception lane + egress detection + signed merge-only main + append-only Forgejo mirror with tamper canary. Coherent end-to-end story.
3. **Alert engineering** — multi-window burn rates, inhibition rules, absence-detection over log-grep (L-031/L-032/L-072 explicitly recorded as superseded anti-patterns), backup alerts with edge-case gating (`backup_send_type=2` exclusion), 4-tier severity routing with quiet hours.
4. **Layered security** — fail-fast middleware ordering, YubiKey-first SSO, socket activation restoring real client IPs after the NAT discovery (L-023), memory limits on all 37 containers, boot I/O tiering (ADR-035).
5. **Backup posture** — Urd with restore-test gate *met* (2026-06-04), nightly DB dump backbone, three-tier recovery-model storage (ADR-029 Phase B executed).

### Findings — gaps and debt, by lens

**Security / configs**
- `NoNewPrivileges=true` present on only **3/37** quadlets — cheap, high-value hardening sweep missing (verified by grep).
- **GH#140 open since 2026-04-28, labeled high**: immich-server runs without `User=1000:1000` — a known security regression aging 6+ weeks.
- CSP allows `unsafe-eval` in places; per-app audit not done. CPUQuota inconsistent across DB/Redis quadlets. Distroless images (Loki, exporters) lack external health probes — "Loki healthcheck" has sat in known-gaps memory for months.
- GH#274 (services with no observed external traffic may not belong on `reverse_proxy`) and GH#284 (native-auth session/device audit residual) are real attack-surface items, both open.
- Secrets handling, .gitignore, SELinux labeling: clean. No findings.

**Automation / operational state as code**
- **22 of 37 live timers are not in the repo** (verified by diff): `autonomous-operations`, `check-image-updates`, `urd-backup`, `security-comprehensive-audit`, `daily-drift-check`, `cloudflare-ddns`, etc. The system that detects config drift is itself partially un-drift-checkable. This is the single biggest "configuration as code" violation in the stack — and it produced a false finding *during this very evaluation* (an explorer concluded the autonomous loop was unscheduled because the timer isn't in git; it actually runs daily at ~06:33).
- Script estate: 81 scripts / ~22k LOC, two scripts >1,600 LOC, ~9 overlapping health/verify variants, 36 archived scripts. No duplication crisis, but clear consolidation debt and an all-shell monoculture for increasingly load-bearing logic (the Urd precedent — graduating critical shell to a tested binary — exists for a reason).

**Monitoring / alerting**
- **The auto-remediation path is inert**: `alertmanager.yml:112` still has `token=REPLACE_WITH_ACTUAL_TOKEN` on the remediation webhook. SLO Tier-1/2 burns route to a dead endpoint. The OODA loop runs daily, the playbooks exist, the decision engine has confidence gates and circuit breakers — but the alert-triggered remediation lane was never switched on. The "autonomous operations" story is ~75% built, 100% designed, and the last mile is unplugged.
- ~15 containers (DB/cache/exporter/ML sidecars: nextcloud-db, redis-*, immich-ml, gathio-db, proton-bridge, qbittorrent…) have no direct liveness alerts — parent-service coverage is assumed but undocumented.
- `runbook_url` on only ~11 of 140 alerts (~8%); the IR/DR runbooks exist but aren't wired to the alerts that should invoke them.
- Grafana: 16 dashboards provisioned as code; some manual dashboards live only in the UI. Loki scrapes journal only (no Traefik access logs); 7d retention is a reasonable, deliberate choice.
- GH#277 (inhibit rule lumps all host alerts via `service=node_exporter`) and GH#276 (prometheus.yml single-file bind-mount inode trap, **4th occurrence**) are known sharp edges awaiting fixes.

**Systems design / resilience**
- **Single-host SPOF remains the defining structural fact.** DR runbooks (DR-001..004) and IR runbooks (IR-001..005) exist, restore tests pass, but: full-host rebuild-from-code has never been drilled (CoreOS/NixOS rebuild plans were shelved; htpc-mgmt substrate is nascent); no UPS/power story found; sdc is a known-weak drive (8 reallocated sectors) with scrub timers still gated (GH#267).
- DNS resolver HA (ADR-031 phase 3) accepted but not started — the resolver SPOF still masks alert-path failures, the exact self-masking failure mode the ADR was written to kill.

**Digital sovereignty** — external dependencies in critical paths (verified):
| Dependency | Role | Criticality |
|---|---|---|
| Discord | **the** alert delivery channel | High — Discord outage = blind during incidents |
| Cloudflare | DNS + DDNS (`cloudflare-ddns.timer`) + ACME DNS-01 | High — single vendor for name resolution AND cert issuance |
| GitHub | **primary** git remote (Forgejo is the mirror, not the source of truth) + issue tracker | Medium-high — runtime config tree's canonical home is a US cloud |
| Let's Encrypt | cert issuance | Medium (acceptable; little alternative) |
| hotmail.com | ACME contact email (traefik.yml:89) | Low but ironic for a sovereignty project |
| docker.io / ghcr.io / lscr.io | image source (mitigated by digest pinning) | Medium, partially mitigated |
| Proton (bridge) | outbound mail | Low-medium, self-hosted bridge |

The detect→decide→notify path today is: self-hosted Prometheus → self-hosted Alertmanager → **Discord** (external), resolved via **Cloudflare-managed DNS** (external), with config canonically on **GitHub** (external). For a sovereignty project, the *control plane* is less sovereign than the *data plane*.

**Efficiency / project goals**
- The roadmap's own principles are sound and mostly honored; the main inefficiency is *designed-but-dormant capability* (remediation webhook, runbooks unlinked from alerts, dashboards half-in-git) — paying the build cost without collecting the operational return.
- CLAUDE.md drift (29 vs 37 containers) and the timer gap show the auto-doc system doesn't cover everything that matters.

---

## Part 2 — Three development trajectories

All three are compatible; they overlap intentionally at the second node and the config-as-code closure. Each is sized as a multi-week arc in the roadmap's sense.

### Trajectory 1 — "Close the Loop": the self-operating homelab
**Thesis:** Stop building autonomy and start *collecting* it. Every component of a self-healing system exists — decision engine, playbooks, snapshots, circuit breakers, effectiveness reports — except the final wire.

1. **Activate auto-remediation** — deploy the remediation webhook with a real token, then run a live drill: induce a synthetic SLO burn → webhook → playbook → pre-action snapshot → Discord trail. (Effort: hours.)
2. **Operational state fully as code** — import the 22 unmanaged timers + their services into the repo, extend `check-drift.sh` to cover them; export the remaining Grafana dashboards; add `promtool check rules` to the pre-commit hook. Closes the gap that misled this very audit.
3. **Coverage completion** — liveness alerts (or explicit written waivers) for the ~15 unalerted sidecars; Loki external health probe; fix GH#277 inhibit granularity and GH#276 inode trap.
4. **Runbooks wired to alerts** — `runbook_url` on the 39 critical/backup/storage alerts pointing at the existing DR/IR docs.
5. **Script estate consolidation** — merge the 9 health/verify variants; pick the 2–3 most load-bearing scripts (candidates: security-audit.sh at 1,612 LOC, the adopt/check update pair) and either harden or graduate them to a tested binary per the Urd precedent.
6. **Raise the autonomy ceiling** — after 1–2 months of webhook telemetry (remediation-effectiveness report already exists on a timer), widen the confidence-gated action set deliberately.

**Endgame:** routine incidents resolve themselves with a signed, snapshotted audit trail; the human handles novelty. Best effort-to-payoff ratio of the three; mostly hours-to-days per item.

### Trajectory 2 — "Sever the Tethers": sovereignty endgame
**Thesis:** Make the control plane as sovereign as the data plane. Defined by a kill test: *for each external dependency, what happens the day it disappears — and does anything in detect→decide→act→record leave owned hardware?*

1. **Alert-path sovereignty** — self-hosted ntfy (or Matrix) as the primary notification channel; Discord demoted to secondary. This is the highest-value single move: today an external chat company sits inside the incident-response loop.
2. **Git sovereignty flip** — Forgejo becomes primary, GitHub becomes the (push-)mirror. Real cost is issue migration (Forgejo has a GitHub importer) and CI/workflow rewiring; the mirror automation and signing infrastructure already exist and just reverse direction.
3. **DNS/ACME blast-radius reduction** — Cloudflare currently holds names, dynamic DNS, *and* cert issuance. Either consciously re-accept that with a documented failure drill, or split: authoritative DNS to deSEC/self-hosted with a secondary, keep registrar-only at Cloudflare. Fix the hotmail ACME contact while in there.
4. **Supply chain Tier 3** — per-image signature verification; plan approved (`97-plans/2026-05-24-tier3-...`), explicitly unblocked, listed as next-session candidate on the roadmap.
5. **Off-site backup under owner keys** — today "external" = a local external drive. Add a true off-site leg (family/friend node, or rented storage with client-side encryption — the sovereignty tradeoff is acceptable when ciphertext is all that leaves) and wire it into the existing `backup_external_expected` gating.
6. **Dependency kill-test drills** — one per quarter: pull a dependency (DNS, Discord, GitHub) in a controlled window and record what breaks. Findings feed lessons.md.

**Endgame:** no external service failure can blind, lock out, or rewrite the system. The project's founding thesis, finished.

### Trajectory 3 — "Two of Everything That Matters": single host → small fleet
**Thesis:** The roadmap's own first principle — *redundancy before monitoring* — applied to its logical conclusion. The system's biggest remaining risks (host loss, disk death, resolver SPOF, power) are all hardware-shaped, and no amount of alerting fixes a SPOF.

1. **Second node** (small low-power box) as the keystone: hosts the secondary Pi-hole + keepalived VIP peer (ADR-031 phase 3, which currently *gates on exactly this design decision*), a standby alert relay, an independent backup target, and the rehearsal substrate for rebuild drills. One purchase unblocks four arcs.
2. **DNS resolver HA** — execute ADR-031 phase 3 on that node; verify alert-path independence (the resolver must not be able to mask its own death — the ADR's core insight).
3. **Storage lifecycle** — replace sdc proactively (8 reallocated sectors, oldest drive, monitored since 2026-06-09); complete first-pass scrub and enable scrub timers (GH#267); write the pool capacity/replacement cadence into an ADR.
4. **Power** — UPS + NUT exporter + graceful-shutdown integration with the boot-tier scheme (ADR-035 already solved the *coming-back-up* half; clean shutdown is the missing half).
5. **Rebuild-from-code drill** — mature the htpc-mgmt substrate until a bare-metal → running-stack rebuild passes on the second node. This is the real test DR-001 has never had, and it answers the question the shelved CoreOS/NixOS plans were really asking ("can I reproduce this host?") without abandoning Fedora.
6. **Hardening floor** (rolled in because it's host/quadlet-shaped): NoNewPrivileges sweep across 34 quadlets, close GH#140 (immich User=), network placement review GH#274, session audit GH#284.

**Endgame:** any single component — disk, host, resolver, power feed — can fail without data loss or observability blackout. Highest cost (hardware + design sessions), highest structural payoff.

---

## Part 3 — Quick wins to do regardless of trajectory (each ≤ a session)

1. Remediation webhook token (alertmanager.yml:112) — or delete the route if auto-remediation is consciously deferred; a dead endpoint is worse than no endpoint.
2. Close GH#140 (immich-server `User=`) — high-severity, 6 weeks old, minutes of work plus a smoke test.
3. `NoNewPrivileges=true` sweep (34 quadlets) + CPUQuota consistency pass.
4. Import the 22 unmanaged timers into the repo; update CLAUDE.md's stale container count while at it.
5. ACME contact email off hotmail.
6. GH#276 prometheus.yml directory-mount fix (4th inode-trap occurrence — it has earned the fix).
7. `runbook_url` on the critical/backup/storage alert families.

## Recommendation

By the project's own sequencing principles, the order is **quick wins now → Trajectory 3 as the primary arc → Trajectory 2's items interleaved as its dependencies land → Trajectory 1's remaining depth last**:

- *Redundancy before monitoring* says the second node and DNS HA (T3) outrank further observability polish (T1's tail).
- The second node is the **shared keystone**: it unblocks ADR-031 phase 3 (T3), hosts the sovereign alert channel and off-site-style backup leg (T2), and provides the rebuild-drill substrate (T3/T2).
- T1's first two items (webhook activation, timers-as-code) are cheap enough to count as quick wins and should not wait.
- Tier 3 signatures (T2) is already roadmap-listed as a next-session candidate with no gate — take it whenever a session needs a bounded win.

A reasonable next concrete step if this report is accepted: the ADR-031 design session (VIP placement, second-host choice) the roadmap already names as the gate — it forces the second-node decision that the largest share of this report's findings converge on.
