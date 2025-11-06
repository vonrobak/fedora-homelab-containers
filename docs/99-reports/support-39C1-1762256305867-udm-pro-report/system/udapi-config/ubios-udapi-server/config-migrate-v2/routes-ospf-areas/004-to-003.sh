#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."routes/ospf/areas"=3 |
            del(."routes/ospf/areas"[]?.networks[]? | select(.source == "interface"))'

exit 0
