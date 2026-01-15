# Gathio Event Management Platform

**Date:** 2026-01-14
**Status:** ✅ Complete
**Service:** Gathio + MongoDB
**URLs:** https://events.patriark.org

---

## Summary

Deployed Gathio as a lightweight, privacy-focused event management platform. First homelab deployment using the new pattern-based deployment framework, demonstrating the value of standardized approaches for multi-container services.

**Key Achievement:** End-to-end deployment from pattern selection to post-reboot validation in under 2 hours.

---

## Decision Context

**Need:** Personal event coordination tool without commercial platform dependencies (Meetup, Eventbrite tracking, data mining).

**Selection Criteria:**
- Self-hosted with minimal external dependencies
- Privacy-first design (no telemetry, optional federation)
- Simple event creation workflow
- No account requirement for attendees

**Why Gathio:**
- Federated ActivityPub support (future-proof for decentralized networks)
- Optional email (can operate entirely via shareable links)
- Clean, minimal UI matching homelab aesthetic
- Active development, well-documented

---

## Implementation Approach

### Pattern-Based Deployment

Used the `web-app-with-database` pattern from the homelab deployment framework:

```bash
cd .claude/skills/homelab-deployment
./scripts/deploy-from-pattern.sh \
  --pattern web-app-with-database \
  --service-name gathio \
  --hostname events.patriark.org \
  --memory 512M \
  --database mongodb
```

**Generated artifacts:**
- `gathio.container` - Main application quadlet
- `gathio-db.container` - MongoDB backend quadlet
- Traefik routing configuration with middleware chain
- systemd-gathio network (internal, database isolation)
- Health checks for both containers

### Network Architecture

**Design decision:** Isolated database network with no internet access.

```
gathio container:
  - systemd-reverse_proxy (first, default route)
  - systemd-gathio (MongoDB access)
  - systemd-monitoring (metrics collection)

gathio-db container:
  - systemd-gathio (isolated, internal=true)
  - systemd-monitoring (metrics only)
```

**Why this matters:** MongoDB has no direct path to internet, reducing attack surface for a database known for historical exposure issues. Internal network flag prevents accidental route leakage.

### Configuration Philosophy

**Email service:** Deliberately disabled (`mail_service = "none"`).

**Reasoning:**
- Gathio provides editing links with embedded passwords on event creation
- Users save links in password manager (Vaultwarden integration)
- Removes dependency on SMTP relay (SendGrid, Gmail)
- Simpler failure modes (no "email didn't arrive" support issues)
- Privacy benefit (no email addresses collected)

Created `gathio-email-setup.md` guide documenting SendGrid/Brevo options for future reconsideration.

**Access control:** Protected by existing Authelia SSO layer. Only authenticated users can create events; attendees access via shareable public links.

---

## Technical Learnings

### 1. Internal Networks Require Explicit Testing

Post-deployment verification revealed the value of testing database connectivity from the application layer, not just at the container level. Podman DNS resolution works differently within internal networks versus external.

**Validation commands that mattered:**
```bash
podman exec gathio wget -q -O /dev/null http://gathio-db:27017  # Reachability
podman exec gathio-db mongosh --eval "db.adminCommand('ping')"  # DB responsive
```

### 2. First Network Determines Default Route

Gathio quadlet lists networks in deliberate order:
```ini
Network=systemd-reverse_proxy  # FIRST - gets default route
Network=systemd-gathio         # Database access
Network=systemd-monitoring     # Metrics
```

Reversing this order would break internet access for container image pulls and external dependencies.

### 3. Secrets in TOML Configurations

Gathio doesn't support environment variable interpolation in `config.toml`. MongoDB connection string includes password in plaintext config file.

**Mitigation:** `.gitignore` protection for `config/gathio/config.toml`. Acceptable trade-off for personal homelab (no shared repository access).

**Alternative considered:** Podman secrets mounted as files. Rejected because Gathio's config parser doesn't support file-based secret injection.

### 4. Pattern Deployment Accelerates Iteration

Using the deployment pattern eliminated 80% of boilerplate:
- No manual Traefik routing configuration
- Pre-configured middleware chain (rate limiting, headers)
- Standardized health checks
- Automatic network creation with proper flags

**Time comparison:**
- Manual deployment (Nextcloud): 4-5 hours (trial and error with networking)
- Pattern deployment (Gathio): 45 minutes (mostly config file tuning)

---

## Post-Reboot Validation (2026-01-15)

System rebooted for unrelated kernel update. Gathio survival testing:

**Health Status:**
- ✅ Both containers started automatically (systemd dependency handling)
- ✅ MongoDB connection established (no orphaned socket files)
- ✅ HTTPS access functional (Traefik routing persisted)
- ✅ Internal network DNS resolution working (gathio-db reachable)
- ⚠️ Missing instance description file (non-critical, created post-boot)

**Resource Usage:**
- Gathio: 110MB / 512MB limit (21.7%)
- MongoDB: 151MB / 384MB limit (39.5%)

**Observations:**
- Traefik circuit breaker briefly tripped during boot sequence (recovered in 6 seconds)
- No MongoDB replica set configuration needed for single-instance deployment
- Health checks prevented premature Traefik routing (HealthStartPeriod=60s effective)

---

## Integration Points

### Monitoring Stack
- Prometheus scrapes Gathio metrics (if exposed, not default)
- MongoDB exporter not deployed (overhead not justified for single small DB)
- Promtail ingests container logs to Loki

### Backup Strategy
- `config/gathio/` - BTRFS snapshots (configuration)
- `data/gathio/static/` - User-uploaded instance customizations
- `data/gathio/images/` - Event images (user-generated content)
- MongoDB data - Not yet integrated into backup rotation (TODO)

### Authentication Flow
Authelia SSO protects event creation endpoints (`/new`). Public event pages remain accessible without authentication. This mirrors the Nextcloud pattern: administrative functions protected, consumption open.

---

## Future Considerations

### Federation (Disabled for Now)

Gathio supports ActivityPub federation with Mastodon and other fediverse platforms. Disabled via `IS_FEDERATED=false` to avoid:
- Public instance discovery and spam event creation
- Federation protocol complexity (ActivityPub debugging)
- Moderation burden for federated events

Could enable later if running invite-only private instance or integrating with personal Mastodon server.

### Email Automation

If manual link-saving becomes friction:
1. SendGrid free tier (100 emails/day)
2. 15-minute setup
3. See `gathio-email-setup.md` for configuration

Current workflow (save editing link in Vaultwarden) works well for personal use at current event volume (1-2/month projected).

### Database Persistence

MongoDB container uses default storage. No BTRFS NOCOW optimization applied (unlike Prometheus/Loki). Event database is small (<50MB projected) and write-light, so COW fragmentation unlikely to impact performance.

Monitor `btrfs fi defrag` needs if database grows significantly.

---

## Reflections

**Pattern-based deployment delivered on promise:** Faster, more consistent, easier to audit. First real-world test case beyond the framework development phase.

**Internal networks working as designed:** Database isolation effective without added complexity. DNS resolution transparent within Podman's network abstraction.

**Email-optional architecture appreciated:** Reducing external dependencies creates more resilient systems. Gathio's design allows graceful degradation (no email = manual link management, not broken functionality).

**Next deployment candidate:** Wiki.js (documentation platform) using same `web-app-with-database` pattern. Expect similar deployment velocity now that pattern is proven.

---

## Related Documentation

- **Pattern Reference:** `.claude/skills/homelab-deployment/patterns/web-app-with-database.yml`
- **Email Setup:** `docs/10-services/guides/gathio-email-setup.md`
- **Service Catalog:** `AUTO-SERVICE-CATALOG.md` (auto-updated)
- **Network Topology:** `AUTO-NETWORK-TOPOLOGY.md` (systemd-gathio internal network diagram)

---

**Status:** Production-ready | Post-reboot validated | Ready for use
