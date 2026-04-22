# Posture Intel Scripts — Handoff for Fresh Sessions

**Date:** 2026-04-22
**PR:** _pending_
**Context:** Built two Python scripts (`scripts/security/posture-local.py`, `scripts/security/posture-remote.py`) that actively gather forensic security intel from two disjoint vantages and emit a shared JSON schema. They are purpose-built to be *consumed by a fresh Claude Code session* that doesn't have today's context. This entry is the handoff — what shipped, what the expected false-positives look like, and the two prompts that orient a new session efficiently.

---

## What shipped

| File | Purpose |
|---|---|
| `scripts/security/posture-local.py` | 11-category internal-plane gap finder run on fedora-htpc. No sudo. **Committed.** |
| `scripts/security/posture-remote.py` | External-plane perimeter probe with active attacks against our own edge. **Gitignored** — distributed to the MacBook via scp, not via `git clone`. Publishing a perimeter-tuned attack kit on a public repo hands adversaries recon-time. |
| `scripts/security/README.md` | Ingestion contract, severity scale, active-probe footprint, cadence table. |
| `scripts/security/README-ssh-sync.md` | Old README (YubiKey SSH sync), renamed to free the canonical path. |

Output lands at `data/security-posture/{local,remote}/<UTC>.json` (gitignored via `data/*`). Shared schema: `meta`, `summary`, `findings[]`, `raw{}`. Finding IDs are stable per category (`LBIND-0001`, `RAUTH-0001`) so reports diff cleanly across runs.

Severity is a heuristic. The scripts do not interpret — they gather. All triage belongs to the consuming session.

---

## Handoff prompt A — local session (on fedora-htpc)

Paste into a fresh Claude Code session invoked inside `~/containers`:

```
You are triaging a security-posture report produced by
scripts/security/posture-local.py. Read the most recent JSON under
data/security-posture/local/ (ls -t | head -1). If none exists, run the
script first: `python3 scripts/security/posture-local.py`.

Your job is to turn the JSON into a prioritised hardening plan for this
homelab.

Process:
1. Skim meta.summary. Spend 0 time on findings with severity=info until
   after critical/high/medium are cleared.
2. For EACH finding with severity >= medium, classify it as one of:
     (a) real gap — propose a concrete file edit or config change
     (b) known-accepted — cite the ADR, journal, or repo state that accepts
         it (e.g., cadvisor privileged is intentional for metric collection)
     (c) collector false-positive — explain which assumption is wrong and
         propose a patch to the script
3. Group remediations by effort: ≤15 min, ≤1 hour, ≤half-day, requires ADR.
4. Cross-check against the latest remote report under
   data/security-posture/remote/ if one exists. Pay special attention to
   findings that contradict each other — e.g., local says rate-limit is
   300rpm, remote observed first 429 at request N; is N consistent?
5. Do NOT re-run the script to collect new data in this first pass unless
   a finding is ambiguous and a fresh datapoint would resolve it. In that
   case, use `--category <name>` to keep the run narrow.

Context you MUST read before starting (load these files):
- CLAUDE.md (architecture principles and ADR-016/018 constraints)
- docs/98-journals/2026-04-22-posture-intel-scripts-handoff.md (this file —
  contains known false-positives you should not re-derive)
- docs/98-journals/2026-04-22-ingress-forensics-udm-blindspot-private.md
  (UDM Region Block is syslog-invisible — shapes what "quiet logs" means)
- docs/98-journals/2026-04-21-crowdsec-acquisition-and-rate-limit-retune.md
  (post-ADR-022 rate-limit values and CrowdSec acquisition state)

Output format: a markdown triage document written to docs/99-reports/
with filename posture-triage-local-<YYYY-MM-DD>.md. Sections:
  ## Summary (counts + headline risks)
  ## Real gaps (numbered, with proposed edits)
  ## Known-accepted (one line each, with citation)
  ## Collector false-positives (if any, with proposed script patches)
  ## Recommended next actions (≤5 items, concrete)

Do not edit code in this pass. The deliverable is the triage document.
```

---

## Handoff prompt B — remote session (on MacBook Air)

Paste into a Claude Code session on the MacBook. The remote script is NOT in the homelab repo (gitignored — it's a tuned attack kit against our own perimeter and the repo is public). It lives at `~/posture/posture-remote.py` on the Mac, transferred out-of-band via:

```bash
scp fedora-htpc.lokal:~/containers/scripts/security/posture-remote.py ~/posture/
```

Reports land at `~/posture/data/security-posture/remote/<UTC>.json` (script auto-detects it's outside the repo and falls back to its own directory). When the user returns home, those JSONs can be scp'd back into `~/containers/data/security-posture/remote/` on fedora-htpc so the local session can cross-reference.

```
You are triaging external-plane security-posture reports produced by
~/posture/posture-remote.py from foreign networks. The script is NOT in
the homelab repo — it is gitignored because the repo is public and
publishing an active attack kit against our own edge is an own-goal.
Read the most recent JSON under ~/posture/data/security-posture/remote/
(or the --out path the user provides). If no report exists yet and the
user is still on a foreign network, run the script first:

    pip3 install requests   # one-time
    python3 ~/posture/posture-remote.py --tag <vantage-label>

--tag should describe the physical vantage (e.g., mbp-oslo-cafe-hotspot,
mbp-airport-osl-ter3, mbp-hotel-berlin-wifi). It lands in X-Probe-Tag
headers on every active probe so the homelab's Loki can correlate.

Your job is to decide: is the perimeter safe? Specifically, what did the
internet actually see that the internal plane cannot?

Process:
1. Read meta first. wan_ip, wan_country, and active_probes matter:
   - If wan_country starts with "Nor", the Region Block negative test is
     uninformative — user is already inside the allowed country.
   - If a corporate/ISP VPN exits in Norway, same problem. Flag this
     ambiguity rather than trusting the finding's severity.
2. Walk findings by category in this order: regionblock, auth,
   crowdsec, ratelimit, scan, tls, http, dns, ct. That ordering mirrors
   the fail-fast chain, so a gap near the top invalidates lower findings
   (e.g., if Region Block leaks, expect other findings to multiply next
   time an abuser shows up).
3. For findings in categories `crowdsec` and `ratelimit`, the raw block
   contains timestamps (ts_ns) for every probe request. Include those
   timestamps in the triage doc so the homelab session can run Loki
   queries:
     {job="traefik-access"} |= "<X-Probe-Tag value>"
4. For `regionblock`, the raw block contains both current_vantage and
   external_probe results. If they disagree (one can reach, the other
   cannot), explain the asymmetry. The UDM Pro's Region Blocking is a
   CyberSecure-internal plane (see journal 2026-04-22-ingress-forensics);
   it cannot be verified from logs, only from probes like this one.
5. Cross-reference the most recent local report under
   data/security-posture/local/ if the repo is available. Divergences are
   the most useful signal — a local "rate-limit middleware present" vs
   remote "no 429 ever" says the limit is not firing.

Context you MUST read before starting:
- scripts/security/README.md (finding severity scale, active-probe
  footprint, unban command if your vantage got banned)
- docs/98-journals/2026-04-22-ingress-forensics-udm-blindspot-private.md
  (F3 follow-up is exactly what this script implements)
- docs/98-journals/2026-04-22-posture-intel-scripts-handoff.md (this file)

Output: a markdown triage at docs/99-reports/posture-triage-remote-<vantage>-
<YYYY-MM-DD>.md. Sections:
  ## Meta (vantage details + caveats about country attribution)
  ## Perimeter verdict (one-paragraph: is the edge holding?)
  ## Active-probe observations (what the attack tests produced)
  ## Passive findings by category
  ## Correlation queries (LogQL snippets the homelab session can run)
  ## Recommended hardening actions

If the user wants to verify active-probe traces actually landed in Loki,
hand them the exact LogQL snippet — do not run it yourself from the Mac.
```

---

## Expected false-positives (already observed on 2026-04-22)

These showed up in the first smoke run and the interpreting session should recognise them without re-deriving:

**Local:**
- `LBIND-000[1-5]` wildcard UDP binds (27500, 5353, 47819/55099) — mDNS and ephemeral SSDP/UPnP. LAN multicast, not a WAN exposure. Firewall blocks them at the edge. Not a gap.
- `LCHAIN-0003` `authelia-portal missing rate-limit` — intentional. Authelia's portal applies its own rate-limit in-app; the Traefik chain uses `hsts-only` on purpose.
- `LCHAIN-0008..0019` 12 dead middlewares — real (issue #156), but cleanup not a security risk.
- `LCONTA-0001` traefik mounts `podman.sock` — intentional (Docker provider). Documented in ADR-016. Keep as explicit data point, not a gap.
- `LCONTA-0002/0003` cadvisor privileged + podman.sock — required for container metrics. Intentional. Document, don't remove.
- `LAUTH-0002` `sshd passwordauthentication=yes` — parser did NOT expand `Match` blocks and did NOT read `sshd_config.d/*.conf` drop-ins that flip it. Verify actual effective state with `sudo sshd -T | grep -i passwordauth` before acting.
- `LJOURN-0002` 16 failed user units — triage individually; most are one-shot services that ran to completion with non-zero rc, not live failures.

**Real** (from the same run, worth keeping on the radar):
- `LCHAIN-0020` router references undefined middleware `nextcloud-caldav` — genuine orphan, route silently broken for that path.
- `LJOURN-0001` SELinux denials in last 24h — worth investigating.

**Remote:**
- `RDNS-0001` split-horizon DNS — only appears when the remote script runs from inside the LAN. On the MacBook's foreign ISP this will not fire.
- `RAUTH-0001` `events.patriark.org returns 200` despite Authelia middleware — known per journal 2026-03-31-authelia-sso-gathio-debugging. Gathio serves public event pages at `/`; Authelia gates creation/admin paths only. The interpreting session should reconcile this against the router config, not treat it as critical.
- `RHTTP-000N` HSTS missing — often because the measured response is a 302 to Authelia and the redirect response doesn't carry HSTS. Reconcile against the *destination* response where possible.

Document these in the triage; don't pretend they're new.

---

## Cadence

| Occasion | Local | Remote |
|---|:---:|:---:|
| Weekly baseline | yes | passive only (if travelling) |
| After `routers.yml` / `middleware.yml` edit | yes | passive next time away |
| After `.network` quadlet change (Internal=true, etc.) | yes | passive |
| After new container deployed | yes | full active next trip |
| After UDM firmware / Region Block config change | yes | full active |
| Post-incident | yes | full active |

Not a daily job. Full active probing burns 60 HTTP requests at the Nextcloud endpoint + a scan of 40 ports — mild, but not something that should run on a cron. Local is cheaper (~45s, no external traffic) and can be cron'd if desired.

---

## Design notes worth writing down

### Severity is intentionally permissive

The scripts err on flagging over silence. A `high` on the local report does not mean "immediately act" — it means "explicitly decide." Known-accepted findings (cadvisor privileged, traefik's podman.sock) are still emitted so they show up as considered data points rather than invisible omissions. Making the interpreting session justify them each run is the point.

This is a deliberate inversion of the `security-audit.sh` philosophy, which uses explicit pass/warn/fail logic tuned to skip known-accepted cases. Both tools coexist because they serve different purposes: `security-audit.sh` is a fast traffic-light check; the posture scripts are forensic gathering for LLM synthesis. If the interpreting session wants the traffic light, it can call `security-audit.sh`.

### The remote script's `--tag` is load-bearing

Every active probe writes `X-Probe-Tag: <tag>` as a request header. Traefik's access log captures it. Without that tag, correlating "did this probe land in Loki" requires matching on fragile substrings (user-agent, timestamp windows). With the tag, it's one LogQL line:

```logql
{job="traefik-access"} |= "<tag>"
```

Teach the interpreting session to ask for tags that describe vantage, not time — `mbp-oslo-cafe-hotspot` is better than `mbp-2026-04-22`.

### Why Prometheus is the Loki probe container

Promtail is distroless — no shell, no wget. Loki itself is distroless. CrowdSec has wget but is on reverse_proxy only. Prometheus has wget and sits on both reverse_proxy and monitoring networks, so it can reach Loki at `http://loki:3100/*` via Podman's aardvark-dns. The `collect_loki_liveness` collector execs through Prometheus for this reason. If Prometheus ever moves image or becomes distroless, swap to the `crowdsec` container (also has wget on reverse_proxy).

---

## Follow-ups

- **Weekly passive-only cron for remote.** When the user is at home, a `--passive` remote run from an external VPS (or a scheduled GitHub Action) would catch regressions in CT logs and external TLS/header state without generating probe traffic. Defer until a foreign-vantage runner is decided.
- **Local script could emit a `history.json`** linking successive runs for trend charts. Not urgent — the JSON files diff cleanly as-is.
- **Third script for post-incident forensics** — a deeper dive that ingests a specific time window and pulls every matching Loki/UDM/CrowdSec record. Out of scope for this work; document the gap.
- **Signed probe bundle.** Currently any client that knows `X-Probe-Tag` could spoof it in Loki. For higher-trust correlation, sign the tag with an HMAC and verify at query time. Probably overkill for single-user homelab.

---

## Scope note

Built in one session, fully tested locally (bind, chain, egress, crowdsec, loki, cert, container, auth, drift, journal, adr) and partially tested remotely (passive only, from inside LAN — DNS split-horizon flagged as expected). Active probes against own perimeter not yet run from a true external vantage; that is the first real deliverable when the user next travels with the MacBook.

The handoff prompts above are the single most important artefact. If they work, a future Claude session can start cold, read a JSON, and produce an actionable hardening plan without this author present.
