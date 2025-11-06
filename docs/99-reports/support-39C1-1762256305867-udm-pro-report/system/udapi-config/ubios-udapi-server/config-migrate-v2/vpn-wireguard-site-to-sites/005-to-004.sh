#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."vpn/wireguard/site-to-sites"=4
            |
            del(."vpn/wireguard/site-to-sites"[]?.tunnelMSSClamping)
'

exit 0
