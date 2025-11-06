#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."firewall/mangle"=2'

# remove the trigger logging feature
JQA "${1}" 'del(."firewall/mangle"[]?."rules"[]? | select(has("categoryId")))'

exit 0
