# ADR-020: Daily External Backups with Incremental Sends

**Date:** 2026-03-21
**Status:** Superseded by ADR-021 (strategy decisions remain valid; shell script implementation replaced by Urd)
**Supersedes:** None (updates the weekly-only external backup model from initial implementation)

## Context

The BTRFS pool runs Single profile — no data redundancy. External backups to WD-18TB drives are the **only protection** against disk failure. The original design sent to external drives weekly (Saturdays only) because every send was a full send: multi-hour, high I/O, wearing on the SATA external drive.

The March 2026 operational excellence work (pinned parent mechanism, space pre-checks, stderr capture) proved that **incremental sends work reliably**. Tested results:
- Full send of 8GB: ~10 minutes
- Incremental send of 11GB: ~4 minutes
- Incremental sends transfer only changed extents, not entire subvolumes

With weekly-only external sends, the RPO was **7 days** — meaning up to a week of data could be lost if the pool fails between Saturday backups. For Tier 1 critical data (home directory, recordings, operational containers), this is unacceptable on a pool with no RAID.

Additionally, the offsite drive (WD-18TB1) will be stored at a friend's location and cycled roughly **every 3 months**. The old 15-daily local retention would delete the offsite pinned parent long before the drive returns, forcing a slow full send on every offsite cycle.

## Decision

### 1. Daily external sends for Tier 1/2

Replace the Saturday-only external gate with per-subvolume `EXTERNAL_SCHEDULE` configuration:
- **Tier 1/2 (critical/important):** External sends every night at 02:00
- **Tier 3 (standard):** External sends monthly (1st of month), local snapshots weekly (Saturdays)

This reduces RPO from 7 days to ~1 day for critical data.

### 2. Single nightly timer replaces daily+weekly

The daily timer runs the full script (no `--local-only`). The weekly timer is disabled. Per-subvolume schedule config determines when each subvolume creates snapshots and sends externally.

### 3. Graduated local retention (Time Machine-style)

Replace flat 15-daily retention with graduated tiers:
- **Last 14 days:** All daily snapshots kept
- **15-60 days:** 1 per week (newest in each ISO week)
- **61-90 days:** 1 per month (newest in each month)

~21 snapshots per subvolume, covering ~149 days (~5 months). This ensures the offsite drive's pinned parent survives even beyond the planned quarterly rotation cycle.

### 4. Dual pin files per drive

Separate `.last-external-parent-WD-18TB` and `.last-external-parent-WD-18TB1` files maintain independent incremental chains. Both pinned parents are protected during cleanup, regardless of which drive is currently mounted.

### 5. Simplified external retention

Replaced the never-implemented "weekly + monthly" external retention with a single count: 14 for Tier 1/2, existing counts for Tier 3. The cleanup function uses a single count — there is no weekly/monthly distinction in snapshot naming.

### 6. Graceful external drive absence

When no external drive is mounted, the script logs INFO and skips external sends without recording a failure or firing Discord alerts. This prevents false-alarm notifications when the offsite drive is at the remote location.

## Consequences

### Positive
- **RPO reduced from 7 days to ~1 day** for critical data
- **Offsite rotation safe** — graduated retention keeps snapshots for 3 months
- **No additional system load** — incremental sends take minutes, not hours
- **Simpler scheduling** — one timer instead of two
- **Drive-independent chains** — primary and offsite drives maintain separate incremental state

### Negative
- **External drive fills faster** — 14 daily snapshots vs 4-8 weekly. Mitigated by incremental deltas being small and 14-day retention cleanup.
- **Offsite drive needs full send after 3+ months without common parent** — if graduated retention is thinned before the drive returns, falls back to full send (slow but safe).

### Constraints
- **Offsite cycle must not exceed ~149 days** (the graduated retention window covers ~5 months). Beyond this, full sends are required.
- **Primary external drive must be always connected** for daily sends to work.

## Related
- Journal: `docs/98-journals/2026-03-21-backup-script-operational-excellence.md`
- Strategy guide: `docs/20-operations/guides/backup-strategy.md`
