#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# bump version down
# delete WAN with table 220
JQA "${1}" '
    .versionDetail."services/wanFailover"=5
    |
    del(.services?.wanFailover?.wanInterfaces[]? | select(.routingTable==220))
'

exit 0
