#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts

# .services.dhcpServers[]?.name has become optional; no action required for the upgrade script
JQA "${1}" '.version=21'

exit 0
