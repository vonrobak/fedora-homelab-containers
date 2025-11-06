#!/bin/sh

. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# update version
# delete radSec sertificates
JQA "${1}" '
    .versionDetail."services/radiusServer"=7
    |
    del(.services?.radiusServer?.radSec)
'

exit 0
