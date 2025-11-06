#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."services/dhcpServers"=3'

# Check if dhcpServers exists, then remove "excludedFromLease" where needed
JQA "${1}" '(.services?.dhcpServers[]?) |= del(.excludedFromLease)'

exit 0
