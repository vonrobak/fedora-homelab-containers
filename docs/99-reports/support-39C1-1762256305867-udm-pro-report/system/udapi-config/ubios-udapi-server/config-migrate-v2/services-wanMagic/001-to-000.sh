#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" 'del(.versionDetail."services/wanMagic")   
            |
            del(.services.wanMagic)'

exit 0
