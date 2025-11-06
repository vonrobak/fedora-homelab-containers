#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."firewall/pbr"=3'

# remove PBR strict field
JQA "${1}" '(."firewall/pbr"."rules"[]?.routingMode | select(.mode="table")) |= del(.strict)'

exit 0
