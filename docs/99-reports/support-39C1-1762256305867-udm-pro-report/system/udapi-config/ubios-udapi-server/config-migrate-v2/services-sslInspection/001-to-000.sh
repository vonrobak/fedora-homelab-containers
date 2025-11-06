#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" 'del(.versionDetail."services/sslInspection")'
JQA "${1}" 'del(.services.sslInspection)'

exit 0
