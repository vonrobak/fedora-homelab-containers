#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '
    .versionDetail."services/messageBroker"=1
    |
    del(.services.messageBroker.flowConfiguration)
'

exit 0
