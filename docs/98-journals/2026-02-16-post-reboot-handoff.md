# Post-Reboot Handoff

**Date:** 2026-02-16
**Context:** System update (dnf update + reboot) applied after GNOME freeze incident

## Quick Start

After reboot, run:

```bash
cd ~/containers
./scripts/post-reboot-verify.sh
```

This will:
1. Compare current state against the pre-update snapshot
2. Detect Podman version changes and DB backend migration
3. Check all 27 services are running
4. Run container health checks
5. Run Nextcloud DB upgrade check with auto-remediation
6. Send Discord notification with results

## Manual Verification Checklist

If you prefer to verify manually or need to troubleshoot:

```bash
# 1. Podman version (expect 5.8.x, was 5.7.1)
podman --version
rpm -q podman

# 2. DB backend migration (expect sqlite, was boltdb)
podman info | grep -i -A2 "database"

# 3. All 27 containers running
podman ps --format '{{.Names}}' | sort | wc -l
podman ps --format 'table {{.Names}}\t{{.Status}}' | sort

# 4. Critical service health
for svc in traefik authelia nextcloud immich-server prometheus grafana; do
    echo -n "$svc: "; systemctl --user is-active $svc.service
done

# 5. Container health checks
for c in traefik authelia nextcloud immich-server jellyfin home-assistant crowdsec; do
    echo -n "$c: "; podman healthcheck run $c 2>/dev/null && echo "healthy" || echo "unhealthy"
done

# 6. Full health score
./scripts/homelab-intel.sh
```

## Troubleshooting

### Service failed to start

```bash
# Check what happened
systemctl --user status <service>.service
journalctl --user -u <service>.service -n 50

# Restart it
systemctl --user restart <service>.service
```

### Podman migration failed

```bash
# Check podman is functional
podman info

# If corrupted, reset (last resort - containers recreated from quadlets)
podman system reset
systemctl --user daemon-reload
# Then start services manually or reboot
```

### Container count mismatch

```bash
# See what's missing
diff <(python3 -c "import json; [print(c['Names'][0]) for c in json.load(open('data/update-snapshots/latest.json'))['containers']['list']]" | sort) <(podman ps --format '{{.Names}}' | sort)

# Start missing service
systemctl --user start <service>.service
```

### Nextcloud DB upgrade pending

```bash
# Check status
podman exec -u www-data nextcloud php occ status

# Manual upgrade
podman exec -u www-data nextcloud php occ upgrade
podman exec -u www-data nextcloud php occ maintenance:mode --off
```

## Expected State After Successful Reboot

- **Podman:** 5.8.x (upgraded from 5.7.1)
- **DB backend:** SQLite (migrated from BoltDB)
- **Containers:** 27 running
- **Health score:** 100/100 (or close, may need a few minutes to stabilize)
- **All services:** Active and healthy
- **Pre-update snapshot:** `data/update-snapshots/latest.json`

## MEMORY.md Updates After Verification

After confirming successful reboot, update these in MEMORY.md:
- Podman version (5.7.1 -> actual new version)
- DB backend if changed (BoltDB -> SQLite)
- Kernel version if changed
- System update date
- Any new issues discovered
