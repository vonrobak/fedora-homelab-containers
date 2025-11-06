#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

JQA "${1}" '.versionDetail."services/wanFailover"=11 |
    (.services?.wanFailover?.wanInterfaces[]?.monitors[]?.alert?) |= del(.thresholdPolicy)
'

exit 0
