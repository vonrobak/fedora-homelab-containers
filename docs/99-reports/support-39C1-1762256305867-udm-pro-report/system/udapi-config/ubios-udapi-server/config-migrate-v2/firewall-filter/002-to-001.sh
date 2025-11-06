#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."firewall/filter"=1'

# remove the trigger logging feature
JQA "${1}" '(."firewall/filter"[].rules[]? | select(has("triggerTag"))) |= (. | del(.triggerTag))'

exit 0
