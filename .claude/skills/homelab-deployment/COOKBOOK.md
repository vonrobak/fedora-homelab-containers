# Deployment Cookbook

**Quick recipes for common deployment tasks**

**Last Updated:** 2025-11-14

---

## Recipe Index

1. [Deploy Media Server (Jellyfin)](#recipe-1-deploy-media-server)
2. [Deploy Database for Application](#recipe-2-deploy-database)
3. [Deploy Redis Cache](#recipe-3-deploy-redis-cache)
4. [Deploy Web Application with Database](#recipe-4-deploy-web-application)
5. [Check System Health](#recipe-5-check-system-health)
6. [Detect Configuration Drift](#recipe-6-detect-configuration-drift)
7. [Fix Drifted Service](#recipe-7-fix-drifted-service)
8. [Change Service Memory Limit](#recipe-8-change-service-memory)
9. [Add Service to Additional Network](#recipe-9-add-network)
10. [Remove Service](#recipe-10-remove-service)

---

## Recipe 1: Deploy Media Server

**Goal:** Deploy Jellyfin with GPU transcoding

**Time:** 5 minutes

```bash
# 1. Check system health
./scripts/homelab-intel.sh

# 2. Deploy using pattern
cd .claude/skills/homelab-deployment
./scripts/deploy-from-pattern.sh \
  --pattern media-server-stack \
  --service-name jellyfin \
  --hostname jellyfin.patriark.org \
  --memory 4G

# 3. Add GPU access (optional)
nano ~/.config/containers/systemd/jellyfin.container
# Add under [Container]:
# AddDevice=/dev/dri/renderD128

# 4. Apply GPU change
systemctl --user daemon-reload
systemctl --user restart jellyfin.service

# 5. Test access
curl https://jellyfin.patriark.org
```

**Expected:** Service accessible at jellyfin.patriark.org with Authelia login

---

## Recipe 2: Deploy Database

**Goal:** Deploy PostgreSQL for an application

**Time:** 3 minutes

**CRITICAL:** BTRFS NOCOW must be set BEFORE first database start

```bash
# 1. Create data directory with NOCOW
mkdir -p /mnt/btrfs-pool/subvol7-containers/myapp-db/data
chattr +C /mnt/btrfs-pool/subvol7-containers/myapp-db/data

# 2. Verify NOCOW set
lsattr -d /mnt/btrfs-pool/subvol7-containers/myapp-db/data
# Should show: ---------------C---

# 3. Generate secure password
DB_PASSWORD=$(openssl rand -base64 32)
echo "Database password: $DB_PASSWORD"  # Save this!

# 4. Deploy database
cd .claude/skills/homelab-deployment
./scripts/deploy-from-pattern.sh \
  --pattern database-service \
  --service-name myapp-db \
  --memory 2G \
  --var db_type=postgres \
  --var db_user=myapp \
  --var db_password="$DB_PASSWORD"

# 5. Test connection
podman exec myapp-db psql -U myapp -c '\l'
```

**Expected:** Database running, accessible on systemd-myapp_services network

---

## Recipe 3: Deploy Redis Cache

**Goal:** Deploy Redis for session storage or caching

**Time:** 2 minutes

```bash
# 1. Generate password
REDIS_PASSWORD=$(openssl rand -base64 32)
echo "Redis password: $REDIS_PASSWORD"

# 2. Deploy
cd .claude/skills/homelab-deployment
./scripts/deploy-from-pattern.sh \
  --pattern cache-service \
  --service-name myapp-redis \
  --memory 512M \
  --var redis_password="$REDIS_PASSWORD"

# 3. Test
podman exec myapp-redis redis-cli -a "$REDIS_PASSWORD" ping
# Should return: PONG
```

**Expected:** Redis running on systemd-myapp_services network

---

## Recipe 4: Deploy Web Application

**Goal:** Deploy Wiki.js with PostgreSQL database

**Time:** 10 minutes

```bash
# 1. Create app-specific network
podman network create systemd-wiki_services

# 2. Deploy database (see Recipe 2)
# Use service-name wiki-db, save DB_PASSWORD

# 3. Deploy application
cd .claude/skills/homelab-deployment
./scripts/deploy-from-pattern.sh \
  --pattern web-app-with-database \
  --service-name wiki \
  --hostname wiki.patriark.org \
  --memory 2G

# 4. Configure database connection
nano ~/.config/containers/systemd/wiki.container
# Add environment variables:
# Environment=DB_HOST=wiki-db
# Environment=DB_USER=wiki
# Environment=DB_PASS=$DB_PASSWORD

# 5. Connect to database network
podman network connect systemd-wiki_services wiki

# 6. Restart
systemctl --user daemon-reload
systemctl --user restart wiki.service

# 7. Test
curl https://wiki.patriark.org
```

**Expected:** Wiki accessible at wiki.patriark.org, connected to database

---

## Recipe 5: Check System Health

**Goal:** Assess system readiness for deployment

**Time:** 1 minute

```bash
# Run intelligence scan
./scripts/homelab-intel.sh

# Quick interpretation:
# Health 90-100: Excellent, deploy anything
# Health 75-89:  Good, proceed with monitoring
# Health 50-74:  Degraded, fix warnings first
# Health 0-49:   Critical, address issues immediately

# View latest report
cat docs/99-reports/intel-*.json | tail -1 | jq .

# Check specific metrics
cat docs/99-reports/intel-*.json | tail -1 | jq .metrics
```

**Expected:** Health score and actionable recommendations

---

## Recipe 6: Detect Configuration Drift

**Goal:** Find services with configuration mismatches

**Time:** 1 minute

```bash
# Check all services
cd .claude/skills/homelab-deployment
./scripts/check-drift.sh

# Check specific service with details
./scripts/check-drift.sh jellyfin --verbose

# Generate JSON report
./scripts/check-drift.sh --json --output drift-$(date +%Y%m%d).json
```

**Interpretation:**
- ✓ MATCH: Service configuration correct
- ✗ DRIFT: Service needs restart to apply quadlet changes
- ⚠ WARNING: Minor difference, likely intentional

**Expected:** List of services with drift status

---

## Recipe 7: Fix Drifted Service

**Goal:** Reconcile service to match quadlet definition

**Time:** 2 minutes

```bash
# 1. Identify drift
cd .claude/skills/homelab-deployment
./scripts/check-drift.sh jellyfin

# 2. Review what changed
cat ~/.config/containers/systemd/jellyfin.container

# 3. Restart to apply quadlet
systemctl --user restart jellyfin.service

# 4. Verify drift resolved
./scripts/check-drift.sh jellyfin
# Should show: MATCH

# 5. Check service still works
systemctl --user status jellyfin.service
curl https://jellyfin.patriark.org
```

**Expected:** Service matches quadlet, no drift

---

## Recipe 8: Change Service Memory

**Goal:** Increase memory limit for service

**Time:** 2 minutes

```bash
# 1. Edit quadlet
nano ~/.config/containers/systemd/jellyfin.container

# 2. Modify [Service] section
# Change:
# Memory=2G
# MemoryHigh=1.5G
# To:
# Memory=4G
# MemoryHigh=3G

# 3. Apply changes
systemctl --user daemon-reload
systemctl --user restart jellyfin.service

# 4. Verify new limit
podman inspect jellyfin | grep -i memory

# 5. Check drift (should show MATCH)
cd .claude/skills/homelab-deployment
./scripts/check-drift.sh jellyfin
```

**Expected:** Service using new memory limit

---

## Recipe 9: Add Network

**Goal:** Connect service to additional network

**Time:** 2 minutes

```bash
# 1. Create network if needed
podman network create systemd-myapp_services

# 2. Connect running container
podman network connect systemd-myapp_services jellyfin

# 3. Update quadlet for persistence
nano ~/.config/containers/systemd/jellyfin.container
# Add line:
# Network=systemd-myapp_services.network

# 4. Verify connection
podman inspect jellyfin | grep -i network

# 5. Test connectivity
podman exec jellyfin ping -c 1 myapp-db
```

**Expected:** Service on multiple networks

**Note:** First network in quadlet gets default route (internet access)

---

## Recipe 10: Remove Service

**Goal:** Completely remove a service

**Time:** 3 minutes

```bash
# 1. Stop service
systemctl --user stop jellyfin.service

# 2. Disable service
systemctl --user disable jellyfin.service

# 3. Remove container
podman rm jellyfin

# 4. Remove quadlet
rm ~/.config/containers/systemd/jellyfin.container

# 5. Remove data (CAREFUL!)
# Verify path first!
ls -la ~/containers/data/jellyfin
rm -rf ~/containers/data/jellyfin

# 6. Reload systemd
systemctl --user daemon-reload

# 7. Verify removal
podman ps -a | grep jellyfin  # Should be empty
systemctl --user status jellyfin.service  # Should error
```

**Expected:** Service completely removed from system

---

## Common Workflows

### Health → Deploy → Verify

```bash
# 1. Check system ready
./scripts/homelab-intel.sh

# 2. Deploy service
cd .claude/skills/homelab-deployment
./scripts/deploy-from-pattern.sh --pattern <pattern> --service-name <name> --memory <size>

# 3. Verify deployment
./scripts/check-drift.sh <name>
systemctl --user status <name>.service
curl https://<hostname>
```

### Debug → Fix → Test

```bash
# 1. Check service status
systemctl --user status <name>.service
podman logs <name> --tail 50

# 2. Check for drift
cd .claude/skills/homelab-deployment
./scripts/check-drift.sh <name>

# 3. If drifted, restart
systemctl --user restart <name>.service

# 4. If still broken, check logs again
journalctl --user -u <name>.service -n 100
```

### Audit → Reconcile → Document

```bash
# 1. Run full drift check
cd .claude/skills/homelab-deployment
./scripts/check-drift.sh > drift-report.txt

# 2. Review drifted services
cat drift-report.txt | grep -E "(DRIFT|WARNING)"

# 3. Reconcile each
for service in $(cat drift-report.txt | grep "DRIFT" | awk '{print $2}'); do
  systemctl --user restart $service
done

# 4. Verify all fixed
./scripts/check-drift.sh
```

---

## Troubleshooting Quick Reference

### Service Won't Start

```bash
# Check logs
journalctl --user -u <service>.service -n 50

# Check quadlet syntax
systemctl --user cat <service>.service

# Reload and retry
systemctl --user daemon-reload
systemctl --user start <service>.service
```

### Service Not Accessible Externally

```bash
# Check Traefik dashboard
# Navigate to traefik.patriark.org/dashboard

# Check Traefik logs
podman logs traefik | grep <service-name>

# Check Traefik labels
podman inspect <service> | grep -i traefik

# Check DNS
dig <hostname>.patriark.org
```

### Database Slow Performance

```bash
# Check NOCOW attribute
lsattr -d /mnt/btrfs-pool/subvol7-containers/<db>/data
# Should show 'C' flag

# If missing, set NOCOW (MUST be empty directory)
chattr +C /path/to/data

# Check fragmentation
sudo btrfs filesystem defragment /mnt/btrfs-pool/subvol7-containers/<db>/data
```

### High Disk Usage

```bash
# Check what's using space
du -sh ~/containers/* | sort -h
du -sh ~/.local/share/containers/* | sort -h

# Clean up
podman system prune -f
journalctl --user --vacuum-time=7d
```

---

## Pattern Selection Cheat Sheet

| I want to deploy... | Use this pattern |
|---------------------|------------------|
| Jellyfin, Plex | media-server-stack |
| Wiki, blog, CMS | web-app-with-database |
| Paperless-ngx | document-management |
| Authelia | authentication-stack |
| Vaultwarden | password-manager |
| PostgreSQL, MySQL | database-service |
| Redis, Memcached | cache-service |
| Internal admin panel | reverse-proxy-backend |
| Metrics exporter | monitoring-exporter |

**Still not sure?** See `docs/10-services/guides/pattern-selection-guide.md`

---

## Next Steps

After mastering these recipes:
- Review pattern files: `cat .claude/skills/homelab-deployment/patterns/<pattern>.yml`
- Understand skill integration: `cat docs/10-services/guides/skill-integration-guide.md`
- Create custom patterns based on your needs
- Automate routine checks (weekly health + drift)

**Need help?** Claude Code can invoke these skills automatically. Just describe what you want to deploy.
