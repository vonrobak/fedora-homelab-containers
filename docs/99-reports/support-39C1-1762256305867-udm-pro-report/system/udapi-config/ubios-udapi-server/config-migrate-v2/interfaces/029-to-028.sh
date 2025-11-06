#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."interfaces"=28'

# Remove DHCPv4 client option 121
JQA "${1}" 'del(.interfaces[]?.ipv4.dhcpOptions[]? | select(.optionNumber==121 or .value==null))'

exit 0
