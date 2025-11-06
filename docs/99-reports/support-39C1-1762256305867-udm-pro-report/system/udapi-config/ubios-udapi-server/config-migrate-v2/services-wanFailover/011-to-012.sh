#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

JQA "${1}" '.versionDetail."services/wanFailover"=12'

exit 0
