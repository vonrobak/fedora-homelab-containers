#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."firewall/nat"=4'

# remove whole .translation where .translation.address is a list of addresses, subnets or ranges
# set such rule to disabled
JQA "${1}" '
(."firewall/nat"[]? | select(.target | contains("SNAT")) | select(.translation.address | test(",")) ) |= (.enabled=false)
'

exit 0
