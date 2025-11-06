#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# - update feature version
# - iterate .services?.wanFailover?.wanInterfaces[]?.monitors[]? and set .bindDomainResolution property to false,
#   if the monitor has the following properties set to false: .bindAddress, bindInterface, bindRoutingTable
JQA "${1}" '
    .versionDetail."services/wanFailover"=9 |
    .services?.wanFailover?.wanInterfaces[]?.monitors |=
        ((. // []) | map(select(
            (.bindAddress != null and .bindAddress == false) and
            (.bindInterface != null and .bindInterface == false) and
            (.bindRoutingTable != null and .bindRoutingTable == false)
        ) |= (. | . + { bindDomainResolution: false })))'

exit 0
