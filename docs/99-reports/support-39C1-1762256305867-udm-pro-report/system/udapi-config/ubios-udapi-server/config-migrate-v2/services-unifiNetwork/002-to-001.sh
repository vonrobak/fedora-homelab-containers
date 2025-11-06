#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."services/unifiNetwork"=1'

# remove new uciAllowList
JQA "${1}" 'del(.services.unifiNetwork?.uciAllowList)'

exit 0
