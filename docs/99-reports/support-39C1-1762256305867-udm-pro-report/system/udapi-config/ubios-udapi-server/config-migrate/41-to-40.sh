#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=40'
JQA "${1}" '.services.dhcpServers[]? |= del(.ipv6Modes[] | select(. != "slaac"))'
exit 0
