#!/bin/bash
# verify-image-signature.sh — ADR-030 P6 (Tier 3) deliberate-path authenticity gate.
#
# Verifies that a specific image digest was signed by the publisher's known keyless
# identity, using cosign. This exists because podman 5.8.2's policy.json cannot match
# a workflow-URI keyless identity (sigstoreSigned.fulcio mandates subjectEmail), so
# authenticity is enforced here — at the moment of DELIBERATE adoption (P1), after a
# bake (P3) — not at pull time. See docs/97-plans/2026-05-24-tier3-…-deliberate-path.md.
#
# cosign runs as a digest-pinned throwaway container (it is itself a supply-chain input).
#
# Usage: verify-image-signature.sh <repo@digest | repo:tag> [--service <name>] [--metric] [--quiet]
#
# Exit codes (the load-bearing contract — callers depend on these):
#   0  verified against a known signer identity
#   3  no signer entry for this repo  -> unsigned-but-tracked (NOT a failure; P6 graduated)
#   1  signer entry exists but verification FAILED  -> fail-closed (tamper / wrong identity)
#   2  tooling / network error (cosign image missing, registry/Rekor unreachable) -> retry, NOT fail-closed
set -uo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/containers}"
SIGNERS_FILE="${SIGNERS_FILE:-$REPO_ROOT/config/supply-chain/signers.yaml}"
COSIGN_IMAGE="${COSIGN_IMAGE:-ghcr.io/sigstore/cosign/cosign:v3.0.6@sha256:de9c65609e6bde17e6b48de485ee788407c9502fa08b8f4459f595b21f56cd00}"
METRIC_DIR="${METRIC_DIR:-$REPO_ROOT/data/backup-metrics}"
METRIC_FILE="$METRIC_DIR/supply-chain-signatures.prom"

ref="${1:?usage: verify-image-signature.sh <repo@digest|repo:tag> [--service <name>] [--metric] [--quiet]}"
shift || true
service=""; want_metric=false; quiet=false
while [ $# -gt 0 ]; do
    case "$1" in
        --service) service="${2:?}"; shift 2 ;;
        --metric)  want_metric=true; shift ;;
        --quiet)   quiet=true; shift ;;
        *) echo "verify-image-signature: unknown arg: $1" >&2; exit 2 ;;
    esac
done

# repo = ref with any @digest or :tag stripped
repo="$ref"; repo="${repo%@*}"; case "$repo" in *:*) repo="${repo%:*}";; esac
[ -n "$service" ] || service="$repo"

log() { $quiet || echo "$*" >&2; }

cosign() { podman run --rm --network=bridge "$COSIGN_IMAGE" "$@"; }

write_metric() {  # $1=value (1 ok / 0 failed)
    $want_metric || return 0
    mkdir -p "$METRIC_DIR" || return 0
    # Temp MUST be in-dir: a /tmp temp moved here keeps user_tmp_t → node_exporter (SELinux)
    # can't read it, silently killing the supply-chain alerts. In-dir inherits container_file_t.
    local tmp; tmp="$(mktemp -p "$METRIC_DIR")" || return 0
    # Preserve only OTHER services' DATA lines (not the HELP/TYPE comments — keeping those
    # and re-appending headers each run produced a "second HELP line" parse error that
    # node_exporter rejects). Emit the header block exactly ONCE, then all data lines.
    local prior=""
    [ -f "$METRIC_FILE" ] && prior="$(grep -E '^supply_chain_signature' "$METRIC_FILE" 2>/dev/null | grep -v "service=\"$service\"")"
    {
        echo "# HELP supply_chain_signature_verify ADR-030 P6 deliberate-path signature check (1=verified, 0=FAILED)."
        echo "# TYPE supply_chain_signature_verify gauge"
        echo "# HELP supply_chain_signature_last_verify_timestamp Unix time of the last deliberate-path signature check."
        echo "# TYPE supply_chain_signature_last_verify_timestamp gauge"
        [ -n "$prior" ] && printf '%s\n' "$prior"
        echo "supply_chain_signature_verify{service=\"$service\",repo=\"$repo\"} $1"
        echo "supply_chain_signature_last_verify_timestamp{service=\"$service\"} $(date +%s)"
    } > "$tmp"
    chmod 0644 "$tmp" 2>/dev/null   # node_exporter runs as 'nobody' — needs other-read
    mv "$tmp" "$METRIC_FILE" 2>/dev/null || rm -f "$tmp"
}

# --- look up signer entry (PyYAML) -------------------------------------------
[ -f "$SIGNERS_FILE" ] || { echo "verify-image-signature: missing $SIGNERS_FILE" >&2; exit 2; }
entry="$(python3 - "$SIGNERS_FILE" "$repo" <<'PY'
import sys, yaml
path, repo = sys.argv[1], sys.argv[2]
with open(path) as f:
    doc = yaml.safe_load(f) or {}
for s in (doc.get("signers") or []):
    if s.get("repo") == repo:
        print(s.get("oidc_issuer", "")); print(s.get("identity_regexp", ""))
        print(s.get("mechanism", "signature")); break
PY
)" || { echo "verify-image-signature: failed to parse $SIGNERS_FILE" >&2; exit 2; }

if [ -z "$entry" ]; then
    log "ℹ️  $repo: no signer entry — unsigned-but-tracked (ADR-030 P6)"
    exit 3
fi
issuer="$(printf '%s\n' "$entry" | sed -n 1p)"
identity="$(printf '%s\n' "$entry" | sed -n 2p)"
mechanism="$(printf '%s\n' "$entry" | sed -n 3p)"
[ -n "$issuer" ] && [ -n "$identity" ] || { echo "verify-image-signature: incomplete signer entry for $repo" >&2; exit 2; }
case "$mechanism" in
    signature|attestation) ;;
    *) echo "verify-image-signature: unknown mechanism '$mechanism' for $repo" >&2; exit 2 ;;
esac

# --- tooling + connectivity pre-checks (separate network errors from FAILURE) -
podman image exists "$COSIGN_IMAGE" || {
    echo "verify-image-signature: cosign image not present ($COSIGN_IMAGE) — run: podman pull $COSIGN_IMAGE" >&2; exit 2; }
if ! skopeo inspect --raw "docker://$ref" >/dev/null 2>&1; then
    echo "verify-image-signature: registry unreachable or ref unresolvable: $ref (retry)" >&2; exit 2
fi

# --- verify ------------------------------------------------------------------
log "🔎 verifying $ref ($mechanism)"
log "   identity ~ $identity"
log "   issuer     $issuer"
if [ "$mechanism" = "attestation" ]; then
    # Referrer-attached sigstore bundle (GitHub Artifact Attestations): the SLSA
    # provenance statement's subject digest is checked against $ref by cosign.
    out="$(cosign verify-attestation --new-bundle-format \
            --type slsaprovenance1 \
            --certificate-identity-regexp "$identity" \
            --certificate-oidc-issuer "$issuer" \
            "$ref" 2>&1)"; rc=$?
else
    out="$(cosign verify \
            --certificate-identity-regexp "$identity" \
            --certificate-oidc-issuer "$issuer" \
            "$ref" 2>&1)"; rc=$?
fi

if [ $rc -eq 0 ]; then
    log "✅ VERIFIED: $repo signed by expected identity"
    write_metric 1
    exit 0
fi

# Registry was reachable (pre-check passed) → a cosign failure is either a genuine
# verification failure (fail-closed) or a transparency-log/transient error (retry).
if printf '%s' "$out" | grep -qiE 'rekor|tlog|transparency|timeout|deadline exceeded|connection refused|no such host|tuf|fetch.*trust'; then
    echo "verify-image-signature: transient verification error (Rekor/TUF/network), retry:" >&2
    $quiet || printf '%s\n' "$out" | tail -5 >&2
    exit 2
fi

echo "❌ SIGNATURE VERIFICATION FAILED for $ref" >&2
echo "   expected identity ~ $identity (issuer $issuer)" >&2
$quiet || printf '%s\n' "$out" | tail -8 >&2
write_metric 0
exit 1
