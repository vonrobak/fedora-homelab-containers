#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."services/radiusServer"=3'

# specify new types for the existing policy groups
JQA "${1}" '
    (. | select(has("services")) | .services | select(has("radiusServer")) | .radiusServer) |= (
        .policyGroups[]? |= ( .type = "filter" | .matchRule = "accept" )
    )
'

exit 0
