#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."vpn/wireguard/servers"=4
            |
            ."vpn/wireguard/servers"[]? |= del(.disableWan, .disableClientEvents)
'

exit 0
