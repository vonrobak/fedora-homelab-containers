#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

JQA "${1}" '.versionDetail."services/flowAccounting"=2 | .versionFormat="v2"'

exit 0
