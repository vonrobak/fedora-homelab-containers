#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# bump version
# fix API typo
JQA "${1}" '.versionDetail."routes/ospf/interfaces"=4
            |
            (."routes/ospf/interfaces"[]? | select(.network == "boradcast")) |= (.network="broadcast")
'
exit 0
