# Systemd User Units

Systemd service and timer units for automating homelab operations.

## Installation

Copy units to systemd user directory and enable:

```bash
cp ~/containers/systemd/*.{service,timer,socket} ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now <unit>.timer   # or .socket, .service
```

## Available Units

### auto-doc-update.timer / auto-doc-update.service

**Purpose:** Automatically regenerate all auto-documentation daily

**Schedule:** Daily at 07:00 (with 5-minute random delay)

**What it runs:** `~/containers/scripts/auto-doc-orchestrator.sh`

**Generates:**
- `docs/AUTO-SERVICE-CATALOG.md` - Running services inventory
- `docs/AUTO-NETWORK-TOPOLOGY.md` - Network diagrams
- `docs/AUTO-DEPENDENCY-GRAPH.md` - Service dependencies
- `docs/AUTO-DOCUMENTATION-INDEX.md` - Complete documentation index

**Installation:**
```bash
cp ~/containers/systemd/auto-doc-update.{service,timer} ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now auto-doc-update.timer
```

**Check status:**
```bash
systemctl --user list-timers auto-doc-update.timer
systemctl --user status auto-doc-update.service
journalctl --user -u auto-doc-update.service -f
```

**Manual trigger:**
```bash
systemctl --user start auto-doc-update.service
```

**Optional: Auto-commit changes**

Uncomment the `ExecStartPost` line in `auto-doc-update.service` to automatically
commit documentation changes to git after generation.

### predictive-maintenance-check.timer / predictive-maintenance-check.service

**Purpose:** Daily predictive analytics check for resource exhaustion forecasting

**Schedule:** Daily at 06:00 (before autonomous-operations at 06:30, with 2-minute random delay)

**What it runs:** `~/containers/.claude/remediation/scripts/apply-remediation.sh --playbook predictive-maintenance`

**Actions:**
- Runs predictive analytics for disk, memory, swap resources
- Forecasts resource exhaustion 7-14 days in advance
- Logs predictions for trending analysis
- Triggers preemptive cleanup if critical thresholds predicted

**Metrics collected:**
- Execution count and success rate
- Prediction accuracy over time
- Forecast confidence scores

**Check status:**
```bash
systemctl --user list-timers predictive-maintenance-check.timer
systemctl --user status predictive-maintenance-check.service
journalctl --user -u predictive-maintenance-check.service -f
```

### database-maintenance.timer / database-maintenance.service

**Purpose:** Weekly automated database maintenance operations

**Schedule:** Weekly on Sunday at 03:00 (low-traffic window, with 5-minute random delay)

**What it runs:** `~/containers/.claude/remediation/scripts/apply-remediation.sh --playbook database-maintenance`

**Actions:**
- PostgreSQL: `VACUUM ANALYZE` to reclaim space and update statistics
- Redis: Memory analysis and fragmentation checks
- Loki: Retention policy verification
- Generates maintenance report with space reclaimed

**Metrics collected:**
- Maintenance duration
- Database size before/after
- Rows vacuumed
- Space reclaimed

**Check status:**
```bash
systemctl --user list-timers database-maintenance.timer
systemctl --user status database-maintenance.service
journalctl --user -u database-maintenance.service -f
```

**Note:** Database maintenance requires confirmation in playbook configuration. See `.claude/remediation/playbooks/database-maintenance.yml` for details.

### remediation-webhook.service

**Purpose:** Alert-driven remediation - Receive Alertmanager webhooks and trigger automatic remediation (Phase 4)

**Type:** Long-running service (not a timer)

**What it runs:** `~/containers/.claude/remediation/scripts/remediation-webhook-handler.py`

**Listens on:** `localhost:9096` (webhook endpoint: `/webhook`, health check: `/health`)

**Actions:**
- Receives POST requests from Alertmanager when alerts fire
- Routes alerts to appropriate remediation playbooks based on `webhook-routing.yml`
- Applies safety controls: rate limiting, idempotency, circuit breaker
- Logs all actions to decision log and systemd journal
- Only auto-executes safe operations with >90% confidence

**Safety controls:**
- Rate limiting: Max 5 executions per hour, 3 per alert type, 15min cooldown
- Idempotency: Same alert within 5 minutes = single execution
- Circuit breaker: Opens after 3 consecutive failures, resets after 30 minutes
- Service overrides: Never auto-restart traefik, authelia, prometheus, alertmanager, grafana

**Monitored alerts:**
- `SystemDiskSpaceCritical` / `SystemDiskSpaceWarning` → disk-cleanup (95%/85% confidence)
- `BtrfsPoolSpaceWarning` → disk-cleanup (80% confidence)
- `ContainerNotRunning` → self-healing-restart (90% confidence)
- `ContainerMemoryPressure` → service-restart (75% confidence, escalates)
- `CrowdSecDown` → self-healing-restart (95% confidence)

**Installation:**
```bash
cp ~/containers/systemd/remediation-webhook.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now remediation-webhook.service
```

**Check status:**
```bash
systemctl --user status remediation-webhook.service
journalctl --user -u remediation-webhook.service -f
curl http://127.0.0.1:9096/health
```

**Test integration:**
```bash
~/containers/scripts/test-webhook-remediation.sh
```

**Logs and metrics:**
- Decision log: `~/.claude/context/decision-log.jsonl`
- Webhook log: `~/containers/data/backup-logs/webhook-remediation.log`
- Metrics: `~/containers/data/backup-metrics/remediation.prom`

**Configuration:**
- Routing rules: `~/.claude/remediation/webhook-routing.yml`
- Alertmanager config: `~/containers/config/alertmanager/alertmanager.yml`

### http.socket / https.socket

**Purpose:** Host-side TCP listeners for ports 80 and 443, inherited by the Traefik container via systemd socket activation. Bypasses rootless Podman's `rootlessport` SNAT path so Traefik sees real external source IPs (required for CrowdSec IP-reputation and per-IP rate limiting to function).

**Why these are not in `quadlets/`:** Podman quadlet only processes `.container`, `.network`, `.volume`, `.pod`, `.build`, `.kube`, `.image`, and `.artifact` files. `.socket` units are plain systemd user units and must live in `~/.config/systemd/user/` directly.

**Wiring:** `FileDescriptorName=web` on `http.socket` and `FileDescriptorName=websecure` on `https.socket` match the Traefik entrypoint names in `config/traefik/traefik.yml`, so Traefik v3.1+ automatically uses the inherited FDs instead of binding its own. `quadlets/traefik.container` declares `Requires=/After=` the two sockets and `Sockets=http.socket` / `Sockets=https.socket` in its `[Service]` section, plus `Notify=true` for sd_notify readiness.

**Installation:**
```bash
cp ~/containers/systemd/{http,https}.socket ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user stop traefik.service   # release ports 80/443 from rootlessport
systemctl --user enable --now http.socket https.socket
# Traefik starts on first connection (triggered via Requires=)
```

**Rollback:** Disable the sockets, re-add `PublishPort=80:80` + `PublishPort=443:443` to `quadlets/traefik.container`, drop the `Sockets=` / `Notify=true` / `Requires=` lines, `daemon-reload`, restart Traefik.

**Check status:**
```bash
systemctl --user status http.socket https.socket traefik.service
ss -tlnp | grep -E ":(80|443)\s"   # owner should be traefik (in-container), NOT rootlessport
```

**See:** [ADR-022](../docs/00-foundation/decisions/2026-04-16-ADR-022-traefik-socket-activation.md) for rationale, alternatives considered, and verification plan.

## Notes

- All units run as user services (not system-wide)
- Timer uses `Persistent=true` to catch up if system was off during scheduled time
- Random delay prevents resource contention if multiple timers run simultaneously
