#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."services/vrrp"=3 | .versionFormat="v2"'

# Rollback priority=255 that not supported in v3
JQA "${1}" '
 (.services.vrrp.instances[]? | select(.priority==255)) |= (.priority=254)
'

exit 0
