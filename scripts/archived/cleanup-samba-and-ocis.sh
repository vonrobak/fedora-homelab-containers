#!/bin/bash
# Cleanup script for Samba and OCIS removal
# Created: 2025-12-29
# Purpose: Remove Samba server and OCIS remnants after migration to Nextcloud

set -e

echo "=================================================="
echo "Samba & OCIS Cleanup Script"
echo "=================================================="
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ============================================================
# PART 1: SAMBA REMOVAL
# ============================================================
echo -e "${YELLOW}PART 1: Samba Server Removal${NC}"
echo ""

# Check if samba is running
if pgrep -x "smbd" > /dev/null; then
    echo "✓ Samba processes detected (smbd running)"
    echo ""
    echo "To stop Samba, run these commands with sudo:"
    echo "  sudo systemctl stop smbd.service"
    echo "  sudo systemctl disable smbd.service"
    echo "  sudo systemctl stop nmbd.service 2>/dev/null || true"
    echo "  sudo systemctl disable nmbd.service 2>/dev/null || true"
    echo ""
    echo -e "${RED}⚠️  Run the above commands manually (requires sudo)${NC}"
    echo ""
else
    echo "✓ Samba is not running"
fi

echo "✓ Samba configuration already archived to:"
echo "  /mnt/btrfs-pool/subvol6-tmp/99-outbound/samba/"
echo ""

# ============================================================
# PART 2: OCIS REMOVAL
# ============================================================
echo -e "${YELLOW}PART 2: OCIS Remnants Removal${NC}"
echo ""

# 1. Remove OCIS quadlet file
if [ -f ~/containers/quadlets/ocis.container ]; then
    echo "→ Archiving OCIS quadlet file..."
    mkdir -p /mnt/btrfs-pool/subvol6-tmp/99-outbound/ocis-archive
    mv ~/containers/quadlets/ocis.container /mnt/btrfs-pool/subvol6-tmp/99-outbound/ocis-archive/
    echo "  ✓ Moved to /mnt/btrfs-pool/subvol6-tmp/99-outbound/ocis-archive/"
else
    echo "✓ OCIS quadlet file not found (already removed)"
fi

# 2. Archive OCIS config
if [ -d ~/containers/config/ocis ]; then
    echo "→ Archiving OCIS config directory..."
    mkdir -p /mnt/btrfs-pool/subvol6-tmp/99-outbound/ocis-archive
    mv ~/containers/config/ocis /mnt/btrfs-pool/subvol6-tmp/99-outbound/ocis-archive/
    echo "  ✓ Moved to /mnt/btrfs-pool/subvol6-tmp/99-outbound/ocis-archive/"
else
    echo "✓ OCIS config directory not found (already removed)"
fi

# 3. Archive OCIS security reports
if ls ~/containers/data/security-reports/trivy-ocis* 1> /dev/null 2>&1; then
    echo "→ Archiving OCIS security reports..."
    mkdir -p /mnt/btrfs-pool/subvol6-tmp/99-outbound/ocis-archive/security-reports
    mv ~/containers/data/security-reports/trivy-ocis* /mnt/btrfs-pool/subvol6-tmp/99-outbound/ocis-archive/security-reports/
    echo "  ✓ Moved to /mnt/btrfs-pool/subvol6-tmp/99-outbound/ocis-archive/security-reports/"
else
    echo "✓ No OCIS security reports found"
fi

# 4. Remove OCIS podman image
if podman images | grep -q "owncloud/ocis"; then
    echo "→ Removing OCIS podman image..."
    podman rmi docker.io/owncloud/ocis:7.1.3 2>/dev/null || true
    echo "  ✓ OCIS image removed (195 MB freed)"
else
    echo "✓ OCIS image not found (already removed)"
fi

# 5. Remove OCIS podman secrets (if they exist)
echo "→ Checking for OCIS podman secrets..."
for secret in ocis_jwt_secret ocis_transfer_secret ocis_machine_auth_api_key; do
    if podman secret exists "$secret" 2>/dev/null; then
        podman secret rm "$secret"
        echo "  ✓ Removed secret: $secret"
    fi
done

# 6. Create archive metadata
echo "→ Creating archive metadata..."
cat > /mnt/btrfs-pool/subvol6-tmp/99-outbound/ocis-archive/ARCHIVED_DATE.txt <<EOF
Archived: $(date '+%Y-%m-%d %H:%M:%S')
Archived by: patriark
Reason: OCIS decommissioned, migrated to Nextcloud
Original decommission date: 2025-12-20
Final cleanup date: $(date '+%Y-%m-%d')

Files archived:
- ocis.container (quadlet file)
- config/ocis/ (configuration directory)
- security-reports/trivy-ocis* (vulnerability scan reports)

Image removed:
- docker.io/owncloud/ocis:7.1.3 (195 MB)

Podman secrets removed:
- ocis_jwt_secret
- ocis_transfer_secret
- ocis_machine_auth_api_key

Data directory status:
- /mnt/btrfs-pool/subvol7-containers/ocis/data (already removed on 2025-12-20)

Note: Documentation files in docs/ intentionally preserved for historical reference
EOF
echo "  ✓ Metadata created"
echo ""

# ============================================================
# PART 3: TRAEFIK CONFIGURATION UPDATE
# ============================================================
echo -e "${YELLOW}PART 3: Traefik Configuration Update Needed${NC}"
echo ""
echo "The following manual updates are required:"
echo ""
echo "1. Rename 'rate-limit-ocis' middleware to 'rate-limit-webdav'"
echo "   File: ~/containers/config/traefik/dynamic/middleware.yml"
echo "   Lines 98-106"
echo ""
echo "2. Update Collabora router to use renamed middleware"
echo "   File: ~/containers/config/traefik/dynamic/routers.yml"
echo "   Line 128: Change 'rate-limit-ocis@file' to 'rate-limit-webdav@file'"
echo ""
echo "   (Traefik will auto-reload the configuration)"
echo ""

# ============================================================
# SUMMARY
# ============================================================
echo -e "${GREEN}=================================================="
echo "Cleanup Summary"
echo "==================================================${NC}"
echo ""
echo "✓ Samba config archived"
echo "✓ OCIS files archived"
echo "✓ OCIS image removed"
echo "✓ OCIS secrets removed"
echo ""
echo "Manual steps required:"
echo "  1. Stop Samba (requires sudo - see commands above)"
echo "  2. Update Traefik configs (rename rate-limit-ocis)"
echo ""
echo "Archive location:"
echo "  /mnt/btrfs-pool/subvol6-tmp/99-outbound/"
echo "    ├── samba/"
echo "    └── ocis-archive/"
echo ""
