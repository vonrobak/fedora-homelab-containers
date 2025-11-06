#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."interfaces"=3'

# remove Port Mirroring
JQA "${1}" 'del(.interfaces[]?.switch.ports[]?.mirrorPorts)'

exit 0
