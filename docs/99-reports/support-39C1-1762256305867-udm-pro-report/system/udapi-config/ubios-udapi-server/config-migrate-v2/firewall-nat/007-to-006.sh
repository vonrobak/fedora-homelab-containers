#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."firewall/nat"=6'

# remove unsupported NETMAP NAT rules

JQA "${1}" 'del (."firewall/nat"[]? | select(.target == "NETMAP"))'

exit 0
