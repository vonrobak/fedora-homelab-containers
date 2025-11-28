#!/bin/bash
# Quick SLO Status Check
# Shows current SLI values and SLO compliance

echo "=== SLO Status Report ==="
echo ""

# Function to query Prometheus
query_prom() {
    podman exec prometheus wget -q -O- "http://localhost:9090/api/v1/query?query=$1" 2>&1 | \
        jq -r '.data.result[0].value[1]' 2>/dev/null || echo "N/A"
}

# Jellyfin
echo "Jellyfin:"
avail=$(query_prom 'sli:jellyfin:availability:ratio')
if [ "$avail" != "N/A" ]; then
    avail_pct=$(echo "$avail * 100" | bc -l | cut -c1-5)
    echo "  Availability: ${avail_pct}%"
else
    echo "  Availability: Calculating..."
fi

# Immich
echo ""
echo "Immich:"
avail=$(query_prom 'sli:immich:availability:ratio')
if [ "$avail" != "N/A" ]; then
    avail_pct=$(echo "$avail * 100" | bc -l | cut -c1-5)
    echo "  Availability: ${avail_pct}%"
else
    echo "  Availability: Calculating..."
fi

# Authelia
echo ""
echo "Authelia:"
avail=$(query_prom 'sli:authelia:availability:ratio')
if [ "$avail" != "N/A" ]; then
    avail_pct=$(echo "$avail * 100" | bc -l | cut -c1-5)
    echo "  Availability: ${avail_pct}%"
else
    echo "  Availability: Calculating..."
fi

# Traefik
echo ""
echo "Traefik Gateway:"
avail=$(query_prom 'sli:traefik:availability:ratio')
if [ "$avail" != "N/A" ]; then
    avail_pct=$(echo "$avail * 100" | bc -l | cut -c1-5)
    echo "  Availability: ${avail_pct}%"
else
    echo "  Availability: Calculating..."
fi

echo ""
echo "Note: Error budgets require 30 days of data to calculate."
