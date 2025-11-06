#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."vpn/wireguard/site-to-sites"=5
            |
            ."vpn/wireguard/site-to-sites"[]? |= del(.disableWan, .disableClientEvents)
'

exit 0
