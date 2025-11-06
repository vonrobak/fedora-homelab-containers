#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=31'

JQA "${1}" '
    if .services.ipAccounting.subnets | length > 512 then
        .services.ipAccounting.subnets = .services.ipAccounting.subnets[0:512]
    else . end
    |
    if .services.ipAccounting.ignoredIPs | length > 512 then
        .services.ipAccounting.ignoredIPs = .services.ipAccounting.ignoredIPs[0:512]
    else . end
    '

exit 0
