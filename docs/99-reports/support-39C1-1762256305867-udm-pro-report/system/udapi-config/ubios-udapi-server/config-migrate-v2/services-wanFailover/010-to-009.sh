#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# - update feature version
# - remove failover monitor threshold from all failover interfaces
JQA "${1}" '
    .versionDetail."services/wanFailover"=9 |
    del(.services?.wanFailover?.wanInterfaces[]?.monitorHealthThreshold)
'

exit 0
