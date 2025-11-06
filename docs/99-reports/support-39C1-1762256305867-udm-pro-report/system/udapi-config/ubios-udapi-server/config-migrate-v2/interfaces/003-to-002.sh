#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."interfaces"=2'

# remove status.baseReachableTime
JQA "${1}" 'del(.interfaces[]?.status.baseReachableTime)'

exit 0
