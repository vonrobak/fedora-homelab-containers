#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" 'del(.versionDetail."vpn/ipsec")'
JQA "${1}" 'del(."vpn/ipsec")'

exit 0
