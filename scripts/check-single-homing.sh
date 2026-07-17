#!/bin/bash
################################################################################
# check-single-homing.sh — declare-time ADR-045 single-homing lint
#
# Invariant: a container on the restricted-egress network must not join any
# other NON-internal network. Internal networks contribute no default route,
# so a compliant member has exactly one default route — wrong-network egress
# is structurally impossible (the 2026-02-02 incident lesson as topology).
#
# This is the commit-time complement to the RUNTIME check in
# egress-filter-apply.sh (which catches even a hand-run `podman network
# connect` within a minute). Runs as pre-commit check 6 over every quadlet in
# the committing tree — cheap enough to skip staged-file filtering.
#
# A network is non-internal iff its quadlet lacks Internal=true. A Network=
# value with no matching .network quadlet (e.g. host) counts as non-internal:
# fail safe, since it may carry a default route.
################################################################################
set -uo pipefail

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel)}"
QUADLET_DIR="${REPO_ROOT}/quadlets"
RESTRICTED="systemd-restricted-egress"
fail=0

# network name (systemd-<basename>) -> internal? (default no)
is_internal() {
    local name="$1" file
    file="${QUADLET_DIR}/${name#systemd-}.network"
    [[ -f "$file" ]] && grep -q '^Internal=true' "$file"
}

for c in "${QUADLET_DIR}"/*.container; do
    nets=$(grep -oP '^Network=\K[^:]+' "$c")
    grep -qx "$RESTRICTED" <<< "$nets" || continue
    while IFS= read -r net; do
        [[ "$net" == "$RESTRICTED" ]] && continue
        if ! is_internal "$net"; then
            echo "  ✗ $(basename "$c"): restricted-egress member also joins non-internal network '${net}'" >&2
            echo "    (ADR-045 single-homing invariant — a second default route bypasses the egress filter)" >&2
            fail=1
        fi
    done <<< "$nets"
done

if [[ $fail -eq 0 ]]; then
    echo "  ✓ All restricted-egress members are single-homed (ADR-045)"
fi
exit $fail
