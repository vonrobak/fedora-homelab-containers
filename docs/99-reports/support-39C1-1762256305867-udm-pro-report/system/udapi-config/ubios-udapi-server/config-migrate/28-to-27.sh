#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=27'

# remove unsupported REDIRECT NAT rules

JQA "${1}" 'del (."firewall/nat"[]? | select(.target == "REDIRECT"))'

exit 0
