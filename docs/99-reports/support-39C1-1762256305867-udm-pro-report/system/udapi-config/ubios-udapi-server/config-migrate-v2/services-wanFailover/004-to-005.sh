#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."services/wanFailover"=5'

# force a value for connectionResetTriggers in each group
JQA "${1}" '
    (. | select(has("services")) | .services | select(has("wanFailover")) | .wanFailover) |= (
        .failoverGroups[]? |= (
            .connectionResetTriggers = [ "onActivation", "onConfiguration", "onWanHealthBad" ]
        )
    )
'

exit 0
