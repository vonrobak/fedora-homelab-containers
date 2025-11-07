#!/usr/bin/env bash
#
# Homelab Intelligence Script
# Analyzes system health and provides actionable recommendations
#
# Usage: ./homelab-intel.sh [--json] [--quiet]
#

set -euo pipefail

# Configuration
REPORT_DIR="${HOME}/containers/docs/99-reports"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
JSON_OUTPUT="${REPORT_DIR}/intel-${TIMESTAMP}.json"
STATE_FILE="${HOME}/containers/data/.intel-state.json"

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Flags
QUIET_MODE=false
JSON_MODE=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --json) JSON_MODE=true ;;
        --quiet) QUIET_MODE=true ;;
    esac
done

# Health scoring variables
HEALTH_SCORE=100
CRITICAL_ISSUES=()
WARNINGS=()
INFO_ITEMS=()

# Metrics collection
declare -A METRICS

##############################################################################
# Helper Functions
##############################################################################

log_header() {
    [[ "$QUIET_MODE" == "true" ]] && return
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
}

log_section() {
    [[ "$QUIET_MODE" == "true" ]] && return
    echo ""
    echo -e "${BLUE}────────────────────────────────────────────────────────────${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}────────────────────────────────────────────────────────────${NC}"
}

add_critical() {
    local code="$1"
    local message="$2"
    local action="$3"
    CRITICAL_ISSUES+=("{\"code\":\"$code\",\"message\":\"$message\",\"action\":\"$action\"}")
    HEALTH_SCORE=$((HEALTH_SCORE - 20))
}

add_warning() {
    local code="$1"
    local message="$2"
    local action="$3"
    WARNINGS+=("{\"code\":\"$code\",\"message\":\"$message\",\"action\":\"$action\"}")
    HEALTH_SCORE=$((HEALTH_SCORE - 5))
}

add_info() {
    local code="$1"
    local message="$2"
    INFO_ITEMS+=("{\"code\":\"$code\",\"message\":\"$message\"}")
}

##############################################################################
# System Checks
##############################################################################

check_system_basics() {
    log_section "System Basics"

    local uptime_seconds
    uptime_seconds=$(awk '{print int($1)}' /proc/uptime)
    local uptime_days=$((uptime_seconds / 86400))
    local uptime_hours=$(((uptime_seconds % 86400) / 3600))

    METRICS[uptime_seconds]=$uptime_seconds
    METRICS[uptime_days]=$uptime_days

    [[ "$QUIET_MODE" == "false" ]] && echo "Uptime: $uptime_days days, $uptime_hours hours"

    # Check if system needs reboot (kernel update)
    if [ -f /var/run/reboot-required ] || needs-restarting -r &>/dev/null; then
        add_warning "W003" "System restart recommended (kernel update pending)" "Reboot system when convenient"
    fi

    # Check SELinux
    local selinux_status
    selinux_status=$(getenforce 2>/dev/null || echo "Unknown")
    METRICS[selinux]="$selinux_status"

    if [[ "$selinux_status" != "Enforcing" ]]; then
        add_critical "C001" "SELinux not in enforcing mode: $selinux_status" "Enable SELinux enforcing mode"
    fi

    [[ "$QUIET_MODE" == "false" ]] && echo "SELinux: $selinux_status"
}

check_disk_usage() {
    log_section "Disk Usage"

    # System SSD check (critical - 128GB limit)
    local root_usage
    root_usage=$(df / | awk 'NR==2 {print int($5)}')
    METRICS[disk_root_percent]=$root_usage

    [[ "$QUIET_MODE" == "false" ]] && echo "System SSD: ${root_usage}%"

    if [ "$root_usage" -ge 90 ]; then
        add_critical "C002" "System SSD at ${root_usage}% capacity (critical)" "Clean up immediately - system may fail"
    elif [ "$root_usage" -ge 80 ]; then
        add_critical "C003" "System SSD at ${root_usage}% capacity" "Clean up logs, prune containers"
    elif [ "$root_usage" -ge 70 ]; then
        add_warning "W001" "System SSD at ${root_usage}% capacity" "Consider archiving old logs"
    fi

    # BTRFS pool check
    if [ -d /mnt/btrfs-pool ]; then
        local btrfs_usage
        btrfs_usage=$(btrfs fi usage /mnt/btrfs-pool 2>/dev/null | grep "^Device allocated:" | awk '{print $3}' | sed 's/%//' || echo "0")
        METRICS[disk_btrfs_percent]=${btrfs_usage:-0}
        [[ "$QUIET_MODE" == "false" ]] && echo "BTRFS Pool: ${btrfs_usage}%"
    fi
}

check_services() {
    log_section "Service Health"

    local critical_services=("traefik" "prometheus" "alertmanager" "grafana")
    local running_count=0
    local failed_services=()

    for service in "${critical_services[@]}"; do
        if systemctl --user is-active "${service}.service" &>/dev/null; then
            ((running_count++))
        else
            failed_services+=("$service")
        fi
    done

    METRICS[services_running]=$running_count
    METRICS[services_total]=${#critical_services[@]}

    [[ "$QUIET_MODE" == "false" ]] && echo "Critical services: $running_count/${#critical_services[@]} running"

    if [ ${#failed_services[@]} -gt 0 ]; then
        add_critical "C004" "Critical services not running: ${failed_services[*]}" "Start failed services immediately"
    else
        add_info "I001" "All ${#critical_services[@]} critical services running healthy" ""
    fi

    # Count all running containers
    local container_count
    container_count=$(podman ps --format "{{.Names}}" 2>/dev/null | wc -l || echo "0")
    METRICS[containers_running]=$container_count

    [[ "$QUIET_MODE" == "false" ]] && echo "Running containers: $container_count"
}

check_resource_usage() {
    log_section "Resource Usage"

    # Memory
    local mem_total mem_used mem_percent
    mem_total=$(free -m | awk 'NR==2 {print $2}')
    mem_used=$(free -m | awk 'NR==2 {print $3}')
    mem_percent=$((mem_used * 100 / mem_total))

    METRICS[memory_total_mb]=$mem_total
    METRICS[memory_used_mb]=$mem_used
    METRICS[memory_percent]=$mem_percent

    [[ "$QUIET_MODE" == "false" ]] && echo "Memory: ${mem_used}MB / ${mem_total}MB (${mem_percent}%)"

    if [ "$mem_percent" -ge 90 ]; then
        add_warning "W004" "Memory usage high: ${mem_percent}%" "Review container resource limits"
    fi

    # CPU (5-second average)
    local cpu_idle
    cpu_idle=$(mpstat 1 1 2>/dev/null | awk 'END {print int($NF)}' || echo "95")
    local cpu_usage=$((100 - cpu_idle))
    METRICS[cpu_usage_percent]=$cpu_usage

    [[ "$QUIET_MODE" == "false" ]] && echo "CPU Usage (avg): ${cpu_usage}%"

    # Swap
    local swap_used
    swap_used=$(free -m | awk 'NR==3 {print $3}')
    METRICS[swap_used_mb]=${swap_used:-0}

    [[ "$QUIET_MODE" == "false" ]] && echo "Swap Usage: ${swap_used}MB"

    if [ "${swap_used:-0}" -gt 512 ]; then
        add_warning "W005" "Swap in use: ${swap_used}MB" "System may be low on memory"
    fi
}

check_backups() {
    log_section "Backup Status"

    # Check for recent external backup
    local backup_dir="/run/media/${USER}/WD-18TB/.snapshots"
    local last_backup_age=-1

    if [ -d "$backup_dir" ]; then
        local latest_backup
        latest_backup=$(find "$backup_dir" -maxdepth 2 -type d -name "htpc-home*" -o -name "subvol*" 2>/dev/null | head -1)

        if [ -n "$latest_backup" ]; then
            last_backup_age=$(( ($(date +%s) - $(stat -c %Y "$latest_backup")) / 86400 ))
            METRICS[last_backup_days_ago]=$last_backup_age

            [[ "$QUIET_MODE" == "false" ]] && echo "Last external backup: $last_backup_age days ago"

            if [ "$last_backup_age" -gt 14 ]; then
                add_warning "W002" "No recent backup detected (>14 days)" "Check external drive and run backup"
            elif [ "$last_backup_age" -gt 7 ]; then
                add_info "I002" "Backup slightly overdue ($last_backup_age days)" ""
            fi
        fi
    else
        add_info "I003" "External backup drive not mounted" ""
        METRICS[last_backup_days_ago]=-1
    fi
}

check_certificates() {
    log_section "SSL Certificates"

    local acme_file="${HOME}/containers/config/traefik/letsencrypt/acme.json"

    if [ -f "$acme_file" ]; then
        local cert_age_days
        cert_age_days=$(( ($(date +%s) - $(stat -c %Y "$acme_file")) / 86400 ))
        local days_until_renewal=$((90 - cert_age_days))

        METRICS[cert_days_until_renewal]=$days_until_renewal

        [[ "$QUIET_MODE" == "false" ]] && echo "Certificate age: $cert_age_days days (renews at ~60 days)"

        if [ "$days_until_renewal" -lt 7 ]; then
            add_critical "C005" "Certificate expiring in $days_until_renewal days" "Check Traefik Let's Encrypt renewal"
        elif [ "$days_until_renewal" -lt 30 ]; then
            add_info "I004" "Certificate expires in $days_until_renewal days (auto-renews)" ""
        fi
    fi
}

check_monitoring_health() {
    log_section "Monitoring Stack"

    # Prometheus
    if curl -sf http://localhost:9090/-/healthy &>/dev/null; then
        add_info "I005" "Prometheus healthy" ""
        METRICS[prometheus_healthy]=1
    else
        add_warning "W006" "Prometheus health check failed" "Check Prometheus service"
        METRICS[prometheus_healthy]=0
    fi

    # Grafana
    if curl -sf http://localhost:3000/api/health &>/dev/null; then
        add_info "I006" "Grafana healthy" ""
        METRICS[grafana_healthy]=1
    else
        add_warning "W007" "Grafana health check failed" "Check Grafana service"
        METRICS[grafana_healthy]=0
    fi

    # Loki
    if curl -sf http://localhost:3100/ready &>/dev/null; then
        add_info "I008" "Loki healthy" ""
        METRICS[loki_healthy]=1
    else
        add_warning "W008" "Loki health check failed" "Check Loki service"
        METRICS[loki_healthy]=0
    fi
}

check_network() {
    log_section "Network Connectivity"

    # Internet connectivity
    if ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
        METRICS[internet_reachable]=1

        # Measure latency
        local latency
        latency=$(ping -c 3 -W 2 8.8.8.8 2>/dev/null | grep 'avg' | awk -F'/' '{print int($5)}' || echo "0")
        METRICS[internet_latency_ms]=$latency

        [[ "$QUIET_MODE" == "false" ]] && echo "Internet: Reachable (${latency}ms)"
    else
        add_critical "C006" "No internet connectivity" "Check network connection"
        METRICS[internet_reachable]=0
    fi
}

##############################################################################
# Trend Analysis
##############################################################################

analyze_trends() {
    if [ ! -f "$STATE_FILE" ]; then
        return # No previous state to compare
    fi

    # Compare disk usage trend
    local prev_disk
    prev_disk=$(jq -r '.metrics.disk_root_percent // 0' "$STATE_FILE" 2>/dev/null || echo "0")
    local current_disk=${METRICS[disk_root_percent]}

    if [ "$prev_disk" != "0" ] && [ "$current_disk" -gt "$prev_disk" ]; then
        local disk_growth=$((current_disk - prev_disk))
        if [ "$disk_growth" -gt 5 ]; then
            add_warning "W009" "Disk usage increased by ${disk_growth}% since last check" "Investigate disk growth"
        fi
    fi
}

##############################################################################
# Output Functions
##############################################################################

generate_recommendations() {
    local recommendations=()

    # Priority: Critical first, then warnings
    if [ ${#CRITICAL_ISSUES[@]} -gt 0 ]; then
        recommendations+=("[HIGH] Address critical issues immediately")
    fi

    if [ ${METRICS[disk_root_percent]:-0} -gt 70 ]; then
        recommendations+=("[MEDIUM] Review system SSD usage, consider cleanup")
    fi

    if [ ${METRICS[last_backup_days_ago]:--1} -gt 7 ]; then
        recommendations+=("[LOW] Verify external backup drive accessibility")
    fi

    if [ ${#recommendations[@]} -eq 0 ]; then
        recommendations+=("[INFO] System healthy - no actions required")
    fi

    # Print recommendations
    if [[ "$QUIET_MODE" == "false" ]]; then
        echo ""
        log_section "🎯 RECOMMENDED ACTIONS (Priority Order)"
        for rec in "${recommendations[@]}"; do
            echo "$rec"
        done
    fi
}

save_state() {
    mkdir -p "$(dirname "$STATE_FILE")"

    local json_metrics="{"
    for key in "${!METRICS[@]}"; do
        json_metrics+="\"$key\":${METRICS[$key]},"
    done
    json_metrics="${json_metrics%,}}"

    cat > "$STATE_FILE" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "health_score": $HEALTH_SCORE,
  "metrics": $json_metrics
}
EOF
}

output_json() {
    mkdir -p "$REPORT_DIR"

    local critical_json=$(printf '%s,' "${CRITICAL_ISSUES[@]}" | sed 's/,$//')
    local warnings_json=$(printf '%s,' "${WARNINGS[@]}" | sed 's/,$//')
    local info_json=$(printf '%s,' "${INFO_ITEMS[@]}" | sed 's/,$//')

    local json_metrics="{"
    for key in "${!METRICS[@]}"; do
        json_metrics+="\"$key\":${METRICS[$key]},"
    done
    json_metrics="${json_metrics%,}}"

    cat > "$JSON_OUTPUT" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "health_score": $HEALTH_SCORE,
  "critical_issues": [$critical_json],
  "warnings": [$warnings_json],
  "info": [$info_json],
  "metrics": $json_metrics
}
EOF

    echo "$JSON_OUTPUT"
}

print_summary() {
    [[ "$QUIET_MODE" == "true" ]] && return

    log_header "HOMELAB INTELLIGENCE REPORT"
    echo "Generated: $(date)"
    echo ""

    # Health score with color
    local score_color=$GREEN
    local score_status="✅ HEALTHY"

    if [ "$HEALTH_SCORE" -lt 50 ]; then
        score_color=$RED
        score_status="🚨 CRITICAL"
    elif [ "$HEALTH_SCORE" -lt 75 ]; then
        score_color=$YELLOW
        score_status="⚠️  DEGRADED"
    fi

    echo -e "OVERALL HEALTH SCORE: ${score_color}${HEALTH_SCORE}/100${NC}  $score_status"
    echo ""
    echo "CRITICAL ISSUES: ${#CRITICAL_ISSUES[@]}"
    echo "WARNINGS: ${#WARNINGS[@]}"
    echo "INFO: ${#INFO_ITEMS[@]}"

    # Print critical issues
    if [ ${#CRITICAL_ISSUES[@]} -gt 0 ]; then
        log_section "🚨 CRITICAL ISSUES"
        for issue in "${CRITICAL_ISSUES[@]}"; do
            local code=$(echo "$issue" | jq -r '.code')
            local message=$(echo "$issue" | jq -r '.message')
            local action=$(echo "$issue" | jq -r '.action')
            echo -e "${RED}[$code]${NC} $message"
            echo "  • Action: $action"
            echo ""
        done
    fi

    # Print warnings
    if [ ${#WARNINGS[@]} -gt 0 ]; then
        log_section "⚠️  WARNINGS"
        for warning in "${WARNINGS[@]}"; do
            local code=$(echo "$warning" | jq -r '.code')
            local message=$(echo "$warning" | jq -r '.message')
            local action=$(echo "$warning" | jq -r '.action')
            echo -e "${YELLOW}[$code]${NC} $message"
            echo "  • Action: $action"
            echo ""
        done
    fi

    # Print info items
    if [ ${#INFO_ITEMS[@]} -gt 0 ]; then
        log_section "ℹ️  INFORMATION"
        for info in "${INFO_ITEMS[@]}"; do
            local code=$(echo "$info" | jq -r '.code')
            local message=$(echo "$info" | jq -r '.message')
            echo -e "${CYAN}[$code]${NC} $message"
        done
    fi

    # Print key metrics
    log_section "📊 KEY METRICS"
    echo "Uptime: ${METRICS[uptime_days]} days"
    echo "CPU Usage (avg): ${METRICS[cpu_usage_percent]}%"
    echo "Memory Usage: ${METRICS[memory_used_mb]}MB / ${METRICS[memory_total_mb]}MB (${METRICS[memory_percent]}%)"
    echo "Swap Usage: ${METRICS[swap_used_mb]}MB"
    echo "Running Containers: ${METRICS[containers_running]}"
    echo "Critical Services: ${METRICS[services_running]}/${METRICS[services_total]}"
}

##############################################################################
# Main Execution
##############################################################################

main() {
    # Run all checks
    check_system_basics
    check_disk_usage
    check_services
    check_resource_usage
    check_backups
    check_certificates
    check_monitoring_health
    check_network

    # Analyze trends
    analyze_trends

    # Enforce health score bounds
    [ "$HEALTH_SCORE" -lt 0 ] && HEALTH_SCORE=0
    [ "$HEALTH_SCORE" -gt 100 ] && HEALTH_SCORE=100

    # Generate output
    print_summary
    generate_recommendations

    # Save state for trend analysis
    save_state

    # Output JSON if requested
    if [[ "$JSON_MODE" == "true" ]]; then
        output_json
    fi

    echo ""
    echo -e "${CYAN}────────────────────────────────────────────────────────────${NC}"
    echo "Full report saved to: $JSON_OUTPUT"
}

# Run main function
main "$@"
