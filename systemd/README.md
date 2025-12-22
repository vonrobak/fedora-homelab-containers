# Systemd User Units

Systemd service and timer units for automating homelab operations.

## Installation

Copy units to systemd user directory and enable:

```bash
cp ~/containers/systemd/*.{service,timer} ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now <unit>.timer
```

## Available Units

### auto-doc-update.timer / auto-doc-update.service

**Purpose:** Automatically regenerate all auto-documentation daily

**Schedule:** Daily at 07:00 (with 5-minute random delay)

**What it runs:** `~/containers/scripts/auto-doc-orchestrator.sh`

**Generates:**
- `docs/AUTO-SERVICE-CATALOG.md` - Running services inventory
- `docs/AUTO-NETWORK-TOPOLOGY.md` - Network diagrams
- `docs/AUTO-DEPENDENCY-GRAPH.md` - Service dependencies
- `docs/AUTO-DOCUMENTATION-INDEX.md` - Complete documentation index

**Installation:**
```bash
cp ~/containers/systemd/auto-doc-update.{service,timer} ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now auto-doc-update.timer
```

**Check status:**
```bash
systemctl --user list-timers auto-doc-update.timer
systemctl --user status auto-doc-update.service
journalctl --user -u auto-doc-update.service -f
```

**Manual trigger:**
```bash
systemctl --user start auto-doc-update.service
```

**Optional: Auto-commit changes**

Uncomment the `ExecStartPost` line in `auto-doc-update.service` to automatically
commit documentation changes to git after generation.

## Notes

- All units run as user services (not system-wide)
- Timer uses `Persistent=true` to catch up if system was off during scheduled time
- Random delay prevents resource contention if multiple timers run simultaneously
