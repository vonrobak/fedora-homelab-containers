#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=10'

# Split NATRule::interface and NATRule::negateInterface into NATRule::[(in)|(out)]Interface and NATRule::negate[(In)|(Out)]Interface according to given target
QUERY='(."firewall/nat"[]? | select(has($prop))) |= (. | . + if .target == "DNAT" then {($in_prop): .[$prop]} else {($out_prop): .[$prop]} end | del(.[$prop]))'
JQA "${1}" "${QUERY}" "--arg prop interface --arg in_prop inInterface --arg out_prop outInterface"
JQA "${1}" "${QUERY}" "--arg prop negateInterface --arg in_prop negateInInterface --arg out_prop negateOutInterface"

exit 0

