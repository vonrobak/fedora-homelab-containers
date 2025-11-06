#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."services/vrrp"=5
            |
            .services.vrrp.instances[]? |= del(.firewallSync)
'
exit 0
