#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."vpn/wireguard/servers"=2'
# remove .disconnectTimeout
JQA "${1}" 'del(."vpn/wireguard/servers"[]?.remotePeers[]?.disconnectTimeout)'

exit 0
