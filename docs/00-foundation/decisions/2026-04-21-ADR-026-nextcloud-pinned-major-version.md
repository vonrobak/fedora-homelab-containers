# ADR-026: Pin Nextcloud to Major Version (amends ADR-015)

**Date:** 2026-04-21
**Status:** Accepted
**Amends:** ADR-015 (container update strategy)
**Driver:** `docs/98-journals/2026-04-21-nextcloud-slo-collapse-postmortem.md`

## Context

ADR-015 lists Nextcloud pinning as *optional* ("if stability issues arise"). The 2026-04-21 postmortem demonstrates that optional framing is incorrect for this service class:

- On 2026-04-06, an unattended image pull advanced Nextcloud from 32.x to 33.x.
- The container entrypoint race (advances `version.php` before `occ upgrade` completes) left the instance with `needsDbUpgrade=true` and effectively locked in maintenance mode.
- Sync clients backed off silently for ~8 days. 30-day availability dropped to 86.48% (27× error-budget burn).
- Existing controls — healthcheck restart loop, `post-update-health-check.sh` auto-remediation, SLO burn-rate alerts — all missed the failure because the pull path bypassed the wrapped update flow and the failure mode was low-volume (sub-rate-threshold).

Nextcloud owns a database schema. Every major-version upgrade carries a migration. The failure class is identical to PostgreSQL, MariaDB, and Immich — all of which ADR-015 already treats as pinned exceptions.

## Decision

Nextcloud joins the pinned list. `Image=` pins to a major tag (e.g. `nextcloud:33`); minor/patch updates within the major flow normally. Major-version upgrades are hands-on, scheduled operations — same model as PostgreSQL, MariaDB, and Immich.

This decision updates ADR-015's "Services Using Pinned Versions" list:

**Before (ADR-015):**
> **Optional** (if stability issues arise):
> - Nextcloud: `30` (major version only, app compatibility)

**After (this ADR):**
> **Required — database schema owner:**
> - Nextcloud: pinned to major tag (currently `33`)

## Consequences

**Positive:**
- Eliminates the silent 8-day failure mode — an unattended pull can no longer cross a major boundary.
- Minor/patch releases within the pinned major still flow automatically, preserving security-patch cadence.
- Aligns Nextcloud's treatment with other schema-owning services, removing the ADR-015 inconsistency.

**Negative:**
- Quarterly-ish planned work to review and bump the major pin when ready.
- Snapshot-before-upgrade still required (covered by the wrapped weekly update path and the pre-pull snapshot work tracked in the postmortem follow-ups).

## Scope

This ADR is strictly about the image tag on `nextcloud.container`. Related work in the postmortem follow-ups is tracked separately:

- **`AutoUpdate=registry` removal on stateful services** — GitHub issue #162.
- **`NextcloudMaintenanceStuck` state-based alert** — GitHub issue #164.
- **Pre-pull BTRFS snapshot in weekly wrapper** — GitHub issue #166.
- **`audit-update-paths.sh` regression guard** — GitHub issue #168.

## References

- ADR-015 — Container update strategy (amended by this ADR).
- `docs/98-journals/2026-04-21-nextcloud-slo-collapse-postmortem.md` — incident write-up and follow-up list.
- `scripts/post-update-health-check.sh:76-116` — existing auto-remediation logic (intact, just not reachable on all update paths).
