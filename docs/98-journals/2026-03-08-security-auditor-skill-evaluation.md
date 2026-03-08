# Security Auditor Skill Evaluation

**Date:** 2026-03-08
**Objective:** Test the security-auditor skill (PR #113), evaluate script behavior, identify bugs and improvement opportunities, and document findings for skill-creator consumption.

## Test Summary

| Aspect | Result |
|--------|--------|
| Script execution | Exit code 1 (arithmetic error, fixed) |
| Check coverage | 53/53 checks ran (level 3) |
| Score calculation | Correct (75/100 = 100 - 8x3 - 1x1) |
| JSON output | Valid, parseable, complete |
| Report generation | Working, markdown saved to docs/99-reports/ |
| Trend comparison | Working (shows delta from previous audit) |
| Timer/automation | Configured (1st/15th @ 06:45) |

## Bug Found and Fixed

**Bug:** `grep -ci ... || echo "0"` pattern on 5 lines (264, 292, 613, 632, 703).

**Root cause:** When `grep -c` finds 0 matches, it outputs "0" to stdout AND exits with code 1. The `|| echo "0"` fallback fires because of the non-zero exit, appending a second "0" via echo. The variable captures `"0\n0"` (two lines), which bash arithmetic `(( ))` cannot parse.

**Fix:** Replace `|| echo "0"` with `|| true` on all 5 instances. `grep -c` already outputs "0" when no matches; we only need to suppress the exit code for `set -e`.

**Impact:** The bug caused the script to emit an arithmetic error to stderr but still complete (the error was non-fatal due to how bash handles the subsequent `if` evaluation). The check results were still correct despite the error message.

## Audit Results (Post-Fix)

**Score: 75/100** | 53 checks: 44 pass, 9 warn, 0 fail

### Warnings Breakdown

| Check ID | Level | Category | Finding | Actionable? |
|----------|-------|----------|---------|-------------|
| SA-TRF-07 | L2 | traefik | Security headers: 9/16 routers | Yes - intentional for some services (streaming, native auth) |
| SA-CTR-05 | L2 | containers | OOM events: 196 in 24h | Investigate - high count, likely journal noise |
| SA-CTR-07 | L2 | containers | No healthcheck: loki, unpoller | Known gap (loki=distroless, unpoller=missing) |
| SA-CTR-09 | L2 | containers | Missing static IPs: nextcloud-db, nextcloud-redis | Low priority - single-network containers |
| SA-CTR-11 | L3 | containers | Missing Slice: nextcloud stack, unpoller | Low priority - resource grouping |
| SA-SEC-03 | L2 | secrets | secrets.yaml perms 644 | Tighten to 600 |
| SA-SEC-04 | L2 | secrets | GPG signing not enabled | Known - user preference |
| SA-CMP-01 | L2 | compliance | Uncommitted changes | Expected (we edited the script) |
| SA-CMP-02 | L2 | compliance | Missing NOCOW: loki, postgresql-immich | Known gap - requires empty dir recreation |

### Warning Analysis

**True positives (actionable):** SA-SEC-03 (easy fix), SA-CTR-05 (investigate OOM count)
**Accepted risks:** SA-SEC-04 (GPG), SA-CTR-07 (loki distroless), SA-CMP-02 (NOCOW migration effort)
**False-ish positives:** SA-CTR-09 (single-network containers don't need static IPs), SA-TRF-07 (intentional for streaming/native-auth services)
**Transient:** SA-CMP-01 (uncommitted changes from this test session)

## Skill Architecture Evaluation

### Strengths

1. **Comprehensive coverage:** 53 checks across 7 categories is thorough for a homelab
2. **Leveled approach:** L1/L2/L3 allows quick critical checks vs deep audits
3. **ADR compliance checks:** SA-TRF-06 (no labels), SA-CTR-06 (network ordering), SA-CTR-09 (static IPs) enforce architectural decisions
4. **Multiple output modes:** Terminal (colored), JSON (machine-readable), Markdown report — all work correctly
5. **Trend tracking:** JSON history with `--compare` flag enables regression detection
6. **Scoring model:** Weighted by severity (L1: -15, L2: -5, L3: -2) with WARN at half penalty — reasonable
7. **Category filtering:** `--category auth` for focused audits
8. **Automation-ready:** Systemd timer for biweekly execution with `--json --report` flags

### Weaknesses and Improvement Opportunities

1. **SA-CTR-09 false positive:** Flags single-network containers (nextcloud-db, nextcloud-redis) for missing static IPs. Static IPs are only needed for multi-network containers (ADR-018). The check at line 703 correctly checks `net_count > 1`, but the multi-network detection may be miscounting — needs investigation.

2. **SA-TRF-07 lacks nuance:** Not all routers need security headers. Streaming services (Jellyfin, Navidrome, Audiobookshelf) and services with native auth may intentionally omit some headers. Consider a whitelist/exception mechanism.

3. **SA-CTR-05 OOM detection too broad:** `grep -ci "oom\|out of memory"` on all journal entries catches kernel OOM mentions, cgroup warnings, and informational messages — not just actual container kills. Consider filtering to `oom_kill` or `memory.oom_control` specifically.

4. **No suppression/exception mechanism:** No way to mark known-acceptable warnings (e.g., `# audit-suppress: SA-SEC-04`) to track intentional risk acceptance vs genuine drift.

5. **Report doesn't include trend:** The markdown report shows current state but not the delta from previous audit (even though `--compare` calculates it).

6. **Exit code semantics:** Script exits 1 for warnings — this conflates "warnings found" with "script error", which caused confusion when diagnosing the arithmetic bug.

7. **Scoring inconsistency:** Previous run (before edits, same day) scored 78 with 8 warnings, current run scores 75 with 9 warnings. The math is correct each time, but the trend comparison shows `previous_score: 100` which was an earlier run — the trend doesn't always compare to the most recent run of the same level.

### SKILL.md Evaluation

The SKILL.md file is well-structured with clear workflow phases (Gather, Analyze, Report). The scenarios.md provides good real-world usage examples. Integration with other skills (homelab-intelligence, systematic-debugging) is documented.

**Missing from SKILL.md:**
- No guidance on interpreting false positives
- No mention of the `--compare` flag behavior
- Check ID quick reference could include severity weights

## Recommendations

### Priority 1 (Bug fixes)
- [x] Fix `grep -ci || echo "0"` arithmetic bug (5 instances) — **DONE**

### Priority 2 (Accuracy improvements)
- [ ] Fix SA-CTR-09: Only flag multi-network containers missing static IPs
- [ ] Refine SA-CTR-05: Use more specific OOM patterns (`oom_kill`, `memory.max`)
- [ ] Add trend data to markdown report

### Priority 3 (Feature enhancements)
- [ ] Add suppression/exception mechanism for accepted risks
- [ ] Add SA-TRF-07 exception list for streaming/native-auth services
- [ ] Separate exit codes: 0=all pass, 1=warnings, 2=failures, 3=script error

## Skill-Creator Context

This evaluation is designed to be consumed by the [skill-creator](https://github.com/anthropics/skills/tree/main/skills/skill-creator) skill for iterative improvement. Key inputs for skill-creator:

### What the skill does well (preserve)
- Multi-level audit with weighted scoring
- ADR compliance enforcement
- Machine-readable JSON + human-readable terminal + report outputs
- Trend tracking across runs
- Clean separation: script handles data collection, SKILL.md handles interpretation guidance

### What needs improvement (iterate on)
- False positive rate on container checks (SA-CTR-09, SA-CTR-05)
- No exception/suppression mechanism for accepted risks
- Report output missing trend data
- Exit code conflation (warning vs error)
- SKILL.md could guide on false positive interpretation

### Eval criteria for skill-creator
- **Trigger accuracy:** Should trigger on "security audit", "security posture", "run audit", "check security"
- **Output quality:** Score + categorized findings + actionable recommendations
- **False positive rate:** Minimize warnings that aren't actionable
- **Integration:** Should reference homelab-intelligence for context, systematic-debugging for deep dives
- **Idempotency:** Running twice with no changes should produce identical scores
