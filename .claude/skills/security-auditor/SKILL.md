---
name: security-auditor
description: >
  Security engineering team providing comprehensive security audits with investigation depth,
  cross-correlation, hypothesis testing, and risk-informed reporting. Use for: security audit,
  security review, compliance check, vulnerability assessment, attack surface analysis,
  post-deployment security verification, CrowdSec analysis, certificate check, container security,
  hardening review, threat model assessment, security posture check, or "is my system secure".
  Runs 53 automated checks across 7 categories, then investigates findings with Prometheus,
  Loki, CrowdSec, and system telemetry to distinguish real risks from noise. Produces prioritized
  remediation roadmaps with tested fixes and effort estimates.
---

# Security Auditor — 5-Phase Investigation Methodology

## Overview

This skill operates as a **security engineering team**, not a script wrapper. The audit script (`scripts/security-audit.sh`) is the data collector — this skill provides the thinking layer: investigation, correlation, hypothesis testing, and risk-informed reporting.

**Key principle:** The script's score is a summary metric, not an assessment. A score of 95 with an uninvestigated warning is worse than a score of 90 with all findings explained.

## Phase 1: Data Collection

Gather raw data from multiple sources. Don't analyze yet — just collect.

### Primary: Run the Audit Script

```bash
cd ~/containers

# Full audit with JSON output and trend comparison
./scripts/security-audit.sh --level 3 --json --compare
```

**Audit levels:**
- Level 1: Critical only (15 checks) — quick sanity check
- Level 2: Important (28 checks) — standard assessment
- Level 3: All (53 checks) — comprehensive deep audit

**Single category:** `./scripts/security-audit.sh --category auth --json`
Categories: auth, network, traefik, containers, monitoring, secrets, compliance

### Supplementary: System Context

```bash
# Health context (unhealthy system = misleading security data)
./scripts/homelab-intel.sh --quiet

# CrowdSec threat intelligence
podman exec crowdsec cscli alerts list --since 24h -o json | jq 'length'
podman exec crowdsec cscli decisions list -o json | jq 'length'

# Recent autonomous operations (may have made security-relevant changes)
~/containers/.claude/context/scripts/query-decisions.sh --last 7d --stats 2>/dev/null || true
```

### Exit Criteria
- Have audit JSON output with all check results
- Know current health context (is the system healthy enough for audit data to be meaningful?)
- Have CrowdSec threat intel snapshot

---

## Phase 2: Triage & Correlation

Classify every non-PASS finding. Reference [threat-model.md](references/threat-model.md) for attack chain analysis.

### Classification

For each FAIL or WARN finding:

1. **Is this part of an attack chain?** Check [threat-model.md — Attack Chains](references/threat-model.md#attack-chains) for combinations:
   - SA-NET-01 FAIL + SA-AUTH-07 WARN → Chain 1 (defense layer bypass) — elevated urgency. Example: CrowdSec is down and auth failures are spiking = known-bad IPs are reaching services and actively probing credentials.
   - SA-AUTH-01 FAIL + SA-AUTH-03 FAIL → Chain 2 (auth cascade) — critical
   - SA-CTR-01 FAIL + SA-CTR-04 WARN → Chain 3 (container escape path) — critical
   - SA-MON-01 FAIL + SA-MON-02 FAIL → Chain 5 (monitoring blindness) — investigate first

2. **Is this a known acceptable exception?** Check [check-reference.md](references/check-reference.md) for each check's false positive documentation:
   - SA-TRF-07: Streaming services intentionally use custom headers
   - SA-SEC-04: GPG signing is a preference, not a deficiency
   - SA-CTR-07 (Loki): Distroless image — no shell for healthcheck
   - SA-CMP-02: NOCOW migration requires downtime — tracked as accepted risk

3. **Does this need investigation?** A finding needs Phase 3 investigation if:
   - It's part of an attack chain with another finding
   - It's a new failure (not in previous audit)
   - The detail field is ambiguous (could be real or noise)
   - It could indicate an active security event

### Exit Criteria
- Every non-PASS finding classified as: attack chain component, known exception, needs investigation, or informational
- Attack chains identified with severity assessment

---

## Phase 3: Investigation

Deep-dive non-trivial findings using [investigation-playbooks.md](references/investigation-playbooks.md). Use actual system data — never guess.

### Investigation Protocol

For each finding marked "needs investigation":

1. **Collect additional evidence** — run the specific commands from [investigation-playbooks.md](references/investigation-playbooks.md) for that category
2. **Cross-correlate** — check related data sources (Prometheus metrics, Loki logs, CrowdSec intel, systemd journal)
3. **Determine true vs false positive** — use the indicators documented in the playbook
4. **Document evidence** — record what was found, not just the conclusion

### Key Investigation Commands by Category

**AUTH — Failure pattern analysis:**
```bash
journalctl --user -u authelia.service --since "24 hours ago" | grep -i "unsuccessful" | grep -oP 'username=[^ ]+' | sort | uniq -c | sort -rn
```

**NETWORK — CrowdSec alert breakdown:**
```bash
podman exec crowdsec cscli alerts list --since 24h -o json | jq '[.[].scenario] | group_by(.) | map({scenario: .[0], count: length}) | sort_by(.count) | reverse'
```

**TRAEFIK — Per-router middleware audit:**
```bash
yq '.http.routers | to_entries[] | {"router": .key, "middlewares": .value.middlewares}' config/traefik/dynamic/routers.yml
```

**CONTAINERS — Memory and OOM analysis:**
```bash
podman stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.MemLimit}}\t{{.MemPerc}}"
journalctl --user --since "24 hours ago" | grep -i "oom_kill\|memory\.max" | head -10
```

**MONITORING — Scrape target details:**
```bash
podman exec prometheus wget -q -O- 'http://localhost:9090/api/v1/targets' | jq '.data.activeTargets[] | select(.health=="down") | {job: .labels.job, error: .lastError}'
```

### Loki Queries for Log Correlation

```logql
# Auth failures with source IPs
{job="traefik-access"} | json | status >= 400 | line_format "{{.ClientHost}} {{.RequestHost}} {{.DownstreamStatus}}"

# Error rate spike detection
rate({job="traefik-access"} | json | status >= 500 [5m])

# Remediation decision correlation
{job="remediation-decisions"} | json | success="false"
```

### Escalation Criteria

Escalate to **systematic-debugging** skill if:
- Root cause is unclear after initial investigation
- Multiple findings interact in unexpected ways
- A finding points to a systemic issue (not a single misconfiguration)

### Exit Criteria
- Every investigated finding has evidence-based assessment (not "this is probably fine")
- True vs false positive determination for each
- Root cause identified for genuine issues

---

## Phase 4: Risk Assessment & Remediation

Model blast radius and prioritize fixes. Reference [remediation-catalog.md](references/remediation-catalog.md) for tested fixes and [threat-model.md](references/threat-model.md) for defense-in-depth impact.

### For Each Genuine Finding

1. **Blast radius:** How many services/users affected? Reference [threat-model.md — Attack Surface Map](references/threat-model.md#attack-surface-map)
2. **Exploitability:** Is this exploitable now, or does it require another failure first?
3. **Compensating controls:** What's still protecting the system? Reference [threat-model.md — Defense-in-Depth Map](references/threat-model.md#defense-in-depth-map)
4. **Fix effort:** Quick / Medium / Significant from [remediation-catalog.md](references/remediation-catalog.md)
5. **Priority:** Combine blast radius + exploitability + effort

### Priority Framework

| Priority | Criteria | Timeline |
|----------|----------|----------|
| CRITICAL | L1 failure, actively exploitable, wide blast radius | Fix now |
| HIGH | L1/L2 failure, requires another failure to exploit | Fix within 24h |
| MEDIUM | L2 warning, compensating controls exist | Next maintenance window |
| LOW | L3 finding, accepted risk, or informational | Track and review |

### Exit Criteria
- Prioritized remediation roadmap with effort estimates
- Each finding has: priority, blast radius, fix reference, effort estimate

---

## Phase 5: Report

Produce a narrative-driven report that distinguishes investigated findings from raw results.

### Report Structure

```
**Security Score: XX/100** [trend indicator]

**Executive Summary** (2-3 sentences)
- Overall posture assessment (not just score)
- Key changes since last audit
- Active threat indicators (if any)

**Investigated Findings** (findings that received Phase 3 deep-dive)
For each:
- What was found (evidence, not just check message)
- Why it matters (blast radius, attack chain context)
- Recommendation with effort and priority
- Reference to remediation-catalog.md

**Known Exceptions** (findings classified as acceptable in Phase 2)
- Brief list with rationale for each

**Domain Summary**
| Category | Pass | Warn | Fail | Notes |
|----------|------|------|------|-------|

**Trend Analysis** (vs previous audit)
- Score change and direction
- New findings / resolved findings
- Pattern narrative (improving, degrading, stable)

**Remediation Roadmap** (prioritized)
1. [CRITICAL] — immediate action
2. [HIGH] — within 24h
3. [MEDIUM] — next maintenance window
4. [LOW] — track
```

### Exit Criteria
- Report clearly distinguishes investigated findings from raw check results
- Every finding has evidence-based context (not template text)
- Remediation roadmap is prioritized by risk, not just severity level

---

## Guardrails

These anti-patterns indicate the methodology is being shortcut:

| Anti-Pattern | What To Do Instead |
|---|---|
| "Just run the script and format output" | That's Phase 1 only. Triage (P2), investigate (P3), then report. |
| "This warning is probably fine" | Investigate in Phase 3 first. Document why it's fine with evidence. |
| "Here are fixes for everything" | Return to Phase 3. Investigate before recommending. |
| "Score is 95, everything looks good" | Score is a summary metric. Investigate all non-PASS findings. |
| Proposing architecture changes for config issues | Check ADRs first. The architecture may be intentional. |
| Skipping Phase 2 triage | Correlation catches attack chains that individual checks miss. |
| Recommending CrowdSec manual bans without evidence | Check if CrowdSec scenarios already handled it automatically. |

---

## Integration Points

### Before This Skill
- **homelab-intelligence:** Run health check first. Unhealthy system produces misleading security data (services down → false FAIL findings).

### During Investigation (Phase 3)
- **systematic-debugging:** Escalate complex findings that need root cause analysis beyond this skill's scope.
- **autonomous-operations:** Check `query-decisions.sh` for security-relevant automated actions in the decision log.

### After This Skill
- **remediation-catalog.md:** Reference for all tested fixes with effort estimates.
- **Incident runbooks:** Reference for active security events:
  - **IR-001** — Brute force / scanning attack
  - **IR-002** — Compromised credentials
  - **IR-003** — Critical CVE
  - **IR-004** — Compliance failure
  - **IR-005** — DDoS / network security event
  - **DR-001..004** — Disaster recovery

---

## Reference Files

| File | Purpose | When to Use |
|------|---------|-------------|
| [check-reference.md](references/check-reference.md) | Full 53-check catalog with scoring, rationale, false positives | Phase 2 triage — classify findings |
| [threat-model.md](references/threat-model.md) | Attack surface, adversary profiles, attack chains, defense layers | Phase 2 correlation, Phase 4 blast radius |
| [investigation-playbooks.md](references/investigation-playbooks.md) | Per-category investigation commands and correlation procedures | Phase 3 deep-dives |
| [remediation-catalog.md](references/remediation-catalog.md) | Tested fixes with effort estimates and verify commands | Phase 4 remediation planning |

---

## History & Automation

**Audit history:** JSON files in `~/containers/data/security-audit/audit-YYYY-MM-DD.json`

**Scheduled:** Biweekly systemd timer (1st and 15th, 06:45) runs `--level 3 --json --report --compare`

**Manual report:** `./scripts/security-audit.sh --level 3 --report` → `docs/99-reports/security-audit-YYYY-MM-DD.md`

**Script reference:** [check-reference.md](references/check-reference.md) — full catalog of all 53 checks
