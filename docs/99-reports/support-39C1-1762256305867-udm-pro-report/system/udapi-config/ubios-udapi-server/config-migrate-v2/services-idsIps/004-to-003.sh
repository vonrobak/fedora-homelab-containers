#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

JQA "${1}" '.versionDetail."services/idsIps"=3 | del(.services.idsIps.sslInspectionEnabled)'

exit 0
