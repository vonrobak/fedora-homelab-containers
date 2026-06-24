#!/bin/bash
# detect-egress-anomaly.sh — ADR-030 P7 (Tier 4) egress observatory: the classifier.
#
# Consumes the union of egress observations accumulated by egress-collector.sh, classifies
# each PUBLIC destination against the frozen-prefix allow-list (config/supply-chain/
# egress-baseline.yaml), maintains the durable observatory state (data/egress/
# destinations.tsv), and emits the detection signal into the existing rails:
#   - data/backup-metrics/egress.prom  (node_exporter textfile → Prometheus → Alertmanager → Discord)
#   - data/egress/anomalies.jsonl      (forensic trail; optional Promtail → Loki)
#
# Classification is pure prefix membership — NO DNS/ASN/whois on the hot path (operator
# chose frozen prefixes; PTR is used only to ANNOTATE a new anomaly, never to gate).
# Peer-swarm services (qbittorrent) are tracked by connection COUNT, not per-destination.
#
# Modes:
#   (default, live)  classify, emit egress_unexpected_destination_count, write JSONL anomalies
#   --shadow         observe only: build destinations.tsv + benign metrics, NO anomaly metric
#                    or JSONL (used during the baseline window before the allow-list is seeded)
#   --strict         exit 1 if any unexpected destination is active (for interactive/CI use;
#                    the timer service does NOT use this — findings travel via the metric)
#
# Exit: 0 ran successfully (findings are in the metric/JSONL, not the exit code unless
#       --strict), 2 operational error.
set -uo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/containers}"
EGRESS_DIR="${EGRESS_DIR:-$REPO_ROOT/data/egress}"
ACC_FILE="$EGRESS_DIR/accumulator.tsv"
LOCK_FILE="$EGRESS_DIR/.accumulator.lock"
DEST_FILE="$EGRESS_DIR/destinations.tsv"
JSONL_FILE="$EGRESS_DIR/anomalies.jsonl"
BASELINE_YAML="${BASELINE_YAML:-$REPO_ROOT/config/supply-chain/egress-baseline.yaml}"
METRIC_DIR="${METRIC_DIR:-$REPO_ROOT/data/backup-metrics}"
METRIC_FILE="$METRIC_DIR/egress.prom"
RESOLVER="${EGRESS_RESOLVER:-192.168.1.69}"   # Pi-hole, PTR annotation only

shadow=0; strict=0
while [ $# -gt 0 ]; do
    case "$1" in
        "")       shift ;;                       # tolerate empty arg from systemd ${EGRESS_MODE} expansion
        --shadow) shadow=1; shift ;;
        --strict) strict=1; shift ;;
        *) echo "detect-egress-anomaly: unknown arg: $1" >&2; exit 2 ;;
    esac
done

[ -f "$BASELINE_YAML" ] || { echo "detect-egress-anomaly: missing $BASELINE_YAML" >&2; exit 2; }
mkdir -p "$EGRESS_DIR" "$METRIC_DIR" || { echo "detect-egress-anomaly: cannot create dirs" >&2; exit 2; }

# Atomically claim the accumulated window (collector recreates the file on next append).
SNAP="$(mktemp)" || exit 2
trap 'rm -f "$SNAP"' EXIT
(
    flock 9
    [ -s "$ACC_FILE" ] && mv "$ACC_FILE" "$SNAP"
) 9>"$LOCK_FILE"

python3 - "$SNAP" "$BASELINE_YAML" "$DEST_FILE" "$JSONL_FILE" "$METRIC_FILE" "$shadow" "$strict" "$RESOLVER" <<'PY'
import sys, os, time, json, tempfile, ipaddress, subprocess
snap, yamlp, destp, jsonlp, metricp, shadow_s, strict_s, resolver = sys.argv[1:9]
shadow = shadow_s == "1"; strict = strict_s == "1"
now = int(time.time())
RECENCY   = int(os.environ.get("EGRESS_RECENCY",   str(24*3600)))    # "recent" window (seen in last 24h)
RETENTION = int(os.environ.get("EGRESS_RETENTION", str(30*24*3600))) # prune destinations.tsv beyond this
# An unexpected dest counts as "persistent" (sustained, not a one-off) once its observation
# span first→last reaches PERSIST_MIN AND it is still recent. A one-off has first==last (span 0)
# and never qualifies — this is what severs the critical alert from mere 24h state-retention.
PERSIST_MIN = int(os.environ.get("EGRESS_PERSIST_MIN", str(3600)))   # span (first→last) marking recurrence

try:
    import yaml
    cfg = yaml.safe_load(open(yamlp)) or {}
except Exception as e:
    sys.stderr.write(f"detect-egress-anomaly: cannot parse {yamlp}: {e}\n"); sys.exit(2)

peer_swarm = set(cfg.get("peer_swarm_services") or [])

def nets_from(entries):
    out = []
    for e in (entries or []):
        for c in (e.get("cidrs") or []):
            try: out.append(ipaddress.ip_network(str(c), strict=False))
            except ValueError: pass
    return out

infra = nets_from(cfg.get("infrastructure"))
svc_nets = {s: nets_from(v) for s, v in (cfg.get("services") or {}).items()}

def classify(svc, ip):
    try: a = ipaddress.ip_address(ip)
    except ValueError: return "unexpected"
    for n in infra + svc_nets.get(svc, []):
        if a.version == n.version and a in n:
            return "expected"
    return "unexpected"

# --- durable state: (svc,ip,port) -> [first, last, count] -------------------------
state = {}
if os.path.exists(destp):
    for line in open(destp):
        f = line.rstrip("\n").split("\t")
        if len(f) >= 6:
            try: state[(f[0], f[1], f[2])] = [int(f[3]), int(f[4]), int(f[5])]
            except ValueError: pass

# --- fold in this window ----------------------------------------------------------
swarm = {}        # svc -> set of (ip,port)
window_dest = 0
fresh_keys = set()  # keys whose last_seen == now (seen this run)
if os.path.exists(snap):
    win = {}
    for line in open(snap):
        f = line.rstrip("\n").split("\t")
        if len(f) < 5: continue
        svc, ip, port = f[1], f[2], f[3]
        if svc in peer_swarm:
            swarm.setdefault(svc, set()).add((ip, port)); continue
        win[(svc, ip, port)] = win.get((svc, ip, port), 0) + 1
    for key, occ in win.items():
        window_dest += 1
        if key in state:
            state[key][1] = now; state[key][2] += occ
        else:
            state[key] = [now, now, occ]
        fresh_keys.add(key)

# --- reclassify all, prune, persist ----------------------------------------------
rows = []
for (svc, ip, port), (first, last, count) in state.items():
    if now - last > RETENTION: continue
    rows.append((svc, ip, port, first, last, count, classify(svc, ip)))

def atomic_write(path, text):
    d = os.path.dirname(path) or "."
    fd, tmp = tempfile.mkstemp(dir=d)
    try:
        with os.fdopen(fd, "w") as fh: fh.write(text)
        os.chmod(tmp, 0o644)   # node_exporter runs as 'nobody' — needs other-read
        os.replace(tmp, path)
    except Exception:
        try: os.unlink(tmp)
        except OSError: pass

atomic_write(destp, "".join(
    f"{s}\t{i}\t{p}\t{fi}\t{la}\t{c}\t{cl}\n" for (s, i, p, fi, la, c, cl) in rows))

# --- PTR annotation (only for new live anomalies; never a gating key) -------------
def ptr(ip):
    try:
        out = subprocess.run(["dig", "+short", "-x", ip, f"@{resolver}"],
                             capture_output=True, text=True, timeout=3)
        r = out.stdout.strip().splitlines()
        return r[0].rstrip(".") if r else ""
    except Exception:
        return ""

# --- JSONL anomalies (live only): unexpected rows seen THIS run -------------------
anomaly_events = 0
if not shadow:
    lines = []
    for (svc, ip, port, first, last, count, cls) in rows:
        if cls == "unexpected" and last == now:
            lines.append(json.dumps({
                "ts": now, "service": svc, "ip": ip, "port": int(port),
                "ptr": ptr(ip), "count": count, "first_seen": first,
                "kind": "egress-unexpected-destination",
            }))
            anomaly_events += 1
    if lines:
        with open(jsonlp, "a") as fh:
            fh.write("\n".join(lines) + "\n")

# --- metrics (whole-file rewrite; detector is the sole writer of egress.prom) -----
classify_svcs = set(s for (s, *_rest) in rows)
unexpected_recent = {}      # unexpected dest seen in last RECENCY (24h) — the sticky "recently seen" signal
unexpected_active = {}      # unexpected dest seen in the window THIS run just folded (last == now) — "right now"
unexpected_persistent = {}  # unexpected dest recurring across >=PERSIST_MIN AND still recent — "sustained"
total_recent = {}
for (svc, ip, port, first, last, count, cls) in rows:
    if now - last <= RECENCY:
        total_recent[svc] = total_recent.get(svc, 0) + 1
        if cls == "unexpected":
            unexpected_recent[svc] = unexpected_recent.get(svc, 0) + 1
            if last == now:
                unexpected_active[svc] = unexpected_active.get(svc, 0) + 1
            if (last - first) >= PERSIST_MIN:
                unexpected_persistent[svc] = unexpected_persistent.get(svc, 0) + 1

m = []
m.append("# HELP egress_detector_last_run_timestamp ADR-030 P7 (Tier 4) egress classifier last run (unix seconds).")
m.append("# TYPE egress_detector_last_run_timestamp gauge")
m.append(f"egress_detector_last_run_timestamp {now}")
m.append("# HELP egress_detector_mode 1=live (alerting), 0=shadow (observe-only).")
m.append("# TYPE egress_detector_mode gauge")
m.append(f"egress_detector_mode {0 if shadow else 1}")
m.append("# HELP egress_detector_window_destinations Distinct classify-service public dests in the last window.")
m.append("# TYPE egress_detector_window_destinations gauge")
m.append(f"egress_detector_window_destinations {window_dest}")
m.append("# HELP egress_destination_count Distinct recent public destinations per egress service (classify mode).")
m.append("# TYPE egress_destination_count gauge")
for svc in sorted(classify_svcs):
    m.append(f'egress_destination_count{{service="{svc}"}} {total_recent.get(svc, 0)}')
if not shadow:
    m.append("# HELP egress_unexpected_destination_count Recent (<=24h) public dests NOT in the allow-list, per service (ADR-030 P7). >0 = new/recent destination, investigate (may be a one-off).")
    m.append("# TYPE egress_unexpected_destination_count gauge")
    for svc in sorted(classify_svcs):
        m.append(f'egress_unexpected_destination_count{{service="{svc}"}} {unexpected_recent.get(svc, 0)}')
    m.append("# HELP egress_unexpected_destination_active Unexpected public dests seen in the LAST detector window (right-now signal), per service. Drops to 0 the window after the dest stops being observed — a one-off shows here for one window only.")
    m.append("# TYPE egress_unexpected_destination_active gauge")
    for svc in sorted(classify_svcs):
        m.append(f'egress_unexpected_destination_active{{service="{svc}"}} {unexpected_active.get(svc, 0)}')
    m.append("# HELP egress_unexpected_destination_persistent Unexpected public dests recurring across >=EGRESS_PERSIST_MIN seconds AND still recent (ADR-030 P7). >0 = SUSTAINED egress (beaconing/exfil shape), NOT a one-off — this is the signal the critical alert keys on.")
    m.append("# TYPE egress_unexpected_destination_persistent gauge")
    for svc in sorted(classify_svcs):
        m.append(f'egress_unexpected_destination_persistent{{service="{svc}"}} {unexpected_persistent.get(svc, 0)}')
if swarm:
    m.append("# HELP egress_connection_count Distinct concurrent public peers for peer-swarm services (volume signal).")
    m.append("# TYPE egress_connection_count gauge")
    for svc in sorted(swarm):
        m.append(f'egress_connection_count{{service="{svc}"}} {len(swarm[svc])}')
atomic_write(metricp, "\n".join(m) + "\n")

total_unexpected = sum(unexpected_recent.values())
total_persistent = sum(unexpected_persistent.values())
mode = "shadow" if shadow else "live"
sys.stderr.write(
    f"detect-egress-anomaly [{mode}]: window_dest={window_dest} "
    f"tracked={len(rows)} unexpected_recent={total_unexpected} persistent={total_persistent} "
    f"new_anomaly_events={anomaly_events} swarm={ {s: len(v) for s, v in swarm.items()} }\n")

sys.exit(1 if (strict and not shadow and total_unexpected > 0) else 0)
PY
rc=$?
exit $rc
