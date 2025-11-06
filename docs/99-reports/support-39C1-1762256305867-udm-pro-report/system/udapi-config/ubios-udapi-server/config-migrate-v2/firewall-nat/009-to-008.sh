#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# - bump version
# - remove unsupported multiport SNAT rules

JQA "${1}" '
    def has_multiport($rule):
        ($rule | select(has("translation")) | .translation | select(has("port")) | .port | contains(",")) // false;

    .versionDetail."firewall/nat"=8
    |
    del (."firewall/nat"[]? | select(.target == "SNAT") | select(has_multiport(.)))
'

exit 0
