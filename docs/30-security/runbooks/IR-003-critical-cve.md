# IR-003: Critical CVE in Running Container

**Severity:** HIGH to CRITICAL (depends on CVE)
**Category:** Vulnerability Management
**Last Updated:** 2025-11-29

---

## Overview

This runbook covers the response when Trivy or external sources report a critical or high-severity CVE in a running container image.

### Trigger Conditions

- Weekly Trivy scan Discord notification (vulnerability-scan.timer)
- External CVE disclosure affecting used software
- Security advisory from container image maintainer
- Manual scan reveals critical vulnerability

### Severity Classification

| CVSS Score | Trivy Severity | Response Time |
|------------|----------------|---------------|
| 9.0-10.0 | CRITICAL | Immediate (hours) |
| 7.0-8.9 | HIGH | Within 24 hours |
| 4.0-6.9 | MEDIUM | Within 1 week |
| 0.1-3.9 | LOW | Next maintenance window |

---

## Immediate Response (0-15 minutes)

### 1. Gather CVE Details

```bash
# View latest vulnerability scan report
ls -lt ~/containers/data/security-reports/trivy-*.json | head -5

# Get details for specific image
cat ~/containers/data/security-reports/trivy-<image>-<date>.json | jq '.Results[].Vulnerabilities[] | select(.Severity=="CRITICAL" or .Severity=="HIGH")'

# Or run fresh scan
~/containers/scripts/scan-vulnerabilities.sh --image <image_name>
```

### 2. Assess Exploitability

For each critical/high CVE, determine:

```bash
# Get CVE details from report
cat ~/containers/data/security-reports/trivy-*.json | jq '.Results[].Vulnerabilities[] | select(.VulnerabilityID=="<CVE-ID>") | {id: .VulnerabilityID, title: .Title, severity: .Severity, fixed: .FixedVersion, pkg: .PkgName}'
```

**Key questions:**
1. Is the vulnerable component actually used by our service?
2. Is the vulnerability remotely exploitable?
3. Does it require authentication to exploit?
4. Is there a known exploit in the wild?

**Quick research:**
- NVD: `https://nvd.nist.gov/vuln/detail/<CVE-ID>`
- Exploit-DB: `https://www.exploit-db.com/search?cve=<CVE-ID>`
- GitHub Advisory: `https://github.com/advisories?query=<CVE-ID>`

### 3. Determine Affected Services

```bash
# List all containers using the vulnerable image
podman ps --format "{{.Names}}\t{{.Image}}" | grep "<vulnerable_image>"

# Check if service is internet-facing
grep -l "<service_name>" ~/.config/containers/systemd/*.container
cat ~/.config/containers/systemd/<service>.container | grep -E "Network|PublishPort|traefik"
```

---

## Risk Assessment (15-30 minutes)

### 4. Evaluate Exposure

**Internet-facing + Critical CVE = Immediate action required**

| Service Exposure | CVE Severity | Risk Level | Action |
|------------------|--------------|------------|--------|
| Internet-facing | CRITICAL | CRITICAL | Immediate update or disable |
| Internet-facing | HIGH | HIGH | Update within 24h |
| LAN only | CRITICAL | HIGH | Update within 24h |
| LAN only | HIGH | MEDIUM | Update within 1 week |
| Internal only | Any | LOW | Next maintenance |

### 5. Check for Mitigations

Sometimes CVEs are mitigated by our configuration:

```bash
# Example: CVE requires specific feature to be enabled
# Check if we have that feature enabled
podman inspect <container> | jq '.[0].Config.Env'
cat ~/containers/config/<service>/config.yml
```

**Common mitigations:**
- Vulnerable endpoint not exposed (behind Authelia)
- Feature disabled in configuration
- Network segmentation limits access
- CrowdSec blocks exploit patterns

---

## Remediation

### 6. Option A: Update Container Image (Preferred)

```bash
# Check for available update
podman pull <image>:<tag>

# Compare versions
podman images | grep <image>

# Update via quadlet (change tag if pinned)
nano ~/.config/containers/systemd/<service>.container

# Restart service
systemctl --user daemon-reload
systemctl --user restart <service>.service

# Verify update
podman inspect <container> | jq '.[0].Image'

# Re-scan to confirm fix
~/containers/scripts/scan-vulnerabilities.sh --image <new_image>
```

### 7. Option B: Temporary Mitigation (If No Patch Available)

**Increase authentication requirements:**
```bash
# Add service to Authelia protection if not already
# Edit config/traefik/dynamic/routers.yml
# Add: middlewares: crowdsec-bouncer@file,authelia@file
```

**Restrict network access:**
```bash
# Move service to internal-only network
# Edit quadlet file, change Network= line
```

**Disable vulnerable feature:**
```bash
# Check service documentation for disabling vulnerable component
# Update service configuration
nano ~/containers/config/<service>/config.yml
systemctl --user restart <service>.service
```

### 8. Option C: Disable Service (Last Resort)

If CVE is critical, actively exploited, no patch available, and service is internet-facing:

```bash
# Stop the service
systemctl --user stop <service>.service

# Document the decision
echo "$(date): <service> disabled due to <CVE-ID> - awaiting patch" >> ~/containers/data/security-reports/disabled-services.log

# Notify via Discord (manual or script)
```

---

## Verification

### 9. Confirm Remediation

```bash
# Re-run vulnerability scan
~/containers/scripts/scan-vulnerabilities.sh --image <updated_image>

# Verify CVE no longer present
cat ~/containers/data/security-reports/trivy-<image>-*.json | jq '.Results[].Vulnerabilities[] | select(.VulnerabilityID=="<CVE-ID>")'
# Should return nothing

# Verify service is healthy
systemctl --user status <service>.service
podman healthcheck run <container>

# Test service functionality
curl -f https://<service>.patriark.org/health || echo "Health check failed"
```

### 10. Document Resolution

Update tracking:

```bash
# Add to security report
cat >> ~/containers/data/security-reports/cve-tracking.log << EOF
$(date -Iseconds) | <CVE-ID> | <service> | RESOLVED | Updated to <version>
EOF
```

---

## Post-Incident

### 11. Document Incident

For critical CVEs, create incident report in `docs/30-security/incidents/`:

```markdown
# CVE Response: <CVE-ID> - YYYY-MM-DD

**CVE:** <CVE-ID>
**CVSS:** <score>
**Severity:** CRITICAL/HIGH
**Status:** Resolved

## Summary
<Brief description of vulnerability>

## Affected Service
- **Container:** <container_name>
- **Image:** <image:tag>
- **Exposure:** Internet-facing / LAN only

## Timeline
- YYYY-MM-DD HH:MM - CVE disclosed / discovered
- YYYY-MM-DD HH:MM - Risk assessment completed
- YYYY-MM-DD HH:MM - Remediation applied
- YYYY-MM-DD HH:MM - Verification completed

## Remediation
- [Updated image to version X.Y.Z]
- [Applied configuration mitigation]
- [Temporarily disabled service]

## Evidence of Exploitation
- [No evidence found / Suspicious activity detected]
```

### 12. Improve Detection

- Ensure weekly Trivy scans are running
- Consider more frequent scans for critical services
- Subscribe to security advisories for key images:
  - Jellyfin: https://github.com/jellyfin/jellyfin/security/advisories
  - Traefik: https://github.com/traefik/traefik/security/advisories
  - Authelia: https://github.com/authelia/authelia/security/advisories

---

## Quick Reference Commands

```bash
# Run full vulnerability scan
~/containers/scripts/scan-vulnerabilities.sh --all --notify

# Scan specific image
~/containers/scripts/scan-vulnerabilities.sh --image <image>

# Update container image
podman pull <image>:<tag>
systemctl --user restart <service>.service

# Check CVE details in report
cat ~/containers/data/security-reports/trivy-*.json | jq '.Results[].Vulnerabilities[] | select(.VulnerabilityID=="CVE-XXXX-XXXXX")'

# View scan history
ls -lt ~/containers/data/security-reports/trivy-*.json | head -10
```

---

## Useful Resources

- **NVD:** https://nvd.nist.gov/vuln/detail/
- **Trivy DB:** https://github.com/aquasecurity/trivy-db
- **Exploit-DB:** https://www.exploit-db.com/
- **CISA KEV:** https://www.cisa.gov/known-exploited-vulnerabilities-catalog

---

## Related Runbooks

- IR-001: Brute Force Attack (if CVE is auth bypass)
- IR-002: Unauthorized Port (if CVE exposes new endpoint)
- IR-004: Failed Compliance Check (if update breaks compliance)
