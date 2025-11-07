# ADR-001: Monitoring Stack Architecture (Prometheus + Grafana + Loki)

**Date:** 2025-11-06
**Status:** Accepted
**Decided by:** System architect
**Category:** Monitoring & Observability

---

## Context

After deploying core services (Traefik, Jellyfin, TinyAuth), the homelab lacked **observability**:
- No visibility into system health
- No metrics history (CPU, memory, disk)
- No centralized logging
- No alerting when things break
- Debugging required SSH + manual log inspection

### The Observability Problem

**Without monitoring, you're flying blind:**
- "Why is Jellyfin slow?" → No metrics to answer
- "Did the server go down last night?" → No history
- "How much disk space left?" → Manual `df -h` checks
- "What caused the service crash?" → Lost logs

### The Scale Question

This homelab runs:
- 1 physical host (fedora-htpc)
- ~12 containerized services
- Future: possibly 20-30 services

**Not "big data" scale** - but needs production-grade observability.

---

## Decision

**Deploy the Prometheus + Grafana + Loki stack for comprehensive observability.**

**Components:**
- **Prometheus:** Metrics collection and storage (time-series database)
- **Grafana:** Visualization and dashboards
- **Loki:** Log aggregation and search
- **Promtail:** Log shipping to Loki
- **Node Exporter:** Host metrics (CPU, memory, disk, network)
- **Alertmanager:** Alert routing and notification management

**Network:** Dedicated `systemd-monitoring` network (10.89.4.0/24)

---

## Rationale

### Why This Stack?

**1. Industry Standard**
- Used in production by thousands of companies
- Transferable skills to professional environments
- Massive ecosystem of exporters and integrations

**2. Open Source & Self-Hosted**
- No vendor lock-in
- No cloud costs
- Complete control over data

**3. Perfect Scale**
- Lightweight enough for single-host homelab
- Powerful enough to scale to dozens of services
- No heavyweight requirements (no Elasticsearch cluster needed)

**4. Learning Value**
- Understanding metrics vs logs vs traces
- Query languages (PromQL, LogQL)
- Dashboard design
- Alert engineering

### Component Choices

#### Prometheus over Graphite/InfluxDB
- **Pull model** better for dynamic environments
- **Better service discovery** for containers
- **Powerful query language** (PromQL)
- **Native Kubernetes support** (future-proof)

#### Grafana over Built-in UIs
- **Single pane of glass** for metrics + logs
- **Beautiful dashboards** that are joy to use
- **Provisioning support** (configuration as code)
- **Alerting built-in**

#### Loki over Elasticsearch (ELK Stack)
- **Much lighter** (no JVM, no resource-hungry indexing)
- **Label-based indexing** matches Prometheus mental model
- **Perfect for small-medium log volumes**
- **Integrates seamlessly** with Grafana

#### Alertmanager over Grafana Alerts Alone
- **Dedicated alert routing** and deduplication
- **Flexible notification channels** (Discord, email, PagerDuty)
- **Silence management** for maintenance windows
- **Alert grouping** and inhibition rules

---

## Architecture

### Data Flow

```
Services → Prometheus (scrapes :9090)
           ↓
        Metrics DB (15-day retention)
           ↓
        Alert Rules (evaluated every 15s)
           ↓
        Alertmanager (routes & groups)
           ↓
        Discord Relay → Discord Webhooks

Logs → Promtail → Loki → Grafana
Metrics → Prometheus → Grafana
```

### Network Topology

```
systemd-monitoring (10.89.4.0/24)
├── prometheus:9090
├── grafana:3000 (also on reverse_proxy for external access)
├── loki:3100
├── promtail:9080
├── node_exporter:9100
├── alertmanager:9093
└── alert-discord-relay:9095
```

**Design principle:** Monitoring services isolated on dedicated network, only Grafana exposed via Traefik.

### Storage Strategy

**Metrics (Prometheus):**
- Location: `/mnt/btrfs-pool/subvol7-containers/prometheus`
- NOCOW enabled (`chattr +C`) for database performance
- Retention: 15 days (configurable)

**Logs (Loki):**
- Location: `/mnt/btrfs-pool/subvol7-containers/loki`
- NOCOW enabled for performance
- Retention: 7 days (configurable)

**Dashboards (Grafana):**
- Provisioned from: `~/containers/config/grafana/provisioning/`
- Database: `~/containers/data/grafana` (SQLite)

**Why BTRFS pool instead of system SSD:**
- System SSD only 128GB (at 51% usage)
- Metrics/logs grow continuously
- BTRFS pool has 4.6TB free

**Why NOCOW:**
- Database write patterns (lots of small updates)
- COW (copy-on-write) causes fragmentation and overhead
- NOCOW provides much better performance for databases

---

## Consequences

### What Becomes Possible

✅ **Proactive monitoring:** See issues before they become outages
✅ **Historical analysis:** "What happened last Tuesday?"
✅ **Capacity planning:** Track growth trends
✅ **Alert notifications:** Discord alerts when things break
✅ **Debugging:** Centralized logs with powerful search
✅ **Performance optimization:** Identify bottlenecks with data

### What Becomes More Complex

⚠️ **Resource usage:** ~500MB RAM for monitoring stack
⚠️ **Storage management:** Need to manage retention policies
⚠️ **Alert fatigue risk:** Need careful alert tuning
⚠️ **Dashboard maintenance:** Dashboards need updates as system evolves

### Accepted Trade-offs

- **Resources for monitoring** for **visibility into everything**
- **Learning multiple query languages** for **powerful troubleshooting**
- **Initial setup complexity** for **long-term operational ease**

---

## Alternatives Considered

### Alternative 1: Cloud Monitoring (Grafana Cloud, Datadog, etc.)

**Pros:**
- No infrastructure to manage
- Managed retention and scaling
- Professional alerting
- Beautiful pre-built dashboards

**Cons:**
- Monthly cost ($20-100+ per month)
- Vendor lock-in
- Send metrics/logs outside homelab
- Less learning value
- Overkill for homelab scale

**Verdict:** ❌ Rejected - Defeats purpose of self-hosted homelab

### Alternative 2: ELK Stack (Elasticsearch, Logstash, Kibana)

**Pros:**
- Powerful full-text search
- Mature ecosystem
- Industry standard

**Cons:**
- **Resource heavy:** Elasticsearch JVM requires 2-4GB RAM minimum
- More complex setup and tuning
- Overkill for log volumes (<1GB/day)
- Doesn't handle metrics (would need separate solution)

**Verdict:** ❌ Rejected - Too resource-intensive for benefit at this scale

### Alternative 3: Simple Logging (rsyslog + grep)

**Pros:**
- Minimal resource usage
- Simple to understand
- Built into Linux

**Cons:**
- No metrics collection
- No visualization
- No alerting
- Manual log inspection
- No retention management

**Verdict:** ❌ Rejected - Too primitive for production-grade homelab

### Alternative 4: Netdata

**Pros:**
- Beautiful real-time dashboards
- Zero-configuration monitoring
- Very low resource usage
- Instant gratification

**Cons:**
- Limited historical data (by default)
- Not industry-standard skill
- Less powerful querying
- Weaker alerting
- Doesn't replace log aggregation

**Verdict:** ⚠️ Considered for future addition as **complement** (real-time view), not replacement

---

## Implementation Details

### Metrics Collection

**Scrape targets:**
- `prometheus:9090` (self-monitoring)
- `node_exporter:9100` (host metrics)
- `grafana:3000/metrics` (Grafana metrics)
- `traefik:8080/metrics` (Traefik performance)
- `loki:3100/metrics` (Loki metrics)

**Scrape interval:** 15 seconds
**Retention:** 15 days (1,296,000 seconds)

### Log Collection

**Sources:**
- All container logs via Promtail (Docker API)
- systemd journal (via journal-export bridge - rootless workaround)

**Labels:**
- `job`, `instance`, `container_name`, `service`

**Retention:** 7 days

### Alerting Rules

**Critical alerts (immediate notification):**
- Host down (>5 min)
- Disk space <10%
- Certificate expiring <7 days
- Monitoring stack down

**Warning alerts (business hours only):**
- Disk space <20%
- High memory/CPU usage
- Container restarts
- Certificate expiring <30 days

### Dashboard Strategy

**Provisioned dashboards:**
- Node Exporter Full (system metrics)
- Traefik Overview (reverse proxy performance)
- Service Health Overview (all services at a glance)

**Manual dashboards:**
- Custom service-specific dashboards
- Saved in Grafana database, exported to git periodically

---

## Validation

### Success Criteria

- [x] Metrics collected from all services
- [x] Logs aggregated from all containers
- [x] Dashboards showing real-time data
- [x] Alerts firing correctly (tested with disk space warning)
- [x] Discord notifications working
- [x] Historical data retained for 15 days
- [x] Performance impact <5% CPU, <500MB RAM

### Metrics (2025-11-07)

**Resource Usage:**
- prometheus: ~80MB RAM
- grafana: ~120MB RAM
- loki: ~60MB RAM
- promtail: ~30MB RAM
- node_exporter: ~15MB RAM
- alertmanager: ~25MB RAM
- alert-discord-relay: ~10MB RAM
- **Total:** ~340MB RAM (0.34GB) ✅ Under budget

**Data Ingestion:**
- Prometheus: 5 targets, 15s scrape interval, ~36MB storage
- Loki: 26 log streams, 8.06MB logs (first hour)

**Uptime:**
- All monitoring services: 6+ hours healthy
- No service restarts
- No alert storms

---

## Challenges and Solutions

### Challenge 1: System Disk Space (94% full)

**Problem:** Initial deployment filled system SSD

**Solution:**
- Moved Prometheus and Loki data to BTRFS pool
- Enabled NOCOW for database performance
- Implemented log rotation for journal-export
- Result: System SSD back to 51% usage ✅

### Challenge 2: Rootless Journal Access

**Problem:** Promtail can't access `/var/log/journal/` (SELinux + rootless)

**Solution:**
- Created journal-export systemd user service
- Bridges journalctl output to file
- Promtail reads file instead
- Trade-off: Only user journal, not system journal (acceptable)

### Challenge 3: Dashboard UID Conflicts

**Problem:** Grafana datasource provisioning failed (missing UIDs)

**Solution:**
- Added explicit UIDs to datasource configs:
  - Prometheus: `uid: prometheus`
  - Loki: `uid: loki`
- Dashboards reference by UID instead of name

### Challenge 4: Traefik Not Scrapeable

**Problem:** Prometheus couldn't reach Traefik metrics

**Solution:**
- Added Traefik to monitoring network (multi-network)
- Enabled metrics endpoint in traefik.yml
- Result: Traefik metrics now available ✅

---

## Future Enhancements

### Phase 1: Enrichment (In Progress)
- [x] Add Traefik metrics
- [x] Create Traefik performance dashboard
- [ ] Add CrowdSec metrics
- [ ] Per-container resource metrics (cAdvisor - attempted, blocked by rootless)

### Phase 2: Advanced Alerting
- [ ] SLO-based alerting (error budget)
- [ ] Alert routing by severity and time
- [ ] Runbook links in alert annotations
- [ ] Multi-channel notifications (Discord + email)

### Phase 3: Long-term Storage
- [ ] Prometheus remote write to long-term storage
- [ ] Log archival to object storage
- [ ] 90-day retention for critical metrics

### Phase 4: Distributed Monitoring (If Multi-Host)
- [ ] Federated Prometheus across hosts
- [ ] Centralized Grafana
- [ ] Distributed tracing with Tempo

---

## References

- **Guides:**
  - `docs/40-monitoring-and-documentation/guides/monitoring-stack.md`
  - `docs/99-reports/20251106-monitoring-stack-deployment-summary.md`

- **External:**
  - [Prometheus Documentation](https://prometheus.io/docs/)
  - [Grafana Documentation](https://grafana.com/docs/grafana/latest/)
  - [Loki Documentation](https://grafana.com/docs/loki/latest/)

- **Related ADRs:**
  - ADR-001 (Rootless Containers) - influenced monitoring approach
  - ADR-002 (Systemd Quadlets) - deployment method

---

## Retrospective (2025-11-07)

**Assessment after 24 hours of operation:**

✅ **Excellent Decision** - The visibility is transformative

**What Worked Exceptionally Well:**
- Grafana dashboards are beautiful and useful
- PromQL is powerful once you understand it
- LogQL makes log search actually pleasant
- Discord alerts provide perfect notification level
- Resource usage is lower than expected

**Unexpected Wins:**
- Historical data already proved valuable (traced performance issue to specific time)
- Alert tuning was easier than anticipated
- Dashboard provisioning makes config-as-code trivial
- Traefik metrics revealed bottlenecks we didn't know existed

**Challenges:**
- Journal access workaround is hacky but functional
- cAdvisor incompatibility is disappointing (would be nice to have)
- Dashboard maintenance will be ongoing
- Alert tuning is iterative process

**What We'd Do Differently:**
- Start with monitoring **before** deploying services (next project)
- Allocate more time for dashboard creation (rushed in deployment)
- Document alert runbooks from day 1
- Consider Netdata for real-time supplement (future)

**Value Assessment:**

**Before monitoring:** "Is the service up?" = SSH + `podman ps`
**After monitoring:** Open Grafana, see everything at a glance ✨

**The difference is night and day.** This might be the highest-value addition to the homelab yet.

**Would we make the same decision again?** 💯 **Absolutely.**

In fact, we'd deploy monitoring **earlier** in the next homelab build. The visibility it provides is invaluable.
