#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

JQA "${1}" '.versionDetail."services/flowAccounting"=1 |
       del(.services.flowAccounting?.instances[]?.sampler)'

exit 0
