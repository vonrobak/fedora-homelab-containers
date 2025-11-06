#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=7'

# Support multiple sets in firewall rule source/destination.
# Move single set (if present) => sets array with single element.
JQA "${1}" '(."firewall/filter"[].rules[] | select(has("source") or has("destination")) | (.source,.destination) | select(has("set"))) |= (. | . + {sets: [.set]} | del(.set))'

exit 0

