#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."vpn/ipsec/site-to-site"=1'

exit 0
