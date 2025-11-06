#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."vpn/openvpn/raws"=4'
# nothing to do -- a capability to reveal fixed bug to NET

exit 0
