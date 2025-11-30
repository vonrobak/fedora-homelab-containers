# Practical Guide: Multi-Service Stack Deployment

**New Capability:** Deploy entire application stacks (Immich, monitoring, etc.) atomically with dependency resolution

**Created:** 2025-11-18
**Implements:** Session 5A - Multi-Service Orchestration
**Skill Level:** Intermediate

---

## What You Can Do Now

### Before (Manual Pain)
```bash
# Deploy Immich manually - 40-60 minutes, error-prone
podman run ... immich-postgres    # Wait... is it ready?
podman run ... immich-redis        # Wait... is it ready?
podman run ... immich-server       # ERROR! Database not ready
# Manual cleanup, retry, frustration...
```

### After (Automated Stack)
```bash
# Deploy Immich stack - 8-10 minutes, fully automated
cd ~/containers/.claude/skills/homelab-deployment
./scripts/deploy-stack.sh --stack immich

# System automatically:
# - Resolves dependencies (postgres + redis first)
# - Deploys in phases (parallel where possible)
# - Waits for health checks
# - Rolls back on failure
```

---

## Quick Start (5 Minutes)

### 1. Test with Simple Stack

```bash
cd ~/containers/.claude/skills/homelab-deployment

# See what will happen (dry-run)
./scripts/deploy-stack.sh --stack test-simple --dry-run

# Deploy test stack (creates 2 services: redis-a, redis-b)
./scripts/deploy-stack.sh --stack test-simple

# Check deployment
systemctl --user status redis-a.service redis-b.service

# Clean up test
systemctl --user stop redis-a.service redis-b.service
podman rm -f redis-a redis-b
```

**What you learned:**
- ✅ Dry-run mode shows deployment plan
- ✅ Automatic service creation and health checking
- ✅ Deployment logs in `~/containers/data/deployment-logs/`

### 2. Visualize Dependencies

```bash
# See how services depend on each other
./scripts/resolve-dependencies.sh --stack stacks/immich.yml --visualize

# Output shows:
# - Phase 1: immich-postgres, immich-redis (parallel)
# - Phase 2: immich-server (depends on postgres + redis)
# - Phase 3: immich-ml, immich-web (parallel, depend on server)
```

### 3. Deploy Real Stack

```bash
# Deploy monitoring stack (Prometheus + Grafana)
./scripts/deploy-stack.sh --stack monitoring-simple

# Watch deployment progress
tail -f ~/containers/data/deployment-logs/stack-monitoring-simple-*.log

# Verify services
systemctl --user status prometheus.service grafana.service
podman ps | grep -E 'prometheus|grafana'
```

---

## Available Stacks

### immich.yml - Photo Management Platform
**Services:** 5 (postgres, redis, server, machine-learning, web)
**Memory:** ~6.5GB total
**Deployment Time:** 8-10 minutes
**Complexity:** High

```bash
# Deploy complete Immich stack
./scripts/deploy-stack.sh --stack immich

# Services deployed:
# - immich-postgres (1.5GB) - Photo database
# - immich-redis (512MB) - Job queue
# - immich-server (2GB) - Main application
# - immich-ml (2GB) - Machine learning (face detection)
# - immich-web (640MB) - Web interface
```

**Prerequisites:**
- Networks: systemd-reverse_proxy, systemd-photos, systemd-monitoring
- Storage: /mnt/btrfs-pool/subvol7-containers/immich/
- Environment variables: IMMICH_DB_PASSWORD, IMMICH_REDIS_PASSWORD

### monitoring-simple.yml - Observability Stack
**Services:** 2 (Prometheus, Grafana)
**Memory:** ~1.5GB total
**Deployment Time:** 3-4 minutes
**Complexity:** Low

```bash
# Deploy monitoring stack
./scripts/deploy-stack.sh --stack monitoring-simple

# Services deployed:
# - prometheus (1GB) - Metrics collection
# - grafana (512MB) - Visualization dashboard
```

**Use case:** Basic monitoring without Loki/Alertmanager

### test-*.yml - Testing/Learning
**Services:** 2-3 simple services
**Purpose:** Learn stack deployment safely

```bash
# Simple 2-service stack
./scripts/deploy-stack.sh --stack test-simple

# Parallel deployment (2 independent services)
./scripts/deploy-stack.sh --stack test-parallel

# Cycle detection test (intentional circular dependency)
./scripts/deploy-stack.sh --stack test-cycle  # Should fail gracefully
```

---

## Common Workflows

### Workflow 1: Deploy New Application Stack

**Scenario:** You want to deploy a new multi-service app (e.g., Nextcloud)

**Steps:**
```bash
# 1. Create stack definition
cd ~/containers/.claude/skills/homelab-deployment/stacks
cp monitoring-simple.yml nextcloud.yml

# 2. Edit stack definition
nano nextcloud.yml
# Define services: nextcloud-db, nextcloud-redis, nextcloud-app

# 3. Validate stack (dry-run)
cd ..
./scripts/deploy-stack.sh --stack nextcloud --dry-run

# 4. Check dependency resolution
./scripts/resolve-dependencies.sh --stack stacks/nextcloud.yml --visualize

# 5. Deploy for real
./scripts/deploy-stack.sh --stack nextcloud

# 6. Monitor deployment
tail -f ~/containers/data/deployment-logs/stack-nextcloud-*.log

# 7. Verify services
systemctl --user status nextcloud-*.service
```

### Workflow 2: Rollback Failed Deployment

**Scenario:** Stack deployment fails partway through

**What happens automatically:**
```bash
# Deploy fails at immich-server (postgres deployed, redis deployed)
./scripts/deploy-stack.sh --stack immich

# Automatic rollback:
# [ERROR] immich-server failed health check
# [ROLLBACK] Stopping immich-redis...
# [ROLLBACK] Stopping immich-postgres...
# [ROLLBACK] Complete. System restored to pre-deployment state.
```

**Manual verification:**
```bash
# Check what's running (should be nothing from failed stack)
systemctl --user list-units | grep immich

# Check logs to see what failed
tail -50 ~/containers/data/deployment-logs/stack-immich-*.log

# Fix issue (e.g., missing password variable)
export IMMICH_DB_PASSWORD="your-secure-password"

# Retry deployment
./scripts/deploy-stack.sh --stack immich
```

### Workflow 3: Update Existing Stack

**Scenario:** Update image versions or configuration for deployed stack

**Steps:**
```bash
# 1. Edit stack definition
cd ~/containers/.claude/skills/homelab-deployment/stacks
nano immich.yml
# Change: image: docker.io/altran1502/immich-server:v1.90.0
# To:     image: docker.io/altran1502/immich-server:v1.91.0

# 2. Stop existing services
systemctl --user stop immich-*.service

# 3. Redeploy stack
cd ..
./scripts/deploy-stack.sh --stack immich

# 4. Verify new version
podman inspect immich-server | grep -i image
```

**Alternative (safer):**
```bash
# Deploy to test environment first
./scripts/deploy-stack.sh --stack immich --dry-run
# Review changes, then deploy
```

---

## Advanced Usage

### Custom Stack Definition Template

```yaml
---
# my-app.yml
stack:
  name: my-app
  description: "My custom application stack"
  version: "1.0"

shared:
  networks:
    - systemd-reverse_proxy
    - systemd-my-app
  resources:
    total_memory_mb: 4096
  domain: my-app.patriark.org

services:
  # Database (deploys first, no dependencies)
  - name: my-app-db
    pattern: database-service
    dependencies: []  # Empty = Phase 1
    configuration:
      image: docker.io/library/postgres:16-alpine
      memory: 1024M
      environment:
        POSTGRES_USER: myapp
        POSTGRES_PASSWORD: "${MYAPP_DB_PASSWORD}"
        POSTGRES_DB: myapp
      volumes:
        - /mnt/btrfs-pool/subvol7-containers/my-app/db:/var/lib/postgresql/data:Z
      networks:
        - systemd-my-app
      healthcheck:
        test: ["CMD-SHELL", "pg_isready -U myapp"]
        interval: 30s
        timeout: 10s
        retries: 5
    ready_criteria:
      type: healthcheck
      timeout: 120s

  # Application (depends on database)
  - name: my-app-server
    pattern: web-app-with-database
    dependencies:
      - my-app-db  # Waits for database to be healthy
    configuration:
      image: docker.io/myorg/my-app:latest
      memory: 2048M
      environment:
        DATABASE_URL: "postgresql://myapp:${MYAPP_DB_PASSWORD}@my-app-db:5432/myapp"
      networks:
        - systemd-my-app
        - systemd-reverse_proxy
      healthcheck:
        test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
        interval: 30s
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.my-app.rule=Host(`my-app.patriark.org`)"
    ready_criteria:
      type: healthcheck
      timeout: 180s
```

### Dependency Visualization

```bash
# Generate GraphViz diagram
./scripts/resolve-dependencies.sh \
  --stack stacks/immich.yml \
  --visualize > immich-deps.dot

# Convert to PNG (requires graphviz package)
dot -Tpng immich-deps.dot -o immich-deps.png

# View diagram
xdg-open immich-deps.png
```

**What the diagram shows:**
- Nodes: Services (colored by phase)
- Edges: Dependencies (arrows point from dependency to dependent)
- Phases: Services that can deploy in parallel

### Parallel Deployment Analysis

```bash
# See how many phases are needed
./scripts/resolve-dependencies.sh --stack stacks/immich.yml

# Output:
# Phase 1 (parallel): immich-postgres, immich-redis
# Phase 2: immich-server
# Phase 3 (parallel): immich-ml, immich-web
#
# Total phases: 3
# Estimated time: Phase 1 (2min) + Phase 2 (3min) + Phase 3 (3min) = 8min
```

---

## Troubleshooting

### Issue: Stack Fails During Deployment

**Symptoms:**
```
[ERROR] Service immich-server failed health check after 180s
[ROLLBACK] Initiated...
```

**Diagnosis:**
```bash
# 1. Check deployment log
tail -100 ~/containers/data/deployment-logs/stack-immich-*.log

# 2. Check service logs
journalctl --user -u immich-server.service -n 50

# 3. Check container logs
podman logs immich-server --tail 50

# 4. Verify dependencies are healthy
podman healthcheck run immich-postgres
podman healthcheck run immich-redis
```

**Common causes:**
- Missing environment variables (IMMICH_DB_PASSWORD, etc.)
- Network not created (systemd-photos.network)
- Insufficient memory
- Database not ready (extend healthcheck timeout)

### Issue: Circular Dependency Detected

**Symptoms:**
```
[ERROR] Circular dependency detected:
  service-a → service-b → service-c → service-a
```

**Diagnosis:**
```bash
# Visualize dependencies to find cycle
./scripts/resolve-dependencies.sh \
  --stack stacks/my-app.yml \
  --visualize
```

**Solution:**
Break the cycle by removing one dependency or reordering service initialization

### Issue: Deployment Hangs on Health Check

**Symptoms:**
```
[INFO] Waiting for immich-server to be healthy...
[INFO] Attempt 1/30...
[INFO] Attempt 2/30...
... (stuck)
```

**Diagnosis:**
```bash
# Check if service is actually running
podman ps | grep immich-server

# Check health check command
podman inspect immich-server | grep -A 10 Healthcheck

# Test health check manually
podman exec immich-server curl -f http://localhost:3001/health
```

**Solutions:**
- Increase `ready_criteria.timeout` in stack definition
- Fix health check command
- Check if service is actually starting (logs)

---

## Best Practices

### 1. Always Dry-Run First

```bash
# GOOD: See what will happen
./scripts/deploy-stack.sh --stack my-app --dry-run
# Review output, then deploy
./scripts/deploy-stack.sh --stack my-app

# BAD: Deploy blindly
./scripts/deploy-stack.sh --stack my-app  # Hope it works!
```

### 2. Use Environment Variables for Secrets

```yaml
# GOOD: Stack definition
environment:
  DATABASE_PASSWORD: "${MYAPP_DB_PASSWORD}"

# GOOD: Shell
export MYAPP_DB_PASSWORD="$(pwgen -s 32 1)"
./scripts/deploy-stack.sh --stack my-app

# BAD: Hardcoded in stack file
environment:
  DATABASE_PASSWORD: "hunter2"  # Don't do this!
```

### 3. Start Small, Scale Up

```bash
# Learn with simple stacks first
./scripts/deploy-stack.sh --stack test-simple      # 2 services
./scripts/deploy-stack.sh --stack monitoring-simple # 2 services

# Then tackle complex stacks
./scripts/deploy-stack.sh --stack immich           # 5 services
```

### 4. Monitor Deployments

```bash
# Start deployment in one terminal
./scripts/deploy-stack.sh --stack immich

# Monitor logs in another terminal
tail -f ~/containers/data/deployment-logs/stack-immich-*.log

# Check service status in third terminal
watch -n 2 'systemctl --user list-units | grep immich'
```

### 5. Document Custom Stacks

```yaml
# Add clear comments to your stack definitions
---
# my-app.yml
# Custom application stack for XYZ project
#
# Services: 3 (database, cache, application)
# Deployment order:
#   Phase 1 (parallel): my-app-db, my-app-redis
#   Phase 2: my-app-server
#
# Prerequisites:
#   - Networks: systemd-my-app.network created
#   - Environment: MYAPP_DB_PASSWORD set
#   - Storage: /mnt/btrfs-pool/subvol7-containers/my-app/ exists
#
# Total memory: ~3GB
# Estimated deployment time: 5-7 minutes
```

---

## Integration with Existing Tools

### With Context Framework

```bash
# After stack deployment, record it
cd ~/containers/.claude/context/scripts
nano build-deployment-log.sh

# Add entries for each service in stack
add_deployment "immich-postgres" "2025-11-18" "database-service" \
  "1536M" "systemd-photos,systemd-monitoring" \
  "Part of Immich stack - photo database" "stack-based"

# Regenerate deployment log
./build-deployment-log.sh

# Query deployments
./query-deployments.sh --method stack-based
```

### With Drift Detection

```bash
# Check if deployed services match patterns
cd ~/containers/.claude/skills/homelab-deployment/scripts
./check-drift.sh immich-postgres
./check-drift.sh immich-server

# Auto-reconcile if drift detected
cd ~/containers/.claude/remediation/scripts
./apply-remediation.sh --playbook drift-reconciliation --service immich-postgres
```

### With Monitoring

```bash
# Stack deployments include Prometheus labels automatically
# Check metrics collection
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job | contains("immich"))'

# Create Grafana dashboard for stack
# - Group all immich-* services
# - Show health status, resource usage
# - Alert if any service unhealthy
```

---

## Learning Resources

**Stack definitions:**
- `stacks/test-simple.yml` - Minimal example (2 services)
- `stacks/test-parallel.yml` - Parallel deployment
- `stacks/monitoring-simple.yml` - Real-world 2-service stack
- `stacks/immich.yml` - Complex 5-service stack

**Scripts:**
- `scripts/deploy-stack.sh` - Main orchestration engine (794 lines)
- `scripts/resolve-dependencies.sh` - Dependency resolution (317 lines)

**Documentation:**
- `STACK-GUIDE.md` - Complete reference (585 lines)

**Practice exercises:**
1. Deploy test-simple stack
2. Create custom 2-service stack (db + app)
3. Visualize dependencies
4. Intentionally break health check, observe rollback
5. Deploy monitoring-simple stack
6. Deploy immich stack (if resources allow)

---

## Next Steps

**Beginner:**
1. Run `./scripts/deploy-stack.sh --stack test-simple --dry-run`
2. Deploy test-simple stack
3. Explore deployment logs
4. Clean up test stack

**Intermediate:**
1. Create custom stack definition for Redis + app
2. Deploy monitoring-simple stack
3. Integrate with Context Framework
4. Monitor stack health in Grafana

**Advanced:**
1. Deploy immich stack
2. Create custom stack for new application
3. Add custom health checks
4. Optimize parallel deployment phases

---

**Bottom Line:** Stack deployment transforms 40-60 minute manual processes into 8-10 minute automated deployments with dependency resolution, health checking, and automatic rollback.

**Key Advantage:** Deploy complex applications (Immich, Nextcloud, etc.) as easily as single services.

---

**Created:** 2025-11-18
**Version:** 1.0
**Maintainer:** patriark
**Session:** 5A - Multi-Service Orchestration
