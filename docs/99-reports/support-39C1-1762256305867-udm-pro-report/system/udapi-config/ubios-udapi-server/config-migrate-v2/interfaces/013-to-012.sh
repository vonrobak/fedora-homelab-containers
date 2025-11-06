#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."interfaces"=12'

# Remove 'ip6tnl' interfaces.
JQA "${1}" 'del(.interfaces[]? | select(.tunnel.mode == "ip6tnl"))'

exit 0
