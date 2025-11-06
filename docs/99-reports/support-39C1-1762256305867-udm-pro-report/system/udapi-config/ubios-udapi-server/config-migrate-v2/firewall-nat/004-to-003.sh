#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."firewall/nat"=3'

JQA "${1}" '
    def transform_primary_set(set):
        if (set | test("^!?PRIMARY_ADDRv[46]_")) then
            sub("PRIMARY_ADDRv";"ADDRv")
        elif (set | test("^!?PRIMARY_NETv[46]_")) then
            sub("PRIMARY_NETv";"NETv")
        else
            .
        end;

    def transform_all_set(set):
        if (set | test("^!?ALL_ADDRv[46]_")) then
            sub("ALL_ADDRv";"ADDRv")
        elif (set | test("^!?ALL_NETv[46]_")) then
            sub("ALL_NETv";"NETv")
        else
            .
        end;

."firewall/nat"[]?.destination.sets[]? |= transform_primary_set(.) |
."firewall/nat"[]?.source.sets[]? |= transform_primary_set(.) |
."firewall/mangle"[]?."rules"[]?.destination.sets[]? |= transform_primary_set(.) |
."firewall/mangle"[]?."rules"[]?.source.sets[]? |= transform_primary_set(.) |
."firewall/filter"[]?."rules"[]?.destination.sets[]? |= transform_primary_set(.) |
."firewall/filter"[]?."rules"[]?.source.sets[]? |= transform_primary_set(.) |
."firewall/nat"[]?.destination.sets[]? |= transform_all_set(.) |
."firewall/nat"[]?.source.sets[]? |= transform_all_set(.) |
."firewall/mangle"[]?."rules"[]?.destination.sets[]? |= transform_all_set(.) |
."firewall/mangle"[]?."rules"[]?.source.sets[]? |= transform_all_set(.) |
."firewall/filter"[]?."rules"[]?.destination.sets[]? |= transform_all_set(.) |
."firewall/filter"[]?."rules"[]?.source.sets[]? |= transform_all_set(.)
'

exit 0
