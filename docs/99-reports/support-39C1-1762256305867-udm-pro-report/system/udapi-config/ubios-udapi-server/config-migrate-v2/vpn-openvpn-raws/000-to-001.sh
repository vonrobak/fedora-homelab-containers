#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."vpn/openvpn/raws"=1 | .versionFormat="v2"'

exit 0
