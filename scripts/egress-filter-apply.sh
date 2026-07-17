#!/bin/bash
################################################################################
# egress-filter-apply.sh — enforce + observe the restricted-egress nft filter
#
# Enforcer AND sensor for the restricted-egress tier (ADR-045, GH#334):
#
#   ENFORCE  Apply the ruleset below inside the rootless netns via a single
#            `podman unshare --rootless-netns nft '<commands>'` invocation.
#            argv, NOT stdin and NOT a file path: file paths don't cross the
#            userns mount namespace, and stdin through podman unshare is RACY —
#            deployment testing (2026-07-17) showed `nft -f -` intermittently
#            reading EMPTY stdin and exiting 0 (a successful parse of nothing),
#            i.e. a silent enforcement no-op. argv is deterministic (5/5).
#            The netns and every rule in it die with the last bridge container
#            and on reboot, so a 1-minute timer reapplies; add+flush makes
#            every tick idempotent. Netns absent -> nothing to filter -> exit 0
#            (fail-open by design; members are no worse than the default-allow
#            fleet during a window, and the alert below bounds the window).
#
#   OBSERVE  Emit a node_exporter textfile with: netns/table presence, drop
#            counter, member count, single-homing violations, run timestamp.
#            Alerting (egress-filter-alerts.yml): table absent >5 min while the
#            netns exists; collector stale; any single-homing violation.
#
#   INVARIANT (ADR-045) A restricted-egress member must not join any other
#            non-internal network — internal networks contribute no default
#            route, so a clean member has exactly ONE default route and
#            wrong-network egress is structurally impossible (the 2026-02-02
#            incident lesson encoded as topology). Enumerated live from the
#            network's member list, so even a hand-run `podman network connect`
#            is caught within a minute.
#
# Root-free: nft runs inside the user-owned netns; no host tables are touched.
# NEVER touch `table inet netavark` — see the NFT_CMDS note below.
#
# Schedule: egress-filter.timer @ every 1 min.
################################################################################
set -uo pipefail
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

TEXTFILE_DIR="${HOME}/containers/data/backup-metrics"
OUT="${TEXTFILE_DIR}/egress-filter.prom"
NETNS_REF="${XDG_RUNTIME_DIR}/containers/networks/rootless-netns/rootless-netns"
NETWORK="systemd-restricted-egress"
RUN_TS="$(date +%s)"

# The ruleset (ADR-045). A SEPARATE table — never touch `table inet netavark`
# (netavark rewrites its own table selectively; a custom table survives
# container restarts, network reloads, and network creates — runtime-proven).
# Subnet-keyed: members need no IP pinning for the filter. Accept set:
#   192.168.1.0/24 — patriark-lan (Pi-hole .69, UDM .1, host .70; widen
#                    deliberately if a member ever needs IoT/WG VLANs)
#   10.89.0.0/16   — container bridges (cross-bridge scrapes to pinned IPs)
#   169.254.1.1    — pasta's --dns-forward shim (DNS keeps resolving; DNS
#                    tunneling stays open — egress observatory is the
#                    alerting complement, ADR-030 T4)
# Everything else from the subnet drops (named counter survives reapply).
# No IPv6 egress path exists under pasta today; the inet-family table is
# where a v6 rule lands if one ever appears.
NFT_CMDS='add table inet egress_filter
flush table inet egress_filter
add counter inet egress_filter dropped
add chain inet egress_filter forward { type filter hook forward priority filter ; policy accept ; }
add rule inet egress_filter forward ip saddr 10.89.11.0/24 ip daddr { 192.168.1.0/24, 10.89.0.0/16, 169.254.1.1 } accept
add rule inet egress_filter forward ip saddr 10.89.11.0/24 counter name dropped drop'

netns_present=0
table_present=0
apply_ok=0
members=0
violations=0
drop_pkts=0
drop_bytes=0

if [[ -e "$NETNS_REF" ]]; then
    netns_present=1

    if podman unshare --rootless-netns nft "$NFT_CMDS" 2>/dev/null; then
        apply_ok=1
    fi

    if podman unshare --rootless-netns nft list table inet egress_filter &>/dev/null; then
        table_present=1
        # counter line looks like: counter dropped { packets 12 bytes 720 ... }
        read -r drop_pkts drop_bytes < <(
            podman unshare --rootless-netns nft list counter inet egress_filter dropped 2>/dev/null \
                | awk '/packets/ {print $2, $4; found=1} END {if (!found) print 0, 0}'
        )
    fi

    # Single-homing invariant: every container on the restricted subnet must
    # have restricted-egress as its ONLY non-internal network.
    declare -A NONINTERNAL=()
    while read -r net internal; do
        [[ "$internal" == "false" ]] && NONINTERNAL["$net"]=1
    done < <(podman network ls --format '{{.Name}}' \
             | xargs -r -n1 -I{} sh -c 'printf "%s %s\n" "{}" "$(podman network inspect {} --format "{{.Internal}}")"')

    for c in $(podman network inspect "$NETWORK" --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null); do
        members=$((members + 1))
        for net in $(podman inspect "$c" --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null); do
            if [[ "$net" != "$NETWORK" && -n "${NONINTERNAL[$net]:-}" ]]; then
                violations=$((violations + 1))
                echo "VIOLATION: ${c} is on non-internal network ${net} besides ${NETWORK}" >&2
            fi
        done
    done
fi

emit() {
    cat <<EOF
# HELP egress_filter_netns_present Rootless netns exists (1) — the filter has somewhere to live.
# TYPE egress_filter_netns_present gauge
egress_filter_netns_present ${netns_present}
# HELP egress_filter_table_present table inet egress_filter exists in the rootless netns.
# TYPE egress_filter_table_present gauge
egress_filter_table_present ${table_present}
# HELP egress_filter_apply_ok Last nft ruleset application succeeded (1).
# TYPE egress_filter_apply_ok gauge
egress_filter_apply_ok ${apply_ok}
# HELP egress_filter_members Containers currently on the restricted-egress network.
# TYPE egress_filter_members gauge
egress_filter_members ${members}
# HELP egress_filter_singlehome_violations Members joined to another non-internal network (must be 0 — ADR-045 invariant).
# TYPE egress_filter_singlehome_violations gauge
egress_filter_singlehome_violations ${violations}
# HELP egress_filter_dropped_packets_total Packets from 10.89.11.0/24 denied internet egress (netns-lifetime counter).
# TYPE egress_filter_dropped_packets_total counter
egress_filter_dropped_packets_total ${drop_pkts}
# HELP egress_filter_dropped_bytes_total Bytes from 10.89.11.0/24 denied internet egress (netns-lifetime counter).
# TYPE egress_filter_dropped_bytes_total counter
egress_filter_dropped_bytes_total ${drop_bytes}
# HELP egress_filter_last_run_timestamp Unix time of the last enforcement run.
# TYPE egress_filter_last_run_timestamp gauge
egress_filter_last_run_timestamp ${RUN_TS}
EOF
}

mkdir -p "$TEXTFILE_DIR"
tmp="$(mktemp "${TEXTFILE_DIR}/.egress-filter.XXXXXX")" || exit 1
trap 'rm -f "$tmp"' EXIT
emit > "$tmp"
chmod 644 "$tmp"
mv -f "$tmp" "$OUT"
trap - EXIT

# Fail the unit (visible in journal) only on a real enforcement failure:
# netns present but the ruleset would not apply.
if [[ "$netns_present" -eq 1 && "$apply_ok" -ne 1 ]]; then
    echo "ERROR: rootless netns present but nft ruleset failed to apply" >&2
    exit 1
fi
exit 0
