#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."vpn/wireguard/clients"=5
            |
            ."vpn/wireguard/clients"[]? |= del(.disableWan, .disableClientEvents)
'

exit 0
