# CLI Session Operational Plan: System Health & Service Reconciliation

**Date:** 2025-11-13
**Session Type:** Claude Code CLI (Web Planning → CLI Handoff)
**Duration:** 2.5-3 hours
**Priority:** High (System disk approaching critical threshold)

---

## Executive Summary

**Mission:** Stabilize system disk usage, reconcile configuration drift, enhance monitoring, and capture knowledge.

**Current State:**
- ✅ All 19 services healthy (100% health check coverage)
- ⚠️ **System disk at 79%** (91GB/118GB) - **URGENT**
- ⚠️ Swap at 86% - elevated
- ⚠️ Configuration drift detected (3 services)
- ✅ Recent security updates (Traefik/CrowdSec restarted)

**Expected Outcomes:**
1. System disk usage <70% with cleanup policies in place
2. Configuration drift resolved (3 services reconciled)
3. Critical alerts configured (disk, swap, cert expiry)
4. Complete documentation of changes
5. Automated monitoring and cleanup procedures

---

## Phase 1: Emergency Triage (30 minutes)

**Objective:** Prevent system disk failure

### Task 1.1: Disk Space Investigation (10 min)

**Commands to run:**
```bash
# System-wide disk usage analysis
du -sh /home/patriark/* | sort -h | tail -20

# Container-specific usage
du -sh ~/containers/* | sort -h
du -sh ~/.local/share/containers/* | sort -h

# Journal logs
journalctl --user --disk-usage

# Podman system usage
podman system df
```

**Analysis checklist:**
- [ ] Identify top 5 disk consumers
- [ ] Check for unexpected large directories
- [ ] Review container image bloat
- [ ] Audit journal log size
- [ ] Inspect backup logs directory

**Expected findings:**
- Container images (likely largest)
- Journal logs (if not rotated)
- Backup logs accumulation
- Misconfigured data on system SSD instead of BTRFS

### Task 1.2: Immediate Cleanup (15 min)

**Cleanup operations (safe):**
```bash
# 1. Prune unused container images/layers (SAFE - only removes unused)
podman system prune -f

# 2. Rotate journal logs (SAFE - keeps last 7 days)
journalctl --user --vacuum-time=7d

# 3. Clean old backup logs (SAFE - keeps last 30 days)
find ~/containers/data/backup-logs/ -name "*.log" -mtime +30 -delete

# 4. Remove old snapshots (SAFE - keep last 10)
cd ~/containers/docs/99-reports/
ls -t snapshot-*.json | tail -n +11 | xargs rm -f
```

**Safety checks:**
- Verify no running containers use images before pruning
- Confirm journal vacuum preserves recent logs
- Test backup restore before deleting old logs

**Expected space reclaimed:** 10-20GB

### Task 1.3: Disk Space Monitoring Setup (5 min)

**Create alert rule:**

File: `~/containers/config/prometheus/alerts/disk-space.yml`

```yaml
groups:
  - name: disk_space
    interval: 60s
    rules:
      - alert: SystemDiskSpaceWarning
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 25
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "System disk space low ({{ $value }}% free)"
          description: "System SSD has less than 25% free space. Current: {{ $value }}%"

      - alert: SystemDiskSpaceCritical
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 20
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "CRITICAL: System disk space dangerously low ({{ $value }}% free)"
          description: "System SSD has less than 20% free space. Immediate action required!"

      - alert: SwapUsageHigh
        expr: (1 - (node_memory_SwapFree_bytes / node_memory_SwapTotal_bytes)) * 100 > 80
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Swap usage high ({{ $value }}%)"
          description: "System is swapping heavily. Consider investigating memory pressure."
```

**Activation:**
```bash
systemctl --user restart prometheus.service
```

---

## Phase 2: Service Configuration Reconciliation (1 hour)

**Objective:** Resolve configuration drift and clean up deprecated services

### Task 2.1: OCIS Investigation & Decision (20 min)

**Current state:**
- Quadlet exists: `~/.config/containers/systemd/ocis.container`
- Config directory exists: `~/containers/config/ocis/` (permission issues)
- Container: NOT running
- Traefik route: Unknown

**Investigation steps:**
```bash
# 1. Check quadlet configuration
cat ~/.config/containers/systemd/ocis.container

# 2. Check config directory permissions
ls -la ~/containers/config/ocis/

# 3. Check for Traefik route
grep -r "ocis" ~/containers/config/traefik/dynamic/

# 4. Review deployment history
git log --all --oneline --grep="ocis" -i
git log --all --oneline -- "*ocis*"
```

**Decision matrix:**

| Condition | Action |
|-----------|--------|
| Deployment incomplete | Complete deployment OR document as future work |
| Permission issues unresolvable | Remove configuration, document decision |
| No longer needed | Archive quadlet, remove config, update .gitignore |
| Should be running | Deploy and test |

**Expected decision:** Based on snapshot showing network config with `reverse_proxy.network` (old naming), this appears to be an incomplete/abandoned deployment.

**Recommended action:**
1. Document incomplete deployment in journal entry
2. Move quadlet to archive location
3. Add OCIS to future roadmap if still desired
4. Clean up config directory

**Deliverables:**
- [ ] Decision documented in journal
- [ ] Quadlet moved to `~/.config/containers/systemd/archive/` (create dir)
- [ ] Config directory status resolved
- [ ] Git commit with rationale

### Task 2.2: Vaultwarden Investigation & Resolution (20 min)

**Current state:**
- Quadlet exists: `~/.config/containers/systemd/vaultwarden.container`
- Traefik route exists: `vaultwarden-secure` router
- Container: NOT running
- Network config: Uses old `reverse_proxy.network` naming

**Investigation steps:**
```bash
# 1. Check when Vaultwarden was last running
systemctl --user status vaultwarden.service

# 2. Check deployment documentation
grep -r "vaultwarden" docs/10-services/journal/
grep -r "vaultwarden" docs/99-reports/

# 3. Review recent reports mentioning Vaultwarden
cat docs/99-reports/2025-11-12-vaultwarden-deployment-*.md
```

**Context from snapshot:** Report exists: `2025-11-12-vaultwarden-deployment-complete.md`

**This suggests recent deployment that failed to persist!**

**Investigation priorities:**
1. Why did deployment not persist after reboot?
2. Is systemd service enabled?
3. Are there errors in journal logs?

**Resolution steps:**
```bash
# 1. Check if service is enabled
systemctl --user is-enabled vaultwarden.service

# 2. If not enabled
systemctl --user enable vaultwarden.service

# 3. Update quadlet to use correct network naming
sed -i 's/reverse_proxy\.network/systemd-reverse_proxy.network/' ~/.config/containers/systemd/vaultwarden.container

# 4. Reload and start
systemctl --user daemon-reload
systemctl --user start vaultwarden.service

# 5. Verify health
systemctl --user status vaultwarden.service
podman ps | grep vaultwarden
curl -I http://localhost:<port>/  # Check internal health
```

**Deliverables:**
- [ ] Vaultwarden running and enabled
- [ ] Quadlet configuration fixed (network naming)
- [ ] Health check verified
- [ ] Traefik route tested
- [ ] Journal entry documenting the issue and fix

### Task 2.3: TinyAuth Deprecation (20 min)

**Current state:**
- Container running (healthy)
- **ADR-005 deprecated this service** (replaced by Authelia)
- Still has active quadlet and route

**Deprecation checklist:**

**Pre-removal verification:**
```bash
# 1. Verify Authelia is handling all auth
grep -r "tinyauth" ~/containers/config/traefik/dynamic/routers.yml

# 2. Check if any services still use tinyauth middleware
# Should all be using authelia@file now

# 3. Verify authelia is healthy and working
systemctl --user status authelia.service redis-authelia.service
curl http://localhost:9091/api/health
```

**Removal procedure:**
```bash
# 1. Stop and disable service
systemctl --user stop tinyauth.service
systemctl --user disable tinyauth.service

# 2. Remove container
podman rm tinyauth

# 3. Archive quadlet (don't delete - keep for history)
mkdir -p ~/.config/containers/systemd/archive/deprecated-by-authelia/
mv ~/.config/containers/systemd/tinyauth.container ~/.config/containers/systemd/archive/deprecated-by-authelia/

# 4. Update Traefik routes (remove tinyauth-portal router)
# Edit ~/containers/config/traefik/dynamic/routers.yml
# Comment out or remove tinyauth-portal router

# 5. Reload systemd
systemctl --user daemon-reload

# 6. Clean up data (CAREFUL - backup first!)
tar -czf ~/tinyauth-data-backup-$(date +%Y%m%d).tar.gz ~/containers/data/tinyauth/
# Then optionally rm -rf ~/containers/data/tinyauth/
```

**Documentation:**
- [ ] Update ADR-005 status section
- [ ] Create journal entry: `docs/10-services/journal/2025-11-13-tinyauth-deprecation.md`
- [ ] Update CLAUDE.md (remove TinyAuth references, note Authelia is canonical)
- [ ] Git commit with clear message

**Deliverables:**
- [ ] TinyAuth service stopped and disabled
- [ ] Quadlet archived with context
- [ ] Traefik route removed
- [ ] Documentation updated
- [ ] Data backed up

---

## Phase 3: Monitoring Enhancements (45 minutes)

**Objective:** Implement proactive alerting for critical thresholds

### Task 3.1: Critical Alert Rules (20 min)

**Create comprehensive alert file:**

File: `~/containers/config/prometheus/alerts/critical-system.yml`

```yaml
groups:
  - name: critical_system_health
    interval: 30s
    rules:
      # Disk space alerts (from Phase 1)
      - alert: SystemDiskSpaceWarning
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 25
        for: 5m
        labels:
          severity: warning
          component: system
        annotations:
          summary: "System disk space low"
          description: "System SSD {{ $labels.instance }} has {{ $value | humanizePercentage }} free space remaining"

      - alert: SystemDiskSpaceCritical
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 20
        for: 2m
        labels:
          severity: critical
          component: system
        annotations:
          summary: "CRITICAL: System disk space dangerously low"
          description: "System SSD {{ $labels.instance }} has only {{ $value | humanizePercentage }} free space. Immediate cleanup required!"

      # BTRFS pool space
      - alert: BtrfsPoolSpaceWarning
        expr: (node_filesystem_avail_bytes{mountpoint="/mnt/btrfs-pool"} / node_filesystem_size_bytes{mountpoint="/mnt/btrfs-pool"}) * 100 < 20
        for: 10m
        labels:
          severity: warning
          component: storage
        annotations:
          summary: "BTRFS pool space low"
          description: "BTRFS pool has {{ $value | humanizePercentage }} free space remaining"

      # Memory pressure
      - alert: MemoryPressureHigh
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 90
        for: 5m
        labels:
          severity: warning
          component: system
        annotations:
          summary: "Memory pressure high"
          description: "System memory usage is {{ $value | humanizePercentage }}. May cause OOM kills."

      # Swap thrashing
      - alert: SwapThrashing
        expr: rate(node_vmstat_pswpin[5m]) > 100 or rate(node_vmstat_pswpout[5m]) > 100
        for: 5m
        labels:
          severity: warning
          component: system
        annotations:
          summary: "System is swap thrashing"
          description: "High swap I/O detected. Performance degradation likely."

      # Service down alerts
      - alert: CriticalServiceDown
        expr: up{job=~"traefik|prometheus|grafana|authelia"} == 0
        for: 2m
        labels:
          severity: critical
          component: infrastructure
        annotations:
          summary: "Critical service {{ $labels.job }} is down"
          description: "Service {{ $labels.job }} on {{ $labels.instance }} is unreachable"

      # Container unhealthy
      - alert: ContainerUnhealthy
        expr: container_health_status{status!="healthy"} == 1
        for: 3m
        labels:
          severity: warning
          component: containers
        annotations:
          summary: "Container {{ $labels.name }} is unhealthy"
          description: "Container {{ $labels.name }} health check is failing"

      # Certificate expiry
      - alert: TLSCertificateExpiringSoon
        expr: (probe_ssl_earliest_cert_expiry - time()) / 86400 < 30
        for: 1h
        labels:
          severity: warning
          component: security
        annotations:
          summary: "TLS certificate expiring soon"
          description: "Certificate for {{ $labels.instance }} expires in {{ $value | humanizeDuration }} days"

      - alert: TLSCertificateExpiringCritical
        expr: (probe_ssl_earliest_cert_expiry - time()) / 86400 < 7
        for: 1h
        labels:
          severity: critical
          component: security
        annotations:
          summary: "TLS certificate expiring VERY soon"
          description: "Certificate for {{ $labels.instance }} expires in {{ $value | humanizeDuration }} days!"
```

**Update Prometheus config to include new alert file:**

```bash
# Check current prometheus.yml includes all alert files
grep -A 5 "rule_files:" ~/containers/config/prometheus/prometheus.yml

# Should include:
# rule_files:
#   - /etc/prometheus/alerts/*.yml
```

**Test alert rules:**
```bash
# Validate syntax
podman exec prometheus promtool check rules /etc/prometheus/alerts/critical-system.yml

# Reload Prometheus
systemctl --user reload prometheus.service

# Verify alerts loaded
curl http://localhost:9090/api/v1/rules | jq .
```

### Task 3.2: Grafana Dashboard for Service Health (15 min)

**Create simplified service health dashboard:**

File: `~/containers/config/grafana/provisioning/dashboards/service-health-summary.json`

**Key panels:**
1. Service Status (up/down indicator)
2. Container Health (healthy/unhealthy)
3. System Disk Usage (gauge)
4. BTRFS Pool Usage (gauge)
5. Memory Usage (graph)
6. Swap Usage (graph)
7. Active Alerts (table)

**Quick import via API:**
```bash
# Copy existing dashboard and modify
# Or create from scratch using Grafana UI, then export JSON

# Import programmatically
curl -X POST http://admin:admin@localhost:3000/api/dashboards/db \
  -H "Content-Type: application/json" \
  -d @service-health-summary.json
```

### Task 3.3: Alert Testing (10 min)

**Test alert flow:**
```bash
# 1. Trigger test alert (disk space)
# Create large file temporarily
dd if=/dev/zero of=/tmp/test-file bs=1M count=10000  # 10GB

# 2. Wait for alert to fire (check Alertmanager)
curl http://localhost:9093/api/v2/alerts | jq .

# 3. Verify Discord notification received

# 4. Clean up test file
rm /tmp/test-file

# 5. Verify alert resolves
```

**Deliverables:**
- [ ] Alert rules created and validated
- [ ] Prometheus reloaded successfully
- [ ] Grafana dashboard created
- [ ] Alert flow tested end-to-end
- [ ] Documentation updated

---

## Phase 4: Documentation & Knowledge Capture (30 minutes)

**Objective:** Document all changes and create session report

### Task 4.1: Service Reconciliation Journal (10 min)

**Create journal entry:**

File: `docs/10-services/journal/2025-11-13-service-configuration-reconciliation.md`

**Template:**
```markdown
# Service Configuration Reconciliation

**Date:** 2025-11-13
**Context:** CLI session to resolve configuration drift detected in snapshot-20251113-205233.json

## Services Investigated

### OCIS (ownCloud Infinite Scale)
**Status:** Deployment abandoned
**Reason:** [Document reason based on investigation]
**Action:** Quadlet archived, config preserved for future reference
**Decision:** [Defer deployment | Remove entirely | Schedule for future]

### Vaultwarden
**Status:** Deployment completed but service not enabled
**Issue:** Service did not persist after system reboot
**Root cause:** [Document findings]
**Fix:** Service enabled, network naming corrected
**Verification:** [Test results]

### TinyAuth
**Status:** Deprecated by ADR-005
**Replacement:** Authelia (YubiKey-first SSO)
**Action:** Service stopped, quadlet archived, data backed up
**Migration:** Complete - all services using Authelia

## Configuration Changes
- [List all quadlet modifications]
- [List all Traefik route changes]
- [List all removed services]

## Lessons Learned
- systemctl --user enable must be run for services to persist
- Network naming migration incomplete on some services
- Configuration drift detection via snapshot is valuable

## Next Steps
- [Any follow-up work required]
```

### Task 4.2: Update Living Documentation (10 min)

**Files to update:**

**1. CLAUDE.md:**
```markdown
# Update services list
- Remove TinyAuth references
- Clarify Authelia as canonical SSO
- Add note about OCIS status (if applicable)

# Update Common Commands section
- Add vaultwarden management commands (if deployed)
- Remove tinyauth commands

# Update Troubleshooting section
- Add "Service not persisting after reboot" → check systemctl enable
```

**2. docs/10-services/guides/ (create if needed):**
```markdown
# Create vaultwarden.md (if deployed)
# Or update existing service guides
```

**3. ADR-005 (Authelia deployment):**
```markdown
# Add status update
**Status:** Complete - TinyAuth fully deprecated as of 2025-11-13
**Migration:** All services migrated, TinyAuth decommissioned
```

### Task 4.3: Session Report (10 min)

**Create session report:**

File: `docs/99-reports/2025-11-13-cli-session-report.md`

**Template:**
```markdown
# CLI Session Report: System Health & Service Reconciliation

**Date:** 2025-11-13
**Duration:** [actual time]
**Operator:** Claude Code CLI

## Mission Summary
Stabilize system disk usage, reconcile configuration drift, enhance monitoring, capture knowledge.

## Achievements

### Phase 1: Emergency Triage ✅
- System disk reduced from 79% → [final %]
- Space reclaimed: [amount]GB
- Disk space alerts configured
- Cleanup policies implemented

### Phase 2: Service Reconciliation ✅
- OCIS: [status]
- Vaultwarden: [status]
- TinyAuth: Deprecated and archived

### Phase 3: Monitoring Enhancements ✅
- Critical alert rules: [count] rules added
- Grafana dashboard: Service Health Summary created
- Alert testing: [results]

### Phase 4: Documentation ✅
- Journal entries: [count]
- Living docs updated: [list]
- This report

## Metrics

### System Health (Before → After)
| Metric | Before | After | Change |
|--------|--------|-------|--------|
| System Disk | 79% | [%] | [delta] |
| Running Services | 19 | [#] | [+/-] |
| Config Drift | 3 | 0 | -3 ✅ |
| Active Alerts | [#] | [#] | [delta] |

### Time Breakdown
- Phase 1: [min]
- Phase 2: [min]
- Phase 3: [min]
- Phase 4: [min]
- **Total:** [min]

## Issues Encountered
- [List any blockers or unexpected issues]

## Follow-up Items
- [ ] [Any remaining tasks]

## Recommendations
1. [Based on session findings]
2. Schedule monthly service reconciliation
3. Automate disk cleanup via systemd timer

## Session Artifacts
- Commits: [list commit SHAs]
- Alerts configured: critical-system.yml
- Dashboards created: service-health-summary.json
- Services modified: [count]

---

**Next Session Recommendations:**
[What to prioritize next]
```

**Deliverables:**
- [ ] Journal entry completed
- [ ] Living documentation updated
- [ ] Session report created
- [ ] All changes committed to Git

---

## Automation Opportunities

### Opportunity 1: Automated Disk Cleanup (High Impact)

**Create systemd timer for periodic cleanup:**

File: `~/.config/systemd/user/homelab-cleanup.service`

```ini
[Unit]
Description=Homelab periodic cleanup (images, logs, snapshots)
Documentation=https://github.com/vonrobak/fedora-homelab-containers

[Service]
Type=oneshot
ExecStart=/home/patriark/containers/scripts/homelab-cleanup.sh

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=homelab-cleanup
```

File: `~/.config/systemd/user/homelab-cleanup.timer`

```ini
[Unit]
Description=Run homelab cleanup weekly
Documentation=https://github.com/vonrobak/fedora-homelab-containers

[Timer]
OnCalendar=Sun 03:00
Persistent=true
RandomizedDelaySec=1h

[Install]
WantedBy=timers.target
```

File: `~/containers/scripts/homelab-cleanup.sh`

```bash
#!/usr/bin/env bash
# Automated homelab cleanup script
# Run weekly to prevent disk space exhaustion

set -euo pipefail

RETENTION_DAYS=30
LOG_FILE="$HOME/containers/data/cleanup-logs/cleanup-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== Homelab Cleanup Started: $(date) ==="

# 1. Prune unused container images
echo "Pruning unused container images..."
podman system prune -f

# 2. Rotate journal logs (keep 7 days)
echo "Rotating journal logs..."
journalctl --user --vacuum-time=7d

# 3. Clean old backup logs
echo "Cleaning old backup logs (>${RETENTION_DAYS} days)..."
find "$HOME/containers/data/backup-logs/" -name "*.log" -mtime +${RETENTION_DAYS} -delete

# 4. Remove old snapshots (keep last 10)
echo "Cleaning old snapshots (keep last 10)..."
cd "$HOME/containers/docs/99-reports/"
ls -t snapshot-*.json | tail -n +11 | xargs -r rm -f

# 5. Clean old cleanup logs (keep 90 days)
echo "Cleaning old cleanup logs (>90 days)..."
find "$HOME/containers/data/cleanup-logs/" -name "*.log" -mtime +90 -delete

# Report
echo "=== Disk Usage After Cleanup ==="
df -h / /mnt/btrfs-pool

echo "=== Cleanup Completed: $(date) ==="
```

**Activation:**
```bash
chmod +x ~/containers/scripts/homelab-cleanup.sh
systemctl --user enable --now homelab-cleanup.timer
systemctl --user list-timers
```

### Opportunity 2: Enhanced System Intelligence Script

**Enhance homelab-intel.sh with:**

1. **Configuration drift detection** (already have this from snapshot!)
2. **Automated remediation suggestions**
3. **Health score calculation**
4. **Trend analysis** (compare to previous snapshots)

**Example enhancement:**

```bash
# Add to homelab-intel.sh

# Configuration drift auto-remediation
check_configuration_drift() {
    echo "Checking for configuration drift..."

    # Compare running containers vs quadlets
    QUADLETS=$(ls ~/.config/containers/systemd/*.container | xargs -n1 basename | sed 's/.container$//')
    RUNNING=$(podman ps --format '{{.Names}}')

    # Services configured but not running
    for service in $QUADLETS; do
        if ! echo "$RUNNING" | grep -q "^${service}$"; then
            # Check if intentionally stopped or drift
            if systemctl --user is-enabled ${service}.service &>/dev/null; then
                echo "⚠️  DRIFT: ${service} is enabled but not running"
                echo "   Fix: systemctl --user start ${service}.service"
            fi
        fi
    done
}
```

### Opportunity 3: Pre-commit Hook for Configuration Validation

**Prevent configuration drift at commit time:**

File: `.git/hooks/pre-commit`

```bash
#!/usr/bin/env bash
# Pre-commit hook: Validate configuration files

set -e

echo "Validating configuration files..."

# Check Traefik dynamic config syntax
if git diff --cached --name-only | grep -q "config/traefik/dynamic/"; then
    echo "Validating Traefik dynamic configuration..."
    # Add traefik validation command here
fi

# Check Prometheus alert syntax
if git diff --cached --name-only | grep -q "config/prometheus/alerts/"; then
    echo "Validating Prometheus alert rules..."
    # Add promtool check rules command here
fi

# Prevent committing secrets
if git diff --cached | grep -E "(password|secret|api_key|token).*=.*[A-Za-z0-9]{16,}"; then
    echo "❌ Potential secret detected in staged changes!"
    echo "Please review and use environment files or secret management."
    exit 1
fi

echo "✅ Configuration validation passed"
```

### Opportunity 4: Service Health Dashboard Automation

**Auto-generate Grafana dashboard from snapshot data:**

File: `~/containers/scripts/generate-service-dashboard.py`

```python
#!/usr/bin/env python3
"""
Generate Grafana dashboard JSON from system snapshot
"""

import json
import sys
from pathlib import Path

def generate_dashboard(snapshot_path):
    with open(snapshot_path) as f:
        snapshot = json.load(f)

    services = snapshot['services'].keys()

    # Generate panel for each service
    panels = []
    for i, service in enumerate(services):
        panel = {
            "id": i,
            "title": f"{service} Status",
            "type": "stat",
            "targets": [{
                "expr": f'up{{job="{service}"}}'
            }],
            "gridPos": {"x": (i % 4) * 6, "y": (i // 4) * 6, "w": 6, "h": 6}
        }
        panels.append(panel)

    dashboard = {
        "dashboard": {
            "title": "Service Health Overview (Auto-generated)",
            "panels": panels,
            "refresh": "30s"
        }
    }

    return dashboard

if __name__ == "__main__":
    snapshot = sys.argv[1] if len(sys.argv) > 1 else "docs/99-reports/snapshot-latest.json"
    dashboard = generate_dashboard(snapshot)
    print(json.dumps(dashboard, indent=2))
```

---

## Success Criteria

**Phase 1 Complete When:**
- [x] System disk usage <75%
- [x] Disk space alerts configured and tested
- [x] Cleanup automation in place

**Phase 2 Complete When:**
- [x] OCIS status documented and resolved
- [x] Vaultwarden running OR documented as deferred
- [x] TinyAuth deprecated and archived
- [x] All changes committed to Git

**Phase 3 Complete When:**
- [x] Critical alerts defined (disk, swap, cert)
- [x] Alerts loaded in Prometheus
- [x] Test alert received in Discord
- [x] Service health dashboard created

**Phase 4 Complete When:**
- [x] Journal entry created
- [x] Living docs updated (CLAUDE.md, ADRs)
- [x] Session report completed
- [x] All commits pushed to Git

**Automation Complete When:**
- [x] Cleanup timer enabled and scheduled
- [x] Enhanced intelligence script deployed
- [x] Pre-commit hooks configured (optional)
- [x] Dashboard automation tested (optional)

---

## Risk Mitigation

### Risk 1: Disk Space Exhaustion During Session
**Probability:** Low
**Impact:** High
**Mitigation:** Run Phase 1 cleanup FIRST before other operations

### Risk 2: Service Fails to Start After Configuration Change
**Probability:** Medium
**Impact:** Medium
**Mitigation:**
- Test each service start individually
- Keep previous config in Git history
- Have rollback plan: `git revert` + `systemctl restart`

### Risk 3: Accidental Data Deletion
**Probability:** Low
**Impact:** Critical
**Mitigation:**
- Backup TinyAuth data before deletion
- Use `podman prune -f` (safe - only removes unused)
- Avoid `rm -rf` without verification

### Risk 4: Breaking Traefik Routing
**Probability:** Low
**Impact:** High
**Mitigation:**
- Validate Traefik config before reload
- Keep previous dynamic config in Git
- Test routes after changes

---

## Configuration Principles Adherence

**This plan follows:**

✅ **Defense in Depth** - Alerts at multiple thresholds (warning → critical)
✅ **Fail-Safe Defaults** - Preserve deprecated configs in archive, don't delete
✅ **Separation of Concerns** - Each phase has distinct objective
✅ **Network Segmentation** - Fix Vaultwarden network naming to use systemd- prefix
✅ **Documentation as Code** - All changes documented in Git
✅ **Middleware Ordering** - N/A for this session (no middleware changes)
✅ **Least Privilege** - Scripts run as user, not root

---

## Documentation Artifacts Checklist

**Living Documents (update in place):**
- [ ] `CLAUDE.md` - Update service list, commands, troubleshooting
- [ ] `docs/10-services/guides/vaultwarden.md` - Create if deployed
- [ ] `docs/30-security/decisions/ADR-005-authelia-deployment.md` - Update status

**Journal Entries (dated, immutable):**
- [ ] `docs/10-services/journal/2025-11-13-service-configuration-reconciliation.md`
- [ ] `docs/10-services/journal/2025-11-13-tinyauth-deprecation.md`
- [ ] `docs/20-operations/journal/2025-11-13-disk-space-crisis-management.md`

**Reports (point-in-time):**
- [ ] `docs/99-reports/2025-11-13-cli-session-report.md`

**ADRs (if architectural decisions made):**
- [ ] `docs/20-operations/decisions/2025-11-13-decision-00X-automated-cleanup-policy.md` (if implementing automation)

---

## Command Reference Sheet

**Quick copy-paste commands for CLI session:**

```bash
# ==== PHASE 1: DISK CLEANUP ====

# Analyze disk usage
du -sh /home/patriark/* | sort -h | tail -20
journalctl --user --disk-usage
podman system df

# Safe cleanup
podman system prune -f
journalctl --user --vacuum-time=7d
find ~/containers/data/backup-logs/ -name "*.log" -mtime +30 -delete
cd ~/containers/docs/99-reports/ && ls -t snapshot-*.json | tail -n +11 | xargs rm -f

# ==== PHASE 2: SERVICE RECONCILIATION ====

# OCIS investigation
cat ~/.config/containers/systemd/ocis.container
ls -la ~/containers/config/ocis/
git log --all --oneline -- "*ocis*"

# Vaultwarden fix
systemctl --user enable vaultwarden.service
systemctl --user start vaultwarden.service
systemctl --user status vaultwarden.service

# TinyAuth deprecation
systemctl --user stop tinyauth.service
systemctl --user disable tinyauth.service
mkdir -p ~/.config/containers/systemd/archive/deprecated-by-authelia/
mv ~/.config/containers/systemd/tinyauth.container ~/.config/containers/systemd/archive/deprecated-by-authelia/
tar -czf ~/tinyauth-data-backup-$(date +%Y%m%d).tar.gz ~/containers/data/tinyauth/

# ==== PHASE 3: MONITORING ====

# Validate alert rules
podman exec prometheus promtool check rules /etc/prometheus/alerts/critical-system.yml

# Reload Prometheus
systemctl --user reload prometheus.service

# Check alerts
curl http://localhost:9090/api/v1/rules | jq .
curl http://localhost:9093/api/v2/alerts | jq .

# ==== PHASE 4: DOCUMENTATION ====

# Commit changes
git add .
git commit -m "Session 2025-11-13: System health & service reconciliation"
git push origin main

# ==== AUTOMATION ====

# Enable cleanup timer
chmod +x ~/containers/scripts/homelab-cleanup.sh
systemctl --user enable --now homelab-cleanup.timer
systemctl --user list-timers
```

---

## Post-Session Validation

**Run these commands after session to verify success:**

```bash
# 1. System health check
./scripts/homelab-intel.sh

# 2. Verify all services healthy
podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Health}}"

# 3. Check disk usage improved
df -h / /mnt/btrfs-pool

# 4. Verify alerts loaded
curl -s http://localhost:9090/api/v1/rules | jq -r '.data.groups[].name'

# 5. Check no configuration drift
./scripts/homelab-snapshot.sh
# Review output for drift section

# 6. Verify timers scheduled
systemctl --user list-timers --all

# 7. Test a service restart (pick one)
systemctl --user restart jellyfin.service
systemctl --user status jellyfin.service
```

---

## Handoff Notes (Web → CLI)

**Context for CLI operator:**

1. **This plan is comprehensive but flexible** - Adjust timing/scope as needed
2. **Phase 1 is URGENT** - System disk at 79% needs immediate attention
3. **Snapshot analysis was done in Web planning session** - Fresh snapshot available
4. **All configuration principles reviewed** - Middleware ordering, network segmentation, etc.
5. **Documentation standards known** - Follow CONTRIBUTING.md structure
6. **Automation opportunities identified** - Implement cleanup timer at minimum

**Key files to have open during session:**
- `docs/99-reports/snapshot-20251113-205233.json` - Current system state
- `CLAUDE.md` - Quick reference for commands
- `docs/CONTRIBUTING.md` - Documentation standards
- This plan - Operational roadmap

**If time runs short, prioritize:**
1. Phase 1 (disk space - CRITICAL)
2. Task 2.2 (Vaultwarden - recent work at risk)
3. Task 3.1 (disk space alerts - prevent future crisis)
4. Phase 4 (documentation - capture what was done)

**Good luck! 🚀**

---

**Plan Version:** 1.0
**Created:** 2025-11-13
**Planning Agent:** Claude Code Web Session
**Execution Agent:** Claude Code CLI Session
**Estimated Duration:** 2.5-3 hours
**Priority:** High (System stability at risk)
