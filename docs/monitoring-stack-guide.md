# Monitoring Stack Guide - Grafana, Prometheus, Loki, Promtail

**Deployment Date:** 2025-11-06
**Status:** Production
**Maintainer:** patriark

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Component Details](#component-details)
4. [Getting Started](#getting-started)
5. [Effective Usage Patterns](#effective-usage-patterns)
6. [Critical Analysis](#critical-analysis)
7. [Optimization Opportunities](#optimization-opportunities)
8. [Security Hardening](#security-hardening)
9. [Storage Policy Review](#storage-policy-review)
10. [Using Monitoring Data to Improve Your Homelab](#using-monitoring-data-to-improve-your-homelab)

---

## Overview

The monitoring stack provides comprehensive observability for the homelab infrastructure through metrics collection (Prometheus), log aggregation (Loki), and visualization (Grafana). This is a lightweight, single-node deployment optimized for a home environment with emphasis on low resource usage and data retention policies.

### Core Services

- **Grafana 11.3.1** - Visualization and dashboard platform
- **Prometheus 2.55.1** - Time-series metrics database
- **Loki 3.2.1** - Log aggregation system
- **Promtail 3.2.1** - Log collection agent
- **Node Exporter 1.8.2** - System metrics exporter

### Key Features

✅ Centralized metrics and logs from all containers and system services
✅ 15-day metrics retention / 7-day log retention
✅ Authenticated access via TinyAuth integration
✅ Data stored on BTRFS pool to preserve system SSD space
✅ Automatic log collection from systemd journal (user services)
✅ Pre-configured Node Exporter dashboard

---

## Architecture

### Network Topology

```
Internet → Traefik (reverse_proxy network)
              ↓
    ┌─────────┴──────────┐
    ↓                    ↓
Grafana              Prometheus
    ↓                    ↓
    └────→ monitoring network ←────┘
              ↓         ↓
            Loki    Promtail
```

**Network Segmentation:**
- `systemd-reverse_proxy` - Public-facing services (Grafana, Prometheus, Loki accessible via Traefik)
- `systemd-monitoring` - Internal monitoring communication (Prometheus ↔ exporters, Promtail → Loki)

### Data Flow

1. **Metrics Path:**
   ```
   node_exporter → Prometheus (scrape every 15s) → Grafana (query/visualize)
   ```

2. **Logs Path:**
   ```
   systemd journal → journal-export.service → file (~/containers/data/journal-export/journal.log)
                                                ↓
                                           Promtail (tail & parse JSON)
                                                ↓
                                             Loki (index & store)
                                                ↓
                                           Grafana (query/visualize)
   ```

### Storage Layout

```
System SSD (128GB, 10GB free):
  ~/containers/config/
    ├── grafana/              # Grafana configuration & provisioning
    ├── prometheus/           # Prometheus scrape config
    ├── loki/                 # Loki configuration
    └── promtail/             # Promtail configuration

  ~/containers/data/
    ├── grafana/              # Grafana database & plugins
    ├── promtail/             # Promtail positions
    └── journal-export/       # Rotating journal export (26MB)

BTRFS Pool (4.6TB free):
  /mnt/btrfs-pool/subvol7-containers/
    ├── prometheus/           # Time-series data (36MB, NOCOW)
    └── loki/                 # Log chunks & indexes (8.7MB, NOCOW)
```

**NOCOW Attribute Applied:** Both Prometheus and Loki use databases that benefit from disabling Copy-on-Write to avoid fragmentation and improve write performance on BTRFS.

---

## Component Details

### Grafana

**Quadlet:** `~/.config/containers/systemd/grafana.container`
**Image:** `docker.io/grafana/grafana:11.3.1`
**Access:** https://grafana.patriark.org
**Authentication:** TinyAuth forward auth + local admin (password in ~/containers/secrets/grafana-admin-password)

**Configuration Highlights:**
- Auth proxy enabled for TinyAuth SSO integration
- Prometheus datasource auto-provisioned as default
- Loki datasource auto-provisioned
- Dashboards directory at `~/containers/config/grafana/provisioning/dashboards/`
- Node Exporter Full dashboard (ID 1860) pre-downloaded

**Key Files:**
- `~/containers/config/grafana/provisioning/datasources/prometheus.yml`
- `~/containers/config/grafana/provisioning/datasources/loki.yml`
- `~/containers/config/grafana/provisioning/dashboards/dashboards.yml`

### Prometheus

**Quadlet:** `~/.config/containers/systemd/prometheus.container`
**Image:** `docker.io/prom/prometheus:v2.55.1`
**Access:** https://prometheus.patriark.org
**Retention:** 15 days (`--storage.tsdb.retention.time=15d`)

**Scrape Targets:**
- `prometheus:9090` - Self-monitoring
- `node_exporter:9100` - System metrics (CPU, memory, disk, network)
- `grafana:3000` - Grafana application metrics

**Configuration:** `~/containers/config/prometheus/prometheus.yml`

**Storage:** `/mnt/btrfs-pool/subvol7-containers/prometheus` (NOCOW enabled)

**Future Scrape Candidates:**
- Traefik metrics endpoint
- Jellyfin metrics (if available)
- CrowdSec metrics
- Redis metrics (Authelia backend)
- Custom application exporters

### Loki

**Quadlet:** `~/.config/containers/systemd/loki.container`
**Image:** `docker.io/grafana/loki:3.2.1`
**Access:** https://loki.patriark.org (API only, no UI)
**Retention:** 7 days (`retention_period: 168h`)

**Configuration:** `~/containers/config/loki/loki-config.yml`

**Key Settings:**
- Single-node deployment (replication_factor: 1)
- Filesystem storage backend (no S3/object storage)
- TSDB index (schema v13, modern and efficient)
- Compactor enabled with automatic retention deletion
- Rate limits: 16MB/s ingestion, 32MB burst

**Storage:** `/mnt/btrfs-pool/subvol7-containers/loki` (NOCOW enabled)

**Label-Based Indexing:**
Loki is NOT a full-text search engine. It indexes based on labels:
- `job` - Always "systemd-journal" for our deployment
- `host` - Hostname (fedora-htpc)
- `unit` - Systemd unit name (e.g., grafana.service, traefik.service)
- `priority` - Log level (3=error, 4=warning, 6=info, 7=debug)
- `hostname` - From journal metadata
- `syslog_id` - Process identifier (e.g., podman, systemd)

### Promtail

**Quadlet:** `~/.config/containers/systemd/promtail.container`
**Image:** `docker.io/grafana/promtail:3.2.1`
**Port:** 9080 (internal metrics)

**Configuration:** `~/containers/config/promtail/promtail-config.yml`

**Log Source:**
Promtail tails `/var/log/journal-export/journal.log`, which is continuously populated by `journal-export.service`.

**Why Not Direct Journal Access?**
Rootless Podman containers cannot access `/var/log/journal/` due to SELinux restrictions, even with the systemd-journal group (GID 190) added. The SELinux label `:z` would attempt to relabel system directories, which is prohibited. Our workaround pipes `journalctl --user -f` output to a user-writable location.

### Journal Export Service

**Systemd Unit:** `~/.config/systemd/user/journal-export.service`
**Command:** `journalctl --user -f -o json --since="1 hour ago"`
**Output:** `~/containers/data/journal-export/journal.log`

**Purpose:** Bridge the gap between systemd journal (system security context) and rootless containers (user security context).

**Limitations:**
- Only captures **user journal** (container services), not system journal
- 1-hour lookback on service restart (recent logs only)
- File grows unbounded (needs log rotation policy)

### Node Exporter

**Quadlet:** `~/.config/containers/systemd/node_exporter.container`
**Image:** `quay.io/prometheus/node-exporter:v1.8.2`
**Port:** 9100

**Host Volumes Mounted:**
- `/:/host:ro,rslave` - Full read-only access to host filesystem
- `/sys:/host/sys:ro,rslave` - System statistics
- `/proc:/host/proc:ro,rslave` - Process information

**Metrics Provided:**
- CPU usage (per-core and aggregate)
- Memory usage (available, cached, buffers)
- Disk I/O and space utilization
- Network interface statistics
- System load average
- Temperature sensors (if available)
- Filesystem statistics

---

## Getting Started

### Accessing Grafana

1. Navigate to https://grafana.patriark.org
2. Authenticate via TinyAuth (or use admin credentials)
3. First-time setup:
   - Go to Dashboards → Browse
   - Import the Node Exporter Full dashboard (already downloaded)
   - Click "New" → "Import" → "Upload JSON file"
   - Select: `~/containers/config/grafana/provisioning/dashboards/node-exporter-full.json`

### Exploring Metrics in Prometheus

**Direct Access:** https://prometheus.patriark.org

**Useful PromQL Queries:**

```promql
# CPU usage percentage (averaged across all cores)
100 - (avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory usage percentage
100 * (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))

# Disk space used percentage (root filesystem)
100 - ((node_filesystem_avail_bytes{mountpoint="/"} * 100) / node_filesystem_size_bytes{mountpoint="/"})

# Network receive bandwidth (bytes/sec)
rate(node_network_receive_bytes_total{device="enp3s0"}[5m])

# Container count
count(container_last_seen) by (name)
```

### Querying Logs in Loki (via Grafana)

**Access:** Grafana → Explore → Select "Loki" datasource

**Basic LogQL Queries:**

```logql
# All logs from systemd journal
{job="systemd-journal"}

# Logs from a specific service
{job="systemd-journal", unit="grafana.service"}

# Error logs only (priority 3)
{job="systemd-journal", priority="3"}

# Logs from Podman (all container events)
{job="systemd-journal", syslog_id="podman"}

# Search for specific text (slower, scans log content)
{job="systemd-journal"} |= "error"

# Prometheus logs with rate calculation (logs per second)
rate({job="systemd-journal", unit="prometheus.service"}[5m])

# Traefik access logs
{job="systemd-journal", unit="traefik.service"} | json | line_format "{{.MESSAGE}}"

# Count errors by service over time
sum by (unit) (count_over_time({job="systemd-journal", priority="3"}[5m]))
```

**LogQL Tips:**
- Use label filters (`{key="value"}`) for fast indexed queries
- Text search (`|= "pattern"`) is slower, use sparingly
- Chain filters: `{unit="traefik.service"} |= "error" | json | status >= 500`
- Rate/count functions help identify patterns over time

---

## Effective Usage Patterns

### Daily Monitoring Routine

1. **Check System Health Dashboard**
   - Open Node Exporter Full dashboard
   - Verify CPU/memory usage is within normal ranges
   - Check disk space trends

2. **Review Service Logs**
   - Open Explore → Loki
   - Query: `{job="systemd-journal", priority=~"3|4"}` (errors + warnings)
   - Look for patterns or repeated errors

3. **Container Lifecycle Events**
   - Query: `{syslog_id="podman"} |= "container"`
   - Check for unexpected restarts or failures

### Troubleshooting Workflows

**Scenario: Service is slow or unresponsive**

1. Check resource usage in Grafana:
   - CPU usage per core
   - Memory pressure
   - Disk I/O wait times

2. Check service logs:
   ```logql
   {unit="<service>.service"} | json | line_format "{{.MESSAGE}}"
   ```

3. Check container events:
   ```logql
   {syslog_id="podman"} |~ "<container-name>" |= "died|restart|oom"
   ```

**Scenario: Investigating authentication failures**

```logql
# TinyAuth logs
{unit="tinyauth.service"} |= "auth" |= "fail"

# Traefik access logs showing 401/403
{unit="traefik.service"} | json | status =~ "40[13]"
```

**Scenario: Diagnosing network issues**

```promql
# Network errors and drops
rate(node_network_receive_errs_total[5m])
rate(node_network_transmit_errs_total[5m])

# Check DNS resolution (in logs)
{unit="traefik.service"} |= "DNS" |= "error"
```

### Creating Useful Dashboards

**Dashboard Best Practices:**

1. **Group by Concern:**
   - System Health (CPU, memory, disk)
   - Service Availability (uptime, restarts)
   - Application Performance (response times, error rates)
   - Security Events (auth failures, unusual access patterns)

2. **Use Time Range Selectors:**
   - Default: Last 6 hours
   - Quick ranges: 15m, 1h, 6h, 24h, 7d

3. **Set Alert Thresholds:**
   - Disk space < 10% free
   - Memory usage > 90%
   - CPU usage > 80% for 5+ minutes
   - Service restart count > 3 in 1 hour

4. **Variables for Flexibility:**
   - `$instance` - Select which node_exporter instance
   - `$service` - Filter by systemd unit
   - `$container` - Filter by container name

### Alerting Strategy (Future Enhancement)

Currently, the stack does **not** include Alertmanager. To add alerting:

1. Deploy Alertmanager container
2. Configure Prometheus alert rules in `/prometheus/alerts/`
3. Set up notification channels (email, Slack, Discord, ntfy.sh)
4. Define alert rules for critical conditions:
   - Disk space exhaustion
   - Service down for > 5 minutes
   - High error rates
   - Certificate expiration (from Traefik)

---

## Critical Analysis

### What Works Well

✅ **Low Resource Footprint**
- Total memory usage: ~500MB across all monitoring components
- CPU usage: < 5% during normal operation
- Storage: < 50MB combined for 7-15 days of data

✅ **Unified Observability**
- Single pane of glass (Grafana) for metrics and logs
- Consistent authentication via TinyAuth
- All services accessible via HTTPS with valid certs

✅ **Automated Collection**
- Prometheus scrapes automatically every 15s
- Logs captured from all containerized services via systemd
- No manual log shipping configuration per service

✅ **Storage Efficiency**
- BTRFS pool utilization prevents system SSD exhaustion
- NOCOW attribute prevents database fragmentation
- Retention policies keep data size bounded

### Architectural Weaknesses

⚠️ **Journal Export Workaround is Fragile**

**Problem:** The `journal-export.service → file → Promtail` pipeline is a workaround for SELinux/rootless limitations.

**Risks:**
- File grows unbounded (no rotation policy)
- Service restart loses logs older than 1 hour
- Duplicate log entries if service crashes and restarts
- Additional disk I/O and storage overhead

**Better Alternatives:**
1. Run Promtail as a **system service** (not rootless container) with proper journal access
2. Use **Grafana Alloy** in system mode (requires breaking rootless constraint)
3. Configure **remote syslog forwarding** from systemd-journald to Loki directly
4. Use **Loki's native systemd journal driver** (experimental)

⚠️ **Single Point of Failure**

**Problem:** All monitoring runs on the same host. If the host goes down, you lose visibility into *why* it went down.

**Impact:**
- Cannot detect host-level failures (kernel panic, hardware failure)
- Cannot monitor from outside the network (no external uptime checks)
- Losing context during power outages or network failures

**Mitigation:**
- Add external uptime monitoring (UptimeRobot, Healthchecks.io)
- Send critical alerts to external services (ntfy.sh, email)
- Backup Grafana dashboards and configs to git regularly

⚠️ **No System Journal Access**

**Problem:** Only collecting user journal (rootless services), missing system-level events.

**Missing Data:**
- Kernel messages (hardware errors, OOM killer)
- System service failures (sshd, networkd, firewalld)
- Security events (SELinux denials, failed logins)
- Boot/shutdown events

**Workaround:**
- Modify `journal-export.service` to run as system service (requires sudo)
- Use `journalctl -f` without `--user` flag
- Update promtail to read from `/var/log/journal/export-system.log`

⚠️ **Limited Metrics Coverage**

**Problem:** Only collecting host metrics (node_exporter), not application metrics.

**Missing Insights:**
- Traefik request rates, latency, error rates
- Jellyfin concurrent streams, transcoding load
- Prometheus query performance (though self-monitored)
- Container resource usage per-container

**Enhancement Path:**
- Enable Traefik metrics endpoint and add to Prometheus
- Deploy cAdvisor for per-container resource metrics
- Add custom exporters for application-specific metrics

⚠️ **No Log Parsing or Structuring**

**Problem:** All logs stored as raw JSON from journal, no additional parsing.

**Impact:**
- Cannot easily query HTTP status codes from Traefik
- Cannot extract response times or latencies
- Cannot correlate requests across services (no trace IDs)

**Enhancement:**
- Add Promtail pipeline stages to parse Traefik JSON logs
- Extract structured fields (status, method, path, duration)
- Add labels for common query patterns

---

## Optimization Opportunities

### Performance Optimizations

#### 1. Reduce Prometheus Scrape Interval

**Current:** 15 seconds
**Proposed:** 30 seconds for most targets, 15s for critical services

**Rationale:** Homelab doesn't need sub-minute granularity for most metrics. Reducing scrape frequency:
- Reduces CPU overhead on exporters
- Reduces network traffic
- Reduces storage growth rate
- Minimal impact on dashboard usefulness

**Implementation:**
```yaml
# ~/containers/config/prometheus/prometheus.yml
global:
  scrape_interval: 30s

scrape_configs:
  - job_name: 'critical-services'
    scrape_interval: 15s
    static_configs:
      - targets: ['traefik:8080']  # High-traffic proxy

  - job_name: 'standard-services'
    scrape_interval: 30s
    static_configs:
      - targets: ['node_exporter:9100', 'grafana:3000']
```

#### 2. Implement Log Rotation for Journal Export

**Problem:** `journal.log` grows unbounded

**Solution:** Add logrotate configuration

```bash
# Create logrotate config for user service
cat > ~/containers/config/journal-export-logrotate.conf <<EOF
/home/patriark/containers/data/journal-export/journal.log {
    size 100M
    rotate 2
    compress
    delaycompress
    notifempty
    missingok
    copytruncate
}
EOF

# Add timer to run logrotate
systemctl --user edit --force --full journal-logrotate.timer
systemctl --user enable --now journal-logrotate.timer
```

#### 3. Optimize Loki Query Performance

**Current Issue:** No caching, every query hits storage

**Optimization:**
- Increase `results_cache.max_size_mb` from 100MB to 256MB
- Enable query frontend for query splitting and caching
- Add bloom filters for faster negative lookups

```yaml
# ~/containers/config/loki/loki-config.yml
query_range:
  results_cache:
    cache:
      embedded_cache:
        enabled: true
        max_size_mb: 256  # Increased from 100

# Enable bloom filters for v13 schema
bloom_build:
  enabled: true

bloom_gateway:
  enabled: true
```

#### 4. Add Retention Policies by Label

**Current:** All logs treated equally (7 days)

**Proposal:** Tiered retention based on priority

```yaml
# Keep errors longer than info logs
limits_config:
  retention_stream:
    - selector: '{priority="3"}'  # Errors
      priority: 1
      period: 336h  # 14 days
    - selector: '{priority="6"}'  # Info
      priority: 2
      period: 168h  # 7 days
```

### Resource Optimizations

#### 5. Limit Container Memory Usage

**Current:** No memory limits, containers can consume all available RAM

**Proposal:** Set memory limits via Quadlet

```ini
# Example: prometheus.container
[Container]
Memory=512M
MemorySwap=512M

# Example: loki.container
[Container]
Memory=256M
MemorySwap=256M

# Example: grafana.container
[Container]
Memory=256M
MemorySwap=256M
```

**Rationale:** Prevents one component from starving others during load spikes.

#### 6. Use Read-Only Root Filesystems

**Security & Performance Win**

```ini
# Example: prometheus.container
[Container]
ReadOnly=true
Tmpfs=/tmp

# Example: grafana.container
[Container]
ReadOnly=true
Tmpfs=/tmp
Tmpfs=/var/lib/grafana/plugins:rw
```

**Benefits:**
- Prevents accidental/malicious file modifications
- Reduces disk write overhead
- Improves container startup time

### Functional Enhancements

#### 7. Deploy cAdvisor for Container Metrics

**What:** Google's container metrics exporter

**Provides:**
- Per-container CPU, memory, network, disk usage
- Container start/stop events
- Resource limit enforcement visibility

**Quick Deploy:**
```ini
# ~/.config/containers/systemd/cadvisor.container
[Unit]
Description=cAdvisor - Container Metrics
After=network-online.target monitoring-network.service

[Container]
Image=gcr.io/cadvisor/cadvisor:latest
ContainerName=cadvisor
Network=systemd-monitoring
Volume=/:/rootfs:ro
Volume=/var/run/podman/podman.sock:/var/run/docker.sock:ro
Volume=/sys:/sys:ro
Volume=/var/lib/containers:/var/lib/containers:ro
PublishPort=8080:8080

[Service]
Restart=on-failure

[Install]
WantedBy=default.target
```

Add to Prometheus:
```yaml
scrape_configs:
  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']
```

#### 8. Add Traefik Metrics

**Traefik already exposes metrics!**

Enable in `~/containers/config/traefik/traefik.yml`:
```yaml
metrics:
  prometheus:
    buckets:
      - 0.1
      - 0.3
      - 1.0
      - 3.0
      - 10.0
    addEntryPointsLabels: true
    addServicesLabels: true
```

Add to Prometheus scrape config:
```yaml
scrape_configs:
  - job_name: 'traefik'
    static_configs:
      - targets: ['traefik:8080']
```

**Gain visibility into:**
- HTTP request rates
- Response time percentiles
- Error rates by service
- Certificate expiration dates
- Backend health

#### 9. Implement Dashboards for Key Services

**Create dashboards for:**
- Traefik overview (requests, errors, latency)
- Jellyfin monitoring (if metrics available)
- Storage utilization trends (BTRFS and system SSD)
- Authentication events (TinyAuth/Authelia)

**Export and version control:**
```bash
# Export dashboard JSON from Grafana UI
# Save to: ~/containers/config/grafana/provisioning/dashboards/
# Commit to git
git add ~/containers/config/grafana/provisioning/dashboards/*.json
git commit -m "Add monitoring dashboards"
```

---

## Security Hardening

### Current Security Posture

✅ **What's Good:**
- TinyAuth authentication required for all monitoring UIs
- Containers run rootless (unprivileged)
- Network segmentation isolates monitoring stack
- Read-only volume mounts where possible
- No publicly exposed database ports

⚠️ **Security Gaps:**

### 1. Prometheus and Loki API Exposure

**Risk:** Prometheus and Loki APIs are accessible via Traefik with only TinyAuth protecting them.

**Attack Vectors:**
- Data exfiltration (all metrics and logs readable)
- Query-based DoS (expensive queries can overload services)
- No rate limiting on API endpoints

**Mitigation:**

```yaml
# ~/containers/config/traefik/dynamic/routers.yml
prometheus-secure:
  middlewares:
    - crowdsec-bouncer
    - rate-limit
    - tinyauth@file
    - monitoring-ip-whitelist  # ADD THIS

loki-secure:
  middlewares:
    - crowdsec-bouncer
    - rate-limit
    - tinyauth@file
    - monitoring-ip-whitelist  # ADD THIS

# Create new middleware
# ~/containers/config/traefik/dynamic/middleware.yml
http:
  middlewares:
    monitoring-ip-whitelist:
      ipWhiteList:
        sourceRange:
          - "192.168.1.0/24"  # Local network only
          - "127.0.0.1/32"    # Localhost
```

**Consideration:** Do you need external access to Prometheus/Loki APIs? If not, remove from Traefik entirely and keep them internal-only.

### 2. Grafana Admin Credentials

**Risk:** Admin password stored in Quadlet file (plaintext)

**Current Location:** `~/.config/containers/systemd/grafana.container`
```ini
Environment=GF_SECURITY_ADMIN_PASSWORD=<password from secrets file>
```

**Better Approach:**

```bash
# Store in secrets directory
echo -n '<your-secure-password>' > ~/containers/secrets/grafana-admin-password
chmod 600 ~/containers/secrets/grafana-admin-password

# Update grafana.container
[Container]
Secret=grafana-admin-password,type=env,target=GF_SECURITY_ADMIN_PASSWORD
```

### 3. No Audit Logging

**Risk:** Cannot detect unauthorized access or suspicious queries

**Missing:**
- Who accessed which dashboards
- What queries were run
- Failed authentication attempts
- Configuration changes

**Solution:** Enable Grafana audit logging

```ini
# grafana.container
[Container]
Environment=GF_LOG_MODE=console file
Environment=GF_LOG_LEVEL=info
Environment=GF_LOG_CONSOLE_FORMAT=json

# Create grafana.ini with audit settings
Volume=%h/containers/config/grafana/grafana.ini:/etc/grafana/grafana.ini:ro,Z
```

```ini
# ~/containers/config/grafana/grafana.ini
[auditing]
enabled = true
loggers = console

[log]
mode = console file
level = info

[log.file]
file_name = /var/lib/grafana/logs/grafana.log
max_lines = 1000000
max_size_shift = 28
daily_rotate = true
max_days = 7
```

### 4. Sensitive Data in Logs

**Risk:** Logs may contain sensitive information (API keys, tokens, passwords)

**Current State:** No log filtering or redaction

**Mitigation in Promtail:**

```yaml
# ~/containers/config/promtail/promtail-config.yml
scrape_configs:
  - job_name: systemd-journal
    pipeline_stages:
      - json:
          expressions:
            message: MESSAGE

      # Redact sensitive patterns
      - replace:
          expression: '(password|token|api[_-]?key)(["\s:=]+)([^\s"]+)'
          replace: '$1$2***REDACTED***'

      - replace:
          expression: 'Bearer [A-Za-z0-9\-\._~\+\/]+=*'
          replace: 'Bearer ***REDACTED***'

      - labels:
          priority:
          unit:
```

### 5. No mTLS Between Components

**Current:** Plain HTTP between all monitoring components

**Risk:** Traffic sniffing within the monitoring network (low risk, but defense-in-depth)

**Enhancement:** Enable TLS for internal communication

```yaml
# Prometheus remote write with TLS
remote_write:
  - url: https://loki:3100/loki/api/v1/push
    tls_config:
      ca_file: /etc/prometheus/ca.crt
      cert_file: /etc/prometheus/client.crt
      key_file: /etc/prometheus/client.key
```

**Complexity vs. Benefit:** Probably not worth it for a homelab, but document as an option for paranoid deployments.

---

## Storage Policy Review

### Current Retention Policies

| Component | Retention | Storage Location | Current Size | Projected Size (Full Retention) |
|-----------|-----------|------------------|--------------|--------------------------------|
| Prometheus | 15 days | BTRFS pool | 36 MB | ~50-100 MB |
| Loki | 7 days | BTRFS pool | 8.7 MB | ~15-20 MB |
| Journal Export | Unbounded | System SSD | 26 MB | ⚠️ **Unbounded** |

### Problem Areas

#### 1. Journal Export File Growth

**Issue:** `~/containers/data/journal-export/journal.log` has no rotation policy

**Current Growth Rate:** ~26 MB in ~10 hours = 62 MB/day

**30-Day Projection:** 1.86 GB on system SSD (eating into the precious 10GB free space)

**CRITICAL ACTION REQUIRED:**

Implement logrotate immediately:

```bash
# Create systemd timer for logrotate
cat > ~/.config/systemd/user/journal-logrotate.service <<'EOF'
[Unit]
Description=Rotate journal export logs

[Service]
Type=oneshot
ExecStart=/usr/bin/truncate -s 0 %h/containers/data/journal-export/journal.log.1
ExecStart=/usr/bin/mv %h/containers/data/journal-export/journal.log %h/containers/data/journal-export/journal.log.1
ExecStart=/usr/bin/touch %h/containers/data/journal-export/journal.log
ExecStartPost=/usr/bin/systemctl --user kill -s SIGHUP journal-export.service
EOF

cat > ~/.config/systemd/user/journal-logrotate.timer <<'EOF'
[Unit]
Description=Rotate journal export logs daily

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now journal-logrotate.timer
```

#### 2. Retention Alignment with Use Cases

**Question:** Do you actually need 15 days of metrics and 7 days of logs?

**Usage Pattern Analysis:**

- **Troubleshooting Window:** Most issues investigated within 24-48 hours
- **Trend Analysis:** Week-over-week comparisons useful (7 days minimum)
- **Capacity Planning:** Monthly trends needed (30 days ideal)

**Recommendation:**

**Option A - Reduce Retention (Minimal Storage)**
- Prometheus: 7 days (sufficient for short-term troubleshooting)
- Loki: 3 days (reduce by half)
- Saves ~50% storage, still covers most use cases

**Option B - Extend Retention (Better Insights)**
- Prometheus: 30 days (enable monthly trend analysis)
- Loki: 7 days (keep current, logs less useful long-term)
- Storage increase: 100-150 MB (negligible on 4.6TB BTRFS pool)

**Recommended Choice: Option B** - Storage is abundant on BTRFS pool, extended metrics retention enables capacity planning.

#### 3. Backup Strategy

**Current State:** No backups of monitoring data

**Risk Assessment:**
- Metrics data: Loss acceptable (regenerates over time)
- Logs: Historical loss acceptable (current logs most valuable)
- **Grafana dashboards:** Loss would be painful to recreate
- **Grafana datasources/config:** Loss breaks everything

**Required Backups:**

```bash
# Add to existing backup script or create new one
#!/bin/bash
# ~/containers/scripts/backup-monitoring-config.sh

BACKUP_DIR=~/containers/backups/monitoring-$(date +%Y%m%d-%H%M%S)
mkdir -p "$BACKUP_DIR"

# Backup Grafana config and dashboards
cp -r ~/containers/config/grafana "$BACKUP_DIR/"
cp -r ~/containers/data/grafana/grafana.db "$BACKUP_DIR/" 2>/dev/null

# Backup Prometheus config
cp -r ~/containers/config/prometheus "$BACKUP_DIR/"

# Backup Loki config
cp -r ~/containers/config/loki "$BACKUP_DIR/"

# Backup Promtail config
cp -r ~/containers/config/promtail "$BACKUP_DIR/"

# Create tarball
tar -czf "$BACKUP_DIR.tar.gz" -C "$BACKUP_DIR/.." "$(basename "$BACKUP_DIR")"
rm -rf "$BACKUP_DIR"

# Keep only last 7 backups
ls -t ~/containers/backups/monitoring-*.tar.gz | tail -n +8 | xargs -r rm

echo "Monitoring config backed up to $BACKUP_DIR.tar.gz"
```

Run daily via systemd timer:

```ini
# ~/.config/systemd/user/backup-monitoring.timer
[Unit]
Description=Daily monitoring config backup

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
```

#### 4. Consider Remote Storage for Long-Term Retention

**Use Case:** Keep metrics for capacity planning without local storage overhead

**Solution:** Prometheus remote write to long-term storage

**Options:**
- Grafana Cloud Free Tier (10k series, 50GB logs)
- Mimir/Thanos (self-hosted multi-tenant storage)
- S3-compatible storage (Backblaze B2, Wasabi)

**Example: Grafana Cloud Integration**

```yaml
# ~/containers/config/prometheus/prometheus.yml
remote_write:
  - url: https://prometheus-prod-XX-prod-us-central-0.grafana.net/api/prom/push
    basic_auth:
      username: 123456
      password: glc_XXXXXXXXXXXXXXXXXXXXXXXXXXXXX
    write_relabel_configs:
      - source_labels: [__name__]
        regex: 'node_.*'  # Only send node_exporter metrics
        action: keep
```

**Cost Analysis:**
- Free tier: 10,000 series (plenty for homelab)
- Retention: 14 days free, longer with paid plan
- Benefit: Offsite backup + unlimited retention options

---

## Using Monitoring Data to Improve Your Homelab

### Data-Driven Decision Making

The monitoring stack is not just for troubleshooting—it's a feedback loop for continuous improvement. Here's how to use the data you're collecting to make informed decisions about your homelab architecture.

---

### 1. Right-Sizing Container Resources

**Question:** Are your containers over-provisioned or under-provisioned?

**Analysis Approach:**

Query historical resource usage:

```promql
# Average memory usage per container (requires cAdvisor)
avg_over_time(container_memory_usage_bytes{name!=""}[7d]) / 1024 / 1024

# Peak CPU usage per container
max_over_time(rate(container_cpu_usage_seconds_total{name!=""}[5m])[7d:])

# Storage I/O by container
rate(container_fs_writes_bytes_total{name!=""}[7d])
```

**Decision Matrix:**

| Observation | Action |
|------------|--------|
| Memory usage < 50% of limit | Reduce memory limit, reclaim RAM |
| Memory usage > 85% consistently | Increase limit to prevent OOM kills |
| CPU usage < 10% average | Consider consolidating services |
| High CPU spikes during specific times | Investigate staggering scheduled tasks |

**Example Finding:**

```
Prometheus: 45 MB average, 120 MB peak → Set limit to 256 MB
Grafana: 80 MB average, 150 MB peak → Set limit to 256 MB
Loki: 35 MB average, 85 MB peak → Set limit to 128 MB
```

---

### 2. Identifying Services to Consolidate or Decompose

**Question:** Is your current service architecture optimal?

**Analyze Service Interaction Patterns:**

```logql
# How often does Traefik route to each backend?
sum by (service) (count_over_time({unit="traefik.service"} | json | __error__="" [7d]))

# Which services restart most frequently?
count_over_time({syslog_id="podman"} |= "restart" | json | name != "" [7d])
```

**Findings Might Reveal:**

- **Low-traffic services:** Jellyfin accessed 10x more than Prometheus → Maybe Prometheus doesn't need TLS/auth overhead
- **Tightly coupled services:** Authelia and Redis always restart together → Consider bundling in a pod
- **Unused services:** A service with zero log entries in 7 days → Candidate for removal

---

### 3. Capacity Planning and Storage Growth Trends

**Question:** When will you run out of space?

**Query Storage Trends:**

```promql
# Filesystem usage trend (bytes)
node_filesystem_avail_bytes{mountpoint="/"}

# Predict when root will be full (linear regression)
predict_linear(node_filesystem_avail_bytes{mountpoint="/"}[7d], 30*24*3600) < 0
```

**Create Alert:**

```yaml
# Prometheus alert rule
- alert: DiskWillFillIn7Days
  expr: predict_linear(node_filesystem_avail_bytes{mountpoint="/"}[7d], 7*24*3600) < 1e9
  for: 1h
  annotations:
    summary: "System disk will fill in 7 days"
    description: "Based on current growth rate, {{ $labels.instance }} root filesystem will be full in 7 days"
```

**Data-Driven Actions:**

- Identify log growth sources: `du -sh ~/containers/data/* | sort -h`
- Archive or prune old container images: `podman image prune -a`
- Move more data to BTRFS pool
- Schedule cleanup jobs for temp files

---

### 4. Network Optimization

**Question:** Is network bandwidth a bottleneck? Are there unexpected traffic patterns?

**Analyze Network Usage:**

```promql
# Inbound bandwidth by interface (Mbps)
rate(node_network_receive_bytes_total{device="enp3s0"}[5m]) * 8 / 1e6

# Outbound bandwidth by interface (Mbps)
rate(node_network_transmit_bytes_total{device="enp3s0"}[5m]) * 8 / 1e6

# Network errors
rate(node_network_receive_errs_total[5m])
```

**Findings Might Reveal:**

- High traffic during specific hours → Schedule backups/maintenance during low-traffic windows
- Sustained high bandwidth → Consider quality-of-service (QoS) rules
- Network errors correlating with service issues → Investigate hardware or switch problems

---

### 5. Identifying Security Anomalies

**Question:** Are there unusual access patterns or potential security issues?

**Query Authentication Events:**

```logql
# Failed authentication attempts
{unit="tinyauth.service"} |= "failed" | json

# Unusual access times (outside business hours)
{unit="traefik.service"} | json | __timestamp__ < bool 08:00 or __timestamp__ > bool 22:00

# Requests from unexpected countries (requires GeoIP in Traefik)
{unit="traefik.service"} | json | ClientCountry != "US"
```

**Create Security Dashboard:**

- Failed auth attempts per hour
- Unique IPs accessing services
- Geographic distribution of traffic
- HTTP error rate trends (4xx, 5xx)

**Data-Driven Security Actions:**

- Block repeat offender IPs in CrowdSec
- Implement rate limiting on auth endpoints
- Add additional auth factor for external access
- Restrict admin interfaces to LAN only

---

### 6. Service Health Scoring

**Question:** Which services are the most/least reliable?

**Create a "Service Health Score" Dashboard:**

```promql
# Uptime percentage (requires service up metric)
avg_over_time(up{job="services"}[7d]) * 100

# Restart count
changes(container_start_time_seconds[7d])

# Error log rate
rate({unit=~".*.service", priority="3"}[7d])
```

**Scoring Formula:**

```
Health Score = (Uptime% * 0.5) + ((1 - RestartCount/10) * 0.3) + ((1 - ErrorRate) * 0.2)
```

**Use Scores to Prioritize:**

- Low-scoring services need attention (debugging, resource allocation, redesign)
- High-scoring services are stable (can reduce monitoring frequency)

---

### 7. Cost-Benefit Analysis of Monitoring Overhead

**Question:** Is the monitoring stack justifying its resource consumption?

**Calculate Monitoring Overhead:**

```promql
# CPU used by monitoring stack
sum(rate(container_cpu_usage_seconds_total{name=~"grafana|prometheus|loki|promtail"}[5m]))

# Memory used by monitoring stack
sum(container_memory_usage_bytes{name=~"grafana|prometheus|loki|promtail"}) / 1024 / 1024 / 1024

# Percentage of total system resources
(monitoring_cpu / total_cpu) * 100
(monitoring_memory / total_memory) * 100
```

**Decision Point:**

- If monitoring consumes > 10% of system resources → Consider optimizations (reduce retention, scrape intervals)
- If monitoring reveals multiple issues preventing downtime → ROI is high, keep it
- If monitoring data goes unused → Scale back or simplify

---

### 8. Experiment with Confidence

**The Ultimate Benefit:** With comprehensive monitoring, you can experiment safely.

**Workflow:**

1. **Baseline:** Observe current metrics for 24 hours
2. **Change:** Modify configuration (e.g., adjust Traefik rate limits, change Prometheus scrape interval)
3. **Observe:** Monitor impact over 24-48 hours
4. **Decide:** Keep change if metrics improve, revert if they degrade
5. **Document:** Record decision and rationale in git commit

**Example Experiment Log:**

```
Experiment: Reduce Prometheus scrape interval from 15s to 30s
Date: 2025-11-08
Hypothesis: Will reduce CPU usage by ~50% with minimal dashboard impact

Results (48 hours):
- CPU: Reduced from 5% to 3% (40% decrease)
- Dashboard responsiveness: No noticeable change
- Query performance: Identical
- Storage growth: Reduced from 2MB/day to 1MB/day

Decision: Keep change. Savings are measurable, no user impact.
```

---

### 9. Tail-End Optimization

**Question:** What's the "long tail" of issues hiding in your logs?

**Approach:** Aggregate rare errors that individually seem insignificant but collectively indicate systemic issues.

```logql
# Find all unique error messages (sampled)
sum by (MESSAGE) (count_over_time({priority="3"}[7d]))

# Identify services with sporadic errors
count by (unit) ({priority="3"} [7d]) > 0 and < 10
```

**Example Findings:**

- `SELinux denial` appearing 3x/day → Indicates misconfigured volume permissions
- `DNS timeout` occurring sporadically → Points to DNS server instability
- `Connection refused` from specific container → Suggests service start order issue

**Action:** Create tickets/tasks to address each class of rare error.

---

### 10. Building a Continuous Improvement Loop

**Framework:**

```
┌─────────────────┐
│  Monitor        │
│  (Collect data) │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Analyze        │
│  (Query/visualize)│
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Hypothesize    │
│  (Form theories) │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Experiment     │
│  (Make changes) │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Validate       │
│  (Check impact) │
└────────┬────────┘
         │
         └──────────► Document & Repeat
```

**Monthly Review Checklist:**

- [ ] Review top 10 error messages, address root causes
- [ ] Check capacity trends, plan for resource needs 3 months out
- [ ] Analyze service uptime, investigate any degradation
- [ ] Review dashboard usage, retire unused dashboards
- [ ] Update alerting thresholds based on new baselines
- [ ] Export and backup new Grafana dashboards to git
- [ ] Audit security logs for suspicious patterns
- [ ] Evaluate new metrics sources (new services, exporters)

---

## Conclusion

The monitoring stack provides a solid foundation for homelab observability with low resource overhead and reasonable retention policies. However, several areas need attention:

**Immediate Actions Required:**
1. ✅ Implement log rotation for journal-export file (critical for system SSD health)
2. ✅ Backup Grafana dashboards and configs to git
3. ✅ Add IP whitelisting to Prometheus/Loki API endpoints

**Short-Term Improvements (Next 2 Weeks):**
1. Deploy cAdvisor for per-container resource visibility
2. Enable Traefik metrics endpoint
3. Create dashboards for Traefik, storage trends, and service health
4. Implement audit logging in Grafana

**Long-Term Enhancements (Next Month):**
1. Evaluate moving to system-mode Promtail for full journal access
2. Add Alertmanager for proactive notifications
3. Consider extending Prometheus retention to 30 days
4. Explore Grafana Cloud for offsite backup and extended retention

**Philosophical Note:**

Monitoring is not a "set it and forget it" system—it's a living tool that should evolve with your homelab. Use the data to inform decisions, experiment safely, and continuously refine your infrastructure. The goal isn't perfect monitoring; it's *useful* monitoring that helps you run a more reliable, efficient, and secure homelab.

---

## Appendix: Quick Reference

### Service URLs

- Grafana: https://grafana.patriark.org
- Prometheus: https://prometheus.patriark.org
- Loki API: https://loki.patriark.org

### Key Commands

```bash
# Service management
systemctl --user status prometheus.service
systemctl --user restart grafana.service
journalctl --user -u loki.service -f

# Container operations
podman ps | grep -E "grafana|prometheus|loki|promtail"
podman logs -f promtail
podman exec -it grafana sh

# Configuration reload (no restart)
systemctl --user reload prometheus.service  # Reloads prometheus.yml

# Check storage usage
du -sh /mnt/btrfs-pool/subvol7-containers/{prometheus,loki}
du -sh ~/containers/data/journal-export/

# Manual journal export test
journalctl --user -f -o json --since="1 hour ago" | head -n 10

# Query Prometheus from CLI
curl -s 'http://localhost:9090/api/v1/query?query=up' | jq

# Query Loki from CLI
curl -s 'http://localhost:3100/loki/api/v1/labels' | jq
```

### File Locations

```
Configuration:
  ~/containers/config/grafana/
  ~/containers/config/prometheus/prometheus.yml
  ~/containers/config/loki/loki-config.yml
  ~/containers/config/promtail/promtail-config.yml

Quadlets:
  ~/.config/containers/systemd/grafana.container
  ~/.config/containers/systemd/prometheus.container
  ~/.config/containers/systemd/loki.container
  ~/.config/containers/systemd/promtail.container
  ~/.config/containers/systemd/node_exporter.container

User Services:
  ~/.config/systemd/user/journal-export.service

Data:
  /mnt/btrfs-pool/subvol7-containers/prometheus/
  /mnt/btrfs-pool/subvol7-containers/loki/
  ~/containers/data/grafana/
  ~/containers/data/journal-export/journal.log

Traefik Integration:
  ~/containers/config/traefik/dynamic/routers.yml
```

### Useful Grafana Queries (Copy-Paste Ready)

**System Overview:**
- CPU: `100 - (avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)`
- Memory: `100 * (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))`
- Disk: `100 - ((node_filesystem_avail_bytes{mountpoint="/"} * 100) / node_filesystem_size_bytes)`
- Load: `node_load1`, `node_load5`, `node_load15`

**Log Queries:**
- Errors: `{job="systemd-journal", priority="3"}`
- Warnings: `{job="systemd-journal", priority="4"}`
- Container restarts: `{syslog_id="podman"} |= "restart"`
- Auth failures: `{unit="tinyauth.service"} |= "fail"`

---

**Document Version:** 1.0
**Last Updated:** 2025-11-06
**Next Review:** 2025-12-06
