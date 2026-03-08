# Investigation Playbooks

Per-category deep-dive procedures with exact commands. Referenced by SKILL.md Phase 3 (Investigation).

Each finding type provides: additional data to collect, how to correlate with other sources, true vs false positive indicators, and escalation criteria.

---

## Table of Contents

- [AUTH — Authentication & Access Control](#auth--authentication--access-control)
- [NETWORK — CrowdSec & Network Security](#network--crowdsec--network-security)
- [TRAEFIK — Reverse Proxy & TLS](#traefik--reverse-proxy--tls)
- [CONTAINERS — Container Security](#containers--container-security)
- [MONITORING — Observability Stack](#monitoring--observability-stack)
- [SECRETS — Secrets Management](#secrets--secrets-management)
- [COMPLIANCE — Configuration Drift & Standards](#compliance--configuration-drift--standards)

---

## AUTH — Authentication & Access Control

### Service Down (SA-AUTH-01, SA-AUTH-02, SA-AUTH-03)

**Additional data to collect:**
```bash
# Service status and recent events
systemctl --user status authelia.service redis-authelia.service
journalctl --user -u authelia.service --since "1 hour ago" --no-pager | tail -30
journalctl --user -u redis-authelia.service --since "1 hour ago" --no-pager | tail -30

# Container health and resources
podman healthcheck run authelia
podman stats --no-stream authelia redis-authelia

# Check if restart loop
systemctl --user show authelia.service -p NRestarts
```

**Correlate with:**
- SA-TRF-01: If Traefik also down, this is a broader infrastructure issue, not auth-specific
- Prometheus: `up{job="authelia"}` — was it recently up? When did it go down?
- Recent changes: `git log --oneline -5` — was a config change made?

**True vs false positive:**
- True: Service status shows "failed" or "inactive". Journal shows error messages.
- False: Service is restarting (brief window during daemon-reload). Check `NRestarts`.

**Escalation:** If Authelia is down and can't be restarted → all protected services are inaccessible. Reference **IR-001** runbook. Check if the issue is Redis (session store) or Authelia itself.

### Auth Failure Analysis (SA-AUTH-07)

**Additional data to collect:**
```bash
# Recent auth failures with context
journalctl --user -u authelia.service --since "24 hours ago" | grep -i "unsuccessful\|failed\|denied" | tail -20

# Extract unique usernames attempted
journalctl --user -u authelia.service --since "24 hours ago" | grep -i "unsuccessful" | grep -oP 'username=[^ ]+' | sort | uniq -c | sort -rn

# Time distribution (hourly buckets)
journalctl --user -u authelia.service --since "24 hours ago" | grep -i "unsuccessful" | awk '{print $1, $2, substr($3,1,2)":00"}' | sort | uniq -c
```

**Correlate with:**
- SA-NET-09: High CrowdSec alerts at same time = coordinated attack
- Loki: `{job="traefik-access"} | json | status >= 400 | line_format "{{.ClientHost}} {{.RequestHost}} {{.RequestPath}} {{.DownstreamStatus}}"` — what domains are being targeted?
- CrowdSec: `podman exec crowdsec cscli alerts list --since 24h -o json | jq '.[].scenario'` — are brute-force scenarios firing?

**True vs false positive indicators:**
- **Bot scan:** Many different usernames, spread across time, from blocked IPs → noise, CrowdSec handling it
- **Targeted attack:** Same username, persistent source IP, targeting specific subdomain → investigate further
- **Legitimate failures:** Low count (< 10), recognizable usernames, normal hours → user typos

**Escalation:** If targeted attack indicators present → reference **IR-001** (brute force). Consider temporary Authelia lockout policy or CrowdSec manual ban: `podman exec crowdsec cscli decisions add -i <IP> -d 24h -R "manual ban"`.

---

## NETWORK — CrowdSec & Network Security

### CrowdSec Issues (SA-NET-01, SA-NET-02, SA-NET-03)

**Additional data to collect:**
```bash
# CrowdSec status overview
podman exec crowdsec cscli capi status
podman exec crowdsec cscli bouncers list
podman exec crowdsec cscli metrics

# Recent alerts with types
podman exec crowdsec cscli alerts list --since 24h -o json | jq '.[0:10] | .[] | {scenario: .scenario, source_ip: .source.ip, decisions_count: (.decisions | length)}'

# Active decisions (current blocks)
podman exec crowdsec cscli decisions list -o json | jq 'length'

# Acquisition status (is CrowdSec reading logs?)
podman exec crowdsec cscli machines list
```

**Correlate with:**
- SA-AUTH-07: Spike in auth failures while CrowdSec is down = unfiltered attack
- Traefik access logs via Loki: `{job="traefik-access"} | json | status >= 400 | count_over_time([5m])` — rate of blocked requests
- Prometheus: `crowdsec_local_api_decisions_total` — decision rate

**True vs false positive:**
- SA-NET-02 (CAPI disconnected): Check internet connectivity from CrowdSec container. Transient network issues resolve within minutes.
- SA-NET-03 (no bouncers): Critical — means CrowdSec detects but can't enforce. Check Traefik CrowdSec plugin config in `middleware.yml`.

**Escalation:** CrowdSec completely down with active attack indicators → reference **IR-005** (DDoS/abuse). Manual rate limit tightening in `middleware.yml` as interim measure.

### Alert Volume Analysis (SA-NET-09)

**Additional data to collect:**
```bash
# Alert type breakdown
podman exec crowdsec cscli alerts list --since 24h -o json | jq '[.[].scenario] | group_by(.) | map({scenario: .[0], count: length}) | sort_by(.count) | reverse'

# Top source IPs
podman exec crowdsec cscli alerts list --since 24h -o json | jq '[.[].source.ip] | group_by(.) | map({ip: .[0], count: length}) | sort_by(.count) | reverse | .[0:10]'

# Decision types (ban, captcha, etc.)
podman exec crowdsec cscli decisions list -o json | jq '[.[].type] | group_by(.) | map({type: .[0], count: length})'
```

**Normal baselines (for comparison):**
- **Typical:** 10-50 alerts/day from automated scanners (HTTP probes, SSH brute force)
- **Elevated but expected:** 50-100 during active scanning campaigns (holidays, vulnerability disclosures)
- **Abnormal:** > 100 from concentrated source or targeting specific service → investigate
- **Zero after 7+ days:** CrowdSec may not be processing logs — check `cscli metrics` for acquisition stats

### Unexpected Ports (SA-NET-05)

**Additional data to collect:**
```bash
# Identify process on unexpected port
ss -tlnp | grep ":<port>"

# If systemd service
systemctl list-units --type=service --state=running | grep -i "<process_name>"

# Check if it's a known system service
rpm -qf $(which <process_name> 2>/dev/null) 2>/dev/null
```

**Known false positive:** Port 27500 = passimd (Passim firmware distribution daemon from fwupd/LVFS). Legitimate Fedora system service.

---

## TRAEFIK — Reverse Proxy & TLS

### Certificate Issues (SA-TRF-02)

**Additional data to collect:**
```bash
# Check Traefik ACME logs
podman logs traefik 2>&1 | grep -i "acme\|certificate\|letsencrypt\|challenge" | tail -20

# Verify DNS-01 challenge works (Cloudflare API)
podman exec traefik env | grep CF_  # Should show CF_DNS_API_TOKEN

# Check cert details
podman exec traefik cat /letsencrypt/acme.json | jq '.letsencrypt.Certificates[] | {domain: .domain.main, sans: .domain.sans}'

# Verify from outside
echo | openssl s_client -connect patriark.org:443 -servername patriark.org 2>/dev/null | openssl x509 -noout -dates -subject
```

**Correlate with:**
- Cloudflare API status: Was there a Cloudflare outage?
- DNS records: `dig TXT _acme-challenge.patriark.org` — any stale challenge records?
- Recent config changes: Was `traefik.yml` or the Cloudflare token modified?

**Escalation:** Certificates expiring within 24h → immediate action. Check if DNS-01 challenge is working. If Cloudflare token expired, recreate: `printf '%s' '<token>' | podman secret create cloudflare_dns_token -` (note: use `printf`, not `echo`).

### Middleware Audit (SA-TRF-03, SA-TRF-04, SA-TRF-05, SA-TRF-07)

**Additional data to collect:**
```bash
# Per-router middleware inventory
yq '.http.routers | to_entries[] | {"router": .key, "middlewares": .value.middlewares}' config/traefik/dynamic/routers.yml

# Identify routers missing CrowdSec
yq '[.http.routers | to_entries[] | select(.value.entryPoints[]? == "websecure") | select(.value.middlewares[]? != "crowdsec-bouncer@file") | .key]' config/traefik/dynamic/routers.yml

# Identify routers without security headers
yq '[.http.routers | to_entries[] | select(.value.entryPoints[]? == "websecure") | select([.value.middlewares[]? | test("security-headers|hsts-only")] | any | not) | .key]' config/traefik/dynamic/routers.yml

# Verify middleware definitions exist
yq '.http.middlewares | keys' config/traefik/dynamic/middleware.yml
```

**True vs false positive for SA-TRF-07:**
- SSO portal (sso.patriark.org) sets its own headers — doesn't need security-headers middleware
- Services with custom header middlewares (security-headers-jellyfin, security-headers-ha, security-headers-gathio) are properly handled
- Nextcloud uses hsts-only (sets its own CSP) — this counts as having headers

**Escalation:** Router without CrowdSec (SA-TRF-03) → add middleware immediately. This is the cheapest check and should never be missing.

### ADR-016 Compliance (SA-TRF-06)

**Additional data to collect:**
```bash
# Find specific Traefik labels in quadlets
grep -rn "^Label=traefik\." ~/containers/quadlets/*.container

# Show the offending lines with context
for f in ~/containers/quadlets/*.container; do
    if grep -q "^Label=traefik\." "$f" 2>/dev/null; then
        echo "=== $(basename $f) ==="
        grep -n "^Label=traefik\." "$f"
    fi
done
```

**Fix:** Move all routing from labels to `config/traefik/dynamic/routers.yml`. See [remediation-catalog.md](remediation-catalog.md#sa-trf-06-traefik-labels-in-quadlets).

---

## CONTAINERS — Container Security

### OOM Investigation (SA-CTR-05)

**Additional data to collect:**
```bash
# Find which container was OOM killed (user journal — systemd cgroup OOM)
journalctl --user --since "24 hours ago" | grep -i "oom_kill\|oom-kill\|memory\.max\|invoked oom" | head -10

# Also check system journal — kernel OOM killer can kill rootless container processes
sudo journalctl -k --since "24 hours ago" | grep -i "oom" | head -10

# Current memory usage vs limits
podman stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.MemLimit}}\t{{.MemPerc}}"

# Check specific container's memory history (Prometheus)
# Query: container_memory_usage_bytes{name="<container>"} / container_spec_memory_limit_bytes{name="<container>"}
```

**Correlate with:**
- SA-CTR-02: Does the OOM'd container have memory limits? Limits too low → increase. No limits → add them.
- Prometheus: `container_memory_usage_bytes{name=~".*"}` — memory trend over time
- Service availability: Was there a corresponding SLO violation?

**True vs false positive:**
- **True OOM:** Journal shows `memory.max` or `oom_kill` with specific container/cgroup path
- **cAdvisor noise:** cAdvisor may log informational OOM metrics that aren't actual kills. Check if a container actually restarted.

**Escalation:** Repeated OOM kills on critical service (Traefik, Authelia) → increase `MemoryMax=` immediately. For non-critical services → investigate memory leak or adjust limits in next maintenance window.

### SELinux Issues (SA-CTR-01, SA-CTR-04)

**Additional data to collect:**
```bash
# SELinux status
sestatus
getenforce

# Recent AVC denials
sudo ausearch -m AVC --start recent 2>/dev/null | head -20

# Check specific container volume labels
podman inspect <container> | jq '.[0].Mounts[] | {source: .Source, destination: .Destination, options: .Options}'
```

**Escalation:** SELinux disabled (SA-CTR-01) → critical security regression. Do not run `setenforce 1` without checking for pending AVC denials first. Investigate why it was disabled.

### Static IP Issues (SA-CTR-09)

**Additional data to collect:**
```bash
# Current container IPs across networks
for c in $(podman ps --format '{{.Names}}'); do
    echo "=== $c ==="
    podman inspect "$c" | jq -r '.[0].NetworkSettings.Networks | to_entries[] | "\(.key): \(.value.IPAddress)"'
done

# Verify Traefik hosts file
podman exec traefik cat /etc/hosts | grep "10.89"

# Check for untrusted proxy errors
journalctl --user -u home-assistant.service --since "1 hour ago" | grep -i "untrusted" | tail -5
```

**Known convention:** Static IPs use .69+ to avoid IPAM collisions. Same last octet per service across all networks. See ADR-018.

---

## MONITORING — Observability Stack

### Scrape Target Down (SA-MON-04)

**Additional data to collect:**
```bash
# List all targets with status
podman exec prometheus wget -q -O- 'http://localhost:9090/api/v1/targets' | jq '.data.activeTargets[] | {job: .labels.job, instance: .labels.instance, health: .health, lastError: .lastError}' | head -40

# Check specific target's last scrape error
podman exec prometheus wget -q -O- 'http://localhost:9090/api/v1/targets' | jq '.data.activeTargets[] | select(.health=="down") | {job: .labels.job, error: .lastError}'

# Verify network connectivity from Prometheus to target
podman exec prometheus wget -q --spider -T 5 http://<target_host>:<port>/metrics
```

**Correlate with:**
- Is the target service actually running? `systemctl --user is-active <service>.service`
- Is the target on the monitoring network? Check quadlet for `Network=systemd-monitoring.network`
- Was the target recently deployed or moved? `git log --oneline -5`

**True vs false positive:**
- Transient during restarts: target down for < 2 minutes after service restart → expected
- Persistent: target down for > 5 minutes → investigate network/service issue

### Alert Rule Validation (SA-MON-07)

**Additional data to collect:**
```bash
# List all alert rules with status
podman exec prometheus wget -q -O- 'http://localhost:9090/api/v1/rules' | jq '.data.groups[] | {name: .name, rules: [.rules[] | {alert: .name, state: .state, health: .health}]}'

# Check for rule evaluation errors
podman exec prometheus wget -q -O- 'http://localhost:9090/api/v1/rules' | jq '.data.groups[] | .rules[] | select(.health != "ok") | {alert: .name, health: .health, lastError: .lastError}'

# Verify rules directory
ls -la ~/containers/config/prometheus/rules/
```

---

## SECRETS — Secrets Management

### Git History Audit (SA-SEC-02)

**Additional data to collect:**
```bash
# Detailed check of flagged files
cd ~/containers && git log --oneline -20 --diff-filter=A --name-only | grep -iE '\.(key|pem|env)$|secret|password|credential'

# Check if file still exists (may have been removed but is in history)
cd ~/containers && git log --all --diff-filter=D --name-only | grep -iE '\.(key|pem|env)$|secret|password|credential'

# Check file content (if it's a false positive like documentation)
cd ~/containers && git show <commit>:<filepath> | head -5
```

**True vs false positive:**
- True: File contains actual credentials, API keys, or certificates
- False: Documentation about secrets management, template files with placeholder values, skill files with "secret" in the name

**Escalation:** Real secret in git history → rotate the credential IMMEDIATELY, then use `git filter-repo` to remove from history. Reference **IR-002** (compromised credentials).

### Podman Secrets Audit (SA-SEC-05)

**Additional data to collect:**
```bash
# List all registered secrets
podman secret ls

# Cross-reference with quadlet requirements
grep -rh "^Secret=" ~/containers/quadlets/*.container | sort -u

# Check for orphaned secrets (registered but not used)
comm -23 <(podman secret ls --format '{{.Name}}' | sort) <(grep -rh "^Secret=" ~/containers/quadlets/*.container | sed 's/Secret=//;s/,.*//' | sort -u)
```

---

## COMPLIANCE — Configuration Drift & Standards

### Drift Detection (SA-CMP-01, SA-CMP-03)

**Additional data to collect:**
```bash
# What changed?
cd ~/containers && git status
cd ~/containers && git diff

# Is it config or data?
cd ~/containers && git diff --stat

# Permission verification details
~/containers/scripts/verify-permissions.sh 2>&1

# Check drift detection script output
~/containers/scripts/check-drift.sh 2>&1 | head -30
```

**Correlate with:**
- Recent operations: `git log --oneline -5` — was a change made but not committed?
- Autonomous operations: `~/containers/.claude/context/scripts/query-decisions.sh --last 24h` — did an automated action cause drift?

### BTRFS NOCOW Verification (SA-CMP-02)

**Additional data to collect:**
```bash
# Check all database directories
for dir in /mnt/btrfs-pool/subvol7-containers/prometheus /mnt/btrfs-pool/subvol7-containers/loki /mnt/btrfs-pool/subvol7-containers/postgresql-immich; do
    echo "=== $(basename $dir) ==="
    lsattr -d "$dir" 2>/dev/null
    du -sh "$dir" 2>/dev/null
done

# Verify BTRFS filesystem
btrfs fi usage -T /mnt/btrfs-pool
```

**Note:** Fixing NOCOW requires empty directory recreation — see [remediation-catalog.md](remediation-catalog.md#sa-cmp-02-btrfs-nocow-missing) for full procedure.

---

## Cross-Category Correlation Patterns

When multiple findings appear together, investigate these patterns:

| Pattern | Findings | Investigation |
|---------|----------|---------------|
| Active attack | SA-AUTH-07 high + SA-NET-09 high | Cross-reference IPs, check Loki for targeted domains |
| Defense gap | SA-NET-01 FAIL + any SA-AUTH FAIL | CrowdSec down + auth issues = completely exposed |
| Post-change regression | SA-CMP-01 WARN + new failures | Check `git diff` — recent changes broke something |
| Resource exhaustion | SA-CTR-05 WARN + SA-MON-04 WARN | OOM kills causing scrape target failures |
| Monitoring blindness | SA-MON-01..03 FAIL | Can't detect other issues — investigate monitoring first |
| Container security regression | SA-CTR-01 FAIL + SA-CTR-04 WARN | SELinux + labels both failing = container escape risk |
