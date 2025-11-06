#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."vpn/wireguard/clients"=2'
# remove .disconnectTimeout
JQA "${1}" 'del(."vpn/wireguard/clients"[]?.remotePeers[]?.disconnectTimeout)'

exit 0
