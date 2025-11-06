#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."system"=1'

# remove fwReleaseChannel
JQA "${1}" 'del(.system.fwReleaseChannel)'

exit 0
