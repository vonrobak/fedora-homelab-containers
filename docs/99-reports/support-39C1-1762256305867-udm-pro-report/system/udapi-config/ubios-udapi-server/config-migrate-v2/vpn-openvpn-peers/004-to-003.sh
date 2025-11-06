#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."vpn/openvpn/peers"=3'

# remove .strictClientCredentials, don't try to restore .strictClientCommonName
JQA "${1}" 'del(."vpn/openvpn/peers"[]?.authentication[]?.strictClientCredentials)'

exit 0
