#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

JQA "${1}" '.versionDetail."interfaces"=27'
JQA "${1}" 'del(.interfaces[]?.ipv6?.dhcp6DuidOverride?)'

exit 0
