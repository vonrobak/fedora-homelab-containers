#!/usr/bin/env bash
#
# Homelab Intelligence Script v2.0
# Simplified, focused system health analysis with actionable recommendations
#
# Usage: ./homelab-intel.sh [--quiet]
#

set -eo pipefail

# Configuration
REPORT_DIR="${HOME}/containers/docs/99-reports"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
JSON_OUTPUT="${REPORT_DIR}/intel-${TIMESTAMP}.json"

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Flags
QUIET_MODE=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --quiet) QUIET_MODE=true ;;
        --help|-h)
            echo "Usage: $0 [--quiet]"
            echo "  --quiet  : Minimal output"
            echo ""
            echo "Always generates JSON report in docs/99-reports/"
            exit 0
            ;;
    esac
done

# Health scoring
HEALTH_SCORE=100
declare -a CRITICAL_ISSUES
declare -a WARNINGS
declare -a INFO_ITEMS

# Metrics - simple array for JSON generation
declare -A METRICS

##############################################################################
# Helper Functions
##############################################################################

log() {
    [[ "$QUIET_MODE" == "true" ]] && return
    echo -e "$1"
}

log_section() {
    [[ "$QUIET_MODE" == "true" ]] && return
    echo ""
    echo -e "${BLUE}▶ $1${NC}"
}

add_critical() {
    CRITICAL_ISSUES+=("$1|$2|$3")
    HEALTH_SCORE=$((HEALTH_SCORE - 20))
}

add_warning() {
    WARNINGS+=("$1|$2|$3")
    HEALTH_SCORE=$((HEALTH_SCORE - 5))
}

add_info() {
    INFO_ITEMS+=("$1|$2")
}

##############################################################################
# System Checks
##############################################################################

check_system_basics() {
    log_section "System Basics"

    # Uptime
    local uptime_seconds=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo "0")
    local uptime_days=$((uptime_seconds / 86400))
    METRICS[uptime_days]=$uptime_days
    log "  Uptime: $uptime_days days"

    # SELinux
    local selinux=$(getenforce 2>/dev/null || echo "Unknown")
    METRICS[selinux]="\"$selinux\""

    if [[ "$selinux" != "Enforcing" ]]; then
        add_critical "C001" "SELinux not enforcing: $selinux" "Enable SELinux with 'sudo setenforce 1'"
    fi
    log "  SELinux: $selinux"

    # Kernel update check
    if command -v needs-restarting &>/dev/null; then
        if ! needs-restarting -r &>/dev/null; then
            add_warning "W001" "System reboot recommended (kernel update)" "Reboot when convenient"
        fi
    fi
}

check_disk_usage() {
    log_section "Disk Usage"

    # System SSD (128GB - critical resource)
    local root_usage=$(df / 2>/dev/null | awk 'NR==2 {print int($5)}' || echo "0")
    METRICS[disk_root_percent]=$root_usage
    log "  System SSD: ${root_usage}%"

    if [ "$root_usage" -ge 90 ]; then
        add_critical "C002" "System SSD critically full: ${root_usage}%" "Free space immediately - run: podman system prune -af"
    elif [ "$root_usage" -ge 80 ]; then
        add_critical "C003" "System SSD very full: ${root_usage}%" "Clean logs: journalctl --vacuum-time=7d"
    elif [ "$root_usage" -ge 70 ]; then
        add_warning "W002" "System SSD high usage: ${root_usage}%" "Review with: du -sh ~/containers/data/* | sort -h"
    fi

    # BTRFS pool
    if [ -d /mnt/btrfs-pool ]; then
        local btrfs_usage=$(df /mnt/btrfs-pool 2>/dev/null | awk 'NR==2 {print int($5)}' || echo "0")
        METRICS[disk_btrfs_percent]=$btrfs_usage
        log "  BTRFS Pool: ${btrfs_usage}%"
    else
        METRICS[disk_btrfs_percent]=0
    fi
}

check_services() {
    log_section "Critical Services"

    # Core services that MUST be running
    local -a critical=("traefik" "prometheus" "alertmanager" "grafana")
    local running=0
    local -a failed

    for svc in "${critical[@]}"; do
        if systemctl --user is-active "${svc}.service" &>/dev/null; then
            running=$((running + 1))
        else
            failed+=("$svc")
        fi
    done

    METRICS[services_running]=$running
    METRICS[services_total]=${#critical[@]}

    log "  Running: $running/${#critical[@]}"

    if [ ${#failed[@]} -gt 0 ]; then
        local failed_list="${failed[*]}"
        add_critical "C004" "Critical services down: ${failed_list}" "Start with: systemctl --user start ${failed[0]}.service"
    else
        add_info "I001" "All ${#critical[@]} critical services healthy"
    fi

    # Container count
    local containers=$(podman ps -q 2>/dev/null | wc -l || echo "0")
    METRICS[containers_running]=$containers
    log "  Containers: $containers running"
}

check_resources() {
    log_section "Resource Usage"

    # Memory
    local mem_total=$(free -m 2>/dev/null | awk 'NR==2 {print $2}' || echo "1")
    local mem_used=$(free -m 2>/dev/null | awk 'NR==2 {print $3}' || echo "0")
    local mem_percent=$((mem_used * 100 / mem_total))

    METRICS[memory_total_mb]=$mem_total
    METRICS[memory_used_mb]=$mem_used
    METRICS[memory_percent]=$mem_percent

    log "  Memory: ${mem_used}MB / ${mem_total}MB (${mem_percent}%)"

    if [ "$mem_percent" -ge 90 ]; then
        add_warning "W003" "Memory critically high: ${mem_percent}%" "Check: podman stats --no-stream"
    fi

    # Swap - only warn if significant (>20% of total RAM)
    local swap_used=$(free -m 2>/dev/null | awk 'NR==3 {print $3}' || echo "0")
    local swap_threshold=$((mem_total / 5))  # 20% of RAM
    METRICS[swap_used_mb]=$swap_used

    log "  Swap: ${swap_used}MB"

    if [ "$swap_used" -gt "$swap_threshold" ]; then
        add_warning "W004" "Swap usage high: ${swap_used}MB (>${swap_threshold}MB threshold)" "System may need more RAM or container limits"
    fi

    # CPU - simple load average
    local load1=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | xargs)
    METRICS[load_avg]="\"$load1\""
    log "  Load Average: $load1"
}

check_backups() {
    log_section "Backup Status"

    local days_old=999
    local backup_location="unknown"

    # Check 1: Local backup logs (BTRFS snapshots)
    local backup_log_dir="${HOME}/containers/data/backup-logs"
    if [ -d "$backup_log_dir" ]; then
        local latest_log=$(find "$backup_log_dir" -name "*.log" -type f 2>/dev/null | sort -r | head -1)
        if [ -n "$latest_log" ]; then
            local log_age=$(( ($(date +%s) - $(stat -c %Y "$latest_log" 2>/dev/null || echo "0")) / 86400 ))
            if [ "$log_age" -lt "$days_old" ]; then
                days_old=$log_age
                backup_location="local (backup logs)"
            fi
        fi
    fi

    # Check 2: External drive snapshots
    local external="/run/media/$(whoami)/WD-18TB/.snapshots"
    if [ -d "$external" ]; then
        local latest_external=$(find "$external" -maxdepth 2 -type d 2>/dev/null | sort -r | head -1)
        if [ -n "$latest_external" ]; then
            local ext_age=$(( ($(date +%s) - $(stat -c %Y "$latest_external" 2>/dev/null || echo "0")) / 86400 ))
            if [ "$ext_age" -lt "$days_old" ]; then
                days_old=$ext_age
                backup_location="external drive"
            fi
        fi
    fi

    # Check 3: Local BTRFS snapshots (home subvolume)
    local snapshot_dir="/home/.snapshots"
    if [ -d "$snapshot_dir" ]; then
        local latest_snap=$(find "$snapshot_dir" -maxdepth 1 -type d 2>/dev/null | sort -r | head -2 | tail -1)
        if [ -n "$latest_snap" ]; then
            local snap_age=$(( ($(date +%s) - $(stat -c %Y "$latest_snap" 2>/dev/null || echo "0")) / 86400 ))
            if [ "$snap_age" -lt "$days_old" ]; then
                days_old=$snap_age
                backup_location="local snapshot"
            fi
        fi
    fi

    METRICS[last_backup_days]=$days_old
    METRICS[backup_location]="\"$backup_location\""

    log "  Last backup: $days_old days ago ($backup_location)"

    if [ "$days_old" -eq 999 ]; then
        add_critical "C005" "No backups found" "Run: ./scripts/btrfs-snapshot-backup.sh"
    elif [ "$days_old" -gt 14 ]; then
        add_warning "W005" "Backup overdue: $days_old days old" "Check external drive and run backup"
    elif [ "$days_old" -le 1 ]; then
        add_info "I002" "Backups current ($backup_location)"
    fi
}

check_certificates() {
    log_section "SSL Certificates"

    # Explicit path - user confirmed location
    local acme_file="/home/patriark/containers/config/traefik/letsencrypt/acme.json"

    if [ -f "$acme_file" ]; then
        local cert_age=$(( ($(date +%s) - $(stat -c %Y "$acme_file" 2>/dev/null || echo "0")) / 86400 ))
        local days_remaining=$((90 - cert_age))

        METRICS[cert_age_days]=$cert_age
        METRICS[cert_days_remaining]=$days_remaining

        log "  Certificate age: $cert_age days (auto-renews ~60 days)"

        if [ "$days_remaining" -lt 7 ]; then
            add_critical "C006" "Certificate expires in $days_remaining days" "Check Traefik logs for renewal errors"
        elif [ "$days_remaining" -lt 30 ]; then
            add_info "I003" "Certificate expires in $days_remaining days (will auto-renew)"
        fi
    else
        add_warning "W006" "Certificate file not found" "Check Traefik Let's Encrypt configuration"
        METRICS[cert_age_days]=0
        METRICS[cert_days_remaining]=0
    fi
}

check_monitoring() {
    log_section "Monitoring Stack"

    # Check via podman exec (more reliable than localhost for rootless containers)

    # Prometheus
    if podman exec prometheus curl -sf http://localhost:9090/-/healthy &>/dev/null; then
        METRICS[prometheus_healthy]=1
        add_info "I004" "Prometheus responding"
    else
        METRICS[prometheus_healthy]=0
        # Only warn if service is running (network issue vs service down)
        if systemctl --user is-active prometheus.service &>/dev/null; then
            add_warning "W007" "Prometheus health check failed (service running)" "May be network/startup delay"
        fi
    fi

    # Grafana
    if podman exec grafana curl -sf http://localhost:3000/api/health &>/dev/null; then
        METRICS[grafana_healthy]=1
        add_info "I005" "Grafana responding"
    else
        METRICS[grafana_healthy]=0
        if systemctl --user is-active grafana.service &>/dev/null; then
            add_warning "W008" "Grafana health check failed (service running)" "May be network/startup delay"
        fi
    fi

    # Loki
    if podman exec loki curl -sf http://localhost:3100/ready &>/dev/null; then
        METRICS[loki_healthy]=1
        add_info "I006" "Loki responding"
    else
        METRICS[loki_healthy]=0
        if systemctl --user is-active loki.service &>/dev/null; then
            add_warning "W009" "Loki health check failed (service running)" "May be network/startup delay"
        fi
    fi
}

check_network() {
    log_section "Network Connectivity"

    if ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
        METRICS[internet]=1
        add_info "I007" "Internet connectivity OK"
    else
        METRICS[internet]=0
        add_critical "C007" "No internet connectivity" "Check network connection"
    fi
}

##############################################################################
# Output Functions
##############################################################################

print_summary() {
    [[ "$QUIET_MODE" == "true" ]] && return

    echo ""
    log "${CYAN}═══════════════════════════════════════════════════════${NC}"
    log "${CYAN}        HOMELAB INTELLIGENCE REPORT${NC}"
    log "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo ""

    # Health score
    local score_color=$GREEN
    local score_icon="✅"

    if [ "$HEALTH_SCORE" -lt 50 ]; then
        score_color=$RED
        score_icon="🚨"
    elif [ "$HEALTH_SCORE" -lt 75 ]; then
        score_color=$YELLOW
        score_icon="⚠️ "
    fi

    echo -e "${score_color}HEALTH SCORE: ${HEALTH_SCORE}/100${NC} $score_icon"
    echo ""
    echo "Critical Issues: ${#CRITICAL_ISSUES[@]}"
    echo "Warnings: ${#WARNINGS[@]}"
    echo "Info: ${#INFO_ITEMS[@]}"

    # Critical issues
    if [ ${#CRITICAL_ISSUES[@]} -gt 0 ]; then
        echo ""
        log "${RED}🚨 CRITICAL ISSUES:${NC}"
        for item in "${CRITICAL_ISSUES[@]}"; do
            IFS='|' read -r code msg action <<< "$item"
            echo -e "  ${RED}[$code]${NC} $msg"
            echo "      → $action"
        done
    fi

    # Warnings
    if [ ${#WARNINGS[@]} -gt 0 ]; then
        echo ""
        log "${YELLOW}⚠️  WARNINGS:${NC}"
        for item in "${WARNINGS[@]}"; do
            IFS='|' read -r code msg action <<< "$item"
            echo -e "  ${YELLOW}[$code]${NC} $msg"
            echo "      → $action"
        done
    fi

    # Info (only if not too many)
    if [ ${#INFO_ITEMS[@]} -gt 0 ] && [ ${#INFO_ITEMS[@]} -lt 8 ]; then
        echo ""
        log "${GREEN}✓ HEALTHY:${NC}"
        for item in "${INFO_ITEMS[@]}"; do
            IFS='|' read -r code msg <<< "$item"
            echo "  [$code] $msg"
        done
    fi
}

generate_json() {
    mkdir -p "$REPORT_DIR" 2>/dev/null || true

    # Build JSON manually (no jq dependency)
    local json="{"
    json+="\"timestamp\":\"$(date -Iseconds)\","
    json+="\"health_score\":$HEALTH_SCORE,"

    # Critical issues
    json+="\"critical\":["
    local first=true
    for item in "${CRITICAL_ISSUES[@]}"; do
        IFS='|' read -r code msg action <<< "$item"
        [ "$first" = false ] && json+=","
        json+="{\"code\":\"$code\",\"message\":\"$msg\",\"action\":\"$action\"}"
        first=false
    done
    json+="],"

    # Warnings
    json+="\"warnings\":["
    first=true
    for item in "${WARNINGS[@]}"; do
        IFS='|' read -r code msg action <<< "$item"
        [ "$first" = false ] && json+=","
        json+="{\"code\":\"$code\",\"message\":\"$msg\",\"action\":\"$action\"}"
        first=false
    done
    json+="],"

    # Info
    json+="\"info\":["
    first=true
    for item in "${INFO_ITEMS[@]}"; do
        IFS='|' read -r code msg <<< "$item"
        [ "$first" = false ] && json+=","
        json+="{\"code\":\"$code\",\"message\":\"$msg\"}"
        first=false
    done
    json+="],"

    # Metrics
    json+="\"metrics\":{"
    first=true
    for key in "${!METRICS[@]}"; do
        [ "$first" = false ] && json+=","
        json+="\"$key\":${METRICS[$key]}"
        first=false
    done
    json+="}}"

    echo "$json" > "$JSON_OUTPUT"
    log "${GREEN}✓${NC} JSON report: $JSON_OUTPUT"
}

##############################################################################
# Main
##############################################################################

main() {
    # Run all checks
    check_system_basics
    check_disk_usage
    check_services
    check_resources
    check_backups
    check_certificates
    check_monitoring
    check_network

    # Enforce bounds
    [ "$HEALTH_SCORE" -lt 0 ] && HEALTH_SCORE=0
    [ "$HEALTH_SCORE" -gt 100 ] && HEALTH_SCORE=100

    # Output
    print_summary
    echo ""
    generate_json

    # Exit code based on health
    if [ "$HEALTH_SCORE" -lt 50 ]; then
        exit 2  # Critical
    elif [ "$HEALTH_SCORE" -lt 75 ]; then
        exit 1  # Warning
    else
        exit 0  # Healthy
    fi
}

main "$@"
