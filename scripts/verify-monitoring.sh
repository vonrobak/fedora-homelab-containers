#!/usr/bin/env bash
# Verify monitoring integration for a service
# Checks: Prometheus targets, metrics scraping, Grafana dashboards, Loki logs
# Part of Phase 2: Verification Infrastructure

set -euo pipefail

# Usage check
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <service-name>"
    echo "Example: $0 jellyfin"
    exit 1
fi

SERVICE="$1"
EXIT_CODE=0

echo "=================================="
echo "Monitoring Verification: $SERVICE"
echo "=================================="
echo ""

# 1. Prometheus target check
echo -n "Prometheus target: "
if TARGET_HEALTH=$(curl -sf http://localhost:9090/api/v1/targets 2>/dev/null | jq -r '.data.activeTargets[] | select(.labels.job == "'$SERVICE'") | .health' 2>/dev/null | head -1); then
    if [[ "$TARGET_HEALTH" == "up" ]]; then
        echo "✓ Target UP"

        # Get scrape details
        SCRAPE_INTERVAL=$(curl -sf http://localhost:9090/api/v1/targets 2>/dev/null | jq -r '.data.activeTargets[] | select(.labels.job == "'$SERVICE'") | .scrapeInterval' 2>/dev/null | head -1)
        LAST_SCRAPE=$(curl -sf http://localhost:9090/api/v1/targets 2>/dev/null | jq -r '.data.activeTargets[] | select(.labels.job == "'$SERVICE'") | .lastScrape' 2>/dev/null | head -1)

        if [[ -n "$SCRAPE_INTERVAL" ]]; then
            echo "  Scrape interval: $SCRAPE_INTERVAL"
        fi
        if [[ -n "$LAST_SCRAPE" ]]; then
            echo "  Last scrape: $LAST_SCRAPE"
        fi
    elif [[ "$TARGET_HEALTH" == "down" ]]; then
        echo "✗ Target DOWN"
        EXIT_CODE=1
    else
        echo "⚠ Unknown state: $TARGET_HEALTH"
    fi
else
    echo "⚠ No target found (service may not expose metrics)"
    # Not marking as failure - some services don't expose metrics
fi

# 2. Metrics scraping check
echo -n "Metrics scraping: "
if METRIC_COUNT=$(curl -sf "http://localhost:9090/api/v1/query?query=up{job=\"$SERVICE\"}" 2>/dev/null | jq -r '.data.result | length' 2>/dev/null); then
    if [[ $METRIC_COUNT -gt 0 ]]; then
        echo "✓ Scraping ($METRIC_COUNT series)"

        # Check metric value (up=1 means healthy)
        METRIC_VALUE=$(curl -sf "http://localhost:9090/api/v1/query?query=up{job=\"$SERVICE\"}" 2>/dev/null | jq -r '.data.result[0].value[1]' 2>/dev/null)
        if [[ "$METRIC_VALUE" == "1" ]]; then
            echo "  Metric 'up' = 1 (healthy)"
        elif [[ "$METRIC_VALUE" == "0" ]]; then
            echo "  ✗ Metric 'up' = 0 (unhealthy)"
            EXIT_CODE=1
        fi
    else
        echo "⚠ No metrics scraped"
    fi
else
    echo "⚠ Could not query metrics"
fi

# 3. Grafana dashboard check
echo -n "Grafana dashboard: "
DASHBOARD_FOUND=0

# Check various possible dashboard file names
for dashboard_file in \
    ~/containers/config/grafana/provisioning/dashboards/${SERVICE}.json \
    ~/containers/config/grafana/provisioning/dashboards/${SERVICE}-dashboard.json \
    ~/containers/config/grafana/provisioning/dashboards/*${SERVICE}*.json; do

    if [[ -f "$dashboard_file" ]]; then
        echo "✓ Dashboard exists: $(basename "$dashboard_file")"
        DASHBOARD_FOUND=1
        break
    fi
done

if [[ $DASHBOARD_FOUND -eq 0 ]]; then
    echo "⚠ No dashboard found (consider creating one)"
fi

# 4. Loki log ingestion check
echo -n "Loki log ingestion: "
if LOG_COUNT=$(curl -sf "http://localhost:3100/loki/api/v1/query?query={job=\"systemd-journal\",unit=\"${SERVICE}.service\"}" 2>/dev/null | jq -r '.data.result | length' 2>/dev/null); then
    if [[ $LOG_COUNT -gt 0 ]]; then
        echo "✓ Logs being ingested ($LOG_COUNT streams)"
    else
        echo "⚠ No logs found (check Promtail config)"
    fi
else
    echo "⚠ Could not query Loki"
fi

# 5. Service-specific metrics check (if service exposes custom metrics)
echo -n "Service-specific metrics: "
if SERVICE_METRICS=$(curl -sf "http://localhost:9090/api/v1/label/__name__/values" 2>/dev/null | jq -r '.data[]' 2>/dev/null | grep -i "$SERVICE" | head -5); then
    if [[ -n "$SERVICE_METRICS" ]]; then
        echo "✓ Custom metrics found"
        echo "$SERVICE_METRICS" | while read -r metric; do
            echo "  - $metric"
        done
    else
        echo "⚠ No service-specific metrics (may use generic metrics only)"
    fi
else
    echo "⚠ Could not enumerate metrics"
fi

echo ""
echo "=================================="
if [[ $EXIT_CODE -eq 0 ]]; then
    echo "Monitoring verification: PASSED ✓"
else
    echo "Monitoring verification: FAILED ✗"
fi
echo "=================================="

exit $EXIT_CODE
