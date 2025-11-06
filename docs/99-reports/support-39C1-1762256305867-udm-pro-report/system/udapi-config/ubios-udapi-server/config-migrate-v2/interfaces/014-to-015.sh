#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."interfaces"=15'

# Removes tunnels with a duplicate pair of local/remote addresses

z=`jq -n 'foreach (inputs | .interfaces[]?.tunnel | select(.mode == "vti")) as $t ({}; .[($t.localAddress.address)+"-"+($t.remoteAddress.address)]+=1; if .[($t.localAddress.address)+"-"+($t.remoteAddress.address)]==1 then empty else $t.id end)' "${1}"`

for id in $z; do
    JQA "${1}" 'del(.interfaces[]? | select(.tunnel.mode == "vti") | select(.tunnel.id == $id))' "--argjson id ${id}"
done

JQA "${1}" '(.interfaces[]?.tunnel | select(.mode == "vti")) |= (.remoteAddress=.remoteAddress.address)'

exit 0
