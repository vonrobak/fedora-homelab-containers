#!/bin/bash
################################################################################
# btrfs-scrub.sh — scheduled BTRFS scrub with metrics (storage-health, ADR-029, part 2)
#
# Scrub reads every block and verifies checksums. On the Single-data / RAID1-metadata
# pool it can self-heal METADATA (from the mirror) but NOT data (no data mirror) — so a
# `uncorrectable` error is data to restore from backup, while a `corrected` error is the
# metadata mirror doing its job (a disk whispering). The point on Single data is
# DETECTION: learn a file rotted while a good copy still exists in Urd.
#
# Throttling (the pool serves all services — see the 2026-06 boot I/O storm). The POOL is
# capped via `btrfs scrub limit --all` BEFORE start, NOT `scrub start --limit`: the latter
# silently skips some devids on a multi-device fs (verified 2026-06-09 — it left devid 1
# unlimited, blowing the cap to ~407 MiB/s). /home (SSD) and the idle, separate-spindle
# backup drives scrub unlimited (no service impact; per-device caps would also make the
# single-device backups absurdly slow).
#   btrfs scrub limit --all --limit 30m /mnt   # cap EVERY pool device (reliable)
#   btrfs scrub start  -B -d -c 3 /mnt          # -B foreground, -d per-device, -c 3 idle ioprio
#   btrfs scrub limit --all --limit 0  /mnt     # reset to unlimited afterwards (hygiene)
#   + unit-level Nice=19 / IOSchedulingClass=idle.
# 30 MiB/s/device held `io full` PSI ~6% on the live pool (supervised run 2026-06-09);
# ~24h for a full ~11 TiB pass. These exact commands/values MUST match the sudoers grant.
#
# Usage:  btrfs-scrub.sh <mountpoint> [<mountpoint> ...]
#   Each arg is scrubbed if it is a mounted btrfs (removable backups are skipped cleanly
#   when absent). Per-fs results are kept as state files and rendered into a single
#   btrfs-scrub.prom (one HELP/TYPE per metric; all filesystems in one file).
################################################################################
set -uo pipefail
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

BTRFS="/usr/sbin/btrfs"
POOL_LIMIT="30m"                         # MiB/s per pool device; keep in sync with sudoers
TEXTFILE_DIR="${HOME}/containers/data/backup-metrics"
STATE_DIR="${TEXTFILE_DIR}/.scrub-state"
OUT="${TEXTFILE_DIR}/btrfs-scrub.prom"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2; }

label_for() {  # mountpoint -> friendly filesystem label
    case "$1" in
        /mnt)                              echo "pool" ;;
        /home)                             echo "home" ;;
        /run/media/patriark/WD-18TB)       echo "WD-18TB" ;;
        /run/media/patriark/2TB-backup)    echo "2TB-backup" ;;
        *)                                 echo "$(basename "$1")" ;;
    esac
}

limit_for() {  # MiB/s per device, or "" for unlimited. Only the pool is throttled.
    case "$1" in
        /mnt) echo "$POOL_LIMIT" ;;
        *)    echo "" ;;
    esac
}

scrub_one() {
    local mnt="$1" label start end dur status corrected uncorrectable rc limit
    label="$(label_for "$mnt")"
    if ! mountpoint -q "$mnt" 2>/dev/null; then
        log "[$label] $mnt not mounted — skipping (removable/absent)"
        return 0
    fi
    limit="$(limit_for "$mnt")"
    if [[ -n "$limit" ]]; then
        log "[$label] capping every device at ${limit} via 'scrub limit --all' (pool serves services)"
        sudo -n "$BTRFS" scrub limit --all --limit "$limit" "$mnt" >/dev/null 2>&1 \
            || log "[$label] WARN: could not set scrub limit — scrub may run unthrottled"
    fi
    log "[$label] scrub starting on $mnt (idle ioprio${limit:+, ${limit}/device})"
    start="$(date +%s)"
    sudo -n "$BTRFS" scrub start -B -d -c 3 "$mnt" >/dev/null 2>&1
    rc=$?
    end="$(date +%s)"; dur=$((end - start))
    # Reset the device cap so a future MANUAL full-speed scrub isn't silently throttled.
    [[ -n "$limit" ]] && sudo -n "$BTRFS" scrub limit --all --limit 0 "$mnt" >/dev/null 2>&1 || true
    # btrfs scrub -B returns 0 (clean) or 3 (completed, found uncorrectable errors) when it
    # actually RAN; anything else means it failed to start/complete (sudo denied, drive gone,
    # already running). Do NOT record a completion in that case, or last_completion_timestamp
    # would advance and mask BtrfsScrubOverdue — the prior real scrub's state is kept instead.
    if [[ $rc -ne 0 && $rc -ne 3 ]]; then
        log "[$label] scrub did NOT run (rc=${rc}) — keeping previous state, not recording completion"
        return 0
    fi
    # Parse the RAW status counters — NEVER the exit code as the source of truth.
    # corrected/uncorrectable are the decision buckets.
    status="$(sudo -n "$BTRFS" scrub status -R "$mnt" 2>/dev/null)"
    corrected="$(grep -oiP 'corrected_errors:\s*\K[0-9]+' <<<"$status" | head -1)"
    uncorrectable="$(grep -oiP 'uncorrectable_errors:\s*\K[0-9]+' <<<"$status" | head -1)"
    corrected="${corrected:-0}"; uncorrectable="${uncorrectable:-0}"
    log "[$label] scrub done in ${dur}s rc=${rc} corrected=${corrected} uncorrectable=${uncorrectable}"
    mkdir -p "$STATE_DIR"
    cat > "${STATE_DIR}/${label}" <<EOF
filesystem=${label}
completion_ts=${end}
duration=${dur}
corrected=${corrected}
uncorrectable=${uncorrectable}
exit_code=${rc}
run_ts=${end}
EOF
}

getf() { grep -oP "(?<=^${2}=).*" "$1" 2>/dev/null; }

render() {  # render all per-fs state files into one valid .prom (HELP/TYPE once per metric)
    local s
    echo "# HELP btrfs_scrub_uncorrectable_errors BTRFS scrub uncorrectable errors (data loss on Single profile — restore from backup)."
    echo "# TYPE btrfs_scrub_uncorrectable_errors gauge"
    for s in "$STATE_DIR"/*; do [ -e "$s" ] || continue; echo "btrfs_scrub_uncorrectable_errors{filesystem=\"$(getf "$s" filesystem)\"} $(getf "$s" uncorrectable)"; done
    echo "# HELP btrfs_scrub_corrected_errors BTRFS scrub corrected errors (self-healed from a good copy, e.g. RAID1 metadata mirror — a disk whispering)."
    echo "# TYPE btrfs_scrub_corrected_errors gauge"
    for s in "$STATE_DIR"/*; do [ -e "$s" ] || continue; echo "btrfs_scrub_corrected_errors{filesystem=\"$(getf "$s" filesystem)\"} $(getf "$s" corrected)"; done
    echo "# HELP btrfs_scrub_last_completion_timestamp Unix time the last scrub of this filesystem finished."
    echo "# TYPE btrfs_scrub_last_completion_timestamp gauge"
    for s in "$STATE_DIR"/*; do [ -e "$s" ] || continue; echo "btrfs_scrub_last_completion_timestamp{filesystem=\"$(getf "$s" filesystem)\"} $(getf "$s" completion_ts)"; done
    echo "# HELP btrfs_scrub_duration_seconds Duration of the last scrub of this filesystem."
    echo "# TYPE btrfs_scrub_duration_seconds gauge"
    for s in "$STATE_DIR"/*; do [ -e "$s" ] || continue; echo "btrfs_scrub_duration_seconds{filesystem=\"$(getf "$s" filesystem)\"} $(getf "$s" duration)"; done
    echo "# HELP btrfs_scrub_exit_code Exit code of the last scrub (0=clean, 3=errors found, other=run failure)."
    echo "# TYPE btrfs_scrub_exit_code gauge"
    for s in "$STATE_DIR"/*; do [ -e "$s" ] || continue; echo "btrfs_scrub_exit_code{filesystem=\"$(getf "$s" filesystem)\"} $(getf "$s" exit_code)"; done
}

[[ $# -ge 1 ]] || { log "usage: $(basename "$0") <mountpoint> [<mountpoint> ...]"; exit 2; }
for mnt in "$@"; do scrub_one "$mnt"; done

mkdir -p "$TEXTFILE_DIR"
tmp="$(mktemp "${TEXTFILE_DIR}/.scrub.XXXXXX")" || exit 1
trap 'rm -f "$tmp"' EXIT
render > "$tmp"
chmod 644 "$tmp"
mv -f "$tmp" "$OUT"
trap - EXIT
log "rendered $OUT"
