#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '
    .versionDetail."services/messageBroker"=2
    |
    (.services?.messageBroker?.flowConfiguration? | select(has("eventState"))) |= (
        .eventState -= ["dnsQueries"]
    )
'

exit 0
