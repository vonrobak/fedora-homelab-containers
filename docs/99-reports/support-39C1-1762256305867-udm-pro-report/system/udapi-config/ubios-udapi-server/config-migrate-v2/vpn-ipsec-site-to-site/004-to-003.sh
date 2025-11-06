#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
# - update version
# - clean an unused array
JQA "${1}" '.versionDetail."vpn/ipsec/site-to-site"=3
            |
            del(."vpn/ipsec/site-to-site"[]?.dnsServers)'
exit 0
