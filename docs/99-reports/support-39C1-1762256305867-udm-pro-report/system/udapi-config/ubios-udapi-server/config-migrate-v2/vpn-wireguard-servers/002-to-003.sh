#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."vpn/wireguard/servers"=3'
# nothing to do -- a new .disconnectTimeout attribute is added

exit 0
