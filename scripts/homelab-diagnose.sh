#!/usr/bin/env bash
set -euo pipefail

OUTDIR="${HOME}/containers/docs/reports"
TS="$(date +'%Y%m%d-%H%M%S')"
REPORT="${OUTDIR}/homelab-diagnose-${TS}.txt"

mkdir -p "${OUTDIR}"

log() { printf "%s\n" "$*" | tee -a "${REPORT}"; }
hr()  { printf -- "--------------------------------------------------------------------------------\n" | tee -a "${REPORT}"; }

# Header
hr
log "# Homelab Diagnostic Report"
log "Generated: $(date -Is)"
log "Host: $(hostname -f 2>/dev/null || hostname)"
hr

# System basics
log "## System"
{ 
  echo "OS: $(grep -E '^PRETTY_NAME=' /etc/os-release | cut -d= -f2- | tr -d '"')"
  echo "Kernel: $(uname -r)"
  echo "Uptime: $(uptime -p)"
  echo "SELinux: $(getenforce 2>/dev/null || echo 'unknown')"
  echo "User linger: $(loginctl show-user \"$USER\" 2>/dev/null | awk -F= '/Linger/ {print $2}')"
  echo "unprivileged_port_start: $(cat /proc/sys/net/ipv4/ip_unprivileged_port_start 2>/dev/null || echo 'unknown')"
} | tee -a "${REPORT}"
hr

# Network & DNS
log "## Network & DNS"
{ 
  ip -brief addr || true
  echo
  echo "Default route:"
  ip route show default || true
  echo
  echo "/etc/resolv.conf:"
  sed -n '1,200p' /etc/resolv.conf || true
  echo
  echo "Pi-hole DNS test (A patriark.lokal via 192.168.1.69):"
  command -v dig >/dev/null && dig +short @192.168.1.69 patriark.lokal || nslookup patriark.lokal 2>/dev/null || true
} | sed 's/\t/  /g' | tee -a "${REPORT}"
hr

# Firewall
log "## Firewall (firewalld)"
{ 
  sudo firewall-cmd --state 2>/dev/null || true
  sudo firewall-cmd --get-active-zones 2>/dev/null || true
  echo
  sudo firewall-cmd --list-all 2>/dev/null || true
} | tee -a "${REPORT}"
hr

# Listeners (privileged + key services)
log "## Listening ports (80,443,8096,9091,8080)"
ss -tulnp | grep -E '(:80 |:443 |:8096 |:9091 |:8080 )' || true | tee -a "${REPORT}"
hr

# Podman
log "## Podman"
{ 
  podman version || true
  echo
  echo "Containers (running):"
  podman ps || true
  echo
  echo "Containers (all):"
  podman ps -a || true
  echo
  echo "Networks:"
  podman network ls || true
  echo
  for net in reverse_proxy media_services web_services; do
    echo
    echo "Inspect network: ${net}"
    podman network inspect "${net}" 2>/dev/null || echo "N/A"
  done
} | tee -a "${REPORT}"
hr

# Quadlets present
log "## Quadlets"
{ 
  echo "~/.config/containers/systemd/"
  ls -al "${HOME}/.config/containers/systemd" || true
  echo
  echo "Rendered user units that mention traefik/authelia/jellyfin:"
  systemctl --user list-units --type=service | grep -E 'traefik|authelia|jellyfin' || true
  echo
  echo "Unit status (traefik/authelia/jellyfin):"
  for u in traefik.service authelia.service jellyfin.service; do
    echo
    systemctl --user is-enabled "${u}" 2>/dev/null || true
    systemctl --user status "${u}" --no-pager -l 2>/dev/null || true
  done
} | tee -a "${REPORT}"
hr

# Traefik config, logs, acme metadata
log "## Traefik"
{ 
  TF_BASE="${HOME}/containers/config/traefik"
  echo "Config dir: ${TF_BASE}"
  echo "Static file (etc): ${TF_BASE}/etc/traefik.yml"
  echo "Dynamic dir (etc): ${TF_BASE}/etc/dynamic"
  echo "Logs dir: ${TF_BASE}/logs"
  echo "ACME dir: ${TF_BASE}/acme"
  echo
  [ -f "${TF_BASE}/etc/traefik.yml" ] && sed -n '1,80p' "${TF_BASE}/etc/traefik.yml" || echo "traefik.yml not found"
  echo
  echo "Dynamic files list:"
  ls -1 "${TF_BASE}/etc/dynamic" 2>/dev/null || echo "No dynamic files"
  echo
  if [ -f "${TF_BASE}/acme/acme.json" ]; then
    echo "ACME file perms & size:"
    ls -l "${TF_BASE}/acme/acme.json"
    echo "ACME file head (first 5 lines):"
    head -n 5 "${TF_BASE}/acme/acme.json" | sed 's/\"token\":[^,]*/"token":"***redacted***"/g' 
  else
    echo "ACME file not present."
  fi
  echo
  echo "Traefik logs (last 200):"
  podman logs traefik --tail=200 2>/dev/null || echo "no traefik container logs"
} | tee -a "${REPORT}"
hr

# Authelia quick checks (no secrets)
log "## Authelia"
{ 
  AU_BASE="${HOME}/containers/config/authelia"
  echo "Config dir: ${AU_BASE} (if present)"
  [ -d "${AU_BASE}" ] && (find "${AU_BASE}" -maxdepth 1 -type f -name '*.yml' -o -name '*.yaml' -o -name '*.toml' -o -name '*.json' | sort) || echo "authelia config dir not found"
  echo
  echo "Authelia logs (last 200):"
  podman logs authelia --tail=200 2>/dev/null || echo "no authelia container logs"
  echo
  echo "Common pitfalls (heuristics):"
  echo "- SMTP notifier configured? (look for 'notifier' in config files)"
  if [ -d "${AU_BASE}" ]; then
    grep -RniE 'notifier|smtp|mail' "${AU_BASE}" 2>/dev/null | sed 's/password:.*/password: ***redacted***/' || true
  fi
  echo "- WebAuthn RP ID should match your domain (e.g., patriark.lokal)."
  echo "- Verify cookie domain and session same-site settings if login loop occurs."
} | tee -a "${REPORT}"
hr

# Jellyfin quick
log "## Jellyfin"
{ 
  podman logs jellyfin --tail=50 2>/dev/null || echo "no jellyfin logs"
} | tee -a "${REPORT}"
hr

# Summary
log "## Summary (short)"
{
  echo "- 80/443 open via firewalld? (see 'Firewall' section)"
  echo "- rootless privileged ports allowed? unprivileged_port_start=$(cat /proc/sys/net/ipv4/ip_unprivileged_port_start 2>/dev/null || echo '?')"
  echo "- Traefik running and listening on :80/:443? (see 'Listening ports')"
  echo "- ACME file present and non-empty? (see 'Traefik' section)"
  echo "- Authelia running; login/email/WebAuthn logs noted above."
} | tee -a "${REPORT}"
hr

echo "Wrote report: ${REPORT}"
