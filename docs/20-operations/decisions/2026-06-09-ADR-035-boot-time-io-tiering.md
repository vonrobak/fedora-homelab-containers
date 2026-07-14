---
type: ADR
title: "ADR-035: Boot-Time I/O Tiering for Service Startup"
description: "ADR introducing boot-time I/O tiering via StartupIOWeight to demote heavy TSDB/WAL replayers (Prometheus, Loki, Grafana) during post-reboot storms."
sensitivity: public
created: 2026-06-09
updated: 2026-06-09
---

# ADR-035: Boot-Time I/O Tiering for Service Startup

**Date:** 2026-06-09
**Status:** Accepted (Tier-C reclassification of prometheus/loki/grafana implemented;
full validation on next reboot, per the established boot-storm verification practice)

---

## Context

After a reboot on 2026-06-09 the host thrashed for ~7 minutes: load peaked ~18 and the
GNOME terminal (ptyxis) took minutes to open. The owner's first read was "podman is in a
death loop." Systematic debugging refuted that:

- **Not a death loop.** One `podman system service` (the API socket), zero restarting or
  failed container units, all ~30 containers active.
- **Not memory.** 24 GiB free throughout; swap barely touched. PSI showed memory pressure
  ~0%.
- **It was I/O saturation.** `/proc/pressure/io` showed `full avg300 ≈ 40%` — at the peak,
  *all* tasks were stalled on disk 40% of the time. The frozen terminal was a *symptom* of
  I/O starvation, not podman looping. The storm self-resolved (load → 0.47).

The boot journal pinned the dominant I/O producers by their wall-clock ≫ CPU-time ratios
(the signature of a process blocked on disk, not spinning):

| Service | Boot recovery work | CPU vs wall clock |
|---|---|---|
| prometheus | TSDB mmap-chunk replay 3.1 s + WAL replay 16.5 s (~20 s reads) | — |
| loki | WAL checkpoint + segment recovery | **2.1 s CPU over 3 min 5 s wall** |
| cadvisor | "recovery of all containers" | 0.49 s CPU over 1 min 56 s wall |

### Why the existing mitigation didn't catch this

A prior boot storm (2026-05-27, PR #242 — documented in
`docs/98-journals/2026-05-27-post-update-boot-storm-and-homepage-decom.md`) introduced a
per-unit startup-tiering scheme using `StartupCPUWeight` / `StartupIOWeight`, which apply
**only while the user manager is in `starting` state and revert once `default.target` is
reached** — so they carry zero steady-state cost. That scheme defined:

- **Tier A (weight 200, "keystones"):** Traefik, the 4 databases, the 3 Redis instances,
  Authelia. Win the disk during boot.
- **Tier C (weight 50, "ancillaries"):** the 6 exporters, unpoller, cadvisor, promtail,
  alert-discord-relay, unifi-syslog. Yield during the fan-out.
- **Tier B (implicit default 100):** "apps — unchanged."

The scheme was **documented only in a journal, never formalized**, and its classification
was structural ("keystones vs exporters"), not measured. **Prometheus, Loki, and Grafana —
the three heaviest I/O producers in the fleet — fell into "Tier B, apps, unchanged" by
omission.** They were never demoted, so on every reboot their TSDB/WAL recovery competed at
default weight (100) against the application tier and saturated the shared BTRFS pool
(`/dev/sdc`, an HDD on the `bfq` scheduler, which honours cgroup `io.weight`). The
slice-level companion drop-in (`container.slice.d/boot-priority.conf`, yielding the whole
container slice to `user.slice`) was intact, but it cannot help once these units' recovery
I/O saturates the disk in absolute terms.

This ADR **formalizes the tier model** and **corrects the misclassification** so the gap is
a tracked standard rather than journal lore.

## Decision

### D1 — The boot-tier model is a standard, not lore

Every service that starts at boot is assigned to one of three startup tiers via
`StartupCPUWeight` / `StartupIOWeight` in the quadlet `[Service]` section. These weights
apply only during `default.target` assembly and revert afterward (no steady-state effect).

| Tier | Weight | Membership rule |
|---|---|---|
| **A — keystone** | 200 | Reverse proxy, databases, caches, auth — anything the app tier *functionally blocks on*. Must come up first. |
| **B — application** | 100 (default, implicit) | User-facing application containers. Left at default. |
| **C — ancillary / deferrable** | 50 | Observability, exporters, log shippers, and **any service whose boot-time I/O is heavy but whose availability is not on a user's critical path** — it can come up after the app tier settles. Also gets `After=traefik.service` to stage it past the storm peak. |

**Classification is by measured boot I/O and criticality, not by category label.** A
"monitoring" service is not automatically Tier C, and Tier B is not a default dumping
ground: if a service does heavy recovery I/O at boot and nothing user-facing waits on it,
it belongs in Tier C regardless of what kind of service it is.

### D2 — Reclassify prometheus, loki, grafana from implicit Tier B → Tier C

Each gains, in its quadlet:

```ini
[Unit]
After=… traefik.service          # stage past the storm peak

[Service]
StartupCPUWeight=50
StartupIOWeight=50
```

Prometheus and Loki store on `/mnt/btrfs-pool/subvol8-db` (HDD/`bfq`, per ADR-029), where
`StartupIOWeight` is effective. Grafana stores on the SSD (`/home`, `none` scheduler) where
IOWeight has little effect — it is tiered for consistency and for the CPU-weight and
ordering benefit. Alertmanager, alert-discord-relay, and the exporters **stay early**
(un-deferred) so the alerting path is not blinded during the post-reboot window.

### D3 — Companion slice drop-in remains out of git

`~/.config/systemd/user/container.slice.d/boot-priority.conf` (demotes `container.slice`
relative to `user.slice` so the desktop session stays responsive) is user-systemd config,
not container infrastructure, and stays out of version control — consistent with the
2026-05-27 decision. Its presence is a precondition for the desktop-responsiveness benefit.

## Consequences

**Positive**
- The two heaviest boot I/O producers (Prometheus, Loki) now yield to the DB/app tiers on
  the shared HDD during boot, flattening the I/O storm and shortening the window in which
  the desktop session is starved.
- The tier model is now a tracked standard with an explicit classification rule, so future
  services are placed deliberately and this class of regression is less likely to recur.

**Negative / accepted trade-offs**
- The monitoring **data-plane** (metrics scraping, dashboards, log ingestion) comes up
  slightly later after a reboot. The **alerting path** (Alertmanager + relay) is
  intentionally *not* deferred, so this is a brief gap in retrospective data, not in paging.
- `Startup*Weight` only governs the `starting` phase. Where a service is marked `active`
  (podman sdnotify on container start) **before** its internal recovery finishes, some
  recovery I/O can spill past `default.target` and escape the weighting. This is a known
  limitation, not a defect (see Future Work).

**Neutral**
- Zero steady-state cost: weights revert once boot completes.

## Future Work (if the storm still bites on the next reboot)

Ship this minimal, in-house-pattern fix first and **measure one reboot**. If I/O pressure
during cold boot is still unacceptable, escalate in this order:

1. Order the heavy monitoring units after the data tier is *ready* (not just started) —
   e.g. `Notify=healthy` on the databases so `After=` waits for real readiness.
2. Add an adaptive **I/O-quiesce gate**: a oneshot that polls `/proc/pressure/io` and
   releases a `homelab-monitoring.target` when `full avg10` is sustainedly low or a hard
   timeout (~180 s) elapses, fail-open. Considered and deliberately deferred here as
   over-engineered for a self-resolving, infrequent event.

## References

- `docs/98-journals/2026-05-27-post-update-boot-storm-and-homepage-decom.md` — origin of the
  tier scheme (PR #242); this ADR formalizes and corrects it.
- `docs/98-journals/2026-06-09-reboot-io-storm-not-podman-deathloop.md` — this incident's
  debugging narrative.
- **ADR-029** — three-tier DB storage; places Prometheus/Loki data on `subvol8-db` (HDD),
  the device under contention.
- **ADR-003** — monitoring stack architecture (the services being tiered).
- **ADR-011** — service dependency mapping (sibling: startup ordering).

## Files Touched

- `quadlets/prometheus.container`, `quadlets/loki.container`, `quadlets/grafana.container` —
  `After=traefik.service` + `StartupCPUWeight=50` / `StartupIOWeight=50`.

**Verification (post-edit, pre-reboot):** `systemctl --user daemon-reload`; confirmed
`StartupCPUWeight=50 / StartupIOWeight=50` applied on all three via `systemctl --user show`;
`systemd-analyze --user verify` reports no ordering cycles. Full validation on next reboot:
`coredumpctl list --since=boot` empty, no `start operation timed out`, lower peak
`/proc/pressure/io`, ptyxis responsive within seconds.
