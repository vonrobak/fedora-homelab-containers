# Storage-Health Monitoring — SMART, dev-stats, Scrub

**Date:** 2026-06-09
**Context:** After verifying the backup loop end-to-end (db-dumps cover the migrated engines,
pruning bounded ~7.5 G local + Urd GFS offsite on LUKS2 drives), the remaining storage gap was
*hardware* health. The pool is **Single data profile — no live redundancy**, so a disk failure
is a restore event and bit rot isn't auto-repaired on data. Early warning was the missing
defense; built it. PRs #262–#265.

## Shipped
- **btrfs dev-stats** (root-free, 15 min) — per-device error counters; the continuous signal
  that catches a failing disk *between* scrubs.
- **SMART** (hourly, scoped sudo) — health / pending-reallocated-uncorrectable sectors / temp /
  NVMe wear into the Prometheus → Discord path (not just smartd's local mail).
- **Scheduled scrub** (monthly, staggered, Urd-coordinated) — bit-rot detection + metadata
  repair; alerts split `uncorrectable` (critical, restore) vs `corrected` (warning, disk
  whispering).
- 13 alerts; least-privilege sudoers (read-only `smartctl` + `btrfs scrub`, no wildcards,
  extends the existing btrfs grant). Guide: `docs/20-operations/guides/storage-health-monitoring.md`.

## Found on day one
- **sdc: 8 reallocated sectors** (stable) — the oldest pool disk (~4.7 y), now the known weak
  link / proactive-replacement candidate. Tuned the alert to fire on *increase*, not stable
  presence (no permanent nag).
- Aging HDD fleet (4–5 y); nvme0 at 71 % endurance. All SMART PASSED.

## Lessons
- **`btrfs scrub start --limit` silently skips devids on a multi-device fs** — it left pool
  devid 1 unlimited (~407 MiB/s, `io full` ~20 %). Throttle via **`btrfs scrub limit --all`**
  instead (reliable, verified live). 30 MiB/s/device → `io full` ~6–9 %, ~24 h per ~11 TiB pass.
  Pool only; /home (SSD) + idle backups scrub unlimited.
- **PSI `some` vs `full`:** a throttled scrub inflates `some` (it waits on its own rate budget) —
  looked alarming at 39 %. Only `full` (~5–9 %) means services are actually starved. Watch `full`.
- **A supervised first run earns its keep:** the throttle bug surfaced on a watched pass, not as
  a mystery-sluggish Sunday on a timer.

## Pending
Owner: `systemctl --user enable --now btrfs-scrub-{internal,backups}.timer` once the first
manual pool scrub (running, ~24 h) completes. Architecture / backups / capacity / early-warning
/ bit-rot detection are now all covered.
