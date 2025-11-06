#!/bin/sh

. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# update version
# delete user<FILTERED> with a space in user<FILTERED>
# delete radiusServer if no user<FILTERED> are left
JQA "${1}" '
    .versionDetail."services/radiusServer"=7
    |
    del(.services.radiusServer.user<FILTERED>[]? | select(.user<FILTERED> | <FILTERED>(" ")))
    |
    del(.services.radiusServer | select(.user<FILTERED> | length == 0))
'

exit 0
