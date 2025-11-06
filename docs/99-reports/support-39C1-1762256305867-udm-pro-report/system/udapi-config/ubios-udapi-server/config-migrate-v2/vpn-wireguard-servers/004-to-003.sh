#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."vpn/wireguard/servers"=3
            |
            del(."vpn/wireguard/servers"[]?.tunnelMSSClamping)
'

exit 0
