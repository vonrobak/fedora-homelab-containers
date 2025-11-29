# IR-004: Failed Compliance Check

**Severity:** MEDIUM to HIGH (depends on ADR violated)
**Category:** Compliance & Governance
**Last Updated:** 2025-11-29

---

## Overview

This runbook covers the response when `security-audit.sh` or manual review identifies a violation of Architecture Decision Records (ADRs) or security policies.

### Trigger Conditions

- `security-audit.sh` returns FAIL or WARN status
- Manual review finds ADR non-compliance
- Deployment blocked by pre-deployment checks
- Configuration drift detected by `check-drift.sh`

### ADR Reference

| ADR | Title | Criticality |
|-----|-------|-------------|
| ADR-001 | Rootless Containers | HIGH |
| ADR-002 | Systemd Quadlets | MEDIUM |
| ADR-003 | Monitoring Stack | MEDIUM |
| ADR-005 | Authelia SSO (YubiKey) | HIGH |
| ADR-006 | CrowdSec Security | HIGH |

---

## Immediate Response (0-10 minutes)

### 1. Run Full Security Audit

```bash
# Run comprehensive security audit
~/containers/scripts/security-audit.sh

# Note which checks failed (FAIL) or warned (WARN)
```

### 2. Identify Specific Violation

**Common failures by ADR:**

**ADR-001 (Rootless Containers):**
```bash
# Check for containers running as root
podman ps --format "{{.Names}}" | while read c; do
    user=$(podman inspect $c --format "{{.Config.User}}")
    if [ "$user" = "root" ] || [ "$user" = "0" ]; then
        echo "VIOLATION: $c running as root"
    fi
done

# Check for privileged containers
podman ps --format "{{.Names}}" | while read c; do
    priv=$(podman inspect $c --format "{{.HostConfig.Privileged}}")
    if [ "$priv" = "true" ]; then
        echo "VIOLATION: $c is privileged"
    fi
done

# Check SELinux volume labels
grep -r "Volume=" ~/.config/containers/systemd/*.container | grep -v ":Z"
```

**ADR-002 (Systemd Quadlets):**
```bash
# Find containers not managed by quadlets
for c in $(podman ps --format "{{.Names}}"); do
    if [ ! -f ~/.config/containers/systemd/${c}.container ]; then
        echo "VIOLATION: $c not managed by quadlet"
    fi
done
```

**ADR-005 (Authelia SSO):**
```bash
# Check services missing Authelia middleware
grep -r "traefik.http.routers" ~/.config/containers/systemd/*.container | \
    grep -v "authelia@file" | grep -v "#"

# Check Authelia health
podman healthcheck run authelia
```

**ADR-006 (CrowdSec):**
```bash
# Check CrowdSec status
systemctl --user status crowdsec.service

# Check CAPI connection
podman exec crowdsec cscli capi status

# Check bouncer registration
podman exec crowdsec cscli bouncers list

# Check services missing CrowdSec middleware
grep -r "traefik.http.routers" ~/.config/containers/systemd/*.container | \
    grep -v "crowdsec-bouncer@file" | grep -v "#"
```

### 3. Assess Impact

**Questions to answer:**
1. How long has the violation existed?
2. Is the service internet-facing?
3. Was security compromised as a result?
4. Is this a new deployment or configuration drift?

```bash
# Check when service was last modified
stat ~/.config/containers/systemd/<service>.container

# Check service deployment history
journalctl --user -u <service>.service | head -50
```

---

## Remediation by ADR

### ADR-001: Rootless Containers

**Violation: Container running as root**
```bash
# Edit quadlet to specify user
nano ~/.config/containers/systemd/<service>.container

# Add or modify:
User=1000
# Or for images with specific user:
User=jellyfin

systemctl --user daemon-reload
systemctl --user restart <service>.service
```

**Violation: Missing SELinux labels**
```bash
# Edit quadlet volumes
# Change from:
Volume=/path/to/data:/data

# To:
Volume=/path/to/data:/data:Z

systemctl --user daemon-reload
systemctl --user restart <service>.service
```

**Violation: Privileged container**
```bash
# Remove privileged flag unless absolutely necessary (GPU)
# Edit quadlet, remove any Privileged=true

# If GPU access needed, use specific devices instead:
AddDevice=/dev/dri/renderD128
AddDevice=/dev/dri/card1
```

### ADR-002: Systemd Quadlets

**Violation: Orphan container (not in quadlet)**
```bash
# Stop the orphan container
podman stop <container_name>
podman rm <container_name>

# Create proper quadlet file
nano ~/.config/containers/systemd/<service>.container

# Use template from:
# ~/containers/.claude/skills/homelab-deployment/templates/
```

**Violation: Manual podman run usage**
```bash
# Generate quadlet from running container (as starting point)
podman generate systemd --name <container> --files --new

# Review and customize the generated file
# Then:
mv container-<name>.service ~/.config/containers/systemd/<name>.container
systemctl --user daemon-reload
```

### ADR-005: Authelia SSO

**Violation: Service missing Authelia protection**
```bash
# Edit quadlet to add Authelia middleware
nano ~/.config/containers/systemd/<service>.container

# Add/modify labels:
Label=traefik.http.routers.<service>.middlewares=crowdsec-bouncer@file,rate-limit@file,authelia@file

systemctl --user daemon-reload
systemctl --user restart <service>.service
```

**Violation: Authelia unhealthy**
```bash
# Check logs
podman logs authelia --tail 100

# Common fixes:
# 1. Redis connection issues
systemctl --user restart redis-authelia.service

# 2. Configuration syntax error
podman exec authelia authelia validate-config

# 3. Certificate issues
podman exec authelia cat /config/configuration.yml | grep -A5 certificates
```

### ADR-006: CrowdSec

**Violation: CrowdSec not running**
```bash
# Restart CrowdSec
systemctl --user restart crowdsec.service

# Check logs for errors
journalctl --user -u crowdsec.service --since "10 minutes ago"
```

**Violation: CAPI disconnected**
```bash
# Re-enroll with CAPI
podman exec crowdsec cscli capi register

# Verify
podman exec crowdsec cscli capi status
```

**Violation: Missing CrowdSec middleware**
```bash
# Edit quadlet to add CrowdSec middleware
nano ~/.config/containers/systemd/<service>.container

# Ensure middleware order (CrowdSec first for fail-fast):
Label=traefik.http.routers.<service>.middlewares=crowdsec-bouncer@file,rate-limit@file,authelia@file
```

**Violation: Bouncer not registered**
```bash
# List bouncers
podman exec crowdsec cscli bouncers list

# If traefik bouncer missing, check Traefik config
cat ~/containers/config/traefik/dynamic/middleware.yml | grep -A10 crowdsec
```

---

## Verification

### 4. Confirm Compliance

```bash
# Re-run security audit
~/containers/scripts/security-audit.sh

# All checks should PASS now

# For specific ADR verification:

# ADR-001: No root containers
podman ps --format "{{.Names}}\t{{.User}}" | grep -v "1000\|jellyfin\|grafana"

# ADR-005: Authelia healthy
curl -f http://localhost:9091/api/health

# ADR-006: CrowdSec operational
podman exec crowdsec cscli capi status | grep "successfully interact"
```

### 5. Test Service Functionality

```bash
# Verify service still works after remediation
curl -f https://<service>.patriark.org/health

# Check for errors in logs
journalctl --user -u <service>.service --since "5 minutes ago" | grep -i error
```

---

## Post-Incident

### 6. Document Compliance Issue

For significant violations, create record in `docs/30-security/incidents/`:

```markdown
# Compliance Violation: <ADR-XXX> - YYYY-MM-DD

**ADR:** ADR-XXX: <Title>
**Severity:** HIGH/MEDIUM
**Status:** Resolved

## Summary
[Brief description of violation]

## Affected Service
- **Service:** <service_name>
- **Violation Type:** [Missing middleware / Root container / etc.]
- **Duration:** [How long violation existed]

## Root Cause
- [New deployment without proper review]
- [Configuration drift]
- [Manual change bypassing process]

## Remediation
[Steps taken to fix]

## Prevention
- [Process improvements]
- [Additional automation]
```

### 7. Prevent Recurrence

**Add to deployment checklist:**
- [ ] Service runs as non-root user
- [ ] Quadlet file created with proper naming
- [ ] Volume mounts have `:Z` label
- [ ] CrowdSec middleware applied
- [ ] Authelia middleware applied (if internet-facing)
- [ ] Health check configured

**Consider automating:**
```bash
# Add pre-deployment check to deployment skill
~/containers/.claude/skills/homelab-deployment/scripts/check-system-health.sh
```

---

## Quick Reference Commands

```bash
# Run full security audit
~/containers/scripts/security-audit.sh

# Check specific ADR compliance:

# ADR-001: Rootless
podman ps --format "{{.Names}}\t{{.User}}"

# ADR-002: Quadlets
ls ~/.config/containers/systemd/*.container

# ADR-005: Authelia
curl -f http://localhost:9091/api/health

# ADR-006: CrowdSec
podman exec crowdsec cscli capi status

# Check configuration drift
~/containers/.claude/skills/homelab-deployment/scripts/check-drift.sh
```

---

## Related Runbooks

- IR-001: Brute Force Attack (if missing auth led to attack)
- IR-002: Unauthorized Port (if missing middleware exposed port)
- IR-003: Critical CVE (if compliance fix introduces vulnerability)
