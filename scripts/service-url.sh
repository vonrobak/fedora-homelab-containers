#!/bin/bash
# service-url.sh — derive a service's external URL from Traefik dynamic config.
#
# Routing truth lives in config/traefik/dynamic/routers.yml (ADR-016), so the
# external hostname for a container is mechanical: find the Traefik service
# whose backend URL targets the container, then the router with a plain
# Host(`…`) rule for that service. No more guessed hostnames in verify steps.
#
# Usage: service-url.sh <container-name>
#   stdout: https://<host>/   (exit 0)
#   exit 1: container has no Traefik route (internal-only service)
set -euo pipefail

ROUTERS_YML="${ROUTERS_YML:-$HOME/containers/config/traefik/dynamic/routers.yml}"
CONTAINER="${1:?usage: service-url.sh <container-name>}"

python3 - "$CONTAINER" "$ROUTERS_YML" <<'EOF'
import re, sys
import yaml
from urllib.parse import urlparse

container, routers_yml = sys.argv[1], sys.argv[2]
d = yaml.safe_load(open(routers_yml)) or {}
http = d.get('http', {})
routers, services = http.get('routers', {}) or {}, http.get('services', {}) or {}

# Traefik's own dashboard has no backend service entry
if container == 'traefik':
    matched = {'api@internal'}
else:
    matched = {
        sname for sname, s in services.items()
        for srv in (s.get('loadBalancer', {}) or {}).get('servers', []) or []
        if urlparse(srv.get('url', '')).hostname == container
    }
if not matched:
    sys.exit(1)

# Prefer the catch-all router (rule is exactly Host(`…`)) over path-scoped ones
plain, scoped = [], []
for r in routers.values():
    if r.get('service') not in matched:
        continue
    m = re.fullmatch(r"Host\(`([^`]+)`\)", r.get('rule', '').strip())
    if m:
        plain.append(m.group(1))
    else:
        m = re.search(r"Host\(`([^`]+)`\)", r.get('rule', ''))
        if m:
            scoped.append(m.group(1))
hosts = plain or scoped
if not hosts:
    sys.exit(1)
print(f"https://{hosts[0]}/")
EOF
