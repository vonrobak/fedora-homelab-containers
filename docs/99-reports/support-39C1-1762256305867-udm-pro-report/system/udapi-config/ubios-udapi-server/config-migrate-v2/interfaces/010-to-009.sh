#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."interfaces"=9'

JQA "${1}" '(.interfaces[]? | select(has("pppoe"))) |= (
    if (.ipv4 and .ipv4.mssClamping and .ipv4.mssClamping.mssClampSize) then
        .pppoe.mssClampSize=.ipv4.mssClamping.mssClampSize |
        .pppoe.mssClamping=true
    else
        .pppoe.mssClampSize=1452 |
        .pppoe.mssClamping=false
    end |
    del(.ipv4.mssClamping) |
    del(.ipv6.mss6Clamping)
)'

exit 0
