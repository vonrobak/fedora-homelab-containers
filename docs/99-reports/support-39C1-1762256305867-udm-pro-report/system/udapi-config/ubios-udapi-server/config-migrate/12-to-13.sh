#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=13'

# add ipVersion to rules with icmpType, icmpv6Type and source/destination/translation address

JQA "${1}" '(."firewall/filter"[]?.rules[]? | select(has("icmpType"))) |= (.ipVersion="v4only")'
JQA "${1}" '(."firewall/filter"[]?.rules[]? | select(has("icmpv6Type"))) |= (.ipVersion="v6only")'

JQA "${1}" '
    def set_ver(addr):
        if (addr | contains(":")) then
            (.ipVersion="v6only")
        else
            (.ipVersion="v4only")
        end;

    def update_rules(rules):
        rules |=
            if .source.address then
                set_ver(.source.address)
            elif .destination.address then
                set_ver(.destination.address)
            elif .translation.address then
                set_ver(.translation.address)
            else
                .
            end;

    update_rules(."firewall/filter"[]?.rules[]?) |
    update_rules(."firewall/nat"[]?)'

exit 0
