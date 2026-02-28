# SLO Framework Expansion + Deploy-from-Pattern Fixes

**Date:** 2026-02-28
**Scope:** Add Navidrome + Audiobookshelf to SLO monitoring; fix deploy-from-pattern skill gaps
**Result:** 13 SLOs across 8 services; 4 deploy-from-pattern improvements shipped

---

## SLO Expansion

Added availability SLOs (99.5% / 30-day) for both audio services deployed earlier today. No latency SLOs — streaming services have highly variable response times that make latency targets meaningless.

### New Rules

| Type | Count | File |
|---|---|---|
| Recording rules | 34 | `slo-recording-rules.yml` (+174 lines) |
| Extended burn rates | 8 | `slo-burn-rate-extended.yml` (+86 lines) |
| Alert rules | 8 | `slo-multiwindow-alerts.yml` (+206 lines) |

Both services follow the Jellyfin pattern: Traefik-based SLIs with `code=~"0|2..|3.."`, 4-tier multi-window burn-rate alerting, error budget forecasting.

### Dashboard

Grafana SLO dashboard updated — all 6 panels now show 8 services (was 6). Gauge panels increased from 6h to 7h height to prevent crowding with the additional indicators.

### Monthly Report

Discord embed now includes Navidrome and Audiobookshelf fields. Service count updated 6 → 8.

### Verification

- Prometheus reloaded: all 34 recording rules + 8 alert rules confirmed active
- Grafana restarted: dashboard provisioning picked up
- Data will populate over the next few hours as SLI rates accumulate

---

## Deploy-from-Pattern Fixes

Addressed the 4 most actionable gaps from the earlier skill gap analysis.

### 1. Template variable validation

After variable substitution, the script now scans output for unresolved `{{VARIABLES}}` and fails hard (or warns in dry-run). This was the highest-value fix — previously, unresolved variables silently produced broken quadlet files.

### 2. Quadlet symlink convention

Changed from `cp` directly to `~/.config/containers/systemd/` to the project convention: generate in `~/containers/quadlets/`, then `ln -sf` to the systemd directory.

### 3. Port and health endpoint configurability

New `--port` and `--health-cmd` CLI flags. Pattern loading now extracts `port:` and `health_cmd:` from YAML. Variable substitution switched from `sed` to `awk` for values containing shell-hostile characters (`||`, `/`).

### 4. More pattern variable extraction

Now extracts `memory_high`, `config_dir`, `data_dir` from pattern YAML. Resolves `{service_name}` placeholders in paths. Both lowercase and UPPERCASE key variants are substituted.

### Remaining gaps (not addressed)

- Template files still have unresolved structural variables (`SERVICE_DESCRIPTION`, `DOCS_URL`, `STATIC_IP_*`, `NETWORK_SERVICES_AFTER/REQUIRES`) — these require template rewrites
- Array-type pattern fields (middleware, volumes, environment) still not extracted — needs proper YAML parsing
- Multi-component patterns (database + webapp) still treated as single service
- Prerequisites script tries to `mkdir` empty strings when `config_dir`/`data_dir` are unresolved

---

## Files Changed

| File | Change |
|---|---|
| `config/prometheus/rules/slo-recording-rules.yml` | +174: SLI, SLO, error budget, burn rate for 2 services |
| `config/prometheus/rules/slo-burn-rate-extended.yml` | +86: Extended windows + forecasting |
| `config/prometheus/alerts/slo-multiwindow-alerts.yml` | +206: 4-tier alerts for 2 services |
| `config/grafana/provisioning/dashboards/json/slo-dashboard.json` | +100: 8 targets per panel, layout adjustments |
| `scripts/monthly-slo-report.sh` | +24: 2 new services in Discord report |
| `docs/40-monitoring-and-documentation/guides/slo-framework.md` | +28: SLO-011, SLO-012 definitions |
| `CLAUDE.md` | Updated SLO counts (9→13, 5→8) |
| `.claude/skills/homelab-deployment/scripts/deploy-from-pattern.sh` | +85: 4 fixes |
