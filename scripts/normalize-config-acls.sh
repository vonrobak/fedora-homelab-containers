#!/bin/bash
# normalize-config-acls.sh
# Make config/ readable by non-root container users across git checkouts
#
# Purpose:
#   Containers that run as a non-root UID inside their userns (prometheus and
#   alertmanager as 65534, grafana as 472, loki, blackbox-exporter) read their
#   bind-mounted config through the *other* permission bits — rootless podman maps
#   container root to the host user, so anything else lands in "other".
#
#   The owner's umask is 077. Git records mode 100644, but a checkout that
#   rewrites a file applies the umask instead, producing 0600. Those containers
#   then cannot read the file. The failure is silent and delayed:
#     - a running process keeps the config it loaded at startup
#     - every subsequent reload fails ("previous rule set restored")
#     - the next *restart* fails outright, because config-load failure is fatal
#   This bit both Prometheus (7 rule files) and Alertmanager (alertmanager.yml)
#   between 2026-07-21 and 2026-07-25 without a single alert firing.
#
#   Git tracks no permission bits beyond the exec bit, so this cannot be fixed
#   in-repo. The durable fix is a *default POSIX ACL* on each config directory:
#   when a directory carries one, new files inherit its entries and the umask is
#   bypassed entirely. Set once, survives every future checkout.
#
# Two classes, because not all config is public:
#   public — tracked, no credentials. Default ACL grants other::r, matching the
#            100644 git already records. UID-agnostic, so it works no matter
#            which user the container runs as.
#   secret — gitignored, contains live credentials. Default ACL grants read to
#            that container's mapped host UID by name and keeps other::---.
#            Tighter than the 0644 these files had before the breakage.
#
# Run: ./scripts/normalize-config-acls.sh [--check]
#   --check   report drift without changing anything (exit 1 if drift found)
#
# Idempotent. Safe to re-run.
#
# See: ADR-019 (Filesystem Permission Model), ADR-001 (rootless containers)
# Status: ACTIVE
# Created: 2026-07-25

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FIXED=0
DRIFT=0

pass()  { echo -e "${GREEN}✅ OK:${NC} $1"; ((PASS++)) || true; }
fixed() { echo -e "${YELLOW}🔧 FIXED:${NC} $1"; ((FIXED++)) || true; }
drift() { echo -e "${RED}❌ DRIFT:${NC} $1"; ((DRIFT++)) || true; }
info()  { echo -e "${BLUE}ℹ️  INFO:${NC} $1"; }

CHECK_ONLY=false
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=true

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Container UID -> host UID, per rootless podman's subuid mapping.
# Container 0 maps to the host user; container N (N>=1) maps to base + N - 1.
SUBUID_BASE=$(awk -F: -v u="$(id -un)" '$1==u {print $2; exit}' /etc/subuid)
if [[ -z "$SUBUID_BASE" ]]; then
  echo "ERROR: no subuid range for $(id -un) in /etc/subuid" >&2
  exit 2
fi
host_uid_for() { echo $((SUBUID_BASE + $1 - 1)); }

# dir:class:container_uid   (container_uid is only consulted for class=secret)
CONFIG_DIRS=(
  "config/prometheus:public:65534"
  "config/grafana:public:472"
  "config/loki:public:0"
  "config/blackbox-exporter:public:1000"
  "config/alloy:public:0"
  "config/promtail:public:0"
  "config/unpoller:public:0"
  "config/alertmanager:secret:65534"
)

apply_public() {
  local dir="$1"
  local want_default="default:other::r"

  if getfacl -p "$dir" 2>/dev/null | grep -qF "$want_default"; then
    pass "$dir — default ACL present (new files inherit other::r)"
  elif $CHECK_ONLY; then
    drift "$dir — no default ACL; a checkout under umask 077 will make files unreadable"
  else
    find "$dir" -type d -exec setfacl -d -m u::rwX,g::rX,o::rX {} +
    fixed "$dir — default ACL installed (u::rwX,g::rX,o::rX)"
  fi

  # Repair files the umask already clipped.
  local broken
  broken=$(find "$dir" -type f ! -perm -o=r 2>/dev/null || true)
  if [[ -n "$broken" ]]; then
    if $CHECK_ONLY; then
      while IFS= read -r f; do drift "$f — not other-readable; its container cannot read it"; done <<< "$broken"
    else
      while IFS= read -r f; do chmod o+r "$f"; fixed "$f — restored other-readable"; done <<< "$broken"
    fi
  fi
}

apply_secret() {
  local dir="$1" cuid="$2"
  local huid; huid=$(host_uid_for "$cuid")
  local want_default="default:user:${huid}:r"

  if getfacl -p "$dir" 2>/dev/null | grep -qF "$want_default"; then
    pass "$dir — default ACL present (new files readable by host UID $huid only)"
  elif $CHECK_ONLY; then
    drift "$dir — no default ACL; a checkout under umask 077 will make files unreadable"
  else
    find "$dir" -type d -exec setfacl -d -m "u::rwX,u:${huid}:rX,g::---,o::---" {} +
    fixed "$dir — default ACL installed (u:${huid}:r, other denied)"
  fi

  # The named entry is what grants access, so other:: can stay closed. Grant
  # before closing, never the reverse — the container must not lose access even
  # momentarily.
  local f has_acl other_readable
  while IFS= read -r -d '' f; do
    getfacl -p "$f" 2>/dev/null | grep -qF "user:${huid}:r" && has_acl=true || has_acl=false
    [[ -n $(find "$f" -perm -o=r -print -quit) ]] && other_readable=true || other_readable=false

    if $has_acl && ! $other_readable; then
      pass "$(basename "$f") — readable by host UID $huid, other denied"
      continue
    fi

    if $CHECK_ONLY; then
      $has_acl || drift "$f — no read ACL for host UID $huid; its container cannot read it"
      $other_readable && drift "$f — credential is world-readable; a named ACL makes that unnecessary"
      continue
    fi

    $has_acl        || { setfacl -m "u:${huid}:r" "$f"; fixed "$f — granted read to host UID $huid"; }
    $other_readable && { chmod o-r "$f";               fixed "$f — closed other-read (named ACL grants the container)"; }
  done < <(find "$dir" -type f -print0)
}

echo ""
info "subuid base for $(id -un): $SUBUID_BASE"
$CHECK_ONLY && info "check-only mode — no changes will be made"
echo ""

for entry in "${CONFIG_DIRS[@]}"; do
  IFS=: read -r dir class cuid <<< "$entry"
  [[ -d "$dir" ]] || { info "$dir — absent, skipped"; continue; }
  case "$class" in
    public) apply_public "$dir" ;;
    secret) apply_secret "$dir" "$cuid" ;;
  esac
done

echo ""
echo "─────────────────────────────────────────"
echo "OK: $PASS   Fixed: $FIXED   Drift: $DRIFT"
echo "─────────────────────────────────────────"
echo ""

if (( DRIFT > 0 )); then
  info "Re-run without --check to repair, then reload the affected services:"
  info "  podman exec grafana curl -s -XPOST http://prometheus:9090/-/reload"
  info "  podman exec grafana curl -s -XPOST http://alertmanager:9093/-/reload"
  exit 1
fi

exit 0
