# Egress Observatory — baseline & scope (ADR-030 P7, Tier 4)

**Method:** host-side read of each `reverse_proxy`-tier container's socket table via
`/proc/<pid>/net/{tcp,tcp6}` (pid from `podman inspect`, cgroup-verified), decoded and
filtered to globally-routable foreign endpoints. Two-tier: `scripts/egress-collector.sh`
samples every ~30s into `data/egress/accumulator.tsv`; `scripts/detect-egress-anomaly.sh`
classifies the accumulated union against `egress-baseline.yaml` every ~10–15 min.

**Why this signal (and not the obvious ones).** The Tier 4 premise survey (2026-05-24)
killed the outline's "DNS egress logging" plan:

- **aardvark-dns 1.17.1 cannot log queries** — no logging in this build.
- **Pi-hole (192.168.1.69) is on a separate host** (the Pi); every container's DNS is
  NAT'd to this host (.70) before reaching it, so container queries are indistinguishable
  from each other and from the host's own browsing — attribution and signal both lost.
- **Rootless pasta SNATs all egress to the host** → host conntrack/nftables carry no
  per-container source; rootless UID 1000 cannot read host conntrack or write firewall
  rules; `nsenter -t <pid> -n` is *Operation not permitted* rootless.

The container's own `/proc/<pid>/net/tcp{,6}`, read host-side, is the one signal that is
**attributable** (per container), **rootless-readable**, **scratch-safe** (no `exec`, no
in-container shell), and **DNS-method-agnostic** — it sees the actual connection, so it
catches DoH and hardcoded-IP egress that DNS logging would miss.

## Scope decisions

### Peer-swarm services → count-only (no per-destination allow-list)
Baseline 2026-05-24: **qBittorrent held ~128 of ~130 public connections** — a BitTorrent
peer swarm of random residential/VPS IPs on random ports. Per-destination classification
is meaningless for P2P and would bury every real signal in noise. qBittorrent (and any
future P2P service) is in `peer_swarm_services`: the detector tracks only its **connection
count** (a volume-anomaly signal), not individual peers. See `egress-baseline.yaml`.

### The classifiable set is small and stable
Excluding the swarm, the egress tier's legitimate public destinations are a handful of
known providers (e.g. HA→AWS MQTT `18.184.210.208:8883`, proton-bridge→Proton
`185.70.42.41:443`) — exactly the shape a frozen-prefix allow-list fits.

## Residual / evasion (this is detection, not prevention — ADR-030 P7)
- **Tripwire, not a guarantee.** A beacon shorter than the collector interval that leaves
  no `TIME_WAIT` can pass between samples. Widened socket states (ESTAB + SYN_SENT +
  TIME_WAIT + CLOSE_WAIT) narrow but do not close the gap.
- **Prefix drift.** A provider adding ranges outside the baselined CIDRs false-positives
  until re-baselined — the accepted cost of the zero-runtime-dependency choice. A flagged
  anomaly is the prompt to re-baseline (`scripts/egress-baseline.sh`).
- **No prevention.** Rootless + pasta offers no clean per-container egress firewall; Tier 4
  detects and surfaces, it does not block.
- **Peer-swarm blind spot.** A compromised qBittorrent image could exfiltrate amid its
  own swarm and evade per-destination detection; only its connection-count volume is watched.

## Adjacent finding (NOT Tier 4 — flagged for the owner)
qBittorrent has **no VPN** in its quadlet — torrent traffic egresses directly on the home
WAN IP. Separate from supply-chain detection; noted for a deliberate privacy/security
decision (VPN sidecar or accepted exposure).

## Zero-egress candidates (blast-radius reduction — REPORT ONLY)
Services that make **zero** public connections across the full baseline window are
candidates to move to an `Internal=true` network (shrinking the egress surface Tier 4 must
watch). This list is generated into `docs/AUTO-EGRESS-BASELINE-INDEX.md` and is **report
only** — never an automated network change (the Feb-2026 21-container outage governs:
network moves are separate, manually-reviewed, per-service).

---

*Point-in-time snapshot. Re-run `scripts/egress-baseline.sh` after the window or when a
flagged anomaly turns out to be a legitimate new destination, then human-review the
proposed `egress-baseline.yaml` diff before arming.*
