# Monitoring Alert Fatigue and False Positive Elimination

**Date:** 2026-01-08
**Type:** Monitoring Improvement
**Status:** Complete

---

## Achievement Summary

Eliminated certificate alert fatigue and resolved monitoring false positives, reducing alert noise by **678,000+ errors/24h** and restoring accurate health reporting.

### Issues Resolved

**1. Certificate Alert Fatigue (Primary)**
- **Problem:** CertificateExpiryWarning firing every 4 hours despite successful auto-renewal
- **Root Cause:** Traefik keeps old certificates in metrics after renewal; alert checked ALL certs including replaced ones
- **Impact:** 5 domains triggering false alerts (26-29 days old certs, while renewed certs had 70-90 days)
- **Fix:** Updated alert queries to use `max by(cn)` aggregation - now checks only newest certificate per domain
- **Result:** 0 active certificate alerts; will only fire if auto-renewal actually fails

**2. Loki Health Check False Positive**
- **Problem:** `homelab-intel.sh` reported Loki unhealthy despite normal operation
- **Root Cause:** Script checked non-existent healthcheck (Loki image lacks wget/curl) and unpublished localhost port
- **Fix:** Changed to verify Promtail → Loki connection by scanning Promtail logs for connection errors
- **Result:** Accurate health reporting - "Loki responding (verified via Promtail)"

**3. Node Exporter Broken Pipe Errors**
- **Problem:** 339,503 "broken pipe" errors in 24 hours from health checks
- **Root Cause:** Health check used `wget --spider` (HEAD request), but `/metrics` endpoint only supports GET
- **Location:** `~/.config/containers/systemd/node_exporter.container` (outside git repo)
- **Fix:** Changed HealthCmd from `--spider` to `-O /dev/null` for proper GET request
- **Result:** 0 errors after restart; health check now working correctly

### Files Modified

- `config/prometheus/alerts/rules.yml` - Certificate alert queries (both warning and critical)
- `scripts/homelab-intel.sh` - Loki health check logic
- `docs/AUTO-*.md` - Auto-generated documentation updates

### Verification

- ✅ Health score: 100/100
- ✅ 0 certificate alerts firing (all 15 domains: 32-90 days validity)
- ✅ Loki verified functional via Promtail
- ✅ Node exporter: 0 broken pipe errors
- ✅ Monitoring stack fully operational

### Impact

**User Experience:**
- No more alert fatigue from duplicate certificate warnings on Discord
- Accurate system health reporting in intelligence checks
- Cleaner logs (678K+ errors eliminated per day)

**System Reliability:**
- Better signal-to-noise ratio in alerting
- More reliable health scoring
- Certificates will only alert if auto-renewal fails

### PR

- **Branch:** `fix/monitoring-alert-improvements`
- **PR:** [#58](https://github.com/vonrobak/fedora-homelab-containers/pull/58)
- **Status:** Merged to main (squash merge: `f350a86`)
