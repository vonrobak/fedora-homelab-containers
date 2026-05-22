#!/bin/bash
################################################################################
# db-dump.sh — Application-consistent database dumps (Tier 2 backup)
#
# Part of the three-tier BTRFS storage architecture (ADR-029). Server database
# engines live NOCOW on subvol8-db (excluded from snapshots); their backup is
# an application-consistent logical dump written here, into subvol7-containers/
# db-dumps/, which Urd snapshots nightly and sends offsite.
#
#   Snapshot tier  -> btrfs snapshot + send (configs, SQLite, Redis, user data)
#   Dump tier      -> THIS SCRIPT (PostgreSQL, MariaDB, MongoDB, Prometheus, Loki)
#
# Design:
#   - Per-engine isolation: one engine's failure never aborts the others
#     (no `set -e`; each engine's result is captured independently).
#   - Idempotent per day: output named YYYY-MM-DD, re-runs overwrite.
#   - Secrets never touch host process args: the dump command runs INSIDE the
#     running container, where the engine password already lives as env. Robust
#     to the ADR-028 secret-store path split.
#   - Observability mirrors Urd's backup_* series (db_dump_* in db-dumps.prom).
#
# Schedule: db-dump.timer @ 01:30 (before Urd's 04:00 send).
# Usage:    db-dump.sh [--service <name>] [--help]
################################################################################

set -uo pipefail   # deliberately NOT -e: per-engine isolation

# --- systemd/cron environment -------------------------------------------------
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

# --- configuration ------------------------------------------------------------
DUMP_ROOT="/mnt/btrfs-pool/subvol7-containers/db-dumps"
METRICS_DIR="${HOME}/containers/data/backup-metrics"
METRICS_FILE="${METRICS_DIR}/db-dumps.prom"
LOG_DIR="${HOME}/containers/data/backup-logs"
RETENTION="${DB_DUMP_RETENTION:-14}"        # daily dumps kept per service
ZSTD_LEVEL="${DB_DUMP_ZSTD_LEVEL:-10}"
DATE="$(date +%Y-%m-%d)"
RUN_TS="$(date +%s)"

# Engines handled by this job (service = container name = output subdir)
ENGINES=(postgresql-immich forgejo-db nextcloud-db gathio-db prometheus loki)

# --- argument parsing ---------------------------------------------------------
ONLY_SERVICE=""
SKIP_FLUSH=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --service) ONLY_SERVICE="${2:-}"; SKIP_FLUSH=1; shift 2 ;;   # test mode: don't clobber live metrics
        --help)
            echo "Usage: $(basename "$0") [--service <name>]"
            echo "  --service <name>   dump only one engine, print metrics to stdout"
            echo "  engines: ${ENGINES[*]}"
            exit 0 ;;
        *) echo "[ERROR] unknown argument: $1" >&2; exit 2 ;;
    esac
done

# --- logging ------------------------------------------------------------------
log() {
    local level="$1"; shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $*" >&2
}

# --- result tracking ----------------------------------------------------------
declare -A R_SUCCESS R_DURATION R_SIZE R_TS

record() {  # record <service> <success 0|1> <duration_s> <size_bytes>
    R_SUCCESS["$1"]="$2"; R_DURATION["$1"]="$3"; R_SIZE["$1"]="$4"
    [[ "$2" == "1" ]] && R_TS["$1"]="$(date +%s)"
}

# Carry forward the previous last-success timestamp for engines that failed this
# run, so DbDumpStale ages correctly instead of the series vanishing.
# NOTE: label is `database`, not `service` — the node_exporter scrape job sets a
# static service="node_exporter" target label that would clobber a `service`
# label here (honor_labels=false). See ADR-029.
prev_ts() {
    [[ -f "$METRICS_FILE" ]] || return 0
    grep -oP "db_dump_last_success_timestamp\{database=\"$1\"\} \K[0-9]+" "$METRICS_FILE" 2>/dev/null | tail -1
}

# --- engine dump functions ----------------------------------------------------
# Each writes "$out_dir/$DATE.<ext>.zst" atomically (.tmp then mv) and returns
# non-zero on any failure (pipefail propagates the in-container command's status).

dump_pg() {  # args: svc out_dir container
    local out="${2}/${DATE}.dump.zst" container="$3"
    podman exec "$container" sh -c \
        'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump --format=custom --compress=0 --no-owner --no-acl -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
        | zstd -q -f -T0 "-${ZSTD_LEVEL}" -o "${out}.tmp" \
        && mv "${out}.tmp" "$out"
}

dump_mariadb() {  # args: svc out_dir
    # root@localhost is locked down on this hardened Nextcloud MariaDB (no
    # password and no socket auth). The app user has ALL on its own database,
    # which is exactly what we dump.
    local out="${2}/${DATE}.sql.zst"
    podman exec nextcloud-db sh -c \
        'mariadb-dump --single-transaction --routines --events -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"' \
        | zstd -q -f -T0 "-${ZSTD_LEVEL}" -o "${out}.tmp" \
        && mv "${out}.tmp" "$out"
}

dump_mongo() {  # args: svc out_dir
    local out="${2}/${DATE}.archive.zst"
    podman exec gathio-db sh -c \
        'mongodump --quiet --username "$MONGO_INITDB_ROOT_USERNAME" --password "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin --archive' \
        | zstd -q -f -T0 "-${ZSTD_LEVEL}" -o "${out}.tmp" \
        && mv "${out}.tmp" "$out"
}

dump_prometheus() {  # args: svc out_dir   (requires --web.enable-admin-api)
    local out="${2}/${DATE}.tar.zst" snap rc
    # Pre-clean orphaned snapshots >60min so a crashed run can't pin TSDB blocks.
    podman exec prometheus sh -c \
        'find /prometheus/snapshots -mindepth 1 -maxdepth 1 -type d -mmin +60 -exec rm -rf {} + 2>/dev/null' || true
    snap="$(podman exec prometheus sh -c \
        'wget -qO- --post-data="" "http://localhost:9090/api/v1/admin/tsdb/snapshot?skip_head=false"' \
        | jq -r '.data.name // empty')"
    if [[ -z "$snap" ]]; then
        log ERROR "[prometheus] snapshot API returned no name — is --web.enable-admin-api set on the quadlet?"
        return 1
    fi
    podman exec prometheus tar -C /prometheus/snapshots -cf - "$snap" \
        | zstd -q -f -T0 "-${ZSTD_LEVEL}" -o "${out}.tmp" \
        && mv "${out}.tmp" "$out"
    rc=$?
    podman exec prometheus rm -rf "/prometheus/snapshots/${snap}" 2>/dev/null || true
    return "$rc"
}

dump_loki() {  # args: svc out_dir
    # Loki is distroless (no shell/tar to exec) with 70k+ constantly-rotating
    # files. Three approaches were measured and rejected: host-side tar/rsync
    # hits permission-denied on mode-600 WAL checkpoint files and is slow (~140s);
    # stop-and-copy fails because the quadlet removes the container on stop;
    # a live `podman cp` races on file rotation under I/O load (rc=125).
    # `podman pause` (SIGSTOP via the freezer cgroup) makes the filesystem static
    # without removing the container, so `podman cp` reads a complete, consistent
    # tree via the namespace in ~40s. Promtail buffers/retries during the freeze;
    # Loki is regenerable, not a source of truth (ADR-027/029).
    local out="${2}/${DATE}.tar.zst" rc
    podman pause loki >/dev/null 2>&1 || { log ERROR "[loki] pause failed"; return 1; }
    trap 'podman unpause loki >/dev/null 2>&1 || true; trap - RETURN' RETURN
    podman cp loki:/loki - | zstd -q -f -T0 "-${ZSTD_LEVEL}" -o "${out}.tmp"
    rc=$?
    podman unpause loki >/dev/null 2>&1 || log WARNING "[loki] unpause returned non-zero"
    trap - RETURN
    [[ $rc -eq 0 ]] || { log ERROR "[loki] podman cp|zstd failed (rc=$rc)"; return 1; }
    mv "${out}.tmp" "$out"
}

# --- engine runner ------------------------------------------------------------
run_engine() {  # run_engine <service> <fn> [extra args...]
    local svc="$1" fn="$2"; shift 2
    local out_dir="${DUMP_ROOT}/${svc}" start now dur rc size
    mkdir -p "$out_dir"
    start="$(date +%s)"
    log INFO "[$svc] dump starting"
    if "$fn" "$svc" "$out_dir" "$@"; then rc=0; else rc=$?; fi
    now="$(date +%s)"; dur=$((now - start))
    if [[ $rc -eq 0 ]]; then
        size="$(stat -c%s "${out_dir}/${DATE}".*.zst 2>/dev/null | head -1)"; size="${size:-0}"
        log INFO "[$svc] OK in ${dur}s (${size} bytes)"
        record "$svc" 1 "$dur" "$size"
    else
        log ERROR "[$svc] FAILED (rc=$rc) after ${dur}s"
        record "$svc" 0 "$dur" 0
    fi
}

prune() {  # keep newest $RETENTION dumps per service
    local dir="${DUMP_ROOT}/$1" f
    [[ -d "$dir" ]] || return 0
    ls -1t "$dir"/*.zst 2>/dev/null | tail -n +"$((RETENTION + 1))" | while read -r f; do
        rm -f "$f" && log INFO "[$1] pruned $(basename "$f")"
    done
}

# --- metrics flush (atomic) ---------------------------------------------------
flush_metrics() {
    local out ts s
    out="$( {
        echo "# HELP db_dump_success Database dump result: 1=success, 0=failure"
        echo "# TYPE db_dump_success gauge"
        for s in "${!R_SUCCESS[@]}"; do echo "db_dump_success{database=\"$s\"} ${R_SUCCESS[$s]}"; done
        echo "# HELP db_dump_last_success_timestamp Unix timestamp of last successful dump"
        echo "# TYPE db_dump_last_success_timestamp gauge"
        for s in "${!R_SUCCESS[@]}"; do
            ts="${R_TS[$s]:-$(prev_ts "$s")}"
            [[ -n "$ts" ]] && echo "db_dump_last_success_timestamp{database=\"$s\"} ${ts}"
        done
        echo "# HELP db_dump_duration_seconds Duration of the dump in seconds"
        echo "# TYPE db_dump_duration_seconds gauge"
        for s in "${!R_DURATION[@]}"; do echo "db_dump_duration_seconds{database=\"$s\"} ${R_DURATION[$s]}"; done
        echo "# HELP db_dump_size_bytes Size of the produced dump in bytes"
        echo "# TYPE db_dump_size_bytes gauge"
        for s in "${!R_SIZE[@]}"; do echo "db_dump_size_bytes{database=\"$s\"} ${R_SIZE[$s]}"; done
        echo "# HELP db_dump_last_run_timestamp Unix timestamp of last db-dump.sh run"
        echo "# TYPE db_dump_last_run_timestamp gauge"
        echo "db_dump_last_run_timestamp ${RUN_TS}"
    } )"
    if [[ $SKIP_FLUSH -eq 1 ]]; then
        echo "--- metrics (test mode, not written) ---" >&2
        echo "$out"
        return 0
    fi
    mkdir -p "$METRICS_DIR"
    printf '%s\n' "$out" > "${METRICS_FILE}.tmp"
    mv "${METRICS_FILE}.tmp" "$METRICS_FILE"
}

# --- main ---------------------------------------------------------------------
main() {
    mkdir -p "$DUMP_ROOT" "$LOG_DIR"
    log INFO "db-dump starting (date=${DATE}, retention=${RETENTION}${ONLY_SERVICE:+, only=${ONLY_SERVICE}})"

    for svc in "${ENGINES[@]}"; do
        [[ -n "$ONLY_SERVICE" && "$ONLY_SERVICE" != "$svc" ]] && continue
        case "$svc" in
            postgresql-immich) run_engine "$svc" dump_pg "$svc" ;;
            forgejo-db)        run_engine "$svc" dump_pg "$svc" ;;
            nextcloud-db)      run_engine "$svc" dump_mariadb ;;
            gathio-db)         run_engine "$svc" dump_mongo ;;
            prometheus)        run_engine "$svc" dump_prometheus ;;
            loki)              run_engine "$svc" dump_loki ;;
        esac
        prune "$svc"
    done

    flush_metrics

    local fails=0 total="${#R_SUCCESS[@]}"
    for s in "${!R_SUCCESS[@]}"; do [[ "${R_SUCCESS[$s]}" == "1" ]] || fails=$((fails + 1)); done
    log INFO "db-dump finished: $((total - fails))/${total} engines OK"
    return 0   # never fail the unit; per-engine status is in metrics + alerts
}

main "$@"
