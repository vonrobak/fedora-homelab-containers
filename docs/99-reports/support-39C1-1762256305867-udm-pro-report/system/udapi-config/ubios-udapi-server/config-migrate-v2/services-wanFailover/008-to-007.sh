#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# - update feature version
# - remove failover monitors if any bind property (.bindAddress or bindInterface or bindRoutingTable) is false
# - remove failover monitors bind properties, if they exist
# - remove failover interfaces with unset .routingTable
JQA "${1}" '
    .versionDetail."services/wanFailover"=7 |
    .services?.wanFailover?.wanInterfaces[]? |= select(.routingTable) |
    .services?.wanFailover?.wanInterfaces[]?.monitors |=
        ((. // []) | map(select(
            (.bindAddress == null or .bindAddress == true) and
            (.bindInterface == null or .bindInterface == true) and
            (.bindRoutingTable == null or .bindRoutingTable == true)
        ) | del(.bindAddress, .bindInterface, .bindRoutingTable)))
'

exit 0
