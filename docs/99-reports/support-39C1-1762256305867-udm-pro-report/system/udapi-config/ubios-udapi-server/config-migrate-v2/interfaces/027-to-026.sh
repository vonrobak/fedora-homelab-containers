#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."interfaces"=26'

JQA "${1}" '(.interfaces[]? | select(.identification.type == "wireless")) |= del(.wireless.lldp)'
exit 0
