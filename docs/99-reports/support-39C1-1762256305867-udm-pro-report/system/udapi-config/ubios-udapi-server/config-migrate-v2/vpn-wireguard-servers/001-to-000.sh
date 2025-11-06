#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" 'del(.versionDetail."vpn/wireguard/servers")'
JQA "${1}" 'del(."vpn/wireguard/servers")'

exit 0
