#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."services/vrrp"=2 | .versionFormat="v2"
           | del(.services?.vrrp?.instances[]?.masterGuard)'

exit 0
