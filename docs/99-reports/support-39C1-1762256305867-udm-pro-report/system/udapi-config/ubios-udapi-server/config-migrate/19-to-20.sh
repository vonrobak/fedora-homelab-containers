#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=20'
# default .routePull to true if .routeNoPull was not set
JQA "${1}" '(."vpn/openvpn/peers"[]? | select(has("routeNoPull") | not)) |= (.routePull=true)'
# invert routeNoPull to routePull
JQA "${1}" '(."vpn/openvpn/peers"[]? | select(has("routeNoPull"))) |= ((.routePull=(.routeNoPull | not)) | del(.routeNoPull))'
# update authentication .sharedkey<FILTERED> to .key<FILTERED>
JQA "${1}" '(."vpn/openvpn/peers"[]?.authentication) |= ((.key<FILTERED>=.sharedkey<FILTERED>) | del(.sharedKey))'
# refactor authentication to array
JQA "${1}" '(."vpn/openvpn/peers"[]?) |= (.authentication=[.authentication])'
exit 0
