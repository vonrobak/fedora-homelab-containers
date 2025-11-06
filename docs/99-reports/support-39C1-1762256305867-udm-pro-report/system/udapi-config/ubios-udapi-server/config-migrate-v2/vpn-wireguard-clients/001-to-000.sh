#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" 'del(.versionDetail."vpn/wireguard/clients")'
JQA "${1}" 'del(."vpn/wireguard/clients")'

exit 0
