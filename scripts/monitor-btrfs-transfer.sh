#!/bin/bash
################################################################################
# BTRFS Transfer Progress Monitor
# Created: 2025-12-06
# Purpose: Monitor progress of ongoing btrfs send/receive operations
#
# Usage:
#   ./monitor-btrfs-transfer.sh [send_pid] [receive_pid] [source_size_tib]
#
# Example:
#   ./monitor-btrfs-transfer.sh 1731050 1731051 2.1
#
# If no arguments provided, attempts to auto-detect running btrfs send/receive
################################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Auto-detect if no args provided
if [ $# -eq 0 ]; then
    echo -e "${BLUE}Auto-detecting btrfs send/receive processes...${NC}"
    SEND_PID=$(pgrep -f "btrfs send" | head -1 || echo "")
    RECV_PID=$(pgrep -f "btrfs receive" | head -1 || echo "")

    if [ -z "$SEND_PID" ] || [ -z "$RECV_PID" ]; then
        echo -e "${RED}ERROR: Could not auto-detect btrfs send/receive processes${NC}"
        echo "Please provide PIDs manually:"
        echo "  $0 <send_pid> <receive_pid> <source_size_tib>"
        exit 1
    fi

    echo -e "${GREEN}Found processes: send=$SEND_PID, receive=$RECV_PID${NC}"
    echo -n "Enter source size in TiB (e.g., 2.1): "
    read SOURCE_SIZE_TIB
else
    SEND_PID=$1
    RECV_PID=$2
    SOURCE_SIZE_TIB=${3:-0}
fi

# Function to get I/O stats
get_io_stats() {
    local pid=$1
    if [ ! -f "/proc/$pid/io" ]; then
        echo "0 0"
        return
    fi

    local read_bytes=$(sudo cat "/proc/$pid/io" 2>/dev/null | grep '^read_bytes:' | awk '{print $2}' || echo "0")
    local write_bytes=$(sudo cat "/proc/$pid/io" 2>/dev/null | grep '^write_bytes:' | awk '{print $2}' || echo "0")
    echo "$read_bytes $write_bytes"
}

# Function to format bytes
format_bytes() {
    local bytes=$1
    if [ $bytes -ge $((1024**4)) ]; then
        echo "$(awk "BEGIN {printf \"%.2f TiB\", $bytes/(1024^4)}")"
    elif [ $bytes -ge $((1024**3)) ]; then
        echo "$(awk "BEGIN {printf \"%.2f GiB\", $bytes/(1024^3)}")"
    elif [ $bytes -ge $((1024**2)) ]; then
        echo "$(awk "BEGIN {printf \"%.2f MiB\", $bytes/(1024^2)}")"
    else
        echo "$bytes bytes"
    fi
}

# Function to get process info
get_process_info() {
    local pid=$1
    if ! ps -p $pid > /dev/null 2>&1; then
        echo "NOT_RUNNING"
        return
    fi

    ps -p $pid -o pid,stat,%cpu,%mem,etime,cmd --no-headers
}

# Check if processes are still running
echo -e "\n${BLUE}=== BTRFS Transfer Monitor ===${NC}\n"

SEND_INFO=$(get_process_info $SEND_PID)
RECV_INFO=$(get_process_info $RECV_PID)

if [ "$SEND_INFO" = "NOT_RUNNING" ]; then
    echo -e "${RED}ERROR: Send process (PID $SEND_PID) is not running${NC}"
    exit 1
fi

if [ "$RECV_INFO" = "NOT_RUNNING" ]; then
    echo -e "${RED}ERROR: Receive process (PID $RECV_PID) is not running${NC}"
    exit 1
fi

echo -e "${GREEN}Process Status:${NC}"
echo "  Send:    $SEND_INFO"
echo "  Receive: $RECV_INFO"

# Get I/O statistics
read SEND_READ SEND_WRITE <<< $(get_io_stats $SEND_PID)
read RECV_READ RECV_WRITE <<< $(get_io_stats $RECV_PID)

# Get elapsed time from process
ELAPSED_SECONDS=$(ps -p $SEND_PID -o etimes= | tr -d ' ')
ELAPSED_HOURS=$(awk "BEGIN {printf \"%.1f\", $ELAPSED_SECONDS/3600}")

echo -e "\n${GREEN}Transfer Statistics:${NC}"
echo "  Elapsed time:     ${ELAPSED_HOURS}h (${ELAPSED_SECONDS}s)"
echo "  Data read:        $(format_bytes $SEND_READ)"
echo "  Data written:     $(format_bytes $RECV_WRITE)"

# Calculate transfer rate
TRANSFER_RATE_MBS=$(awk "BEGIN {printf \"%.2f\", ($SEND_READ/1024/1024)/$ELAPSED_SECONDS}")
echo "  Average rate:     ${TRANSFER_RATE_MBS} MB/s"

# Calculate completion if source size provided
if [ $(awk "BEGIN {print ($SOURCE_SIZE_TIB > 0)}") -eq 1 ]; then
    SOURCE_BYTES=$(awk "BEGIN {printf \"%.0f\", $SOURCE_SIZE_TIB * (1024^4)}")
    COMPLETION_PCT=$(awk "BEGIN {printf \"%.1f\", ($SEND_READ/$SOURCE_BYTES)*100}")
    REMAINING_BYTES=$(awk "BEGIN {printf \"%.0f\", $SOURCE_BYTES - $SEND_READ}")

    echo -e "\n${GREEN}Progress:${NC}"
    echo "  Source size:      ${SOURCE_SIZE_TIB} TiB"
    echo "  Completion:       ${COMPLETION_PCT}%"
    echo "  Remaining:        $(format_bytes $REMAINING_BYTES)"

    # Estimate time remaining
    if [ $(awk "BEGIN {print ($COMPLETION_PCT < 100)}") -eq 1 ]; then
        ETA_SECONDS=$(awk "BEGIN {printf \"%.0f\", $REMAINING_BYTES / ($SEND_READ/$ELAPSED_SECONDS)}")
        ETA_HOURS=$(awk "BEGIN {printf \"%.1f\", $ETA_SECONDS/3600}")
        TOTAL_HOURS=$(awk "BEGIN {printf \"%.0f\", $ELAPSED_HOURS + $ETA_HOURS}")

        echo "  ETA:              ~${ETA_HOURS}h remaining (~${TOTAL_HOURS}h total)"

        # Progress bar
        BAR_WIDTH=50
        FILLED=$(awk "BEGIN {printf \"%.0f\", ($COMPLETION_PCT/100)*$BAR_WIDTH}")
        BAR=$(printf "%${FILLED}s" | tr ' ' '█')
        EMPTY=$(printf "%$((BAR_WIDTH-FILLED))s" | tr ' ' '░')
        echo -e "\n  [${GREEN}${BAR}${NC}${EMPTY}] ${COMPLETION_PCT}%"
    else
        echo -e "${GREEN}  Transfer appears complete!${NC}"
    fi
fi

# Process health check
echo -e "\n${GREEN}Health Check:${NC}"
SEND_CPU=$(ps -p $SEND_PID -o %cpu= | tr -d ' ')
RECV_CPU=$(ps -p $RECV_PID -o %cpu= | tr -d ' ')

if [ $(awk "BEGIN {print ($SEND_CPU < 1.0)}") -eq 1 ] && [ $(awk "BEGIN {print ($RECV_CPU < 1.0)}") -eq 1 ]; then
    echo -e "  ${YELLOW}WARNING: Low CPU usage (send: ${SEND_CPU}%, recv: ${RECV_CPU}%)${NC}"
    echo "  Transfer may be I/O bound or stalled"
else
    echo -e "  ${GREEN}Processes are active (send: ${SEND_CPU}%, recv: ${RECV_CPU}%)${NC}"
fi

echo -e "\n${BLUE}Tip: Run this script again to see updated progress${NC}"
echo "     Or use: watch -n 60 '$0 $SEND_PID $RECV_PID $SOURCE_SIZE_TIB'"
