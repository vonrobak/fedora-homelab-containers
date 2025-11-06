#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."vpn/openvpn/peers"=4'

# add default and most strict .strictClientCredentials if .strictClientCommonName is true
JQA "${1}" '
    (."vpn/openvpn/peers"[]?.authentication[]? | select(.method=="tls"))
     |= (if (.strictClientCommonName==true) then .strictClientCredentials={} else . end
         | del(.strictClientCommonName))
'

exit 0
