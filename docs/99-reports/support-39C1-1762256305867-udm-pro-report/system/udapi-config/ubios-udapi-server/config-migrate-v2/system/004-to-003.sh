#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."system"=3'

# remove fwUpdateToken
JQA "${1}" 'del(.system.fwUpdateToken)'

exit 0
