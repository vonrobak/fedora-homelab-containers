#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."interfaces"=6'

# remove egress rate limit
JQA "${1}" 'del(.interfaces[]?.switch.ports[]?.egressRate)'

exit 0
