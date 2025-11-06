#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."vpn/wireguard/clients"=4
            |
            del(."vpn/wireguard/clients"[]?.tunnelMSSClamping)
'

exit 0
