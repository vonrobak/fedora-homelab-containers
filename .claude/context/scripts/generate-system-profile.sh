#!/bin/bash
#
# generate-system-profile.sh
# Creates persistent system profile for Claude context framework
#
# Usage: ./generate-system-profile.sh [--output FILE]
#

set -euo pipefail

# Configuration
OUTPUT_FILE="${1:-./../system-profile.json}"
TEMP_FILE=$(mktemp)

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Generating system profile...${NC}"

# Gather system information
HOSTNAME=$(hostname)
TIMESTAMP=$(date -Iseconds)
UPTIME_DAYS=$(awk '{print int($1/86400)}' /proc/uptime)

# CPU info
CPU_MODEL=$(grep "model name" /proc/cpuinfo | head -1 | cut -d':' -f2 | xargs)
CPU_CORES=$(nproc)

# Memory info (in MB)
MEM_TOTAL=$(free -m | awk '/^Mem:/ {print $2}')
MEM_AVAILABLE=$(free -m | awk '/^Mem:/ {print $7}')

# GPU info
GPU_MODEL=$(lspci | grep -i vga | cut -d':' -f3 | xargs || echo "Unknown")
GPU_DRIVER=$(lsmod | grep -E "amdgpu|nvidia|i915" | awk '{print $1}' | head -1 || echo "none")

# Storage info
SYSTEM_SSD_SIZE=$(df -BG / | awk 'NR==2 {print $2}' | tr -d 'G')
SYSTEM_SSD_USED_PCT=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
BTRFS_SIZE=$(df -BG /mnt/btrfs-pool | awk 'NR==2 {print $2}' | tr -d 'G' || echo "0")
BTRFS_USED_PCT=$(df /mnt/btrfs-pool | awk 'NR==2 {print $5}' | tr -d '%' || echo "0")

# Network info
NETWORKS=$(podman network ls --format '{{.Name}}' | grep -v "^podman$" || true)
NETWORK_COUNT=$(echo "$NETWORKS" | grep -v "^$" | wc -l)

# Service/Container info
CONTAINERS=$(podman ps --format '{{.Names}}')
CONTAINER_COUNT=$(echo "$CONTAINERS" | grep -v "^$" | wc -l)

# Build JSON using jq
cat > "$TEMP_FILE" <<EOF
{
  "generated_at": "$TIMESTAMP",
  "system": {
    "hostname": "$HOSTNAME",
    "uptime_days": $UPTIME_DAYS,
    "os": "Fedora Workstation 42",
    "kernel": "$(uname -r)"
  },
  "hardware": {
    "cpu": {
      "model": "$CPU_MODEL",
      "cores": $CPU_CORES
    },
    "memory": {
      "total_mb": $MEM_TOTAL,
      "available_mb": $MEM_AVAILABLE
    },
    "gpu": {
      "model": "$GPU_MODEL",
      "driver": "$GPU_DRIVER",
      "dri_devices": ["/dev/dri/card1", "/dev/dri/renderD128"]
    },
    "storage": {
      "system_ssd": {
        "size_gb": $SYSTEM_SSD_SIZE,
        "used_percent": $SYSTEM_SSD_USED_PCT,
        "mount": "/"
      },
      "btrfs_pool": {
        "size_gb": $BTRFS_SIZE,
        "used_percent": $BTRFS_USED_PCT,
        "mount": "/mnt/btrfs-pool"
      }
    }
  },
  "networks": $(echo "$NETWORKS" | jq -R -s 'split("\n") | map(select(length > 0))'),
  "network_count": $NETWORK_COUNT,
  "services": $(echo "$CONTAINERS" | jq -R -s 'split("\n") | map(select(length > 0))'),
  "service_count": $CONTAINER_COUNT,
  "container_runtime": {
    "type": "podman",
    "version": "$(podman --version | awk '{print $3}')",
    "rootless": true,
    "orchestration": "systemd quadlets"
  }
}
EOF

# Pretty-print and save
jq '.' "$TEMP_FILE" > "$OUTPUT_FILE"
rm "$TEMP_FILE"

echo -e "${GREEN}✓ System profile generated: $OUTPUT_FILE${NC}"
echo -e "${BLUE}Summary:${NC}"
echo "  Hostname: $HOSTNAME"
echo "  CPU: $CPU_MODEL ($CPU_CORES cores)"
echo "  Memory: ${MEM_TOTAL}MB total"
echo "  GPU: $GPU_MODEL"
echo "  Networks: $NETWORK_COUNT"
echo "  Services: $CONTAINER_COUNT running containers"
echo "  System SSD: ${SYSTEM_SSD_USED_PCT}% used"
echo "  BTRFS Pool: ${BTRFS_USED_PCT}% used"
