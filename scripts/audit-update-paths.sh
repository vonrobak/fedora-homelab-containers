#!/bin/bash
# audit-update-paths.sh
# Regression guard for the 2026-04-06 Nextcloud SLO collapse.
#
# Ensures no stateful-schema container carries `AutoUpdate=registry` in its quadlet.
# Stateful services must be updated only via `podman-auto-update-weekly.service`,
# which wraps `pre-update-health-check.sh` and `post-update-health-check.sh`.
# An `AutoUpdate=registry` line on a stateful service triggers pulls outside that
# wrapped path, bypassing the remediation logic at
# `scripts/post-update-health-check.sh:76-116`.
#
# Exit codes:
#   0 = clean (no stateful service has AutoUpdate=registry)
#   1 = violation (at least one stateful service has AutoUpdate=registry)
#   2 = usage / missing input

set -euo pipefail

QUADLET_DIR="${QUADLET_DIR:-$HOME/containers/quadlets}"

if [ ! -d "$QUADLET_DIR" ]; then
    echo "ERROR: quadlet directory not found: $QUADLET_DIR" >&2
    exit 2
fi

# Services whose container owns, embeds, or caches a schema/session that requires
# `occ upgrade`, WAL replay, or similar remediation on restart with a new image.
# Additions to this list are cheap; removals need justification.
STATEFUL_SERVICES=(
    nextcloud
    nextcloud-db
    nextcloud-redis
    immich-server
    immich-ml
    postgresql-immich
    redis-immich
    gathio
    gathio-db
    home-assistant
    authelia
    redis-authelia
    loki
    prometheus
)

violations=()

for service in "${STATEFUL_SERVICES[@]}"; do
    file="$QUADLET_DIR/${service}.container"
    if [ ! -f "$file" ]; then
        continue
    fi
    if grep -qE '^\s*AutoUpdate\s*=\s*registry\s*$' "$file"; then
        violations+=("$service ($file)")
    fi
done

if [ ${#violations[@]} -eq 0 ]; then
    echo "audit-update-paths: OK — no stateful service has AutoUpdate=registry"
    exit 0
fi

echo "audit-update-paths: VIOLATION — ${#violations[@]} stateful service(s) have AutoUpdate=registry:" >&2
for v in "${violations[@]}"; do
    echo "  - $v" >&2
done
echo "" >&2
echo "Stateful services must be updated only via podman-auto-update-weekly.service" >&2
echo "(which wraps pre/post health checks). Remove 'AutoUpdate=registry' from each" >&2
echo "quadlet listed above and run: systemctl --user daemon-reload" >&2
echo "" >&2
echo "Rationale: docs/98-journals/2026-04-21-nextcloud-slo-collapse-postmortem.md" >&2
exit 1
