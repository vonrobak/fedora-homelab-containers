#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# Bump version
# Remove rules with netmask addresses, iterating over all "firewall/mangle" members
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

    .versionDetail."firewall/mangle" = 6
    |
    if ."firewall/mangle" then
        ."firewall/mangle" |= map(
            if .rules then
                .rules |= map(select(
                    (.source | address_check) and (.destination | address_check)
                ))
            else
                .
            end
        )
    else
        .
    end'

exit 0
