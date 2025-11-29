# IR-001: Brute Force Attack Detected

**Severity:** HIGH
**Category:** Authentication Attack
**Last Updated:** 2025-11-29

---

## Overview

This runbook covers the response to brute force authentication attacks detected by CrowdSec or observed in Authelia logs.

### Trigger Conditions

- CrowdSec alert: `crowdsecurity/http-bad-user-agent`, `crowdsecurity/http-probing`, `crowdsecurity/http-backdoors-attempts`
- Authelia logs show >100 failed auth attempts from single IP in 5 minutes
- Discord alert for "Failed Authentication" spike
- Manual observation of repeated 401/403 responses in Traefik logs

---

## Immediate Response (0-5 minutes)

### 1. Verify the Attack

```bash
# Check CrowdSec active decisions (bans)
podman exec crowdsec cscli decisions list

# Check recent CrowdSec alerts
podman exec crowdsec cscli alerts list --since 1h

# Check Authelia logs for failed attempts
podman logs authelia --since 1h 2>&1 | grep -i "unsuccessful\|failed\|denied" | tail -50
```

### 2. Confirm Automatic Ban Applied

CrowdSec should automatically ban the attacking IP. Verify:

```bash
# Check if attacker IP is banned
podman exec crowdsec cscli decisions list | grep "<ATTACKER_IP>"

# If not banned automatically, manual ban:
podman exec crowdsec cscli decisions add --ip <ATTACKER_IP> --duration 168h --reason "Manual ban: brute force"
```

### 3. Check for Successful Breach

**CRITICAL:** Determine if any attack succeeded before the ban.

```bash
# Check Authelia for successful logins from attacker IP
podman logs authelia --since 24h 2>&1 | grep "<ATTACKER_IP>" | grep -i "success\|authenticated"

# Check Traefik access logs for successful requests
podman logs traefik --since 24h 2>&1 | grep "<ATTACKER_IP>" | grep -E "HTTP/[0-9.]+ 200"
```

**If successful login found:** Escalate to IR-005 (Account Compromise) - treat as critical incident.

---

## Investigation (5-30 minutes)

### 4. Gather Attack Details

```bash
# Count total attempts from attacker
podman logs authelia --since 24h 2>&1 | grep "<ATTACKER_IP>" | wc -l

# Identify targeted usernames
podman logs authelia --since 24h 2>&1 | grep "<ATTACKER_IP>" | grep -oP 'username=\K[^ ]+' | sort | uniq -c | sort -rn

# Check attack timing pattern
podman logs authelia --since 24h 2>&1 | grep "<ATTACKER_IP>" | grep -oP '^\d{4}-\d{2}-\d{2}T\d{2}' | uniq -c
```

### 5. Check IP Reputation

```bash
# Check if IP is in CrowdSec community blocklist
podman exec crowdsec cscli alerts inspect <ALERT_ID>

# Check IP origin (requires external lookup)
# Use: https://www.abuseipdb.com/check/<ATTACKER_IP>
# Or: whois <ATTACKER_IP>
```

### 6. Review CrowdSec Scenario Effectiveness

```bash
# Check which scenario triggered
podman exec crowdsec cscli alerts list --since 24h -o json | jq '.[] | select(.source.ip=="<ATTACKER_IP>") | .scenario'

# Verify bouncer is properly rejecting
podman exec crowdsec cscli bouncers list
```

---

## Containment (If Breach Suspected)

### 7. Emergency Actions

If any evidence of successful breach:

```bash
# Force logout all Authelia sessions
systemctl --user restart redis-authelia.service

# Temporarily increase authentication requirements
# Edit ~/containers/config/authelia/configuration.yml
# Change default_policy to 'deny' temporarily

# Restart Authelia
systemctl --user restart authelia.service
```

### 8. Preserve Evidence

```bash
# Export CrowdSec alerts for the incident
podman exec crowdsec cscli alerts list --since 24h -o json > ~/containers/data/security-reports/incident-$(date +%Y%m%d)-crowdsec.json

# Export Authelia logs
podman logs authelia --since 24h > ~/containers/data/security-reports/incident-$(date +%Y%m%d)-authelia.log 2>&1

# Export Traefik access logs
podman logs traefik --since 24h > ~/containers/data/security-reports/incident-$(date +%Y%m%d)-traefik.log 2>&1
```

---

## Recovery

### 9. Verify Block is Effective

```bash
# Test that banned IP cannot access services
# (From another device if possible, or use online tools)

# Monitor for continued attempts (should show 403)
podman logs traefik -f 2>&1 | grep "<ATTACKER_IP>"
```

### 10. Extend Ban if Necessary

```bash
# Default CrowdSec bans may be too short for persistent attackers
# Extend to 7 days:
podman exec crowdsec cscli decisions add --ip <ATTACKER_IP> --duration 168h --reason "Extended ban: persistent brute force"

# For severe attacks, permanent ban:
podman exec crowdsec cscli decisions add --ip <ATTACKER_IP> --duration 8760h --reason "Permanent ban: severe attack"
```

---

## Post-Incident

### 11. Document Incident

Create incident report in `docs/30-security/incidents/`:

```markdown
# Incident Report: Brute Force Attack YYYY-MM-DD

**Date:** YYYY-MM-DD HH:MM
**Severity:** HIGH
**Status:** Resolved

## Summary
[Brief description of the attack]

## Timeline
- HH:MM - Attack detected by [CrowdSec/manual observation]
- HH:MM - Automatic ban applied
- HH:MM - Investigation completed
- HH:MM - Incident closed

## Impact
- [Number] failed authentication attempts
- [No successful breaches / Breach detected - see IR-005]

## Root Cause
- [Standard brute force / Credential stuffing / Targeted attack]

## Actions Taken
- [List of response actions]

## Lessons Learned
- [Any improvements identified]
```

### 12. Review and Improve

- Consider adding attacker IP range to permanent blocklist if from known malicious ASN
- Review if CrowdSec scenarios need tuning (too slow/fast to trigger)
- Verify Discord alerts fired correctly
- Update this runbook if gaps found

---

## Quick Reference Commands

```bash
# Check CrowdSec decisions
podman exec crowdsec cscli decisions list

# Manual ban IP
podman exec crowdsec cscli decisions add --ip <IP> --duration 168h --reason "Manual ban"

# Remove ban
podman exec crowdsec cscli decisions delete --ip <IP>

# Check Authelia logs
podman logs authelia --since 1h 2>&1 | grep -i failed

# Force logout all sessions
systemctl --user restart redis-authelia.service
```

---

## Related Runbooks

- IR-005: Account Compromise (if breach confirmed)
- IR-004: Failed Compliance Check (if CrowdSec not functioning)
