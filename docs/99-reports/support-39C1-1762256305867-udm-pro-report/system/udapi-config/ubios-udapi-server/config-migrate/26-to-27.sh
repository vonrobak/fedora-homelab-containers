#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=27'

# Convert tproxyMark from boolean to integer (remove it if false)

JQA "${1}" '(."firewall/mangle"[]? | .rules[]?) |= (if .tproxyMark == true then .tproxyMark = 1 else del(.tproxyMark) end)'

exit 0
