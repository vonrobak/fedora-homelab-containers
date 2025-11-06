#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."services/radius-profiles"=2'

# only updating capabilities to indicate new attributes added

exit 0
