#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."vpn/ipsec/site-to-site"=4'
# nothing to do -- an issue is fixed and version bumped for capability flag

exit 0
