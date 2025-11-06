#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."interfaces"=18'

# Remove VRRP address
JQA "${1}" 'del(.interfaces[]?.addresses[]? | select(.origin=="vrrp"))'

exit 0
