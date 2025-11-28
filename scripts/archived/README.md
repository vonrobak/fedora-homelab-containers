# Archived Scripts

This directory contains scripts that have been superseded or are no longer in active use.

## Archive Policy

Scripts are archived (not deleted) when:
- They've been superseded by better implementations
- They were experimental and never reached production
- They served a one-time purpose that's complete

## Contents

### intelligence-2025-11/

**Archived:** 2025-11-28
**Reason:** Superseded by `homelab-intel.sh` and `predictive-analytics/`
**Original location:** `scripts/intelligence/`

Early attempt at trend analysis system. The README noted "syntax issues" in the main analyzer. Functionality has been replaced by:
- `homelab-intel.sh` - Core health scoring and JSON reports
- `predictive-analytics/` - Resource exhaustion forecasting
- `weekly-intelligence-report.sh` - Trend analysis with Discord integration

### homelab-snapshot.sh

**Archived:** 2025-11-28
**Reason:** Not scheduled, generates similar data to `homelab-intel.sh`
**Original location:** `scripts/homelab-snapshot.sh`
**Last used:** 2025-11-15

Comprehensive infrastructure state capture tool. Was useful during initial development but:
- Never added to scheduled timers
- `homelab-intel.sh` covers the critical health metrics
- Snapshot data went stale between manual runs
- The JSON output format overlapped with intel reports

**Note:** If detailed snapshots are needed again, this script still works - just not maintained.

---

## Restoring Archived Scripts

If you need to restore an archived script:

```bash
# Restore single file
mv scripts/archived/homelab-snapshot.sh scripts/

# Restore directory
mv scripts/archived/intelligence-2025-11 scripts/intelligence
```

Then update `docs/20-operations/guides/automation-reference.md` to reflect the change.
