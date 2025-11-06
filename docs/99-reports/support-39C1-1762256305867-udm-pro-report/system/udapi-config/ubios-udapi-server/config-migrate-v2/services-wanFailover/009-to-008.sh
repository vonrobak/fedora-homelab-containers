#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# - update feature version
# - remove services?.wanFailover?.wanInterfaces[]?.monitors[]?.bindDomainResolution property, if it exists
JQA "${1}" '
    .versionDetail."services/wanFailover"=8 |
    del(.services?.wanFailover?.wanInterfaces[]?.monitors[]?.bindDomainResolution)
'

exit 0
