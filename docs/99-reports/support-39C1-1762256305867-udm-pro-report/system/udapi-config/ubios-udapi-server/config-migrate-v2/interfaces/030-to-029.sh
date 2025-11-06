#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."interfaces"=29'

# remove Port Restriction
JQA "${1}" 'del(.interfaces[]?.switch.ports[]?.portRestrict)'

exit 0
