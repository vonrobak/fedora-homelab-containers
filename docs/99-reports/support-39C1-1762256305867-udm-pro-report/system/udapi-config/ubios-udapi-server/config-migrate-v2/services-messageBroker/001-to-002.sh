#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

JQA "${1}" '
    .versionDetail."services/messageBroker"=2
    |
    if .services.messageBroker then .services.messageBroker += { "flowConfiguration": { "eventState": ["ipsIds", "honeypot", "contentFiltering", "adBlocking", "regionBlocking", "trigger"] } } else . end
'

exit 0
