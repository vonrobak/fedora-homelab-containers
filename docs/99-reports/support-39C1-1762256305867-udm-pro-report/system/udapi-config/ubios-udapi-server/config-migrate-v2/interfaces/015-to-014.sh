#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."interfaces"=14'

# 1. Remove vti tunnels with fqdn.
JQA "${1}" 'del(.interfaces[]? | select(.tunnel.mode == "vti") | select(.tunnel.remoteAddress|match("[A-Za-z]")))'

# 2. Convert all Host to SimpleAddress
JQA "${1}" '
    def get_version(ip):
        if (ip | contains(":")) then
            "v6"
        else
            "v4"
        end;

    def convert_to_simple(ip):
        {"address": ip, "version": get_version(ip), "origin": null, "type":"static"};

    (.interfaces[]? | select(has("tunnel")) | select(.tunnel.mode == "vti") | .tunnel.remoteAddress) |= convert_to_simple(.)
'

exit 0
