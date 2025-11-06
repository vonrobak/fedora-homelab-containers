#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."vpn/ipsec/site-to-site"=2'
# nothing to do -- a readonly attribute is removed

exit 0
