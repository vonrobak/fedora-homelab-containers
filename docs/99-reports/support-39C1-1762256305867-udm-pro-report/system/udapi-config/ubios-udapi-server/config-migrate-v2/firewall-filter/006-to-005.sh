#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# Replace "log" object value with a boolean literal.
# Disabled/missing ".log?.enabled" are simply removed to
# keep it simple and short.
JQA "${1}" '.versionDetail."firewall/filter"=5 |
    ."firewall/filter"[]?.rules[]? |=
    (if .log.enabled == true
     then .log = true
     else del(.log)
     end)'

exit 0
