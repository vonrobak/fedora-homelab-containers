#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."interfaces"=9'

# Removing:
# * duplicate IPv4 addresses;
# * duplicate IPv6 addresses disregarding their subnet, only address part is considered.
JQA "${1}" '
    def addr_key:
        if .version == "v6" then
            (.cidr // "") | split("/")[0]
        else
            .cidr
        end;
    def criterion:
        (.version // "")
        + (addr_key <FILTERED> ((.origin // "") + ( .type // "")));
    def make_index:
        [ index(unique_by(criterion)[]) ] | sort;
    (.interfaces[]? | select(has("addresses"))).addresses |= [ .[make_index[]] ]'

exit 0
