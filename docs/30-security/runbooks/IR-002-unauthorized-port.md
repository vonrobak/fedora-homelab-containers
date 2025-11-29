# IR-002: Unauthorized Port Exposed

**Severity:** CRITICAL
**Category:** Network Security
**Last Updated:** 2025-11-29

---

## Overview

This runbook covers the response when the security audit or monitoring detects an unexpected open port on the system, potentially exposing internal services to the internet.

### Trigger Conditions

- `security-audit.sh` reports unexpected open port
- Manual port scan reveals unapproved exposure
- External notification of accessible service (e.g., Shodan alert)
- Firewall rule change detected

### Expected Open Ports (Whitelist)

| Port | Protocol | Service | Exposure |
|------|----------|---------|----------|
| 22 | TCP | SSH | LAN only (firewalld zone) |
| 80 | TCP | Traefik HTTP | Internet (redirects to 443) |
| 443 | TCP | Traefik HTTPS | Internet |
| 8096 | TCP | Jellyfin | Internet (via Traefik) |
| 7359 | UDP | Jellyfin Discovery | LAN only |

Any port not on this list is **unauthorized** and requires investigation.

---

## Immediate Response (0-5 minutes)

### 1. Identify the Exposed Port

```bash
# List all listening ports
ss -tulnp | grep LISTEN

# Check what process owns the port
ss -tulnp | grep ":<PORT>"

# If podman container, identify which one
podman ps --format "{{.Names}}\t{{.Ports}}" | grep "<PORT>"
```

### 2. Assess Internet Exposure

```bash
# Check if port is exposed through firewall
sudo firewall-cmd --list-ports
sudo firewall-cmd --list-services

# Check if port forwarding exists on router
# (Manual check required - access router admin)

# Quick external check (from phone or external network)
# curl -v http://<PUBLIC_IP>:<PORT>
```

### 3. Immediate Containment

**If internet-exposed and unauthorized:**

```bash
# Block port immediately via firewall
sudo firewall-cmd --remove-port=<PORT>/tcp
sudo firewall-cmd --runtime-to-permanent

# Or stop the offending service
systemctl --user stop <service>.service

# Or kill the process directly (last resort)
kill $(ss -tulnp | grep ":<PORT>" | grep -oP 'pid=\K\d+')
```

---

## Investigation (5-30 minutes)

### 4. Identify the Service

```bash
# Get process details
ps aux | grep $(ss -tulnp | grep ":<PORT>" | grep -oP 'pid=\K\d+')

# If container, get full details
podman inspect <container_name> | jq '.[0].HostConfig.PortBindings'

# Check when port was opened
journalctl --user --since "7 days ago" | grep -i "port\|listen\|bind" | grep "<PORT>"
```

### 5. Determine Root Cause

**Common causes:**

1. **Misconfigured container** - Port published that shouldn't be
   ```bash
   # Check quadlet file
   grep -r "PublishPort" ~/.config/containers/systemd/
   ```

2. **Development/testing leftover** - Temporary service still running
   ```bash
   # Check for non-quadlet containers
   podman ps -a --format "{{.Names}}" | while read c; do
       if [ ! -f ~/.config/containers/systemd/${c}.container ]; then
           echo "Orphan container: $c"
       fi
   done
   ```

3. **Firewall misconfiguration** - Port opened manually
   ```bash
   # Check firewall history
   sudo firewall-cmd --list-all
   cat /etc/firewalld/zones/FedoraWorkstation.xml
   ```

4. **Service default binding to 0.0.0.0** - Should bind to localhost
   ```bash
   # Check if service binds to all interfaces
   ss -tulnp | grep ":<PORT>" | grep "0.0.0.0"
   ```

### 6. Check for Exploitation

```bash
# Check access logs for the service (if any)
journalctl --user -u <service>.service --since "7 days ago" | tail -100

# Check for connections from unknown IPs
ss -tn | grep ":<PORT>"

# Check Traefik logs for requests to the port (if proxied)
podman logs traefik --since 7d 2>&1 | grep ":<PORT>"
```

---

## Remediation

### 7. Close the Port Properly

**Option A: Remove port publishing from container**

```bash
# Edit quadlet file
nano ~/.config/containers/systemd/<service>.container

# Remove or comment out:
# PublishPort=<PORT>:<PORT>

# Reload and restart
systemctl --user daemon-reload
systemctl --user restart <service>.service
```

**Option B: Bind to localhost only**

```bash
# Change from:
PublishPort=8080:8080

# To:
PublishPort=127.0.0.1:8080:8080
```

**Option C: Remove unauthorized service entirely**

```bash
# Stop and disable
systemctl --user stop <service>.service
systemctl --user disable <service>.service

# Remove container
podman rm <container_name>

# Remove quadlet file
rm ~/.config/containers/systemd/<service>.container
systemctl --user daemon-reload
```

### 8. Update Firewall Rules

```bash
# Ensure port is blocked
sudo firewall-cmd --remove-port=<PORT>/tcp --permanent
sudo firewall-cmd --reload

# Verify
sudo firewall-cmd --list-ports
```

### 9. Verify Remediation

```bash
# Confirm port is closed
ss -tulnp | grep ":<PORT>"
# Should return nothing

# External verification (from phone/external network)
# curl -v --connect-timeout 5 http://<PUBLIC_IP>:<PORT>
# Should timeout or refuse connection

# Run security audit
~/containers/scripts/security-audit.sh
```

---

## Post-Incident

### 10. Document Incident

Create incident report in `docs/30-security/incidents/`:

```markdown
# Incident Report: Unauthorized Port YYYY-MM-DD

**Date:** YYYY-MM-DD HH:MM
**Severity:** CRITICAL
**Status:** Resolved

## Summary
Port <PORT> was found exposed to [internet/LAN] running [service].

## Timeline
- HH:MM - Port discovered via [audit/external report]
- HH:MM - Port blocked via firewall
- HH:MM - Root cause identified
- HH:MM - Permanent fix applied
- HH:MM - Verification completed

## Impact
- Duration of exposure: [X hours/days]
- Evidence of exploitation: [Yes/No]
- Data at risk: [Description]

## Root Cause
[How the port came to be exposed]

## Actions Taken
1. Immediate firewall block
2. [Specific remediation steps]

## Prevention
- [Changes to prevent recurrence]
```

### 11. Prevent Recurrence

- Add port to security-audit.sh expected ports list (if legitimate)
- Review deployment procedures to ensure port review step
- Consider adding pre-deployment port check to deployment skill
- Set up external port monitoring (e.g., Shodan alerts)

---

## Quick Reference Commands

```bash
# List all listening ports
ss -tulnp | grep LISTEN

# Block port via firewall
sudo firewall-cmd --remove-port=<PORT>/tcp --permanent && sudo firewall-cmd --reload

# Find what's using a port
lsof -i :<PORT>

# Check container port bindings
podman inspect <container> | jq '.[0].HostConfig.PortBindings'

# Run security audit
~/containers/scripts/security-audit.sh
```

---

## Related Runbooks

- IR-001: Brute Force Attack (if exploitation detected)
- IR-004: Failed Compliance Check (if ADR violation)
