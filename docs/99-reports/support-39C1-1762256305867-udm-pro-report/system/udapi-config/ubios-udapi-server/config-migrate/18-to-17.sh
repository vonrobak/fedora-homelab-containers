#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=17'

# Remove interfaces without alerting monitors.
JQA "${1}" '.services.wanFailover?.wanInterfaces 
            |= [.[] | select(has("monitors") and (.monitors[] | has("alert")))  ]'

# WanFailover service format changed. Keep only single, alerting monitor.
JQA "${1}" '.services.wanFailover?.wanInterfaces[]
            |= ((.monitor = ((.monitors[] | select(has("alert")) + .alert)
                             | del(.alert)))
                | del(.monitors))'

exit 0
