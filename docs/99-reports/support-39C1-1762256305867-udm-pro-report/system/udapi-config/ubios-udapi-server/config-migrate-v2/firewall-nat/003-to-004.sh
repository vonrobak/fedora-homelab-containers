#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."firewall/nat"=4'

JQA "${1}" '
    def transform_set(set):
        if (set | test("^!?ADDRv[46]_")) then
            sub("ADDRv";"PRIMARY_ADDRv")
        elif (set | test("^!?NETv[46]_")) then
            sub("NETv";"ALL_NETv")
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
