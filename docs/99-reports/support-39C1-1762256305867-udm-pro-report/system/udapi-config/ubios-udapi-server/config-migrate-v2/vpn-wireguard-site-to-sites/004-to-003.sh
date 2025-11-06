#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."vpn/wireguard/site-to-sites"=3'
# remove .disconnectTimeout
JQA "${1}" 'del(."vpn/wireguard/site-to-sites"[]?.remotePeers[]?.disconnectTimeout)'

exit 0
