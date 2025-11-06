#!/bin/bash
# SSH Yubikey Test Monitoring Script
# Run this on fedora-htpc while testing from MacBook Air

echo "═══════════════════════════════════════════════════════════"
echo " SSH Yubikey Test Monitor - fedora-htpc.lokal"
echo " Watching for connections from MacBook Air (192.168.1.34)"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Check auto-rollback status
ROLLBACK_PID=$(cat /tmp/ssh-rollback-pid 2>/dev/null)
if [ -n "$ROLLBACK_PID" ] && ps -p "$ROLLBACK_PID" > /dev/null 2>&1; then
    echo "⏱  Auto-rollback ACTIVE (PID: $ROLLBACK_PID)"
    echo "   Will trigger in: ~$((300 - $(ps -o etimes= -p $ROLLBACK_PID))) seconds"
else
    echo "✅ Auto-rollback INACTIVE or canceled"
fi

echo ""
echo "───────────────────────────────────────────────────────────"
echo " Current Configuration"
echo "───────────────────────────────────────────────────────────"
echo "Active authorized_keys: $(grep -cv '^#\|^$' ~/.ssh/authorized_keys) keys"
echo "Backup available: $([ -f ~/.ssh/authorized_keys.old ] && echo 'YES' || echo 'NO')"
echo ""

echo "───────────────────────────────────────────────────────────"
echo " Recent SSH Authentications (last 10 minutes)"
echo "───────────────────────────────────────────────────────────"
journalctl -u sshd --since "10 minutes ago" --no-pager | grep "Accepted publickey" | tail -10

echo ""
echo "───────────────────────────────────────────────────────────"
echo " Live Monitoring Mode"
echo "───────────────────────────────────────────────────────────"
echo "Press Ctrl+C to exit"
echo ""
echo "Waiting for SSH connections from 192.168.1.34..."
echo ""

# Follow logs in real-time
journalctl -u sshd -f --no-pager | grep --line-buffered -E "Accepted publickey|Failed publickey|Connection closed|192.168.1.34"
