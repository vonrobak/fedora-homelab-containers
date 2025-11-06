#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."services/radiusServer"=2'

# only updating capabilities to indicate a bugfix implemented

exit 0
