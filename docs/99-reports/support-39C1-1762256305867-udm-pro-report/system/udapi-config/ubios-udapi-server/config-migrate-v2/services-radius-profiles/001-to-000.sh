#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" 'del(.versionDetail."services/radius-profiles")'

exit 0
