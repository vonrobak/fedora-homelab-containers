# IR-005: Network Security Event

**Severity:** CRITICAL
**Category:** Network Layer Threat
**Last Updated:** 2026-01-08

---

## Overview

This runbook covers the response to network-layer security events detected by UniFi Network (UDM Pro) via Unpoller metrics, including DPI-detected threats, extreme bandwidth spikes, and firewall blocking patterns.

### Trigger Conditions

- **DPISecurityThreatDetected alert**: UDM Pro Deep Packet Inspection identified malicious traffic (any non-zero rate)
- **ExtremeBandwidthSpike alert**: Sustained bandwidth >100 MB/s (~800 Mbps) to homelab (192.168.1.70) for 5+ minutes
- **HighFirewallBlockRate alert**: UDM Pro blocking >10 connections/minute for 10+ minutes
- Manual observation of unusual traffic patterns in UniFi dashboards
- Correlation with Traefik/CrowdSec application-layer alerts

---

## Immediate Response (0-5 minutes)

### 1. Verify the Alert

```bash
# Check current bandwidth to homelab
curl -s 'http://localhost:9090/api/v1/query?query=homelab:bandwidth_bytes_per_second:rate5m' | jq '.data.result[0].value[1]'

# Check DPI security threat bytes
curl -s 'http://localhost:9090/api/v1/query?query=homelab:dpi_security_bytes:rate5m' | jq '.data.result[0].value[1]'

# Check firewall block rate
curl -s 'http://localhost:9090/api/v1/query?query=homelab:firewall_blocks_per_minute:rate5m' | jq '.data.result[0].value[1]'
```

### 2. Identify Source of Threat

**Access UDM Pro UI for detailed investigation:**
- URL: https://unifi.patriark.org
- Navigate to: **Insights** → **Traffic** → **Deep Packet Inspection**

**Check for:**
- Source IP addresses
- Destination ports (80, 443, or others)
- DPI-identified applications/threats
- Timeline of the event

### 3. Check Correlation with Application Layer

```bash
# Check if CrowdSec has already banned the source IP
podman exec crowdsec cscli decisions list | grep "<SOURCE_IP>"

# Check Traefik access logs for the source IP
podman logs traefik --since 30m 2>&1 | grep "<SOURCE_IP>" | tail -50

# Check for Traefik rate limiting (429 responses)
podman logs traefik --since 30m 2>&1 | grep "<SOURCE_IP>" | grep "429"
```

---

## Investigation (5-30 minutes)

### 4. Gather Network-Layer Details

**Query UniFi metrics for source analysis:**

```bash
# Get top clients by bandwidth usage (last 5 minutes)
curl -s 'http://localhost:9090/api/v1/query?query=topk(10, rate(unpoller_client_transmit_bytes_total[5m]))' | jq '.data.result[] | {hostname: .metric.hostname, ip: .metric.ip, bytes_per_sec: .value[1]}'

# Get firewall block count by source IP (if available)
curl -s 'http://localhost:9090/api/v1/query?query=topk(10, rate(unpoller_device_stat_gw_user_num_blocked_total[5m]))' | jq .

# Check for anomalous clients
curl -s 'http://localhost:9090/api/v1/query?query=unpoller_client_uptime_seconds{ip="<SOURCE_IP>"}' | jq .
```

**Review UDM Pro DPI logs:**
- UDM Pro UI → **Insights** → **DPI**
- Filter by source IP and time window
- Document application classifications and threat categories

### 5. Establish Traffic Baseline Comparison

```bash
# Compare current bandwidth to 7-day average
curl -s 'http://localhost:9090/api/v1/query?query=avg_over_time(homelab:bandwidth_bytes_per_second:rate5m[7d])' | jq '.data.result[0].value[1]'

# Calculate standard deviation
curl -s 'http://localhost:9090/api/v1/query?query=stddev_over_time(homelab:bandwidth_bytes_per_second:rate5m[7d])' | jq '.data.result[0].value[1]'

# Determine if spike is >3 standard deviations from mean
# If yes: Statistically significant anomaly
```

### 6. Check Attack Vector

**Determine if attack is:**

- **DDoS (Distributed Denial of Service):**
  - Multiple source IPs
  - High connection rate
  - Targeting specific ports (80, 443)
  - Action: Contact ISP if sustained, consider Cloudflare proxy

- **Data Exfiltration:**
  - Single internal client
  - High outbound bandwidth
  - Unusual destination IPs
  - Action: Isolate client, investigate for compromise

- **Port Scanning:**
  - High firewall block rate
  - Multiple destination ports
  - Single or few source IPs
  - Action: Verify CrowdSec ban, extend duration

- **Application Exploit Attempt:**
  - DPI identifies specific threat category
  - Targeting specific service (Jellyfin, Immich, etc.)
  - Action: Check application logs, verify patch level

---

## Containment

### 7. Network-Layer Blocking

**If source IP is external attacker:**

```bash
# Manual CrowdSec ban (7 days)
podman exec crowdsec cscli decisions add --ip <SOURCE_IP> --duration 168h --reason "Network security event: DPI threat/bandwidth spike"

# Verify ban is active
podman exec crowdsec cscli decisions list | grep "<SOURCE_IP>"
```

**If DDoS is sustained and bypassing CrowdSec:**

```bash
# Temporary UDM Pro firewall rule (requires UDM Pro UI)
# Navigate to: Settings → Firewall & Security → Rules
# Create rule: Block <SOURCE_IP> or <SOURCE_IP_RANGE>
```

### 8. Service Protection

**If specific service is targeted:**

```bash
# Check which backend service is receiving traffic
podman logs traefik --since 30m 2>&1 | grep "<SOURCE_IP>" | grep -oP 'Backend-[^ ]+' | sort | uniq -c

# If attack targets specific service, consider temporary shutdown
systemctl --user stop <targeted-service>.service

# OR adjust Traefik rate limits for that service
# Edit: ~/containers/config/traefik/dynamic/rate-limit.yml
# Reduce rate limit temporarily, then reload Traefik
```

### 9. Preserve Evidence

```bash
# Create incident directory
mkdir -p ~/containers/data/security-reports/network-event-$(date +%Y%m%d-%H%M)

# Export Prometheus metrics snapshot
curl -s 'http://localhost:9090/api/v1/query?query={__name__=~"unpoller.*|homelab.*"}' > ~/containers/data/security-reports/network-event-$(date +%Y%m%d-%H%M)/prometheus-snapshot.json

# Export CrowdSec decisions
podman exec crowdsec cscli decisions list -o json > ~/containers/data/security-reports/network-event-$(date +%Y%m%d-%H%M)/crowdsec-decisions.json

# Export Traefik logs
podman logs traefik --since 1h > ~/containers/data/security-reports/network-event-$(date +%Y%m%d-%H%M)/traefik.log 2>&1

# Screenshot UDM Pro DPI page (manual, from UDM Pro UI)
```

---

## Recovery

### 10. Monitor for Continued Attack

```bash
# Watch Prometheus metrics in real-time
watch -n 5 'curl -s "http://localhost:9090/api/v1/query?query=homelab:bandwidth_bytes_per_second:rate5m" | jq ".data.result[0].value[1]"'

# Watch Traefik logs for source IP (should show 403 if banned)
podman logs traefik -f 2>&1 | grep "<SOURCE_IP>"

# Check if bandwidth returns to baseline
# Expected: Within 5 minutes after ban
```

### 11. Verify Service Availability

```bash
# Check all critical services are responding
curl -I https://traefik.patriark.org
curl -I https://authelia.patriark.org
curl -I https://grafana.patriark.org

# Check SLO compliance
curl -s 'http://localhost:9090/api/v1/query?query=slo:udm_availability:ratio_30d' | jq '.data.result[0].value[1]'
# Expected: >0.999 (99.9% availability target)
```

### 12. Restore Services (If Shut Down)

```bash
# Restart any services that were temporarily stopped
systemctl --user start <service>.service

# Verify service health
podman healthcheck run <service>

# Monitor for re-attack
podman logs traefik -f
```

---

## Post-Incident

### 13. Document Incident

Create incident report in `docs/30-security/incidents/`:

```markdown
# Incident Report: Network Security Event YYYY-MM-DD

**Date:** YYYY-MM-DD HH:MM
**Severity:** CRITICAL
**Status:** Resolved

## Summary
[Brief description: DPI threat detection / bandwidth spike / sustained firewall blocking]

## Timeline
- HH:MM - Alert fired: [DPISecurityThreatDetected / ExtremeBandwidthSpike / HighFirewallBlockRate]
- HH:MM - Source IP identified: <SOURCE_IP>
- HH:MM - CrowdSec ban applied / UDM firewall rule created
- HH:MM - Bandwidth returned to baseline
- HH:MM - Incident closed

## Impact
- Peak bandwidth: [X MB/s] (baseline: [Y MB/s])
- Duration: [X minutes]
- Services affected: [None / List services]
- Data exfiltrated: [None / Under investigation]

## Root Cause
- Attack type: [DDoS / Port scan / Application exploit / Data exfiltration]
- Source: [Single IP / Botnet / Internal compromise]
- DPI classification: [Threat category from UDM Pro]

## Actions Taken
- [List of response actions]
- [CrowdSec ban applied]
- [UDM firewall rule created]
- [Service temporarily shut down]

## Lessons Learned
- [Was alert threshold appropriate?]
- [Did CrowdSec react quickly enough?]
- [Should bandwidth threshold be adjusted?]
- [Any application vulnerabilities identified?]
```

### 14. Review and Improve

**Alert Tuning:**
- If false positive: Adjust `ExtremeBandwidthSpike` threshold in `unifi-alerts.yml`
- Current: 100 MB/s → Consider raising if legitimate traffic causes alerts
- Verify 7-day baseline is representative

**Security Posture Improvements:**
- Review DPI threat categories and correlate with CrowdSec scenarios
- Consider adding source IP range to permanent blocklist if from known malicious ASN
- Verify application patch levels if exploit attempt detected
- Update Traefik rate limits if application-layer attack succeeded

**Documentation Updates:**
- Update this runbook if gaps found
- Add incident to decision log: `docs/99-reports/remediation-decision-log.md`
- Update `unifi-security-monitoring.md` with any new correlation patterns discovered

---

## Quick Reference Commands

```bash
# Check current bandwidth to homelab
curl -s 'http://localhost:9090/api/v1/query?query=homelab:bandwidth_bytes_per_second:rate5m' | jq '.data.result[0].value[1]'

# Check DPI security threats
curl -s 'http://localhost:9090/api/v1/query?query=homelab:dpi_security_bytes:rate5m' | jq '.data.result[0].value[1]'

# Check firewall block rate
curl -s 'http://localhost:9090/api/v1/query?query=homelab:firewall_blocks_per_minute:rate5m' | jq '.data.result[0].value[1]'

# Manual CrowdSec ban
podman exec crowdsec cscli decisions add --ip <IP> --duration 168h --reason "Network security event"

# Check CrowdSec decisions
podman exec crowdsec cscli decisions list

# View Traefik logs for specific IP
podman logs traefik --since 30m 2>&1 | grep "<IP>"

# Access UDM Pro DPI logs
# https://unifi.patriark.org → Insights → DPI
```

---

## Related Runbooks

- IR-001: Brute Force Attack (if authentication attack component)
- IR-003: Critical CVE (if application exploit detected)
- DR-001: Complete System Failure (if attack causes outage)

---

## Related Documentation

- [UniFi Security Monitoring Guide](../../40-monitoring-and-documentation/guides/unifi-security-monitoring.md)
- [SLO Framework](../../40-monitoring-and-documentation/guides/slo-framework.md)
- [Loki Remediation Queries](../../40-monitoring-and-documentation/guides/loki-remediation-queries.md)
- [CrowdSec Phase 3: Threat Intelligence](../guides/crowdsec-phase3-threat-intelligence.md)
