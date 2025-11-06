#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."vpn/wireguard/clients"=1'
# nothing to do -- a readonly attribute is removed

exit 0
