#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# - update feature version
# - Restore default latencyThreshold and lossThreshold values
# - remove jitterThreshold alert if wanFailover service exists
JQA "${1}" '.versionDetail."services/wanFailover"=6 |
    (. | select(has("services")) | .services | select(has("wanFailover")) | .wanFailover) |= (
        (.wanInterfaces[]?.monitors[]? | select(has("alert")) | .alert |
            select(has("latencyThreshold") | not)) |= (.latencyThreshold=1500) |
        (.wanInterfaces[]?.monitors[]? | select(has("alert")) | .alert |
            select(has("lossThreshold") | not)) |= (.lossThreshold=20) |
        del(.wanInterfaces[]?.monitors[]?.alert?.jitterThreshold)
    )
'

exit 0
