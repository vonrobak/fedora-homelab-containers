# Traefik Access-Log Empty Query — Investigation & Reading Guide

**Date:** 2026-04-28
**Status:** No action needed. Empty query result was correct; documenting so a fresh session doesn't repeat the chase.
**Trigger:** During T3.2 (Loki move to subvol8-db) post-deployment validation, `count_over_time({job="traefik-access"}[5m])` returned an empty vector. First reading was "Promtail isn't pushing traefik logs" — second reading and investigation showed it's a quiet stack returning the truth.

---

## What was checked

### 1. Promtail → Loki pipeline

- `promtail` container `Up X minutes (healthy)`, no errors after Loki cut over to new path.
- Loki ingest receiving `systemd-journal` entries at ~1322/30s (verified via `count_over_time({job="systemd-journal"}[30s])`). So the pipeline itself is alive.
- `unifi-syslog` and `traefik-access` both appear in `loki/api/v1/label/job/values` → Promtail HAS pushed traefik-access entries historically; the label is registered.

### 2. Promtail config

`config/promtail/promtail-config.yml` defines a `traefik-access` job that tails `/var/log/traefik/access.log` (mounted from `/mnt/btrfs-pool/subvol7-containers/traefik-logs`). JSON pipeline extracts method/status/service into Loki labels and replaces the line body with the request path. Mount path verified via `podman inspect promtail`.

### 3. Traefik access log itself

- File present: `/mnt/btrfs-pool/subvol7-containers/traefik-logs/access.log`, 50MB
- Last write timestamp: 2026-04-28 20:53 local (22 minutes before the empty-query observation)
- Last 5 entries inspected (via `podman exec promtail tail -5`): all 4xx/5xx responses (503/401/401/401/404), spread across nextcloud-secure and audiobookshelf-secure routers. Latest at 18:53:39 UTC.

### 4. The smoking gun: filter config

`config/traefik/traefik.yml`:

```yaml
accessLog:
  filters:
    statusCodes:
      - "400-599"  # Only log errors (reduce volume)
```

**Successful (2xx/3xx) responses are not written to access.log at all.** Promtail therefore has nothing to ingest unless an actual error occurs. In a quiet stack, gaps of 20+ minutes between log entries are normal.

### 5. Cross-check: is Traefik actually receiving traffic?

`traefik_service_requests_total[5m]`: 170 requests in 5 min, **all attributed to the `traefik` service** — i.e. Prometheus scraping `/metrics`, Promtail querying internal endpoints, and the user's own dashboard polling. No external-user traffic to `nextcloud-secure@file` / `immich-secure@file` / etc. during the observation window.

Conclusion: stack is genuinely idle. Empty Loki query is the correct answer.

---

## What to look for at the Traefik dashboard

The dashboard is at `https://traefik.patriark.org` (Authelia-protected). Useful panels for "is the stack actually working":

- **HTTP → Routers** — should list ~18 routers. Click into any to inspect its middleware chain. Every internet-facing route should start with `crowdsec-bouncer@file`. If a router shows up but has no middlewares, that's a misconfig (and would also fail security audit `SA-TRF-04`).
- **HTTP → Services** — green dot = backend container is reachable. Red = look at `journalctl --user -u <svc>.service`.
- **HTTP → Entrypoints → websecure (port 443)** — request rate timeseries. Flatline during idle hours is normal; flatline during your active use of `nextcloud.patriark.org` would be pathological.
- **`traefik@internal` router** — usually the busiest in any 5-min window during quiet times, because Prometheus scrapes `/metrics` on it every scrape interval. Don't mistake this for user traffic.

For "did real users hit anything in the last hour", a better source than the dashboard is Prometheus:

```
# Per-service request rate (last 1h average), excluding internal scrape noise
sum by (service) (rate(traefik_service_requests_total{service!~"traefik|prometheus.*"}[1h]))
```

Anything > 0 there means at least one external request reached that backend.

---

## Why the empty query was misleading at first

The query `count_over_time({job="traefik-access"}[5m])` returns "no entries in this 5-minute window for this job." That sounds like "Loki has no data for that label," but it's actually "the access log file has not had a write in 5 minutes that Promtail could ingest." Two distinct failure modes share an identical empty-result surface:

1. **Pipeline broken** (Promtail not pushing, Loki not ingesting, label dropped) — would be persistent and reproducible across all jobs.
2. **No data to ingest** (Traefik filter excludes 2xx/3xx, no errors in window) — affects this one job only, depends on activity.

The discriminator is: query the same window with a different active job (here `systemd-journal`, which writes constantly). Non-zero result there proves the pipeline works; the empty `traefik-access` is just absence-of-errors.

---

## What this means for future debugging

If the question is "is `traefik-access` ingest broken?", the right test is:

```bash
# Generate a deliberate 4xx and check it lands in Loki within ~30s
curl -s -o /dev/null -w "%{http_code}\n" https://traefik.patriark.org/this-path-does-not-exist
sleep 30
podman exec grafana wget -qO- 'http://loki:3100/loki/api/v1/query?query=sum(count_over_time({job="traefik-access"}[1m]))'
```

If the second command returns > 0, the pipeline is healthy. If it stays at 0 after a guaranteed-error request, then there's a real problem to investigate.

---

## What's invariant after this

- **Empty `traefik-access` query during quiet hours is benign** — the access log filter is intentionally errors-only.
- **Promtail's pipeline strips `client_addr` from indexed content** (see 2026-04-28 T3.2 journal) — for per-IP forensics, query the raw access log, not Loki.
- **The 170 req/5min on `service=traefik` is dashboard + scrape noise**, not user traffic. Real user traffic appears under `nextcloud-secure@file`, `immich-secure@file`, `vaultwarden-secure@file`, etc.

## What's open

Nothing. This investigation is closed. Recorded as a handoff so a fresh session doesn't burn cycles re-deriving the answer when someone next sees an empty query result.
