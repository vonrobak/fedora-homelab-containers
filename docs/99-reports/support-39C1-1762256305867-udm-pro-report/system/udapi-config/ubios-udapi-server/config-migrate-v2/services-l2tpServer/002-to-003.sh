#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."services/l2tpServer"=3'

# There's a bug in NET when it sometimes provisions invalid `l2tpServer` config
# like this when L2TP is disabled WebUI:
# {
#   "dnsServers": [],
#   "enabled": false,
#   "localAddress": {
#     "source": "wan"
#   },
#   "preSharedkey": "<FILTERED>",
#   "radiusProfileID": "",              <------------------ Empty string
#   "rangeStart": {
#     "address": "0.0.0.0",             <------------------ Wrong address
#     "origin": null,
#     "type": "static",
#     "version": "v4"
#   },
#   "rangeStop": {
#     "address": "0.0.0.0",             <------------------ Wrong address
#     "origin": null,
#     "type": "static",
#     "version": "v4"
#   },
#   "tunnelIP": {
#     "address": "0.0.0.0",             <------------------ Wrong address
#     "origin": null,
#     "type": "static",
#     "version": "v4"
#   }
# }

# This bug was unnoticed until `1.12.15` firmware because `udapi-server` did
# not properly validate contents of "services.l2tpServer", but in `1.12.15` we
# introduced validation that forbids bad `radiusProfileID` from being
# provisioned. To fix this issue we need to completely remove bad `l2tpServer`
# if empty `radiusProfileID` was spotted.
JQA "${1}" 'del(.services?.l2tpServer? | select(.radiusProfileID?==""))'
JQA "${1}" 'del(.services?.l2tpServer? | select(.rangeStop?.address?=="0.0.0.0"))'
JQA "${1}" 'del(.services?.l2tpServer? | select(.rangeStart?.address?=="0.0.0.0"))'
JQA "${1}" 'del(.services?.l2tpServer? | select(.tunnelIP?.address?=="0.0.0.0"))'

exit 0
