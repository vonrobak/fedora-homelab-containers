#!/bin/bash
# Memory Leak Investigation Script
# Created: 2025-11-26
# Purpose: Identify sources of swap usage and potential memory leaks

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${1}"; }
log_section() { echo ""; log "${BLUE}▶ ${1}${NC}"; }

log "${CYAN}═══════════════════════════════════════════════════════${NC}"
log "${CYAN}   MEMORY LEAK INVESTIGATION${NC}"
log "${CYAN}   $(date '+%Y-%m-%d %H:%M:%S')${NC}"
log "${CYAN}═══════════════════════════════════════════════════════${NC}"

# ============================================================================
# 1. IDENTIFY PROCESSES USING SWAP
# ============================================================================
log_section "Processes Using Swap"

log "Top 10 processes by swap usage:"
echo ""

# Check all running processes for swap usage
for pid in $(ps aux | awk 'NR>1 {print $2}'); do
    if [ -f "/proc/$pid/status" ]; then
        swap=$(grep VmSwap /proc/$pid/status 2>/dev/null | awk '{print $2}')
        if [ -n "$swap" ] && [ "$swap" -gt 0 ]; then
            name=$(ps -p $pid -o comm= 2>/dev/null || echo "unknown")
            echo "$swap $pid $name"
        fi
    fi
done | sort -rn | head -10 | while read swap pid name; do
    swap_mb=$((swap / 1024))
    log "  ${YELLOW}${swap_mb}MB${NC} - PID $pid ($name)"
done

# ============================================================================
# 2. CONTAINER MEMORY USAGE (CURRENT)
# ============================================================================
log_section "Container Memory Usage (Current)"

log "Containers sorted by memory usage:"
podman stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}" | \
    head -1
podman stats --no-stream --format "{{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}" | \
    sort -k2 -h -r | \
    head -15 | \
    awk '{printf "  %-25s %15s %10s\n", $1, $2, $3}'

# ============================================================================
# 3. CONTAINERS WITHOUT MEMORY LIMITS (DANGEROUS!)
# ============================================================================
log_section "Containers Without Memory Limits"

log "Checking for unbounded containers..."
found_unlimited=false

for container in $(podman ps --format "{{.Names}}"); do
    limit=$(podman inspect "$container" --format '{{.HostConfig.Memory}}' 2>/dev/null || echo "0")
    if [ "$limit" = "0" ]; then
        found_unlimited=true
        log "  ${RED}⚠ $container${NC} - NO MEMORY LIMIT (can grow unbounded!)"
    fi
done

if [ "$found_unlimited" = false ]; then
    log "  ${GREEN}✓ All containers have memory limits${NC}"
fi

# ============================================================================
# 4. MONITORING STACK ANALYSIS
# ============================================================================
log_section "Monitoring Stack Deep Dive"

# Prometheus
if systemctl --user is-active prometheus.service &>/dev/null; then
    log ""
    log "${YELLOW}Prometheus:${NC}"

    # Memory usage
    prom_mem=$(podman stats prometheus --no-stream --format "{{.MemUsage}}" 2>/dev/null | awk '{print $1}')
    log "  Memory: $prom_mem"

    # Check retention and storage
    prom_retention=$(podman inspect prometheus --format '{{range .Args}}{{if contains . "retention"}}{{.}} {{end}}{{end}}' 2>/dev/null)
    log "  Retention: $prom_retention"

    # Check time series cardinality (indicator of memory usage)
    cardinality=$(curl -s http://localhost:9090/api/v1/status/tsdb 2>/dev/null | \
        jq -r '.data.seriesCountByMetricName | length' 2>/dev/null || echo "unknown")
    log "  Metric types: $cardinality"

    # Check head stats
    head_chunks=$(curl -s http://localhost:9090/api/v1/status/tsdb 2>/dev/null | \
        jq -r '.data.headStats.numSeries' 2>/dev/null || echo "unknown")
    log "  Active time series: $head_chunks"

    # Storage size
    prom_storage=$(du -sh ~/containers/data/prometheus 2>/dev/null | awk '{print $1}' || echo "unknown")
    log "  Storage size: $prom_storage"
fi

# Grafana
if systemctl --user is-active grafana.service &>/dev/null; then
    log ""
    log "${YELLOW}Grafana:${NC}"
    grafana_mem=$(podman stats grafana --no-stream --format "{{.MemUsage}}" 2>/dev/null | awk '{print $1}')
    log "  Memory: $grafana_mem"
fi

# Loki
if systemctl --user is-active loki.service &>/dev/null; then
    log ""
    log "${YELLOW}Loki:${NC}"
    loki_mem=$(podman stats loki --no-stream --format "{{.MemUsage}}" 2>/dev/null | awk '{print $1}')
    log "  Memory: $loki_mem"

    loki_storage=$(du -sh ~/containers/data/loki 2>/dev/null | awk '{print $1}' || echo "unknown")
    log "  Storage size: $loki_storage"
fi

# ============================================================================
# 5. MEMORY GROWTH TRENDS (Last 24h)
# ============================================================================
log_section "Memory Growth Trends (Last 24 Hours)"

log "Querying Prometheus for memory growth..."

# Check monitoring stack containers for growth
for container in prometheus grafana loki promtail; do
    if systemctl --user is-active "${container}.service" &>/dev/null; then
        # Get memory 24h ago vs now
        query="container_memory_working_set_bytes{name=\"$container\"}"

        # Current
        current=$(curl -s "http://localhost:9090/api/v1/query?query=${query}" 2>/dev/null | \
            jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")

        # 24h ago
        time_24h_ago=$(($(date +%s) - 86400))
        past=$(curl -s "http://localhost:9090/api/v1/query?query=${query}&time=${time_24h_ago}" 2>/dev/null | \
            jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")

        if [ "$current" != "0" ] && [ "$past" != "0" ]; then
            current_mb=$((current / 1024 / 1024))
            past_mb=$((past / 1024 / 1024))
            delta=$((current_mb - past_mb))

            if [ $delta -gt 50 ]; then
                log "  ${RED}$container: ${past_mb}MB → ${current_mb}MB (+${delta}MB) ⚠️${NC}"
            elif [ $delta -gt 0 ]; then
                log "  ${YELLOW}$container: ${past_mb}MB → ${current_mb}MB (+${delta}MB)${NC}"
            else
                log "  ${GREEN}$container: ${current_mb}MB (stable)${NC}"
            fi
        fi
    fi
done

# ============================================================================
# 6. CHECK FOR KNOWN ISSUES
# ============================================================================
log_section "Checking for Known Memory Leak Patterns"

# Prometheus: High cardinality metrics
if [ "$cardinality" != "unknown" ] && [ "$cardinality" -gt 500 ]; then
    log "  ${YELLOW}⚠ Prometheus has $cardinality metric types (high cardinality)${NC}"
    log "    High cardinality = more memory usage"
    log "    Consider: Reduce scrape interval or number of exporters"
fi

# Check for log explosion (Loki)
if [ -d ~/containers/data/loki ]; then
    loki_size_gb=$(du -sm ~/containers/data/loki 2>/dev/null | awk '{print $1}')
    if [ "$loki_size_gb" -gt 1000 ]; then
        log "  ${YELLOW}⚠ Loki storage is ${loki_size_gb}MB (very large)${NC}"
        log "    Large logs = more memory for indexing"
        log "    Consider: Reduce retention or increase compaction"
    fi
fi

# ============================================================================
# 7. RECOMMENDATIONS
# ============================================================================
log_section "Recommendations"

log "Based on the analysis:"
log ""
log "${GREEN}Immediate actions:${NC}"
log "  1. Review containers without memory limits (if any)"
log "  2. Check for containers with >100MB memory growth in 24h"
log "  3. Consider reducing Prometheus retention if >1TB"
log ""
log "${YELLOW}If memory leak confirmed:${NC}"
log "  • Restart the leaking container: systemctl --user restart <service>"
log "  • Add/lower memory limit in quadlet file"
log "  • Check container logs for errors: journalctl --user -u <service> -n 100"
log ""
log "${BLUE}Monitoring:${NC}"
log "  • Run this script daily to track trends"
log "  • Watch for consistent upward growth (sign of leak)"
log "  • Stable containers = normal behavior"

log ""
log "${CYAN}═══════════════════════════════════════════════════════${NC}"
log "${GREEN}Investigation complete!${NC}"
log "${CYAN}═══════════════════════════════════════════════════════${NC}"
