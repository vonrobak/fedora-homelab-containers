#!/bin/bash
################################################################################
# btrfs-dev-stats-collector.sh — per-device BTRFS error counters → node_exporter
#
# Part of the storage-health monitoring for the Single-data-profile pool (ADR-029):
# with no live data redundancy, the earliest, most actionable signal that a disk is
# going bad is BTRFS's own persistent per-device error counters. They accumulate
# CONTINUOUSLY during normal operation — the instant the kernel hits an I/O or
# checksum error on a real read/write — so they catch a failing/rotting device
# *between* the monthly scrubs, which a scrub-only design cannot.
#
#   write/read/flush_io_errs -> the drive is failing I/O (classic pre-death signal)
#   corruption_errs          -> bit-rot / CSUM failures hit during production reads
#   generation_errs          -> stale metadata (transid mismatch)
#
# Counters are PERSISTENT (only `btrfs dev stats -z` resets them), so we alert on the
# value, not a rate. After replacing/clearing a disk, zero them.
#
# Root-free by design: `btrfs device stats` needs no privileges (verified). Runs as a
# USER systemd oneshot and writes its .prom as user 1000, so the file lands with the
# correct container_file_t SELinux context for the rootless node_exporter (same
# contract as db-dump.sh).
#
# Schedule: btrfs-dev-stats.timer @ every 15 min.
################################################################################
set -uo pipefail
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

TEXTFILE_DIR="${HOME}/containers/data/backup-metrics"
OUT="${TEXTFILE_DIR}/btrfs-dev-stats.prom"
RUN_TS="$(date +%s)"

# mountpoint -> friendly filesystem label. Pool is canonically mounted at /mnt
# (subvolid=5); /mnt/btrfs-pool is a subvolume path, not the mountpoint. Backups are
# removable LUKS2 drives — present only when connected; absent = skip, never fail.
declare -A FS=(
    ["/mnt"]="pool"
    ["/run/media/patriark/WD-18TB"]="WD-18TB"
    ["/run/media/patriark/2TB-backup"]="2TB-backup"
)

emit() {
    local mnt label key val dev typ present
    echo "# HELP btrfs_device_errors BTRFS persistent per-device error counter (btrfs device stats)."
    echo "# TYPE btrfs_device_errors gauge"
    for mnt in "${!FS[@]}"; do
        mountpoint -q "$mnt" 2>/dev/null || continue
        label="${FS[$mnt]}"
        # lines look like: [/dev/sdc].write_io_errs    0
        btrfs device stats "$mnt" 2>/dev/null | while read -r key val; do
            dev="${key%%]*}"; dev="${dev#[}"                 # /dev/sdc | /dev/mapper/luks-...
            typ="${key##*.}"; typ="${typ%_errs}"; typ="${typ%_io}"  # write|read|flush|corruption|generation
            [[ -n "$dev" && -n "$typ" && -n "$val" ]] || continue
            echo "btrfs_device_errors{filesystem=\"${label}\",device=\"${dev}\",type=\"${typ}\"} ${val}"
        done
    done

    echo "# HELP btrfs_device_stats_present BTRFS filesystem mounted (1) and collected this run."
    echo "# TYPE btrfs_device_stats_present gauge"
    for mnt in "${!FS[@]}"; do
        label="${FS[$mnt]}"
        if mountpoint -q "$mnt" 2>/dev/null; then present=1; else present=0; fi
        echo "btrfs_device_stats_present{filesystem=\"${label}\"} ${present}"
    done

    echo "# HELP btrfs_device_stats_last_run_timestamp Unix time of the last dev-stats collection."
    echo "# TYPE btrfs_device_stats_last_run_timestamp gauge"
    echo "btrfs_device_stats_last_run_timestamp ${RUN_TS}"
}

mkdir -p "$TEXTFILE_DIR"
tmp="$(mktemp "${TEXTFILE_DIR}/.devstats.XXXXXX")" || exit 1
trap 'rm -f "$tmp"' EXIT
emit > "$tmp"
chmod 644 "$tmp"
mv -f "$tmp" "$OUT"
trap - EXIT
