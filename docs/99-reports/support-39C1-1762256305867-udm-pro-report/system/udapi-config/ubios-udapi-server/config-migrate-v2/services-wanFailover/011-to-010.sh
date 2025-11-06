#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# - update version
# - remove unsupported jitterThreshold for DNS monitors only

JQA "${1}" '.versionDetail."services/wanFailover"=10 |
    (.services?.wanFailover?.wanInterfaces[]?.monitors[]?
    | select(.type == "dns")) |= del(.alert?.jitterThreshold)
'

exit 0
