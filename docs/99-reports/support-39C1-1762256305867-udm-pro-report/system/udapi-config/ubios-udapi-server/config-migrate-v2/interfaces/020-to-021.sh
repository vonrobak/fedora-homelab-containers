#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."interfaces"=21'

# 1. Convert SimpleAddress to AddressSelector
JQA "${1}" '
    def convert_to_selector(localAddress):
        {"address": localAddress.address, "source":"static"};

    (.interfaces[]? | select(has("tunnel")) | select(.tunnel.mode == "vti") | .tunnel.localAddress) |= convert_to_selector(.)
'

exit 0
