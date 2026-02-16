# GNOME Shell Freeze, System Update Preparation

**Date:** 2026-02-16
**Type:** Incident recovery + operational improvement

## GNOME Shell Freeze

### Incident

The GNOME desktop on fedora-htpc became completely unresponsive. `gnome-shell` (PID 14415) was consuming 92% CPU. The system was accessible via SSH from MacBook Air but the local display was frozen.

**Symptoms observed (via SSH):**
- `gnome-shell` at 92% CPU in `top`
- `libinput` errors in journal related to Apple Magic Trackpad (Bluetooth)
- Desktop completely unresponsive (no mouse/keyboard input)
- All 27 containers were unaffected and running normally

### Resolution

```bash
# From MacBook Air via SSH
ssh fedora-htpc
sudo systemctl restart gdm
```

GDM restart killed the frozen gnome-shell, restarted the display manager, and presented a login screen. All containers continued running throughout -- rootless Podman containers managed by user systemd are independent of the desktop session.

### Root Cause Investigation Pointers

The freeze correlates with Apple Magic Trackpad Bluetooth connectivity. Known areas to investigate:
- `libinput` debug logging: `sudo libinput debug-events` during Bluetooth reconnection
- GNOME Shell extensions interfering with input handling
- Bluetooth power management causing reconnection storms
- Kernel 6.18.x regressions with Apple Bluetooth HID devices

This is a low-priority investigation since the workaround (`restart gdm`) is fast and non-destructive.

## Restart Policy Standardization

Changed `Restart=always` to `Restart=on-failure` in 10 quadlet files:

- crowdsec.container
- gathio.container
- gathio-db.container
- home-assistant.container
- jellyfin.container
- matter-server.container
- nextcloud.container
- nextcloud-db.container
- nextcloud-redis.container
- unpoller.container

**Rationale:** `Restart=on-failure` restarts on crashes (non-zero exit) but not on clean stops (exit 0 from `podman stop`). This prevents systemd from fighting with intentional shutdowns during updates. Services still auto-start on boot via `WantedBy=default.target`.

The remaining quadlets already used `Restart=on-failure` -- these 10 were legacy `Restart=always` from initial deployment.

## System Update Skill

Created `.claude/skills/system-update/SKILL.md` with pre-update and post-reboot workflows.

**New scripts:**
- `scripts/pre-update-snapshot.sh` -- Captures JSON state (Podman version, DB backend, containers, images, systemd units)
- `scripts/graceful-shutdown.sh` -- 6-phase dependency-aware shutdown (supporting -> apps -> infra -> auth -> data -> gateway)
- `scripts/post-reboot-verify.sh` -- Compares against snapshot, detects Podman migrations, runs health checks

**Modified:**
- `scripts/update-before-reboot.sh` -- Refactored as orchestrator calling snapshot -> shutdown -> pull -> prune

## Podman 5.8 Migration Expectations

The upcoming `dnf update` is expected to upgrade Podman from 5.7.1 to 5.8.x. Key change: BoltDB metadata backend is replaced by SQLite.

**Expected behavior:**
- Migration is automatic and transparent on first `podman` command after upgrade
- No user action required
- `podman info` will show the new backend
- `post-reboot-verify.sh` will detect and report the migration

**Risk:** Low. The migration has been tested in Podman 5.8 betas. Snapshot comparison will confirm container count matches post-reboot.
