#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."vpn/openvpn/raws"=5
            |
            ."vpn/openvpn/raws"[]? |= del(.tunnelMTU, .tunnelMSSClamping)
'

exit 0
