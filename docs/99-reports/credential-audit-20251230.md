# Credential Audit Report

**Date:** $(date)
**Auditor:** Claude Code (automated security scan)

## Plaintext Credentials Found:

### Critical - Immediate Action Required

1. **grafana.container:18**
   - Environment=GF_SECURITY_ADMIN_PASSWORD=qTR#k28w4$RPM3
   - Service: Grafana
   - Type: Admin password
   - Risk: High (monitoring access)

2. **nextcloud-db.container:13**
   - Environment=MYSQL_ROOT_PASSWORD=[REDACTED]
   - Service: Nextcloud MariaDB
   - Type: Database root password
   - Risk: Critical (database access)

3. **nextcloud-db.container:16**
   - Environment=MYSQL_PASSWORD=[REDACTED]
   - Service: Nextcloud MariaDB
   - Type: Database user password
   - Risk: Critical (application database access)

4. **nextcloud-redis.container** (checking...)

## Migration Plan:

- [ ] Grafana admin password → podman secret
- [ ] Nextcloud MariaDB root password → podman secret
- [ ] Nextcloud MariaDB user password → podman secret
- [ ] Nextcloud Redis password → podman secret (if found)

## Security Impact:

- Passwords visible in systemd unit files via `systemctl cat`
- Non-compliance with homelab security standards (ADR patterns)
- Inconsistent with Immich/Authelia implementations (both use secrets)

## Next Steps:

1. Generate NEW secure passwords for all services
2. Create podman secrets
3. Update quadlet files
4. Test and verify
5. Document in secrets inventory

**Status:** In Progress
**Started:** $(date)
