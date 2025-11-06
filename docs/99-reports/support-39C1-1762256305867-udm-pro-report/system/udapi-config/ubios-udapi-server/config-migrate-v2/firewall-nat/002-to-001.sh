#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."firewall/nat"=1'

# remove the trigger logging feature
JQA "${1}" '(."firewall/nat"[]? | select(has("triggerTag"))) |= (. | del(.triggerTag))'

exit 0
