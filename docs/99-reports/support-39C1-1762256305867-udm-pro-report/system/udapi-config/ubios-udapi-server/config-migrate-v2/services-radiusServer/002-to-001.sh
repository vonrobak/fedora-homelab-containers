#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."services/radiusServer"=1'

# only updating capabilities to indicate a bugfix rolled back

exit 0
