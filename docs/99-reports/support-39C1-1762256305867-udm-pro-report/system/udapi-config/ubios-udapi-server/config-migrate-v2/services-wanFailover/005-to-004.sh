#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."services/wanFailover"=4'

# no need to downgrade if no wanFailover service
JQT "${1}" '.services.wanFailover' || exit 0

# remove connectionResetTriggers
JQA "${1}" 'del(.services.wanFailover.failoverGroups[]?.connectionResetTriggers)'

exit 0
