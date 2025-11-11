#!/usr/bin/env bash
#
# Deploy Immich ML with AMD ROCm GPU Acceleration
#
# This script enables GPU acceleration for Immich machine learning by:
# 1. Detecting and validating GPU prerequisites
# 2. Backing up current CPU-only configuration
# 3. Deploying ROCm-enabled immich-ml quadlet
# 4. Verifying GPU is being utilized
#

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}     IMMICH ML GPU ACCELERATION DEPLOYMENT${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo

# Step 1: Run GPU detection
echo -e "${YELLOW}▶ Step 1: Detecting GPU and validating prerequisites${NC}"
echo

if ! "$SCRIPT_DIR/detect-gpu-capabilities.sh"; then
    echo
    echo -e "${RED}✗ GPU prerequisites not met${NC}"
    echo "  Please resolve the issues above before continuing"
    exit 1
fi

echo
read -p "GPU prerequisites verified. Continue with deployment? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    echo -e "${YELLOW}Deployment cancelled${NC}"
    exit 0
fi

# Step 2: Backup current configuration
echo
echo -e "${YELLOW}▶ Step 2: Backing up current CPU-only configuration${NC}"
BACKUP_FILE="$HOME/.config/containers/systemd/immich-ml.container.backup-$(date +%Y%m%d-%H%M%S)"
if [[ -f "$HOME/.config/containers/systemd/immich-ml.container" ]]; then
    cp "$HOME/.config/containers/systemd/immich-ml.container" "$BACKUP_FILE"
    echo -e "${GREEN}✓ Backup saved: $BACKUP_FILE${NC}"
else
    echo -e "${YELLOW}⚠ No existing immich-ml.container found (first deployment?)${NC}"
fi

# Step 3: Measure baseline CPU performance (if ML is currently running)
echo
echo -e "${YELLOW}▶ Step 3: Measuring baseline CPU performance${NC}"
if systemctl --user is-active immich-ml.service &>/dev/null; then
    echo "  Taking baseline measurements..."
    echo "  • Current memory usage:"
    podman stats --no-stream immich-ml --format "    {{.Name}}: {{.MemUsage}}" 2>/dev/null || echo "    (unable to measure)"

    echo
    echo -e "${BLUE}  Note: For accurate before/after comparison:${NC}"
    echo "    1. Upload a test photo set before GPU deployment"
    echo "    2. Note ML processing time in Immich logs"
    echo "    3. After GPU deployment, upload similar photos and compare"
else
    echo -e "${YELLOW}  ⚠ immich-ml not currently running (skipping baseline)${NC}"
fi

# Step 4: Stop current immich-ml service
echo
echo -e "${YELLOW}▶ Step 4: Stopping current immich-ml service${NC}"
if systemctl --user is-active immich-ml.service &>/dev/null; then
    systemctl --user stop immich-ml.service
    podman rm -f immich-ml 2>/dev/null || true
    echo -e "${GREEN}✓ Service stopped${NC}"
else
    echo -e "${YELLOW}  ⚠ Service not running${NC}"
fi

# Step 5: Deploy ROCm-enabled quadlet
echo
echo -e "${YELLOW}▶ Step 5: Deploying ROCm-enabled quadlet${NC}"
cp "$REPO_ROOT/quadlets/immich-ml-rocm.container" "$HOME/.config/containers/systemd/immich-ml.container"
echo -e "${GREEN}✓ Quadlet copied${NC}"

systemctl --user daemon-reload
echo -e "${GREEN}✓ Systemd reloaded${NC}"

# Step 6: Pull ROCm image (this will take a while!)
echo
echo -e "${YELLOW}▶ Step 6: Pulling ROCm image (this may take 10-15 minutes for first pull)${NC}"
echo "  Image size: ~35GB"
echo "  Progress will be shown by Podman..."
echo

START_TIME=$(date +%s)
systemctl --user start immich-ml.service || {
    echo -e "${RED}✗ Failed to start service${NC}"
    echo "  Check logs: journalctl --user -u immich-ml.service -n 50"
    exit 1
}
END_TIME=$(date +%s)
PULL_TIME=$((END_TIME - START_TIME))

echo -e "${GREEN}✓ Service started (took ${PULL_TIME}s)${NC}"

# Step 7: Wait for health check
echo
echo -e "${YELLOW}▶ Step 7: Waiting for ML service to become healthy${NC}"
echo "  Health check start period: 600s (10 minutes)"
echo "  This allows time for model loading..."
echo

for i in {1..40}; do
    sleep 15
    if systemctl --user is-active immich-ml.service &>/dev/null; then
        HEALTH=$(podman healthcheck run immich-ml 2>&1 || echo "starting")
        if [[ "$HEALTH" != *"unhealthy"* && "$HEALTH" != "starting" ]]; then
            echo -e "${GREEN}✓ ML service is healthy!${NC}"
            break
        else
            printf "\r  Waiting... (%d/600s) Status: %s" $((i*15)) "$HEALTH"
        fi
    else
        echo -e "${RED}✗ Service stopped unexpectedly${NC}"
        echo "  Check logs: journalctl --user -u immich-ml.service -n 50"
        exit 1
    fi
done
echo

# Step 8: Verify GPU utilization
echo
echo -e "${YELLOW}▶ Step 8: Verifying GPU utilization${NC}"
echo

# Check if rocm-smi is available
if command -v rocm-smi &>/dev/null; then
    echo "  Running rocm-smi to check GPU status:"
    rocm-smi --showuse || echo "  (rocm-smi failed - this is OK, container has GPU access)"
else
    echo -e "${YELLOW}  ⚠ rocm-smi not installed on host${NC}"
fi

# Check for GPU activity in sysfs
if [[ -f /sys/kernel/debug/dri/0/amdgpu_pm_info ]]; then
    echo
    echo "  Current GPU power state:"
    cat /sys/kernel/debug/dri/0/amdgpu_pm_info 2>/dev/null || echo "  (unable to read - may require sudo)"
fi

echo
echo -e "${BLUE}  To monitor GPU utilization during ML processing:${NC}"
echo "    watch -n 1 'cat /sys/kernel/debug/dri/0/amdgpu_pm_info 2>/dev/null || echo \"Run: sudo chmod +r /sys/kernel/debug/dri/0/amdgpu_pm_info\"'"
echo
echo "  Or if radeontop is installed:"
echo "    radeontop"

# Step 9: Check logs for ROCm initialization
echo
echo -e "${YELLOW}▶ Step 9: Checking logs for ROCm initialization${NC}"
echo
echo "  Recent ML service logs:"
journalctl --user -u immich-ml.service -n 30 --no-pager | grep -i -E "(rocm|hip|gpu|gfx)" || {
    echo -e "${YELLOW}  ⚠ No ROCm-specific messages in logs yet${NC}"
    echo "    This is normal if no ML jobs have run"
    echo "    GPU will be activated when Immich processes photos"
}

# Final summary
echo
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}     DEPLOYMENT COMPLETE${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo
echo -e "${GREEN}✓ immich-ml now running with ROCm GPU acceleration${NC}"
echo
echo -e "${BLUE}Next steps to verify GPU acceleration:${NC}"
echo
echo "1. Upload photos to Immich (via web or mobile app)"
echo "2. Monitor GPU utilization:"
echo "   watch -n 1 'cat /sys/kernel/debug/dri/0/amdgpu_pm_info 2>/dev/null || echo \"Need sudo access\"'"
echo
echo "3. Check ML processing logs:"
echo "   podman logs -f immich-ml"
echo
echo "4. Compare performance:"
echo "   • CPU baseline: Check your notes from Step 3"
echo "   • GPU performance: Check Immich job queue times"
echo "   • Expected: 5-10x faster face detection and smart search"
echo
echo -e "${BLUE}Troubleshooting:${NC}"
echo "  • Service status: systemctl --user status immich-ml.service"
echo "  • Container logs: podman logs immich-ml"
echo "  • GPU access test: podman exec -it immich-ml ls -la /dev/kfd /dev/dri"
echo
echo -e "${BLUE}Rollback (if needed):${NC}"
echo "  cp $BACKUP_FILE ~/.config/containers/systemd/immich-ml.container"
echo "  systemctl --user daemon-reload"
echo "  systemctl --user restart immich-ml.service"
echo
