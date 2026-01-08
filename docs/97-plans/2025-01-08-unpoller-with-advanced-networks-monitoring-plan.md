Unpoller Security Integration Plan

 Date: 2026-01-08
 Status: Awaiting Phase 1 Completion
 Owner: User (Phase 1), Claude Code (Phase 2)

 ---
 Executive Summary

 This plan configures secure integration between Unpoller and your UDM Pro for comprehensive network security monitoring. Phase 1 (user-executed) establishes secure authentication using podman secrets. Phase 2
 (Claude-automated) integrates UniFi metrics with existing Traefik/CrowdSec monitoring to provide data-driven security insights toward your port-forwarded homelab (80/443 → 192.168.1.70).

 Key Objectives:
 - Secure read-only access from Unpoller to UDM Pro
 - Comprehensive network security monitoring (traffic, DPI, firewall, presence)
 - Unified security dashboard correlating network + application layer threats
 - Conservative alerting (critical issues only, reduce alert fatigue)
 - Data-driven security posture improvements

 ---
 Current State

 Unpoller Deployment Status:
 - ✅ Quadlet exists: ~/.config/containers/systemd/unpoller.container
 - ✅ Prometheus scrape target configured (unpoller:9130)
 - ✅ Configuration file created: ~/containers/config/unpoller/up.conf
 - ❌ Credentials not configured (placeholder: UP_UNIFI_DEFAULT_PASS=CHANGE_ME)
 - ❌ Service not started (waiting for credentials)

 Secrets Management Issue:
 - Current quadlet uses Environment= variables (Pattern 3 - legacy)
 - Must migrate to: Podman secrets with type=env (Pattern 2 - RECOMMENDED per ADR-016)
 - Reference: /home/patriark/containers/docs/30-security/guides/secrets-management.md

 ---
 Phase 1: Secure UDM Pro Connection (USER MANUAL)

 Prerequisites:
 - Access to UDM Pro web interface (unifi.patriark.org)
 - Admin credentials for UDM Pro

 Estimated Time: 15-20 minutes

 Step 1: Create Read-Only User in UDM Pro

 1. Navigate to UDM Pro Settings:
   - Login: https://unifi.patriark.org
   - Go to: Settings → Admins → Add Admin
 2. Configure Read-Only Account:
 Username: unifipoller
 Role: Read Only
 Email: (optional, can leave blank)
 Password: (generate strong password - see Step 2)
 3. Verify Role Permissions:
   - Ensure "Read Only" role is selected
   - This role can view all settings but cannot make changes
   - Perfect for metrics collection

 Step 2: Generate Strong Password

 Run on homelab:
 # Generate 32-character password
 openssl rand -base64 32

 # Save output temporarily - you'll need it in Step 3
 # Example output: CB5sbWz55FUDTdcAHu0c9otJE5pDshr/QnpRXHjOiDs=

 Use this password when creating the UDM Pro user in Step 1.

 Step 3: Create Podman Secrets

 Create three secrets for Unpoller:

 # 1. UniFi controller URL
 echo -n "https://unifi.patriark.org" | podman secret create unpoller_url -

 # 2. Read-only username
 echo -n "unifipoller" | podman secret create unpoller_user -

 # 3. Password (paste the password from Step 2)
 echo -n "CB5sbWz55FUDTdcAHu0c9otJE5pDshr/QnpRXHjOiDs=" | podman secret create unpoller_pass -

 # Verify secrets created
 podman secret ls | grep unpoller
 # Expected output:
 # unpoller_url    <timestamp>
 # unpoller_user   <timestamp>
 # unpoller_pass   <timestamp>

 Security Notes:
 - Secrets are encrypted at rest: ~/.local/share/containers/storage/secrets/
 - Only accessible by containers that explicitly mount them
 - Not stored in Git or filesystem as plain text
 - Follows Pattern 2 (type=env) from secrets-management.md

 Step 4: Update Unpoller Quadlet

 Backup current quadlet:
 cp ~/.config/containers/systemd/unpoller.container ~/.config/containers/systemd/unpoller.container.backup

 Edit quadlet:
 nano ~/.config/containers/systemd/unpoller.container

 Replace these lines (17-22):
 # OLD (Pattern 3 - Environment variables):
 Environment=UP_UNIFI_DEFAULT_URL=https://unifi.patriark.org
 Environment=UP_UNIFI_DEFAULT_USER=unifipoller
 Environment=UP_UNIFI_DEFAULT_PASS=CHANGE_ME
 Environment=TZ=Europe/Oslo

 With these lines (Pattern 2 - Podman secrets):
 # NEW (Pattern 2 - Podman secrets with type=env):
 Secret=unpoller_url,type=env,target=UP_UNIFI_DEFAULT_URL
 Secret=unpoller_user,type=env,target=UP_UNIFI_DEFAULT_USER
 Secret=unpoller_pass,type=env,target=UP_UNIFI_DEFAULT_PASS
 Environment=TZ=Europe/Oslo

 Save and exit (Ctrl+O, Enter, Ctrl+X in nano)

 Step 5: Start Unpoller Service

 # Reload systemd to pick up quadlet changes
 systemctl --user daemon-reload

 # Enable and start Unpoller
 systemctl --user enable --now unpoller.service

 # Check service status
 systemctl --user status unpoller.service
 # Expected: "active (running)"

 # Follow logs for connection verification
 journalctl --user -u unpoller.service -f
 # Press Ctrl+C to stop following after ~30 seconds

 Expected log output:
 INFO  unpoller: Unpoller v2.x.x starting
 INFO  unifi: Connecting to UniFi controller: https://unifi.patriark.org
 INFO  unifi: Successfully authenticated to controller
 INFO  poller: Polling controller every 30s
 INFO  prometheus: Serving metrics on :9130

 If you see errors:
 - authentication failed → Check username/password in UDM Pro and podman secrets
 - connection refused → Verify URL and network connectivity
 - certificate error → Expected (verify_ssl=false in up.conf handles this)

 Step 6: Verify Metrics Collection

 Test Unpoller metrics endpoint:
 curl -s http://localhost:9130/metrics | head -30

 Expected output (sample metrics):
 # HELP unpoller_device_info UniFi device information
 # TYPE unpoller_device_info gauge
 unpoller_device_info{mac="xx:xx:xx:xx:xx:xx",model="UDM-Pro",name="UDM Pro",site="default",type="udm"} 1

 # HELP unifi_device_uptime_seconds Device uptime in seconds
 # TYPE unifi_device_uptime_seconds gauge
 unifi_device_uptime_seconds{mac="...",name="UDM Pro",site="default"} 1234567

 # HELP unifi_client_received_bytes_total Client received bytes
 # TYPE unifi_client_received_bytes_total counter
 unifi_client_received_bytes_total{hostname="...",mac="...",site="default"} 12345678901
 ...

 If no metrics appear:
 - Wait 30 seconds (initial polling interval)
 - Check service logs: journalctl --user -u unpoller.service -n 50
 - Verify UDM Pro account can access data (login as unifipoller user via browser test)

 Step 7: Verify Prometheus Scraping

 Check Prometheus is scraping Unpoller:
 # Query Prometheus targets API
 curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="unpoller")'

 Expected output:
 {
   "labels": {
     "instance": "fedora-htpc",
     "job": "unpoller",
     "service": "unpoller"
   },
   "health": "up",
   "lastError": "",
   "lastScrape": "2026-01-08T10:30:15.123Z",
   "scrapeUrl": "http://unpoller:9130/metrics"
 }

 Verify in Prometheus UI:
 - Open: http://localhost:9090/targets
 - Find "unpoller" job
 - Status should be "UP" (green)

 Query some metrics:
 # Check if UniFi metrics are in Prometheus
 curl -s 'http://localhost:9090/api/v1/query?query=unifi_device_uptime_seconds' | jq .

 Expected: JSON response with metric values

 Step 8: Phase 1 Completion Checklist

 Before proceeding to Phase 2, verify:

 - UDM Pro has "unifipoller" read-only user created
 - Three podman secrets created (unpoller_url, unpoller_user, unpoller_pass)
 - Unpoller quadlet updated to use podman secrets (Pattern 2)
 - Service running: systemctl --user is-active unpoller.service returns "active"
 - Logs show successful authentication to UDM Pro
 - Metrics endpoint responding: curl http://localhost:9130/metrics returns data
 - Prometheus scraping successfully: target status "UP"
 - At least one UniFi metric queryable in Prometheus

 If all checkboxes are checked, inform Claude Code to proceed with Phase 2.

 ---
 Phase 2: Security Monitoring Integration (CLAUDE AUTOMATED)

 Prerequisites:
 - ✅ Phase 1 completed (all checklist items verified)
 - ✅ User confirms Unpoller → UDM Pro connection is working

 Execution: Automated by Claude Code

 Estimated Time: 30-45 minutes (automated)

 Overview

 Phase 2 integrates UniFi network metrics with your existing security monitoring stack to provide comprehensive threat detection across network and application layers.

 Key Deliverables:
 1. Unified Security Dashboard - Correlate Traefik access logs, CrowdSec bans, UniFi firewall/DPI events
 2. UniFi Metrics Dashboards - Import community dashboards for network visibility
 3. Conservative Alerting - Critical-only alerts (UDM offline, scrape failures, extreme bandwidth)
 4. SLO Tracking - Network availability SLOs for homelab
 5. Documentation - Security monitoring guide and runbooks

 2.1: Import UniFi Grafana Dashboards

 Objective: Provide comprehensive UniFi network visibility

 Dashboards to Import (Community):
 ┌───────────────────────────────┬────────────┬────────────────────────────────────────────────────────────────────┐
 │           Dashboard           │ Grafana ID │                              Purpose                               │
 ├───────────────────────────────┼────────────┼────────────────────────────────────────────────────────────────────┤
 │ UniFi-Poller: Client Insights │ 11313      │ Client connections, bandwidth usage per device, presence detection │
 ├───────────────────────────────┼────────────┼────────────────────────────────────────────────────────────────────┤
 │ UniFi-Poller: Network Sites   │ 11314      │ Network-wide metrics, site health, aggregate statistics            │
 ├───────────────────────────────┼────────────┼────────────────────────────────────────────────────────────────────┤
 │ UniFi-Poller: USW (Switch)    │ 11315      │ Switch port statistics, PoE usage, uplink health                   │
 └───────────────────────────────┴────────────┴────────────────────────────────────────────────────────────────────┘
 Implementation Method:

 1. Programmatic Import via Grafana API:
 # Import dashboard from grafana.com
 DASHBOARD_ID=11313
 curl -X POST \
   -H "Content-Type: application/json" \
   -H "Authorization: Bearer $(podman exec grafana cat /run/secrets/admin_token)" \
   http://localhost:3000/api/dashboards/import \
   -d "{\"pluginId\":\"grafana\",\"dashboard\":{\"id\":$DASHBOARD_ID},\"overwrite\":true,\"inputs\":[]}"
 2. Download JSON and Save Locally (Recommended):
   - Download JSON from grafana.com/grafana/dashboards/
   - Save to: ~/containers/config/grafana/provisioning/dashboards/json/
   - Grafana auto-imports via provisioning (updateIntervalSeconds: 30)
   - Versioned in Git for reproducibility

 Critical File: /home/patriark/containers/config/grafana/provisioning/dashboards/json/unifi-*.json

 2.2: Enhance Security Overview Dashboard

 Objective: Unified security monitoring across network + application layers

 Existing Dashboard:
 - File: ~/containers/config/grafana/provisioning/dashboards/json/security-overview.json
 - URL: https://grafana.patriark.org/d/security-overview/
 - Current Panels: Traefik access logs, CrowdSec bans, authentication failures

 New Panels to Add:

 Panel 1: Port Forwarding Traffic to Homelab (80/443 → 192.168.1.70)

 Query (PromQL):
 # Total bytes to homelab IP
 sum(rate(unifi_client_received_bytes_total{ip="192.168.1.70"}[5m]))
 +
 sum(rate(unifi_client_transmitted_bytes_total{ip="192.168.1.70"}[5m]))

 Visualization: Time series graph (bytes/sec)

 Annotations: Mark Traefik rate limit hits and CrowdSec bans on same timeline

 Purpose: Correlate network-level traffic spikes with application-level security events

 Panel 2: DPI Security Threats Detected

 Query (PromQL):
 # DPI application classification - security categories
 unifi_device_dpi_app_bytes{category=~".*security.*|.*threat.*|.*malware.*"}

 Visualization: Table with columns: Application, Category, Bytes, Client IP

 Alert Threshold: Any non-zero value → investigate

 Purpose: Identify malicious traffic patterns detected by UDM Pro DPI before reaching Traefik

 Panel 3: Firewall Blocks by Source (Top 10)

 Query (PromQL):
 # Top 10 IPs blocked by UDM Pro firewall
 topk(10, sum by (src_ip) (rate(unifi_device_fw_blocked_total[5m])))

 Visualization: Bar chart (horizontal)

 Correlation: Cross-reference with CrowdSec ban list

 Purpose: Identify persistent attackers targeting homelab (complement to CrowdSec data)

 Panel 4: WireGuard VPN Presence Detection

 Query (PromQL):
 # Connected VPN clients (for Home Assistant presence)
 count(unifi_client_uptime_seconds{network="WireGuard"})

 Visualization: Single stat panel (current count)

 Use Case: Correlate with Home Assistant automation triggers (VPN connect → "Home" scene)

 Integration Point: Phase 2 of Matter automation plan (presence detection)

 Panel 5: Bandwidth Usage to Homelab (24h)

 Query (PromQL):
 # 24-hour bandwidth profile to 192.168.1.70
 sum(increase(unifi_client_received_bytes_total{ip="192.168.1.70"}[1h]))

 Visualization: Heatmap (hourly buckets over 24h period)

 Purpose: Identify normal vs. anomalous traffic patterns for threat detection

 Baseline: Establish 7-day baseline, alert on >3 std dev spike

 Panel 6: Correlation Matrix (Unified View)

 Layout: 3x2 grid showing concurrent events

 | Traefik Access Rate | CrowdSec Bans | UDM Firewall Blocks |
 | DPI Security Events | Bandwidth to Homelab | Authentication Failures |

 Purpose: Single-pane-of-glass security correlation

 Time Range: Synchronized across all panels (default: last 6 hours)

 Design Pattern: Use Grafana dashboard variables for IP filtering

 2.3: Create Prometheus Recording Rules

 Objective: Pre-compute expensive queries for faster dashboard rendering

 File: ~/containers/config/prometheus/rules/unifi-recording-rules.yml

 Recording Rules:

 groups:
   - name: unifi_metrics
     interval: 15s
     rules:
       # Total bandwidth to homelab
       - record: homelab:bandwidth_bytes_per_second:rate5m
         expr: |
           sum(rate(unifi_client_received_bytes_total{ip="192.168.1.70"}[5m]))
           +
           sum(rate(unifi_client_transmitted_bytes_total{ip="192.168.1.70"}[5m]))

       # VPN client count (presence detection)
       - record: homelab:vpn_clients:count
         expr: count(unifi_client_uptime_seconds{network="WireGuard"}) OR on() vector(0)

       # UDM Pro health
       - record: homelab:udm_health:up
         expr: up{job="unpoller"}

       # Firewall blocks per minute
       - record: homelab:firewall_blocks_per_minute:rate5m
         expr: sum(rate(unifi_device_fw_blocked_total[5m])) * 60

       # DPI security threat bytes
       - record: homelab:dpi_security_bytes:rate5m
         expr: |
           sum(rate(unifi_device_dpi_app_bytes{category=~".*security.*|.*threat.*|.*malware.*"}[5m]))

 Usage in Dashboards:
 - Replace complex queries with pre-computed recording rules
 - Faster rendering (queries already aggregated)
 - Lower Prometheus CPU usage

 2.4: Create Conservative Alert Rules

 Objective: Critical-only alerts (reduce alert fatigue per user preference)

 File: ~/containers/config/prometheus/alerts/unifi-alerts.yml

 Alert Rules:

 groups:
   - name: unifi_critical
     interval: 15s
     rules:
       # Alert: UDM Pro offline
       - alert: UDMProDown
         expr: up{job="unpoller"} == 0
         for: 5m
         labels:
           severity: critical
           component: network
           remediation: none  # Manual investigation required
         annotations:
           summary: "UDM Pro is unreachable"
           description: "Unpoller cannot scrape metrics from UDM Pro. Network gateway may be offline. CRITICAL: All internet access lost."
           runbook_url: "https://github.com/patriark/containers/blob/main/docs/30-security/runbooks/IR-001-network-outage.md"

       # Alert: Unpoller scrape failures
       - alert: UnpollerScrapeFailed
         expr: up{job="unpoller"} == 0 OR absent(up{job="unpoller"})
         for: 3m
         labels:
           severity: critical
           component: monitoring
           remediation: service-restart
         annotations:
           summary: "Unpoller metrics collection failing"
           description: "Prometheus cannot scrape Unpoller metrics. Check service: systemctl --user status unpoller.service"
           playbook: "service-restart"
           service: "unpoller"

       # Alert: Extreme bandwidth spike (>80% capacity)
       - alert: ExtremeBandwidthSpike
         expr: homelab:bandwidth_bytes_per_second:rate5m > 100000000  # 100 MB/s (~800 Mbps for 1Gbps link)
         for: 5m
         labels:
           severity: critical
           component: network
           remediation: none  # Investigation required
         annotations:
           summary: "Extreme bandwidth usage to homelab (>80% capacity)"
           description: "Sustained bandwidth spike {{ $value | humanize }}B/s to 192.168.1.70. Possible DDoS or data exfiltration. Investigate immediately."
           query: "homelab:bandwidth_bytes_per_second:rate5m"

       # Alert: DPI security threat detected
       - alert: DPISecurityThreatDetected
         expr: homelab:dpi_security_bytes:rate5m > 0
         for: 1m
         labels:
           severity: critical
           component: security
           remediation: none  # Manual analysis required
         annotations:
           summary: "UDM Pro DPI detected security threat"
           description: "Deep Packet Inspection identified malicious traffic. Check DPI logs in UDM Pro UI and correlate with Traefik/CrowdSec."
           investigation_steps: |
             1. Check UDM Pro DPI logs: https://unifi.patriark.org
             2. Identify source IP and correlate with Traefik access logs
             3. Verify if CrowdSec has banned the IP
             4. Review firewall rules and consider additional blocking

 Alert Routing (Alertmanager):

 # config/alertmanager/alertmanager.yml
 route:
   routes:
     - match:
         component: network
       receiver: 'discord-critical'
       continue: true  # Also send to remediation webhook for logging

 Alert Severity Levels:
 - Critical: UDM Pro down, Unpoller failures, extreme bandwidth (>80%), DPI threats
 - Warning: (Future) Moderate bandwidth (>60%), new unknown clients
 - Info: (Disabled) Client connect/disconnect, VPN sessions

 2.5: Create SLO Recording Rules

 Objective: Track network availability SLOs for homelab connectivity

 File: ~/containers/config/prometheus/rules/unifi-slo-rules.yml

 SLO Definition:
 ┌──────────────────────┬────────────┬────────────────────┬─────────────────────────────────────────────┐
 │       Service        │ SLO Target │ Error Budget (30d) │                  Rationale                  │
 ├──────────────────────┼────────────┼────────────────────┼─────────────────────────────────────────────┤
 │ UDM Pro Availability │ 99.9%      │ 43 min/month       │ Network gateway - critical for all services │
 ├──────────────────────┼────────────┼────────────────────┼─────────────────────────────────────────────┤
 │ Homelab Connectivity │ 99.5%      │ 216 min/month      │ End-to-end connectivity (UDM → Homelab)     │
 └──────────────────────┴────────────┴────────────────────┴─────────────────────────────────────────────┘
 Recording Rules:

 groups:
   - name: unifi_slo
     interval: 15s
     rules:
       # SLO: UDM Pro availability
       - record: slo:udm_availability:ratio_rate5m
         expr: avg_over_time(up{job="unpoller"}[5m])

       # SLO: Homelab connectivity (UDM can reach homelab IP)
       - record: slo:homelab_connectivity:ratio_rate5m
         expr: |
           (
             up{job="unpoller"}
             * on() group_left()
             (count(unifi_client_uptime_seconds{ip="192.168.1.70"}) > 0 OR on() vector(1))
           )

       # Error budget burn rate (alerts if burning budget too fast)
       - record: slo:udm_availability:error_budget_burn_rate_1h
         expr: |
           (1 - slo:udm_availability:ratio_rate5m)
           / (1 - 0.999)  # SLO target: 99.9%

 SLO Dashboard Integration:

 Add to existing SLO dashboard: ~/containers/config/grafana/provisioning/dashboards/json/slo-dashboard.json

 Panels:
 - Current availability (7d, 30d rolling windows)
 - Error budget remaining (minutes)
 - Burn rate alerts (tiered: 1h, 6h, 24h windows)

 2.6: Update Monitoring Documentation

 Objective: Document UniFi security monitoring patterns and runbooks

 2.6.1: Create UniFi Security Monitoring Guide

 File: ~/containers/docs/40-monitoring-and-documentation/guides/unifi-security-monitoring.md

 Contents:
 - Overview: UniFi metrics for security threat detection
 - Architecture: Unpoller → Prometheus → Grafana → Alertmanager
 - Key Metrics: DPI, firewall blocks, bandwidth, presence detection
 - Correlation Patterns: Network-layer + application-layer threat correlation
 - Investigation Workflows: Step-by-step runbooks for each alert type
 - Dashboard Tour: Security Overview panel descriptions and queries
 - Baseline Establishment: 7-day traffic profiling for anomaly detection

 2.6.2: Update Security Audit Guide

 File: ~/containers/docs/30-security/guides/security-audit.md

 Add section: "Network-Layer Security Monitoring"

 Checklist Items:
 - Unpoller scraping UDM Pro successfully
 - DPI security threat alerts configured
 - Firewall block correlation with CrowdSec
 - Bandwidth baseline established (7 days)
 - Port forwarding traffic monitored (80/443 → 192.168.1.70)

 2.6.3: Create Incident Response Runbook

 File: ~/containers/docs/30-security/runbooks/IR-005-network-security-event.md

 Runbook: Network Security Event Investigation

 Triggers:
 - DPISecurityThreatDetected alert
 - ExtremeBandwidthSpike alert
 - Unusual traffic patterns to homelab

 Investigation Steps:
 1. Assess severity: Check alert annotations for threat type
 2. Identify source IP: Query Prometheus for source IPs in traffic spike
 3. Correlate with application logs: Check Traefik access logs, CrowdSec decisions
 4. Check DPI details: Review UDM Pro UI for DPI classification
 5. Verify firewall rules: Confirm UDM Pro blocking malicious IPs
 6. Cross-reference CrowdSec: Check if IP already banned
 7. Remediation actions: Manual firewall rule, CrowdSec manual ban, rate limit adjustment
 8. Document findings: Add to decision log for future correlation

 2.7: Test End-to-End Integration

 Verification Steps:

 1. Dashboard Rendering:
   - Security Overview dashboard loads without errors
   - All UniFi panels display data (not "No data")
   - Correlation timeline shows synchronized events
 2. Alert Functionality:
   - Simulate Unpoller failure: systemctl --user stop unpoller.service
   - Wait 5 minutes, verify "UnpollerScrapeFailed" alert fires
   - Restart service: systemctl --user start unpoller.service
   - Verify alert resolves within 3 minutes
 3. Recording Rules:
   - Query recording rules in Prometheus UI
   - Verify homelab:bandwidth_bytes_per_second:rate5m returns data
   - Verify homelab:vpn_clients:count matches actual VPN connections
 4. SLO Tracking:
   - SLO dashboard shows UDM Pro availability: >99.9%
   - Error budget displays remaining minutes
   - Burn rate within acceptable limits
 5. Documentation:
   - Security monitoring guide is complete and accurate
   - Runbook IR-005 is actionable (test investigation steps)
   - Security audit checklist includes UniFi items

 2.8: Integration with Matter Home Automation Plan

 Cross-Reference: ~/containers/docs/97-plans/2025-12-30-matter-home-automation-implementation-plan.md

 Unpoller appears in Phase 2 (Weeks 4-5): Network Observability

 Integration Points:

 1. Presence Detection (Week 4):
   - Use homelab:vpn_clients:count recording rule
   - Home Assistant automation: VPN connect → "Home" scene
   - Query: unifi_client_uptime_seconds{network="WireGuard"}
 2. SLO Recording Rules (Week 4):
   - ✅ Already implemented in Phase 2.5 (this plan)
   - UDM Pro availability: 99.9%
   - Homelab connectivity: 99.5%
 3. Loki Log Aggregation (Week 5):
   - Configure Promtail to scrape Unpoller logs
   - LogQL queries for debugging network issues
   - Correlation: Prometheus metrics + Loki logs
 4. Automation Bridge (Week 7):
   - Cross-system action: Query VPN client count for presence
   - Endpoint: /query/presence (returns WireGuard client IPs)
   - Function Gemma context: Network presence + occupancy sensors

 Status: Unpoller Phase 2 completes prerequisites for Matter automation Phase 2 (Weeks 4-5)

 ---
 Critical Files Modified/Created

 Phase 1 (User Manual)

 Modified:
 - ~/.config/containers/systemd/unpoller.container - Migrate to podman secrets

 Created:
 - Podman secrets (encrypted): unpoller_url, unpoller_user, unpoller_pass

 Phase 2 (Claude Automated)

 Modified:
 1. ~/containers/config/prometheus/prometheus.yml - Add recording rule files (if not auto-discovered)
 2. ~/containers/config/grafana/provisioning/dashboards/json/security-overview.json - Add UniFi panels
 3. ~/containers/config/alertmanager/alertmanager.yml - Add network alert routing (if needed)

 Created:
 1. ~/containers/config/prometheus/rules/unifi-recording-rules.yml - Recording rules
 2. ~/containers/config/prometheus/alerts/unifi-alerts.yml - Alert rules
 3. ~/containers/config/prometheus/rules/unifi-slo-rules.yml - SLO tracking
 4. ~/containers/config/grafana/provisioning/dashboards/json/unifi-client-insights.json - Dashboard 11313
 5. ~/containers/config/grafana/provisioning/dashboards/json/unifi-network-sites.json - Dashboard 11314
 6. ~/containers/config/grafana/provisioning/dashboards/json/unifi-usw.json - Dashboard 11315
 7. ~/containers/docs/40-monitoring-and-documentation/guides/unifi-security-monitoring.md - Guide
 8. ~/containers/docs/30-security/runbooks/IR-005-network-security-event.md - Runbook
 9. ~/containers/docs/30-security/guides/security-audit.md - Updated with UniFi checklist

 ---
 Success Metrics

 Phase 1 Success Criteria

 - UDM Pro has read-only "unifipoller" user
 - Podman secrets created (encrypted at rest)
 - Unpoller quadlet uses Pattern 2 (type=env secrets)
 - Service running and authenticated to UDM Pro
 - Metrics endpoint responding (curl http://localhost:9130/metrics)
 - Prometheus scraping successfully (target "UP")

 Phase 2 Success Criteria

 - 3 UniFi dashboards imported (11313, 11314, 11315)
 - Security Overview dashboard enhanced (6 new panels)
 - Recording rules pre-computing UniFi metrics
 - Conservative alerts configured (critical only)
 - SLO tracking for UDM Pro availability (99.9% target)
 - Documentation complete (guide + runbook)
 - End-to-end test passed (alert simulation)

 Overall Objectives

 1. Data-Driven Security: Baseline network traffic, identify anomalies >3 std dev
 2. Threat Correlation: Unified dashboard showing network + application threats
 3. Presence Detection: VPN client count for Home Assistant automations
 4. Conservative Alerting: Only critical alerts, reduce alert fatigue
 5. Comprehensive Visibility: DPI, firewall, bandwidth, port forwarding stats

 ---
 Risk Mitigation
 ┌──────────────────────────┬─────────────────────────────────────────────────────────────────────────────────────────────┐
 │           Risk           │                                         Mitigation                                          │
 ├──────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────┤
 │ Credentials compromised  │ Use podman secrets (encrypted), rotate annually, read-only UDM user limits damage           │
 ├──────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────┤
 │ High cardinality metrics │ Use recording rules to pre-aggregate, retain only 15 days in Prometheus                     │
 ├──────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────┤
 │ Alert fatigue            │ Conservative alerting (critical only), 5-minute delay before firing, proper severity labels │
 ├──────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────┤
 │ Dashboard overload       │ Separate dashboards (Security Overview for threats, UniFi dashboards for network ops)       │
 ├──────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────┤
 │ UDM Pro API changes      │ Pin Unpoller container tag after testing, review release notes before updating              │
 └──────────────────────────┴─────────────────────────────────────────────────────────────────────────────────────────────┘
 ---
 Rollback Plan

 Phase 1 Rollback

 If Unpoller fails to start or authenticate:

 # Stop service
 systemctl --user stop unpoller.service

 # Restore backup quadlet
 cp ~/.config/containers/systemd/unpoller.container.backup ~/.config/containers/systemd/unpoller.container

 # Reload systemd
 systemctl --user daemon-reload

 # Remove secrets (optional)
 podman secret rm unpoller_url unpoller_user unpoller_pass

 # Service remains stopped - no impact on other services

 Phase 2 Rollback

 If dashboards or alerts cause issues:

 # Disable alert rules
 mv ~/containers/config/prometheus/alerts/unifi-alerts.yml ~/containers/config/prometheus/alerts/unifi-alerts.yml.disabled

 # Remove dashboards
 rm ~/containers/config/grafana/provisioning/dashboards/json/unifi-*.json

 # Reload Prometheus
 curl -X POST http://localhost:9090/-/reload

 # Grafana auto-removes dashboards after 30s

 Impact: Minimal - Only Unpoller metrics affected, no impact on existing monitoring

 ---
 Timeline Estimate
 ┌─────────────┬────────────────────────────────────┬──────────────────┐
 │    Phase    │                Task                │     Duration     │
 ├─────────────┼────────────────────────────────────┼──────────────────┤
 │ Phase 1     │ Create UDM Pro user                │ 5 min            │
 ├─────────────┼────────────────────────────────────┼──────────────────┤
 │             │ Generate password + create secrets │ 3 min            │
 ├─────────────┼────────────────────────────────────┼──────────────────┤
 │             │ Update quadlet                     │ 5 min            │
 ├─────────────┼────────────────────────────────────┼──────────────────┤
 │             │ Start service + verify             │ 5 min            │
 ├─────────────┼────────────────────────────────────┼──────────────────┤
 │             │ Phase 1 Total                      │ ~20 min (user)   │
 ├─────────────┼────────────────────────────────────┼──────────────────┤
 │ Phase 2     │ Import UniFi dashboards            │ 10 min           │
 ├─────────────┼────────────────────────────────────┼──────────────────┤
 │             │ Enhance Security Overview          │ 15 min           │
 ├─────────────┼────────────────────────────────────┼──────────────────┤
 │             │ Create recording rules + alerts    │ 10 min           │
 ├─────────────┼────────────────────────────────────┼──────────────────┤
 │             │ Create SLO tracking                │ 5 min            │
 ├─────────────┼────────────────────────────────────┼──────────────────┤
 │             │ Write documentation                │ 10 min           │
 ├─────────────┼────────────────────────────────────┼──────────────────┤
 │             │ Test end-to-end                    │ 10 min           │
 ├─────────────┼────────────────────────────────────┼──────────────────┤
 │             │ Phase 2 Total                      │ ~60 min (Claude) │
 ├─────────────┼────────────────────────────────────┼──────────────────┤
 │ Grand Total │                                    │ ~80 min          │
 └─────────────┴────────────────────────────────────┴──────────────────┘
 ---
 Next Steps

 For User (Phase 1)

 1. Complete Phase 1 steps 1-8 (manual execution, ~20 minutes)
 2. Verify all checklist items in Step 8
 3. Inform Claude Code: "Phase 1 complete, proceed with Phase 2"

 For Claude Code (Phase 2)

 Wait for user confirmation before starting Phase 2.

 When Phase 1 is confirmed:
 1. Import UniFi Grafana dashboards
 2. Enhance Security Overview dashboard with 6 new panels
 3. Create Prometheus recording rules, alert rules, SLO tracking
 4. Write documentation (guide + runbook)
 5. Test end-to-end integration
 6. Commit changes with comprehensive PR

 ---
 End of Plan

