#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" 'del(.versionDetail."vpn/openvpn/peers")'

exit 0
