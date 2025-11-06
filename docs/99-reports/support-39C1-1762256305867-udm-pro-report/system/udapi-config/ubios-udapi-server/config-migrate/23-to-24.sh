#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=24'

# NATRule .translation.address cannot be a subnet
JQA "${1}" '(."firewall/nat"[]?.translation | select(has("address"))) |= (.address=(.address | split("/")[0]))'

# NATRule .translation.port cannot be a port enumeration
JQA "${1}" '(."firewall/nat"[]?.translation | select(has("port"))) |= (.port=(.port | split(",")[0]))'

exit 0
