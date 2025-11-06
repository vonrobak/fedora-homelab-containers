#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."routes/ospf/interfaces"=2
            |
            ."routes/ospf/interfaces"[]? |= del(.priority, .retransmitInterval, .network)
'

exit 0
