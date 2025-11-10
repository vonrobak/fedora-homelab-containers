#!/usr/bin/env bash
#
# GPU Detection and ROCm Capability Check
#
# This script detects AMD GPU hardware and verifies prerequisites for
# Immich ML ROCm acceleration.
#

set -euo pipefail

# Get current user (handle environments where USER isn't set)
CURRENT_USER="${USER:-$(whoami)}"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}     AMD GPU DETECTION & ROCM CAPABILITY CHECK${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo

# Check 1: Detect GPU hardware
echo -e "${YELLOW}▶ Checking for AMD GPU hardware...${NC}"
if command -v lspci >/dev/null 2>&1 && lspci | grep -i vga | grep -qi amd; then
    GPU_INFO=$(lspci | grep -i vga | grep -i amd)
    echo -e "${GREEN}✓ AMD GPU detected:${NC}"
    echo "  $GPU_INFO"
    GPU_DETECTED=true
elif [[ -d /dev/dri ]] && [[ -e /dev/kfd ]]; then
    # Fallback: if GPU devices exist, assume AMD GPU present
    echo -e "${GREEN}✓ AMD GPU detected (via device presence):${NC}"
    echo "  /dev/dri and /dev/kfd exist (lspci not available)"
    GPU_DETECTED=true
else
    echo -e "${RED}✗ No AMD GPU detected${NC}"
    GPU_DETECTED=false
fi
echo

# Check 2: Verify /dev/dri exists
echo -e "${YELLOW}▶ Checking for DRI devices (/dev/dri)...${NC}"
if [[ -d /dev/dri ]]; then
    echo -e "${GREEN}✓ /dev/dri exists${NC}"
    echo "  Available devices:"
    ls -la /dev/dri/ | tail -n +2 | while read line; do
        echo "    $line"
    done
    DRI_EXISTS=true
else
    echo -e "${RED}✗ /dev/dri not found${NC}"
    DRI_EXISTS=false
fi
echo

# Check 3: Verify /dev/kfd exists
echo -e "${YELLOW}▶ Checking for KFD device (/dev/kfd)...${NC}"
if [[ -e /dev/kfd ]]; then
    echo -e "${GREEN}✓ /dev/kfd exists${NC}"
    ls -la /dev/kfd | while read line; do
        echo "    $line"
    done
    KFD_EXISTS=true
else
    echo -e "${RED}✗ /dev/kfd not found${NC}"
    echo "  This device is required for ROCm GPU compute"
    KFD_EXISTS=false
fi
echo

# Check 4: Verify user is in render group
echo -e "${YELLOW}▶ Checking user group membership...${NC}"
if groups | grep -q render; then
    echo -e "${GREEN}✓ User is in 'render' group${NC}"
    RENDER_GROUP=true
else
    echo -e "${RED}✗ User is NOT in 'render' group${NC}"
    echo "  This is required to access /dev/kfd"
    echo "  Fix: sudo usermod -aG render $CURRENT_USER"
    echo "       Then log out and back in"
    RENDER_GROUP=false
fi
echo

# Check 5: Test device access permissions
echo -e "${YELLOW}▶ Checking device access permissions...${NC}"
if [[ -e /dev/kfd ]]; then
    if [[ -r /dev/kfd && -w /dev/kfd ]]; then
        echo -e "${GREEN}✓ /dev/kfd is readable and writable${NC}"
        KFD_ACCESS=true
    else
        echo -e "${RED}✗ /dev/kfd exists but is not accessible${NC}"
        echo "  Current permissions:"
        ls -la /dev/kfd
        KFD_ACCESS=false
    fi
else
    echo -e "${YELLOW}⚠ /dev/kfd does not exist (skipping access check)${NC}"
    KFD_ACCESS=false
fi
echo

# Check 6: Check available disk space for ROCm image
echo -e "${YELLOW}▶ Checking available disk space...${NC}"
AVAILABLE_GB=$(df -BG ~/.local/share/containers | tail -1 | awk '{print $4}' | sed 's/G//')
echo "  Available space: ${AVAILABLE_GB}GB"
if [[ $AVAILABLE_GB -ge 40 ]]; then
    echo -e "${GREEN}✓ Sufficient space for ROCm image (requires ~35GB)${NC}"
    SPACE_OK=true
else
    echo -e "${RED}✗ Insufficient space${NC}"
    echo "  ROCm image requires ~35GB, you have ${AVAILABLE_GB}GB"
    SPACE_OK=false
fi
echo

# Check 7: Try to detect GPU architecture (gfx version)
echo -e "${YELLOW}▶ Attempting to detect GPU architecture...${NC}"
if command -v rocminfo &>/dev/null; then
    echo "  Running rocminfo to detect gfx version..."
    GFX_VERSION=$(rocminfo | grep "Name:" | grep "gfx" | head -1 | awk '{print $2}')
    if [[ -n "$GFX_VERSION" ]]; then
        echo -e "${GREEN}✓ GPU architecture: $GFX_VERSION${NC}"

        # Check for known problematic architectures
        if [[ "$GFX_VERSION" == "gfx1150" || "$GFX_VERSION" == "gfx1151" ]]; then
            echo -e "${YELLOW}  ⚠ WARNING: gfx1150/gfx1151 (RDNA 3.5) has known issues with ROCm 6.3.4${NC}"
            echo "    See: https://github.com/immich-app/immich/issues/22874"
            echo "    May require HSA_OVERRIDE_GFX_VERSION workaround"
        fi
    else
        echo -e "${YELLOW}⚠ Could not detect gfx version from rocminfo${NC}"
    fi
elif [[ -e /sys/class/kfd/kfd/topology/nodes/1/properties ]]; then
    echo "  Checking KFD topology..."
    if grep -q "gfx_target_version" /sys/class/kfd/kfd/topology/nodes/1/properties 2>/dev/null; then
        GFX_TARGET=$(grep "gfx_target_version" /sys/class/kfd/kfd/topology/nodes/1/properties | awk '{print $2}')
        echo -e "${GREEN}✓ gfx_target_version: $GFX_TARGET${NC}"
    else
        echo -e "${YELLOW}⚠ Could not determine gfx version${NC}"
    fi
else
    echo -e "${YELLOW}⚠ rocminfo not installed and KFD topology not accessible${NC}"
    echo "  This is OK - ROCm container will detect GPU at runtime"
fi
echo

# Final summary
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}     SUMMARY${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo

ALL_CHECKS_PASSED=true

if [[ "$GPU_DETECTED" == "true" ]]; then
    echo -e "${GREEN}✓ AMD GPU detected${NC}"
else
    echo -e "${RED}✗ AMD GPU not detected${NC}"
    ALL_CHECKS_PASSED=false
fi

if [[ "$DRI_EXISTS" == "true" ]]; then
    echo -e "${GREEN}✓ DRI devices available${NC}"
else
    echo -e "${RED}✗ DRI devices missing${NC}"
    ALL_CHECKS_PASSED=false
fi

if [[ "$KFD_EXISTS" == "true" ]]; then
    echo -e "${GREEN}✓ KFD device available${NC}"
else
    echo -e "${RED}✗ KFD device missing${NC}"
    ALL_CHECKS_PASSED=false
fi

if [[ "$RENDER_GROUP" == "true" ]]; then
    echo -e "${GREEN}✓ User in render group${NC}"
else
    echo -e "${RED}✗ User not in render group${NC}"
    ALL_CHECKS_PASSED=false
fi

if [[ "$KFD_ACCESS" == "true" ]]; then
    echo -e "${GREEN}✓ KFD device accessible${NC}"
else
    echo -e "${RED}✗ KFD device not accessible${NC}"
    ALL_CHECKS_PASSED=false
fi

if [[ "$SPACE_OK" == "true" ]]; then
    echo -e "${GREEN}✓ Sufficient disk space${NC}"
else
    echo -e "${RED}✗ Insufficient disk space${NC}"
    ALL_CHECKS_PASSED=false
fi

echo
if [[ "$ALL_CHECKS_PASSED" == "true" ]]; then
    echo -e "${GREEN}🎉 All prerequisites met! Ready for ROCm GPU acceleration${NC}"
    echo
    echo -e "${BLUE}Next steps:${NC}"
    echo "  1. Update immich-ml.container with ROCm image and devices"
    echo "  2. Restart immich-ml service"
    echo "  3. Monitor GPU utilization with: watch -n 1 cat /sys/kernel/debug/dri/0/amdgpu_pm_info"
    exit 0
else
    echo -e "${RED}⚠ Some prerequisites are missing${NC}"
    echo
    echo -e "${BLUE}Required actions:${NC}"

    if [[ "$RENDER_GROUP" == "false" ]]; then
        echo "  • Add user to render group:"
        echo "    sudo usermod -aG render $USER"
        echo "    Then log out and log back in"
    fi

    if [[ "$KFD_EXISTS" == "false" ]]; then
        echo "  • Install ROCm drivers for /dev/kfd support"
        echo "    See: https://rocm.docs.amd.com/projects/install-on-linux/en/latest/"
    fi

    if [[ "$SPACE_OK" == "false" ]]; then
        echo "  • Free up disk space (need ~${AVAILABLE_GB}GB more)"
    fi

    exit 1
fi
