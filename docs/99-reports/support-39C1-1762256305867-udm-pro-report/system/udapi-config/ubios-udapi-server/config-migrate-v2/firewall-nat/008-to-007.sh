#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."firewall/nat"=7'

# remove unsupported NETMAP NAT rules with ipsets

JQA "${1}" '
    def has_set($rule):
        ($rule | select(has("source") or has("destination")) | (.source,.destination) | select(has("sets")) | select(.sets | length != 0)) // false;

    del (."firewall/nat"[]? | select(.target == "NETMAP") | select(has_set(.)))
'

exit 0
