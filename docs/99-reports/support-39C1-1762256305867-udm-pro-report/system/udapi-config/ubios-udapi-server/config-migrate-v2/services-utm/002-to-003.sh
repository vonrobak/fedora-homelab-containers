#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '
    .versionDetail."services/utm"=3
    |
    .services.utm.contentFilteringLoggingEnabled |= false
    |
    .services.utm.adBlockingLoggingEnabled |= false
'

exit 0
