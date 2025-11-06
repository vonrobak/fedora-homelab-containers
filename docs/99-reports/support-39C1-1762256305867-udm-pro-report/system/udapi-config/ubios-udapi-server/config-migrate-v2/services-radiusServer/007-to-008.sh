#!/bin/sh

. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# update version
JQA "${1}" '.versionDetail."services/radiusServer"=8'

exit 0
