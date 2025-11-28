#!/bin/bash
# Clear swap and optimize memory
# Only run when system is under memory pressure

set -euo pipefail

echo "Current memory and swap usage:"
free -h

echo ""
echo "Clearing PageCache, dentries, and inodes..."
sync
sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'

echo ""
echo "Current swap usage: $(free -h | awk '/^Swap:/ {print $3}')"
read -p "Do you want to clear swap? (requires sufficient free RAM) [y/N]: " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Turning off swap..."
    sudo swapoff -a
    
    echo "Turning swap back on..."
    sudo swapon -a
    
    echo "Swap cleared!"
fi

echo ""
echo "After cleanup:"
free -h
