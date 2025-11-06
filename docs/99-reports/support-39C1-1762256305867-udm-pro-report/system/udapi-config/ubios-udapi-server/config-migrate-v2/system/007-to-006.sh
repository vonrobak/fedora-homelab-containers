#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
# update version
# remove hardwareOffload
JQA "${1}" '.versionDetail."system"=6
            |
            del(.system.hardwareOffload)'

exit 0
