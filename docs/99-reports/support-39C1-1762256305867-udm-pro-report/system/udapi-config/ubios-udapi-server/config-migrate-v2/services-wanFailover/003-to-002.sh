#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."services/wanFailover"=2'

# no need to downgrade from 003 to 002 in cases:
# - if no wanFailover service, then nothing to update
JQT "${1}" '.services.wanFailover' || exit 0

# remove DNS wanFailover monitors 
JQA "${1}" 'del(.services.wanFailover.wanInterfaces[]?.monitors[]?|select(.type=="dns"))'

exit 0
