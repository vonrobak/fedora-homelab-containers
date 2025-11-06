#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."services/radiusServer"=4'

# only updating capabilities to indicate new attributes added

exit 0
