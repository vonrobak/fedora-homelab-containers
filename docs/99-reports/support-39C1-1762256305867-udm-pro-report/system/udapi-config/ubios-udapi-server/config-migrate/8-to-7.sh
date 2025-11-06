#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=7'

# Downgrading to version that doesn't support user<FILTERED> chains.
# - Rename 'target' to 'action' property of NATRule and FilterRule and
#   put DROP action to all jump targets to user<FILTERED> chains.
JQA "${1}" '(."firewall/filter"[].rules[]? | select(has("target"))) |= (. | . + if (.target == "DROP" or .target == "REJECT" or.target == "RETURN") then {action: .target} else {action: "ACCEPT"} end | del(.target))'
JQA "${1}" '(."firewall/nat"[]? | select(has("target"))) |= (. | . + if (.target == "SNAT" or .target == "DNAT" or.target == "MASQUERADE") then {action: .target} else {action: "ACCEPT"} end | del(.target))'

# - Drop all user<FILTERED> chains
JQA "${1}" 'del(."firewall/filter"[]? | select(.config.name != "INPUT" and .config.name != "OUTPUT" and .config.name != "FORWARD"))'
JQA "${1}" 'del(."firewall/nat"[]? | select(.chain != "POSTROUTING" and .chain != "PREROUTING"))'

exit 0
