#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=25'

# When firewall/filter or firewall/mangle chain has rules with duplicate IDs, remove all IDs from the chain.
# When firewall/nat has duplicate IDs, remove all IDs from the NAT.

JQA "${1}" '
def has_dupl_ids:
    ([.[]?.id] | length) > ([.[]?.id] | unique | length);
def dedup:
    if (.|has_dupl_ids) then del(.[]?.id) else . end;
."firewall/filter"[]?.rules |= (. | dedup)
|
."firewall/nat" |= (. | dedup)
|
."firewall/mangle"[]?.rules |= (. | dedup)'

exit 0
