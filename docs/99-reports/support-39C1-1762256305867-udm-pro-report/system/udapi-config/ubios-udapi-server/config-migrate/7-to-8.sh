#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=8'

# Support user<FILTERED> firewall chains.
# FilterRule and NATRule 'action' renamed to 'target' allow user<FILTERED> chain to be set as a target.
JQA "${1}" '(."firewall/filter"[].rules[]? | select(has("action"))) |= (. | . + {target: .action} | del(.action))'
JQA "${1}" '(."firewall/nat"[]? | select(has("action"))) |= (. | . + {target: .action} | del(.action))'

exit 0

