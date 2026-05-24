#!/bin/bash
# generate-egress-index.sh — ADR-030 P7 (Tier 4) egress observatory audit view.
#
# Renders the durable observatory state (data/egress/destinations.tsv), the allow-list
# (config/supply-chain/egress-baseline.yaml), and the live metrics into one reviewable
# document: docs/AUTO-EGRESS-BASELINE-INDEX.md. Offline + fast (reads local files only —
# no whois/dig), so it fits the daily ~2s auto-doc run. Includes the zero-egress
# blast-radius candidates (REPORT ONLY — never an automated network change).
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/containers}"
QUADLET_DIR="${QUADLET_DIR:-$REPO_ROOT/quadlets}"
EGRESS_DIR="${EGRESS_DIR:-$REPO_ROOT/data/egress}"
DEST_FILE="$EGRESS_DIR/destinations.tsv"
BASELINE_YAML="${BASELINE_YAML:-$REPO_ROOT/config/supply-chain/egress-baseline.yaml}"
METRIC_DIR="${METRIC_DIR:-$REPO_ROOT/data/backup-metrics}"
OUTPUT_FILE="${OUTPUT_FILE:-$REPO_ROOT/docs/AUTO-EGRESS-BASELINE-INDEX.md}"

is_egress() { grep -qE '^Network=systemd-reverse_proxy' "$1"; }
EGRESS_LIST="$(for f in "$QUADLET_DIR"/*.container; do [ -e "$f" ] && is_egress "$f" && basename "$f" .container; done | sort | paste -sd, -)"

python3 - "$DEST_FILE" "$BASELINE_YAML" "$METRIC_DIR" "$EGRESS_LIST" <<'PY' > "$OUTPUT_FILE"
import sys, os, time, re
destp, yamlp, metricdir, egress_csv = sys.argv[1:5]
egress_all = [s for s in egress_csv.split(",") if s]
now = int(time.time())

try:
    import yaml
    cfg = yaml.safe_load(open(yamlp)) or {}
except Exception:
    cfg = {}
peer_swarm = set(cfg.get("peer_swarm_services") or [])

def read_prom(path):
    vals = {}
    if not os.path.exists(path): return vals
    for line in open(path):
        line = line.strip()
        if not line or line.startswith("#"): continue
        m = re.match(r"^(\w+)(\{[^}]*\})?\s+([0-9.eE+-]+)$", line)
        if not m: continue
        name, labels, val = m.group(1), m.group(2) or "", m.group(3)
        svc = ""
        ms = re.search(r'service="([^"]+)"', labels)
        if ms: svc = ms.group(1)
        vals[(name, svc)] = float(val)
    return vals

prom = read_prom(os.path.join(metricdir, "egress.prom"))
prom.update(read_prom(os.path.join(metricdir, "egress-collector.prom")))

def g(name, svc=""):
    return prom.get((name, svc))

# destinations.tsv → per service rows
svc_rows = {}
seen = set()
if os.path.exists(destp):
    for line in open(destp):
        f = line.rstrip("\n").split("\t")
        if len(f) < 7: continue
        svc, ip, port, first, last, count, cls = f[:7]
        seen.add(svc)
        svc_rows.setdefault(svc, []).append((ip, port, int(first), int(last), int(count), cls))

def ago(ts):
    if ts is None: return "—"
    d = now - int(ts)
    if d < 120: return f"{d}s ago"
    if d < 7200: return f"{d//60}m ago"
    if d < 172800: return f"{d//3600}h ago"
    return f"{d//86400}d ago"

mode = g("egress_detector_mode")
mode_s = "live (alerting)" if mode == 1 else ("shadow (observe-only)" if mode == 0 else "not yet run")
P = print
P("# Egress Observatory — Baseline Index (Auto-Generated)")
P("")
P(f"**Generated:** {time.strftime('%Y-%m-%d %H:%M:%S UTC', time.gmtime())}")
P(f"**Implements:** ADR-030 P7 (Tier 4) — egress detection. **Mode:** {mode_s}")
P("")
P("Host-side `/proc/<pid>/net/{tcp,tcp6}` sampling of reverse_proxy-tier containers "
  "(attributable, rootless, scratch-safe, DNS-method-agnostic). Detection, not prevention. "
  "See `config/supply-chain/known-egress.md` for method and residual/evasion scope.")
P("")
P("## Pipeline health")
P("")
P("| Component | Last run | Detail |")
P("|---|---|---|")
P(f"| Collector (`egress-collector.service`) | {ago(g('egress_collector_last_run_timestamp'))} | "
  f"{int(g('egress_collector_services_sampled') or 0)} services sampled |")
P(f"| Classifier (`egress-detect.timer`) | {ago(g('egress_detector_last_run_timestamp'))} | "
  f"mode={mode_s}; last window {int(g('egress_detector_window_destinations') or 0)} dest(s) |")
P("")

# Summary table
P("## Per-service egress")
P("")
P("| Service | Mode | Public dests | Unexpected | Peers (swarm) |")
P("|---|---|---|---|---|")
for svc in sorted(egress_all):
    if svc in peer_swarm:
        peers = g("egress_connection_count", svc)
        P(f"| {svc} | peer-swarm (count-only) | — | — | {int(peers) if peers is not None else '—'} |")
    else:
        rows = svc_rows.get(svc, [])
        ndest = len(rows)
        unexp = g("egress_unexpected_destination_count", svc)
        unexp_s = ("✅ 0" if unexp == 0 else f"⚠️ {int(unexp)}") if unexp is not None else (
            f"{sum(1 for r in rows if r[5]=='unexpected')} (unarmed)" if rows else "—")
        P(f"| {svc} | classify | {ndest if ndest else '—'} | {unexp_s} | — |")
P("")

# Zero-egress candidates (report only)
zero = sorted(set(egress_all) - seen - peer_swarm)
P("## Zero-egress candidates — blast-radius reduction (REPORT ONLY)")
P("")
P("Egress-tier services with **no observed public destination** over the window. Each is a "
  "candidate to move to an `Internal=true` network (shrinking the surface Tier 4 watches). "
  "**Not an automated change** — manual, per-service review (Feb-2026 21-container outage precedent). "
  "A short window will list services that simply hadn't egressed yet (e.g. proton-bridge in "
  "`TIME_WAIT`); confirm against a full ≥7-day baseline before acting.")
P("")
P(f"> {', '.join(zero) if zero else '(none — every egress service made at least one public connection)'}")
P("")

# Detailed observed destinations
P("## Observed destinations (durable state)")
P("")
classify_seen = [s for s in sorted(svc_rows) if s not in peer_swarm]
if not classify_seen:
    P("*No classify-service public destinations recorded yet.*")
for svc in classify_seen:
    P(f"### {svc}")
    P("")
    P("| Destination | Port | Class | First seen | Last seen | Obs |")
    P("|---|---|---|---|---|---|")
    for ip, port, first, last, count, cls in sorted(svc_rows[svc], key=lambda r: (r[5] != "unexpected", r[0])):
        mark = "⚠️ unexpected" if cls == "unexpected" else "✅ expected"
        P(f"| `{ip}` | {port} | {mark} | {ago(first)} | {ago(last)} | {count} |")
    P("")

P("---")
P("")
P("*Auto-generated by `scripts/generate-egress-index.sh`. Allow-list: "
  "`config/supply-chain/egress-baseline.yaml` (frozen prefixes; re-seed with "
  "`scripts/egress-baseline.sh`). Anomaly trail: `data/egress/anomalies.jsonl`. "
  "Alerts armed by renaming `config/prometheus/alerts/egress-alerts.yml.disabled` → `.yml` "
  "after the baseline window (shadow-first).*")
PY

echo "✓ Egress baseline index generated: $OUTPUT_FILE"
