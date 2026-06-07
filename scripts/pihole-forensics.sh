#!/usr/bin/env bash
# pihole-forensics.sh — read-only diagnostic capture for the Pi-hole v6 resolver.
#
# Context: pihole-exporter (on fedora-htpc) degraded to >10s scrape latency at
# 2026-06-04 ~20:28 UTC (= 22:28 CEST), tripping a false "Pi-hole down" page for
# 3 days. A restart of the *exporter* fixed it (latency 0.25s), so FTL itself was
# not the bottleneck. This script captures what happened ON THE PI around that
# window to identify the TRIGGER (FTL restart? gravity run? session throttle?
# under-voltage?) and to confirm the resolver is healthy.
#
# SAFE: read-only. No restarts, no config changes, no deletes. Per-command timeout
# so it can never hang. Secrets (password, session IDs) are never written.
#
# Usage on the Pi (raspberrypi @ 192.168.1.69):
#   # optional: lets the script time a REAL authenticated login cycle
#   export PIHOLE_PW='your-admin-or-app-password'
#   sudo -E bash pihole-forensics.sh
#   # then copy the printed output file back.
#
# Without sudo it still runs; privileged log reads will just be marked SKIPPED.

set -u
API="http://127.0.0.1:80"            # FTL embedded webserver / API base
INCIDENT_DATE="2026-06-04"           # local date of the regression onset (CEST)
OUT="${HOME:-/tmp}/pihole-forensics-$(hostname)-$(date +%Y%m%d-%H%M%S).txt"

# ---- helpers ---------------------------------------------------------------
exec > >(tee -a "$OUT") 2>&1
sec()  { printf '\n========== %s ==========\n' "$*"; }
run()  { printf '$ %s\n' "$*"; timeout 25 bash -c "$*" 2>&1 || echo "[exit $? — failed/timeout/skipped]"; echo; }
have() { command -v "$1" >/dev/null 2>&1; }
redact() { sed -E 's/("sid"|"validity"|"csrf")[^,}]*/\1":"<redacted>"/g; s/password=[^ &]*/password=<redacted>/g'; }
# run() executes via `bash -c`, a child shell — export redact so it's importable
# there (the original bug: "redact: command not found" inside run()).
export -f redact

sec "META"
echo "output_file : $OUT"
echo "generated   : $(date -u '+%Y-%m-%dT%H:%M:%SZ') (UTC) / $(date '+%Y-%m-%d %H:%M:%S %Z') (local)"
echo "host        : $(hostname)  kernel=$(uname -r)"
echo "incident    : ${INCIDENT_DATE} ~20:28 UTC (22:28 CEST) — exporter latency 0.26s -> >10s"
echo "auth probe  : $([ -n "${PIHOLE_PW:-}" ] && echo 'PIHOLE_PW set — real login cycle will be timed' || echo 'PIHOLE_PW unset — only unauth timing')"

sec "SYSTEM STATE (now)"
run "uptime"
run "free -h"
run "df -h / /var /var/log 2>/dev/null | sort -u"
run "cat /proc/loadavg"

sec "RASPBERRY PI HEALTH (throttling / under-voltage — a classic cause of erratic slowness)"
if have vcgencmd; then
  run "vcgencmd get_throttled"   # 0x0 = healthy; any bit set = power/thermal event
  run "vcgencmd measure_temp"
else echo "vcgencmd not present (not a Pi, or firmware tools missing)"; fi
run "sudo dmesg -T 2>/dev/null | grep -iE 'under-voltage|throttl|oom|hung task' | tail -30 || echo '[needs sudo / none found]'"

sec "THERMAL / COOLING DEEP-DIVE (idle CPU + chronic 80-86C ⇒ heat-removal fault, not load)"
if have vcgencmd; then
  run "vcgencmd measure_clock arm"        # throttled clock sits well below max (1.5-1.8GHz)
  run "vcgencmd measure_volts core"
  run "vcgencmd get_config int | grep -iE 'fan|temp|arm_freq|over_volt' || echo '[no relevant config ints]'"
fi
echo "--- thermal zones (type + temp, millideg) + trip points ---"
run "for z in /sys/class/thermal/thermal_zone*; do printf '%s type=' \"\$z\"; cat \"\$z/type\" 2>/dev/null; printf '  temp='; cat \"\$z/temp\" 2>/dev/null; done"
echo "--- cooling devices: a fan appears here; cur_state 0 while HOT = fan NOT spinning ---"
run "for c in /sys/class/thermal/cooling_device*; do printf '%s type=' \"\$c\"; cat \"\$c/type\" 2>/dev/null; printf '  cur='; cat \"\$c/cur_state\" 2>/dev/null; printf ' max='; cat \"\$c/max_state\" 2>/dev/null; echo; done 2>/dev/null || echo '[no cooling_device entries — no managed fan]'"
echo "--- fan / cooling directives in firmware config.txt (missing dtoverlay = fan never told to spin) ---"
run "grep -inE 'fan|dtoverlay|temp|cooling' /boot/firmware/config.txt /boot/config.txt 2>/dev/null || echo '[no fan/cooling directives found]'"
echo "--- top CPU consumers (confirm NOTHING is generating the heat) ---"
run "ps -eo pcpu,pmem,comm --sort=-pcpu | head -8"
echo "--- USB devices (a faulty/hot peripheral can heat the board) ---"
run "lsusb 2>/dev/null || echo '[lsusb n/a]'"

sec "PI-HOLE / FTL VERSION & STATUS"
run "pihole -v 2>&1 | head"
run "pihole-FTL --version 2>&1 | head"
run "pihole status 2>&1 | head"

sec "FTL SERVICE LIFECYCLE (did FTL restart at the incident time?)"
run "systemctl show pihole-FTL -p ActiveEnterTimestamp,ExecMainStartTimestamp,NRestarts,ActiveState,SubState"
run "systemctl status pihole-FTL --no-pager -n 5 2>&1 | head -20"

sec "FTL/SYSTEM JOURNAL AROUND INCIDENT (${INCIDENT_DATE} 20:00–23:30 local)"
run "sudo journalctl -u pihole-FTL --since '${INCIDENT_DATE} 20:00:00' --until '${INCIDENT_DATE} 23:30:00' --no-pager 2>&1 | tail -120 || echo '[needs sudo]'"
run "sudo journalctl --since '${INCIDENT_DATE} 20:20:00' --until '${INCIDENT_DATE} 22:40:00' --no-pager 2>&1 | grep -iE 'pihole|FTL|lighttpd|webserver|reboot|shutdown|systemd' | tail -80 || echo '[needs sudo]'"

sec "FTL.log AROUND INCIDENT (lifecycle + auth/session events)"
for f in /var/log/pihole/FTL.log /var/log/pihole/FTL.log.1; do
  [ -f "$f" ] || continue
  echo "--- $f : lines on ${INCIDENT_DATE} 20:00–23:59 local ---"
  run "grep -E '${INCIDENT_DATE} 2[0-3]:' '$f' | redact | tail -150"
done
echo "--- recent FTL lifecycle/auth/error lines (whole log) ---"
run "grep -hiE 'Starting|Shutting down|listening|api|auth|session|seat|rate.?limit|ERROR|WARNING' /var/log/pihole/FTL.log 2>/dev/null | redact | tail -80"

sec "API CONFIG — session limits & rate limiting (the throttle suspects)"
for key in webserver.api.max_sessions webserver.api.app_sudo webserver.api.prettyJSON \
           webserver.api.maxHistory dns.rateLimit.count dns.rateLimit.interval \
           webserver.session.timeout misc.privacylevel; do
  run "pihole-FTL --config $key 2>&1 | head -3"
done

sec "WHAT'S LISTENING ON :80 / FIREWALL (port 80 reachable from .70?)"
run "sudo ss -tlnp 2>/dev/null | grep -E ':80 |:443 |:53 ' || ss -tln | grep -E ':80|:443|:53'"
run "sudo ufw status 2>&1 | head -20 || echo '[ufw not used / needs sudo]'"

sec "PACKAGE / GRAVITY ACTIVITY ON INCIDENT DATE (did an update restart FTL?)"
run "grep -A2 -iE '${INCIDENT_DATE}|$(date -d "${INCIDENT_DATE}" '+%Y-%m-%d' 2>/dev/null)' /var/log/apt/history.log 2>/dev/null | tail -40 || echo '[no apt history match]'"
run "zgrep -A2 -iE '${INCIDENT_DATE}' /var/log/apt/history.log.1.gz 2>/dev/null | tail -40 || true"
run "ls -l --time-style=full-iso /etc/pihole/gravity.db 2>/dev/null"
run "tail -15 /var/log/pihole/pihole_updateGravity.log 2>/dev/null || echo '[no gravity log]'"

sec "LIVE API TIMING (reproduce what the exporter does)"
echo "--- unauthenticated GETs (baseline; should be ~0.001s, HTTP 401) ---"
for ep in /api/auth /api/stats/summary /api/info/ftl; do
  run "curl -s -o /dev/null -w '$ep -> HTTP %{http_code} time_total=%{time_total}s\n' --max-time 20 '$API$ep'"
done
echo "--- failed POST /api/auth (dummy pw): measures brute-force/throttle delay ---"
run "curl -s -o /dev/null -w 'POST /api/auth(bad) -> HTTP %{http_code} time_total=%{time_total}s\n' --max-time 20 -H 'Content-Type: application/json' -d '{\"password\":\"forensic-probe\"}' '$API/api/auth'"

if [ -n "${PIHOLE_PW:-}" ]; then
  echo "--- REAL authenticated cycle: login -> sessions -> summary -> logout (timed) ---"
  SID=$(curl -s --max-time 20 -H 'Content-Type: application/json' \
        -d "{\"password\":\"${PIHOLE_PW}\"}" "$API/api/auth" \
        | grep -oE '"sid"[[:space:]]*:[[:space:]]*"[^"]+"' | sed -E 's/.*"sid"[^"]*"([^"]+)"/\1/' )
  if [ -n "${SID:-}" ]; then
    echo "login: OK (sid captured, redacted)"
    run "curl -s -o /dev/null -w 'GET /api/auth/sessions -> HTTP %{http_code} time_total=%{time_total}s\n' --max-time 20 -H 'sid: $SID' '$API/api/auth/sessions'"
    echo "--- active sessions (counts only; SIDs redacted) ---"
    run "curl -s --max-time 20 -H 'sid: $SID' '$API/api/auth/sessions' | redact | head -40"
    run "curl -s -o /dev/null -w 'GET /api/stats/summary -> HTTP %{http_code} time_total=%{time_total}s\n' --max-time 20 -H 'sid: $SID' '$API/api/stats/summary'"
    # be a good citizen: delete the session we created
    curl -s -o /dev/null --max-time 10 -X DELETE -H "sid: $SID" "$API/api/auth" && echo "logout: OK (session cleaned up)"
  else
    echo "login FAILED with provided PIHOLE_PW (wrong password, or API rejected). Skipped authed timing."
  fi
else
  echo "(PIHOLE_PW unset — skipped authenticated timing. Re-run with it set for the highest-value measurement.)"
fi

sec "DONE"
echo "Output written to: $OUT"
echo "Send this file back. Key things I'll look for:"
echo "  1. COOLING: cooling_device cur_state (0 while hot = fan not spinning), and"
echo "     whether config.txt has a fan dtoverlay at all. Leading hypothesis: heat-"
echo "     removal fault (idle CPU at 0.8% but 80-86C ⇒ not a workload problem)."
echo "  2. vcgencmd get_throttled bits + measure_clock arm (throttled below max)."
echo "  3. ps top CPU consumers (confirm nothing is generating the heat)."
echo "  4. FTL lifecycle / FTL.log around ${INCIDENT_DATE} 22:28 CEST (exporter-wedge trigger)."
