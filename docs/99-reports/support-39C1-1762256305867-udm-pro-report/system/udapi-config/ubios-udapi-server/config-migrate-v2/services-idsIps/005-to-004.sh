#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

JQA "${1}" '
    .versionDetail."services/idsIps"=4
    |
    del(.services?.idsIps?.alienLoggingEnabled)
    |
    del(.services?.idsIps?.torLoggingEnabled)
    |
    del(.services?.idsIps?.threatLoggingEnabled)
'

exit 0
