#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=26'

# Convert tproxyMark from integer to boolean

JQA "${1}" '(."firewall/mangle"[]? | .rules[]?) |= (if .tproxyMark == 1 then .tproxyMark = true else del(.tproxyMark) end)'

exit 0
