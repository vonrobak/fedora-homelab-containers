#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=41'
JQA "${1}" '.services.dhcpServers[]?.ipv6Modes[]? |= sub("_";"-")'
exit 0
