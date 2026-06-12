#!/bin/bash
# generate-predictions-cache.sh
# Aggregate predictions from all sources and cache results
#
# Purpose:
#   - Run disk and memory predictions for all monitored resources
#   - Aggregate results into single predictions.json file
#   - Include timestamps, severity levels, and recommendations
#   - Provide easy integration with monitoring/alerting systems
#
# Usage:
#   ./generate-predictions-cache.sh [--output <file>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREDICT_EXHAUSTION="${SCRIPT_DIR}/predict-resource-exhaustion.sh"

# Default output location
OUTPUT_FILE="${OUTPUT_FILE:-$HOME/containers/data/predictions.json}"
LOOKBACK="${LOOKBACK:-7d}"

# Services to monitor
MONITORED_SERVICES=(
    "jellyfin"
    "prometheus"
    "grafana"
    "loki"
    "traefik"
    "authelia"
)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    local level=$1
    shift
    local message="$*"

    # Always output to stderr
    case $level in
        ERROR)   echo -e "${RED}[ERROR]${NC} $message" >&2 ;;
        SUCCESS) echo -e "${GREEN}[SUCCESS]${NC} $message" >&2 ;;
        WARNING) echo -e "${YELLOW}[WARNING]${NC} $message" >&2 ;;
        INFO)    echo -e "${BLUE}[INFO]${NC} $message" >&2 ;;
    esac
}

usage() {
    cat <<EOF
Usage: $0 [options]

Generate predictions cache by analyzing all monitored resources.

Options:
  --output <file>    Output file path (default: ~/containers/data/predictions.json)
  --lookback <dur>   Historical window (default: 7d)
  --help             Show this help

Examples:
  # Generate predictions cache
  $0

  # Custom output location
  $0 --output /tmp/predictions.json

  # Longer lookback window
  $0 --lookback 14d
EOF
}

# Collect disk prediction
collect_disk_prediction() {
    log INFO "Collecting disk predictions..."

    "$PREDICT_EXHAUSTION" --type disk --output json --lookback "$LOOKBACK" 2>/dev/null || echo '{}'
}

# Collect memory predictions for all services
collect_memory_predictions() {
    log INFO "Collecting memory predictions for ${#MONITORED_SERVICES[@]} services..."

    local predictions="[]"

    for service in "${MONITORED_SERVICES[@]}"; do
        local prediction=$("$PREDICT_EXHAUSTION" --type memory --service "$service" --output json --lookback "$LOOKBACK" 2>/dev/null || echo '{}')

        # Check if prediction is not empty
        if [[ "$prediction" != "{}" ]]; then
            # Add to array
            if [[ "$predictions" == "[]" ]]; then
                predictions="[$prediction]"
            else
                # Remove trailing ] and add new item
                predictions="${predictions%]}, $prediction]"
            fi
        fi
    done

    echo "$predictions"
}

# Calculate overall severity (highest severity wins)
calculate_overall_severity() {
    local disk_severity=$1
    local memory_severities=$2

    # Priority: critical > warning > info
    if [[ "$disk_severity" == "critical" ]] || echo "$memory_severities" | grep -q '"severity": "critical"'; then
        echo "critical"
    elif [[ "$disk_severity" == "warning" ]] || echo "$memory_severities" | grep -q '"severity": "warning"'; then
        echo "warning"
    else
        echo "info"
    fi
}

# Count issues by severity
count_issues() {
    local predictions=$1

    python3 <<EOF
import json

data = json.loads('''$predictions''')

disk = data.get('disk', {})
memory = data.get('memory', [])

critical = 0
warning = 0

if disk.get('severity') == 'critical':
    critical += 1
elif disk.get('severity') == 'warning':
    warning += 1

for m in memory:
    if m.get('severity') == 'critical':
        critical += 1
    elif m.get('severity') == 'warning':
        warning += 1

print(f'{critical} {warning}')
EOF
}

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --lookback)
                LOOKBACK="$2"
                shift 2
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    log INFO "Generating predictions cache..."
    log INFO "Lookback window: $LOOKBACK"
    log INFO "Output: $OUTPUT_FILE"

    # Collect predictions
    local disk_prediction=$(collect_disk_prediction)
    local memory_predictions=$(collect_memory_predictions)

    # Calculate overall severity
    local overall_severity=$(python3 -c "
import json

disk = json.loads('''$disk_prediction''')
memory = json.loads('''$memory_predictions''')

# Priority: critical > warning > info
severities = []
if disk:
    severities.append(disk.get('severity', 'info'))
for m in memory:
    severities.append(m.get('severity', 'info'))

if 'critical' in severities:
    print('critical')
elif 'warning' in severities:
    print('warning')
else:
    print('info')
")

    # Count issues
    local issue_counts=$(python3 -c "
import json

disk = json.loads('''$disk_prediction''')
memory = json.loads('''$memory_predictions''')

critical = 0
warning = 0
info = 0

if disk:
    sev = disk.get('severity', 'info')
    if sev == 'critical':
        critical += 1
    elif sev == 'warning':
        warning += 1
    else:
        info += 1

for m in memory:
    sev = m.get('severity', 'info')
    if sev == 'critical':
        critical += 1
    elif sev == 'warning':
        warning += 1
    else:
        info += 1

print(f'{critical} {warning} {info}')
")

    local critical_count=$(echo "$issue_counts" | awk '{print $1}')
    local warning_count=$(echo "$issue_counts" | awk '{print $2}')
    local info_count=$(echo "$issue_counts" | awk '{print $3}')

    # Create final JSON structure
    python3 <<EOF > "$OUTPUT_FILE"
import json
from datetime import datetime

disk = json.loads('''$disk_prediction''')
memory = json.loads('''$memory_predictions''')

output = {
    "generated_at": datetime.now().isoformat(),
    "lookback_window": "$LOOKBACK",
    "overall_severity": "$overall_severity",
    "issue_summary": {
        "critical": $critical_count,
        "warning": $warning_count,
        "info": $info_count
    },
    "predictions": {
        "disk": disk if disk else None,
        "memory": memory
    }
}

print(json.dumps(output, indent=2))
EOF

    log SUCCESS "Predictions cache generated: $OUTPUT_FILE"
    log INFO "Overall severity: $overall_severity"
    log INFO "Issues: $critical_count critical, $warning_count warning, $info_count info"

    # Show critical/warning issues
    if [[ $critical_count -gt 0 ]] || [[ $warning_count -gt 0 ]]; then
        log WARNING "Action required - check predictions for details"
    fi
}

main "$@"
