#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts

# .services.dnsForwarder.forwardBehavior moved back to strictOrder
JQA "${1}" '.version=21'
JQA "${1}" 'if .services.dnsForwarder.forwardBehavior == "strictOrder" then .services.dnsForwarder.strictOrder = true else . end'
JQA "${1}" 'del(.services.dnsForwarder.forwardBehavior)'

exit 0
