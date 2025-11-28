# Memory Management Guide

**Created:** 2025-11-28  
**Purpose:** Optimize memory and swap usage for efficient homelab operation

## Current System Profile

**Hardware:**
- RAM: 30GB
- Swap: 8GB zram (compressed, in-memory)

**Typical Usage:**
- Homelab containers: ~2.7GB
- Desktop applications: ~6-7GB
- System cache: ~11GB (file cache - can be reclaimed)
- Available for apps: ~12GB

## Memory Consumption Breakdown

### Homelab Containers (Well-Optimized)
- Jellyfin: 1.3GB (max: 4GB)
- Prometheus: 252MB (max: 1GB)
- Immich: 295MB
- cAdvisor: 213MB
- OCIS: 137MB
- Loki: 131MB
- Grafana: 101MB
- Others: <100MB each

**Total: ~2.7GB** ✅

### Desktop Applications (High Usage)
- qbittorrent: 2.1GB ⚠️
- Browsers (Firefox + Vivaldi): ~2GB
- GNOME Desktop: ~1.5GB
- Claude Code session: ~400MB

**Total: ~6-7GB** ⚠️

## Understanding Swap Behavior

### Why Swap Gets Used (Even with Swappiness=10)

1. **Memory pressure triggers swapping** - When free RAM drops below threshold
2. **Swap persists** - Once pages are swapped out, they stay there unless accessed
3. **Swappiness=10** only affects *future* swap decisions, not existing swap

### Swap vs Cache

- **Cache (11GB)**: Can be instantly reclaimed - not a problem
- **Swap (4.5GB)**: Requires moving pages back to RAM - causes slowdown

## Immediate Solutions

### 1. Clear Swap (Temporary Fix)

```bash
# Use the automated script
~/containers/scripts/clear-swap-memory.sh

# Or manually:
sudo swapoff -a && sudo swapon -a
```

**When to use:** After closing memory-heavy applications, before starting intensive tasks.

**Caution:** Requires sufficient free RAM. System will freeze if RAM is full.

### 2. Drop Caches (Reclaim RAM from Cache)

```bash
# Drop page cache, dentries, and inodes
sync
sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'
```

**Effect:** Frees cache memory (the 11GB), makes it available for applications.

**Trade-off:** Slower file access until cache rebuilds.

### 3. Identify Memory Hogs

```bash
# Top processes by memory
ps aux --sort=-%mem | head -20

# Check what's using swap
sudo grep -H '^VmSwap:' /proc/*/status 2>/dev/null | \
  awk '$3 > 10000 {print $0}' | sort -k3 -n -r

# Container memory usage
podman stats --no-stream
```

## Long-Term Optimizations

### 1. Reduce Desktop Application Memory

**qbittorrent (2.1GB):**
```bash
# Set memory limit in qBittorrent settings
# Tools > Preferences > Advanced > Memory usage
# Recommended: 512MB-1GB for homelab use
```

**Browsers:**
- Close unused tabs
- Use single browser instead of Firefox + Vivaldi
- Consider lightweight browser for homelab admin tasks

**GNOME Desktop:**
```bash
# Disable GNOME Software auto-updates
gsettings set org.gnome.software download-updates false

# Reduce Nautilus cache
gsettings set org.gnome.nautilus.preferences thumbnail-limit 1
```

### 2. Optimize Zram Swap

Zram uses compression (1:3 ratio typically), so 8GB zram ≈ 2.7GB RAM.

**Check compression ratio:**
```bash
sudo zramctl
```

**Option: Reduce zram size** (if not needed):
```bash
# Check current config
cat /etc/systemd/zram-generator.conf

# Edit to reduce size (e.g., 4GB instead of 8GB)
sudo nano /etc/systemd/zram-generator.conf
sudo systemctl restart systemd-zram-setup@zram0.service
```

### 3. Set Memory Limits on Desktop Apps

**qbittorrent with systemd:**
```bash
# Create user service with memory limit
mkdir -p ~/.config/systemd/user/
cat > ~/.config/systemd/user/qbittorrent.service << 'UNIT'
[Unit]
Description=qBittorrent
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/qbittorrent
MemoryMax=1G
Restart=on-failure

[Install]
WantedBy=default.target
UNIT

systemctl --user daemon-reload
systemctl --user enable --now qbittorrent.service
```

### 4. Separate Homelab from Desktop Workstation

**Long-term recommendation** for homelab expansion:

- **Option A**: Dedicated server hardware (even low-power like NUC/Mini PC)
- **Option B**: Run homelab in VM with fixed memory allocation
- **Option C**: Use headless server OS on separate machine

**Benefits:**
- Predictable resource allocation
- No competition with desktop apps
- Can run 24/7 without desktop overhead
- Easier to scale

## Monitoring and Alerts

### Add Memory Pressure Alerts

```bash
# Create systemd notification for high memory usage
cat > ~/.config/systemd/user/memory-warning.service << 'UNIT'
[Unit]
Description=Memory Pressure Warning

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'notify-send "Memory Warning" "RAM usage above 80%"'
UNIT

cat > ~/.config/systemd/user/memory-warning.timer << 'UNIT'
[Unit]
Description=Check memory every 5 minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
UNIT

systemctl --user daemon-reload
systemctl --user enable --now memory-warning.timer
```

### Monitor with Grafana

Access dashboard: `https://grafana.patriark.org/d/node-exporter-full`

**Key metrics:**
- Node Memory Available
- Node Memory Swap Used
- Node Memory Cache
- Container Memory Usage

## Best Practices

1. **Close desktop apps before intensive homelab tasks**
2. **Clear swap after closing memory-heavy applications**
3. **Monitor memory trends** in Grafana weekly
4. **Set memory limits** on new containers
5. **Consider dedicated hardware** for homelab expansion

## Troubleshooting

### System Becomes Unresponsive

**Cause:** OOM (Out of Memory) killer activated.

**Prevention:**
```bash
# Increase vm.min_free_kbytes (keep more RAM free)
sudo sysctl vm.min_free_kbytes=524288  # 512MB
echo "vm.min_free_kbytes=524288" | sudo tee -a /etc/sysctl.conf
```

### Containers Getting OOM Killed

**Check logs:**
```bash
journalctl --user -u jellyfin.service | grep -i "oom\|memory"
```

**Increase container limits:**
```bash
# Edit quadlet file
nano ~/.config/containers/systemd/jellyfin.container

# Increase MemoryMax
MemoryMax=6G

# Restart
systemctl --user daemon-reload
systemctl --user restart jellyfin.service
```

### Swap Always Full

1. **Identify culprit:** Check process memory usage over time
2. **Memory leak?** Restart suspect service
3. **Insufficient RAM?** Consider hardware upgrade
4. **Desktop bloat?** Reduce running applications

## Related Documentation

- Hardware specs: `docs/20-operations/guides/system-architecture.md`
- Container limits: `~/.config/containers/systemd/*.container`
- Monitoring: `docs/40-monitoring-and-documentation/guides/slo-framework.md`
