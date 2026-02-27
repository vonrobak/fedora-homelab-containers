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

### Batch archive: 2026-02-27

**Archived:** 2026-02-27
**Reason:** Audit of scripts/ directory — one-off fixes, applied migrations, completed tests, and superseded tools.

**One-off fixes (applied, permanent):**
- `fix-podman-secrets.sh` — Converted file secrets to Podman secrets (on disk only, never git-tracked due to secrets content)
- `fix-immich-ml-healthcheck.sh` — Replaced curl healthcheck with wget (superseded by v2)
- `fix-immich-ml-healthcheck-v2.sh` — Python3 healthcheck fix (applied, now in quadlet)
- `migrate-to-container-slice.sh` — Added Slice=container.slice to all quadlets
- `apply-resource-limits.sh` — Applied MemoryHigh/MemoryMax to services
- `optimize-permissions.sh` — Standardized subvol permissions + POSIX ACLs (ADR-019)
- `cleanup-samba-and-ocis.sh` — Decommissioned Samba (ADR-019)
- `verify-dns-fix-post-reboot.sh` — Verified static IP DNS fix post-reboot (ADR-018)

**Diagnostics (issue resolved):**
- `diagnose-redis-immich.sh` — Redis health validation debugging
- `investigate-memory-leak.sh` — Memory leak investigation

**Test/prototype scripts (real automation in place):**
- `test-yubikey-ssh.sh` — YubiKey SSH auth testing
- `monitor-ssh-tests.sh` — SSH test monitoring from remote host
- `test-predictive-trigger.sh` — Predictive maintenance integration test
- `test-slo-webhook-integration.sh` — SLO webhook→remediation flow test
- `test-webhook-remediation.sh` — Alertmanager→webhook end-to-end test
- `verify-autonomous-outcome.sh` — Phase 4 verification prototype (not yet integrated)

**Superseded tools:**
- `compare-quadlets.sh` — Replaced by `daily-drift-check.sh` + `check-drift.sh`
- `deploy-immich-gpu-acceleration.sh` — Failed ROCm attempt (iGPU incompatible)
- `detect-gpu-capabilities.sh` — Companion to failed GPU acceleration
- `generate-service-catalog.sh` — Superseded by `generate-service-catalog-simple.sh`
- `organize-docs.sh` — One-time documentation reorganization
- `homepage-add-api-key.sh` — One-time Homepage widget configuration

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
