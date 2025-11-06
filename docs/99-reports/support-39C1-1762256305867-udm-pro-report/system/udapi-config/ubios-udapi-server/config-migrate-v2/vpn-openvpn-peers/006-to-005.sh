#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."vpn/openvpn/peers"=5
            |
            ."vpn/openvpn/peers"[]?.tunnel? |= del(.tunnelMTU, .tunnelMSSClamping)
'

exit 0
