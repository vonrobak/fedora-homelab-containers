#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" 'del(.services.loopProtection)'
JQA "${1}" 'del(.versionDetail."services/loopProtection")'

exit 0
