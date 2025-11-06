#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."firewall/nat"=5'

# remove whole .translation where .translation.port is zero (or "00", "000", ...)
# set such rule to disabled
JQA "${1}" '
    (."firewall/nat"[]? | select(.translation.port // "" | split("-")[]? | tonumber | . == 0))  |= (.enabled=false | del(.translation))
'

exit 0
