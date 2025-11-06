#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."services/dhcpServers"=2'

# Check if dhcpServers exists, then remove "conflictChecking"
JQA "${1}" '(.services?.dhcpServers[]?) |= del(.conflictChecking)'

exit 0
