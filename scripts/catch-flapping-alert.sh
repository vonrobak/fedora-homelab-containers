#!/bin/bash
# Script to identify the flapping alert
# Monitors alertmanager and logs what alert fires

echo "=== Flapping Alert Hunter ==="
echo "Monitoring for alerts firing at XX:XX:04 timestamps..."
echo "Started: $(date)"
echo ""

LAST_COUNT=0
while true; do
    # Get current alerts from Alertmanager
    CURRENT_ALERTS=$(curl -s http://localhost:9093/api/v2/alerts 2>/dev/null)
    CURRENT_COUNT=$(echo "$CURRENT_ALERTS" | jq '. | length' 2>/dev/null || echo "0")

    # Check if alert count changed
    if [ "$CURRENT_COUNT" != "$LAST_COUNT" ]; then
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
        echo "[$TIMESTAMP] Alert count changed: $LAST_COUNT → $CURRENT_COUNT"

        # Show what alerts are active
        if [ "$CURRENT_COUNT" -gt 0 ]; then
            echo "$CURRENT_ALERTS" | jq -r '.[] | "  - \(.labels.alertname) [\(.labels.severity)] state:\(.status.state) since:\(.startsAt)"'
        else
            echo "  (All alerts resolved)"
        fi
        echo ""

        LAST_COUNT=$CURRENT_COUNT
    fi

    sleep 5
done
