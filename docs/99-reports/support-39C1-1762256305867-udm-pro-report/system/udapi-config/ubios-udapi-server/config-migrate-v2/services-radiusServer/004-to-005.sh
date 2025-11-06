#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# only updating capabilities to indicate a new attribute is added
JQA "${1}" '.versionDetail."services/radiusServer"=5'

exit 0
