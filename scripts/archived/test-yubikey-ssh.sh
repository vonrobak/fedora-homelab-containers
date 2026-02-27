#!/bin/bash
# Yubikey SSH Test Script
# Tests each Yubikey can authenticate to fedora-htpc

echo "═══════════════════════════════════════════════════════════"
echo " Yubikey SSH Authentication Test"
echo " fedora-htpc.lokal (192.168.1.70)"
echo "═══════════════════════════════════════════════════════════"
echo ""

echo "Current authorized_keys:"
grep -v "^#" ~/.ssh/authorized_keys | grep -v "^$" | wc -l
echo ""

echo "Testing authentication to localhost..."
echo "This will require Yubikey touch for EACH attempt"
echo ""

# Test 1: Current Yubikey
echo "─────────────────────────────────────────────────────────"
echo "TEST 1: Currently inserted Yubikey"
echo "─────────────────────────────────────────────────────────"
SERIAL=$(ykman list --serials 2>/dev/null | head -1)
if [ -n "$SERIAL" ]; then
    echo "Detected Yubikey Serial: $SERIAL"
    echo "Attempting SSH..."
    if timeout 30 ssh -o BatchMode=no -o PreferredAuthentications=publickey patriark@localhost "echo 'Authentication successful!'" 2>&1 | grep -q "successful"; then
        echo "✅ SUCCESS: Yubikey $SERIAL can authenticate"
    else
        echo "❌ FAILED: Yubikey $SERIAL cannot authenticate"
        echo "   Check if key is in authorized_keys"
    fi
else
    echo "⚠️  No Yubikey detected"
fi

echo ""
echo "─────────────────────────────────────────────────────────"
echo "To test other Yubikeys:"
echo "1. Remove current Yubikey"
echo "2. Insert different Yubikey"
echo "3. Run this script again"
echo "─────────────────────────────────────────────────────────"
