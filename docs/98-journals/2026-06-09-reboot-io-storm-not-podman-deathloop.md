# Reboot I/O Storm Misread as a Podman Death Loop

**Date:** 2026-06-09
**Context:** Post-reboot the host thrashed for ~7 minutes; ptyxis took minutes to open. The
owner's read was "podman is in a death loop starting all the containers." Systematic
debugging refuted that and traced it to a recurrence of the 2026-05-27 boot storm. Fix +
formalization landed as ADR-035.

## Symptom vs. cause

The reported symptom — frozen desktop, terminal taking minutes — *looked* like podman
spinning. Evidence said otherwise:

- **Not a death loop.** 1 `podman system service` (the API socket), 0 restarting/failed
  container units, all ~30 containers active. A loop would show podman process churn and
  restarting units; neither was present.
- **Not memory.** 24 GiB available throughout, swap ~146 MiB, PSI memory ~0%.
- **I/O saturation was the whole story.** `/proc/pressure/io` `full avg300 ≈ 40%` — every
  task stalled on disk 40% of the time at peak. Load had already fallen 18 → 0.47 by the
  time we finished looking; the storm self-resolves.

Dominant producers, proven by wall-clock ≫ CPU-time (blocked on disk, not spinning):
Prometheus TSDB+WAL replay (~20 s of reads) and Loki WAL recovery (**2.1 s CPU over 3 min
5 s wall**), with cAdvisor's container scan third. Root cause: ~30 containers cold-starting
in parallel on the BTRFS pool, and the three heaviest monitoring services were never
demoted in the 2026-05-27 boot-tier scheme (they sat at implicit Tier B / default weight
100). See ADR-035 for the fix.

## The red herring (lesson)

The first `ps` snapshot showed `localsearch-extractor` (GNOME file indexer) at **63 % CPU** —
the single largest consumer. The tempting hypothesis: the desktop indexer was crawling the
photo/music subvolumes (reached via the `~/Pictures → /mnt/btrfs-pool/...` symlinks) and
generating the I/O storm. A fix was even chosen on that basis (exclude the data dirs from
indexing).

**Verifying before acting killed the hypothesis.** `localsearch status` reported **34 files
indexed, idle** — it does *not* follow the directory symlinks out to the subvolumes; the
"63 %" was `ps` averaging a just-spawned, short-lived extractor over its brief lifetime. The
chosen `ignored-directories` setting would have been a **no-op**. It was not applied.

- **`ps %CPU` is a lifetime average, not an instantaneous rate.** A freshly-forked process
  that did one CPU burst reads deceptively high. Confirm "what is this process doing *now*"
  before building a theory on it.
- **Ask the component, don't infer from one surface.** `localsearch status` (34 files)
  settled in one command what a CPU snapshot only hinted at.
- **A chosen fix is not a committed fix.** The premise was re-checked between decision and
  execution; the no-op was caught before it shipped.

## Loose ends (benign, no action)

- Loki logged a WAL-segment corruption warning on recovery — Loki itself says *"No
  administrator action is needed"* (single ingester; at most seconds of recent logs lost).
  Classic unclean-shutdown artifact.
- `podman-user-wait-network-online.service` failed (timed out polling the system
  `network-online.target` from the user session). Cosmetic rootless-podman shim; all
  containers started regardless.

## Fix

ADR-035: reclassified prometheus / loki / grafana from implicit Tier B → Tier C
(`StartupCPUWeight=50`, `StartupIOWeight=50`, `After=traefik.service`), completing and
formalizing the 2026-05-27 scheme. Alerting path (Alertmanager + relay) intentionally left
early. Validation deferred to the next reboot.
