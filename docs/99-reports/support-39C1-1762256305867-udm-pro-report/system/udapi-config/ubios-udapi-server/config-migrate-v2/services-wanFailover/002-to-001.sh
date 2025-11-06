#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."services/wanFailover"=1'

# no need to downgrade from 002 to 001 in cases:
# - if no wanFailover service, then nothing to update
JQT "${1}" '.services.wanFailover' || exit 0
# - if interfaceIdentification is used, then format is already updated
JQT "${1}" '.services.wanFailover.wanInterfaces[]?.interface?.id?' && exit 0

# remove groups
JQA "${1}" '
    (. | select(has("services")) | .services | select(has("wanFailover")) | .wanFailover) |= (
        del(.failoverGroups)
    )'

# convert InterfaceID to InterfaceIdentification
JQA "${1}" '
    (. | select(has("services")) | .services | select(has("wanFailover")) | .wanFailover) |= (
        (.wanInterfaces[]?) |= (.interface as $iface | del(.interface) | (.interface.id=$iface))
    )'

exit 0
