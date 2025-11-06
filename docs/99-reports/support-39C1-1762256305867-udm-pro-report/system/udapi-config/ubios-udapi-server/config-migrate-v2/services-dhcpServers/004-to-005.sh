#!/bin/sh
. "$(dirname "${0}")"/../JQ
JQA "${1}" '.versionDetail."services/dhcpServers"=5'

# set .services.dhcpServers[].ipExclusion = false as a default for relay and slaac-only configurations
JQA "${1}" '(.services?.dhcpServers[]? | select(.relay or any(.ipv6Modes[]?; IN("ra-only", "ra-names", "ra-stateless"))) | .ipExclusion) //= false'

exit 0
