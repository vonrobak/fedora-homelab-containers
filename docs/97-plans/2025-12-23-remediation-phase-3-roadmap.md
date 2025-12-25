# Remediation Arsenal Phase 3: Advanced Features Roadmap

**Date Created:** 2025-12-23
**Status:** 🔄 In Progress
**Category:** Autonomous Operations / Remediation Framework
**Estimated Duration:** 4-6 weeks

---

## Executive Summary

This roadmap outlines the implementation of 6 advanced features for the auto-remediation framework, building on the 7 playbooks completed in Phase 2A. The progression follows a **dependency-driven approach**: observability → scheduling → integration → orchestration → analytics.

**Key Principle:** Each phase builds on the previous, creating a robust foundation before adding complexity.

---

## Phase Overview

| Phase | Feature | Duration | Complexity | Value | Dependencies |
|-------|---------|----------|------------|-------|--------------|
| 1 | Prometheus Metrics | 2-3 days | Low | High | None |
| 2 | Scheduled Automation | 1-2 days | Low | Medium | Phase 1 |
| 3 | Autonomous Integration | 2-3 days | Medium | High | Phases 1-2 |
| 4 | Alertmanager Webhooks | 3-5 days | High | Very High | Phases 1-3 |
| 5 | Multi-Playbook Chaining | 4-6 days | Very High | High | Phases 1-4 |
| 6 | History Analytics | 3-4 days | Medium | Medium | Phases 1-5 |

**Total Estimated Duration:** 15-23 days (3-5 weeks)

---

## Phase 1: Observability Foundation - Prometheus Metrics

### Objective
Instrument all remediation playbooks with Prometheus metrics to track effectiveness, execution time, success rates, and impact.

### Why First?
- **Foundation for all other phases:** Can't validate effectiveness without metrics
- **Zero dependencies:** Uses existing Prometheus infrastructure
- **Immediate value:** Visibility into current remediation operations
- **Low risk:** Read-only metrics, no operational changes

### Implementation Details

**Metrics to Track:**
```prometheus
# Execution metrics
remediation_playbook_executions_total{playbook, status}  # Counter
remediation_playbook_duration_seconds{playbook}          # Histogram
remediation_playbook_last_success_timestamp{playbook}    # Gauge

# Impact metrics
remediation_disk_space_reclaimed_bytes{playbook}         # Gauge
remediation_services_restarted_total{playbook, service}  # Counter
remediation_oom_events_detected_total{service}           # Counter

# Effectiveness metrics
remediation_predictive_accuracy{resource}                # Gauge (0-1)
remediation_self_healing_success_rate{root_cause}        # Gauge (0-1)
remediation_database_vacuum_rows_removed{database}       # Gauge
```

**Implementation Approach:**
1. Create `prometheus-exporter.sh` script for remediation metrics
2. Add textfile collector directory: `/var/lib/prometheus/node-exporter/remediation.prom`
3. Instrument `apply-remediation.sh` to write metrics after each execution
4. Create Grafana dashboard: "Remediation Effectiveness"
5. Add alerting rules for remediation failures

**Deliverables:**
- [ ] `scripts/remediation-prometheus-exporter.sh`
- [ ] Metrics integration in `apply-remediation.sh`
- [ ] Grafana dashboard JSON
- [ ] Prometheus alerting rules
- [ ] Documentation update

**Success Criteria:**
- All 7 playbooks emit metrics
- Metrics visible in Prometheus within 5 minutes of execution
- Grafana dashboard displays remediation history
- Alerts trigger on consecutive failures

---

## Phase 2: Scheduled Automation - Systemd Timers

### Objective
Schedule low-risk maintenance operations (database maintenance, predictive checks) to run automatically on optimal schedules.

### Why Second?
- **Quick wins:** Builds on existing systemd timer infrastructure
- **Proven patterns:** Similar to `auto-doc-update.timer` and `autonomous-operations.timer`
- **Low risk:** Maintenance operations are non-disruptive
- **Validates Phase 1:** Scheduled runs generate metrics for trending

### Implementation Details

**Timers to Create:**

1. **database-maintenance.timer**
   - **Schedule:** Weekly on Sunday at 03:00 (low-traffic window)
   - **Playbook:** `database-maintenance`
   - **Target:** PostgreSQL VACUUM, Redis memory analysis
   - **Confirmation:** YES (required by playbook)

2. **predictive-maintenance-check.timer**
   - **Schedule:** Daily at 06:00 (before autonomous-operations at 06:30)
   - **Playbook:** `predictive-maintenance`
   - **Purpose:** Daily forecasting, even when not critical
   - **Confirmation:** NO (read-only analytics)

**File Structure:**
```
~/.config/systemd/user/
├── database-maintenance.service
├── database-maintenance.timer
├── predictive-maintenance-check.service
└── predictive-maintenance-check.timer
```

**Integration Points:**
- Metrics from Phase 1 track scheduled execution
- Logs written to systemd journal (visible via `journalctl --user`)
- Decision log integration for audit trail

**Deliverables:**
- [ ] 2 systemd service units
- [ ] 2 systemd timer units
- [ ] Enable and start timers
- [ ] Add to `systemd/README.md`
- [ ] Verify first scheduled execution

**Success Criteria:**
- Timers appear in `systemctl --user list-timers`
- First execution completes successfully
- Metrics updated in Prometheus
- Journal logs show execution history

---

## Phase 3: Autonomous Integration - Predictive Maintenance in OODA Loop

### Objective
Integrate predictive-maintenance playbook into the daily autonomous operations cycle, enabling proactive remediation before issues occur.

### Why Third?
- **Natural evolution:** Extends existing autonomous-operations framework
- **Proven reliability:** Phases 1-2 validate predictive-maintenance effectiveness
- **High impact:** Shifts from reactive to proactive operations
- **Controlled rollout:** Starts with high-confidence predictions only

### Implementation Details

**Modifications to `autonomous-check.sh`:**

Add predictive analysis to the Observe phase:
```bash
# New observation: Predictive forecasts
PREDICTIONS=$(~/containers/scripts/predictive-analytics/predict-resource-exhaustion.sh --output json)

# Parse predictions for critical/warning severity
CRITICAL_PREDICTIONS=$(echo "$PREDICTIONS" | jq '[.[] | select(.severity == "critical")]')

# Add to observations
if [ -n "$CRITICAL_PREDICTIONS" ]; then
    OBSERVATIONS+=("PREDICTIVE: Critical resource exhaustion forecasted")
fi
```

**Decision Logic:**
```bash
# In Orient → Decide phase
if [[ "$OBSERVATIONS" =~ "PREDICTIVE: Critical" ]]; then
    CONFIDENCE=85  # High confidence in predictive analytics
    RISK="low"     # Preemptive cleanup is low-risk

    if [ $CONFIDENCE -gt 80 ] && [ "$RISK" = "low" ]; then
        RECOMMENDED_ACTIONS+=("playbook:predictive-maintenance")
    fi
fi
```

**Safety Controls:**
- Only act on "critical" severity forecasts (>85% utilization in 7 days)
- Minimum 80% confidence threshold
- Circuit breaker: Pause if prediction accuracy <60%
- Override: Add `predictive-maintenance` to service overrides if needed

**Deliverables:**
- [ ] Modify `autonomous-check.sh` (Observe phase)
- [ ] Update decision matrix with predictive triggers
- [ ] Add circuit breaker for low accuracy
- [ ] Test with simulated critical forecast
- [ ] Update `autonomous-operations.md` guide

**Success Criteria:**
- Autonomous operations detect critical predictions
- Remediation triggered automatically when confidence >80%
- Metrics show preemptive actions reducing actual incidents
- No false positive remediation spam

---

## Phase 4: Reactive Automation - Alertmanager Webhook Integration

### Objective
Enable Alertmanager to trigger remediation playbooks automatically when alerts fire, creating a closed-loop incident response system.

### Why Fourth?
- **Closes the loop:** Alert → Remediation → Resolution
- **Complex integration:** Requires webhook endpoint, authentication, routing logic
- **Proven foundation:** Phases 1-3 validate remediation reliability
- **High value:** Reduces MTTR (Mean Time To Resolution)

### Implementation Details

**Architecture:**
```
Alertmanager (alert fires)
    ↓
Webhook: POST http://localhost:9095/webhook
    ↓
remediation-webhook-handler.sh
    ↓
Routing logic (alert → playbook mapping)
    ↓
apply-remediation.sh --playbook <mapped>
    ↓
Metrics updated, logs written
```

**Alert → Playbook Mapping:**
```yaml
# Configuration: .claude/remediation/webhook-routing.yml
routes:
  - alert: HostDiskWillFillIn4Hours
    playbook: disk-cleanup
    confidence: 95

  - alert: ServiceDown
    playbook: self-healing-restart
    parameter: --service ${alert.labels.service}
    confidence: 85

  - alert: HighMemoryPressure
    playbook: resource-pressure
    confidence: 90

  - alert: DatabaseFragmentation
    playbook: database-maintenance
    confidence: 80
    requires_confirmation: true
```

**Webhook Handler Implementation:**

1. **Lightweight HTTP server:** Use `socat` or Python `http.server`
2. **Parse Alertmanager payload:** Extract alert name, labels, annotations
3. **Route to playbook:** Match alert against routing table
4. **Execute with safety checks:**
   - Verify confidence threshold
   - Check circuit breaker state
   - Respect service overrides
   - Log to decision log
5. **Return 200 OK:** Acknowledge webhook

**Security Considerations:**
- **Localhost only:** Bind to `127.0.0.1:9095` (no external access)
- **Authentication:** Shared secret in webhook URL
- **Rate limiting:** Max 5 remediation triggers per hour
- **Idempotency:** Same alert within 5 minutes = single execution

**Deliverables:**
- [ ] `scripts/remediation-webhook-handler.sh`
- [ ] `.claude/remediation/webhook-routing.yml`
- [ ] Systemd service: `remediation-webhook.service`
- [ ] Alertmanager config update
- [ ] Security testing (rate limits, auth)
- [ ] Integration test with simulated alert

**Success Criteria:**
- Webhook receives Alertmanager payloads
- Correct playbook executed based on alert
- Metrics show alert → remediation correlation
- No unauthorized execution
- Rate limiting prevents alert storms

---

## Phase 5: Advanced Orchestration - Multi-Playbook Chaining

### Objective
Enable complex remediation workflows by chaining multiple playbooks together in sequences (e.g., cleanup → restart → verify).

### Why Fifth?
- **Most complex feature:** Requires orchestration logic, dependency management
- **Builds on maturity:** Needs proven reliability from Phases 1-4
- **Power-user feature:** Enables sophisticated remediation strategies
- **Careful design required:** Failure handling, rollback, state management

### Implementation Details

**Use Cases:**

1. **Full Recovery Sequence:**
   ```yaml
   chain: full-recovery
   playbooks:
     - disk-cleanup
     - resource-pressure
     - self-healing-restart --service jellyfin
     - drift-reconciliation
   strategy: continue-on-error
   ```

2. **Predictive Preemption:**
   ```yaml
   chain: predictive-preemption
   playbooks:
     - predictive-maintenance
     - disk-cleanup (if prediction critical)
     - database-maintenance
   strategy: stop-on-failure
   ```

3. **Database Health:**
   ```yaml
   chain: database-health
   playbooks:
     - database-maintenance
     - self-healing-restart --service postgres-immich
   strategy: rollback-on-failure
   ```

**Chain Specification Format:**
```yaml
# .claude/remediation/chains/full-recovery.yml
name: full-recovery
description: Complete system recovery sequence
risk_level: high
requires_confirmation: yes

playbooks:
  - name: disk-cleanup
    timeout: 300

  - name: resource-pressure
    timeout: 180
    condition: memory_available < 20%

  - name: self-healing-restart
    parameters:
      service: jellyfin
    timeout: 120
    on_failure: skip

  - name: drift-reconciliation
    timeout: 300
    on_failure: abort

execution_strategy: sequential
rollback_on_failure: false
max_duration: 900  # 15 minutes
```

**Orchestration Engine:**

1. **Parse chain definition:** Read YAML, validate playbooks exist
2. **Pre-flight checks:**
   - Verify all playbooks are available
   - Check system health (don't chain on unstable system)
   - Estimate total duration
3. **Execute sequence:**
   - Run playbooks in order
   - Respect timeouts
   - Evaluate conditions
   - Handle failures per strategy
4. **State management:**
   - Track which playbooks completed
   - Store intermediate results
   - Enable resume on failure
5. **Reporting:**
   - Chain-level metrics
   - Per-playbook timing
   - Overall success/failure
   - Recommendations for next run

**Failure Strategies:**
- **continue-on-error:** Run all playbooks regardless of failures
- **stop-on-failure:** Stop chain on first failure
- **rollback-on-failure:** Undo previous playbooks (where possible)
- **skip:** Continue to next playbook, ignore current failure

**Deliverables:**
- [ ] Chain specification format (YAML schema)
- [ ] `scripts/execute-chain.sh` orchestration engine
- [ ] 3 example chains (full-recovery, predictive-preemption, database-health)
- [ ] State management (resume capability)
- [ ] Chain-level Prometheus metrics
- [ ] Documentation: chain authoring guide

**Success Criteria:**
- All 3 example chains execute successfully
- Failure strategies work as designed
- Timeout enforcement prevents runaway chains
- Metrics track chain-level success rates
- Resume works after interruption

---

## Phase 6: Intelligence Layer - Remediation History Analytics

### Objective
Build analytics and trending capabilities to learn from remediation history, identify patterns, and continuously improve effectiveness.

### Why Last?
- **Requires data:** Needs execution history from all previous phases
- **Insight-driven:** Enables data-driven decisions on remediation strategy
- **Continuous improvement:** Identifies high-value vs low-value playbooks
- **Not time-critical:** System works without it, but improves with it

### Implementation Details

**Data Sources:**
1. Decision log: `~/.claude/context/decision-log.json`
2. Prometheus metrics: Time-series remediation data
3. Systemd journal: Execution logs
4. Prediction accuracy: Historical forecasts vs actuals

**Analytics to Build:**

**1. Effectiveness Scoring:**
```bash
# Calculate per-playbook effectiveness score (0-100)
# Factors:
#   - Success rate (40%)
#   - Impact (disk reclaimed, services recovered) (30%)
#   - Execution time (20%)
#   - Prediction accuracy (10%)

./scripts/analytics/remediation-effectiveness.sh --playbook disk-cleanup
# Output: Effectiveness score: 87/100
```

**2. Trend Analysis:**
```bash
# Identify trends over time
./scripts/analytics/remediation-trends.sh --last 30d

# Output:
# - Disk cleanups increasing (5→12 per month)
# - Self-healing restarts decreasing (8→3 per month) ← Good sign
# - Predictive accuracy improving (65%→82%)
# - Most common root cause: Memory pressure (45% of incidents)
```

**3. ROI Calculation:**
```bash
# Calculate return on investment
./scripts/analytics/remediation-roi.sh

# Metrics:
# - Incidents prevented: 23 (via predictive maintenance)
# - Manual interventions avoided: 47
# - Average resolution time: 2 minutes (vs 30 minutes manual)
# - Total time saved: 22 hours this month
```

**4. Recommendation Engine:**
```bash
# Suggest optimizations based on history
./scripts/analytics/remediation-recommendations.sh

# Sample output:
# 1. Consider increasing jellyfin memory limit (5 OOM restarts this month)
# 2. Disk cleanup threshold too aggressive (running 3x per week)
# 3. Database maintenance effective (query time improved 23%)
# 4. Add redis-authelia to self-healing-restart overrides (100% success without it)
```

**Report Generation:**

Monthly automated report: `~/containers/docs/99-reports/remediation-monthly-YYYYMM.md`

```markdown
# Remediation Report - December 2025

## Summary
- **Total Executions:** 67
- **Success Rate:** 94%
- **Time Saved:** 22 hours
- **Disk Reclaimed:** 47 GB
- **Services Recovered:** 12

## Top Performers
1. disk-cleanup (32 runs, 97% success)
2. predictive-maintenance (28 runs, 89% accuracy)
3. self-healing-restart (7 runs, 86% success)

## Incidents Prevented
- 8 disk exhaustion events (via predictive maintenance)
- 5 service crashes (via self-healing restart)
- 3 database performance degradations (via maintenance)

## Recommendations
[Generated recommendations here]
```

**Deliverables:**
- [ ] `scripts/analytics/remediation-effectiveness.sh`
- [ ] `scripts/analytics/remediation-trends.sh`
- [ ] `scripts/analytics/remediation-roi.sh`
- [ ] `scripts/analytics/remediation-recommendations.sh`
- [ ] Monthly report generator
- [ ] Systemd timer for monthly reports
- [ ] Grafana dashboard: "Remediation Intelligence"

**Success Criteria:**
- Effectiveness scores calculated for all 7 playbooks
- Trend analysis identifies patterns over 30-day window
- ROI calculation shows time/effort saved
- Recommendations actionable and data-driven
- Monthly report generated automatically

---

## Dependencies & Prerequisites

### System Requirements
- ✅ Prometheus + Grafana + Alertmanager operational
- ✅ 7 remediation playbooks fully implemented
- ✅ Autonomous operations framework running
- ✅ Decision logging infrastructure
- ✅ Systemd timer infrastructure
- ✅ BTRFS snapshots for rollback

### Phase Dependencies
```
Phase 1 (Metrics) ─┬─→ Phase 2 (Timers) ─┬─→ Phase 3 (Autonomous) ─┬─→ Phase 4 (Webhooks) ─┬─→ Phase 5 (Chaining) ─→ Phase 6 (Analytics)
                   │                      │                         │                        │
                   └──────────────────────┴─────────────────────────┴────────────────────────┴─→ Phase 6 (needs all data)
```

---

## Risk Mitigation

### High-Risk Areas
1. **Alertmanager webhooks:** Could trigger excessive remediation
   - **Mitigation:** Rate limiting, circuit breaker, localhost-only

2. **Multi-playbook chains:** Complex failure scenarios
   - **Mitigation:** Thorough testing, dry-run mode, BTRFS snapshots

3. **Autonomous integration:** Unwanted remediation actions
   - **Mitigation:** High confidence thresholds, service overrides, pause capability

### Rollback Strategy
- Each phase independently testable
- All changes git-tracked with revert capability
- BTRFS snapshots before risky operations
- Circuit breaker pauses autonomous operations on failures
- Manual override: `~/containers/scripts/autonomous-execute.sh --pause`

---

## Testing Strategy

### Per-Phase Testing
1. **Syntax validation:** Bash syntax checks
2. **Dry-run testing:** All scripts support `--dry-run`
3. **Unit testing:** Individual component tests
4. **Integration testing:** End-to-end workflows
5. **Metrics validation:** Verify Prometheus ingestion
6. **Documentation review:** Ensure guides updated

### Acceptance Criteria
Each phase must meet:
- [ ] All deliverables completed
- [ ] Success criteria met
- [ ] Tests passing
- [ ] Metrics emitting (where applicable)
- [ ] Documentation updated
- [ ] No regressions in existing functionality

---

## Documentation Updates

### Files to Update Per Phase

**Phase 1:**
- `.claude/remediation/README.md` (metrics section)
- `docs/40-monitoring-and-documentation/guides/prometheus-metrics.md`

**Phase 2:**
- `systemd/README.md` (new timers)
- `docs/20-operations/guides/automation-reference.md`

**Phase 3:**
- `docs/20-operations/guides/autonomous-operations.md`
- `.claude/skills/autonomous-operations/README.md`

**Phase 4:**
- `.claude/remediation/README.md` (webhook section)
- `docs/30-security/guides/webhook-security.md` (new)

**Phase 5:**
- `.claude/remediation/README.md` (chaining section)
- `docs/20-operations/guides/remediation-chains.md` (new)

**Phase 6:**
- `docs/99-reports/README.md` (analytics reports)
- `docs/20-operations/guides/remediation-analytics.md` (new)

### Journal Entries
Create journal entry after each phase completion in `docs/98-journals/`.

---

## Success Metrics

### Quantitative
- **Automation rate:** % of incidents resolved without manual intervention
- **MTTR reduction:** Mean time to resolution (target: <5 minutes)
- **Prediction accuracy:** Forecasting success rate (target: >80%)
- **Uptime improvement:** Reduction in service downtime
- **Resource optimization:** Disk space, memory pressure incidents reduced

### Qualitative
- **Operational confidence:** Trust in autonomous remediation
- **Learning velocity:** Speed of identifying and fixing new issues
- **System stability:** Fewer emergency interventions required

---

## Timeline Estimate

| Week | Phases | Key Milestones |
|------|--------|----------------|
| 1 | Phase 1-2 | Metrics live, timers scheduled |
| 2 | Phase 3 | Autonomous integration complete |
| 3 | Phase 4 | Webhook handler operational |
| 4-5 | Phase 5 | Chain orchestration working |
| 6 | Phase 6 | First monthly analytics report |

**Flexibility:** Timeline can compress if phases complete faster than estimated.

---

## Next Actions

1. ✅ Create this roadmap document
2. ⏭️ Begin Phase 1: Design Prometheus metrics schema
3. ⏭️ Implement textfile collector integration
4. ⏭️ Create initial Grafana dashboard
5. ⏭️ Test metrics collection with existing playbooks

---

## Related Documentation
- Phase 2A completion: `docs/98-journals/2025-12-23-remediation-arsenal-expansion.md`
- Remediation framework: `.claude/remediation/README.md`
- Autonomous operations: `docs/20-operations/guides/autonomous-operations.md`
- Monitoring stack: `docs/40-monitoring-and-documentation/guides/prometheus-metrics.md`

---

**Last Updated:** 2025-12-23
**Next Review:** After Phase 1 completion
