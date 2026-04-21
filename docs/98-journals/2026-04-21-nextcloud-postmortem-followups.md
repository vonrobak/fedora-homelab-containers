# Nextcloud Postmortem Follow-Ups — Session Wrap-Up

**Date:** 2026-04-21
**Context:** Execution session following the 8-day Nextcloud SLO collapse postmortem
**Postmortem (archived):** `docs/90-archive/2026-04-21-nextcloud-slo-collapse-postmortem.md`
**Outcome:** 6 of 8 follow-ups landed in-tree this session; 2 parked on deliberate decisions

---

## What happened this session

The postmortem enumerated 8 resilience improvements. Each was filed as a standalone GitHub issue (#161–#168) with severity + area labels, then most were executed in the same session. Everything is uncommitted — the tree is ready for review and a single squash commit.

## Issues filed and status

| # | Issue | Status | Notes |
|---|---|---|---|
| 161 | Pin Nextcloud to major | ✅ landed | `Image=nextcloud:33` in `nextcloud.container` |
| 162 | Strip `AutoUpdate=registry` from stateful services | ✅ landed | 15 quadlets cleaned (scope expanded beyond the original NC/Immich/Gathio trio once the audit ran) |
| 163 | Mask stock `podman-auto-update.timer` | ✅ landed | Timer + service masked; weekly wrapper remains the only path |
| 164 | `NextcloudMaintenanceStuck` state alert | ⏸ parked | Needs approach decision: blackbox exporter vs. textfile-sidecar |
| 165 | Low-volume sustained-5xx compensating alert | ✅ landed | New rule group in `slo-multiwindow-alerts.yml`; Nextcloud + HA, promtool clean, Prometheus reloaded |
| 166 | Pre-pull BTRFS snapshot in weekly wrapper | ⏸ parked | Needs retention policy + rollback runbook, own session |
| 167 | ADR-015 amendment for Nextcloud pin | ✅ landed | `ADR-026` supersedes the "optional" framing |
| 168 | `scripts/audit-update-paths.sh` | ✅ landed | Script catches 15→0 violations in the same session it was written — cheap regression guard |

## Scope surprise

Issue #162 was originally scoped to three services (NC, Immich, Gathio). Running the audit revealed **15 stateful services** carrying `AutoUpdate=registry`, including PostgreSQL, MariaDB, MongoDB, Authelia, Home Assistant, Matter Server, Loki, and Prometheus. All 15 were cleaned in this session. The broader scope makes the fix more valuable *and* makes #168 more important — without the regression guard, the next copy-paste deployment would reintroduce the problem silently.

The audit script's stateful-services list is now the canonical declaration of "which services must not auto-update outside the wrapped path." Changes to that list are cheap; removals need justification.

## What's parked, and why

**#164 (maintenance state alert).** The choice is architectural:

- **Blackbox exporter** — standard pattern, +1 container, reusable for any boolean-state probe. Recommended.
- **Textfile sidecar** (script + timer writing to `node_exporter` textfile dir) — lighter, no new container, but introduces another moving part.

Both are fine. Deferred to the next session so the decision isn't rushed.

**#166 (pre-pull snapshot).** Not technically hard — a BTRFS snapshot before the weekly `podman auto-update` run, with a retention policy of N most recent. The part that needs care is the rollback runbook: stop service → restore subvol → start with previous image, under time pressure, with a known-good procedure. Defer until #164 is in place so we're not stacking moving parts.

## Verification summary

- `./scripts/audit-update-paths.sh` → OK (0 violations)
- `systemctl --user is-enabled podman-auto-update.timer` → masked
- `systemctl --user is-enabled podman-auto-update-weekly.timer` → enabled
- `systemctl --user daemon-reload` → no errors
- All critical services (nextcloud, immich-server, authelia, home-assistant, prometheus, loki) → `active`
- `promtool check rules` on updated alert file → 34 rules found, SUCCESS
- Prometheus reloaded via SIGHUP → both new low-volume alerts load, state `unknown` pending first evaluation

## Uncommitted tree state

```
 M config/prometheus/alerts/slo-multiwindow-alerts.yml
 M quadlets/{authelia,gathio,gathio-db,home-assistant,immich-ml,
              immich-server,loki,matter-server,nextcloud,nextcloud-db,
              nextcloud-redis,postgresql-immich,prometheus,
              redis-authelia,redis-immich}.container
?? docs/00-foundation/decisions/2026-04-21-ADR-026-nextcloud-pinned-major-version.md
?? docs/90-archive/2026-04-21-nextcloud-slo-collapse-postmortem.md
?? docs/98-journals/2026-04-21-nextcloud-postmortem-followups.md  (this file)
?? scripts/audit-update-paths.sh
```

Plus one intentional move: the postmortem journal relocated to `docs/90-archive/` per `docs/CONTRIBUTING.md` archiving conventions, with an archival header added.

## Lessons that held up

- **Filing issues before executing is cheap and pays off fast.** By the time I started executing, each change had a self-contained brief — no context-switching cost. The issue bodies then became the commit justifications.
- **Audit scripts discover scope.** The audit for #168 was intended to lock in the #162 fix, but the script immediately exposed that #162 was under-scoped by 5×. The regression guard paid for itself inside the same hour it was written.
- **Deferring is not delaying.** Pinning Nextcloud (#161) and stripping AutoUpdate (#162) together close 80% of the recurrence risk for the April 6 failure mode. #164 and #166 are additive hardening. Shipping the 80% now without waiting for the 20% is the right call.

## References

- Postmortem (archived): `docs/90-archive/2026-04-21-nextcloud-slo-collapse-postmortem.md`
- New ADR: `docs/00-foundation/decisions/2026-04-21-ADR-026-nextcloud-pinned-major-version.md`
- New script: `scripts/audit-update-paths.sh`
- Updated alerts: `config/prometheus/alerts/slo-multiwindow-alerts.yml` (new group `low_volume_sustained_5xx_compensating`)
- Open GitHub issues: #164, #166
