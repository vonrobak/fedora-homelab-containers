#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."vpn/wireguard/site-to-sites"=1 | .versionFormat="v2"'

exit 0
