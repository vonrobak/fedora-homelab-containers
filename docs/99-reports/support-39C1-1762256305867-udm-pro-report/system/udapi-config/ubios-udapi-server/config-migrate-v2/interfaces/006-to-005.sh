#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."interfaces"=5'

# remove Storm Control
JQA "${1}" 'del(.interfaces[]?.switch.ports[]?.stormControl)'

exit 0
