#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# service disabled in compile time
JQA "${1}" '.versionDetail."services/discoveryResponder"=2 |
            del(.services.discoveryResponder)'

exit 0
