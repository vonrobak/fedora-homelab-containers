#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# Bump version
# Remove rules with netmask addresses, iterating over all "firewall/nat" members
JQA "${1}" '
    def address_check:
        if .address then
            (
                (.address | contains("/") | not) or
                (.address | split("/") | length == 2 and (.[1] | test("^[0-9]+$")))
            )
        else
            true
        end;
    
    .versionDetail."firewall/nat" = 9
    |
    if ."firewall/nat" then
        ."firewall/nat" |= map(select(
            (.source | address_check) and (.destination | address_check)
        ))
    else
        .
    end'

exit 0
