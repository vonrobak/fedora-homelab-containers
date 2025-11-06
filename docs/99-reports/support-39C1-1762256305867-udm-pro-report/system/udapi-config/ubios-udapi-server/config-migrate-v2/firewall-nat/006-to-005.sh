#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."firewall/nat"=5'

JQA "${1}" '
    def transform_primary_set(set):
        if (set | test("^!?key<FILTERED>[46]_")) then
            sub("key<FILTERED>";"PRIMARY_ADDRv")
        elif (set | test("^!?key<FILTERED>[46]_")) then
            sub("key<FILTERED>";"PRIMARY_NETv")
        else
            .
        end;

."firewall/nat"[]?.destination.sets[]? |= transform_primary_set(.) |
."firewall/nat"[]?.source.sets[]? |= transform_primary_set(.) |
."firewall/mangle"[]?."rules"[]?.destination.sets[]? |= transform_primary_set(.) |
."firewall/mangle"[]?."rules"[]?.source.sets[]? |= transform_primary_set(.) |
."firewall/filter"[]?."rules"[]?.destination.sets[]? |= transform_primary_set(.) |
."firewall/filter"[]?."rules"[]?.source.sets[]? |= transform_primary_set(.)
'

exit 0
