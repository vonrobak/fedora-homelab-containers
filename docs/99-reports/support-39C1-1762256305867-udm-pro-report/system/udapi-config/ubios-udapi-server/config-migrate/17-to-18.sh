#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=18'

# config format has changed for services/wanFailover


# To avoid increased data usage on LTE, default the monitoring interval to 300 on
# "gre" interface, if it is undefined. (in that case, overwrite the linked timePeriod too)
JQA "${1}" '.services.wanFailover?.wanInterfaces[] 
    |= if ((.interface.id == "gre") and (.monitor | has("interval") | not)) 
       then . |= (.monitor.interval = 300) | (.monitor.timePeriod = 3600)
       else . end'

# Convert "monitor" element to new format and into "monitors" array.
JQA "${1}" '.services.wanFailover?.wanInterfaces[]
    |= (.monitors = [.monitor
                     + {"alert": { "latencyThreshold": (.monitor.latencyThreshold // 1500),
                                   "lossThreshold":    (.monitor.lossThreshold    // 20) }}
                     | del(.latencyThreshold,
                           .lossThreshold)]
        | del(.monitor))'

exit 0
