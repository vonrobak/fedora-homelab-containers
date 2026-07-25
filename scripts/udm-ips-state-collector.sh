#!/bin/bash
################################################################################
# udm-ips-state-collector.sh — UDM Pro IPS engine/ruleset state → node_exporter
#
# WHY THIS EXISTS
#
# `ubnt-idsips-daemon` on the UDM Pro re-attempts a Suricata engine upgrade
# (v6 -> v8) every hour and fails every hour with INSUFFICIENT_MEMORY: exactly
# 24 events/day for at least 7 consecutive days, with zero variance across a
# memory swing of 56.2%-70.4%. Toggling Intrusion Prevention off/on on
# 2026-07-25 forced a genuine live re-check ("detect memory is insufficient for
# upgrade, set status to memory_insufficient") which failed *at the moment of
# maximum free memory*, immediately after the running engine had been stopped
# (1.73 GiB free at the weekly minimum). Conclusion: the check is not satisfiable
# by freeing memory on a 4 GB UDM Pro, so the hourly line is a standing condition,
# not an incident.
#
# 168 identical log lines per week is alarm fatigue in log form (L-042). The fix is
# not to ignore them, it is to represent the condition as STATE instead of as an
# EVENT STREAM: one gauge you can alert on and graph, plus a promtail drop stage
# for the repeated line (see config/promtail/promtail-config.yml).
#
# WHY IT READS THE RAW FILE, NOT LOKI
#
# Deliberate decoupling: promtail drops the noisy line on the way to Loki, so a
# Loki-sourced exporter would starve the moment the suppression works. syslog-ng
# writes udm.log; this script reads that file directly, so it still sees
# everything Loki no longer stores. Never invert this.
#
# WHAT IT PARSES (two independent sources, different cadences)
#
#   hourly    EVT_GW_UpgradeSuricata ... current_version:N status:S target_version:M
#             -> engine version, target, and blocked/ok state. Always fresh.
#   on start  the daemon's config JSON dump (only emitted on daemon start, i.e.
#             rarely) -> rule_count, ruleset update_time, suricata_version.
#             Last-known-value semantics: a stale rule_count is correct here,
#             because the ruleset genuinely has not changed since it was logged.
#
# Both are scanned newest-first across the live file and today's rotated file, so
# a rotation at midnight doesn't blank the metrics. If a field is never found, its
# metric is OMITTED rather than emitted as 0 — absence must look like absence
# (L-099), which is the whole lesson that produced this script.
#
# Root-free. Runs as a USER systemd oneshot and writes its .prom as user 1000, so
# the file lands with the container_file_t context the rootless node_exporter needs
# (same contract as btrfs-dev-stats-collector.sh).
#
# Schedule: udm-ips-state.timer @ every 15 min.
################################################################################
set -uo pipefail
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

TEXTFILE_DIR="${HOME}/containers/data/backup-metrics"
OUT="${TEXTFILE_DIR}/udm-ips-state.prom"
LOG_DIR="/mnt/btrfs-pool/subvol7-containers/unifi-syslog"
RUN_TS="$(date +%s)"

# Live file plus today's rotated sibling — enough to survive a midnight rotation
# without reaching into the .gz archive on every 15-minute run.
mapfile -t SOURCES < <(
    printf '%s\n' "${LOG_DIR}/udm.log" "${LOG_DIR}/udm.log-$(date +%Y%m%d)"
)

# Newest matching line for a pattern, across the sources, or empty.
newest() {
    local pat="$1" f out=""
    for f in "${SOURCES[@]}"; do
        [[ -r "$f" ]] || continue
        out="$(grep -a -- "$pat" "$f" 2>/dev/null | tail -n1)"
        [[ -n "$out" ]] && printf '%s' "$out"
    done
}

emit() {
    local upg cfg cur tgt status blocked rules upd upd_ts

    # ---- hourly upgrade-status event -------------------------------------------
    upg="$(newest 'EVT_GW_UpgradeSuricata')"
    if [[ -n "$upg" ]]; then
        cur="$(grep -oE 'current_version:[0-9]+' <<< "$upg" | head -n1 | cut -d: -f2)"
        tgt="$(grep -oE 'target_version:[0-9]+'  <<< "$upg" | head -n1 | cut -d: -f2)"
        status="$(grep -oE 'status:[A-Z_]+'      <<< "$upg" | head -n1 | cut -d: -f2)"

        if [[ -n "$cur" ]]; then
            echo "# HELP udm_ips_engine_version Running Suricata engine major version on the UDM Pro."
            echo "# TYPE udm_ips_engine_version gauge"
            echo "udm_ips_engine_version ${cur}"
        fi
        if [[ -n "$tgt" ]]; then
            echo "# HELP udm_ips_engine_target_version Suricata engine version the UDM is attempting to upgrade to."
            echo "# TYPE udm_ips_engine_target_version gauge"
            echo "udm_ips_engine_target_version ${tgt}"
        fi
        if [[ -n "$status" ]]; then
            # 1 = the upgrade is being refused for the labelled reason. The reason
            # rides as a label so a change of cause (INSUFFICIENT_MEMORY -> something
            # else) is visible as a new series rather than a silent value change.
            [[ "$status" == "SUCCESS" || "$status" == "OK" ]] && blocked=0 || blocked=1
            echo "# HELP udm_ips_engine_upgrade_blocked 1 if the UDM is refusing the Suricata engine upgrade, 0 if it reports success."
            echo "# TYPE udm_ips_engine_upgrade_blocked gauge"
            echo "udm_ips_engine_upgrade_blocked{reason=\"${status}\"} ${blocked}"
        fi
    fi

    # ---- daemon config dump (rule inventory + ruleset freshness) ---------------
    cfg="$(newest 'upgrade_suricata_status')"
    if [[ -n "$cfg" ]]; then
        rules="$(grep -oE '"rule_count":[0-9]+' <<< "$cfg" | head -n1 | cut -d: -f2)"
        upd="$(grep -oE '"update_time":"[^"]+"' <<< "$cfg" | head -n1 | cut -d'"' -f4)"

        if [[ -n "$rules" ]]; then
            echo "# HELP udm_ips_rule_count Signatures loaded in the UDM Pro IPS ruleset, as last reported by the daemon."
            echo "# TYPE udm_ips_rule_count gauge"
            echo "udm_ips_rule_count ${rules}"
        fi
        if [[ -n "$upd" ]] && upd_ts="$(date -d "$upd" +%s 2>/dev/null)"; then
            # The signature freshness the CyberSecure UI shows. This is the metric
            # that matters operationally: the engine being pinned at v6 does NOT
            # imply stale rules, and conflating the two was the original mistake.
            echo "# HELP udm_ips_ruleset_update_timestamp_seconds Unix time of the last IPS signature/ruleset update."
            echo "# TYPE udm_ips_ruleset_update_timestamp_seconds gauge"
            echo "udm_ips_ruleset_update_timestamp_seconds ${upd_ts}"
        fi
    fi

    # ---- collector liveness ----------------------------------------------------
    # Distinguishes "the IPS is fine" from "this collector stopped running", which
    # a missing-metric alert alone cannot.
    echo "# HELP udm_ips_state_last_run_timestamp Unix time of the last UDM IPS state collection."
    echo "# TYPE udm_ips_state_last_run_timestamp gauge"
    echo "udm_ips_state_last_run_timestamp ${RUN_TS}"
}

mkdir -p "$TEXTFILE_DIR"
tmp="$(mktemp "${TEXTFILE_DIR}/.udmips.XXXXXX")" || exit 1
trap 'rm -f "$tmp"' EXIT
emit > "$tmp"
chmod 644 "$tmp"
mv -f "$tmp" "$OUT"
trap - EXIT
