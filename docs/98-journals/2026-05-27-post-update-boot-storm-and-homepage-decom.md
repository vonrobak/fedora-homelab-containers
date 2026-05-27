# Post-Update Boot Storm + Homepage Decommission

**Date:** 2026-05-27
**Context:** Triage of post-reboot crashes after `dnf update`, then a systematic boot-ordering audit, then an unrelated cleanup (homepage decom). Shipped as PR #242 (boot storm) and PR #243 (homepage). AUTO doc regen + this journal in a follow-up.

## What Happened

After running `update-before-reboot.sh` and `sudo dnf update -y`, the system rebooted. `post-reboot-verify.sh` reported all green, but GNOME surfaced two ABRT crash reports:

- `podman` crash dumps at 18:07:29 and 18:07:30
- `ptyxis` crash dump at 18:09:02

Ptyxis would not start; a process kill recovered it. The user wanted to know what happened, given the homelab had been declared "healthy" by automation.

## Root Cause (Single, Shared)

Cold-cache boot-storm contention. All three crashes have the same shape:

1. Kernel comes up. `podman-user-wait-network-online.service` blocks all containers until `network-online.target` fires at ~1m 30s into boot.
2. When that gate opens, **all 38 containers fan out in parallel**, contending for the rootless Podman storage layer, network plugin, SELinux relabeling, and BTRFS cold cache.
3. Lighter, less-anchored services (`blackbox-exporter`, `unifi-syslog`) exceeded their `TimeoutStartSec=60s` while waiting their turn at the runtime lock.
4. Systemd terminated them, then triggered `ExecStopPost=podman rm -v -f -i <name>` for cleanup. That `podman rm` **also hung** waiting on the same runtime lock — the Go core dump showed it parked in `parallel/ctr.ContainerOp` → `runtime.notesleep` on a channel.
5. After 30s of stop-post timeout, systemd sent SIGABRT → coredump. Two cores filed under ABRT.
6. Meanwhile, ptyxis (GNOME terminal) tried to spawn its bwrap-sandboxed helper agent during the same load peak, hit its own timeout, and GLib's `_g_log_abort` killed it on `G_LOG_LEVEL_ERROR`.

`post-reboot-verify.sh` reported green because by the time it ran, `Restart=on-failure` had already recovered both units (1 and 2 restarts respectively). The script samples post-recovery state, not the boot-storm window.

**The dnf update itself was not implicated:** podman version unchanged across the reboot per the verify script, and the crash signatures were timeout-induced SIGABRTs, not symbol-resolution failures of the kind a botched update would produce.

## Mitigation (PR #242)

Three layers, all `Startup*` directives — they apply only while user-manager is in `starting` state, then revert to normal weight once `default.target` is reached. So no steady-state behavior change.

**1. Timeout headroom** on the two units that timed out (blackbox-exporter, unifi-syslog): `TimeoutStartSec 60s → 180s`, `TimeoutStopSec → 60s`. This gives `ExecStopPost=podman rm` time to acquire the runtime lock instead of getting SIGABRT'd.

**2. Per-unit startup tiering** via `StartupCPUWeight` / `StartupIOWeight`:

- **Tier A (weight 200, 9 keystones):** Traefik, all 4 databases (postgresql-immich, nextcloud-db, forgejo-db, gathio-db), all 3 Redis instances, Authelia. Reverse proxy + gated dependencies come up first.
- **Tier C (weight 50, 11 ancillaries):** all 6 exporters, unpoller, cadvisor, promtail, alert-discord-relay, unifi-syslog. Yield during the storm.
- **Tier B (default 100):** apps — unchanged.

**3. Tail staggering** via `After=traefik.service` on 9 services with no functional heavyweight dependency. Traefik becoming active is the natural "system past the storm peak" signal.

**Slice-level companion (not in version control):**
`~/.config/systemd/user/container.slice.d/boot-priority.conf` adds `StartupIOWeight=50, StartupCPUWeight=50` at the slice level — the whole container fan-out yields to `user.slice` (GNOME session, ptyxis). This is what fixes the ptyxis-agent spawn timeout. It's user-systemd config, not container infrastructure, so it's not under git. The PR description calls this out.

Will be validated on the next reboot.

## Decommission (PR #243)

Unrelated to the boot-storm work, but the same session. Homepage dashboard was not in active use. Removed:

- `quadlets/homepage.container` + `config/homepage/` (full config tree)
- Two Traefik routers (`root-redirect` for `patriark.org`, `homepage-dashboard` for `home.patriark.org`) + the `homepage` service stanza
- 4 Podman secrets (locally, not in git)
- `quadlets/README.md` line entry
- `docs/10-services/guides/homepage-widget-configuration.md` (found during AUTO doc regen cleanup, archived alongside the rest)

Root domain `patriark.org` intentionally has no replacement route per user decision — subdomains only. Catch-all returns 404.

Archived at `/mnt/btrfs-pool/subvol1-docs/homelab/99-outbound/2026-05-27-homepage-decommission/` with quadlet, config tree, routers.yml excerpt, secrets list, the widget-config guide, and a `DECOMMISSION.md` with restore steps.

## Lessons Learned

### On root-cause analysis

- **Green health checks aren't proof of a clean boot.** `post-reboot-verify.sh` was honest about the *post-recovery* state — but the SIGABRT'd coredumps happened in the window before recovery, and the script can't see history. **When a host-side bug report (ABRT, GNOME) contradicts a self-test, trust the host-side report.** The systemd journal and `coredumpctl info` together gave the full timeline; the verify script gave a frame.
- **Shared root causes can wear different costumes.** A podman SIGABRT and a ptyxis g_log_abort look like different problems; both were the same boot storm starving different timeouts. **When two unrelated failures happen in the same ~2-minute window after a reboot, suspect a shared substrate (CPU, IO, lock contention) before going deep on either trace.**
- **Read the *failed* unit's stop-post path, not just its start path.** The actual coredump came from `ExecStopPost=podman rm`, not from `ExecStart`. The unit had already failed by the time the core was generated. The Go stack confirmed the rm call was blocked on the runtime lock — which is the diagnostic, not the start-timeout itself.

### On systemd boot ordering

- **`StartupCPUWeight` / `StartupIOWeight` are the right tool for boot-storm mitigation.** They apply only during `starting`, then become normal weights — so the production cost is zero, the boot benefit is real. Kubernetes' QoS classes do the same thing; this is systemd's native version.
- **`After=` is a scheduling barrier, not just a functional dependency.** Adding `After=traefik.service` to 9 lightweight services is technically a "lie" about dependencies — none of them actually need Traefik to function. But it's an effective and honest staging mechanism: Traefik becoming active is a real signal that the storm peak has passed. Better than `ExecStartPre=sleep N`.
- **Default user-systemd parallelism is unbounded.** With 38 leaf services hanging off `default.target` via `Wants=`, systemd fans them out as fast as their `After=` chains allow. Nothing throttles the rate. The slice-level `Startup*Weight` is the closest thing systemd offers to a concurrency cap — it doesn't limit *count* but does limit *share*, which is effectively the same thing under contention.
- **Trust but verify weight changes.** `systemctl --user show <unit> -p StartupCPUWeight,StartupIOWeight` confirms the parsed value, not just the file contents. Did this for all 20 units before declaring done.

### On working through this session

- **Two unrelated changesets in the same session deserve two PRs.** The boot work and homepage decom share nothing but a clock. Bundling them would have made the PR title meaningless and the revert path messier. Two PRs (#242, #243) gave clean review surfaces.
- **Outside-git companion changes need a flag in the PR description, not silence.** The slice drop-in is part of the fix but not in the diff. The PR description has to call this out so a future reviewer reproducing the fix on another machine knows to drop the file in place themselves.
- **Stale AUTO doc regens are dangerous.** The working tree had a pre-session AUTO doc regen showing `Services: 0/0` — a clearly broken orchestrator run. Committing it would have replaced the real service catalog with empty data. Verified the regen output (37/37 services) before trusting it.

## Files Touched

**PR #242 (fix/boot-storm-mitigation):** 20 quadlets — alert-discord-relay, authelia, blackbox-exporter, cadvisor, forgejo-db, gathio-db, nextcloud-db, nextcloud-redis, node_exporter, pihole-exporter, postgres-exporter, postgresql-immich, promtail, redis-authelia-exporter, redis-authelia, redis-immich-exporter, redis-immich, traefik, unifi-syslog, unpoller.

**PR #243 (chore/decom-homepage):** 12 files — `config/homepage/*` (9 deletes), `config/traefik/dynamic/routers.yml`, `quadlets/homepage.container` (delete), `quadlets/README.md`.

**Follow-up (this PR):** AUTO doc regen reflecting both merges + homepage doc archival + this journal.

**Not in any PR (user-systemd):** `~/.config/systemd/user/container.slice.d/boot-priority.conf`.

## Test Plan for Next Reboot

- `coredumpctl list --since=boot` — should be empty
- `journalctl --user -b -p 3` — no `start operation timed out` or `State 'stop-post' timed out`
- `systemd-analyze blame --user` — keystones faster, tail slower (intended)
- GNOME/ptyxis responsive within seconds of login, not minutes
- `podman ps | wc -l` — 37 (was 38 before homepage decom)
