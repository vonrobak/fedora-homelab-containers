#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts

# .services.dnsForwarder.strictOrder has been moved to forwardBehavior
JQA "${1}" '.version=22'
JQA "${1}" 'if .services.dnsForwarder.strictOrder == true then .services.dnsForwarder.forwardBehavior = "strictOrder" else . end | del(.services.dnsForwarder.strictOrder)'

exit 0
