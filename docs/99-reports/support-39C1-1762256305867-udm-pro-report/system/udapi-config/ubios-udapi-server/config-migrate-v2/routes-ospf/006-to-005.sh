#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# bump version
# delete unused attribute
JQA "${1}" '.versionDetail."routes/ospf"=5
            |
            del(."routes/ospf"?.knownNeighbors)'

exit 0
