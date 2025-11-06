#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=19'
# delete peers, that cannot be handled
JQA "${1}" 'del(."vpn/openvpn/peers"[] | select(.mode != "peer"))'
JQA "${1}" 'del(."vpn/openvpn/peers"[] | select((.authentication | length) != 1))'
JQA "${1}" 'del(."vpn/openvpn/peers"[] | select(.authentication[0].method != "sharedKey"))'
# default .routeNoPull to true if .routePull was not set
JQA "${1}" '(."vpn/openvpn/peers"[]? | select(has("routePull") | not)) |= (.routeNoPull=true)'
# invert routePull to routeNoPull
JQA "${1}" '(."vpn/openvpn/peers"[]? | select(has("routePull"))) |= ((.routeNoPull=(.routePull | not)) | del(.routePull))'
# refactor authentication to object from array
JQA "${1}" '(."vpn/openvpn/peers"[]?) |= (.authentication=.authentication[0])'
# update authentication .key<FILTERED> to .sharedkey<FILTERED>
JQA "${1}" '(."vpn/openvpn/peers"[]?.authentication) |= ((.sharedkey<FILTERED>=.key<FILTERED>) | del(.key<FILTERED>))'
exit 0
