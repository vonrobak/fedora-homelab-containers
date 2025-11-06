#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# Replace boolean "log" field value with an object representing
# firewall rule log options. False values are simply removed to
# keep it simple and short.
JQA "${1}" '.versionDetail."firewall/filter"=6 |
    ."firewall/filter"[]?.rules[]? |=
    (if .log == true
     then
        .log = {
          "enabled": true,
          "connectionState": [
            "new"
          ],
          "limit": {
            "rateLimit": "50/s",
            "burstLimit": 100
          }
        }
     else
        del(.log)
     end)'

exit 0
