#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."interfaces"=10'

# remove Loop Protection per interface
JQA "${1}" 'del(.interfaces[]?.ethernet.loopProtection)'

# remove Loop Protection service
JQA "${1}" 'del(.services.loopProtection)'

exit 0
