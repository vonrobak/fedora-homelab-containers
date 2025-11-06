#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."services/l2tpServer"=2'
# nothing to do -- a new readonly attribute is added

exit 0
