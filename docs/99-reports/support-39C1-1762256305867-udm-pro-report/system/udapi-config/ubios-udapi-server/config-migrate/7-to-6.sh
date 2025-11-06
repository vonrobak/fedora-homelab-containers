#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=6'

# Downgrading to version that only supports a single set in firewall
# rule source/destination. Retain first set in sets, if present. All
# others get thrown away!
JQA "${1}" '(."firewall/filter"[].rules[] | select(has("source") or has("destination")) | (.source,.destination) | select(has("sets"))) |= (. | if (.sets | length) > 0 then . + {set: .sets[0]} else . end | del(.sets))'
exit 0
