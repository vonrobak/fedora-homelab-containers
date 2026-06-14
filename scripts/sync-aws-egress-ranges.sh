#!/bin/bash
# sync-aws-egress-ranges.sh — ADR-039: refresh crowdsec's AWS egress allow-list from
# AWS's PUBLISHED ip-ranges.json instead of chasing per-rotation re-baselines.
#
# WHY (ADR-039): api.crowdsec.net is AWS-API-Gateway-fronted in eu-west-1 and answers
# from a large ROTATING pool. Per-IP / per-/18 allow-listing is a treadmill (#275, #296,
# #299). The tightest HONEST description of "where crowdsec legitimately talks to AWS" is
# AWS's own published eu-west-1 EC2 prefix list. This script regenerates exactly that
# block in config/supply-chain/egress-baseline.yaml, between the marker lines:
#       # >>> BEGIN generated: crowdsec AWS eu-west-1 EC2 (sync-aws-egress-ranges.sh)
#       ...
#       # <<< END generated
# Static entries OUTSIDE the markers (CloudFront hub-cdn, Cloudflare hub-data/version)
# are hand-maintained and never touched — they have not hit the ADR-039 >=3-rotation gate.
#
# DELIBERATE + OFFLINE (ADR-030 P7 / ADR-039 D2): this is NOT on the classifier hot path.
# Run it by hand during the monthly update loop (ADR-036 cadence); review the diff; commit.
# The detector (detect-egress-anomaly.sh) stays a pure prefix-membership test with no
# network calls.
#
# Usage:
#   scripts/sync-aws-egress-ranges.sh            # fetch + print proposed block, diff, coverage; NO write
#   scripts/sync-aws-egress-ranges.sh --write    # splice the regenerated block into egress-baseline.yaml
#
# Exit: 0 ok (0 also when --write made no change), 2 operational error (offline / no markers /
#       observed crowdsec eu-west-1 IP would lose coverage).
set -uo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/containers}"
BASELINE_YAML="${BASELINE_YAML:-$REPO_ROOT/config/supply-chain/egress-baseline.yaml}"
DEST_FILE="${DEST_FILE:-$REPO_ROOT/data/egress/destinations.tsv}"
IP_RANGES_URL="${IP_RANGES_URL:-https://ip-ranges.amazonaws.com/ip-ranges.json}"

# --- The crowdsec carve-out parameters (ADR-039 D3: crowdsec-only, gated by churn) ------
SERVICE_KEY="${SERVICE_KEY:-crowdsec}"   # quadlet basename whose AWS block we regenerate
AWS_REGION="${AWS_REGION:-eu-west-1}"    # CAPI / community-blocklist region
AWS_SERVICE="${AWS_SERVICE:-EC2}"        # tightest sufficient service tag (all observed CAPI is EC2)

write=0
[ "${1:-}" = "--write" ] && write=1

[ -f "$BASELINE_YAML" ] || { echo "sync-aws-egress-ranges: missing $BASELINE_YAML" >&2; exit 2; }

RANGES_JSON="$(mktemp)" || exit 2
trap 'rm -f "$RANGES_JSON"' EXIT
if ! curl -fsS --max-time 25 "$IP_RANGES_URL" -o "$RANGES_JSON"; then
    echo "sync-aws-egress-ranges: could not fetch $IP_RANGES_URL (offline?). No change made." >&2
    exit 2
fi

python3 - "$RANGES_JSON" "$BASELINE_YAML" "$DEST_FILE" "$write" \
          "$SERVICE_KEY" "$AWS_REGION" "$AWS_SERVICE" <<'PY'
import sys, json, ipaddress, re

ranges_path, baseline_path, dest_path, write, svc_key, region, aws_svc = sys.argv[1:8]
write = (write == "1")

BEGIN = f"    # >>> BEGIN generated: {svc_key} AWS {region} {aws_svc} (sync-aws-egress-ranges.sh)"
END   =  "    # <<< END generated"

data = json.load(open(ranges_path))
create_date = data.get("createDate", "unknown")
sync_token  = data.get("syncToken", "unknown")

# 1. Collect + collapse the published region/service prefixes (lossless minimisation).
raw = [ipaddress.ip_network(p["ip_prefix"])
       for p in data["prefixes"]
       if p.get("region") == region and p.get("service") == aws_svc]
collapsed = sorted(ipaddress.collapse_addresses(raw), key=lambda n: (int(n.network_address), n.prefixlen))
cidrs = [str(n) for n in collapsed]

# 2. Coverage self-check against the durable observatory state: every observed
#    destination for this service that lands in this region/service MUST be covered.
def regsvc_match(ip):
    hits = [(p.get("region"), p.get("service")) for p in data["prefixes"]
            if ip in ipaddress.ip_network(p["ip_prefix"])]
    return hits

observed = []
try:
    for line in open(dest_path):
        f = line.split("\t")
        if len(f) >= 2 and f[0] == svc_key:
            observed.append(f[1])
except FileNotFoundError:
    pass

covered_nets = [ipaddress.ip_network(c) for c in cidrs]
def covered(ipstr):
    ip = ipaddress.ip_address(ipstr)
    return any(ip in n for n in covered_nets)

in_scope_uncovered = []   # observed, IS region/aws_svc per AWS, but NOT in generated set -> bug/regression
out_of_scope = []         # observed, not region/aws_svc (expected: CloudFront / Cloudflare / other)
for ipstr in sorted(set(observed)):
    try: ip = ipaddress.ip_address(ipstr)
    except ValueError: continue
    pairs = regsvc_match(ip)
    is_in_scope = any(r == region and s == aws_svc for r, s in pairs)
    if is_in_scope and not covered(ipstr):
        in_scope_uncovered.append(ipstr)
    elif not is_in_scope:
        out_of_scope.append((ipstr, pairs))

# 3. Render the generated block.
# NOTE: keep this free of ": " (colon-space) — the YAML plain scalar would otherwise
# parse as a mapping. Same gotcha the rest of egress-baseline.yaml avoids.
note = (f"CrowdSec CAPI (api.crowdsec.net, AWS-API-Gateway-fronted) + community-blocklist\n"
        f"        mirrors. Per ADR-039, scoped to AWS-published {region} {aws_svc} ranges (synced\n"
        f"        from ip-ranges.json) instead of per-rotation widening. REGENERATED by\n"
        f"        scripts/sync-aws-egress-ranges.sh — do not hand-edit; re-run the sync to refresh.")
block_lines = [
    BEGIN,
    f"    #     source=ip-ranges.json createDate={create_date} syncToken={sync_token} region={region} service={aws_svc} prefixes={len(cidrs)}",
    f"    - owner: Amazon {region} {aws_svc} (AWS-published ranges, ADR-039)",
    f"      cidrs: [{', '.join(cidrs)}]",
    f"      note: {note}",
    END,
]
block = "\n".join(block_lines) + "\n"

# 4. Splice or preview.
src = open(baseline_path).read()
m = re.search(re.escape(BEGIN) + r".*?" + re.escape(END) + r"\n", src, flags=re.S)

print(f"# sync-aws-egress-ranges — {svc_key} / {region} / {aws_svc}")
print(f"#   ip-ranges.json createDate={create_date}  ->  {len(cidrs)} collapsed prefixes")
print(f"#   observed {svc_key} dests: {len(set(observed))} unique; "
      f"in-scope-uncovered={len(in_scope_uncovered)}; out-of-scope(static)={len(out_of_scope)}")
if out_of_scope:
    print(f"#   out-of-scope observed (must be covered by STATIC entries — CloudFront/Cloudflare):")
    for ipstr, pairs in out_of_scope:
        tag = ",".join(sorted({f"{r}/{s}" for r, s in pairs})) or "non-AWS"
        print(f"#     {ipstr:16} {tag}")

if in_scope_uncovered:
    print(f"\nERROR: {len(in_scope_uncovered)} observed {svc_key} {region} {aws_svc} IP(s) would LOSE "
          f"coverage: {in_scope_uncovered}", file=sys.stderr)
    print("Refusing to write (AWS may have withdrawn a range still in use).", file=sys.stderr)
    sys.exit(2)

if not m:
    if write:
        print(f"\nERROR: markers not found in {baseline_path}; add the BEGIN/END block once, then re-run.",
              file=sys.stderr)
        sys.exit(2)
    print("\n# (markers not yet present — proposed block to insert under the crowdsec entry:)\n")
    print(block)
    sys.exit(0)

if m.group(0) == block:
    print("\n# No change: generated block already matches egress-baseline.yaml.")
    sys.exit(0)

if not write:
    print("\n# --- proposed generated block (run with --write to apply) ---\n")
    print(block)
    sys.exit(0)

open(baseline_path, "w").write(src[:m.start()] + block + src[m.end():])
print(f"\n# WROTE regenerated block ({len(cidrs)} prefixes) into {baseline_path}.")
print("# Next: daemon-reload not needed; the detector reloads the YAML on its next run.")
sys.exit(0)
PY
