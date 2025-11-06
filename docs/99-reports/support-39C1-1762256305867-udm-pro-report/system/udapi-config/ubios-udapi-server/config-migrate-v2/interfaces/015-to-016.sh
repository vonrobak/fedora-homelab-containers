#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
# do nothing CoS == 0 for DHCPv6 is OK
JQA "${1}" '.versionDetail."interfaces"=16'

exit 0
