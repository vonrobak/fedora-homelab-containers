# Session 2 Validation Checklist

**Status:** 🚧 DRAFT - Requires CLI Testing
**Created:** Web Session (2025-11-14)
**Scripts to Validate:** 3 automation scripts

---

## Overview

Three automation scripts were created in Web session and need validation in CLI:

1. **deploy-service.sh** - Service deployment orchestration
2. **test-deployment.sh** - Post-deployment verification
3. **generate-docs.sh** - Documentation auto-generation

**Goal:** Validate each script works on real fedora-htpc system, then deploy test service end-to-end.

---

## Pre-Validation Setup

### 1. Verify Scripts Exist

```bash
cd ~/containers
git pull origin claude/code-web-planning-01HnMgvdLc4F9TV26WxYb3sk

# Verify scripts
ls -lh .claude/skills/homelab-deployment/scripts/

# Should show:
# - check-prerequisites.sh (from Session 1)
# - check-system-health.sh (from Session 1)
# - validate-quadlet.sh (from Session 1)
# - deploy-service.sh (NEW - Session 2)
# - test-deployment.sh (NEW - Session 2)
# - generate-docs.sh (NEW - Session 2)
```

### 2. Verify Executable Permissions

```bash
chmod +x .claude/skills/homelab-deployment/scripts/*.sh

# Verify
ls -l .claude/skills/homelab-deployment/scripts/*.sh | grep rwx
```

### 3. Check System Health

```bash
./scripts/homelab-intel.sh

# Health score should be >70
cat docs/99-reports/intel-*.json | tail -1 | jq '.health_score'
```

---

## Validation Phase 1: Individual Script Testing

### Test 1: deploy-service.sh Help and Syntax

**Objective:** Verify script runs and shows help

```bash
cd ~/containers

# Test help
./.claude/skills/homelab-deployment/scripts/deploy-service.sh --help

# Expected: Usage message with options
```

**Success Criteria:**
- [ ] Script executes without syntax errors
- [ ] Help message displays correctly
- [ ] All options documented

**If Failed:**
- Check for bash syntax errors
- Verify shebang is correct: `#!/usr/bin/env bash`
- Run with `bash -x` for debugging

---

### Test 2: test-deployment.sh Help and Syntax

**Objective:** Verify verification script syntax

```bash
cd ~/containers

# Test help
./.claude/skills/homelab-deployment/scripts/test-deployment.sh --help

# Expected: Usage message with options
```

**Success Criteria:**
- [ ] Script executes without syntax errors
- [ ] Help message displays correctly
- [ ] All options documented

---

### Test 3: generate-docs.sh Help and Syntax

**Objective:** Verify documentation generator syntax

```bash
cd ~/containers

# Test help
./.claude/skills/homelab-deployment/scripts/generate-docs.sh --help

# Expected: Usage message with options
```

**Success Criteria:**
- [ ] Script executes without syntax errors
- [ ] Help message displays correctly
- [ ] All options documented

---

### Test 4: deploy-service.sh on Existing Service

**Objective:** Test deployment script with already-running service

```bash
cd ~/containers

# Test with Traefik (already deployed)
./.claude/skills/homelab-deployment/scripts/deploy-service.sh \
  --service traefik \
  --wait-for-healthy \
  --timeout 60

# Expected: Should reload systemd, service already running message
```

**Success Criteria:**
- [ ] systemd daemon-reload succeeds
- [ ] Service enable works (or notes already enabled)
- [ ] Service start works (or notes already running)
- [ ] Health check passes (if container has healthcheck)
- [ ] Traefik integration detected
- [ ] Deployment time displayed

**If Failed:**
- Check systemd commands have `--user` flag
- Verify service name format (traefik.service)
- Check health check command syntax

---

### Test 5: test-deployment.sh on Existing Service

**Objective:** Test verification script with known-good service

```bash
cd ~/containers

# Test with Traefik
./.claude/skills/homelab-deployment/scripts/test-deployment.sh \
  --service traefik \
  --internal-port 8080 \
  --external-url https://traefik.patriark.org \
  --expect-auth

# Expected: All checks pass
```

**Success Criteria:**
- [ ] Systemd service check passes
- [ ] Container status check passes
- [ ] Health check runs (pass or warn if no healthcheck)
- [ ] Internal endpoint test (localhost:8080)
- [ ] External URL test (expect auth redirect)
- [ ] Traefik integration detected
- [ ] Prometheus check (pass or warn)
- [ ] Logs check (no recent errors)

**If Failed:**
- Check curl commands work
- Verify systemctl commands have `--user`
- Check podman inspect commands

---

### Test 6: generate-docs.sh with Test Data

**Objective:** Test documentation generation

```bash
cd ~/containers

# Generate test service guide
./.claude/skills/homelab-deployment/scripts/generate-docs.sh \
  --service test-httpbin \
  --type guide \
  --output /tmp/test-service-guide.md \
  --description "HTTP testing service" \
  --image "docker.io/kennethreitz/httpbin:latest" \
  --hostname "httpbin.test.local" \
  --memory "512M" \
  --networks "systemd-reverse_proxy" \
  --public

# Expected: Document generated in /tmp/
```

**Success Criteria:**
- [ ] Script completes successfully
- [ ] Output file created
- [ ] Template variables substituted correctly
- [ ] No {{TEMPLATE}} markers remain
- [ ] File is valid markdown

**Validation:**
```bash
# Check file exists
ls -lh /tmp/test-service-guide.md

# View content
cat /tmp/test-service-guide.md

# Check for remaining template markers (should be empty)
grep '{{' /tmp/test-service-guide.md

# Clean up
rm /tmp/test-service-guide.md
```

---

## Validation Phase 2: End-to-End Test Service Deployment

### Test 7: Deploy httpbin Test Service

**Objective:** Deploy real service end-to-end using all scripts

**Service:** httpbin (simple HTTP testing service)

#### Step 1: Create Quadlet from Template

```bash
cd ~/containers

# Copy web-app template
cp .claude/skills/homelab-deployment/templates/quadlets/web-app.container \
   ~/.config/containers/systemd/test-httpbin.container

# Edit quadlet
nano ~/.config/containers/systemd/test-httpbin.container

# Customize:
# - ContainerName=test-httpbin
# - Image=docker.io/kennethreitz/httpbin:latest
# - Network=systemd-reverse_proxy.network
# - PublishPort=8888:80
# - Remove Authelia middleware (public service)
```

**Example Configuration:**
```ini
[Unit]
Description=Test HTTP Bin Service
After=network-online.target

[Container]
ContainerName=test-httpbin
Image=docker.io/kennethreitz/httpbin:latest
AutoUpdate=registry
Pull=newer

Network=systemd-reverse_proxy.network

PublishPort=8888:80

Environment=TZ=America/New_York

HealthCmd=curl -f http://localhost:80/health || exit 1
HealthInterval=30s
HealthRetries=3
HealthStartPeriod=10s

Label=traefik.enable=true
Label=traefik.http.routers.test-httpbin.rule=Host(`httpbin.test.local`)
Label=traefik.http.services.test-httpbin.loadbalancer.server.port=80
Label=traefik.http.routers.test-httpbin.middlewares=crowdsec-bouncer@file,rate-limit-public@file

[Service]
Restart=always
TimeoutStartSec=300

[Install]
WantedBy=default.target
```

#### Step 2: Run Prerequisites Check

```bash
./.claude/skills/homelab-deployment/scripts/check-prerequisites.sh \
  --service-name test-httpbin \
  --image docker.io/kennethreitz/httpbin:latest \
  --networks systemd-reverse_proxy \
  --ports 8888 \
  --config-dir ~/containers/config/test-httpbin \
  --data-dir ~/containers/data/test-httpbin

# Expected: All checks pass
```

**Success Criteria:**
- [ ] Image pulled successfully
- [ ] Network exists
- [ ] Port 8888 available
- [ ] Directories created
- [ ] Disk space OK (<80%)
- [ ] No conflicting services
- [ ] SELinux enforcing

**If Failed:** Fix issues before proceeding

#### Step 3: Validate Quadlet

```bash
./.claude/skills/homelab-deployment/scripts/validate-quadlet.sh \
  ~/.config/containers/systemd/test-httpbin.container

# Expected: Validation passes (may have warnings)
```

**Success Criteria:**
- [ ] All required sections present
- [ ] Network naming correct (systemd- prefix)
- [ ] No critical errors

#### Step 4: Deploy Service

```bash
# Start timer
START_TIME=$(date +%s)

# Deploy
./.claude/skills/homelab-deployment/scripts/deploy-service.sh \
  --service test-httpbin \
  --wait-for-healthy \
  --timeout 120

# Expected: Deployment completes successfully
```

**Success Criteria:**
- [ ] systemd daemon-reload succeeds
- [ ] Service enabled
- [ ] Service started
- [ ] Service becomes active
- [ ] Health check passes (within timeout)
- [ ] Traefik integration detected
- [ ] Deployment time <15 minutes (preferably <5 minutes)

**Measure Time:**
```bash
END_TIME=$(date +%s)
DEPLOY_TIME=$((END_TIME - START_TIME))
echo "Deployment time: ${DEPLOY_TIME}s"

# Target: <900s (15 minutes)
# Expected: ~30-120s for httpbin
```

#### Step 5: Verify Deployment

```bash
./.claude/skills/homelab-deployment/scripts/test-deployment.sh \
  --service test-httpbin \
  --internal-port 8888

# Expected: All tests pass
```

**Success Criteria:**
- [ ] Service is active
- [ ] Container running
- [ ] Health check passes
- [ ] Internal endpoint accessible (curl localhost:8888)
- [ ] No errors in logs

#### Step 6: Manual Verification

```bash
# Test HTTP endpoint
curl http://localhost:8888/get

# Should return JSON response:
# {
#   "args": {},
#   "headers": {...},
#   "origin": "...",
#   "url": "http://localhost:8888/get"
# }

# Check service status
systemctl --user status test-httpbin.service

# View logs
journalctl --user -u test-httpbin.service -n 20

# Check Traefik integration
podman logs traefik | grep test-httpbin | tail -5
```

#### Step 7: Generate Documentation

```bash
./.claude/skills/homelab-deployment/scripts/generate-docs.sh \
  --service test-httpbin \
  --type guide \
  --output docs/10-services/guides/test-httpbin.md \
  --description "HTTP request and response testing service" \
  --purpose "Testing and debugging HTTP requests/responses" \
  --image "docker.io/kennethreitz/httpbin:latest" \
  --memory "512M" \
  --networks "systemd-reverse_proxy" \
  --config-dir "N/A" \
  --data-dir "N/A" \
  --public

# Expected: Guide generated

# Generate deployment journal
./.claude/skills/homelab-deployment/scripts/generate-docs.sh \
  --service test-httpbin \
  --type journal \
  --output docs/10-services/journal/$(date +%Y-%m-%d)-test-httpbin-deployment.md \
  --description "HTTP testing service"

# Expected: Journal generated
```

**Success Criteria:**
- [ ] Service guide created
- [ ] Deployment journal created
- [ ] Files contain valid markdown
- [ ] Template variables substituted
- [ ] No {{TEMPLATE}} markers remain

**Validation:**
```bash
# Verify files exist
ls -lh docs/10-services/guides/test-httpbin.md
ls -lh docs/10-services/journal/*test-httpbin-deployment.md

# Check content
head -20 docs/10-services/guides/test-httpbin.md

# Check for template markers (should be none)
grep '{{' docs/10-services/guides/test-httpbin.md
```

#### Step 8: Cleanup Test Service

```bash
# Stop service
systemctl --user stop test-httpbin.service

# Disable service
systemctl --user disable test-httpbin.service

# Remove container
podman rm test-httpbin

# Remove quadlet
rm ~/.config/containers/systemd/test-httpbin.container

# Reload systemd
systemctl --user daemon-reload

# Remove test docs
rm docs/10-services/guides/test-httpbin.md
rm docs/10-services/journal/*test-httpbin-deployment.md

# Verify cleanup
systemctl --user list-units | grep test-httpbin  # Should be empty
podman ps -a | grep test-httpbin  # Should be empty
```

---

## Validation Phase 3: Script Issues and Fixes

### Common Issues Checklist

**Issue 1: Permission Denied**
```bash
# Symptom: ./script.sh: Permission denied
# Fix:
chmod +x .claude/skills/homelab-deployment/scripts/*.sh
```

**Issue 2: systemd Commands Fail**
```bash
# Symptom: Failed to connect to bus
# Verify: All systemd commands use --user flag
# Check: systemctl --user status
```

**Issue 3: Health Check Timeout**
```bash
# Symptom: Health check never passes
# Debug:
podman healthcheck run <service>
podman inspect <service> --format '{{.Config.Healthcheck}}'

# If no healthcheck defined:
# Use --skip-health-check flag
```

**Issue 4: Template Variable Not Substituted**
```bash
# Symptom: {{VARIABLE}} remains in generated docs
# Check: generate-docs.sh sed commands
# Fix: Add missing variable to sed substitution list
```

**Issue 5: curl Commands Fail**
```bash
# Symptom: External URL tests fail
# Debug:
curl -v http://localhost:PORT/
curl -v -I https://external.url/

# Check: Network connectivity, Traefik routing
```

---

## Success Criteria Summary

### Phase 1: Individual Scripts ✅
- [ ] All 3 scripts execute without syntax errors
- [ ] Help messages display correctly
- [ ] deploy-service.sh works on existing service
- [ ] test-deployment.sh validates existing service
- [ ] generate-docs.sh creates valid documentation

### Phase 2: End-to-End Deployment ✅
- [ ] httpbin deploys successfully
- [ ] Deployment time <15 minutes (target: <5 minutes)
- [ ] All verification tests pass
- [ ] Documentation auto-generated correctly
- [ ] Service cleanup completes

### Phase 3: Production Readiness ✅
- [ ] No blocking bugs found
- [ ] Scripts handle errors gracefully
- [ ] Output is clear and actionable
- [ ] Documentation is accurate
- [ ] Cleanup leaves no artifacts

---

## If Validation Fails

### Critical Bugs (Blockers)

If scripts don't run at all:
1. Check bash syntax: `bash -n script.sh`
2. Check for environment-specific issues (paths, commands)
3. Fix bugs and re-test
4. Commit fixes before proceeding

### Minor Issues (Non-Blockers)

If scripts work but have issues:
1. Document issues in validation notes
2. Note as "known issues" for future enhancement
3. Proceed if workaround exists
4. Create follow-up tasks

---

## Validation Report Template

After validation, create report:

```markdown
# Session 2 Validation Report

**Date:** YYYY-MM-DD
**Validator:** [Name or "CLI Session"]
**Duration:** Xh Xm

## Summary

- **Status:** ✅ PASSED / ⚠️ PASSED WITH ISSUES / ❌ FAILED
- **Scripts Tested:** 3/3
- **Test Service:** httpbin
- **Deployment Time:** Xs

## Phase 1: Individual Scripts

- [✅/❌] deploy-service.sh: [Notes]
- [✅/❌] test-deployment.sh: [Notes]
- [✅/❌] generate-docs.sh: [Notes]

## Phase 2: End-to-End Test

- [✅/❌] Prerequisites check: [Notes]
- [✅/❌] Quadlet validation: [Notes]
- [✅/❌] Service deployment: [Notes]
- [✅/❌] Deployment verification: [Notes]
- [✅/❌] Documentation generation: [Notes]
- [✅/❌] Cleanup: [Notes]

## Issues Found

### Critical (Blockers)
1. [None or list]

### Minor (Non-Blockers)
1. [None or list]

## Fixes Applied

1. [List any fixes made during validation]

## Recommendations

1. [Suggestions for improvement]

## Conclusion

[Final assessment of Session 2 automation scripts]

**Ready for production:** ✅ YES / ❌ NO (reason)
```

---

## Next Steps After Validation

### If Validation Passes ✅

1. Commit validated scripts:
   ```bash
   git add .claude/skills/homelab-deployment/scripts/
   git commit -m "Session 2: Validated deployment automation scripts

   - deploy-service.sh: Full orchestration with health checks
   - test-deployment.sh: 8-step verification suite
   - generate-docs.sh: Auto-documentation from templates

   Validation:
   - All scripts tested on fedora-htpc
   - End-to-end test with httpbin successful
   - Deployment time: Xs (target: <900s)

   Status: Production ready"
   ```

2. Update Session 2 status:
   ```bash
   # Mark Session 2 complete in handoff document
   ```

3. Create Session 2 completion report

4. Deploy skill officially (merge to main)

### If Validation Fails ❌

1. Document failures in detail
2. Create bug fix branch
3. Address critical issues
4. Re-test with this checklist
5. Don't proceed until validation passes

---

**This checklist ensures Session 2 automation scripts are production-ready before declaring victory!** 🎯
