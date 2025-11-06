#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."services/wanFailover"=3'

# no need to downgrade from 004 to 003 in cases:
# - if no wanFailover service, then nothing to update
JQT "${1}" '.services.wanFailover' || exit 0

# remove `overrideTargetTtl` monitors 
JQA "${1}" 'del(.services.wanFailover.wanInterfaces[]?.monitors[]?.overrideTargetTtl)'

exit 0
