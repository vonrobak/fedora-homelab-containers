# HANDOFF: post-audit follow-ups (for a fresh session)

**Date:** 2026-06-12 (end of session)
**Context:** One session ran: holistic audit → strategic trajectories report → all quick wins →
ADR-031 Phase 3 design + full pre-build (both repos) → Trajectory-1 sidecar alert coverage →
egress re-baseline. Everything is merged and live. This handoff lists what a fresh session
should know and the open threads, in priority order.

## State snapshot (verified at handoff time)

- main at `db7d0be`; worktree on main, clean (except `96-project-supervisor/`, local-only by design)
- 37 containers running, zero unhealthy; all quadlets carry `NoNewPrivileges=true` + CPU limits
- Remediation webhook **LIVE end-to-end** (alertmanager → `192.168.1.72`-era note: handler binds
  `192.168.1.70:9096`, token via gitignored `url_file`; tested with a synthetic POST)
- prometheus + alertmanager on **directory mounts** (inode trap dead; GH#276 closed)
- immich-server runs **non-root** via `keep-id` (GH#140 closed)
- Egress observatory: `unexpected_recent=1` — the deliberate watch item (below)
- Merged today: #291 (quick wins), #293 (ADR-031 staging), #294 (sidecar coverage),
  #296 (egress re-baseline; #295 is its dead predecessor, closed by the stacked-PR gotcha)

## Follow-ups, in priority order

1. **Immich first-upload eyeball (GH#140 residual).** The non-root change was verified by
   startup/GPU/ping/healthcheck, but no authenticated upload was possible. After the owner's
   next real upload: confirm the asset lands, thumbnail generates, and
   `journalctl --user -u immich-server` shows no EACCES.
2. **Egress watch item: crowdsec → `172.66.154.109` (Cloudflare dedicated-IP space).**
   Unidentified — SNI candidates (api/blocklists/smoke/app/version/hub).crowdsec.net all fail.
   Documented in `config/supply-chain/egress-baseline.yaml` under crowdsec. It WILL re-fire on
   the next crowdsec restart. To identify: capture SNI live during a controlled restart
   (`tcpdump -i any 'host 172.66.154.109'` + TLS clienthello parse), or enumerate endpoints in
   crowdsec's config/docs. Only allowlist after identification.
3. **Remediation drill (Trajectory 1, deferred).** The webhook path was tested with a direct
   synthetic POST, but a full drill — induced SLO burn → alertmanager routing →
   webhook → playbook → pre-action snapshot → Discord trail — has NOT run. The routing only
   fires on `SLOBurnRateTier1/2`; design a safe induction (e.g. blackbox target to a dead
   endpoint in a scrap SLO) rather than degrading a real service.
4. **Monthly update loop regression check.** Next `monthly-update.sh` run mass-restarts
   services; the egress observatory should now stay quiet (L-076 re-baseline). If it fires,
   it's either a new legitimate restart-time destination (extend baseline, same procedure as
   PR #296) or the watch item resurfacing.
5. **ADR-031 Phase 3 — gated on Pi 5 purchase.** All pre-build done in both repos
   (GH#292 is the build-evening checklist; design doc
   `docs/97-plans/2026-06-12-adr031-phase3-design-node-b-vip.md`). IPs: VIP `192.168.1.72`,
   node B `192.168.1.169`. At hardware arrival the owner does the UDM DHCP reservation first.
   htpc-mgmt note: routine resolver Ansible runs need `--limit raspberrypi` until node B exists.
6. **Trajectory backlog (owner-approved order: T3 → T2 → T1 tail).** Unblocked next-session
   candidates: **Tier 3 signature verification** (plan approved, no gate, roadmap-listed) and
   the remaining T1 items (Grafana dashboards-as-code export, script-estate consolidation,
   `promtool check rules` in pre-commit — note the alert *test suite* exists at
   `config/prometheus/tests/`, run via podman cp + `promtool test rules`). Open issues:
   GH#284 (session audit), GH#277 (HostDown inhibit lumping — NOT fixed by today's
   CadvisorDown inhibit, which is separate), GH#274 (network placement), GH#267 (scrub timers;
   note `btrfs-scrub-internal.service` failed by timeout 2026-06-10, pre-existing).
7. **Process guardrail (cost a PR today):** stacked-PR merge order is
   `gh pr edit <child> --base main` FIRST, then delete the parent branch. Deleting the parent
   branch first CLOSES the child irrecoverably (recovery = recreate PR from the intact branch).

## Where the context lives

- Strategy: `docs/97-plans/2026-06-12-strategic-development-trajectories-2026H2.md` (the audit
  report + three trajectories) and local `docs/96-project-supervisor/roadmap.md`
- Lessons added today: L-076 (steady-state baselines blind to event-driven behavior) in
  `docs/96-project-supervisor/lessons.md`
- Session memory: `project_2026h2_trajectories`, `project_dns_resolver_ha` (both current as of
  this handoff)
