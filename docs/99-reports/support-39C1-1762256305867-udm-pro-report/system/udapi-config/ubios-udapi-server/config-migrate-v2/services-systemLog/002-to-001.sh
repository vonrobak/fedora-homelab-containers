#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."services/systemLog"=1 | del(.services?.systemLog?.encryption)'

exit 0
