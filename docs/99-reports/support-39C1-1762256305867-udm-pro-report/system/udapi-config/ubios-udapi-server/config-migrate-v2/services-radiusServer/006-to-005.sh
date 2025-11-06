#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# remove unused attribute
JQA "${1}" '.versionDetail."services/radiusServer"=5'
exit 0
