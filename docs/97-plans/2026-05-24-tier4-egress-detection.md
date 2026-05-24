# Tier 4 — Egress Detection (the "Egress Observatory")

**Date:** 2026-05-24
**Status:** Implemented (shadow mode; alerts armed after the baseline window)
**Implements:** ADR-030 **P7** (containment/detection). **No new ADR** — implementation of
an existing principle. Supersedes the Tier 4 section of
`2026-05-23-tier3-4-signatures-and-egress-detection-outline.md`.

---

## Context

Tiers 1–3 closed the *integrity* (digest pinning, de-automation) and *authenticity*
(deliberate-path cosign gate) axes. Tier 4 is the **irreducible residual**: a
*validly-signed but malicious* image from a compromised maintainer defeats Tier 1 and
Tier 3. The only remaining controls are containment (already strong: rootless + SELinux +
10 `Internal=true` networks) and **detecting outbound** from the one egress tier —
`reverse_proxy` (10.89.2.0/24, 21 containers). Detection/limiting, **not prevention**, and
strictly **off the boot-critical path**.

## What the premise-testing forensic changed

The outline bet on "DNS egress logging via aardvark / Pi-hole." The survey killed it:

- **aardvark-dns 1.17.1 cannot log queries** (no logging in this build).
- **Pi-hole (192.168.1.69) is on a separate host** (the Pi). Every container's DNS is
  NAT'd to this host (.70) before reaching it → container queries are indistinguishable
  from each other and from the host's own browsing. Attribution and signal both lost.
- **Rootless pasta SNATs all egress to .70** → host conntrack/nftables carry no
  per-container source; rootless UID 1000 cannot read host conntrack or write firewall
  rules; `nsenter -t <pid> -n` is *Operation not permitted* rootless.

**Chosen signal:** each container's own socket table, read **host-side** via
`/proc/<pid>/net/{tcp,tcp6}` (pid from `podman inspect`, cgroup-verified). It is
attributable (per container), rootless-readable, **scratch-safe** (no `exec`, no
in-container shell — works for traefik/crowdsec), and **DNS-method-agnostic** — it sees the
actual connection, so it catches DoH and hardcoded-IP egress that DNS logging would miss.

**Second forensic (the architect's, then confirmed live):** point-in-time sampling is DOA —
even continuous egress (proton-bridge SMTP/IMAP) is invisible at most instants. Hence a
**two-tier** design: a frequent cheap collector that only accumulates, and a less-frequent
classifier that does the PTR/classify work over the accumulated union. Socket states kept:
ESTABLISHED + SYN_SENT + TIME_WAIT + CLOSE_WAIT.

**Third forensic (from the live data):** **qBittorrent held ~128 of ~130 public
connections** — a BitTorrent peer swarm of random IPs/ports. Per-destination allow-listing
is meaningless for P2P; it is tracked **count-only** (`peer_swarm_services`). The remaining
classifiable set is tiny and stable — the right shape for a frozen-prefix allow-list.

## Architecture

```
egress-collector.service (daemon ~30s)  →  data/egress/accumulator.tsv  (flock)
   per reverse_proxy container: PID (cgroup-verified, cached) → /proc/<pid>/net/{tcp,tcp6}
   → decode (ipaddress: LE hex, IPv6 words, v4-mapped) → keep is_global → append
   → data/backup-metrics/egress-collector.prom (last_run, services_sampled)

egress-detect.timer (~10m) → detect-egress-anomaly.sh [--shadow]
   flock: consume+truncate accumulator → upsert data/egress/destinations.tsv (durable,
   first/last/count/class, reclassified each run, pruned >30d)
   classify by PREFIX MEMBERSHIP vs config/supply-chain/egress-baseline.yaml (no runtime
   DNS/ASN/whois). peer-swarm svcs → connection_count only. PTR (dig @Pi-hole) annotates
   new live anomalies only.
   → data/backup-metrics/egress.prom (unexpected_destination_count, destination_count,
     connection_count, detector_mode, last_run) + data/egress/anomalies.jsonl (Loki trail)
   → Prometheus → config/prometheus/alerts/egress-alerts.yml → Alertmanager → Discord
```

Decisions baked in (operator, 2026-05-24): **frozen-prefix** classification (zero runtime
dependency, no external account); **shadow-first** alerting (detector runs observe-only
until the allow-list is seeded; alert file ships `.disabled`).

## Components

| File | Role |
|---|---|
| `scripts/egress-collector.sh` | daemon collector (`--once` for tests) |
| `scripts/detect-egress-anomaly.sh` | classifier (`--shadow`, `--strict`) |
| `scripts/egress-baseline.sh` | post-window survey → proposed allow-list + zero-egress candidates |
| `scripts/generate-egress-index.sh` | `docs/AUTO-EGRESS-BASELINE-INDEX.md` (wired as auto-doc Phase 6) |
| `config/supply-chain/egress-baseline.yaml` | frozen-prefix allow-list + `peer_swarm_services` |
| `config/supply-chain/known-egress.md` | method, scope, residual/evasion |
| `config/prometheus/alerts/egress-alerts.yml.disabled` | alerts (armed after window) |
| `systemd/egress-collector.service`, `egress-detect.{service,timer}` | scheduling |

## Operating procedure

1. **Now (done):** collector + detector(`--shadow`) deployed → baseline window running
   (≥7 days, 14 ideal). Metrics flow; nothing alerts.
2. **After the window:** `scripts/egress-baseline.sh --write` → review
   `egress-baseline.proposed.yaml`, merge real prefixes into `egress-baseline.yaml`
   (promote shared infra to the `infrastructure:` block), commit.
3. **Arm:** set `EGRESS_MODE=` empty in `egress-detect.service` (or `systemctl --user edit`),
   `daemon-reload`; `podman exec prometheus promtool check rules` then rename
   `egress-alerts.yml.disabled` → `.yml`.
4. **Re-baseline** whenever a flagged anomaly turns out legitimate (provider added ranges).

## Verification performed (2026-05-24)
- Decoder correctness (synthetic hex: internal filtered, public kept, IPv6 + v4-mapped).
- Collector via systemd samples all 21 egress containers; PID cache + cgroup verify.
- **Tripwire fired on real data:** HA's AWS connections flagged with correct PTR
  (`ec2-…eu-central-1.compute.amazonaws.com`); adding a CIDR reclassified one IP →expected
  while a different AWS range stayed unexpected (proves reclassification + why the window
  must capture all ranges).
- Shadow vs live behavior correct (mode metric, no JSONL/unexpected_count in shadow).
- End-to-end into Prometheus: `node_textfile_scrape_error=0`, all `egress_*` series live.
- promtool validates the 5 alert rules.

## Bundled fix — resurrected a triply-dead Tier 3 metric
Verifying the metric reached Prometheus (not just "the file exists") exposed that
`supply-chain-signatures.prom` (Tier 3, P6) was **unreadable by node_exporter** for three
compounding reasons, so the `SupplyChainSignatureFailed`/`Stale` alerts had never had data:
1. **SELinux type** — `write_metric`'s `mktemp` created the temp in `/tmp`; `mv` preserved
   `user_tmp_t`, which node_exporter (SELinux) cannot read. Fix: `mktemp -p "$METRIC_DIR"`
   (in-dir → inherits `container_file_t`).
2. **DAC mode** — `mktemp` makes `0600`; node_exporter runs as `nobody` (mapped UID) and
   needs other-read. Fix: `chmod 0644`.
3. **Format** — `write_metric` kept the old file's `# HELP`/`# TYPE` lines and re-appended
   headers each run → "second HELP line" parse error. Fix: preserve only data lines, emit
   one header block.

The same `mktemp`+`chmod` fix is applied to the new Tier 4 writers. Re-ran the Tier 3
verifier: HA re-verified via cosign and the metric now parses (`supply_chain_signature_verify=1`
live in Prometheus). This is the repo's "an alert isn't wired until you've seen it fire on
real data" lesson, recurring.

## Residual / accepted (ADR-030 P7)
- **Tripwire, not a guarantee** — a beacon shorter than the collector interval leaving no
  TIME_WAIT can pass between samples.
- **Prefix drift** — providers adding ranges false-positive until re-baselined.
- **No prevention** — rootless + pasta offers no clean per-container egress firewall.
- **Peer-swarm blind spot** — a compromised qBittorrent could exfiltrate amid its swarm.

## Adjacent finding (NOT Tier 4)
qBittorrent has **no VPN** in its quadlet — torrent traffic egresses on the home WAN IP.
Flagged for a separate, deliberate privacy decision. The zero-egress candidate list
(`AUTO-EGRESS-BASELINE-INDEX.md`) is **report only** for blast-radius reduction — never an
automated `Internal=true` change (Feb-2026 21-container outage precedent).
