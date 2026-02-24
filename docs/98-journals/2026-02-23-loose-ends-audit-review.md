# Loose Ends Audit Review and Actions

**Date:** 2026-02-23
**Type:** Follow-up to 2026-02-18 loose ends audit
**Outcome:** 3 items addressed, several audit conclusions corrected

---

## Audit Corrections

The Feb 18 audit contained several inaccurate conclusions. Verified state:

| Audit Claim | Reality |
|-------------|---------|
| **1.1** DR "0% executed" | `test-backup-restore.sh` exists, runs monthly via systemd timer. DR-003 tested 2026-01-03 (100% success). DR-004 off-site verified. |
| **1.4** Remediation dashboard "never created" | Exists: `grafana.patriark.org/d/remediation-effectiveness/` (11 panels, provisioned) |
| **2.2** "Only 5 of 27 containers" have memory limits | All 27 have `MemoryHigh` + `MemoryMax` (systemd cgroup). The 5 it found also had redundant container-level `Memory=`. |
| **1.3** Immich phases 2-6 "never started" | User confirms phases 2-6 were completed but not journaled. Immich working well across all devices. |

## Actions Taken (PR #101)

**Home Assistant SLO monitoring added (item 2.3):**
- 99.5% availability target, WebSocket-aware (`code=~"0|2..|3.."`)
- Recording rules, burn rates (8 windows), 4-tier multiwindow alerts
- Added to Grafana SLO dashboard (all 6 panels) and monthly Discord report
- Current 30d availability: 97.43% (404s + client disconnections, will recover)

**Redundant Memory= removed from 5 quadlets (item 2.2):**
- alertmanager, immich-ml, node_exporter, postgresql-immich, prometheus
- `MemoryHigh`/`MemoryMax` in `[Service]` already enforce the same limits

**MEMORY.md updated (item 4.1):**
- SSD: 70% → 74%, Promtail removed from known gaps, immich-ml timeout noted as potentially fixed
- SLO coverage section added (6 services, 11 SLOs)

**Also fixed:** Immich SLO target label in Grafana (99.9% → 99.5%)

## Items Deprioritized by User

- **1.2** Nextcloud testing phases 2-4: nice to have, not need to have
- **1.3** Immich documentation: low priority, user-tested
- **2.5** SSD at 74%: user has good handle on it (BTRFS snapshots primary driver, automation in place)
- **2.1** Loki healthcheck: distroless image, genuinely hard to fix, external monitoring sufficient
- **2.4** WebSocket fix in templates: no SLO templates exist yet, low impact
