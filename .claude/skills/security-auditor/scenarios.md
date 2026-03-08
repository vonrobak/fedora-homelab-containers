# Security Auditor — Scenarios

Narratives exercising the 5-phase investigation methodology. See [SKILL.md](SKILL.md) for the methodology.

---

## Scenario 1: Routine Biweekly Audit

The scheduled biweekly deep audit (1st and 15th of month). Full Phase 1-5.

### Phase 1: Data Collection
```bash
cd ~/containers
./scripts/security-audit.sh --level 3 --json --compare --report
./scripts/homelab-intel.sh --quiet
podman exec crowdsec cscli alerts list --since 336h -o json | jq 'length'  # 14 days since last audit
```

### Phase 2: Triage
- Parse JSON output. Classify every WARN/FAIL.
- **Expected accepted risks:** SA-TRF-07 (streaming service headers), SA-SEC-04 (GPG signing preference), SA-CTR-07/loki (distroless healthcheck), SA-CMP-02 (NOCOW migration deferred).
- Check for attack chain combinations (see threat-model.md).
- Compare with previous audit — flag new failures.

### Phase 3: Investigation
- Investigate any **new** failures or warnings not present in previous audit.
- For SA-AUTH-07 (auth failures): check pattern — bot scan vs targeted. Cross-reference with CrowdSec alert breakdown.
- For SA-NET-09 (CrowdSec alerts): get alert type breakdown. Normal volume for scanners is 10-50/day.
- For SA-CTR-10 (old images): which images are stale? Are they pinned (expected) or `:latest` (should auto-update)?

### Phase 4: Risk Assessment
- Build remediation roadmap from any genuine findings.
- Reference remediation-catalog.md for effort estimates.
- Accepted risks get re-validated — still accepted? Circumstances changed?

### Phase 5: Report
- Full report with executive summary, investigated findings, known exceptions, trend analysis.
- Highlight any score changes and explain why.
- Include remediation roadmap if any new actions needed.

**Expected outcome:** Score stable (90-97 range). Most findings are accepted risks. Trend narrative: "stable posture, no degradation."

---

## Scenario 2: Post-Deployment Verification

After deploying a new service, verify it doesn't degrade security posture.

### Phase 1: Focused Data Collection
```bash
# Run relevant categories only
./scripts/security-audit.sh --category traefik --json
./scripts/security-audit.sh --category containers --json
./scripts/security-audit.sh --category auth --json --compare
```

### Phase 2: Triage
Focus on deployment-related checks:
- **SA-TRF-03:** Does the new router have CrowdSec bouncer?
- **SA-TRF-04:** Does it have rate limiting?
- **SA-TRF-05:** Is CrowdSec first in middleware chain?
- **SA-TRF-06:** No Traefik labels in the new quadlet?
- **SA-TRF-07:** Security headers present?
- **SA-CTR-02:** Memory limits set?
- **SA-CTR-04:** SELinux labels on volumes?
- **SA-CTR-07:** Healthcheck defined?
- **SA-AUTH-05:** If Authelia-protected, access_control rule exists?
- **SA-CTR-09:** If multi-network, static IPs assigned?

### Phase 3: Investigation
- Only investigate failures — new service should pass all checks.
- For any FAIL: determine if it's a deployment gap or intentional design.
- Reference check-reference.md for the specific check's false positive documentation.

### Phase 4 & 5: Assessment & Report
- Brief report focused on the new service.
- Score should not decrease from pre-deployment baseline.
- Remediation for any new failures is immediate (deployment isn't complete until security checks pass).

**Expected outcome:** All relevant checks pass. No score decrease.

---

## Scenario 3: Score Drop Investigation

Security score dropped > 5 points from previous audit. Requires deep investigation.

### Phase 1: Data Collection
```bash
./scripts/security-audit.sh --level 3 --json --compare
# The --compare flag shows which checks changed status
```

### Phase 2: Triage
- Parse the `trend.new_failures` array from JSON — these caused the drop.
- For each new failure, check:
  - Is it L1 (critical)? If so, investigate immediately.
  - Did multiple failures appear simultaneously? Check attack chain table in threat-model.md.
  - Correlate timing: when did the score drop? `ls -lt ~/containers/data/security-audit/` — was it gradual or sudden?

### Phase 3: Deep Investigation
- **Infrastructure issue** (services down): Check `journalctl --user` for crash reasons. Was there a reboot? Did `systemctl --user` daemon restart?
- **Configuration drift** (middleware, labels): Check `git log --oneline --since="<previous audit date>"` and `git diff` to identify config changes since the last clean score. Use the previous audit date from `ls -lt ~/containers/data/security-audit/` to scope the range.
- **External factor** (CrowdSec, certs): Check connectivity, API keys, Let's Encrypt logs.
- Run investigation playbook commands for each affected category.
- Cross-correlate: Are the failures related? (e.g., system reboot → multiple services down → score drops from multiple L1 checks)

### Phase 4: Risk Assessment
- Determine root cause: single event causing multiple failures vs independent issues.
- Blast radius assessment using threat-model.md.
- Prioritized fix list with effort estimates.

### Phase 5: Report
- Lead with root cause and blast radius.
- Show the attack chain impact if applicable.
- Remediation roadmap with clear priorities.

**Expected outcome:** Root cause identified. Score recoverable after fixes.

---

## Scenario 4: Active Security Incident

Real-time investigation triggered by high alert volume, auth failure spike, or external indicator.

### Phase 1: Rapid Data Collection
```bash
# Quick critical checks first
./scripts/security-audit.sh --level 1 --json

# CrowdSec intel (most time-sensitive)
podman exec crowdsec cscli alerts list --since 1h -o json | jq '.[0:5]'
podman exec crowdsec cscli decisions list -o json | jq 'length'

# Traefik access patterns via Loki
# {job="traefik-access"} | json | status >= 400 | count_over_time([5m])

# Auth failure pattern
journalctl --user -u authelia.service --since "1 hour ago" | grep -i "unsuccessful" | wc -l
```

### Phase 2: Rapid Triage
- **Is the attacker blocked?** Check SA-NET-01 (CrowdSec running) + SA-NET-03 (bouncer active). If both pass, CrowdSec is handling it.
- **Is auth intact?** Check SA-AUTH-01..03. If all pass, Authelia is still protecting services.
- **What's the attack type?** Cross-reference CrowdSec scenario names with auth failure patterns.

### Phase 3: Active Investigation
- **Identify the attacker:** Source IPs from CrowdSec alerts and Traefik access logs.
- **Determine scope:** Which subdomains are targeted? Single service or broad scan?
- **Assess effectiveness:** Are they getting past CrowdSec? Are auth failures from same IPs?
- **Timeline:** When did it start? Is it escalating or steady?

```bash
# Top attacking IPs (last hour)
podman exec crowdsec cscli alerts list --since 1h -o json | jq '[.[].source.ip] | group_by(.) | map({ip: .[0], count: length}) | sort_by(.count) | reverse | .[0:5]'

# Manual ban if needed
podman exec crowdsec cscli decisions add -i <IP> -d 24h -R "manual ban - active attack"
```

### Phase 4: Incident-Specific Actions
- Reference IR runbooks based on attack type.
- If credential stuffing → IR-001 (brute force)
- If vulnerability probe → IR-003 (critical CVE)
- If sustained DDoS → IR-005 (DDoS/abuse)
- Document actions taken for post-incident review.

### Phase 5: Incident Report
- Timeline of events and response.
- Attack indicators and source attribution.
- Effectiveness of defenses (what blocked, what got through).
- Remediation actions taken.
- Preventive measures for recurrence.

**Expected outcome:** Attack contained by existing defenses. Report documents what happened and what (if anything) needs hardening.

---

## Scenario 5: Compliance-Focused Audit

Pre-maintenance drift check. Ensures configuration matches expected state before making changes.

### Phase 1: Compliance Data Collection
```bash
./scripts/security-audit.sh --category compliance --level 3 --json
./scripts/check-drift.sh 2>&1 | head -30
git status
```

### Phase 2: Triage
- SA-CMP-01 (uncommitted changes): What changed? Is it intentional work-in-progress?
- SA-CMP-02 (BTRFS NOCOW): Known accepted risk — re-validate.
- SA-CMP-03 (filesystem permissions): Did a recent operation break ACLs?
- SA-CMP-04 (naming conventions): Any new containers with mismatched names?
- SA-CMP-05 (dependency declarations): Any new services missing Requires/After?

### Phase 3: Investigation
- For permission drift: run `scripts/verify-permissions.sh` and check specific failures.
- For uncommitted changes: `git diff` — are these security-relevant configs?
- For drift: `scripts/check-drift.sh` output — which services drifted?

### Phase 4 & 5: Assessment & Report
- Brief compliance report.
- Clear before/after for any drift found.
- Remediation for anything that shouldn't have drifted.
- Explicitly note accepted risks that were re-validated.

**Expected outcome:** Clean compliance state before maintenance. Any drift either fixed or documented as accepted.
