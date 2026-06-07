#!/bin/bash
################################################################################
# pihole-exporter-watchdog.sh — self-heal a wedged pihole-exporter
#
# Context (2026-06-04 false-page incident):
#   ekofr/pihole-exporter serves /metrics SYNCHRONOUSLY (full Pi-hole v6
#   login→query cycle per scrape). On 2026-06-04 its latency stepped 0.26s →
#   >10s and stayed there for 3 days, tripping Prometheus' scrape_timeout
#   (up=0) and a false CRITICAL "Pi-hole down" page. The process never crashed
#   (RestartCount=0) and the image is distroless (no in-container HealthCmd
#   possible), so nothing auto-recovered it. A manual restart fixed it instantly.
#
#   This watchdog supplies the missing self-heal WITHOUT depending on
#   in-container tooling: it reads the verdict Prometheus already computes every
#   scrape (up + scrape_duration), and restarts pihole-exporter.service when the
#   exporter is wedged or degrading toward the timeout.
#
# Triggers a restart when EITHER:
#   - DOWN:      up{job="pihole"} has been 0 for the whole last 5m, OR
#   - DEGRADING: mean scrape_duration over 5m > 15s (creeping toward the 20s
#                timeout — heals proactively, before `up` flips and pages).
#
# Cooldown: never restarts more than once per COOLDOWN_SECS. If it's still bad
# after a restart, that means the fault is NOT the exporter (e.g. Pi-hole API
# genuinely down) — we back off and let PiHoleExporterDown (warning) page instead
# of crash-looping the sidecar.
#
# Emits a textfile metric (node_exporter collector dir) so restarts are visible
# and a future alert can catch a flapping watchdog (= deeper problem).
#
# Safe: only ever restarts a metrics SIDECAR — zero DNS impact.
################################################################################

set -euo pipefail

PROM_CONTAINER="${PROM_CONTAINER:-prometheus}"
EXPORTER_UNIT="${EXPORTER_UNIT:-pihole-exporter.service}"
DEGRADE_SECS="${DEGRADE_SECS:-15}"        # mean scrape_duration over 5m above this = degrading
COOLDOWN_SECS="${COOLDOWN_SECS:-1200}"    # min seconds between restarts (20m)
METRICS_DIR="${HOME}/containers/data/backup-metrics"
METRICS_FILE="${METRICS_DIR}/pihole-exporter-watchdog.prom"

# systemd-cron environment (consistent with sibling scripts)
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

now=$(date +%s)

# --- read the verdict Prometheus already computes -----------------------------
# Returns the scalar value of an instant query, or "" if unavailable/empty.
promq() {
    local enc="$1" out
    out=$(podman exec "$PROM_CONTAINER" wget -qO- "http://localhost:9090/api/v1/query?query=${enc}" 2>/dev/null) || return 0
    printf '%s' "$out" | python3 -c '
import json, sys
try:
    r = json.load(sys.stdin)["data"]["result"]
    print(r[0]["value"][1] if r else "")
except Exception:
    print("")
' 2>/dev/null || printf ''
}

# up==0 for the ENTIRE last 5m (max_over_time==0 ⇒ never came up). 1=down, 0=ok, ""=unknown.
down=$(promq 'max_over_time(up%7Bjob%3D%22pihole%22%7D%5B5m%5D)')
# mean scrape latency over 5m.
dur=$(promq 'avg_over_time(scrape_duration_seconds%7Bjob%3D%22pihole%22%7D%5B5m%5D)')

if [[ -z "$down" && -z "$dur" ]]; then
    log "Prometheus unreachable or no pihole samples yet — nothing to evaluate (exit 0)"
    # still refresh heartbeat below
fi

is_down=0;     [[ "$down" == "0" ]] && is_down=1   # max_over_time==0 means continuously down
is_degraded=0; [[ -n "$dur" ]] && awk "BEGIN{exit !($dur > $DEGRADE_SECS)}" && is_degraded=1

# --- read prior watchdog state ------------------------------------------------
prev_total=0; last_restart=0
if [[ -f "$METRICS_FILE" ]]; then
    prev_total=$(awk '/^pihole_exporter_watchdog_restart_total /{print int($2)}' "$METRICS_FILE" 2>/dev/null || echo 0)
    last_restart=$(awk '/^pihole_exporter_watchdog_last_restart_timestamp_seconds /{print int($2)}' "$METRICS_FILE" 2>/dev/null || echo 0)
fi
prev_total=${prev_total:-0}; last_restart=${last_restart:-0}

restarted=0
reason=""
[[ $is_down -eq 1 ]] && reason="up=0 for >5m"
[[ $is_degraded -eq 1 ]] && reason="${reason:+$reason; }mean scrape_duration ${dur}s > ${DEGRADE_SECS}s"

if [[ $is_down -eq 1 || $is_degraded -eq 1 ]]; then
    since_last=$(( now - last_restart ))
    if (( since_last >= COOLDOWN_SECS )); then
        log "UNHEALTHY ($reason) → restarting ${EXPORTER_UNIT}"
        if systemctl --user restart "$EXPORTER_UNIT"; then
            restarted=1; last_restart=$now; prev_total=$(( prev_total + 1 ))
            log "restart issued (restart_total=$prev_total)"
        else
            log "ERROR: systemctl --user restart ${EXPORTER_UNIT} failed"
        fi
    else
        log "UNHEALTHY ($reason) but in cooldown (${since_last}s < ${COOLDOWN_SECS}s) — backing off; PiHoleExporterDown will page if persistent"
    fi
else
    log "healthy (down='${down:-NA}' mean_scrape_duration='${dur:-NA}s')"
fi

# --- emit textfile metric (atomic, in-dir tmp → inherits container_file_t) -----
mkdir -p "$METRICS_DIR"
out=$(cat <<EOF
# HELP pihole_exporter_watchdog_last_run_timestamp_seconds Unix timestamp of the last watchdog run.
# TYPE pihole_exporter_watchdog_last_run_timestamp_seconds gauge
pihole_exporter_watchdog_last_run_timestamp_seconds $now
# HELP pihole_exporter_watchdog_restart_total Cumulative pihole-exporter restarts issued by the watchdog.
# TYPE pihole_exporter_watchdog_restart_total counter
pihole_exporter_watchdog_restart_total $prev_total
# HELP pihole_exporter_watchdog_last_restart_timestamp_seconds Unix timestamp of the last restart issued.
# TYPE pihole_exporter_watchdog_last_restart_timestamp_seconds gauge
pihole_exporter_watchdog_last_restart_timestamp_seconds $last_restart
# HELP pihole_exporter_watchdog_restarted Whether this run issued a restart (1) or not (0).
# TYPE pihole_exporter_watchdog_restarted gauge
pihole_exporter_watchdog_restarted $restarted
EOF
)
printf '%s\n' "$out" > "${METRICS_FILE}.tmp"
mv "${METRICS_FILE}.tmp" "$METRICS_FILE"
