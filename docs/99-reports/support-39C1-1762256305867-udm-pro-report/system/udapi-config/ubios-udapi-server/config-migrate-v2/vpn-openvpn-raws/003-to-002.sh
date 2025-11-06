#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."vpn/openvpn/raws"=2'
# nothing to do -- a readonly attribute is removed

exit 0
