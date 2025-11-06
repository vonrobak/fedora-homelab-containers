#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."services/dhcpServers"=1'

# Check if dhcpServers exists, then remove "interval" and "routerLifetime" from "routerAdvertisement" where needed
JQA "${1}" '(.services?.dhcpServers[]? | select(has("routerAdvertisement"))) |= del(.routerAdvertisement.interval, .routerAdvertisement.routerLifetime)'

exit 0
