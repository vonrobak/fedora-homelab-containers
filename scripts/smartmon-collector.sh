#!/bin/bash
################################################################################
# smartmon-collector.sh — SMART health/attributes → node_exporter textfile
#
# Storage-health monitoring (ADR-029). On a Single-data-profile pool with no live
# redundancy, SMART pre-failure attributes are the drive-firmware view of "this disk
# is about to die" — the complement to btrfs-dev-stats (the filesystem view). This
# puts them in the Prometheus -> Alertmanager -> Discord path you actually watch,
# instead of relying on smartd's local mail.
#
# Scope: the stable, fixed-bay internal disks (4 pool members + the NVMe SSD). These
# are the redundancy-less data + system devices. Removable LUKS2 backup drives are
# covered (when mounted) by btrfs-dev-stats-collector.sh; their by-id SMART can be
# added later. Device letters here are stable (fixed SATA bays + the sole NVMe).
#
# Privilege: smartctl needs root, granted via a tightly-scoped, no-wildcard
# /etc/sudoers.d/homelab-storage-health (read-only -H -A -i on these exact devices).
# The .prom is written as user 1000 (correct container_file_t context for the rootless
# node_exporter). Parses smartctl --json — NEVER the exit code (smartctl returns 0 with
# the real status inside the JSON). Degrades gracefully: if sudo/devices are absent it
# still writes a valid file (just the run timestamp), so the unit never fails.
#
# Schedule: smartmon.timer @ hourly (SMART attributes change slowly).
################################################################################
set -uo pipefail
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

TEXTFILE_DIR="${HOME}/containers/data/backup-metrics"
OUT="${TEXTFILE_DIR}/smartmon.prom"
RUN_TS="$(date +%s)"
SMARTCTL="/usr/sbin/smartctl"
DEVICES=(/dev/sda /dev/sdb /dev/sdc /dev/sdd /dev/nvme0)

# --- collect JSON per present device (read-only smartctl via NOPASSWD sudo) ---------
declare -A J
ORDER=()
for dev in "${DEVICES[@]}"; do
    [[ -e "$dev" ]] || continue
    out="$(sudo -n "$SMARTCTL" -j -H -A -i "$dev" 2>/dev/null)" || true
    [[ -n "$out" ]] || continue
    # must be parseable JSON with a device block, else skip
    jq -e '.device' >/dev/null 2>&1 <<<"$out" || continue
    J["$dev"]="$out"; ORDER+=("$dev")
done

san() { local s="${1//\\/}"; printf '%s' "${s//\"/}"; }   # strip backslashes + quotes for label safety

emit() {
    local dev j model serial proto v

    echo "# HELP smartmon_device_smart_healthy SMART overall-health self-assessment (1=PASSED, 0=FAILED)."
    echo "# TYPE smartmon_device_smart_healthy gauge"
    for dev in "${ORDER[@]}"; do
        j="${J[$dev]}"
        model="$(san "$(jq -r '.model_name // .scsi_model_name // "unknown"' <<<"$j")")"
        serial="$(san "$(jq -r '.serial_number // "unknown"' <<<"$j")")"
        proto="$(san "$(jq -r '.device.protocol // "unknown"' <<<"$j")")"
        v="$(jq -r 'if .smart_status.passed==true then 1 elif .smart_status.passed==false then 0 else empty end' <<<"$j")"
        [[ -n "$v" ]] && echo "smartmon_device_smart_healthy{device=\"${dev}\",model=\"${model}\",serial=\"${serial}\",protocol=\"${proto}\"} ${v}"
    done

    echo "# HELP smartmon_temperature_celsius Current drive temperature (Celsius)."
    echo "# TYPE smartmon_temperature_celsius gauge"
    for dev in "${ORDER[@]}"; do
        v="$(jq -r '.temperature.current // empty' <<<"${J[$dev]}")"
        [[ -n "$v" ]] && echo "smartmon_temperature_celsius{device=\"${dev}\"} ${v}"
    done

    echo "# HELP smartmon_power_on_hours Drive power-on time (hours)."
    echo "# TYPE smartmon_power_on_hours gauge"
    for dev in "${ORDER[@]}"; do
        v="$(jq -r '.power_on_time.hours // empty' <<<"${J[$dev]}")"
        [[ -n "$v" ]] && echo "smartmon_power_on_hours{device=\"${dev}\"} ${v}"
    done

    # --- ATA pre-failure attributes (the early-warning trio) ---
    echo "# HELP smartmon_reallocated_sectors ATA attr 5 (Reallocated_Sector_Ct) raw value."
    echo "# TYPE smartmon_reallocated_sectors gauge"
    for dev in "${ORDER[@]}"; do
        v="$(jq -r '.ata_smart_attributes.table[]? | select(.id==5) | .raw.value' <<<"${J[$dev]}" 2>/dev/null | head -1)"
        [[ -n "$v" ]] && echo "smartmon_reallocated_sectors{device=\"${dev}\"} ${v}"
    done
    echo "# HELP smartmon_current_pending_sectors ATA attr 197 (Current_Pending_Sector) raw value."
    echo "# TYPE smartmon_current_pending_sectors gauge"
    for dev in "${ORDER[@]}"; do
        v="$(jq -r '.ata_smart_attributes.table[]? | select(.id==197) | .raw.value' <<<"${J[$dev]}" 2>/dev/null | head -1)"
        [[ -n "$v" ]] && echo "smartmon_current_pending_sectors{device=\"${dev}\"} ${v}"
    done
    echo "# HELP smartmon_offline_uncorrectable ATA attr 198 (Offline_Uncorrectable) raw value."
    echo "# TYPE smartmon_offline_uncorrectable gauge"
    for dev in "${ORDER[@]}"; do
        v="$(jq -r '.ata_smart_attributes.table[]? | select(.id==198) | .raw.value' <<<"${J[$dev]}" 2>/dev/null | head -1)"
        [[ -n "$v" ]] && echo "smartmon_offline_uncorrectable{device=\"${dev}\"} ${v}"
    done

    # --- NVMe health log (SSD wear + media errors) ---
    echo "# HELP smartmon_nvme_media_errors NVMe media_errors count."
    echo "# TYPE smartmon_nvme_media_errors gauge"
    for dev in "${ORDER[@]}"; do
        v="$(jq -r '.nvme_smart_health_information_log.media_errors // empty' <<<"${J[$dev]}")"
        [[ -n "$v" ]] && echo "smartmon_nvme_media_errors{device=\"${dev}\"} ${v}"
    done
    echo "# HELP smartmon_nvme_percentage_used NVMe endurance used (percent; 100 = rated life)."
    echo "# TYPE smartmon_nvme_percentage_used gauge"
    for dev in "${ORDER[@]}"; do
        v="$(jq -r '.nvme_smart_health_information_log.percentage_used // empty' <<<"${J[$dev]}")"
        [[ -n "$v" ]] && echo "smartmon_nvme_percentage_used{device=\"${dev}\"} ${v}"
    done
    echo "# HELP smartmon_nvme_available_spare NVMe available spare (percent)."
    echo "# TYPE smartmon_nvme_available_spare gauge"
    for dev in "${ORDER[@]}"; do
        v="$(jq -r '.nvme_smart_health_information_log.available_spare // empty' <<<"${J[$dev]}")"
        [[ -n "$v" ]] && echo "smartmon_nvme_available_spare{device=\"${dev}\"} ${v}"
    done
    echo "# HELP smartmon_nvme_critical_warning NVMe critical_warning bitfield (0 = healthy)."
    echo "# TYPE smartmon_nvme_critical_warning gauge"
    for dev in "${ORDER[@]}"; do
        v="$(jq -r '.nvme_smart_health_information_log.critical_warning // empty' <<<"${J[$dev]}")"
        [[ -n "$v" ]] && echo "smartmon_nvme_critical_warning{device=\"${dev}\"} ${v}"
    done

    echo "# HELP smartmon_devices_collected Number of devices SMART data was read from this run."
    echo "# TYPE smartmon_devices_collected gauge"
    echo "smartmon_devices_collected ${#ORDER[@]}"
    echo "# HELP smartmon_collector_last_run_timestamp Unix time of the last SMART collection."
    echo "# TYPE smartmon_collector_last_run_timestamp gauge"
    echo "smartmon_collector_last_run_timestamp ${RUN_TS}"
}

mkdir -p "$TEXTFILE_DIR"
tmp="$(mktemp "${TEXTFILE_DIR}/.smartmon.XXXXXX")" || exit 1
trap 'rm -f "$tmp"' EXIT
emit > "$tmp"
chmod 644 "$tmp"
mv -f "$tmp" "$OUT"
trap - EXIT
