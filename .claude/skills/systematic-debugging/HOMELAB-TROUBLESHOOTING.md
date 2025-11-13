# Homelab Systematic Troubleshooting

Integration of systematic-debugging methodology with homelab infrastructure troubleshooting.

## Homelab-Specific Application

The core systematic-debugging process (4 phases) applies directly to homelab issues, but with infrastructure-specific adaptations.

## When to Use in Homelab Context

**Always use for:**
- Services failing to start (`systemctl --user status <service>.service`)
- Containers in unhealthy state
- Network connectivity issues between services
- Traefik routing problems (502/503 errors)
- Monitoring stack failures (Prometheus, Grafana, Loki)
- Backup script failures
- Disk space mysteries
- Performance degradation

**Especially critical for:**
- Production services down (Jellyfin, Authelia, Traefik)
- Security stack issues (CrowdSec, Authelia)
- Multi-service dependencies (monitoring stack)

## Phase 1: Root Cause Investigation (Homelab Edition)

### 1. Read Error Messages from Homelab Sources

**Service logs:**
```bash
# systemd journal (most detailed)
journalctl --user -u <service>.service -n 100

# Podman container logs
podman logs <container> --tail 100

# Follow logs in real-time
journalctl --user -u <service>.service -f
```

**Common error patterns:**
- `Permission denied` → Check `:Z` labels on volume mounts
- `Address already in use` → Port conflict, check with `ss -tulnp`
- `Network not found` → Check network exists: `podman network ls`
- `Unable to find image` → Check image name/tag
- `Failed to create container` → Usually quadlet syntax error

### 2. Reproduce Consistently

**For services:**
```bash
# Can you trigger failure reliably?
systemctl --user restart <service>.service
systemctl --user status <service>.service

# Check health
podman healthcheck run <container>

# Manual service test
curl -I http://localhost:<port>/
```

**For Traefik routing:**
```bash
# Test from inside system
curl -I https://service.patriark.org

# Check Traefik logs for routing
podman logs traefik | grep -i error

# Verify route exists in dashboard
# http://localhost:8080/dashboard/
```

###3. Check Recent Changes

**Homelab-specific:**
```bash
# Git history
git log --oneline -10
git diff HEAD~1

# Systemd service changes
systemctl --user list-units --state=failed

# Recent quadlet changes
git log --oneline -- .config/containers/systemd/

# Recent config changes
git log --oneline -- config/
```

### 4. Gather Evidence in Multi-Component Systems

**Homelab has many multi-component flows:**

**Example: Jellyfin Accessibility Issue**
```
User → Internet → Router → fedora-htpc
  → Traefik (reverse proxy)
  → Authelia (SSO)
  → Jellyfin (media server)
```

**Diagnostic instrumentation:**
```bash
# Layer 1: External accessibility
curl -I https://jellyfin.patriark.org
# Expected: 302 redirect to Authelia OR 200 OK

# Layer 2: Traefik routing
podman logs traefik | tail -20
# Check for: Router matched, middleware executed

# Layer 3: Authelia authentication
podman logs authelia | tail -20
systemctl --user status authelia.service

# Layer 4: Jellyfin service
systemctl --user status jellyfin.service
podman healthcheck run jellyfin

# Layer 5: Network connectivity
podman network inspect systemd-reverse_proxy | grep jellyfin
podman network inspect systemd-auth_services | grep authelia
```

**This reveals:** Which layer fails (e.g., Traefik → Authelia works, Authelia → Jellyfin fails)

### 5. Trace Data Flow (Homelab Services)

**Example: Prometheus can't scrape service**

```bash
# Symptom: Prometheus shows target DOWN

# Trace backward:
# 1. Can Prometheus reach service network?
podman network inspect systemd-monitoring | grep prometheus

# 2. Is service on monitoring network?
podman network inspect systemd-monitoring | grep <service>

# 3. Is service exposing metrics port?
podman port <service>

# 4. Can you curl metrics from Prometheus container?
podman exec prometheus curl http://<service>:<port>/metrics

# 5. Check Prometheus config
cat config/prometheus/prometheus.yml | grep -A 5 <service>
```

## Phase 2: Pattern Analysis (Homelab Edition)

### 1. Find Working Examples

**In this homelab:**
```bash
# Find similar working service
ls ~/.config/containers/systemd/*.container | grep -v <broken>

# Compare quadlet files
diff ~/.config/containers/systemd/jellyfin.container \
     ~/.config/containers/systemd/<broken>.container

# Find working Traefik route
grep -r "service-name" config/traefik/dynamic/
```

### 2. Compare Against References

**Homelab has documented patterns:**
- `CLAUDE.md` - Common commands and troubleshooting
- `docs/00-foundation/guides/configuration-design-quick-reference.md`
- `docs/00-foundation/guides/middleware-configuration.md`
- ADRs in `docs/*/decisions/`

**Always check:**
```bash
# Network naming convention
# Correct: systemd-reverse_proxy
# Wrong: reverse_proxy

# Volume mount labels
# Correct: ~/containers/config:/config:Z
# Wrong: ~/containers/config:/config (missing :Z)

# Middleware ordering (from CLAUDE.md)
# Correct: crowdsec → rate-limit → authelia → headers
# Wrong: authelia → crowdsec (fail-slow, not fail-fast)
```

### 3. Identify Differences

**Homelab-specific checks:**
```bash
# Network connections
podman inspect <working> | jq '.[] | .NetworkSettings.Networks | keys'
podman inspect <broken> | jq '.[] | .NetworkSettings.Networks | keys'

# Environment variables
podman inspect <working> | jq '.[] | .Config.Env'
podman inspect <broken> | jq '.[] | .Config.Env'

# Volume mounts
podman inspect <working> | jq '.[] | .Mounts'
podman inspect <broken> | jq '.[] | .Mounts'

# Labels (for Traefik discovery)
podman inspect <working> | jq '.[] | .Config.Labels'
podman inspect <broken> | jq '.[] | .Config.Labels'
```

## Phase 3: Hypothesis and Testing (Homelab Edition)

### Form Single Hypothesis

**Homelab examples:**
```
"I think Jellyfin can't start because it's not on systemd-reverse_proxy network"

"I think Traefik can't route because middleware name has wrong @file suffix"

"I think Prometheus can't scrape because service isn't on monitoring network"

"I think Authelia is failing because Redis session storage is down"
```

### Test Minimally

**Infrastructure-specific minimal changes:**
```bash
# Hypothesis: Network connection missing
podman network connect systemd-monitoring <service>
# Test
systemctl --user restart <service>.service

# Hypothesis: Wrong middleware reference
# Edit config/traefik/dynamic/routers.yml
# Change ONE middleware reference
# Test
systemctl --user restart traefik.service
curl -I https://service.patriark.org

# Hypothesis: SELinux blocking volume access
# Check with :Z label
# Edit quadlet, add :Z to ONE volume
systemctl --user daemon-reload
systemctl --user restart <service>.service
```

### When You Don't Know

**Homelab help resources:**
```bash
# Run comprehensive diagnostics
./scripts/homelab-diagnose.sh

# Get system intelligence
./scripts/homelab-intel.sh

# Check service-specific status
./scripts/jellyfin-status.sh

# Review documentation
cat CLAUDE.md | grep -A 20 "Troubleshooting"

# Check similar issues in git history
git log --all --grep="<error keyword>"
```

## Phase 4: Implementation (Homelab Edition)

### 1. Create Failing Test Case

**Homelab test examples:**
```bash
# Service health test
#!/bin/bash
systemctl --user is-active jellyfin.service || exit 1
curl -f http://localhost:8096/health || exit 1
echo "Jellyfin healthy"

# Traefik routing test
#!/bin/bash
curl -I https://jellyfin.patriark.org | grep -q "200\|302" || exit 1
echo "Jellyfin accessible"

# Prometheus scraping test
#!/bin/bash
curl -s http://localhost:9090/api/v1/targets | \
  jq '.data.activeTargets[] | select(.labels.job=="jellyfin") | .health' | \
  grep -q "up" || exit 1
echo "Jellyfin metrics scraped"
```

### 2. Implement Single Fix

**Infrastructure fixes:**
```bash
# Fix network connectivity
podman network connect systemd-monitoring service

# Fix volume mount
# Edit quadlet: Add :Z label to volume
systemctl --user daemon-reload
systemctl --user restart service.service

# Fix Traefik route
# Edit config/traefik/dynamic/routers.yml
# Fix middleware reference
# No restart needed - Traefik watches for changes

# Fix quadlet syntax
# Edit ~/.config/containers/systemd/service.container
systemctl --user daemon-reload
systemctl --user restart service.service
```

### 3. Verify Fix

**Homelab verification:**
```bash
# Service level
systemctl --user status service.service
podman healthcheck run service

# Application level
curl -f http://localhost:<port>/

# External level
curl -I https://service.patriark.org

# Monitoring level
# Check Prometheus targets: http://localhost:9090/targets
# Check Grafana dashboard

# Run test case created in step 1
./test-service-health.sh
```

### 4. If Fix Doesn't Work

**Count fixes attempted:**
- Fix #1 failed → Return to Phase 1, gather more evidence
- Fix #2 failed → Return to Phase 1, question assumptions
- **Fix #3 failed → STOP. Question the architecture**

**Common architectural problems in homelab:**
- Service doesn't belong on this network (consider separate network)
- Traefik middleware chain too complex (simplify)
- Service needs complete redesign (consult ADRs)
- Multiple services sharing state incorrectly

## Homelab Troubleshooting Workflows

### Service Won't Start

**Follow this diagnostic flow:**
```bash
# 1. Read error
journalctl --user -u service.service -n 50

# 2. Check quadlet syntax
cat ~/.config/containers/systemd/service.container

# 3. Reload systemd
systemctl --user daemon-reload

# 4. Try starting
systemctl --user start service.service

# 5. If still fails, check:
# - Network exists: podman network ls
# - Image exists: podman images
# - Volumes accessible: ls -la ~/containers/config/service/
# - Ports available: ss -tulnp | grep <port>
```

### Traefik Routing Issues

**Systematic diagnostic:**
```bash
# Phase 1: Evidence gathering
# 1. Check Traefik dashboard
# http://localhost:8080/dashboard/

# 2. Check logs
podman logs traefik | grep -i error

# 3. Test internal connectivity
podman exec traefik wget -qO- http://service:port/

# 4. Check route configuration
cat config/traefik/dynamic/*.yml | grep -A 10 "service-name"

# Phase 2: Pattern analysis
# Compare with working route
diff config/traefik/dynamic/jellyfin-router.yml \
     config/traefik/dynamic/broken-router.yml

# Phase 3: Hypothesis
# "Route exists but middleware is wrong"

# Phase 4: Test
# Edit route config, Traefik auto-reloads
curl -I https://service.patriark.org
```

### Monitoring Stack Issues

**Multi-service debugging:**
```bash
# All monitoring services must be healthy
systemctl --user status prometheus.service
systemctl --user status grafana.service
systemctl --user status loki.service
systemctl --user status promtail.service

# Check connectivity
podman exec prometheus wget -qO- http://grafana:3000/api/health
podman exec grafana curl http://prometheus:9090/-/healthy

# Check network
podman network inspect systemd-monitoring

# Verify all on same network
for service in prometheus grafana loki promtail; do
  echo "$service networks:"
  podman inspect $service | jq '.[] | .NetworkSettings.Networks | keys'
done
```

## Red Flags in Homelab Context

If you catch yourself thinking:
- "Just restart the service, it'll probably fix it"
- "Add more middleware, one will work"
- "Try changing the network to see what happens"
- "Comment out the health check for now"
- "Just use host network mode" (violates rootless principle)
- "Skip the :Z label, it's probably fine" (SELinux will block)
- "Force pull latest image without checking version" (breaks reproducibility)

**ALL mean: STOP. Return to Phase 1.**

## Integration with Homelab Scripts

**Use existing diagnostics:**
```bash
# Before investigating
./scripts/homelab-intel.sh  # Get system state
./scripts/homelab-snapshot.sh  # Create snapshot for comparison

# During investigation
./scripts/show-pod-status.sh  # Service overview
./scripts/jellyfin-status.sh  # Service-specific (if exists)

# After fix
./scripts/homelab-intel.sh  # Verify health score improved
```

## Documentation After Fix

**Per docs/CONTRIBUTING.md:**
```bash
# If fix requires configuration change:
# 1. Update relevant guide in docs/*/guides/
# 2. Create journal entry in docs/*/journal/
# 3. If architectural decision made, create ADR
# 4. Update CLAUDE.md troubleshooting if general pattern

# Commit with context
git add <files>
git commit -m "<service>: Fix <issue>

Root cause: <what was wrong>
Investigation: <how you found it>
Fix: <what you changed>

Tested:
- systemctl --user status <service> - Running
- Health check: OK
- <specific test>: Verified

Ref: docs/*/journal/YYYY-MM-DD-<description>.md"
```

---

**Integration Version:** 1.0
**Last Updated:** 2025-11-13
**References:** CLAUDE.md (Troubleshooting Workflow), systematic-debugging SKILL.md
