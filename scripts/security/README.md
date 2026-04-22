# Security Intel — Posture Scripts

Two scripts that actively probe the homelab's security posture and emit
structured JSON. Designed to be consumed by a fresh Claude Code session that
synthesises a hardening plan from one or more runs.

| Script | Vantage | What it sees | Distribution |
|--------|---------|-------------|------------|
| `posture-local.py`  | inside LAN, on fedora-htpc      | internal plane: bind surface, container egress, Traefik chain, CrowdSec/Loki pipeline liveness, certs, container hardening, SSH config, config drift, journal anomalies, ADR compliance | committed (defensive-only) |
| `posture-remote.py` | outside LAN, from foreign ISP    | external plane: WAN port scan, CT-log enumeration, TLS/headers/auth matrix, DNS audit, live attack probes (CrowdSec bouncer, rate-limit, Region Block negative test) | **gitignored** — scp to MacBook out-of-band |

The two scripts deliberately do not overlap. Local sees what external probes
cannot (container configs, CrowdSec acquisition, journal, SELinux); remote
sees what the LAN cannot (Region Block enforcement, real CrowdSec behaviour
against foreign IPs, what the internet actually negotiates).

## Quickstart

### Local (fedora-htpc)

```bash
python3 scripts/security/posture-local.py                  # full run, writes JSON
python3 scripts/security/posture-local.py --category chain # single category
python3 scripts/security/posture-local.py --pretty         # also dump to stdout
```

Writes: `data/security-posture/local/<UTC>.json` (gitignored).

Dependencies: `python3-pyyaml` (already on Fedora Workstation). No sudo
required — SSH config is parsed from world-readable files, and every other
check uses rootless `podman`.

### Remote (MacBook Air)

**`posture-remote.py` is deliberately NOT committed to this public repo**
(see `.gitignore`). It is a tuned attack tool for this perimeter specifically
and publishing it would hand adversaries a pre-built kit. Distribute it to the
MacBook out-of-band and keep it there.

1. Copy the script to the Mac via scp (run this from the Mac):

   ```bash
   scp fedora-htpc.lokal:~/containers/scripts/security/posture-remote.py \
       ~/posture/posture-remote.py
   ```

   Suggested destination on the Mac: `~/posture/` (outside any cloned repo, so
   a stale sync can't overwrite or publish it). The script auto-detects
   whether it's inside the homelab repo and adapts output path accordingly.

2. `pip3 install requests`
3. Run:

   ```bash
   # Full run including active attack probes (default per user request)
   python3 scripts/security/posture-remote.py --tag mbp-oslo-cafe

   # Passive only (TLS/headers/DNS/CT, no attacks)
   python3 scripts/security/posture-remote.py --passive --tag mbp-airport

   # Write to explicit location (if repo not synced)
   python3 scripts/security/posture-remote.py --out ~/posture-$(date +%s).json
   ```

   Writes: `data/security-posture/remote/<UTC>.json` when in repo, else the
   script directory.

**The `--tag` string is inserted into `X-Probe-Tag` headers on every active
probe.** It shows up in Traefik access logs and lets the interpreting Claude
session correlate probe timestamps back to Loki without guessing. Pick a tag
per vantage (`mbp-oslo-cafe`, `mbp-airport-ter3`, etc.).

### Running remote from inside the LAN

You can, and the TLS/headers/DNS data still lands — but three gotchas:

- **DNS is split-horizon.** `patriark.org` resolves to `192.168.1.70` from
  the LAN; from the internet it's the public WAN IP. The script flags this
  mismatch as `medium` when run from LAN, which is noise in that case.
- **Region Block can't be tested.** You're already inside the allowed country.
- **CrowdSec whitelist absorbs your probes.** `192.168.1.0/24` is
  whitelisted (per `acquis.yaml` header). Attack probes will not trigger
  bouncer responses. That by itself is a useful negative-verification of
  the whitelist — but it means "no bouncer engagement" is expected.

## Output schema

Both scripts write the same JSON shape:

```json
{
  "meta": {
    "schema_version": 1,
    "vantage": "local|remote",
    "host": "fedora-htpc",
    "generated_at": "2026-04-22T22:42:02+00:00",
    "git_head": "...",
    "git_dirty": false,
    "wan_ip": null,              // remote only
    "wan_country": null,         // remote only
    "active_probes": true,       // remote only
    "tag": "mbp-oslo-cafe",      // remote only
    "run_id": "uuid"             // remote only
  },
  "summary": { "critical": 0, "high": 12, "medium": 5, "low": 16, "info": 2 },
  "findings": [
    {
      "id": "LBIND-0001",
      "category": "bind",
      "severity": "high",
      "title": "Listener on wildcard 0.0.0.0:27500/tcp beyond expected WAN ports",
      "evidence": ["{\"proto\": \"tcp\", \"host\": \"0.0.0.0\", \"port\": 27500, \"process\": \"\"}"],
      "adr_refs": ["#141", "#142"],
      "hint": "Rebind to 192.168.1.70:PORT (LAN) or 127.0.0.1 (host-only). Pattern: ADR-free follow-on to PR #170."
    }
  ],
  "raw": { "bind": {...}, "egress": {...}, ... }
}
```

Finding IDs are `<vantage-prefix><category-prefix>-<counter>`:
- `L*` = local, `R*` = remote
- First five letters of the category, uppercased
- Zero-padded 4-digit counter per category

### Severity scale

| Level | Meaning |
|-------|---------|
| `critical` | Probable active security gap. Treat as incident. |
| `high` | Likely gap or clear hardening opportunity. Action within 7d. |
| `medium` | Hardening recommendation; may be known-accepted. |
| `low` | Cleanup / audit-surface reduction. |
| `info` | Signal-only; often documents that something works as designed. |

**The scripts do not interpret — they gather.** Severity is a heuristic. The
consuming Claude session decides what action follows. Known-accepted findings
(e.g., cadvisor's privileged flag, traefik's podman.sock mount for the Docker
provider) will still be flagged — the intent is to make them explicit data
points, not silent omissions.

## How a fresh Claude Code session should consume these reports

Prompt template (paste into a new Claude Code session on the homelab repo):

```
Read the most recent posture reports under data/security-posture/local/ and
data/security-posture/remote/. Correlate findings across both vantages; give
me a prioritised hardening plan. Specifically:

1. For each finding with severity >= medium, decide: real gap, known-accepted,
   or collector false-positive. Cite ADRs, journals, or repo state to justify.
2. Identify findings that appear in one vantage but not the other — those are
   the most forensically valuable because they describe a capability only
   visible from one side.
3. Group remediations by effort (≤15 min, ≤1 hour, requires ADR/approach
   shift). Propose concrete file changes where effort is low.
4. Flag any discrepancy between what the local report claims and what the
   remote report measured. E.g., local says rate-limit is 300rpm; remote
   observed first 429 at request N — is N consistent with 300?
5. Do NOT run commands to collect new data in this first pass. Work from
   what the JSON already contains. After you've triaged, you may ask to re-run
   with a specific --category if you need a fresh datapoint.
```

Tight prompt that binds the session to the data without letting it
re-collect everything from scratch.

## Active probe footprint (remote, by default)

When `--passive` is not set, the remote script sends these requests:

| Probe | Target | Volume | Effect |
|-------|--------|--------|--------|
| TCP port scan | WAN IP | ~40 SYNs | Likely not flagged (no payload) |
| CrowdSec web-shell burst | `nextcloud.patriark.org` | 6 paths over ~3s | Logged as Traefik 40x errors; may trigger CrowdSec scenarios |
| Rate-limit burst | `nextcloud.patriark.org/status.php` | 60 rapid HEADs | Will appear in access.log; may or may not hit 429 |
| Region Block TCP | WAN IP:443 | 1 connect | Logged as drop at UDM (if outside NO) |
| External reflector | `api.hackertarget.com` | 1 call out | Third-party probe; not our infra |

All active probes carry `User-Agent: posture-remote/1.0 (authorized-probe)`
and an `X-Probe-Tag: <tag>` header so correlation in Loki is trivial:

```logql
{job="traefik-access"} |= `posture-remote/1.0`
{job="traefik-access"} |= `X-Probe-Tag`
```

**Plan for getting banned by your own bouncer.** If the burst crosses a
CrowdSec scenario threshold, your vantage IP becomes a decision. Expected
outcomes:

- Passes: burst absorbed by rate-limiter (429s), no CrowdSec decision → normal.
- Fail-open: burst treated as legitimate (all 200/40x, no throttle) → gap.
- Fail-closed: bouncer engages mid-burst (403s) → desired behaviour.

To unban your own vantage IP after a test (only needed if a decision persists):

```bash
# on fedora-htpc
podman exec crowdsec cscli decisions delete --ip <your-wan-ip>
```

## When to run

| Occasion | Local | Remote |
|----------|:-----:|:------:|
| Weekly cron (quiet baseline) | yes | passive only |
| After any `routers.yml` / `middleware.yml` edit | yes | passive |
| After network topology change | yes | yes (when next travelling) |
| When a journal entry proposes a hardening | yes | passive — use as baseline |
| After shipping a security ADR | yes | full active |
| Before and after a UDM firmware update | yes | yes |

## Known limitations (document, don't paper over)

- **Local SSH audit does not expand `Match` blocks.** `sshd -T` would, but
  requires root. The parser is correct for the common case.
- **Container egress probe uses example.com + 1.1.1.1:443.** Inherits the
  assumption those remain reachable. Swap to a self-hosted canary if that
  becomes a constraint.
- **Remote CT enumeration depends on crt.sh uptime.** Failures degrade to a
  `low` finding, not a hard error.
- **Remote region-block interpretation requires trusting ipapi.co's country
  attribution.** Corporate VPNs that exit from Norway make the test always
  return "allowed" regardless of user's physical location. The `wan_country`
  field in meta captures this — the interpreting session should read it.
- **Rate-limit empirical probe is 60 requests.** Below burst thresholds by
  design (post-ADR-022: 1500 burst). A true saturation test would require
  distributed probes; not in scope.

## See also

- `security-audit.sh` — rules-based bash audit (53 checks, same repo). This
  new tool is complementary, not a replacement: it is forensic (gathers more
  context per finding) and structured for LLM consumption, whereas
  `security-audit.sh` is optimised for fast pass/warn/fail reporting.
- `scripts/security/README-ssh-sync.md` — YubiKey SSH key sync toolkit (was
  the old README at this path).
- `docs/98-journals/2026-04-21-crowdsec-acquisition-and-rate-limit-retune.md`
  — why CrowdSec probes are worth doing.
- `docs/98-journals/2026-04-22-ingress-forensics-udm-blindspot-private.md`
  — F3 follow-up; this script is the negative-test the journal calls for.
