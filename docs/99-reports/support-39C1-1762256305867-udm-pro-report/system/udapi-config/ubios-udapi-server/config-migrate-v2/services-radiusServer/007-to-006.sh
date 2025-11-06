#!/bin/sh

. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# update version
JQA "${1}" '.versionDetail."services/radiusServer"=6'

exit 0
