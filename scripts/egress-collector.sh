#!/bin/bash
# egress-collector.sh — ADR-030 P7 (Tier 4) egress observatory: the cheap collector.
#
# WHY this exists / what the forensic settled (see docs/97-plans/2026-05-24-tier4-…):
#   The only egress tier is `reverse_proxy` (21 containers). Rootless pasta SNATs all
#   egress to the host, so host conntrack/nftables see NO per-container source; aardvark
#   1.17.1 can't log DNS; Pi-hole is on another host and NATs everything to .70. The one
#   signal that is attributable, rootless-readable, scratch-safe, and catches DoH /
#   hardcoded-IP egress is the container's own socket table read HOST-SIDE via
#   /proc/<pid>/net/{tcp,tcp6} (pid from `podman inspect`). nsenter -n is blocked rootless.
#
# WHY two tiers (collector + detector): point-in-time sampling is DOA — even continuous
#   egress (proton-bridge) is invisible at most instants. So this collector runs OFTEN
#   (~30s) and only ACCUMULATES a raw observation log; the heavy work (PTR/classify) is
#   done less often by detect-egress-anomaly.sh over the accumulated union.
#
# It is OFF the boot-critical path: a timer/daemon-driven observer. If it stops, nothing
# breaks — egress still flows; only detection pauses (and the last_run gauge alerts on that).
#
# Usage: egress-collector.sh [--once]      (default: daemon loop every $EGRESS_COLLECT_INTERVAL s)
# Exit:  0 normal (—once); daemon runs until stopped.
set -uo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/containers}"
QUADLET_DIR="${QUADLET_DIR:-$REPO_ROOT/quadlets}"
EGRESS_DIR="${EGRESS_DIR:-$REPO_ROOT/data/egress}"
ACC_FILE="$EGRESS_DIR/accumulator.tsv"
LOCK_FILE="$EGRESS_DIR/.accumulator.lock"
METRIC_DIR="${METRIC_DIR:-$REPO_ROOT/data/backup-metrics}"
METRIC_FILE="$METRIC_DIR/egress-collector.prom"
INTERVAL="${EGRESS_COLLECT_INTERVAL:-30}"
# TCP states to keep: 01 ESTABLISHED, 02 SYN_SENT, 06 TIME_WAIT, 08 CLOSE_WAIT.
# (ESTAB-only misses short-lived beacons — proton-bridge only ever showed TIME_WAIT.)
STATES="${EGRESS_STATES:-01 02 06 08}"

is_egress() { grep -qE '^Network=systemd-reverse_proxy' "$1"; }

# Emit "<svc>\t<containerName>" for every reverse_proxy-tier quadlet.
list_egress_services() {
    local f name cname
    for f in "$QUADLET_DIR"/*.container; do
        [ -e "$f" ] || continue
        is_egress "$f" || continue
        name="$(basename "$f" .container)"
        cname="$(grep -m1 -E '^ContainerName=' "$f" | sed 's/^ContainerName=//' | tr -d '[:space:]')"
        [ -n "$cname" ] || cname="$name"
        printf '%s\t%s\n' "$name" "$cname"
    done
}

# PID cache across daemon cycles (avoids `podman inspect` every 30s — the architect's
# cost note). A cached pid is trusted only if /proc/<pid>/cgroup still names the same
# container id (guards PID reuse after a restart).
declare -A PID_CACHE CID_CACHE
resolve_pid() {  # $1=svc $2=cname -> echoes pid, or nothing
    local svc="$1" cname="$2" p="${PID_CACHE[$svc]:-}" c="${CID_CACHE[$svc]:-}" info
    if [ -n "$p" ] && [ -n "$c" ] && [ -r "/proc/$p/cgroup" ] && grep -q "$c" "/proc/$p/cgroup" 2>/dev/null; then
        echo "$p"; return 0
    fi
    info="$(podman inspect "$cname" --format '{{.State.Pid}} {{.Id}}' 2>/dev/null)" || return 1
    p="${info%% *}"; c="${info##* }"
    [ -n "$p" ] && [ "$p" != "0" ] && [ -n "$c" ] || return 1
    [ -r "/proc/$p/cgroup" ] && grep -q "$c" "/proc/$p/cgroup" 2>/dev/null || return 1
    PID_CACHE[$svc]="$p"; CID_CACHE[$svc]="$c"
    echo "$p"; return 0
}

# Decode /proc/<pid>/net/{tcp,tcp6} for the given svc→pid map, keep only PUBLIC
# (globally-routable) foreign endpoints in the wanted states. Python's ipaddress
# handles little-endian hex, IPv6 word order, IPv4-mapped unwrap, and is_global —
# far safer than hand-rolled CIDR maths. The svc→pid map is passed as an ARGUMENT,
# not stdin: `python3 -` reads its script from stdin (the heredoc), so stdin is not
# available for data. Emits: "<epoch>\t<svc>\t<ip>\t<port>\t<state>"
decode_proc() {  # $1=epoch  $2=map ("<svc> <pid>" lines)
    python3 - "$1" "$STATES" "$2" 2>/dev/null <<'PY'
import sys, ipaddress
epoch = sys.argv[1]
want = set(sys.argv[2].split())
mapdata = sys.argv[3]

def v4(h):
    return ipaddress.IPv4Address(bytes(reversed(bytes.fromhex(h))))
def v6(h):
    b = bytes.fromhex(h)
    out = b''.join(bytes(reversed(b[i:i+4])) for i in range(0, 16, 4))
    a = ipaddress.IPv6Address(out)
    return a.ipv4_mapped or a

def parse(path, dec):
    try:
        with open(path) as f:
            next(f, None)
            for line in f:
                p = line.split()
                if len(p) < 4 or p[3] not in want:
                    continue
                hexip, hexport = p[2].split(':')
                try:
                    ip = dec(hexip)
                except Exception:
                    continue
                if not ip.is_global:
                    continue
                yield str(ip), int(hexport, 16), p[3]
    except FileNotFoundError:
        return

seen = set()
for raw in mapdata.splitlines():
    raw = raw.strip()
    if not raw:
        continue
    svc, pid = raw.split()
    for path, dec in ((f"/proc/{pid}/net/tcp", v4), (f"/proc/{pid}/net/tcp6", v6)):
        for ip, port, st in parse(path, dec):
            key = (svc, ip, port, st)
            if key in seen:
                continue
            seen.add(key)
            print(f"{epoch}\t{svc}\t{ip}\t{port}\t{st}")
PY
}

write_collector_metric() {  # $1=services_sampled
    mkdir -p "$METRIC_DIR" || return 0
    # Temp MUST be created in-dir: a /tmp temp moved here keeps user_tmp_t and node_exporter
    # (SELinux) then can't read it (node_textfile_scrape_error). In-dir inherits container_file_t.
    local tmp; tmp="$(mktemp -p "$METRIC_DIR")" || return 0
    {
        echo "# HELP egress_collector_last_run_timestamp ADR-030 P7 (Tier 4) egress collector last successful sample (unix seconds)."
        echo "# TYPE egress_collector_last_run_timestamp gauge"
        echo "egress_collector_last_run_timestamp $(date +%s)"
        echo "# HELP egress_collector_services_sampled Number of egress-tier containers sampled in the last collector pass."
        echo "# TYPE egress_collector_services_sampled gauge"
        echo "egress_collector_services_sampled ${1:-0}"
    } > "$tmp"
    chmod 0644 "$tmp" 2>/dev/null   # node_exporter runs as 'nobody' — needs other-read
    mv "$tmp" "$METRIC_FILE" 2>/dev/null || rm -f "$tmp"
}

run_once() {
    mkdir -p "$EGRESS_DIR"
    local map="" svc cname pid sampled=0
    while IFS=$'\t' read -r svc cname; do
        pid="$(resolve_pid "$svc" "$cname")" || continue
        [ -n "$pid" ] || continue
        map+="$svc $pid"$'\n'
        sampled=$((sampled+1))
    done < <(list_egress_services)

    if [ -n "$map" ]; then
        local obs
        obs="$(decode_proc "$(date +%s)" "$map")"
        if [ -n "$obs" ]; then
            (
                flock 9
                printf '%s\n' "$obs" >> "$ACC_FILE"
            ) 9>"$LOCK_FILE"
        fi
    fi
    write_collector_metric "$sampled"
}

main() {
    if [ "${1:-}" = "--once" ]; then run_once; exit 0; fi
    # daemon
    while true; do
        run_once
        sleep "$INTERVAL"
    done
}

main "$@"
