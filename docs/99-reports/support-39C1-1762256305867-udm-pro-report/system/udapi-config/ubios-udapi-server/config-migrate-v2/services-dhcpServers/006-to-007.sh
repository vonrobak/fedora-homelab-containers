#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# This config migration is equal to 006-to-005.sh as we are just rolling back the feature.
JQA "${1}" '.versionDetail."services/dhcpServers"=7
        | del(.services?.dhcpServers[]?.isolated)'

exit 0
