#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."firewall/nat"=6'

JQA "${1}" '
    def transform_set(set):
        if (set | test("^!?PRIMARY_ADDRv[46]_")) then
            sub("PRIMARY_ADDRv";"key<FILTERED>")
        elif (set | test("^!?PRIMARY_NETv[46]_")) then
            sub("PRIMARY_NETv";"key<FILTERED>")
        else
            .
        end;

."firewall/nat"[]?.destination.sets[]? |= transform_set(.) |
."firewall/nat"[]?.source.sets[]? |= transform_set(.) |
."firewall/mangle"[]?."rules"[]?.destination.sets[]? |= transform_set(.) |
."firewall/mangle"[]?."rules"[]?.source.sets[]? |= transform_set(.) |
."firewall/filter"[]?."rules"[]?.destination.sets[]? |= transform_set(.) |
."firewall/filter"[]?."rules"[]?.source.sets[]? |= transform_set(.)
'

exit 0
