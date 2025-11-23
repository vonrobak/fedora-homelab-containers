# Immich Data Loss Troubleshooting Plan
**Date:** 2025-11-23
**Status:** CRITICAL - Complete data loss (4,223 photos missing)
**Affected Services:** Immich web UI, iOS app, iPadOS app
**Last Known Good:** 2025-11-22

## Incident Summary

### Symptoms
1. **Web UI (photos.patriark.org):** Shows "upload your first photo" - all 4,223 photos missing
2. **iOS/iPadOS apps:**
   - Sync status shows 4,223 remote assets (correct count)
   - Photos section is empty
   - People/Places metadata exists but shows "0 items"
   - Local Apple Photos access works normally

### Critical Observation
**The sync status showing correct asset count (4,223) while UI shows nothing suggests the database knows about the photos but cannot access/display them.** This points to:
- File storage mount issue
- Database-to-storage mapping broken
- Permissions issue on media files
- Library corruption

---

## Troubleshooting Workflow

### Phase 1: Initial State Assessment (5 minutes)

**Goal:** Establish current system state and verify the scope of the issue.

#### 1.1 Service Health Check
```bash
# Check all Immich services are running
systemctl --user status immich.service
systemctl --user status immich-machine-learning.service
systemctl --user status immich-postgres.service
systemctl --user status immich-redis.service

# Quick pod status
podman ps --filter "name=immich" --format "table {{.Names}}\t{{.Status}}\t{{.State}}"

# Check for recent restarts (important!)
podman ps -a --filter "name=immich" --format "table {{.Names}}\t{{.Status}}\t{{.RunningFor}}"
```

**Expected:** All 4 services running, no recent unexpected restarts.
**Red flag:** Services restarted in last 24 hours without user action.

#### 1.2 Storage Mount Verification
```bash
# Verify BTRFS pool is mounted
mount | grep btrfs-pool

# Check Immich data directories exist and are not empty
ls -lah /mnt/btrfs-pool/subvol7-containers/immich/
ls -lah /mnt/btrfs-pool/subvol7-containers/immich/upload/
ls -lah /mnt/btrfs-pool/subvol7-containers/immich/upload/library/

# Count files in upload directory (should have 4,223+ files)
find /mnt/btrfs-pool/subvol7-containers/immich/upload/ -type f | wc -l

# Check volume mounts inside container
podman exec immich df -h
podman inspect immich --format '{{range .Mounts}}{{.Source}} -> {{.Destination}} ({{.Type}}){{"\n"}}{{end}}'
```

**Expected:**
- BTRFS pool mounted
- Upload directory contains ~4,223 files
- Container mounts correct paths

**Red flags:**
- Upload directory empty or missing
- Wrong paths mounted
- Mount points not accessible

#### 1.3 Database Quick Check
```bash
# Connect to PostgreSQL
podman exec -it immich-postgres psql -U immich -d immich

# Count assets in database
SELECT COUNT(*) FROM assets;

# Check for orphaned assets (files exist but not in DB)
SELECT COUNT(*) FROM assets WHERE "isOffline" = true;

# Check user libraries
SELECT id, email, "createdAt" FROM users;
SELECT "userId", COUNT(*) as asset_count FROM assets GROUP BY "userId";

# Exit
\q
```

**Expected:** Asset count matches 4,223.
**Red flags:**
- Asset count is 0 (database loss)
- All assets marked as "isOffline"
- User table empty

---

### Phase 2: Log Analysis (10 minutes)

**Goal:** Identify what happened overnight.

#### 2.1 System Journal Review
```bash
# Check for errors in last 24 hours
journalctl --user --since "24 hours ago" | grep -i "immich\|postgres\|error\|fail" | less

# Immich service logs
journalctl --user -u immich.service --since "24 hours ago" --no-pager

# PostgreSQL logs
journalctl --user -u immich-postgres.service --since "24 hours ago" --no-pager

# Machine learning service logs
journalctl --user -u immich-machine-learning.service --since "24 hours ago" --no-pager
```

**Look for:**
- Database migration messages
- Volume mount failures
- Permission errors
- Crash/restart events
- "schema migration" or "database upgrade"

#### 2.2 Container Logs Deep Dive
```bash
# Immich server logs (last 500 lines)
podman logs immich --tail 500 | grep -i "error\|warn\|migration\|database"

# PostgreSQL logs
podman logs immich-postgres --tail 200

# Redis logs (session issues?)
podman logs immich-redis --tail 100
```

**Red flags:**
- Database connection errors
- File system errors
- Migration failures
- "could not access file" messages

#### 2.3 Recent System Changes
```bash
# Check for Immich container image updates
podman images | grep immich

# Check systemd unit file modification times
ls -lah ~/.config/containers/systemd/immich*.container

# Check recent git commits (did we change something?)
git log --oneline --since="2 days ago" -- "*immich*"

# Check for BTRFS issues
sudo dmesg | grep -i "btrfs\|i/o error" | tail -50
```

---

### Phase 3: Database Deep Dive (15 minutes)

**Goal:** Understand database state and identify corruption or missing data.

#### 3.1 Database Integrity Check
```bash
podman exec -it immich-postgres psql -U immich -d immich
```

```sql
-- Check database size
SELECT pg_size_pretty(pg_database_size('immich'));

-- List all tables and row counts
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size,
    n_live_tup AS rows
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Check assets table schema (verify structure is intact)
\d assets

-- Sample 10 assets to see their state
SELECT
    id,
    "originalPath",
    "isOffline",
    "isVisible",
    "deletedAt",
    "createdAt"
FROM assets
LIMIT 10;

-- Check for deleted assets
SELECT COUNT(*) FROM assets WHERE "deletedAt" IS NOT NULL;

-- Check asset storage layout
SELECT
    COUNT(*) as count,
    "isOffline",
    "isVisible",
    "deletedAt" IS NOT NULL as is_deleted
FROM assets
GROUP BY "isOffline", "isVisible", "deletedAt" IS NOT NULL;

-- Check libraries
SELECT * FROM libraries;

-- Check storage templates
SELECT * FROM system_config WHERE key LIKE '%storage%';
```

**Hypotheses to test:**
1. Assets marked as deleted → Check `deletedAt` column
2. Assets marked offline → Check `isOffline` column
3. Assets marked invisible → Check `isVisible` column
4. Path corruption → Check `originalPath` values

#### 3.2 File-to-Database Reconciliation
```bash
# Exit psql first, then:

# Create temporary script to compare filesystem to database
cat > /tmp/check_immich_files.sh << 'EOF'
#!/bin/bash
echo "=== Filesystem Check ==="
echo "Files in upload directory:"
find /mnt/btrfs-pool/subvol7-containers/immich/upload/ -type f | wc -l

echo -e "\n=== Database Check ==="
echo "Assets in database:"
podman exec immich-postgres psql -U immich -d immich -t -c "SELECT COUNT(*) FROM assets;"

echo -e "\n=== Sample File Paths ==="
echo "First 5 files on disk:"
find /mnt/btrfs-pool/subvol7-containers/immich/upload/ -type f | head -5

echo -e "\n=== Sample Database Paths ==="
echo "First 5 originalPath values from DB:"
podman exec immich-postgres psql -U immich -d immich -t -c "SELECT \"originalPath\" FROM assets LIMIT 5;"
EOF

chmod +x /tmp/check_immich_files.sh
/tmp/check_immich_files.sh
```

**Critical question:** Do the database paths match the filesystem paths?

---

### Phase 4: Configuration Verification (10 minutes)

**Goal:** Verify container configuration hasn't changed.

#### 4.1 Quadlet Configuration Review
```bash
# Check current quadlet configuration
cat ~/.config/containers/systemd/immich.container
cat ~/.config/containers/systemd/immich-postgres.container

# Compare to git history (if tracked)
git diff HEAD -- ~/.config/containers/systemd/immich*.container

# Check environment variables
cat ~/containers/config/immich/.env
```

**Verify:**
- Volume mounts are correct
- `UPLOAD_LOCATION` environment variable
- `DB_HOSTNAME`, `DB_USERNAME`, `DB_PASSWORD`
- Network configuration

#### 4.2 Running Container Inspection
```bash
# Get actual running container configuration
podman inspect immich --format '{{json .Config.Env}}' | jq
podman inspect immich --format '{{json .Mounts}}' | jq

# Check if volumes are mounted read-only (should be rw)
podman inspect immich | grep -A 20 "Mounts"
```

**Red flag:** Volume mounted read-only or wrong source path.

---

### Phase 5: Immich API Health Check (5 minutes)

**Goal:** Test Immich API directly to bypass UI issues.

#### 5.1 API Server Health
```bash
# Check server info endpoint
curl -s http://localhost:2283/api/server/version | jq

# Check server stats (requires auth, so may fail)
curl -s http://localhost:2283/api/server/statistics | jq

# Check if server can see files
podman exec immich ls -lah /usr/src/app/upload/library/
```

#### 5.2 Check Immich Server Logs for API Errors
```bash
# Watch logs in real-time while accessing web UI
podman logs immich --tail 0 -f &
LOGS_PID=$!

# In another terminal, access photos.patriark.org
# Then stop log tail
kill $LOGS_PID
```

---

### Phase 6: Recovery Decision Tree

Based on findings, choose recovery path:

#### **Scenario A: Files exist, database empty**
**Cause:** Database wiped or migration failed
**Recovery:** Restore database from backup or re-scan library

```bash
# Check for database backups
ls -lah ~/containers/data/immich-backups/
ls -lah ~/containers/data/backup-logs/

# If backup exists, restore
# (Document specific restore steps based on backup method)

# If no backup, trigger library re-scan via API
# (This will rediscover files and rebuild metadata)
```

#### **Scenario B: Database intact, files missing**
**Cause:** Storage mount issue or file deletion
**Recovery:** Fix mount or restore files from backup

```bash
# Check BTRFS snapshots
sudo btrfs subvolume list /mnt/btrfs-pool/
sudo btrfs subvolume snapshot /mnt/btrfs-pool/subvol7-containers /mnt/btrfs-pool/subvol7-containers-recovery

# Restore from backup
# (Document specific restore steps)
```

#### **Scenario C: Database shows assets as "isOffline" or "deletedAt" set**
**Cause:** Immich job marked files as missing or deleted
**Recovery:** Update database to mark files as online and not deleted

```sql
-- CAUTION: Only run if diagnosis confirms this is the issue
-- Connect to database first
UPDATE assets SET "isOffline" = false WHERE "isOffline" = true;
UPDATE assets SET "isVisible" = true WHERE "isVisible" = false;
UPDATE assets SET "deletedAt" = NULL WHERE "deletedAt" IS NOT NULL;

-- Restart Immich after update
```

```bash
systemctl --user restart immich.service
```

#### **Scenario D: Path mismatch (database paths don't match filesystem)**
**Cause:** Container volume mount changed or UPLOAD_LOCATION variable changed
**Recovery:** Fix mount path or update database paths

```bash
# Fix container mount in quadlet file
nano ~/.config/containers/systemd/immich.container

# Then reload and restart
systemctl --user daemon-reload
systemctl --user restart immich.service
```

#### **Scenario E: Library deleted in Immich settings**
**Cause:** User or job accidentally deleted library
**Recovery:** Re-create library and trigger scan

```bash
# Check libraries in database
podman exec -it immich-postgres psql -U immich -d immich -c "SELECT * FROM libraries;"

# If library missing, may need to recreate via UI or API
# Document steps after investigation
```

---

### Phase 7: Prevention & Monitoring

#### 7.1 Immediate Safeguards
```bash
# Create BTRFS snapshot BEFORE any recovery attempts
sudo btrfs subvolume snapshot /mnt/btrfs-pool/subvol7-containers \
    /mnt/btrfs-pool/subvol7-containers-snapshot-$(date +%Y%m%d-%H%M%S)

# Export database backup
podman exec immich-postgres pg_dump -U immich immich > \
    ~/containers/data/immich-backups/immich-db-$(date +%Y%m%d-%H%M%S).sql
```

#### 7.2 Add Monitoring Alert
```bash
# Add Prometheus alert for asset count drop
# (To be implemented - alert if asset count drops by >10% in 24h)
```

#### 7.3 Document Findings
```bash
# After resolution, create incident report in docs/99-reports/
# Include:
# - Root cause
# - Timeline of events
# - Recovery steps taken
# - Prevention measures added
```

---

## Investigation Checklist

Use this checklist to track progress:

- [ ] Phase 1.1: Service health verified
- [ ] Phase 1.2: Storage mounts verified
- [ ] Phase 1.3: Database asset count checked
- [ ] Phase 2.1: System journal reviewed
- [ ] Phase 2.2: Container logs analyzed
- [ ] Phase 2.3: Recent changes identified
- [ ] Phase 3.1: Database integrity checked
- [ ] Phase 3.2: File-to-database reconciliation completed
- [ ] Phase 4.1: Quadlet configuration verified
- [ ] Phase 4.2: Running container inspected
- [ ] Phase 5.1: API health tested
- [ ] Phase 5.2: API logs captured
- [ ] Phase 6: Recovery scenario identified
- [ ] Phase 7.1: Safeguard snapshot created
- [ ] Recovery executed
- [ ] Services verified working
- [ ] Incident report created

---

## Expected Timeline

- **Phase 1-2 (Diagnosis):** 20 minutes
- **Phase 3-5 (Deep investigation):** 30 minutes
- **Phase 6 (Recovery):** 15-60 minutes depending on scenario
- **Phase 7 (Documentation):** 15 minutes

**Total estimated time:** 1.5 - 2 hours

---

## Critical Questions to Answer

1. **Did the container restart overnight?** (Check `podman ps` uptime)
2. **Are the files still on disk?** (Count files in upload directory)
3. **Does the database have asset records?** (SELECT COUNT from assets)
4. **Do database paths match filesystem paths?** (Compare originalPath to actual files)
5. **Were any Immich jobs run overnight?** (Check Immich admin > Jobs page)
6. **Did the storage mount fail?** (Check mount points)
7. **Did a database migration run?** (Check logs for migration messages)

---

## Emergency Contacts / Resources

- **Immich Documentation:** https://immich.app/docs/
- **Immich Discord:** https://discord.gg/immich (for urgent community help)
- **PostgreSQL Backup Location:** `~/containers/data/immich-backups/`
- **BTRFS Pool:** `/mnt/btrfs-pool/subvol7-containers/immich/`

---

## Notes Section

*Use this space during investigation to track findings:*

```
[Timestamp] Finding:


[Timestamp] Finding:


[Timestamp] Finding:


```

---

**Next Steps:** Execute Phase 1 immediately to establish current state.
