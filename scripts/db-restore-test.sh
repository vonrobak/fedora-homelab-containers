#!/bin/bash
################################################################################
# db-restore-test.sh — Weekly per-engine restore validation (ADR-029)
#
# "A dump nobody has restored is a dump you don't have." For each engine, this
# restores the LATEST dump from db-dump.sh into a throwaway, matching-version
# container, validates that real objects came back, and tears the container
# down. Result is exported as db_restore_test_* metrics (DbRestoreTest* alerts).
#
#   PG / MariaDB / Mongo : full ephemeral restore + object-count validation
#   Prometheus / Loki    : archive integrity + structure check (full TSDB
#                          restore is heavy; integrity is the weekly gate)
#
# Schedule: db-restore-test.timer @ Sun 05:00 (after Urd's 04:00 send).
# Usage:    db-restore-test.sh [--service <name>] [--keep]
################################################################################

set -uo pipefail

export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

DUMP_ROOT="/mnt/btrfs-pool/subvol7-containers/db-dumps"
METRICS_DIR="${HOME}/containers/data/backup-metrics"
METRICS_FILE="${METRICS_DIR}/db-restore-test.prom"
LOG_DIR="${HOME}/containers/data/backup-logs"
TEST_PW="restoretest"               # ephemeral throwaway container password
RUN_TS="$(date +%s)"

# Matching images per engine (must match the source so extensions/format load)
IMG_IMMICH="ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0"
IMG_PG16="docker.io/library/postgres:16-alpine"
IMG_MARIADB="docker.io/library/mariadb:11"
IMG_MONGO="docker.io/library/mongo:7"

ONLY_SERVICE=""
KEEP=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --service) ONLY_SERVICE="${2:-}"; shift 2 ;;
        --keep)    KEEP=1; shift ;;       # leave the live metrics file alone (test mode)
        --help)    echo "Usage: $(basename "$0") [--service <name>] [--keep]"; exit 0 ;;
        *) echo "[ERROR] unknown argument: $1" >&2; exit 2 ;;
    esac
done

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$1] ${*:2}" >&2; }

declare -A R_OK R_TS
record() { R_OK["$1"]="$2"; [[ "$2" == "1" ]] && R_TS["$1"]="$(date +%s)"; }

latest_dump() {  # echo newest dump path for a service, empty if none
    ls -1t "${DUMP_ROOT}/$1/"*.zst 2>/dev/null | head -1
}

# Wait for a predicate (podman exec health probe) up to ~90s.
wait_ready() {  # wait_ready <container> <probe-shell-cmd>
    local c="$1" probe="$2" i
    for i in $(seq 1 45); do
        podman exec "$c" sh -c "$probe" >/dev/null 2>&1 && return 0
        sleep 2
    done
    return 1
}

# --- engine restore tests -----------------------------------------------------
test_pg() {  # args: svc image user db
    local svc="$1" img="$2" user="$3" db="$4" c="dbrestoretest-${1}" dump n
    dump="$(latest_dump "$svc")"; [[ -n "$dump" ]] || { log ERROR "[$svc] no dump found"; return 1; }
    podman rm -f "$c" >/dev/null 2>&1 || true
    trap 'podman rm -f "'"$c"'" >/dev/null 2>&1 || true; trap - RETURN' RETURN
    podman run -d --rm --name "$c" --network none \
        -e POSTGRES_PASSWORD="$TEST_PW" -e POSTGRES_USER="$user" -e POSTGRES_DB="$db" \
        "$img" >/dev/null || { log ERROR "[$svc] could not start $img"; return 1; }
    # Probe the DATABASE, not just the server: pg_isready passes as soon as the
    # server accepts connections, but slow images (immich/vectorchord, ~40s)
    # create POSTGRES_DB well after that — restoring too early gives 0 tables.
    wait_ready "$c" "psql -U $user -d $db -tAc 'SELECT 1'" || { log ERROR "[$svc] ephemeral PG/db never ready"; return 1; }
    zstd -dc "$dump" | podman exec -i "$c" pg_restore --no-owner --no-acl -U "$user" -d "$db" >/dev/null 2>&1 || true
    n="$(podman exec "$c" psql -U "$user" -d "$db" -tAc \
        "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'" 2>/dev/null | tr -d '[:space:]')"
    [[ "${n:-0}" -gt 0 ]] && { log SUCCESS "[$svc] restored, ${n} public tables"; return 0; }
    log ERROR "[$svc] restore produced 0 tables"; return 1
}

test_mariadb() {  # args: svc db
    local svc="$1" db="$2" c="dbrestoretest-${1}" dump n
    dump="$(latest_dump "$svc")"; [[ -n "$dump" ]] || { log ERROR "[$svc] no dump found"; return 1; }
    podman rm -f "$c" >/dev/null 2>&1 || true
    trap 'podman rm -f "'"$c"'" >/dev/null 2>&1 || true; trap - RETURN' RETURN
    podman run -d --rm --name "$c" --network none \
        -e MARIADB_ROOT_PASSWORD="$TEST_PW" -e MARIADB_DATABASE="$db" \
        "$IMG_MARIADB" >/dev/null || { log ERROR "[$svc] could not start mariadb"; return 1; }
    wait_ready "$c" "mariadb -uroot -p${TEST_PW} ${db} -e 'SELECT 1'" || { log ERROR "[$svc] ephemeral MariaDB/db never ready"; return 1; }
    zstd -dc "$dump" | podman exec -i "$c" mariadb -uroot -p"$TEST_PW" "$db" >/dev/null 2>&1 || { log ERROR "[$svc] import failed"; return 1; }
    n="$(podman exec "$c" mariadb -uroot -p"$TEST_PW" -N -B -e \
        "SELECT count(*) FROM information_schema.tables WHERE table_schema='$db'" 2>/dev/null | tr -d '[:space:]')"
    [[ "${n:-0}" -gt 0 ]] && { log SUCCESS "[$svc] restored, ${n} tables"; return 0; }
    log ERROR "[$svc] restore produced 0 tables"; return 1
}

test_mongo() {  # args: svc
    local svc="$1" c="dbrestoretest-${1}" dump n
    dump="$(latest_dump "$svc")"; [[ -n "$dump" ]] || { log ERROR "[$svc] no dump found"; return 1; }
    podman rm -f "$c" >/dev/null 2>&1 || true
    trap 'podman rm -f "'"$c"'" >/dev/null 2>&1 || true; trap - RETURN' RETURN
    podman run -d --rm --name "$c" --network none \
        -e MONGO_INITDB_ROOT_USERNAME=root -e MONGO_INITDB_ROOT_PASSWORD="$TEST_PW" \
        "$IMG_MONGO" >/dev/null || { log ERROR "[$svc] could not start mongo"; return 1; }
    wait_ready "$c" "mongosh --quiet -u root -p ${TEST_PW} --authenticationDatabase admin --eval 'db.adminCommand(\"ping\")'" \
        || { log ERROR "[$svc] ephemeral Mongo never ready"; return 1; }
    zstd -dc "$dump" | podman exec -i "$c" mongorestore --quiet \
        -u root -p "$TEST_PW" --authenticationDatabase admin --archive >/dev/null 2>&1 || { log ERROR "[$svc] mongorestore failed"; return 1; }
    n="$(podman exec "$c" mongosh --quiet -u root -p "$TEST_PW" --authenticationDatabase admin --eval \
        'db.adminCommand("listDatabases").databases.filter(d=>!["admin","config","local"].includes(d.name)).length' 2>/dev/null | tr -d '[:space:]')"
    [[ "${n:-0}" -gt 0 ]] && { log SUCCESS "[$svc] restored, ${n} user database(s)"; return 0; }
    log ERROR "[$svc] restore produced 0 user databases"; return 1
}

test_archive() {  # args: svc   (integrity + structure only — for TSDB tarballs)
    local svc="$1" dump
    dump="$(latest_dump "$svc")"; [[ -n "$dump" ]] || { log ERROR "[$svc] no dump found"; return 1; }
    zstd -t "$dump" >/dev/null 2>&1 || { log ERROR "[$svc] zstd integrity check failed"; return 1; }
    zstd -dc "$dump" | tar -tf - >/dev/null 2>&1 || { log ERROR "[$svc] tar structure check failed"; return 1; }
    log SUCCESS "[$svc] archive integrity + structure OK"; return 0
}

test_sqlite() {  # args: svc   (decompress + integrity_check + table count, host sqlite3)
    local svc="$1" dump tmp n
    dump="$(latest_dump "$svc")"; [[ -n "$dump" ]] || { log ERROR "[$svc] no dump found"; return 1; }
    tmp="$(mktemp)" || return 1
    zstd -dc "$dump" > "$tmp" 2>/dev/null
    if [[ "$(sqlite3 "$tmp" 'PRAGMA integrity_check' 2>/dev/null)" != "ok" ]]; then
        log ERROR "[$svc] integrity_check failed"; rm -f "$tmp"; return 1
    fi
    n="$(sqlite3 "$tmp" "SELECT count(*) FROM sqlite_master WHERE type='table'" 2>/dev/null)"
    rm -f "$tmp"
    [[ "${n:-0}" -gt 0 ]] && { log SUCCESS "[$svc] integrity ok, ${n} tables"; return 0; }
    log ERROR "[$svc] 0 tables"; return 1
}

run_test() {  # run_test <svc> <fn> [args...]
    local svc="$1" fn="$2"; shift 2
    [[ -n "$ONLY_SERVICE" && "$ONLY_SERVICE" != "$svc" ]] && return 0
    log INFO "[$svc] restore test starting"
    if "$fn" "$svc" "$@"; then record "$svc" 1; else record "$svc" 0; fi
}

flush_metrics() {
    local out s
    out="$( {
        echo "# HELP db_restore_test_success Restore test result: 1=restored+validated, 0=failed"
        echo "# TYPE db_restore_test_success gauge"
        for s in "${!R_OK[@]}"; do echo "db_restore_test_success{database=\"$s\"} ${R_OK[$s]}"; done
        echo "# HELP db_restore_test_last_timestamp Unix timestamp of last successful restore test"
        echo "# TYPE db_restore_test_last_timestamp gauge"
        for s in "${!R_OK[@]}"; do
            local ts="${R_TS[$s]:-}"
            [[ -z "$ts" && -f "$METRICS_FILE" ]] && ts="$(grep -oP "db_restore_test_last_timestamp\{database=\"$s\"\} \K[0-9]+" "$METRICS_FILE" 2>/dev/null | tail -1)"
            [[ -n "$ts" ]] && echo "db_restore_test_last_timestamp{database=\"$s\"} ${ts}"
        done
        echo "# HELP db_restore_test_last_run_timestamp Unix timestamp of last db-restore-test.sh run"
        echo "# TYPE db_restore_test_last_run_timestamp gauge"
        echo "db_restore_test_last_run_timestamp ${RUN_TS}"
    } )"
    if [[ $KEEP -eq 1 ]]; then echo "--- metrics (test mode, not written) ---" >&2; echo "$out"; return 0; fi
    mkdir -p "$METRICS_DIR"
    printf '%s\n' "$out" > "${METRICS_FILE}.tmp"
    mv "${METRICS_FILE}.tmp" "$METRICS_FILE"
}

main() {
    mkdir -p "$LOG_DIR"
    log INFO "db-restore-test starting${ONLY_SERVICE:+ (only=${ONLY_SERVICE})}"
    run_test postgresql-immich test_pg     "$IMG_IMMICH" immich  immich
    run_test forgejo-db        test_pg     "$IMG_PG16"   forgejo forgejo
    run_test nextcloud-db      test_mariadb nextcloud
    run_test gathio-db         test_mongo
    run_test prometheus        test_archive
    run_test vaultwarden       test_sqlite
    flush_metrics
    local fails=0 total="${#R_OK[@]}"
    for s in "${!R_OK[@]}"; do [[ "${R_OK[$s]}" == "1" ]] || fails=$((fails + 1)); done
    log INFO "db-restore-test finished: $((total - fails))/${total} restored OK"
    return 0
}

main "$@"
