#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=10'

# Due to downgrade OpenVPN can accept only clear IPv4 address instead of
# interface. We need to rename 'tunnel.localPeer.interface' property to
# 'tunnel.localPeer.address'. But there is no regex support in our JQ to do it
# properly -- we cannot distinguish IP or Iface. So we are simply ignoring
# '.interface' property. VPN should start working on "any" interface.
# JQA "${1}" '(."vpn/openvpn/peers"[]?.tunnel.localPeer | select(has("interface"))) |= ((if (.interface|test("([0-9]+)\\.([0-9]+)\\.([0-9]+)\\.([0-9]+)")) then (.address=.interface) else . end) | del(.interface))'
