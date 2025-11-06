#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."interfaces"=20'

# 1. Remove vti tunnels with interface source
JQA "${1}" 'del(.interfaces[]? | select(.tunnel.mode == "vti") | select(.tunnel.localAddress.source == "interface"))'

# 2. Convert AddressSelector to SimpleAddress
JQA "${1}" '
    def get_version(ip):
        if (ip | contains(":")) then
            "v6"
        else
            "v4"
        end;

    def convert_to_simple(selector):
        {"address": selector.address, "version": get_version(selector.address), "origin": null, "type":"static"};

    (.interfaces[]? | select(has("tunnel")) | select(.tunnel.mode == "vti") | .tunnel.localAddress) |= convert_to_simple(.)
'

exit 0
