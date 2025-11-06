#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."vpn/wireguard/clients"=3'

# Change interface source to default
JQA "${1}" 'del(."vpn/wireguard/clients"[]?.address)'

exit 0
