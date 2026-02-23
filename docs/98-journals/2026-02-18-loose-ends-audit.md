# Loose Ends Audit: Mid-December 2025 to February 2026

**Date:** 2026-02-18
**Type:** Retrospective audit
**Scope:** Journals (28 entries), plans (27 files), PRs (#58-#97), commit history (80 commits), system state verification
**Method:** Cross-referenced documented intentions against current system state

---

## Executive Summary

The homelab is in excellent operational shape -- 27/27 containers running, 26/27 healthy, stable 36h uptime. But scattered across two months of journals, plans, and PR reviews are a significant number of loose ends: items planned but never executed, review suggestions never acted on, and documentation that has drifted from reality. This audit catalogs them all.

---

## Tier 1: Significant Unfinished Work

### 1.1 Disaster Recovery Plan: Fully Planned, Never Executed | User has verified this, and it should be documented in one of the DR runbooks located here: /home/patriark/containers/docs/20-operations/runbooks

**Source:** `docs/97-plans/PROJECT-A-DISASTER-RECOVERY-PLAN.md`
**Planned:** November 2025 (8-10 hours across 3 sessions)
**Current status:** 0% executed

A detailed 450+ line restore validation script was designed. Systemd timer configuration, Prometheus alert rules, Grafana dashboard specs, and four runbook templates were all specified. None were implemented. The plan called for:

- `test-backup-restore.sh` script -- never created
- Monthly automated restore validation timer -- never registered
- Backup health Grafana dashboard -- never built
- DR runbooks (SSD failure, BTRFS corruption, accidental deletion, total catastrophe) -- templates exist in plan, not in `docs/20-operations/runbooks/`

**Why this matters:** Untested backups are not backups. BTRFS snapshots run daily, external backups run weekly, but there is no automated validation that any of them can actually restore.

**Effort:** 8-10 hours.

### 1.2 Nextcloud Testing Phases 2-4: Two Months Waiting

**Source:** Journal `2025-12-20`, MEMORY.md user priorities
**Identified:** December 20, 2025
**Current status:** Not started

Phase 1 (deployment + security hardening) completed December 20. The remaining phases were listed as a user priority:
- Phase 2: Conflict resolution testing
- Phase 3: Sharing workflows
- Phase 4: VFS (Virtual File System) testing

Nextcloud has been stable at v32.0.6 since mid-February, syncing across all five devices. The risk here is unknown-unknowns -- edge cases in conflict handling or sharing that only surface under testing.

### 1.3 Immich Operational Excellence: Plan Ready, Phases 2-6 Not documented but user believes they were done. Put low priority on 1.3

**Source:** `.claude/plans/immich-operational-excellence.md`
**Planned:** February 7, 2026
**Current status:** Phase 1 (server verification + monitoring fix) completed. User comment: Phases 2-6 completed but not documented. The user has some uncertainty about phase 5-6 being completed or not, but Immich is confirmed working very well across all devices.

The remaining phases cover:
- **Phase 2:** Multi-device client testing (iOS, iPad, browser, gaming PC)
- **Phase 3:** Cross-device sync and consistency verification
- **Phase 4:** Resilience and edge case testing
- **Phase 5:** SLO and alert remediation (502 root cause, SLO target evaluation)
- **Phase 6:** Documentation and service guide update


**Key findings from Phase 1 that remain unaddressed:**
- No direct Prometheus scrape of Immich application metrics
- Immich SLO was 96.8% (target 99.9%) due to residual Feb 2 incident 502s -- these should have rolled out of the 30d window by now, worth re-checking
- Both the above should be investigated as the user believes the first is solved and for the second, SLO levels are confirmed to be at a much higher rate currently. 



### 1.4 Remediation Dashboard: 56 Days Overdue (low priority from user)

**Source:** Journal `2025-12-26`
**Scheduled:** Late January 2026 (after 30 days of baseline data)
**Current status:** Never created | user comment: it does seem to be created? https://grafana.patriark.org/d/remediation-effectiveness/

The remediation system has been running since December 24 with metrics exported to Prometheus. A Grafana dashboard was planned to visualize remediation effectiveness, trends, and ROI. The 30-day data prerequisite was met in late January.

---

## Tier 2: Infrastructure Gaps

### 2.1 Loki Has No Container Healthcheck

**Source:** MEMORY.md known gaps, journal `2026-02-08`
**Current state verified:** `podman ps` shows Loki as `Up 36 hours` (no `(healthy)` tag) -- the ONLY container without a healthcheck.

The quadlet has no `HealthCmd` directive. The Loki container uses a scratch/distroless image with no shell, making traditional healthcheck approaches difficult. The `:3100/ready` endpoint exists.

**Note:** Promtail healthcheck WAS implemented (PR #90, `/dev/tcp` approach) -- MEMORY.md still lists this as a gap, which is now inaccurate.

**Options:**
- Use `podman healthcheck` with an external curl from the host
- Switch to Grafana's Loki Alpine image (has shell)
- Accept the gap with external monitoring via Prometheus `up{job="loki"}`

### 2.2 Memory Limits: Only 5 of 27 Containers | user comment: (this assessment seems to be flawed, as the current architecture relies on MemoryHigh and MemoryMax arguments - this should not be give much priority)

**Source:** Journal `2025-12-26`
**Current state verified:** Only 5 containers have `Memory=` in their quadlets:

| Container | Limit |
|-----------|-------|
| prometheus | 1G |
| alertmanager | 256M |
| postgresql-immich | 1G |
| node_exporter | 128M |
| immich-ml | 4G |

Missing from all other 22 containers, including high-memory services: immich-server (~280MB), jellyfin (~200MB idle, 1GB transcoding), grafana (~200MB), nextcloud (~200MB), loki (~200MB).

The December 26 journal identified this as in-progress work but only the first batch was completed.

### 2.3 Home Assistant Has No SLO (this is high priority)

**Source:** Cross-reference of `slo-recording-rules.yml` against services
**Current state verified:** No Home Assistant recording rules exist in the SLO framework.

This is notable because HA was the service *most affected* by the WebSocket `code=0` bug (15.6% false failure rate, 437 miscounted connections over 30 days, documented February 7). SLO rules were added for Jellyfin, Immich, Authelia, and Nextcloud, but not for Home Assistant despite it being a critical service with active WebSocket usage.

### 2.4 WebSocket `code=0` Fix Not in Deployment Templates (nice to have)

**Source:** Journal `2026-02-07` (explicit note: "should be added to deployment pattern templates")
**Current state verified:** No `code=~"0|..."` patterns exist in `.claude/skills/homelab-deployment/`

The fix was applied to all production SLO rules (recording rules + burn rate rules) but the journal explicitly flagged that deployment templates need updating. Any future service added to SLO monitoring via the deployment skill would inherit the old bug.

### 2.5 System SSD at 70% (Was 64%) - this should be investigated against the auto-remediation framework - the likely culprit is high number of btrfs snapshots which the user can manually delete when space gets tight

**Source:** `df -h /` shows `/dev/nvme0n1p3 118G 82G 36G 70%`
**MEMORY.md claims:** "System SSD: 64% (118GB)"

The SSD has gained 6 percentage points since MEMORY.md was last updated. At 70%, this is approaching the 75% warning threshold documented in CLAUDE.md. Not urgent, but trending in the wrong direction.

---

## Tier 3: PR Review Suggestions Never Acted On

These are suggestions from code reviews (all by Claude Sonnet) that were marked "non-blocking" but represent real improvement opportunities.

### PR #85 (Skill Stack Alignment, Feb 7)

1. **Static IP allocation undocumented** -- Templates show `{{STATIC_IP_REVERSE_PROXY}}` placeholders but `deploy-from-pattern.sh` doesn't populate them. No documentation on how to allocate IPs.
2. **Podman secret creation workflow missing** -- `database-service.yml` references `db-password` secret but no creation workflow is documented.

### PR #90 (Field Guide v3, Timer Fixes, Promtail Healthcheck, Feb 14)

3. **Timeout protection for podman commands** in `weekly-intelligence-report.sh` -- `timeout 5 podman ps -q` instead of bare podman calls. Prevents hung reports if Podman hangs.
4. **"Default Route?" column** in Network Architecture table in the Field Guide -- helps operators quickly identify which networks provide internet access.

### PR #92 (Auto-Documentation Rewrite, Feb 14)

5. **Image name truncation bug** -- Container image names get truncated at 50 characters, losing version tags.
6. **Service name mapping gaps** -- Only 2 mappings defined (immich-server, home-assistant) in `generate-service-catalog-simple.sh:38-46`. URL lookup fails for unmapped services.
7. **Performance optimization** -- 4 separate `podman ps` calls could be 1-2 with batching. 24+ `podman network inspect` calls for 8 networks.
8. **Error handling** -- Scripts silently fail when config files are missing (routers.yml, middleware.yml).

### PR #96 (Jellyfin CSP Hardening, Feb 15)

9. **Verify `unsafe-eval` is actually required** -- Modern webpack may not need it. Test with browser DevTools CSP violation filter.
10. **CSP reporting** -- Add `report-uri` directive to detect future CSP regressions.
11. **Inline documentation comment** explaining why `unsafe-eval` is needed and when it was last verified.

---

## Tier 4: Documentation Drift

### 4.1 MEMORY.md Inaccuracies

| Claim | Reality |
|-------|---------|
| "Loki and Promtail have no container healthchecks" | Promtail fixed in PR #90 (Feb 14). Only Loki remains. |
| "System SSD: 64% (118GB)" | Now 70% (82GB used of 118GB) |
| "immich-ml 300s inactivity timeout causes transient ML failures" | May be fixed in v2.5.5 -- never re-verified |

### 4.2 Loki Ingestion of Decision Logs: Never Started

**Source:** Journal `2025-12-26`, planned as "Loki Phase 1"
**Status:** Remediation decision logs still write to JSONL files only, not ingested into Loki.

This means remediation history is not queryable via Grafana Explore, only via CLI scripts. The planned Promtail scrape configuration for JSONL format was never added.

### 4.3 Webhook HMAC Authentication: Recommended, Never Implemented

**Source:** Journal `2025-12-26`
**Status:** Remediation webhook handler uses token-based authentication (query parameter). HMAC signature validation was recommended as an upgrade but never implemented. Acceptable for localhost-only access but would be a vulnerability if the endpoint is ever exposed.

---

## Tier 5: Completed Items Worth Noting

These were identified as loose ends but verified as resolved:

- **Immich circuit breaker/retry removed** from Traefik route (confirmed in `routers.yml:86` with explanatory comment)
- **Promtail healthcheck added** (PR #90, `/dev/tcp` bash approach)
- **WebSocket `code=0` fix applied** to all production SLO rules
- **Upload SLO NaN fix applied** with `clamp_min` approach
- **LowSnapshotCount alert** disabled (commented out, monitoring via Grafana dashboard instead)
- **Immich service guide updated** to v2.5.5 with correct URLs and storage paths (Feb 8)
- **Nextcloud auto-update race condition** remediation working (`needsDbUpgrade: false` verified)
- **Autonomous operations cooldown** mechanism implemented in `autonomous-execute.sh` (5min-1hr per action type)

---

## Recommended Priority Order

If tackling these, here's a suggested sequence based on risk vs. effort:

| Priority | Item | Effort | Risk if Ignored |
|----------|------|--------|-----------------|
| 1 | Fix MEMORY.md inaccuracies (4.1) | 5 min | Low, but accumulates confusion | User comment: seems important. MEMORY.md should be accurate.
| 2 | Memory limits on remaining containers (2.2) | 1 hour | Runaway container could OOM the host | User comment: see above. This is solved through Memory High and MemoryMax configs. Memory syntax configs should deprecate
| 3 | SSD usage investigation (2.5) | 30 min | Approaching 75% threshold | User comment: the user has good assessment of this situation. BTRFS snapshots primary driver of space utilization.
| 4 | Nextcloud testing phases 2-4 (1.2) | 2-4 hours | Unknown edge cases in production | User comment: nice to have, but not need to have
| 5 | Loki healthcheck (2.1) | 30 min | Blind spot in container health | User comment: this has been tried fixed before. I seem to remember it being hard to fix because the image is so minimal
| 6 | Home Assistant SLO rules (2.3) | 30 min | WebSocket-heavy service unmonitored | User: seems important and would be a nice addition. Should also be included in the already existing SLO Grafana dashboard.
| 7 | WebSocket fix in deployment templates (2.4) | 15 min | Future deployments inherit bug | User comment: could you explain this more fully before commiting to this?
| 8 | Immich operational excellence phases 2-6 (1.3) | 2 hours | Untested client behavior | User: low importance, most of this testing was done by user, but not adequately documented/journaled.
| 9 | Disaster recovery validation (1.1) | 8-10 hours | Untested backups | User comment: this has been thoroughly tested and verified. Should be information in some of the DR runbooks about this.
| 10 | Remediation dashboard (1.4) | 2 hours | No visibility into automation ROI | User comment: already exists? https://grafana.patriark.org/d/remediation-effectiveness/
| 11 | PR review suggestions (Tier 3) | 3-4 hours | Technical debt accumulation | User comment: nice to have.

---

## System Health Snapshot (2026-02-18)

| Metric | Value | Status |
|--------|-------|--------|
| Containers | 27/27 running | OK |
| Healthy | 26/27 | Loki has no healthcheck |
| Uptime | 36 hours (since Feb 16 reboot) | OK |
| System SSD | 70% (82G/118G) | Watch |
| BTRFS Pool | 74% (11T/15T, 3.9T free) | OK |
| Nextcloud | v32.0.6, needsDbUpgrade: false | OK |
| Immich | v2.5.5 (pinned) | OK |
| Timers | 53 active | OK |
