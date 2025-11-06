#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# remove unused attribute
JQA "${1}" '.versionDetail."services/radiusServer"=4 |
            del(.services?.radiusServer?.user<FILTERED>[]?.tunnelPassword)'

exit 0
