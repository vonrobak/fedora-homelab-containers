#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=11'

# OpenVPN can accept interface names now
# - rename 'tunnel.localPeer.address' property to 'tunnel.localPeer.interface'
JQA "${1}" '(."vpn/openvpn/peers"[]?.tunnel.localPeer | select(has("address"))) |= (.interface=.address | del(.address))'

exit 0
