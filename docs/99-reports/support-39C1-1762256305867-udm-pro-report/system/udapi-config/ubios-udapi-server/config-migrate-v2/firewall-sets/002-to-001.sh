#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# Bump version.
# Remove IPv6 ranges from FirewallSet
JQA "${1}" '
    .versionDetail."firewall/sets"=1
    |
    ."firewall/sets"[]? |=
        if .identification.type == "address" then
            .entries |= map(select((contains(":") and contains("-")) | not))
        else
            .
        end
'

exit 0
