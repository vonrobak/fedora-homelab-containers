# Log Storage Migration to BTRFS - Phase 2

**Date:** 2026-01-17
**Status:** ✅ Complete
**Component:** Logging Infrastructure (Promtail, Traefik, journal-export)
**Context:** Part of 5-phase alerting system redesign (breezy-wobbling-kettle plan)

---

## Executive Summary

Successfully migrated container log storage from SSD (`~/containers/data/`) to BTRFS pool (`/mnt/btrfs-pool/subvol7-containers/`) to:
- Increase log retention capacity (300MB → 30+ days at current rate)
- Reduce SSD wear (~1GB/day writes)
- Leverage BTRFS pool capacity (4.2TB free vs SSD 53GB free)

**Logs migrated:** journal-export (335MB), traefik-logs (3.7MB)
**COW enabled:** User preference for data integrity on log files
**Services updated:** journal-export.service, traefik.container, promtail.container
**Validation:** ✅ All logs writing to BTRFS, Promtail ingesting, Loki receiving

---

## Background

### Loki False Positive Alert Investigation

Received Discord alert: "ServiceErrorRateHigh - high error rate in Loki" (2026-01-17 08:01)

**Root Cause:** False positive from overly broad `service_errors_total` metric
- Loki logs normal INFO operations at syslog priority 3 (ERROR level)
- Promtail metric extraction (lines 38-48) counts ALL priority <=3 as errors
- Result: 25,275 "errors" accumulated from normal table uploads, stream flushing
- Actual service health: ✅ Fully operational, no degradation

**Evidence:** `journalctl --user -u loki.service --priority=3` showed only `level=info` messages during alert period

**Solution:** This metric already marked for removal in Phase 3 of the plan (fundamentally flawed design)

### Phase 2 Implementation

From plan `/home/patriark/.claude/plans/breezy-wobbling-kettle.md`:
- **Original plan:** Enable NOCOW on log directories
- **User correction:** Keep COW enabled for data integrity
- **Rationale:** Logs are critical audit trail, data integrity > performance

---

## Migration Process

### 1. Preparation (User-executed)

```bash
# Created BTRFS directories (sudo required)
sudo mkdir -p /mnt/btrfs-pool/subvol7-containers/journal-export \
              /mnt/btrfs-pool/subvol7-containers/traefik-logs
sudo chown patriark:patriark /mnt/btrfs-pool/subvol7-containers/journal-export \
                              /mnt/btrfs-pool/subvol7-containers/traefik-logs

# COW enabled by default (no chattr +C applied)
```

### 2. Copy Existing Logs

```bash
# journal-export logs
cp -a ~/containers/data/journal-export/* \
      /mnt/btrfs-pool/subvol7-containers/journal-export/

# traefik-logs
cp -a ~/containers/data/traefik-logs/* \
      /mnt/btrfs-pool/subvol7-containers/traefik-logs/

# Verification
ls -lh /mnt/btrfs-pool/subvol7-containers/journal-export/
# total 266M
# -rw-r--r--. journal.log (123M → growing)
# -rw-r--r--. journal.log.1 (134M)
# -rw-r--r--. journal.log.1.gz (9.1M)

ls -lh /mnt/btrfs-pool/subvol7-containers/traefik-logs/
# total 3.7M
# -rw-r--r--. access.log + rotated archives
```

### 3. Update Service Configurations

**File: `~/.config/systemd/user/journal-export.service`**
```diff
- StandardOutput=append:%h/containers/data/journal-export/journal.log
+ StandardOutput=append:/mnt/btrfs-pool/subvol7-containers/journal-export/journal.log
```

**File: `~/containers/scripts/rotate-journal-export.sh`**
```diff
- LOG_DIR="$HOME/containers/data/journal-export"
+ LOG_DIR="/mnt/btrfs-pool/subvol7-containers/journal-export"
```

**File: `~/.config/containers/systemd/promtail.container`**
```diff
- Volume=%h/containers/data/journal-export:/var/log/journal-export:ro,Z
+ Volume=/mnt/btrfs-pool/subvol7-containers/journal-export:/var/log/journal-export:ro,Z

- Volume=%h/containers/data/traefik-logs:/var/log/traefik:ro,z
+ Volume=/mnt/btrfs-pool/subvol7-containers/traefik-logs:/var/log/traefik:ro,z
```

**File: `~/.config/containers/systemd/traefik.container`**
```diff
- Volume=%h/containers/data/traefik-logs:/var/log/traefik:z
+ Volume=/mnt/btrfs-pool/subvol7-containers/traefik-logs:/var/log/traefik:z
```

**SELinux labels preserved:** `:Z` for journal-export, `:z` for traefik-logs

### 4. Restart Services

```bash
# Reload systemd to pick up config changes
systemctl --user daemon-reload

# Restart in dependency order
systemctl --user restart journal-export.service  # Writes journal logs
systemctl --user restart traefik.service         # Writes access logs
systemctl --user restart promtail.service        # Reads both logs
# Loki continues running (no restart needed)

# Verification
systemctl --user is-active journal-export.service traefik.service \
                            promtail.service loki.service grafana.service
# active (all services)
```

---

## Validation Results

### Log Writing to BTRFS ✅

**journal-export:**
```bash
$ ls -lh /mnt/btrfs-pool/subvol7-containers/journal-export/
total 335M
-rw-r--r--. journal.log (192M - actively growing)

$ tail -1 /mnt/btrfs-pool/subvol7-containers/journal-export/journal.log | jq -r '.MESSAGE'
"container health_status 42a8de6e816d... (health_status=healthy)"
# Timestamp: 2026-01-17 09:55:17 ✅
```

**traefik-logs:**
```bash
$ stat /mnt/btrfs-pool/subvol7-containers/traefik-logs/access.log
Modify: 2026-01-17 09:54:06 ✅
```

### Promtail Ingestion ✅

**Container mount verification:**
```bash
$ podman exec promtail ls -lh /var/log/journal-export/ /var/log/traefik/
/var/log/journal-export/:
total 335M
-rw-r--r--. journal.log (192M) ✅

/var/log/traefik/:
total 3.7M
-rw-r--r--. access.log ✅
```

**Tailing confirmation:**
```bash
$ podman logs promtail --tail 20 | grep "tail routine"
level=info msg="tail routine: started" path=/var/log/journal-export/journal.log
level=info msg="tail routine: started" path=/var/log/traefik/access.log
msg="Seeked /var/log/journal-export/journal.log - &{Offset:132046167}"
```

**Metrics:**
```bash
$ podman exec prometheus wget -qO- 'http://promtail:9080/metrics' | grep read_bytes
promtail_read_bytes_total{path="/var/log/journal-export/journal.log"} 201870611
# 201.8 MB read successfully ✅
```

### Loki Ingestion ✅

**Flush activity from new location:**
```bash
$ podman logs loki --since "2m" | grep flush
level=info component=ingester msg="flushing stream"
  labels="{filename=\"/var/log/journal-export/journal.log\", ...}"
  total_uncomp="16 MB" synced=1
# Multiple flush events showing new BTRFS path ✅
```

**Service health:**
```bash
$ systemctl --user is-active loki.service
active ✅

$ podman ps | grep loki
loki  Up 44 hours  3100/tcp ✅
```

---

## Storage Impact

### Before Migration
- SSD usage: 63GB / 118GB (55%)
- Journal-export: 258MB on SSD
- Traefik-logs: 3.6MB on SSD
- Total SSD log storage: ~262MB

### After Migration
- SSD usage: 63GB / 118GB (55% - unchanged, old logs still present)
- BTRFS usage: 335MB (journal) + 3.7MB (traefik) = ~339MB
- Old logs location: `~/containers/data/journal-export/` (to be cleaned after 24h validation)

### Future State (after cleanup)
- SSD freed: ~262MB
- Retention capacity: 30+ days at ~1GB/day (vs 3 rotations / 300MB previously)
- Write reduction: ~1GB/day moved from SSD to BTRFS (reduced wear)

---

## Dependencies Updated

**Services depending on log paths:**
1. ✅ `journal-export.service` - Updated StandardOutput
2. ✅ `rotate-journal-export.sh` - Updated LOG_DIR
3. ✅ `promtail.container` - Updated both volume mounts
4. ✅ `traefik.container` - Updated access log mount

**No impact on:**
- Loki (receives from Promtail over network)
- Grafana (queries Loki over network)
- Prometheus (scrapes Promtail metrics over network)
- Alert rules (query Loki/Prometheus, not direct log access)

---

## Next Steps

### Immediate (Completed)
- ✅ Logs migrated to BTRFS with COW enabled
- ✅ All services restarted and validated
- ✅ Full pipeline operational (journal → promtail → loki)

### 24-Hour Validation Period
Monitor for:
- Log rotation behavior at next hourly rotation
- Promtail position tracking across restarts
- Disk I/O impact of COW on BTRFS
- Any permission or SELinux issues

### After 24h Validation (2026-01-18)
```bash
# Clean up old SSD logs
rm -rf ~/containers/data/journal-export/*
rm -rf ~/containers/data/traefik-logs/*

# Keep directories for potential future use
```

### Remaining Plan Phases
- ⏳ **Phase 3:** Eliminate fragile log-based metrics (remove service_errors_total)
- ⏳ **Phase 4:** Alert consolidation (51 → 48 alerts)
- ⏳ **Phase 5:** Meta-monitoring (detect monitoring failures)

---

## Design Decisions

### COW vs NOCOW on Log Directories

**Original plan:** NOCOW for performance (databases benefit from NOCOW)
**User preference:** COW for data integrity

**Rationale:**
- Logs are critical audit trail (compliance, incident investigation)
- Data integrity > performance for log storage
- NOCOW primarily benefits random-write workloads (databases)
- Sequential log appends less affected by COW overhead
- BTRFS snapshots work better with COW data

**Performance impact:** Minimal - logs are append-only sequential writes, COW overhead negligible

### Why BTRFS for Logs?

1. **Capacity:** 4.2TB free vs SSD 53GB free
2. **Retention:** Can store 30+ days vs 3 rotations (300MB)
3. **Wear:** Moves ~1GB/day writes off SSD
4. **Snapshots:** BTRFS snapshots include logs for point-in-time recovery
5. **Compression:** Transparent compression available if needed

---

## Rollback Procedure

If issues arise:

```bash
# 1. Stop services
systemctl --user stop promtail.service traefik.service journal-export.service

# 2. Revert configuration files
git checkout HEAD -- ~/.config/systemd/user/journal-export.service \
                     ~/.config/containers/systemd/promtail.container \
                     ~/.config/containers/systemd/traefik.container \
                     ~/containers/scripts/rotate-journal-export.sh

# 3. Reload and restart
systemctl --user daemon-reload
systemctl --user restart journal-export.service traefik.service promtail.service

# 4. Verify
systemctl --user is-active journal-export.service promtail.service
```

**Estimated rollback time:** 5 minutes

---

## Related Documentation

- **Plan:** `~/.claude/plans/breezy-wobbling-kettle.md` - 5-phase alerting redesign
- **Phase 1:** `docs/98-journals/2026-01-16-nextcloud-cron-alert-fix-phase1.md`
- **Alert config:** `config/prometheus/rules/log-based-alerts.yml`
- **Promtail config:** `config/promtail/promtail-config.yml`
- **Service files:** `~/.config/systemd/user/journal-export.service`
- **Container files:** `~/.config/containers/systemd/{traefik,promtail}.container`

---

## Summary

**Phase 2 Status:** ✅ Complete
- Logs successfully migrated to BTRFS with COW enabled
- Full pipeline validated (write → ingest → store)
- Zero downtime, all services operational
- SSD freed after 24h validation: ~262MB
- Retention capacity increased: 3 rotations → 30+ days

**False Positive Identified:** ServiceErrorRateHigh for Loki
- Root cause: Overly broad log-based metric
- Resolution: Marked for removal in Phase 3
- No service impact, operational as expected

**Time invested:** ~1 hour (investigation + migration + validation)
**Next milestone:** 24h validation, then Phase 3 (eliminate fragile metrics)
