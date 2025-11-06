#!/bin/sh
. "$(dirname "${0}")"/../JQ

JQA "${1}" '.versionDetail."services/dhcpServers"=6'

exit 0
