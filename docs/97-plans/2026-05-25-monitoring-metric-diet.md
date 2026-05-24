# Plan A: Monitoring Metric Diet & Stack Hygiene

**Date Created:** 2026-05-25
**Status:** Implemented (2026-05-25) — core metric diet live; postgres trim deferred (see log)
**Last Updated:** 2026-05-25
**Implements:** Report [2026-05-25 Monitoring Stack Deep-Dive](../99-reports/2026-05-25-monitoring-stack-deep-dive.md) §3, §7
**Reconciles with:** ADR-003 (Monitoring Stack), ADR-030 (Supply-Chain Trust Model — `:latest` pin)

## Objective

Cut Prometheus active series ~40–45% by dropping data that **no dashboard and no rule consumes**,
then fix three small hygiene items. This is the highest-ROI, lowest-risk change in the deep-dive:
pure subtraction, fully reversible, with zero loss of any metric currently used.

## Background (verified 2026-05-25)

- **33,745 active series**; **cAdvisor = 17,660 (52%)**; Grafana self-metrics 2,631; postgres-immich
  2,330; node_exporter 1,873.
- **`config/prometheus/prometheus.yml` contains zero `metric_relabel_configs`** — nothing is dropped.
- TSDB on disk = 4.0 GB (15d retention); ingest ~1,850 samples/s.
- Blast-radius grep (this session) proved the top cardinality drivers have **no consumer**:
  `container_tasks_state`, `container_memory_failures_total`, `container_blkio_device_usage_total`,
  per-device `container_fs_reads_total`/`container_fs_writes_total`,
  `container_pressure_io_stalled_seconds_total`, `grafana_feature_toggles_info`,
  `redis_commands_latencies_usec_bucket`.
- The complete cAdvisor keep-list (union of all dashboard + alert + recording-rule references):

  ```
  container_cpu_usage_seconds_total      container_network_receive_bytes_total
  container_memory_usage_bytes           container_network_transmit_bytes_total
  container_memory_working_set_bytes     container_fs_reads_bytes_total
  container_spec_memory_limit_bytes      container_fs_writes_bytes_total
  container_last_seen                    container_start_time_seconds
  machine_memory_bytes                   machine_cpu_cores
  ```

  `container_fs_*_bytes_total` **must be preserved** (used by `container-metrics.json` +
  `service-health.json`); everything outside the list is unreferenced.

## Approach

### 1. cAdvisor allowlist (the big lever)

Add a `metric_relabel_configs` keep-filter to the **`cadvisor` job only** in
`config/prometheus/prometheus.yml`. Allowlist (keep) approach, not denylist, so future cAdvisor
metric additions stay dropped by default:

```yaml
  - job_name: cadvisor
    # ... existing static_configs / labels ...
    metric_relabel_configs:
      # Keep only the container_/machine_ series consumed by dashboards + rules.
      # Audited 2026-05-25 (see Plan A / deep-dive report §3). Drops ~14k unused series.
      - source_labels: [__name__]
        regex: 'container_(cpu_usage_seconds_total|memory_usage_bytes|memory_working_set_bytes|spec_memory_limit_bytes|network_receive_bytes_total|network_transmit_bytes_total|fs_reads_bytes_total|fs_writes_bytes_total|last_seen|start_time_seconds)|machine_(memory_bytes|cpu_cores)|cadvisor_version_info|container_scrape_error'
        action: keep
```

- Keep the `cadvisor_version_info` and `container_scrape_error` series (tiny, useful for self-health).
- Document the keep-list inline with a comment pointing at this plan + the report, so the rationale
  survives.

### 2. Exporter trims (secondary)

- **Grafana job:** drop `grafana_feature_toggles_info` (346 unused series) and other unused
  `grafana_*_info` families via a small drop rule on the grafana job. Keep
  `grafana_http_request_*`, datasource health, and build/version series.
- **Redis jobs** (`redis-authelia`, `redis-immich`): drop `redis_commands_latencies_usec_bucket`
  (518 unused histogram series). Dashboards use `redis_commands_duration_seconds_total` /
  `redis_command_calls_total`, which stay.
- **postgres-immich (lower priority):** `datname=immich` carries ~2,330 series from per-table
  `pg_stat_*`. Evaluate dropping per-relation stats not used by `postgres-exporter.json`; defer if it
  risks a dashboard panel — confirm with a grep of `postgres-exporter.json` first.

### 3. Dashboard verification (no rewrites expected)

- `container-metrics.json` and `service-health.json` reference only `container_fs_*_bytes_total`
  (preserved) plus the kept CPU/memory/network metrics — **no panel should break.**
- After applying, open both dashboards (+ `homelab-overview`) and confirm all panels render. If any
  panel goes empty, fix the query *in the same PR* (do not widen the keep-list to paper over it).

### 4. Stack hygiene

- **Loki delete-workers:** `config/loki/loki-config.yml` `retention_delete_worker_count: 150` → `20`.
- **Loki healthcheck:** add a TCP-probe `HealthCmd` to `quadlets/loki.container` mirroring promtail's
  `/dev/tcp` `GET /ready` pattern (distroless-safe; no shell/curl needed in image). Keeps systemd
  restart-on-unhealthy instead of relying solely on `up{job="loki"}`.
- **Pin `alert-discord-relay`:** resolve `localhost/...:latest` to a digest (or, since it is a
  locally-built image, pin the base + record the build digest per ADR-030 Tier-2). Brings the last
  unpinned image into supply-chain compliance.

## Success Criteria

- `prometheus_tsdb_head_series` drops from ~33,745 to **~19–20k** within one scrape cycle.
- `seriesCountByMetricName` no longer lists `container_tasks_state`, `container_blkio_device_usage_total`,
  `container_memory_failures_total`, `grafana_feature_toggles_info`, `redis_commands_latencies_usec_bucket`.
- TSDB on disk trends toward **~2.2 GB** over the next 15-day retention cycle; nightly Prometheus dump
  shrinks proportionally.
- All Grafana dashboards still render every panel.
- Loki shows a healthy systemd healthcheck; `alert-discord-relay` is digest-pinned.

## Verification

```bash
# Before
podman exec prometheus wget -qO- 'http://localhost:9090/api/v1/query?query=prometheus_tsdb_head_series'
# Validate config, then hot-reload
podman exec prometheus promtool check config /etc/prometheus/prometheus.yml
curl -s -X POST http://localhost:9090/-/reload   # or: systemctl --user restart prometheus
# After (give it a scrape interval)
podman exec prometheus wget -qO- 'http://localhost:9090/api/v1/status/tsdb'
# Dashboards: load container-metrics, service-health, homelab-overview in Grafana — all panels populated
# Loki health
systemctl --user restart loki && systemctl --user status loki   # healthy
```

## Rollback

`git revert` the `prometheus.yml` change (metric_relabel only affects ingestion going forward; no
historical data is mutated). Loki worker count and healthcheck are independent reverts. The relay pin
reverts to `:latest` if a bad digest is chosen.

## Notes / future

- If the cAdvisor allowlist proves durable, consider promoting "ingest only consumed metrics" to a
  standing convention — possibly a short ADR — so new exporters get a keep-list at deploy time. **Not**
  authored in this plan; flagged only.

## Progress Log

- 2026-05-25 — Plan drafted from deep-dive report. Status: Proposed.
- 2026-05-25 — **Implemented on branch `chore/monitoring-metric-diet`.** Pre-flight grep re-verified
  the keep-list (14 cAdvisor names kept / 102 dropped) and zero-consumer drop candidates.
  - **cAdvisor allowlist** added to `config/prometheus/prometheus.yml`. Per-scrape proof:
    `scrape_samples_post_metric_relabeling{job="cadvisor"}` **16,130 → 2,879** (−13,251).
  - **Grafana** drop `grafana_feature_toggles_info`: 2,626 → 2,280 (−346).
  - **Redis** drop `redis_commands_latencies_usec_*`: redis-immich 1,096 → 612 (−484);
    redis-authelia emits none of that family (−0, rule harmless).
  - **Loki** `retention_delete_worker_count` 150 → 20; quadlet healthcheck comment rewritten —
    see below.
  - **alert-discord-relay** moved off mutable `:latest` to immutable `:2026-05-23` (build date),
    matching the proton-bridge local-build convention; build digest recorded in the quadlet.
    Supply-chain gate stays green. (NB: `audit-egress-updates.sh` *exempts* `localhost/*` from
    digest-pinning — the relay's integrity is already covered by the Tier-2 base-pin +
    hash-locked `requirements.lock`, so a version tag, not a `@sha256`, is the correct fix.)
  - **Dashboards verified:** every metric referenced by container-metrics / service-health /
    homelab-overview returns data (CPU, memory, `fs_*_bytes_total`=603, last_seen, network,
    start_time, node_*). No empty panels.
  - **Plan deviations (verified before acting):**
    1. **Loki healthcheck NOT added.** Plan said "mirror promtail's `/dev/tcp` probe
       (distroless-safe, no shell needed)" — but Podman `HealthCmd` runs *inside* the container
       and the grafana/loki image is genuinely distroless (no `sh`/`ls`/`wget`, only the loki
       binary). promtail's probe works *only* because promtail is Debian-based and ships `bash`.
       An in-container probe is therefore impossible. Documented why in `quadlets/loki.container`;
       readiness stays covered by the existing `up{job="loki"} == 0` critical alert
       (infrastructure-critical.yml) + homelab-intel.sh. (Owner-confirmed: skip.)
    2. **Relay pinned by version tag, not `@sha256` digest** (plan's literal wording). A local
       digest is fragile (breaks systemd start on prune/rebuild, not registry-verifiable) and the
       repo's own tooling exempts `localhost/*` from digest-pinning. (Owner-confirmed: version tag.)
    3. **postgres-immich trim DEFERRED.** The cAdvisor cut alone reaches the ~19–20k target; the
       postgres dashboard consumes only cluster/`pg_stat_database_*`/`pg_settings_*` aggregates
       (no per-table stats), so a trim is low-yield-for-risk here. Left for a follow-up if needed.
  - **Operational note (cost me a cycle, worth recording):** `prometheus.yml` and `loki-config.yml`
    are *single-file* bind mounts. Editing them with an atomic-write tool swaps the file inode,
    but the bind mount stays pinned to the old inode — so `POST /-/reload` (HTTP 200, success=1)
    read **stale** config and dropped nothing. Fix is a container **restart** (re-binds the mount
    to the new inode), which the plan listed as the alternative; here it is *required*, not optional.
  - **head_series** was still ~34k immediately after (stale series linger in the head until ~5 min
    staleness + head truncation ~2h); the authoritative immediate signal is the per-scrape
    `post_metric_relabeling` drop above. TSDB on disk shrinks over the 15-day retention cycle.
  - **Not yet committed** — changes staged on the branch pending owner review.
