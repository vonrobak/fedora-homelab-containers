#!/bin/bash
################################################################################
# pihole-session-sweeper.sh — Mitigate ekofr/pihole-exporter session leak
#
# Context (GH#246):
#   The Pi-hole exporter (docker.io/ekofr/pihole-exporter) re-authenticates
#   when its session expires but never calls DELETE /api/auth on the previous
#   one. Pi-hole v6 does not garbage-collect expired sessions from the visible
#   pool, so abandoned sessions accumulate against api.max_sessions (16),
#   eventually rejecting new admin-UI logins with "too many requests".
#
#   Source confirmation: ensureAuth() at
#   github.com/eko/pihole-exporter internal/pihole/api_client.go — calls
#   c.Authenticate() (new session) without c.Logout() (does not exist).
#   Same root cause underlies upstream eko/pihole-exporter#318
#   ("endpoint gets slow until it stalls").
#
# Companion (already applied): Pi-hole webserver.session.timeout 1800 → 86400.
#   That alone drops the leak rate from 48/day to 1/day; this sweeper makes
#   the pool self-healing regardless of upstream-exporter behavior.
#
# Behavior:
#   1. Auth with the app-password from Podman secret pihole_api_token.
#   2. GET /api/auth/sessions; find any session where valid_until < now.
#   3. DELETE each expired session by id.
#   4. Log out the sweeper's own session (so this script never adds to the
#      problem it solves).
#   5. Emit a textfile metric for node_exporter so Prometheus can alert
#      before exhaustion regardless of whether sweeping keeps up.
#
# Idempotent. Safe to run as often as you like; defaults to hourly via
# pihole-session-sweeper.timer.
################################################################################

set -euo pipefail

PIHOLE_HOST="${PIHOLE_HOST:-192.168.1.69}"
SECRET_NAME="${PIHOLE_SECRET_NAME:-pihole_api_token}"
METRICS_DIR="${HOME}/containers/data/backup-metrics"
METRICS_FILE="${METRICS_DIR}/pihole-sessions.prom"
PIHOLE_MAX_SESSIONS="${PIHOLE_MAX_SESSIONS:-16}"

# systemd-cron environment (consistent with sibling scripts)
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
die() { log "FATAL: $*" >&2; exit 1; }

token=$(podman secret inspect --showsecret "$SECRET_NAME" --format '{{.SecretData}}' 2>/dev/null) \
    || die "Failed to read podman secret $SECRET_NAME"
[[ -n "$token" ]] || die "Empty token from $SECRET_NAME"

sid=""
cleanup() {
    local rc=$?
    if [[ -n "$sid" ]]; then
        curl -sS --max-time 5 -X DELETE \
            "http://${PIHOLE_HOST}/api/auth" \
            -H "X-FTL-SID: $sid" >/dev/null 2>&1 || true
    fi
    return $rc
}
trap cleanup EXIT

auth_resp=$(curl -sSf --max-time 10 -X POST "http://${PIHOLE_HOST}/api/auth" \
    -H "Content-Type: application/json" \
    -d "$(printf '{"password":"%s"}' "$token")") \
    || die "Auth POST failed"
sid=$(echo "$auth_resp" | python3 -c 'import json,sys; print(json.load(sys.stdin)["session"]["sid"])')
[[ -n "$sid" ]] || die "Auth response missing sid"

sessions_json=$(curl -sSf --max-time 10 \
    "http://${PIHOLE_HOST}/api/auth/sessions" \
    -H "X-FTL-SID: $sid") \
    || die "GET /api/auth/sessions failed"

now=$(date +%s)
read -r total expired_ids_csv < <(python3 -c '
import json, sys
j = json.load(sys.stdin)
sessions = j.get("sessions", [])
now = '"$now"'
my_sid = "'"$sid"'"
expired = [s["id"] for s in sessions
           if s.get("valid_until", 0) < now and s.get("sid","") != my_sid]
print(len(sessions), ",".join(str(i) for i in expired))
' <<<"$sessions_json")

deleted=0
failed=0
if [[ -n "${expired_ids_csv:-}" ]]; then
    IFS=',' read -ra ids <<<"$expired_ids_csv"
    for id in "${ids[@]}"; do
        if curl -sSf --max-time 5 -X DELETE \
            "http://${PIHOLE_HOST}/api/auth/session/${id}" \
            -H "X-FTL-SID: $sid" >/dev/null; then
            deleted=$((deleted + 1))
        else
            failed=$((failed + 1))
        fi
    done
fi

active_after=$((total - deleted))
log "sessions_before=$total expired_deleted=$deleted delete_failures=$failed sessions_after=$active_after max=$PIHOLE_MAX_SESSIONS"

# Emit textfile metric (atomic, in-dir tmp → inherits container_file_t).
# Same pattern as db-dump.sh per project_platform_gotchas.
mkdir -p "$METRICS_DIR"
out=$(cat <<EOF
# HELP pihole_sessions_active Active Pi-hole API sessions after the last sweep.
# TYPE pihole_sessions_active gauge
pihole_sessions_active $active_after
# HELP pihole_sessions_max Maximum allowed Pi-hole API sessions (Pi-hole config).
# TYPE pihole_sessions_max gauge
pihole_sessions_max $PIHOLE_MAX_SESSIONS
# HELP pihole_session_sweeper_deleted Sessions deleted by the sweeper in the most recent run.
# TYPE pihole_session_sweeper_deleted gauge
pihole_session_sweeper_deleted $deleted
# HELP pihole_session_sweeper_delete_failures Sweep delete attempts that failed in the most recent run.
# TYPE pihole_session_sweeper_delete_failures gauge
pihole_session_sweeper_delete_failures $failed
# HELP pihole_session_sweeper_last_success_timestamp_seconds Unix timestamp of last successful sweep.
# TYPE pihole_session_sweeper_last_success_timestamp_seconds gauge
pihole_session_sweeper_last_success_timestamp_seconds $now
EOF
)
printf '%s\n' "$out" > "${METRICS_FILE}.tmp"
mv "${METRICS_FILE}.tmp" "$METRICS_FILE"
