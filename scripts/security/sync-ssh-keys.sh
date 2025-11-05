#!/usr/bin/env bash
# sync-ssh-keys.sh
# Push a canonical authorized_keys file to a set of hosts, with backups and verification.
# Idempotent and safe: backs up remote file with timestamp, sets correct perms, optional verify.
#
# Usage:
#   ./sync-ssh-keys.sh [--dry-run] [--verify] [--limit "host1 host2"] [--port 22]
#
# Requires:
#   - ssh, scp on the local machine
#   - Passwordless (key-based) SSH to the REMOTE_USER on each host (you'll still be prompted for YubiKey touch)
#   - A config file ssh-hosts.env in the same directory or exported env vars:
#       HOSTS, REMOTE_USER, AUTHORIZED_KEYS_PATH, SSH_PORT
#
# Exit codes:
#   0 success, non-zero on first failure encountered.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/ssh-hosts.env"

# Defaults (can be overridden by env file or environment)
HOSTS="${HOSTS:-}"
REMOTE_USER="${REMOTE_USER:-patriark}"
AUTHORIZED_KEYS_PATH="${AUTHORIZED_KEYS_PATH:-${HOME}/containers/docs/30-security/authorized_keys.lan}"
SSH_PORT="${SSH_PORT:-22}"

DRY_RUN="0"
VERIFY="0"
LIMIT_HOSTS=""

ts() { date "+%Y-%m-%d %H:%M:%S"; }
msg() { echo "[$(ts)] $*"; }
err() { echo "[$(ts)] ERROR: $*" >&2; }

usage() {
  sed -n '1,40p' "$0" | sed 's/^# \?//'
  exit 1
}

# Load env file if present
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN="1"; shift ;;
    --verify)  VERIFY="1"; shift ;;
    --limit)   LIMIT_HOSTS="$2"; shift 2;;
    --port)    SSH_PORT="$2"; shift 2;;
    -h|--help) usage ;;
    *) err "Unknown arg: $1"; usage ;;
  esac
done

if [[ -n "$LIMIT_HOSTS" ]]; then
  HOSTS="$LIMIT_HOSTS"
fi

if [[ -z "${HOSTS}" ]]; then
  err "HOSTS is empty. Set in ssh-hosts.env or pass with --limit."
  exit 2
fi

if [[ ! -f "${AUTHORIZED_KEYS_PATH}" ]]; then
  err "Canonical authorized_keys not found at ${AUTHORIZED_KEYS_PATH}"
  exit 3
fi

# Quick policy check: ensure LAN restriction present on all non-comment lines
NON_COMMENT_LINES=$(grep -vE '^(#|\s*$)' "${AUTHORIZED_KEYS_PATH}" || true)
if [[ -n "${NON_COMMENT_LINES}" ]]; then
  MISSING_FROM=$(echo "${NON_COMMENT_LINES}" | grep -v 'from="192.168.1.0/24"' || true)
  if [[ -n "${MISSING_FROM}" ]]; then
    msg "Policy warning: some keys lack from="192.168.1.0/24" restriction."
    msg "Proceeding anyway (you can enforce policy by editing ${AUTHORIZED_KEYS_PATH})."
  fi
fi

tmpdir="$(mktemp -d)"
cleanup() { rm -rf "${tmpdir}"; }
trap cleanup EXIT

REMOTE_TMP=".ssh/authorized_keys.new"
REMOTE_FILE=".ssh/authorized_keys"

for host in ${HOSTS}; do
  msg "=== Host: ${host} ==="
  if [[ "${DRY_RUN}" == "1" ]]; then
    msg "[dry-run] Would connect to ${REMOTE_USER}@${host}:${SSH_PORT}"
    msg "[dry-run] Would back up remote ${REMOTE_FILE} if exists"
    msg "[dry-run] Would upload ${AUTHORIZED_KEYS_PATH} → ${REMOTE_TMP} and move into place"
    continue
  fi

  # Ensure .ssh exists with correct perms
  ssh -p "${SSH_PORT}" "${REMOTE_USER}@${host}" "mkdir -p ~/.ssh && chmod 700 ~/.ssh"

  # Backup existing authorized_keys if present
  ssh -p "${SSH_PORT}" "${REMOTE_USER}@${host}" 'if [[ -f ~/.ssh/authorized_keys ]]; then cp ~/.ssh/authorized_keys ~/.ssh/authorized_keys.backup-$(date +%Y%m%d%H%M%S); fi'

  # Upload new file to a temp path
  scp -P "${SSH_PORT}" "${AUTHORIZED_KEYS_PATH}" "${REMOTE_USER}@${host}:${REMOTE_TMP}"

  # Set perms and move atomically
  ssh -p "${SSH_PORT}" "${REMOTE_USER}@${host}" "chmod 600 ${REMOTE_TMP} && mv ${REMOTE_TMP} ${REMOTE_FILE}"

  msg "Pushed authorized_keys to ${host} and set permissions."

  if [[ "${VERIFY}" == "1" ]]; then
    # BatchMode avoids password prompt; success means key auth works
    if ssh -p "${SSH_PORT}" -o BatchMode=yes -o ConnectTimeout=5 "${REMOTE_USER}@${host}" "true"; then
      msg "Verification: ✅ key-only auth works for ${host}"
    else
      err "Verification: ❌ failed for ${host} (check sshd or key order)"
      exit 4
    fi
  fi
done

msg "All done."
