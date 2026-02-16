#!/bin/bash
# pre-update-snapshot.sh
# Capture system state before updates for post-reboot comparison
#
# Output: JSON snapshot at data/update-snapshots/YYYY-MM-DD_HHMMSS.json
# Usage: ./scripts/pre-update-snapshot.sh [--output-path PATH]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINERS_DIR="$(dirname "$SCRIPT_DIR")"
SNAPSHOT_DIR="$CONTAINERS_DIR/data/update-snapshots"

# Allow custom output path
SNAPSHOT_PATH="${1:-$SNAPSHOT_DIR/$(date +%Y-%m-%d_%H%M%S).json}"

mkdir -p "$(dirname "$SNAPSHOT_PATH")"

echo "Capturing pre-update snapshot..."

# Write components to temp files to avoid shell quoting issues with JSON
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

podman version --format json > "$TMPDIR/version.json" 2>/dev/null
podman info --format json > "$TMPDIR/info.json" 2>/dev/null
podman ps --all --format json > "$TMPDIR/containers.json" 2>/dev/null
podman images --format json > "$TMPDIR/images.json" 2>/dev/null

CONTAINER_COUNT=$(podman ps --format '{{.Names}}' 2>/dev/null | wc -l)

# Systemd unit states
export XDG_RUNTIME_DIR=/run/user/$(id -u)
systemctl --user list-units --type=service --all --no-pager --plain 2>/dev/null \
  | grep -E '\.service' \
  | awk '{print "{\"unit\":\"" $1 "\",\"load\":\"" $2 "\",\"active\":\"" $3 "\",\"sub\":\"" $4 "\"}"}' \
  | python3 -c "import sys; print('[' + ','.join(line.strip() for line in sys.stdin) + ']')" \
  > "$TMPDIR/units.json" 2>/dev/null || echo "[]" > "$TMPDIR/units.json"

# Kernel and package versions
KERNEL=$(uname -r)
PODMAN_PKG=$(rpm -q podman 2>/dev/null || echo "not-installed")
KERNEL_PKG=$(rpm -q kernel 2>/dev/null | tail -1 || echo "not-installed")

# Assemble snapshot using Python with file reads (no shell interpolation of JSON)
python3 - "$TMPDIR" "$SNAPSHOT_PATH" "$KERNEL" "$PODMAN_PKG" "$KERNEL_PKG" "$CONTAINER_COUNT" <<'PYEOF'
import json, sys, os
from datetime import datetime, timezone

tmpdir, snapshot_path, kernel, podman_pkg, kernel_pkg, container_count = sys.argv[1:7]

def load(name):
    with open(os.path.join(tmpdir, name)) as f:
        return json.load(f)

info = load("info.json")
db_backend = info.get("store", {}).get("graphDriverName", "unknown")

snapshot = {
    "timestamp": datetime.now(timezone.utc).astimezone().isoformat(),
    "kernel": kernel,
    "packages": {
        "podman": podman_pkg,
        "kernel": kernel_pkg,
    },
    "podman": {
        "version": load("version.json"),
        "db_backend": db_backend,
    },
    "containers": {
        "count": int(container_count),
        "list": load("containers.json"),
    },
    "images": load("images.json"),
    "systemd_units": load("units.json"),
}

with open(snapshot_path, "w") as f:
    json.dump(snapshot, f, indent=2)

print(f"Snapshot saved: {snapshot_path}")
print(f"  Podman: {podman_pkg}")
print(f"  DB backend: {db_backend}")
print(f"  Containers: {container_count}")
print(f"  Images: {len(snapshot['images'])}")
print(f"  Systemd units: {len(snapshot['systemd_units'])}")
PYEOF

# Write symlink for easy access
ln -sf "$SNAPSHOT_PATH" "$SNAPSHOT_DIR/latest.json"
echo "  Symlink: $SNAPSHOT_DIR/latest.json"
