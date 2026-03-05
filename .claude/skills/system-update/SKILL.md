---
name: system-update
description: Orchestrate safe system updates - graceful shutdown, image pulls, and post-reboot verification. Use before running dnf update + reboot.
---

# System Update

Dependency-aware shutdown, image update, and post-reboot verification for safe Fedora system updates.

## Pre-Update

```bash
~/containers/scripts/update-before-reboot.sh
```

Does 4 things in order:
1. **Snapshot** — captures running state to `data/update-snapshots/latest.json`
2. **Graceful shutdown** — 6-phase dependency-aware stop (supporting → apps → infra → auth → data → gateway)
3. **Image pull** — pulls latest for all tracked images
4. **Image prune** — removes unused layers

Then the user runs:
```bash
sudo dnf update -y && sudo reboot
```

## Post-Reboot

```bash
~/containers/scripts/post-reboot-verify.sh
```

Compares current state against the pre-update snapshot:
- Podman version changes
- Container count (all running?)
- Service health via systemd + container healthchecks
- Nextcloud DB upgrade auto-remediation

## Options

```bash
# Preview without stopping anything
~/containers/scripts/update-before-reboot.sh --dry-run

# Skip image pulls (for urgent kernel-only updates)
~/containers/scripts/update-before-reboot.sh --skip-pull

# Individual scripts
~/containers/scripts/graceful-shutdown.sh [--dry-run]
~/containers/scripts/pre-update-snapshot.sh
~/containers/scripts/post-reboot-verify.sh [--snapshot PATH]
```

## Notes

- Services auto-start on boot via `WantedBy=default.target` in quadlets
- Clean `podman stop` (exit 0) won't fight systemd's `Restart=on-failure`
- Snapshot comparison is best-effort — post-reboot verification runs health checks regardless
