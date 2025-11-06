#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" 'del(.versionDetail."services/vrrp")'
JQA "${1}" 'del(.services.vrrp)'

exit 0
