#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" 'del(.versionDetail."vpn/wireguard/site-to-sites")'
JQA "${1}" 'del(."vpn/wireguard/site-to-sites")'

exit 0
