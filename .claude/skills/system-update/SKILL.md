# System Update Skill

Orchestrates safe Fedora system updates (dnf + reboot) with state capture, dependency-aware shutdown, and post-reboot verification.

## Workflows

### Pre-Update (before `dnf update` + reboot)

Run when preparing for a system update:

```bash
~/containers/scripts/update-before-reboot.sh
```

**What it does (4 phases):**

1. **State Snapshot** (`pre-update-snapshot.sh`)
   - Captures Podman version, DB backend, running containers, images, systemd unit states
   - Saves JSON to `data/update-snapshots/YYYY-MM-DD_HHMMSS.json`
   - Symlinks `latest.json` for post-reboot comparison

2. **Graceful Shutdown** (`graceful-shutdown.sh`)
   - 6-phase dependency-aware stop:
     - Phase 1: Supporting (exporters, ML, matter-server)
     - Phase 2: Applications (nextcloud, jellyfin, immich, etc.)
     - Phase 3: Infrastructure (monitoring, crowdsec)
     - Phase 4: Auth (authelia)
     - Phase 5: Data (databases, caches)
     - Phase 6: Gateway (traefik)
   - 2-second pause between phases for clean TCP teardown
   - Verifies all containers stopped

3. **Image Pull** - Pulls latest for all tracked images
4. **Image Prune** - Removes unused layers

**After the script completes, the user runs:**
```bash
sudo dnf update -y
sudo reboot
```

### Post-Reboot (after system comes back up)

Run after system reboots:

```bash
~/containers/scripts/post-reboot-verify.sh
```

**What it does:**

1. **Snapshot Comparison**
   - Reads `data/update-snapshots/latest.json`
   - Compares Podman version (detects upgrades)
   - Detects DB backend migration (BoltDB -> SQLite for Podman 5.8+)
   - Validates container count matches pre-update state

2. **Service Health**
   - Checks all 27 services are active via systemd
   - Runs container health checks where configured
   - Lists any services that failed to start

3. **Detailed Health Check**
   - Wraps existing `post-update-health-check.sh`
   - Nextcloud DB upgrade detection and auto-remediation
   - Discord notification with results

4. **Summary**
   - Reports issues found
   - Provides troubleshooting commands
   - Suggests MEMORY.md updates if versions changed

## Options

```bash
# Dry run (shows what would happen without stopping anything)
~/containers/scripts/update-before-reboot.sh --dry-run
~/containers/scripts/graceful-shutdown.sh --dry-run

# Skip image pulls (faster, for urgent updates)
~/containers/scripts/update-before-reboot.sh --skip-pull

# Individual scripts (for targeted use)
~/containers/scripts/pre-update-snapshot.sh              # Just capture state
~/containers/scripts/graceful-shutdown.sh                # Just stop services
~/containers/scripts/post-reboot-verify.sh               # Just verify
~/containers/scripts/post-reboot-verify.sh --snapshot /path/to/specific.json
```

## File Locations

| File | Purpose |
|------|---------|
| `scripts/update-before-reboot.sh` | Orchestrator (snapshot + shutdown + pull + prune) |
| `scripts/pre-update-snapshot.sh` | Captures JSON state snapshot |
| `scripts/graceful-shutdown.sh` | 6-phase dependency-aware shutdown |
| `scripts/post-reboot-verify.sh` | Compares against snapshot + health checks |
| `scripts/post-update-health-check.sh` | Existing: Nextcloud DB upgrade + Discord notify |
| `data/update-snapshots/` | Snapshot storage (gitignored) |
| `data/update-snapshots/latest.json` | Symlink to most recent snapshot |

## Known Considerations

- **Podman 5.8 BoltDB -> SQLite migration**: Automatic, transparent. Podman handles it on first run after upgrade. Verify with `podman info` checking `store.graphDriverName`.
- **Restart policy**: All quadlets use `Restart=on-failure`. Services auto-start on boot via `WantedBy=default.target`, but clean `podman stop` (exit 0) won't fight systemd.
- **Snapshot comparison is best-effort**: If no snapshot exists, post-reboot-verify still runs all health checks.
