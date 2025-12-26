# Security Review and Infrastructure Improvements

**Date:** 2025-12-26
**Type:** Security Assessment, Configuration Improvements, Service Updates
**Duration:** ~2 hours

---

## Overview

Conducted comprehensive security assessment of homelab infrastructure with focus on HTTP/HTTPS attack surface resilience. Implemented memory resource limits for container security and updated Immich to latest version.

## Security Assessment Findings

### Strengths Identified
- **Layered defense architecture working as designed**: CrowdSec proactively blocking 4,165 malicious IPs via CAPI
- **Zero authentication failures** in 7 days (indicates threat blocking before reaching Authelia)
- **Phishing-resistant authentication**: YubiKey/FIDO2 + Authelia SSO operational
- **Strong security posture**: 8/10 checks passed, 2 minor warnings

### Vulnerabilities Addressed

1. **Access Logging Gap** (Medium Priority)
   - **Issue**: No Traefik access logging enabled (forensics gap)
   - **Resolution**: Added JSON access logging to Traefik static config
   - **Impact**: Full request/response logging for security auditing and incident response

2. **Container Memory Limits** (Medium Priority)
   - **Issue**: 5 containers had systemd limits but not podman-visible limits
   - **Resolution**: Added `Memory=` directives to [Container] sections in quadlets
   - **Containers updated**: immich-ml (4G), prometheus (1G), postgresql-immich (1G), alertmanager (256M), node_exporter (128M)
   - **Impact**: DoS attack mitigation, monitoring tool visibility

3. **Configuration Compliance** (Design Principles)
   - **Issue**: alertmanager.container had Traefik labels (violates separation of concerns)
   - **Resolution**: Migrated routing to `~/containers/config/traefik/dynamic/routers.yml`
   - **Additional fixes**: Updated deprecated tinyauth reference → authelia, added reverse_proxy network
   - **Impact**: Architecture compliance with documented design principles

## Infrastructure Updates

### Immich Update (v2.3.1 → v2.4.1)

**Containers Updated:**
- immich-server: v2.3.1 → v2.4.1
- immich-ml: v2.3.1 → v2.4.1
- postgres/redis: No changes required (compatible)

**Key Features Added:**
- Command palette (Ctrl+K) for navigation
- Improved search and album management
- Mobile UX enhancements

**Process Followed:**
1. Verified no breaking changes across v2.3.1 → v2.4.0 → v2.4.1
2. Confirmed BTRFS snapshots available for rollback
3. Updated quadlet files (adhering to ADR-015 pinned version strategy)
4. Pulled new images and restarted services in dependency order
5. Verified health checks and API functionality

**Result:** ✅ All services healthy, v2.4.1 confirmed operational

## Files Modified

**Traefik Configuration:**
- `config/traefik/traefik.yml` - Added accessLog section (JSON format)
- `config/traefik/dynamic/routers.yml` - Added alertmanager router and service

**Quadlet Files:**
- `immich-server.container` - Updated to v2.4.1, added Memory=4G
- `immich-ml.container` - Updated to v2.4.1, increased to Memory=4G (from 2G)
- `prometheus.container` - Added Memory=1G
- `postgresql-immich.container` - Added Memory=1G
- `alertmanager.container` - Added Memory=256M, removed Traefik labels, added reverse_proxy network
- `node_exporter.container` - Added Memory=128M

## Security Posture Improvements

**Before:**
- ⚠️ No access logging (blind spots in attack detection)
- ⚠️ Memory limits not visible to monitoring tools (DoS risk)
- ⚠️ Configuration drift (labels vs dynamic config)

**After:**
- ✅ Full JSON access logging with security-aware field filtering
- ✅ Dual memory limits (podman + systemd) for defense in depth
- ✅ Architecture compliance with design principles
- ✅ Updated Immich with security patches

**Overall Security Score:** 8.7/10 → Strong security posture maintained

## Key Learnings

1. **Systemd vs Podman Memory Limits**: `MemoryMax=` in [Service] section (systemd cgroup) vs `Memory=` in [Container] section (podman runtime) - both needed for full coverage

2. **Security Audit Tools**: The security-audit.sh script checks podman inspect output, so podman-level limits are needed for visibility even when systemd limits exist

3. **Traefik Label Migration**: Moving from container labels to dynamic YAML files improves maintainability and follows separation of concerns principle

4. **Immich Update Strategy**: Pinned versions (per ADR-015) allow controlled updates with pre-verification of breaking changes - update successful with zero downtime

## Validation

**Traefik Access Logging:**
```bash
podman logs traefik | grep ClientAddr  # JSON logs visible ✓
```

**Memory Limits:**
```bash
systemctl --user status immich-ml | grep Memory
# Memory: 295.6M (max: 4G, swap max: 512M) ✓
```

**Immich Version:**
```bash
curl https://photos.patriark.org/api/server/version
# {"major":2,"minor":4,"patch":1} ✓
```

## Next Actions

- [ ] Monitor Traefik access logs for anomalous patterns
- [ ] Consider adding Memory= to remaining containers (redis-authelia, grafana, loki, authelia, promtail) for consistency
- [ ] Test Immich v2.4.1 new features (command palette, improved mobile UX)
- [ ] Review monthly SLO metrics post-update

## References

- Security Assessment Report: Generated in session (not persisted)
- ADR-015: Container Update Strategy
- Configuration Design Principles: `/docs/00-foundation/guides/configuration-design-quick-reference.md`
- Immich Release Notes: https://github.com/immich-app/immich/releases

---

**Status:** Complete
**Impact:** High (security + functionality improvements)
**Rollback Available:** Yes (BTRFS snapshots + version pins)
