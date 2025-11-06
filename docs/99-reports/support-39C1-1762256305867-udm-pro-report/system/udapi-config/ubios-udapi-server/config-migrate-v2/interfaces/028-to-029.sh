#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."interfaces"=29'

JQA "${1}" 'del(.interfaces[]?.ipv4.dhcpOptions[]? | select(.value==""))'

exit 0
