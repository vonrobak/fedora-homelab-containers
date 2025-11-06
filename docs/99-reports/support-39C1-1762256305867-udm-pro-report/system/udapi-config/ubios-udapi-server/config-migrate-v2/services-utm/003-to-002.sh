#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '
    .versionDetail."services/utm"=2
    |
    del(.services?.utm?.contentFilteringLoggingEnabled)
    |
    del(.services?.utm?.adBlockingLoggingEnabled)
'

exit 0
