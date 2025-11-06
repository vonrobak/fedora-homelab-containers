#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."interfaces"=15'

# 1. Set CoS for DHCPv6 to 0
JQA "${1}" '.interfaces[].ipv6.cos = 0'

exit 0
