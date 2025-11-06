#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=9'

# join NATRule::[(in)|(out)]Interface and NATRule::negate[(In)|(Out)]Interface into NATRule::interface and NATRule::negateInterface
# there is expected that (in)|(out) properties are mutually exclusive in the config being downgraded
QUERY='(."firewall/nat"[]? | select(has($prop_from))) |= (. | . + {($prop_to): .[$prop_from]} | del(.[$prop_from]))'
JQA "${1}" "${QUERY}" "--arg prop_from inInterface --arg prop_to interface"
JQA "${1}" "${QUERY}" "--arg prop_from outInterface --arg prop_to interface"
JQA "${1}" "${QUERY}" "--arg prop_from negateInInterface --arg prop_to negateInterface"
JQA "${1}" "${QUERY}" "--arg prop_from negateOutInterface --arg prop_to negateInterface"
exit 0
