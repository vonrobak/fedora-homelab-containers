#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

JQA "${1}" 'del(.versionDetail."services/flowAccounting") | del(.services.flowAccounting)'

exit 0
